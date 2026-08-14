//! Shared validated vocabulary used by the canonical Workflow document.
//!
//! These values are pure data. They do not read files, call providers, inspect
//! captures, or execute tools.

use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId};

use super::errors::{Result, WorkflowError};

/// A confidence assessment that can honestly represent unavailable evidence.
#[derive(Clone, Debug, PartialEq)]
pub struct ConfidenceAssessment {
    score: Option<Confidence>,
    basis: Option<String>,
}

impl ConfidenceAssessment {
    /// Creates an assessment for which no confidence score was available.
    pub const fn unknown() -> Self {
        Self {
            score: None,
            basis: None,
        }
    }

    /// Creates an assessment from a validated confidence score.
    pub const fn scored(score: Confidence) -> Self {
        Self {
            score: Some(score),
            basis: None,
        }
    }

    /// Adds a human-readable explanation for the assessment.
    pub fn with_basis(mut self, basis: impl Into<String>) -> Self {
        self.basis = Some(basis.into());
        self
    }

    /// Returns the score, if one was measured.
    pub const fn score(&self) -> Option<Confidence> {
        self.score
    }

    /// Returns the evidence basis, if one was recorded.
    pub fn basis(&self) -> Option<&str> {
        self.basis.as_deref()
    }
}

/// References to durable records that support a Workflow claim.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Provenance {
    /// The analysis session that produced the material, when known.
    pub session_id: Option<SessionId>,
    /// Observations that support the material.
    pub observation_ids: Vec<ObservationId>,
    /// Captures that support the material, when their identifiers remain known.
    pub capture_ids: Vec<CaptureId>,
    /// A short note about how the material was established.
    pub note: Option<String>,
}

impl Provenance {
    /// Creates provenance with no source records.
    pub const fn empty() -> Self {
        Self {
            session_id: None,
            observation_ids: Vec::new(),
            capture_ids: Vec::new(),
            note: None,
        }
    }

    /// Returns whether this provenance has no recorded source information.
    pub fn is_empty(&self) -> bool {
        self.session_id.is_none()
            && self.observation_ids.is_empty()
            && self.capture_ids.is_empty()
            && self.note.is_none()
    }
}

/// An input or output artifact observed in a Workflow.
#[derive(Clone, Debug, PartialEq)]
pub struct Artifact {
    /// The artifact's human-readable name.
    pub name: String,
    /// What the artifact is used for, when observed.
    pub description: Option<String>,
    /// Whether the artifact is required for the described path.
    pub required: bool,
    /// Confidence in the artifact claim.
    pub confidence: ConfidenceAssessment,
    /// Source records supporting the artifact claim.
    pub provenance: Provenance,
}

impl Artifact {
    /// Creates a required artifact with unknown confidence.
    pub fn new(name: impl Into<String>) -> Result<Self> {
        Ok(Self {
            name: required_text("artifact name", name.into())?,
            description: None,
            required: true,
            confidence: ConfidenceAssessment::unknown(),
            provenance: Provenance::empty(),
        })
    }

    /// Sets an optional artifact description.
    pub fn with_description(mut self, description: impl Into<String>) -> Self {
        self.description = Some(description.into());
        self
    }

    /// Marks the artifact as optional.
    pub const fn optional(mut self) -> Self {
        self.required = false;
        self
    }

    /// Sets the artifact confidence.
    pub fn with_confidence(mut self, confidence: ConfidenceAssessment) -> Self {
        self.confidence = confidence;
        self
    }

    /// Sets the artifact provenance.
    pub fn with_provenance(mut self, provenance: Provenance) -> Self {
        self.provenance = provenance;
        self
    }
}

/// A tool or application observed while the Workflow was performed.
#[derive(Clone, Debug, PartialEq)]
pub struct ToolObserved {
    /// The observed tool name.
    pub name: String,
    /// The role the tool played, when known.
    pub purpose: Option<String>,
    /// What was actually observed about its use.
    pub observed_usage: Option<String>,
    /// Confidence in the tool claim.
    pub confidence: ConfidenceAssessment,
    /// Source records supporting the tool claim.
    pub provenance: Provenance,
}

impl ToolObserved {
    /// Creates an observed tool with unknown confidence.
    pub fn new(name: impl Into<String>) -> Result<Self> {
        Ok(Self {
            name: required_text("tool name", name.into())?,
            purpose: None,
            observed_usage: None,
            confidence: ConfidenceAssessment::unknown(),
            provenance: Provenance::empty(),
        })
    }

    /// Sets the tool's purpose.
    pub fn with_purpose(mut self, purpose: impl Into<String>) -> Self {
        self.purpose = Some(purpose.into());
        self
    }

    /// Sets the observed usage description.
    pub fn with_observed_usage(mut self, observed_usage: impl Into<String>) -> Self {
        self.observed_usage = Some(observed_usage.into());
        self
    }

    /// Sets the tool confidence.
    pub fn with_confidence(mut self, confidence: ConfidenceAssessment) -> Self {
        self.confidence = confidence;
        self
    }

    /// Sets the tool provenance.
    pub fn with_provenance(mut self, provenance: Provenance) -> Self {
        self.provenance = provenance;
        self
    }
}

/// One observed action in the canonical Workflow sequence.
#[derive(Clone, Debug, PartialEq)]
pub struct WorkflowStep {
    /// A short name for the step.
    pub name: String,
    /// The observed action, stated without inventing missing details.
    pub action: String,
    /// Why the action was performed, when observed.
    pub rationale: Option<String>,
    /// Tool names observed in this step.
    pub tools: Vec<String>,
    /// Inputs used by this step.
    pub inputs: Vec<String>,
    /// Outputs produced by this step.
    pub outputs: Vec<String>,
    /// Confidence in this step.
    pub confidence: ConfidenceAssessment,
    /// Source records supporting this step.
    pub provenance: Provenance,
}

impl WorkflowStep {
    /// Creates a step from an observed name and action.
    pub fn new(name: impl Into<String>, action: impl Into<String>) -> Result<Self> {
        Ok(Self {
            name: required_text("step name", name.into())?,
            action: required_text("step action", action.into())?,
            rationale: None,
            tools: Vec::new(),
            inputs: Vec::new(),
            outputs: Vec::new(),
            confidence: ConfidenceAssessment::unknown(),
            provenance: Provenance::empty(),
        })
    }

    /// Sets the step rationale.
    pub fn with_rationale(mut self, rationale: impl Into<String>) -> Self {
        self.rationale = Some(rationale.into());
        self
    }

    /// Adds a tool name to the step.
    pub fn using_tool(mut self, tool: impl Into<String>) -> Self {
        self.tools.push(tool.into());
        self
    }

    /// Adds an input name to the step.
    pub fn consuming(mut self, input: impl Into<String>) -> Self {
        self.inputs.push(input.into());
        self
    }

    /// Adds an output name to the step.
    pub fn producing(mut self, output: impl Into<String>) -> Self {
        self.outputs.push(output.into());
        self
    }

    /// Sets the step confidence.
    pub fn with_confidence(mut self, confidence: ConfidenceAssessment) -> Self {
        self.confidence = confidence;
        self
    }

    /// Sets the step provenance.
    pub fn with_provenance(mut self, provenance: Provenance) -> Self {
        self.provenance = provenance;
        self
    }
}

/// An observed branch or decision in the Workflow.
#[derive(Clone, Debug, PartialEq)]
pub struct DecisionPoint {
    /// The question or condition that separated paths.
    pub question: String,
    /// The observed answer or selected path, when known.
    pub observed_answer: Option<String>,
    /// Other observed alternatives, if any.
    pub alternatives: Vec<DecisionAlternative>,
    /// Confidence in this decision point.
    pub confidence: ConfidenceAssessment,
    /// Source records supporting this decision point.
    pub provenance: Provenance,
}

impl DecisionPoint {
    /// Creates a decision point from its observed question.
    pub fn new(question: impl Into<String>) -> Result<Self> {
        Ok(Self {
            question: required_text("decision question", question.into())?,
            observed_answer: None,
            alternatives: Vec::new(),
            confidence: ConfidenceAssessment::unknown(),
            provenance: Provenance::empty(),
        })
    }

    /// Records the observed answer.
    pub fn with_answer(mut self, answer: impl Into<String>) -> Self {
        self.observed_answer = Some(answer.into());
        self
    }

    /// Adds an observed alternative path.
    pub fn with_alternative(mut self, alternative: DecisionAlternative) -> Self {
        self.alternatives.push(alternative);
        self
    }

    /// Sets decision confidence.
    pub fn with_confidence(mut self, confidence: ConfidenceAssessment) -> Self {
        self.confidence = confidence;
        self
    }

    /// Sets decision provenance.
    pub fn with_provenance(mut self, provenance: Provenance) -> Self {
        self.provenance = provenance;
        self
    }
}

/// One alternative path associated with a decision point.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DecisionAlternative {
    /// The condition under which this path applies.
    pub condition: String,
    /// The observed result of taking this path.
    pub outcome: String,
}

impl DecisionAlternative {
    /// Creates an alternative path.
    pub fn new(condition: impl Into<String>, outcome: impl Into<String>) -> Result<Self> {
        Ok(Self {
            condition: required_text("decision condition", condition.into())?,
            outcome: required_text("decision outcome", outcome.into())?,
        })
    }
}

/// A known variation from the observed primary Workflow path.
#[derive(Clone, Debug, PartialEq)]
pub struct WorkflowVariation {
    /// The variation's name.
    pub name: String,
    /// When this variation applies.
    pub when: String,
    /// What differs from the primary path.
    pub difference: String,
    /// Confidence in this variation.
    pub confidence: ConfidenceAssessment,
    /// Source records supporting this variation.
    pub provenance: Provenance,
}

impl WorkflowVariation {
    /// Creates a known Workflow variation.
    pub fn new(
        name: impl Into<String>,
        when: impl Into<String>,
        difference: impl Into<String>,
    ) -> Result<Self> {
        Ok(Self {
            name: required_text("variation name", name.into())?,
            when: required_text("variation condition", when.into())?,
            difference: required_text("variation difference", difference.into())?,
            confidence: ConfidenceAssessment::unknown(),
            provenance: Provenance::empty(),
        })
    }

    /// Sets variation confidence.
    pub fn with_confidence(mut self, confidence: ConfidenceAssessment) -> Self {
        self.confidence = confidence;
        self
    }

    /// Sets variation provenance.
    pub fn with_provenance(mut self, provenance: Provenance) -> Self {
        self.provenance = provenance;
        self
    }
}

/// Validates a required human-readable value.
pub(super) fn required_text(field: &'static str, value: String) -> Result<String> {
    if value.trim().is_empty() {
        Err(WorkflowError::EmptyField { field })
    } else {
        Ok(value)
    }
}

/// Validates an optional human-readable value.
pub(super) fn optional_text(field: &'static str, value: Option<String>) -> Result<Option<String>> {
    value.map(|value| required_text(field, value)).transpose()
}
