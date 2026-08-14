//! Construction errors for the canonical Workflow model.

use qaptr_domain::DomainError;
use thiserror::Error;

/// Errors returned while constructing a canonical Workflow document.
#[derive(Debug, Error, PartialEq)]
pub enum WorkflowError {
    /// A required human-readable field was empty or whitespace-only.
    #[error("{field} must not be empty")]
    EmptyField {
        /// The field that failed validation.
        field: &'static str,
    },
    /// A domain identifier or confidence value failed its shared validation.
    #[error(transparent)]
    Domain(#[from] DomainError),
}

/// The result type for Workflow model construction.
pub type Result<T> = std::result::Result<T, WorkflowError>;
