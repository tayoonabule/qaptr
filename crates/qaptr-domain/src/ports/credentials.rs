//! The secure credential-storage port.

use std::fmt;

use super::PortResult;

/// A non-empty logical key for a provider credential.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct CredentialKey(String);

impl CredentialKey {
    /// Creates a credential key, rejecting an empty value.
    pub fn new(value: impl Into<String>) -> crate::Result<Self> {
        let value = value.into();
        if value.is_empty() {
            return Err(crate::DomainError::EmptyId { kind: "credential" });
        }
        Ok(Self(value))
    }

    /// Returns the logical key.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A secret credential value whose debug output never reveals the secret.
#[derive(Clone, Eq, PartialEq)]
pub struct CredentialValue(String);

impl CredentialValue {
    /// Creates a credential value.
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// Returns the secret value for the owning adapter.
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for CredentialValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("CredentialValue([redacted])")
    }
}

/// Reads, writes, and deletes provider credentials through secure storage.
pub trait CredentialPort {
    /// Reads one credential, returning `None` when it has not been configured.
    fn read(&self, key: &CredentialKey) -> PortResult<Option<CredentialValue>>;

    /// Stores one credential.
    fn write(&self, key: &CredentialKey, value: CredentialValue) -> PortResult<()>;

    /// Deletes one credential.
    fn delete(&self, key: &CredentialKey) -> PortResult<()>;
}

/// Short alias for callers that prefer the domain noun.
pub use CredentialPort as Credentials;
