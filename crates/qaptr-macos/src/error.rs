//! Errors raised by the native macOS adapters.

use thiserror::Error;

/// An error produced while crossing a macOS boundary.
#[derive(Debug, Error)]
pub enum MacosError {
    /// A Keychain operation failed.
    #[error("keychain {operation} failed with status {code}: {message}")]
    Keychain {
        /// The operation being performed.
        operation: &'static str,
        /// The Security framework status code.
        code: i32,
        /// The system's human-readable description, when available.
        message: String,
    },
    /// A Keychain item was not valid UTF-8.
    #[error("keychain {operation} returned a non-UTF-8 value")]
    InvalidCredentialEncoding {
        /// The operation being performed.
        operation: &'static str,
    },
    /// The current process could not be associated with a TCC client.
    #[error("the macOS bundle identifier is missing")]
    MissingBundleIdentifier,
    /// The current process has no home directory for the per-user TCC database.
    #[error("the user's home directory is missing")]
    MissingHomeDirectory,
    /// The TCC database could not be queried.
    #[error("TCC status query failed: {0}")]
    TccDatabase(String),
    /// A login-item operation failed.
    #[error("login-item {operation} failed with status {code}")]
    LoginItem {
        /// The operation being performed.
        operation: &'static str,
        /// The ServiceManagement error code.
        code: i64,
    },
    /// The current target is not macOS.
    #[error("qaptr-macos adapters are only available on macOS")]
    UnsupportedPlatform,
}
