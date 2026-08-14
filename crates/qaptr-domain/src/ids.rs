//! Newtyped identifiers used to keep domain records from being mixed up.

use std::{fmt, str::FromStr};

use crate::{DomainError, Result};

macro_rules! define_id {
    ($name:ident, $kind:literal, $docs:literal) => {
        #[doc = $docs]
        #[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
        pub struct $name(String);

        impl $name {
            /// Constructs an identifier after rejecting an empty value.
            pub fn new(value: impl Into<String>) -> Result<Self> {
                let value = value.into();
                if value.is_empty() {
                    return Err(DomainError::EmptyId { kind: $kind });
                }
                Ok(Self(value))
            }

            /// Returns the identifier's string representation.
            pub fn as_str(&self) -> &str {
                &self.0
            }

            /// Returns the owned string representation.
            pub fn into_inner(self) -> String {
                self.0
            }
        }

        impl AsRef<str> for $name {
            fn as_ref(&self) -> &str {
                self.as_str()
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                self.0.fmt(formatter)
            }
        }

        impl FromStr for $name {
            type Err = DomainError;

            fn from_str(value: &str) -> std::result::Result<Self, Self::Err> {
                Self::new(value)
            }
        }
    };
}

define_id!(
    CaptureId,
    "capture",
    "The stable identifier of a captured sample."
);
define_id!(
    ObservationId,
    "observation",
    "The stable identifier of an observation."
);
define_id!(
    SessionId,
    "session",
    "The stable identifier of an analysis session."
);
define_id!(
    WorkflowId,
    "workflow",
    "The stable identifier of a workflow."
);
