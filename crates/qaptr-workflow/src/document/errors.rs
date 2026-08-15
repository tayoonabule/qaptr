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
    /// A durable Workflow record did not identify its originating session.
    #[error("workflow provenance is missing a session id")]
    MissingSession,
    /// A scalar field in a durable Workflow record could not be decoded.
    #[error("workflow record field {field} is not valid canonical data")]
    InvalidStoredField {
        /// The record field that failed decoding.
        field: &'static str,
    },
}

/// The result type for Workflow model construction.
pub type Result<T> = std::result::Result<T, WorkflowError>;
