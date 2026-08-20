//! `SMAppService` login-item adapter.

#![allow(unsafe_code)]

#[cfg(test)]
use std::ffi::CStr;
#[cfg(test)]
use std::os::raw::c_char;

use qaptr_domain::DomainError;
use qaptr_domain::ports::{LoginItemPort, LoginItemState, PortOutcome, PortResult};

use crate::error::MacosError;

unsafe extern "C" {
    #[cfg(test)]
    fn qaptr_smappservice_identifier() -> *const c_char;
    fn qaptr_smappservice_status() -> i64;
    fn qaptr_smappservice_register(error_code: *mut i64) -> i32;
    fn qaptr_smappservice_unregister(error_code: *mut i64) -> i32;
}

const SM_STATUS_NOT_REGISTERED: i64 = 0;
const SM_STATUS_ENABLED: i64 = 1;
const SM_STATUS_REQUIRES_APPROVAL: i64 = 2;
const SM_STATUS_NOT_FOUND: i64 = 3;

/// A login-item adapter for the packaged `com.qaptr.helper` application.
#[derive(Clone, Copy, Debug, Default)]
pub struct MacLoginItem;

impl MacLoginItem {
    /// Creates an adapter for the current app bundle.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }

    /// Reads the native registration status.
    pub fn status_value(&self) -> Result<LoginItemState, MacosError> {
        match native_status() {
            SM_STATUS_ENABLED => Ok(LoginItemState::Enabled),
            SM_STATUS_NOT_REGISTERED | SM_STATUS_REQUIRES_APPROVAL | SM_STATUS_NOT_FOUND => {
                Ok(LoginItemState::Disabled)
            }
            status => Err(MacosError::LoginItem {
                operation: "status",
                code: status,
            }),
        }
    }

    /// Sets registration state and returns the state confirmed by the OS.
    ///
    /// Unregistering an already-disabled item is a successful no-op. Enabling an
    /// already-enabled item deliberately unregisters and registers again so an
    /// upgrade replaces any stale registration that still points at an older
    /// copy of Qaptr.
    pub fn set_enabled_value(&self, enabled: bool) -> Result<LoginItemState, MacosError> {
        let current = self.status_value()?;
        if !enabled && current == LoginItemState::Disabled {
            return Ok(current);
        }

        if enabled && current == LoginItemState::Enabled {
            let mut error_code = 0_i64;
            let succeeded = unsafe { qaptr_smappservice_unregister(&mut error_code) != 0 };
            if !succeeded && self.status_value()? != LoginItemState::Disabled {
                return Err(MacosError::LoginItem {
                    operation: "unregister stale registration",
                    code: error_code,
                });
            }
        }

        let mut error_code = 0_i64;
        let succeeded = if enabled {
            unsafe { qaptr_smappservice_register(&mut error_code) != 0 }
        } else {
            unsafe { qaptr_smappservice_unregister(&mut error_code) != 0 }
        };

        if !succeeded {
            let confirmed = self.status_value()?;
            if confirmed == desired_state(enabled) {
                return Ok(confirmed);
            }
            return Err(MacosError::LoginItem {
                operation: if enabled { "register" } else { "unregister" },
                code: error_code,
            });
        }

        self.status_value()
    }
}

impl LoginItemPort for MacLoginItem {
    fn status(&self) -> PortResult<LoginItemState> {
        self.status_value()
            .map(PortOutcome::Complete)
            .map_err(|_| DomainError::Denied {
                operation: "login-item status",
            })
    }

    fn set_enabled(&self, enabled: bool) -> PortResult<LoginItemState> {
        self.set_enabled_value(enabled)
            .map(PortOutcome::Complete)
            .map_err(|_| DomainError::Denied {
                operation: "login-item registration",
            })
    }
}

fn desired_state(enabled: bool) -> LoginItemState {
    if enabled {
        LoginItemState::Enabled
    } else {
        LoginItemState::Disabled
    }
}

#[allow(unsafe_code)]
fn native_status() -> i64 {
    unsafe { qaptr_smappservice_status() }
}

#[cfg(test)]
mod tests {
    use super::{CStr, LoginItemState, desired_state, qaptr_smappservice_identifier};

    #[test]
    fn native_service_targets_the_packaged_helper() {
        let identifier = unsafe { CStr::from_ptr(qaptr_smappservice_identifier()) };
        assert_eq!(identifier.to_bytes(), b"com.qaptr.helper");
    }

    #[test]
    fn desired_state_is_stable_for_repeated_requests() {
        assert_eq!(desired_state(true), LoginItemState::Enabled);
        assert_eq!(desired_state(false), LoginItemState::Disabled);
    }
}
