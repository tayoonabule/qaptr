//! The permission-state port.

use super::PortResult;

/// A user-visible capability that may be required by Qaptr.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Permission {
    /// Permission to capture the screen.
    ScreenCapture,
    /// Permission to sample temporary accessibility context.
    AccessibilityContext,
}

/// The current state of a permission.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PermissionState {
    /// The capability is available.
    Granted,
    /// The capability was refused or is unavailable.
    Denied,
    /// The person has not made a decision yet.
    NotDetermined,
}

/// Reads and requests user permission state.
pub trait PermissionPort {
    /// Reads current state without prompting.
    fn state(&self, permission: Permission) -> PortResult<PermissionState>;

    /// Requests a permission and returns the resulting state.
    fn request(&self, permission: Permission) -> PortResult<PermissionState>;
}

/// Short alias for callers that prefer the domain noun.
pub use PermissionPort as Permissions;
