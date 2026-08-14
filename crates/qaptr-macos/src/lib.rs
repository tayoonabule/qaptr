//! Native macOS adapters for Qaptr's platform ports.
//!
//! This crate is review-app-only. The capture helper must not link it, construct
//! its credential adapter, access the Keychain, or call any private-key method.
//! Under KTD6, the helper receives only public generation material through the
//! vault hand-off. The review app alone owns Keychain credentials and private
//! generation keys, permission requests, and login-item registration.
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
#[cfg(target_os = "macos")]
mod ocr;
#[cfg(target_os = "macos")]
mod permissions;
#[cfg(target_os = "macos")]
mod recognition;
#[cfg(target_os = "macos")]
mod vision;

pub use error::MacosError;

#[cfg(target_os = "macos")]
pub use credentials::{KEYCHAIN_SERVICE, MacCredentials};
#[cfg(target_os = "macos")]
pub use login_item::MacLoginItem;
#[cfg(target_os = "macos")]
pub use ocr::MacOcr;
#[cfg(target_os = "macos")]
pub use permissions::MacPermissions;
#[cfg(target_os = "macos")]
pub use vision::MacVision;
