//! Geometry shared by local recognizers and the later masking pipeline.

use crate::{DomainError, Result};

/// A rectangle in Vision's normalized image coordinate space.
///
/// Coordinates use the image's lower-left origin, matching Apple's Vision
/// framework. The rectangle is intentionally independent of pixel dimensions
/// so the same recognition result can be mapped exactly once by the privacy
/// pipeline.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NormalizedRect {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

impl NormalizedRect {
    /// Creates a rectangle after checking that it is finite and inside the
    /// normalized unit square.
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Result<Self> {
        let valid = [x, y, width, height].into_iter().all(f32::is_finite)
            && (0.0..=1.0).contains(&x)
            && (0.0..=1.0).contains(&y)
            && (0.0..=1.0).contains(&width)
            && (0.0..=1.0).contains(&height)
            && x + width <= 1.0
            && y + height <= 1.0;
        if valid {
            Ok(Self {
                x,
                y,
                width,
                height,
            })
        } else {
            Err(DomainError::InvalidGeometry { kind: "normalized" })
        }
    }

    /// Returns the lower-left x coordinate.
    pub const fn x(self) -> f32 {
        self.x
    }

    /// Returns the lower-left y coordinate.
    pub const fn y(self) -> f32 {
        self.y
    }

    /// Returns the normalized width.
    pub const fn width(self) -> f32 {
        self.width
    }

    /// Returns the normalized height.
    pub const fn height(self) -> f32 {
        self.height
    }
}
