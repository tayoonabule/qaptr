//! The canonical Workflow document and its construction API.

mod components;
mod errors;

pub use components::{
    Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, Provenance, ToolObserved,
    WorkflowStep, WorkflowVariation,
};
pub use errors::{Result, WorkflowError};

use qaptr_domain::{CaptureId, SessionId, WorkflowId};
use qaptr_provider::NormalizedWorkflow;
use qaptr_store::{ObservationRecord, UnixMillis, WorkflowRecord};
use serde_json::json;

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
    /// Structured fields are encoded as deterministic JSON text inside the
    /// existing scalar columns. The store still sees only validated text, and
    /// no capture bytes, thumbnails, or privacy payloads can cross this API.
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
        let steps = self
            .steps
            .iter()
            .map(|step| {
                json!({
                    "name": step.name,
                    "action": step.action,
                    "rationale": step.rationale,
                    "tools": step.tools,
                    "inputs": step.inputs,
                    "outputs": step.outputs,
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
            sequence: serde_json::to_string(&json!({
                "inputs": self.inputs.iter().map(|input| json!({
                    "name": input.name,
                    "description": input.description,
                    "required": input.required,
                })).collect::<Vec<_>>(),
                "outputs": self.outputs.iter().map(|output| json!({
                    "name": output.name,
                    "description": output.description,
                    "required": output.required,
                })).collect::<Vec<_>>(),
                "steps": steps,
            }))
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

    /// Returns whether the document has no observed sequence.
    pub fn has_no_sequence(&self) -> bool {
        self.steps.is_empty()
    }
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
