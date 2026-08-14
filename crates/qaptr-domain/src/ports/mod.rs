//! Platform-independent ports used by the Qaptr core.
//!
//! These traits describe domain intent only. They deliberately do not expose
//! operating-system handles, framework errors, image bytes, or provider types.
//! Platform crates translate their native APIs into these small contracts.

pub mod capture;
pub mod context;
pub mod credentials;
pub mod ocr;
pub mod permissions;
pub mod vision;

use crate::Result;

pub use capture::{CapturePort, CaptureRequest, CaptureSample, DisplayId};
pub use context::{AccessibilityContextPort, ContextRequest, ContextSnapshot};
pub use credentials::{CredentialKey, CredentialPort, CredentialValue};
pub use ocr::{OcrPort, OcrResult, TextRegion};
pub use permissions::{Permission, PermissionPort, PermissionState};
pub use vision::{VisionFinding, VisionKind, VisionPort, VisionResult};

/// The result of a port operation that may have produced incomplete data.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PortOutcome<T> {
    /// The operation completed with a complete value.
    Complete(T),
    /// The operation completed with a value that is explicitly incomplete.
    Partial(T),
}

impl<T> PortOutcome<T> {
    /// Returns whether this outcome is incomplete.
    pub const fn is_partial(&self) -> bool {
        matches!(self, Self::Partial(_))
    }

    /// Returns the contained value, discarding the completeness marker.
    pub fn into_inner(self) -> T {
        match self {
            Self::Complete(value) | Self::Partial(value) => value,
        }
    }
}

/// The common result type for all platform ports.
pub type PortResult<T> = Result<PortOutcome<T>>;

/// Registers Qaptr as a login item and reports its current state.
pub trait LoginItemPort {
    /// Reads whether Qaptr is registered to start at login.
    fn status(&self) -> PortResult<LoginItemState>;

    /// Requests the desired registration state.
    fn set_enabled(&self, enabled: bool) -> PortResult<LoginItemState>;
}

/// The registration state of the Qaptr login item.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LoginItemState {
    /// The login item is registered.
    Enabled,
    /// The login item is not registered.
    Disabled,
}
