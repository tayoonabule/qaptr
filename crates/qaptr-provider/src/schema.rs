//! Raw provider output and schema validation inputs.

use thiserror::Error;

/// Raw observation output returned by an adapter before normalization.
#[derive(Clone, Debug, PartialEq)]
pub struct RawObservation {
    /// Short observation title.
    pub title: String,
    /// Human-readable observation summary.
    pub summary: String,
    /// Confidence score expected to be between zero and one.
    pub confidence: f32,
}

impl RawObservation {
    /// Creates a raw observation for an adapter or in-process fake.
    pub fn new(title: impl Into<String>, summary: impl Into<String>, confidence: f32) -> Self {
        Self {
            title: title.into(),
            summary: summary.into(),
            confidence,
        }
    }
}

/// Raw candidate workflow returned by an adapter before normalization.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RawWorkflow {
    /// Workflow title.
    pub title: String,
    /// Workflow goal.
    pub goal: String,
}

impl RawWorkflow {
    /// Creates a raw workflow for an adapter or in-process fake.
    pub fn new(title: impl Into<String>, goal: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            goal: goal.into(),
        }
    }
}

/// The complete raw response returned by an adapter.
#[derive(Clone, Debug, PartialEq)]
pub struct RawProviderResponse {
    /// Ordered observations.
    pub observations: Vec<RawObservation>,
    /// Optional candidate workflow.
    pub workflow: Option<RawWorkflow>,
}

impl RawProviderResponse {
    /// Creates a raw response for an adapter or in-process fake.
    pub fn new(observations: Vec<RawObservation>, workflow: Option<RawWorkflow>) -> Self {
        Self {
            observations,
            workflow,
        }
    }
}

/// Schema failures found before raw provider output becomes normalized output.
#[derive(Clone, Debug, Error, PartialEq)]
pub enum SchemaError {
    /// A required response field was empty.
    #[error("{object} field {field} must not be empty")]
    EmptyField {
        /// The response object containing the field.
        object: &'static str,
        /// The invalid field name.
        field: &'static str,
    },
    /// An observation confidence was invalid.
    #[error("observation {index} confidence must be finite and between 0 and 1")]
    InvalidConfidence {
        /// The observation index.
        index: usize,
    },
}
