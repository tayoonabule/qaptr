//! Read-only TCC status queries and explicit permission requests.

#![allow(unsafe_code)]

use std::path::{Path, PathBuf};

use core_foundation::base::TCFType;
use core_foundation::boolean::CFBoolean;
use core_foundation::dictionary::CFDictionary;
use core_foundation::string::CFString;
use core_foundation_sys::base::Boolean;
use core_foundation_sys::string::CFStringRef;
use qaptr_domain::DomainError;
use qaptr_domain::ports::permissions::{Permission, PermissionPort, PermissionState};
use qaptr_domain::ports::{PortOutcome, PortResult};
use rusqlite::{Connection, OpenFlags, OptionalExtension};

use crate::error::MacosError;

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    static kAXTrustedCheckOptionPrompt: CFStringRef;
    fn AXIsProcessTrusted() -> Boolean;
    fn AXIsProcessTrustedWithOptions(options: *const std::ffi::c_void) -> Boolean;
}

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGPreflightScreenCaptureAccess() -> bool;
    fn CGRequestScreenCaptureAccess() -> bool;
}

const SCREEN_CAPTURE_SERVICE: &str = "kTCCServiceScreenCapture";
const ACCESSIBILITY_SERVICE: &str = "kTCCServiceAccessibility";

/// A macOS permission adapter bound to one application bundle identifier.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MacPermissions {
    bundle_identifier: String,
}

impl MacPermissions {
    /// Creates an adapter for a bundle identifier used as the TCC client key.
    pub fn new(bundle_identifier: impl Into<String>) -> Result<Self, MacosError> {
        let bundle_identifier = bundle_identifier.into();
        if bundle_identifier.is_empty() {
            return Err(MacosError::MissingBundleIdentifier);
        }
        Ok(Self { bundle_identifier })
    }

    /// Returns the bundle identifier used for TCC lookup.
    #[must_use]
    pub fn bundle_identifier(&self) -> &str {
        &self.bundle_identifier
    }

    /// Reads permission state without opening a consent prompt.
    pub fn state_value(&self, permission: Permission) -> Result<PermissionState, MacosError> {
        let granted_by_public_api = match permission {
            Permission::ScreenCapture => screen_capture_preflight(),
            Permission::AccessibilityContext => accessibility_preflight(),
        };
        if granted_by_public_api {
            return Ok(PermissionState::Granted);
        }

        let service = service_name(permission);
        let database = tcc_database_path()?;
        match query_tcc_state(&database, service, &self.bundle_identifier) {
            Ok(Some(auth_value)) => Ok(auth_value_to_state(auth_value, false)),
            Ok(None) => Ok(PermissionState::NotDetermined),
            Err(_) => Ok(PermissionState::Denied),
        }
    }

    /// Requests permission through the native API, then reports its state.
    ///
    /// Production onboarding calls this explicitly. The read-only [`Self::state_value`]
    /// method is used by status surfaces and by all hermetic tests.
    pub fn request_value(&self, permission: Permission) -> Result<PermissionState, MacosError> {
        match permission {
            Permission::ScreenCapture => {
                let _ = request_screen_capture();
            }
            Permission::AccessibilityContext => request_accessibility(),
        }
        self.state_value(permission)
    }
}

impl PermissionPort for MacPermissions {
    fn state(&self, permission: Permission) -> PortResult<PermissionState> {
        self.state_value(permission)
            .map(PortOutcome::Complete)
            .map_err(|_| DomainError::Denied {
                operation: "permission state",
            })
    }

    fn request(&self, permission: Permission) -> PortResult<PermissionState> {
        self.request_value(permission)
            .map(PortOutcome::Complete)
            .map_err(|_| DomainError::Denied {
                operation: "permission request",
            })
    }
}

fn service_name(permission: Permission) -> &'static str {
    match permission {
        Permission::ScreenCapture => SCREEN_CAPTURE_SERVICE,
        Permission::AccessibilityContext => ACCESSIBILITY_SERVICE,
    }
}

fn tcc_database_path() -> Result<PathBuf, MacosError> {
    let home = std::env::var_os("HOME").ok_or(MacosError::MissingHomeDirectory)?;
    Ok(Path::new(&home).join("Library/Application Support/com.apple.TCC/TCC.db"))
}

fn query_tcc_state(
    database: &Path,
    service: &str,
    client: &str,
) -> Result<Option<i64>, MacosError> {
    let connection = Connection::open_with_flags(
        database,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|error| MacosError::TccDatabase(error.to_string()))?;
    connection
        .query_row(
            "SELECT auth_value FROM access WHERE service = ?1 AND client = ?2 ORDER BY last_modified DESC LIMIT 1",
            (service, client),
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| MacosError::TccDatabase(error.to_string()))
}

fn auth_value_to_state(auth_value: i64, public_api_granted: bool) -> PermissionState {
    match (auth_value, public_api_granted) {
        (2, true) => PermissionState::Granted,
        (2, false) => PermissionState::Denied,
        (0, _) => PermissionState::Denied,
        _ => PermissionState::NotDetermined,
    }
}

#[allow(unsafe_code)]
fn screen_capture_preflight() -> bool {
    unsafe { CGPreflightScreenCaptureAccess() }
}

#[allow(unsafe_code)]
fn request_screen_capture() -> bool {
    unsafe { CGRequestScreenCaptureAccess() }
}

#[allow(unsafe_code)]
fn accessibility_preflight() -> bool {
    unsafe { AXIsProcessTrusted() != 0 }
}

#[allow(unsafe_code)]
fn request_accessibility() {
    let key = unsafe { CFString::wrap_under_get_rule(kAXTrustedCheckOptionPrompt) };
    let options: CFDictionary<CFString, CFBoolean> =
        CFDictionary::from_CFType_pairs(&[(key, CFBoolean::from(true))]);
    unsafe {
        let _ = AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef().cast());
    }
}

#[cfg(test)]
mod tests {
    use super::{PermissionState, auth_value_to_state};

    #[test]
    fn tcc_auth_values_fail_closed() {
        assert_eq!(auth_value_to_state(2, true), PermissionState::Granted);
        assert_eq!(auth_value_to_state(2, false), PermissionState::Denied);
        assert_eq!(auth_value_to_state(0, false), PermissionState::Denied);
        assert_eq!(
            auth_value_to_state(1, false),
            PermissionState::NotDetermined
        );
    }
}
