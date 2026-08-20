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
    /// A login-item operation failed.
    #[error("login-item {operation} failed with status {code}")]
    LoginItem {
        /// The operation being performed.
        operation: &'static str,
        /// The ServiceManagement error code.
        code: i64,
    },
    /// A local recognition helper could not be started or completed.
    #[error("{operation} helper failed: {message}")]
    Recognition {
        /// The local operation that failed.
        operation: &'static str,
        /// A bounded diagnostic from the helper.
        message: String,
    },
    /// A local recognition helper exceeded its caller-provided deadline.
    #[error("{operation} recognition timed out")]
    RecognitionTimeout {
        /// The local operation that timed out.
        operation: &'static str,
    },
    /// The current target is not macOS.
    #[error("qaptr-macos adapters are only available on macOS")]
    UnsupportedPlatform,
}
