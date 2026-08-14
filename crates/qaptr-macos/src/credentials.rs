//! Keychain-backed credentials for the review app.

#![allow(unsafe_code)]

use qaptr_domain::DomainError;
use qaptr_domain::ports::credentials::{CredentialKey, CredentialPort, CredentialValue};
use qaptr_domain::ports::{PortOutcome, PortResult};
use security_framework::base::Error as SecurityError;
use security_framework::passwords::{generic_password, set_generic_password_options};
use security_framework::passwords_options::PasswordOptions;

use crate::error::MacosError;

/// The service namespace used for all Qaptr Keychain items.
pub const KEYCHAIN_SERVICE: &str = "com.qaptr.review.credentials";

/// A review-app-only Keychain adapter.
///
/// The capture helper must never construct or link this type. It only receives
/// public generation keys through the vault hand-off and never receives private
/// credentials or Keychain access. This crate therefore belongs exclusively to
/// the review-app target.
#[derive(Clone, Debug, Default)]
pub struct MacCredentials;

impl MacCredentials {
    /// Creates an adapter using Qaptr's non-synchronizing service namespace.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }

    /// Reads a credential, returning `None` when no item exists.
    pub fn read_value(&self, key: &CredentialKey) -> Result<Option<CredentialValue>, MacosError> {
        let mut options = options_for(key);
        options.set_access_synchronized(Some(false));

        match generic_password(options) {
            Ok(value) => String::from_utf8(value)
                .map(|value| Some(CredentialValue::new(value)))
                .map_err(|_| MacosError::InvalidCredentialEncoding { operation: "read" }),
            Err(error) if error.code() == -25300 => Ok(None),
            Err(error) => Err(keychain_error("read", error)),
        }
    }

    /// Stores a credential in the local, non-synchronizing Keychain store.
    pub fn write_value(
        &self,
        key: &CredentialKey,
        value: &CredentialValue,
    ) -> Result<(), MacosError> {
        let mut options = options_for(key);
        options.set_access_synchronized(Some(false));
        set_generic_password_options(value.expose().as_bytes(), options)
            .map_err(|error| keychain_error("write", error))
    }

    /// Deletes a credential, treating an already-absent item as success.
    pub fn delete_value(&self, key: &CredentialKey) -> Result<(), MacosError> {
        let mut options = options_for(key);
        options.set_access_synchronized(Some(false));
        security_framework::passwords::delete_generic_password_options(options).or_else(|error| {
            if error.code() == -25300 {
                Ok(())
            } else {
                Err(keychain_error("delete", error))
            }
        })
    }
}

impl CredentialPort for MacCredentials {
    fn read(&self, key: &CredentialKey) -> PortResult<Option<CredentialValue>> {
        self.read_value(key)
            .map(PortOutcome::Complete)
            .map_err(|_| DomainError::Denied {
                operation: "credential read",
            })
    }

    fn write(&self, key: &CredentialKey, value: CredentialValue) -> PortResult<()> {
        self.write_value(key, &value)
            .map(|()| PortOutcome::Complete(()))
            .map_err(|_| DomainError::Denied {
                operation: "credential write",
            })
    }

    fn delete(&self, key: &CredentialKey) -> PortResult<()> {
        self.delete_value(key)
            .map(|()| PortOutcome::Complete(()))
            .map_err(|_| DomainError::Denied {
                operation: "credential delete",
            })
    }
}

fn options_for(key: &CredentialKey) -> PasswordOptions {
    PasswordOptions::new_generic_password(KEYCHAIN_SERVICE, key.as_str())
}

fn keychain_error(operation: &'static str, error: SecurityError) -> MacosError {
    MacosError::Keychain {
        operation,
        code: error.code(),
        message: error
            .message()
            .unwrap_or_else(|| "no system description".to_owned()),
    }
}

#[cfg(test)]
mod tests {
    use super::KEYCHAIN_SERVICE;

    #[test]
    fn service_namespace_is_stable_and_app_scoped() {
        assert_eq!(KEYCHAIN_SERVICE, "com.qaptr.review.credentials");
    }
}
