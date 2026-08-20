//! Login-item queries for the review app's settings surfaces.
//!
//! # Invariants
//!
//! - Every function reports state or performs the single explicit registration
//!   change the caller asked for.
//! - Login-item codes are a small fixed integer contract documented at each
//!   function so Swift needs no shared header.

use qaptr_domain::ports::LoginItemState;
use qaptr_macos::MacLoginItem;

const STATE_GRANTED: i32 = 1;
const STATE_DENIED: i32 = 0;
const STATE_ERROR: i32 = -2;

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
