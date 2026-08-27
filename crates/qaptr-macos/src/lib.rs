//! Native macOS adapters for Qaptr's platform ports.
//!
//! Native macOS adapters for local credentials, image recognition, and
//! login-item integration.
//!
//! The default test suite is hermetic: Keychain writes, login-item mutations,
//! and permission prompts are confined to ignored OS-integration tests. The
//! permission status adapter itself never prompts while reading state.

#![cfg_attr(not(target_os = "macos"), allow(dead_code))]

mod error;

#[cfg(target_os = "macos")]
mod credentials;
#[cfg(target_os = "macos")]
mod login_item;

pub use error::MacosError;

#[cfg(target_os = "macos")]
pub use credentials::{KEYCHAIN_SERVICE, MacCredentials};
#[cfg(target_os = "macos")]
pub use login_item::MacLoginItem;
