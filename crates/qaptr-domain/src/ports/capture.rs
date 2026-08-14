//! The screen-capture port.

use crate::{CaptureId, DomainError, Result};

use super::PortResult;

/// A stable identifier for a display selected by the person.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct DisplayId(String);

impl DisplayId {
    /// Creates a display identifier, rejecting an empty value.
    pub fn new(value: impl Into<String>) -> Result<Self> {
        let value = value.into();
        if value.is_empty() {
            return Err(DomainError::EmptyId { kind: "display" });
        }
        Ok(Self(value))
    }

    /// Returns the display identifier as text.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Describes one requested, downscaled capture.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CaptureRequest {
    display: DisplayId,
    max_width: u32,
    max_height: u32,
}

impl CaptureRequest {
    /// Creates a request for one display and a positive output size.
    pub fn new(display: DisplayId, max_width: u32, max_height: u32) -> Result<Self> {
        if max_width == 0 {
            return Err(DomainError::InvalidDimension {
                kind: "capture width",
            });
        }
        if max_height == 0 {
            return Err(DomainError::InvalidDimension {
                kind: "capture height",
            });
        }
        Ok(Self {
            display,
            max_width,
            max_height,
        })
    }

    /// Returns the selected display.
    pub fn display(&self) -> &DisplayId {
        &self.display
    }

    /// Returns the requested maximum width.
    pub const fn max_width(&self) -> u32 {
        self.max_width
    }

    /// Returns the requested maximum height.
    pub const fn max_height(&self) -> u32 {
        self.max_height
    }
}

/// Metadata for a captured frame. Image bytes remain outside the domain crate.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CaptureSample {
    id: CaptureId,
    display: DisplayId,
    width: u32,
    height: u32,
}

impl CaptureSample {
    /// Creates metadata for a captured frame with a positive output size.
    pub fn new(id: CaptureId, display: DisplayId, width: u32, height: u32) -> Result<Self> {
        if width == 0 {
            return Err(DomainError::InvalidDimension {
                kind: "capture width",
            });
        }
        if height == 0 {
            return Err(DomainError::InvalidDimension {
                kind: "capture height",
            });
        }
        Ok(Self {
            id,
            display,
            width,
            height,
        })
    }

    /// Returns the capture identifier used by later local processing ports.
    pub fn id(&self) -> &CaptureId {
        &self.id
    }

    /// Returns the display from which the sample was taken.
    pub fn display(&self) -> &DisplayId {
        &self.display
    }

    /// Returns the output width.
    pub const fn width(&self) -> u32 {
        self.width
    }

    /// Returns the output height.
    pub const fn height(&self) -> u32 {
        self.height
    }
}

/// Captures one frame at the scheduled instant.
pub trait CapturePort {
    /// Captures one selected display at the requested bounded size.
    fn capture(&self, request: &CaptureRequest) -> PortResult<CaptureSample>;
}

/// Short alias for callers that prefer the domain noun.
pub use CapturePort as Capture;
