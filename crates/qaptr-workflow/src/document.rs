//! The canonical Workflow document and its construction API.

mod components;
mod errors;

pub use components::{
    Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, Provenance, ToolObserved,
    WorkflowStep, WorkflowVariation,
};
pub use errors::{Result, WorkflowError};

use qaptr_domain::WorkflowId;

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
