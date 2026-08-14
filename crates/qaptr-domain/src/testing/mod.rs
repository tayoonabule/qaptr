//! Deterministic in-memory doubles for domain-port tests.
//!
//! This module is compiled only for tests or when the `testing` feature is
//! enabled. Production builds without that feature cannot depend on these
//! doubles.

mod doubles;

pub use doubles::{
    InMemoryAccessibilityContext, InMemoryCapture, InMemoryCredentials, InMemoryLoginItem,
    InMemoryOcr, InMemoryPermissions, InMemoryVision,
};

/// Translates a configured response into a domain result.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Response<T> {
    /// Return a complete value.
    Complete(T),
    /// Return an explicitly incomplete value.
    Partial(T),
    /// Return a typed denial.
    Denied,
    /// Return a typed timeout.
    TimedOut,
}

impl<T> Response<T> {
    /// Converts this configured response to a port result.
    pub fn into_result(
        self,
        operation: &'static str,
    ) -> crate::Result<crate::ports::PortOutcome<T>> {
        match self {
            Self::Complete(value) => Ok(crate::ports::PortOutcome::Complete(value)),
            Self::Partial(value) => Ok(crate::ports::PortOutcome::Partial(value)),
            Self::Denied => Err(crate::DomainError::Denied { operation }),
            Self::TimedOut => Err(crate::DomainError::TimedOut { operation }),
        }
    }
}
