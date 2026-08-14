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
    /// A required positive dimension was zero.
    #[error("{kind} must be greater than zero")]
    InvalidDimension {
        /// The dimension's domain name.
        kind: &'static str,
    },
    /// A confidence value was outside the inclusive range from zero to one.
    #[error("confidence must be finite and between 0 and 1, got {value}")]
    InvalidConfidence {
        /// The value that failed validation.
        value: f32,
    },
    /// A platform operation was refused by the user or operating system.
    #[error("{operation} was denied")]
    Denied {
        /// The domain operation that was refused.
        operation: &'static str,
    },
    /// A platform operation exceeded its bounded time budget.
    #[error("{operation} timed out")]
    TimedOut {
        /// The domain operation that exceeded its budget.
        operation: &'static str,
    },
}

/// A convenient result type for domain constructors.
pub type Result<T> = std::result::Result<T, DomainError>;
