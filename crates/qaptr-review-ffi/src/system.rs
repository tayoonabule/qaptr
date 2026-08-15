//! Permission and login-item queries for the review app's onboarding and
//! settings surfaces.
//!
//! # Invariants
//!
//! - Every function reports state or performs the single explicit request the
//!   caller asked for. No function silently prompts when the caller only
//!   asked to read state.
//! - Permission and login-item codes are a small fixed integer contract
//!   documented at each function so Swift needs no shared header.

use qaptr_domain::ports::LoginItemState;
use qaptr_domain::ports::permissions::Permission;
use qaptr_macos::{MacLoginItem, MacPermissions};

use crate::support::read_utf8;

const STATE_GRANTED: i32 = 1;
const STATE_DENIED: i32 = 0;
const STATE_NOT_DETERMINED: i32 = -1;
const STATE_ERROR: i32 = -2;

const PERMISSION_SCREEN_CAPTURE: i32 = 0;
const PERMISSION_ACCESSIBILITY_CONTEXT: i32 = 1;

fn permission_from_code(code: i32) -> Option<Permission> {
    match code {
        PERMISSION_SCREEN_CAPTURE => Some(Permission::ScreenCapture),
        PERMISSION_ACCESSIBILITY_CONTEXT => Some(Permission::AccessibilityContext),
        _ => None,
    }
}

fn permission_state_code(
    result: Result<qaptr_domain::ports::PermissionState, qaptr_macos::MacosError>,
) -> i32 {
    match result {
        Ok(qaptr_domain::ports::PermissionState::Granted) => STATE_GRANTED,
        Ok(qaptr_domain::ports::PermissionState::Denied) => STATE_DENIED,
        Ok(qaptr_domain::ports::PermissionState::NotDetermined) => STATE_NOT_DETERMINED,
        Err(_) => STATE_ERROR,
    }
}

/// Reads a permission's current state without prompting.
///
/// `permission_code` is `0` for Screen Recording, `1` for Accessibility
/// context. Returns `1` (granted), `0` (denied), `-1` (not determined), or
/// `-2` on an unresolvable bundle identifier or query failure.
///
/// # Safety
///
/// `bundle_identifier` must reference `bundle_identifier_len` readable bytes
/// for the duration of the call, or be null when the length is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_permission_state(
    bundle_identifier: *const u8,
    bundle_identifier_len: usize,
    permission_code: i32,
) -> i32 {
    let Some(bundle_identifier) = (unsafe { read_utf8(bundle_identifier, bundle_identifier_len) })
    else {
        return STATE_ERROR;
    };
    let Some(permission) = permission_from_code(permission_code) else {
        return STATE_ERROR;
    };
    let Ok(adapter) = MacPermissions::new(bundle_identifier) else {
        return STATE_ERROR;
    };
    permission_state_code(adapter.state_value(permission))
}

/// Requests a permission through the native prompt, then reports its state.
///
/// See [`qaptr_permission_state`] for the code contract. Onboarding is the
/// only caller expected to invoke this; settings and status surfaces should
/// use [`qaptr_permission_state`] instead so a status glance never re-prompts.
///
/// # Safety
///
/// `bundle_identifier` must reference `bundle_identifier_len` readable bytes
/// for the duration of the call, or be null when the length is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_permission_request(
    bundle_identifier: *const u8,
    bundle_identifier_len: usize,
    permission_code: i32,
) -> i32 {
    let Some(bundle_identifier) = (unsafe { read_utf8(bundle_identifier, bundle_identifier_len) })
    else {
        return STATE_ERROR;
    };
    let Some(permission) = permission_from_code(permission_code) else {
        return STATE_ERROR;
    };
    let Ok(adapter) = MacPermissions::new(bundle_identifier) else {
        return STATE_ERROR;
    };
    permission_state_code(adapter.request_value(permission))
}

fn login_item_state_code(result: Result<LoginItemState, qaptr_macos::MacosError>) -> i32 {
    match result {
        Ok(LoginItemState::Enabled) => STATE_GRANTED,
        Ok(LoginItemState::Disabled) => STATE_DENIED,
        Err(_) => STATE_ERROR,
    }
}

/// Reads whether Qaptr is registered to start at login.
///
/// Returns `1` (enabled), `0` (disabled), or `-2` on a query failure.
#[unsafe(no_mangle)]
pub extern "C" fn qaptr_login_item_status() -> i32 {
    login_item_state_code(MacLoginItem::new().status_value())
}

/// Sets login-item registration and returns the state confirmed by the OS.
///
/// `enabled` is `1` to register, `0` to unregister. See
/// [`qaptr_login_item_status`] for the return-code contract.
#[unsafe(no_mangle)]
pub extern "C" fn qaptr_login_item_set_enabled(enabled: i32) -> i32 {
    login_item_state_code(MacLoginItem::new().set_enabled_value(enabled != 0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_permission_code_reports_error_state() {
        let bundle = b"com.qaptr.review";
        let result = unsafe { qaptr_permission_state(bundle.as_ptr(), bundle.len(), 42) };
        assert_eq!(result, STATE_ERROR);
    }

    #[test]
    fn empty_bundle_identifier_reports_error_state() {
        let result =
            unsafe { qaptr_permission_state(std::ptr::null(), 0, PERMISSION_SCREEN_CAPTURE) };
        assert_eq!(result, STATE_ERROR);
    }
}
