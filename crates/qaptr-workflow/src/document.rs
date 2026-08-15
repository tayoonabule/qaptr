//! The canonical Workflow document and its construction API.

mod components;
mod errors;

pub use components::{
    Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, Provenance, ToolObserved,
    WorkflowStep, WorkflowVariation,
};
pub use errors::{Result, WorkflowError};

use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId, WorkflowId};
use qaptr_provider::NormalizedWorkflow;
use qaptr_store::{ObservationRecord, UnixMillis, WorkflowRecord};
use serde_json::{Value, json};

use components::{optional_text, required_text};

/// The canonical Workflow document shared by all four exports.
///
/// A document contains only observed or explicitly supplied material. An empty
/// sequence is valid and means that no procedure was captured, not that a
/// renderer may infer one.
#[derive(Clone, Debug, PartialEq)]
pub struct WorkflowDocument {
    /// Stable Workflow identifier.
    pub id: WorkflowId,
    /// Human-readable Workflow title.
    pub title: String,
    /// Observed goal, if available.
    pub goal: Option<String>,
    /// Observed context, if available.
    pub context: Option<String>,
    /// Inputs observed for the Workflow.
    pub inputs: Vec<Artifact>,
    /// Outputs observed for the Workflow.
    pub outputs: Vec<Artifact>,
    /// Tools observed while performing the Workflow.
    pub tools: Vec<ToolObserved>,
    /// Ordered observed steps.
    pub steps: Vec<WorkflowStep>,
    /// Observed decision points.
    pub decision_points: Vec<DecisionPoint>,
    /// Known variations from the primary path.
    pub variations: Vec<WorkflowVariation>,
    /// Overall evidence confidence.
    pub confidence: ConfidenceAssessment,
    /// Source records supporting the document as a whole.
    pub provenance: Provenance,
}

/// Concise alias for the canonical Workflow document.
pub type Workflow = WorkflowDocument;

impl WorkflowDocument {
    /// Starts a document builder with a stable identifier and title.
    pub fn builder(id: WorkflowId, title: impl Into<String>) -> WorkflowBuilder {
        WorkflowBuilder {
            id,
            title: title.into(),
            goal: None,
            context: None,
            inputs: Vec::new(),
            outputs: Vec::new(),
            tools: Vec::new(),
            steps: Vec::new(),
            decision_points: Vec::new(),
            variations: Vec::new(),
            confidence: ConfidenceAssessment::unknown(),
            provenance: Provenance::empty(),
        }
    }

    /// Builds a canonical document from one durable observation.
    ///
    /// An observation is evidence, not a complete procedure. Its summary is
    /// retained as context, while the sequence, tools, decisions, and outputs
    /// remain empty until they are actually observed or explicitly supplied.
    pub fn from_observation(observation: &ObservationRecord) -> Result<Self> {
        let provenance = Provenance {
            session_id: Some(observation.session_id.clone()),
            observation_ids: vec![observation.id.clone()],
            capture_ids: observation.capture_id.clone().into_iter().collect(),
            note: Some("Generated from one durable observation; missing procedure detail was not inferred.".to_owned()),
        };
        Self::builder(
            WorkflowId::new(format!("u19/observation/{}", observation.id))?,
            observation.title.clone(),
        )
        .context(observation.summary.clone())
        .confidence(
            ConfidenceAssessment::scored(observation.confidence)
                .with_basis("Inherited from the selected observation without calibration"),
        )
        .provenance(provenance)
        .build()
    }

    /// Builds a canonical document from a provider's scalar workflow candidate.
    ///
    /// Candidate workflows contain only a title and goal today. The stable
    /// session/index identifier lets a resumed analysis replace the same
    /// durable row, and the empty sequence makes the missing detail visible in
    /// every renderer instead of turning a suggestion into an invented recipe.
    pub fn from_candidate(
        session_id: &SessionId,
        candidate: &NormalizedWorkflow,
        candidate_index: usize,
        evidence: ConfidenceAssessment,
        capture_id: Option<CaptureId>,
    ) -> Result<Self> {
        let provenance = Provenance {
            session_id: Some(session_id.clone()),
            observation_ids: Vec::new(),
            capture_ids: capture_id.into_iter().collect(),
            note: Some(
                "Generated from a provider candidate; sequence and details were not captured."
                    .to_owned(),
            ),
        };
        Self::builder(
            WorkflowId::new(format!("u19/{session_id}/candidate-{candidate_index}"))?,
            candidate.title().to_owned(),
        )
        .goal(candidate.goal().to_owned())
        .confidence(evidence)
        .provenance(provenance)
        .build()
    }

    /// Converts this document to the scalar record used by `qaptr-store`.
    ///
    /// Structured fields are encoded as deterministic, versioned JSON text in
    /// the existing `sequence` scalar column. The store still sees only
    /// validated text, and no capture bytes, thumbnails, or privacy payloads
    /// can cross this API.
    pub fn to_record(&self, created_at: UnixMillis) -> Result<WorkflowRecord> {
        let session_id = self
            .provenance
            .session_id
            .clone()
            .ok_or(WorkflowError::MissingSession)?;
        let tools = self
            .tools
            .iter()
            .map(|tool| {
                json!({
                    "name": tool.name,
                    "purpose": tool.purpose,
                    "observed_usage": tool.observed_usage,
                })
            })
            .collect::<Vec<_>>();
        let decisions = self
            .decision_points
            .iter()
            .map(|decision| {
                json!({
                    "question": decision.question,
                    "observed_answer": decision.observed_answer,
                    "alternatives": decision.alternatives.iter().map(|alternative| json!({
                        "condition": alternative.condition,
                        "outcome": alternative.outcome,
                    })).collect::<Vec<_>>(),
                })
            })
            .collect::<Vec<_>>();
        let variations = self
            .variations
            .iter()
            .map(|variation| {
                json!({
                    "name": variation.name,
                    "when": variation.when,
                    "difference": variation.difference,
                })
            })
            .collect::<Vec<_>>();

        let evidence_confidence = match self.confidence.score() {
            Some(score) => score,
            None => qaptr_domain::Confidence::new(0.0)?,
        };

        Ok(WorkflowRecord {
            id: self.id.clone(),
            session_id,
            title: self.title.clone(),
            goal: self.goal.clone().unwrap_or_default(),
            context: self.context.clone().unwrap_or_default(),
            tools: serde_json::to_string(&tools)
                .map_err(|_| WorkflowError::InvalidStoredField { field: "tools" })?,
            sequence: serde_json::to_string(&document_value(self))
                .map_err(|_| WorkflowError::InvalidStoredField { field: "sequence" })?,
            decisions: serde_json::to_string(&decisions)
                .map_err(|_| WorkflowError::InvalidStoredField { field: "decisions" })?,
            variations: serde_json::to_string(&variations).map_err(|_| {
                WorkflowError::InvalidStoredField {
                    field: "variations",
                }
            })?,
            evidence_confidence,
            created_at,
        })
    }

    /// Restores a document only from the versioned lossless scalar payload.
    ///
    /// Legacy workflow rows intentionally return an error. Their scalar
    /// projections do not contain enough information to reconstruct nested
    /// confidence or provenance without inventing details.
    pub fn from_record(record: &WorkflowRecord) -> Result<Self> {
        let value: Value = serde_json::from_str(&record.sequence)
            .map_err(|_| WorkflowError::InvalidStoredField { field: "sequence" })?;
        let object = value
            .as_object()
            .ok_or(WorkflowError::InvalidStoredField { field: "sequence" })?;
        if object.get("format") != Some(&json!(DOCUMENT_FORMAT))
            || object.get("version") != Some(&json!(DOCUMENT_VERSION))
        {
            return Err(WorkflowError::InvalidStoredField { field: "sequence" });
        }

        let id = WorkflowId::new(required_string(object, "id")?)?;
        let title = required_string(object, "title")?;
        let goal = optional_string(object, "goal")?;
        let context = optional_string(object, "context")?;
        let inputs = parse_artifacts(object, "inputs")?;
        let outputs = parse_artifacts(object, "outputs")?;
        let tools = parse_tools(object)?;
        let steps = parse_steps(object)?;
        let decisions = parse_decisions(object)?;
        let variations = parse_variations(object)?;
        let confidence = parse_confidence(required_value(object, "confidence")?, "confidence")?;
        let provenance = parse_provenance(required_value(object, "provenance")?)?;

        let mut builder = Self::builder(id, title);
        if let Some(goal) = goal {
            builder = builder.goal(goal);
        }
        if let Some(context) = context {
            builder = builder.context(context);
        }
        for input in inputs {
            builder = builder.input(input);
        }
        for output in outputs {
            builder = builder.output(output);
        }
        for tool in tools {
            builder = builder.tool(tool);
        }
        for step in steps {
            builder = builder.step(step);
        }
        for decision in decisions {
            builder = builder.decision(decision);
        }
        for variation in variations {
            builder = builder.variation(variation);
        }
        let document = builder
            .confidence(confidence)
            .provenance(provenance)
            .build()?;

        if document.id != record.id
            || document.title != record.title
            || document.goal.as_deref().unwrap_or_default() != record.goal
            || document.context.as_deref().unwrap_or_default() != record.context
            || document.confidence.score().map_or(0.0, Confidence::as_f32)
                != record.evidence_confidence.as_f32()
        {
            return Err(WorkflowError::InvalidStoredField { field: "sequence" });
        }
        if document.provenance.session_id.as_ref() != Some(&record.session_id) {
            return Err(WorkflowError::InvalidStoredField { field: "sequence" });
        }
        Ok(document)
    }

    /// Returns whether the document has no observed sequence.
    pub fn has_no_sequence(&self) -> bool {
        self.steps.is_empty()
    }
}

const DOCUMENT_FORMAT: &str = "qaptr.workflow.document";
const DOCUMENT_VERSION: u64 = 1;

fn document_value(document: &WorkflowDocument) -> Value {
    json!({
        "format": DOCUMENT_FORMAT,
        "version": DOCUMENT_VERSION,
        "id": document.id.as_str(),
        "title": document.title,
        "goal": document.goal,
        "context": document.context,
        "inputs": document.inputs.iter().map(artifact_value).collect::<Vec<_>>(),
        "outputs": document.outputs.iter().map(artifact_value).collect::<Vec<_>>(),
        "tools": document.tools.iter().map(tool_value).collect::<Vec<_>>(),
        "steps": document.steps.iter().map(step_value).collect::<Vec<_>>(),
        "decision_points": document.decision_points.iter().map(decision_value).collect::<Vec<_>>(),
        "variations": document.variations.iter().map(variation_value).collect::<Vec<_>>(),
        "confidence": confidence_value(&document.confidence),
        "provenance": provenance_value(&document.provenance),
    })
}

fn artifact_value(artifact: &Artifact) -> Value {
    json!({
        "name": artifact.name,
        "description": artifact.description,
        "required": artifact.required,
        "confidence": confidence_value(&artifact.confidence),
        "provenance": provenance_value(&artifact.provenance),
    })
}

fn tool_value(tool: &ToolObserved) -> Value {
    json!({
        "name": tool.name,
        "purpose": tool.purpose,
        "observed_usage": tool.observed_usage,
        "confidence": confidence_value(&tool.confidence),
        "provenance": provenance_value(&tool.provenance),
    })
}

fn step_value(step: &WorkflowStep) -> Value {
    json!({
        "name": step.name,
        "action": step.action,
        "rationale": step.rationale,
        "tools": step.tools,
        "inputs": step.inputs,
        "outputs": step.outputs,
        "confidence": confidence_value(&step.confidence),
        "provenance": provenance_value(&step.provenance),
    })
}

fn decision_value(decision: &DecisionPoint) -> Value {
    json!({
        "question": decision.question,
        "observed_answer": decision.observed_answer,
        "alternatives": decision.alternatives.iter().map(|alternative| json!({
            "condition": alternative.condition,
            "outcome": alternative.outcome,
        })).collect::<Vec<_>>(),
        "confidence": confidence_value(&decision.confidence),
        "provenance": provenance_value(&decision.provenance),
    })
}

fn variation_value(variation: &WorkflowVariation) -> Value {
    json!({
        "name": variation.name,
        "when": variation.when,
        "difference": variation.difference,
        "confidence": confidence_value(&variation.confidence),
        "provenance": provenance_value(&variation.provenance),
    })
}

fn confidence_value(assessment: &ConfidenceAssessment) -> Value {
    json!({
        "score": assessment.score().map(Confidence::as_f32),
        "basis": assessment.basis(),
    })
}

fn provenance_value(provenance: &Provenance) -> Value {
    json!({
        "session_id": provenance.session_id.as_ref().map(ToString::to_string),
        "observation_ids": provenance.observation_ids.iter().map(ToString::to_string).collect::<Vec<_>>(),
        "capture_ids": provenance.capture_ids.iter().map(ToString::to_string).collect::<Vec<_>>(),
        "note": provenance.note,
    })
}

fn required_value<'a>(
    object: &'a serde_json::Map<String, Value>,
    field: &'static str,
) -> Result<&'a Value> {
    object
        .get(field)
        .ok_or(WorkflowError::InvalidStoredField { field })
}

fn required_string(object: &serde_json::Map<String, Value>, field: &'static str) -> Result<String> {
    required_value(object, field)?
        .as_str()
        .map(str::to_owned)
        .ok_or(WorkflowError::InvalidStoredField { field })
}

fn optional_string(
    object: &serde_json::Map<String, Value>,
    field: &'static str,
) -> Result<Option<String>> {
    match required_value(object, field)? {
        Value::Null => Ok(None),
        Value::String(value) => Ok(Some(value.clone())),
        _ => Err(WorkflowError::InvalidStoredField { field }),
    }
}

fn required_array<'a>(
    object: &'a serde_json::Map<String, Value>,
    field: &'static str,
) -> Result<&'a Vec<Value>> {
    required_value(object, field)?
        .as_array()
        .ok_or(WorkflowError::InvalidStoredField { field })
}

fn required_object<'a>(
    value: &'a Value,
    field: &'static str,
) -> Result<&'a serde_json::Map<String, Value>> {
    value
        .as_object()
        .ok_or(WorkflowError::InvalidStoredField { field })
}

fn parse_confidence(value: &Value, field: &'static str) -> Result<ConfidenceAssessment> {
    let object = required_object(value, field)?;
    let score = match required_value(object, "score")? {
        Value::Null => None,
        value => Some(
            value
                .as_f64()
                .and_then(|value| Confidence::new(value as f32).ok())
                .ok_or(WorkflowError::InvalidStoredField { field })?,
        ),
    };
    let basis = optional_string(object, "basis")?;
    let assessment = match score {
        Some(score) => ConfidenceAssessment::scored(score),
        None => ConfidenceAssessment::unknown(),
    };
    Ok(match basis {
        Some(basis) => assessment.with_basis(basis),
        None => assessment,
    })
}

fn parse_provenance(value: &Value) -> Result<Provenance> {
    let object = required_object(value, "provenance")?;
    let session_id = optional_string(object, "session_id")?
        .map(SessionId::new)
        .transpose()?;
    let observation_ids = required_array(object, "observation_ids")?
        .iter()
        .map(|value| {
            let value = value.as_str().ok_or(WorkflowError::InvalidStoredField {
                field: "observation_ids",
            })?;
            Ok(ObservationId::new(value)?)
        })
        .collect::<Result<Vec<_>>>()?;
    let capture_ids = required_array(object, "capture_ids")?
        .iter()
        .map(|value| {
            let value = value.as_str().ok_or(WorkflowError::InvalidStoredField {
                field: "capture_ids",
            })?;
            Ok(CaptureId::new(value)?)
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(Provenance {
        session_id,
        observation_ids,
        capture_ids,
        note: optional_string(object, "note")?,
    })
}

fn parse_artifacts(
    object: &serde_json::Map<String, Value>,
    field: &'static str,
) -> Result<Vec<Artifact>> {
    required_array(object, field)?
        .iter()
        .map(|value| {
            let object = required_object(value, field)?;
            let mut artifact = Artifact::new(required_string(object, "name")?)?;
            if !required_value(object, "required")?
                .as_bool()
                .ok_or(WorkflowError::InvalidStoredField { field })?
            {
                artifact = artifact.optional();
            }
            if let Some(description) = optional_string(object, "description")? {
                artifact = artifact.with_description(description);
            }
            Ok(artifact
                .with_confidence(parse_confidence(
                    required_value(object, "confidence")?,
                    field,
                )?)
                .with_provenance(parse_provenance(required_value(object, "provenance")?)?))
        })
        .collect()
}

fn parse_tools(object: &serde_json::Map<String, Value>) -> Result<Vec<ToolObserved>> {
    required_array(object, "tools")?
        .iter()
        .map(|value| {
            let object = required_object(value, "tools")?;
            let mut tool = ToolObserved::new(required_string(object, "name")?)?;
            if let Some(purpose) = optional_string(object, "purpose")? {
                tool = tool.with_purpose(purpose);
            }
            if let Some(usage) = optional_string(object, "observed_usage")? {
                tool = tool.with_observed_usage(usage);
            }
            Ok(tool
                .with_confidence(parse_confidence(
                    required_value(object, "confidence")?,
                    "tools",
                )?)
                .with_provenance(parse_provenance(required_value(object, "provenance")?)?))
        })
        .collect()
}

fn parse_steps(object: &serde_json::Map<String, Value>) -> Result<Vec<WorkflowStep>> {
    required_array(object, "steps")?
        .iter()
        .map(|value| {
            let object = required_object(value, "steps")?;
            let mut step = WorkflowStep::new(
                required_string(object, "name")?,
                required_string(object, "action")?,
            )?;
            if let Some(rationale) = optional_string(object, "rationale")? {
                step = step.with_rationale(rationale);
            }
            for tool in required_array(object, "tools")? {
                step = step.using_tool(
                    tool.as_str()
                        .ok_or(WorkflowError::InvalidStoredField { field: "steps" })?,
                );
            }
            for input in required_array(object, "inputs")? {
                step = step.consuming(
                    input
                        .as_str()
                        .ok_or(WorkflowError::InvalidStoredField { field: "steps" })?,
                );
            }
            for output in required_array(object, "outputs")? {
                step = step.producing(
                    output
                        .as_str()
                        .ok_or(WorkflowError::InvalidStoredField { field: "steps" })?,
                );
            }
            Ok(step
                .with_confidence(parse_confidence(
                    required_value(object, "confidence")?,
                    "steps",
                )?)
                .with_provenance(parse_provenance(required_value(object, "provenance")?)?))
        })
        .collect()
}

fn parse_decisions(object: &serde_json::Map<String, Value>) -> Result<Vec<DecisionPoint>> {
    required_array(object, "decision_points")?
        .iter()
        .map(|value| {
            let object = required_object(value, "decision_points")?;
            let mut decision = DecisionPoint::new(required_string(object, "question")?)?;
            if let Some(answer) = optional_string(object, "observed_answer")? {
                decision = decision.with_answer(answer);
            }
            for value in required_array(object, "alternatives")? {
                let alternative = required_object(value, "alternatives")?;
                decision = decision.with_alternative(DecisionAlternative::new(
                    required_string(alternative, "condition")?,
                    required_string(alternative, "outcome")?,
                )?);
            }
            Ok(decision
                .with_confidence(parse_confidence(
                    required_value(object, "confidence")?,
                    "decision_points",
                )?)
                .with_provenance(parse_provenance(required_value(object, "provenance")?)?))
        })
        .collect()
}

fn parse_variations(object: &serde_json::Map<String, Value>) -> Result<Vec<WorkflowVariation>> {
    required_array(object, "variations")?
        .iter()
        .map(|value| {
            let object = required_object(value, "variations")?;
            Ok(WorkflowVariation::new(
                required_string(object, "name")?,
                required_string(object, "when")?,
                required_string(object, "difference")?,
            )?
            .with_confidence(parse_confidence(
                required_value(object, "confidence")?,
                "variations",
            )?)
            .with_provenance(parse_provenance(required_value(object, "provenance")?)?))
        })
        .collect()
}

/// A builder for a validated canonical Workflow document.
#[derive(Clone, Debug)]
pub struct WorkflowBuilder {
    id: WorkflowId,
    title: String,
    goal: Option<String>,
    context: Option<String>,
    inputs: Vec<Artifact>,
    outputs: Vec<Artifact>,
    tools: Vec<ToolObserved>,
    steps: Vec<WorkflowStep>,
    decision_points: Vec<DecisionPoint>,
    variations: Vec<WorkflowVariation>,
    confidence: ConfidenceAssessment,
    provenance: Provenance,
}

impl WorkflowBuilder {
    /// Sets the observed goal.
    pub fn goal(mut self, goal: impl Into<String>) -> Self {
        self.goal = Some(goal.into());
        self
    }

    /// Sets the observed context.
    pub fn context(mut self, context: impl Into<String>) -> Self {
        self.context = Some(context.into());
        self
    }

    /// Adds an input artifact.
    pub fn input(mut self, input: Artifact) -> Self {
        self.inputs.push(input);
        self
    }

    /// Adds an output artifact.
    pub fn output(mut self, output: Artifact) -> Self {
        self.outputs.push(output);
        self
    }

    /// Adds an observed tool.
    pub fn tool(mut self, tool: ToolObserved) -> Self {
        self.tools.push(tool);
        self
    }

    /// Adds an observed step in sequence order.
    pub fn step(mut self, step: WorkflowStep) -> Self {
        self.steps.push(step);
        self
    }

    /// Adds an observed decision point.
    pub fn decision(mut self, decision: DecisionPoint) -> Self {
        self.decision_points.push(decision);
        self
    }

    /// Adds a known variation.
    pub fn variation(mut self, variation: WorkflowVariation) -> Self {
        self.variations.push(variation);
        self
    }

    /// Sets overall document confidence.
    pub fn confidence(mut self, confidence: ConfidenceAssessment) -> Self {
        self.confidence = confidence;
        self
    }

    /// Sets document provenance.
    pub fn provenance(mut self, provenance: Provenance) -> Self {
        self.provenance = provenance;
        self
    }

    /// Validates and finishes the document.
    pub fn build(self) -> Result<WorkflowDocument> {
        Ok(WorkflowDocument {
            id: self.id,
            title: required_text("workflow title", self.title)?,
            goal: optional_text("workflow goal", self.goal)?,
            context: optional_text("workflow context", self.context)?,
            inputs: self.inputs,
            outputs: self.outputs,
            tools: self.tools,
            steps: self.steps,
            decision_points: self.decision_points,
            variations: self.variations,
            confidence: self.confidence,
            provenance: self.provenance,
        })
    }
}
