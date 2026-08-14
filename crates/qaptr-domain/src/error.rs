//! Errors returned when domain values cannot be constructed.

use thiserror::Error;

/// The error type shared by validated domain value constructors.
#[derive(Debug, Error, PartialEq)]
pub enum DomainError {
    /// An identifier was constructed without any characters.
    #[error("{kind} id must not be empty")]
    EmptyId {
        /// The domain type whose identifier was empty.
        kind: &'static str,
    },
    /// A confidence value was outside the inclusive range from zero to one.
    #[error("confidence must be finite and between 0 and 1, got {value}")]
    InvalidConfidence {
        /// The value that failed validation.
        value: f32,
    },
}

/// A convenient result type for domain constructors.
pub type Result<T> = std::result::Result<T, DomainError>;
