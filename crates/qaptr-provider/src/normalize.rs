//! Normalized provider response values.

use qaptr_domain::Confidence;

use crate::{RawObservation, RawProviderResponse, RawWorkflow, SchemaError};

/// A validated observation shared by every provider adapter.
#[derive(Clone, Debug, PartialEq)]
pub struct NormalizedObservation {
    title: String,
    summary: String,
    confidence: Confidence,
}

impl NormalizedObservation {
    /// Returns the observation title.
    pub fn title(&self) -> &str {
        &self.title
    }

    /// Returns the observation summary.
    pub fn summary(&self) -> &str {
        &self.summary
    }

    /// Returns the validated confidence.
    pub const fn confidence(&self) -> Confidence {
        self.confidence
    }
}

/// A validated candidate workflow shared by every provider adapter.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NormalizedWorkflow {
    title: String,
    goal: String,
}

impl NormalizedWorkflow {
    /// Returns the workflow title.
    pub fn title(&self) -> &str {
        &self.title
    }

    /// Returns the workflow goal.
    pub fn goal(&self) -> &str {
        &self.goal
    }
}

/// The provider-independent response shape consumed by later analysis units.
#[derive(Clone, Debug, PartialEq)]
pub struct NormalizedResponse {
    observations: Vec<NormalizedObservation>,
    workflow: Option<NormalizedWorkflow>,
}

impl NormalizedResponse {
    /// Returns normalized observations in provider response order.
    pub fn observations(&self) -> &[NormalizedObservation] {
        &self.observations
    }

    /// Returns the optional normalized workflow candidate.
    pub fn workflow(&self) -> Option<&NormalizedWorkflow> {
        self.workflow.as_ref()
    }
}

/// Validates and normalizes one raw adapter response.
pub fn normalize_response(raw: RawProviderResponse) -> Result<NormalizedResponse, SchemaError> {
    let observations = raw
        .observations
        .into_iter()
        .enumerate()
        .map(normalize_observation)
        .collect::<Result<Vec<_>, _>>()?;
    let workflow = raw.workflow.map(normalize_workflow).transpose()?;
    Ok(NormalizedResponse {
        observations,
        workflow,
    })
}

fn normalize_observation(
    (index, raw): (usize, RawObservation),
) -> Result<NormalizedObservation, SchemaError> {
    if raw.title.trim().is_empty() {
        return Err(SchemaError::EmptyField {
            object: "observation",
            field: "title",
        });
    }
    if raw.summary.trim().is_empty() {
        return Err(SchemaError::EmptyField {
            object: "observation",
            field: "summary",
        });
    }
    let confidence =
        Confidence::new(raw.confidence).map_err(|_| SchemaError::InvalidConfidence { index })?;
    Ok(NormalizedObservation {
        title: raw.title,
        summary: raw.summary,
        confidence,
    })
}

fn normalize_workflow(raw: RawWorkflow) -> Result<NormalizedWorkflow, SchemaError> {
    if raw.title.trim().is_empty() {
        return Err(SchemaError::EmptyField {
            object: "workflow",
            field: "title",
        });
    }
    if raw.goal.trim().is_empty() {
        return Err(SchemaError::EmptyField {
            object: "workflow",
            field: "goal",
        });
    }
    Ok(NormalizedWorkflow {
        title: raw.title,
        goal: raw.goal,
    })
}
