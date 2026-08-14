//! `SMAppService` login-item adapter.

#![allow(unsafe_code)]

use qaptr_domain::DomainError;
use qaptr_domain::ports::{LoginItemPort, LoginItemState, PortOutcome, PortResult};

use crate::error::MacosError;

unsafe extern "C" {
    fn qaptr_smappservice_status() -> i64;
    fn qaptr_smappservice_register(error_code: *mut i64) -> i32;
    fn qaptr_smappservice_unregister(error_code: *mut i64) -> i32;
}

const SM_STATUS_NOT_REGISTERED: i64 = 0;
const SM_STATUS_ENABLED: i64 = 1;
const SM_STATUS_REQUIRES_APPROVAL: i64 = 2;
const SM_STATUS_NOT_FOUND: i64 = 3;

/// A login-item adapter for the review app's main `SMAppService`.
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
    /// Registering an already-enabled item and unregistering an already-disabled
    /// item are both successful no-ops. This is important because onboarding and
    /// settings may repeat the same request after a process restart.
    pub fn set_enabled_value(&self, enabled: bool) -> Result<LoginItemState, MacosError> {
        let current = self.status_value()?;
        if current == desired_state(enabled) {
            return Ok(current);
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
    use super::{LoginItemState, desired_state};

    #[test]
    fn desired_state_is_stable_for_repeated_requests() {
        assert_eq!(desired_state(true), LoginItemState::Enabled);
        assert_eq!(desired_state(false), LoginItemState::Disabled);
    }
}
