//! Local recognition composition and the one canonical geometry mapping.

use qaptr_domain::ports::{OcrPort, OcrResult, VisionPort, VisionResult};
use qaptr_domain::{CaptureId, DomainError, NormalizedRect, Result};

use crate::Image;

/// A local recognizer that can inspect the exact RGB image supplied to it.
///
/// U12 requires this interface whenever an image is being prepared. A
/// capture-id-only recognizer is intentionally insufficient because it could
/// inspect a different image than the one being masked. The same interface is
/// called again for the post-mask verification rerun.
pub trait ImageRecognizer: Send + Sync {
    /// Recognizes one exact in-memory image without network access.
    fn recognize_image(&self, image: &Image) -> Result<RecognitionResult>;
}

/// The four orientations supported by the U9 mapping contract.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ImageOrientation {
    /// No rotation or reflection.
    Up,
    /// A 180-degree clockwise rotation.
    Down,
    /// A 90-degree counter-clockwise rotation.
    Left,
    /// A 90-degree clockwise rotation.
    Right,
}

/// A rectangle in top-left-origin pixel coordinates.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PixelRect {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

impl PixelRect {
    /// Returns the left coordinate.
    pub const fn x(self) -> u32 {
        self.x
    }

    /// Returns the top coordinate.
    pub const fn y(self) -> u32 {
        self.y
    }

    /// Returns the pixel width.
    pub const fn width(self) -> u32 {
        self.width
    }

    /// Returns the pixel height.
    pub const fn height(self) -> u32 {
        self.height
    }
}

/// Maps Vision's lower-left normalized rectangle to a top-left pixel
/// rectangle. This is the only coordinate mapping used by recognition and
/// later masking, so detection and masking cannot accumulate different
/// rounding or orientation rules.
pub fn map_normalized_rect(
    rect: NormalizedRect,
    image_width: u32,
    image_height: u32,
    orientation: ImageOrientation,
) -> Result<PixelRect> {
    if image_width == 0 {
        return Err(DomainError::InvalidDimension {
            kind: "image width",
        });
    }
    if image_height == 0 {
        return Err(DomainError::InvalidDimension {
            kind: "image height",
        });
    }

    let corners = [
        transform_point(rect.x(), rect.y(), orientation),
        transform_point(rect.x() + rect.width(), rect.y(), orientation),
        transform_point(rect.x(), rect.y() + rect.height(), orientation),
        transform_point(
            rect.x() + rect.width(),
            rect.y() + rect.height(),
            orientation,
        ),
    ];
    let min_x = corners.iter().map(|point| point.0).fold(1.0_f32, f32::min);
    let max_x = corners.iter().map(|point| point.0).fold(0.0_f32, f32::max);
    let min_y = corners.iter().map(|point| point.1).fold(1.0_f32, f32::min);
    let max_y = corners.iter().map(|point| point.1).fold(0.0_f32, f32::max);
    let (output_width, output_height) = match orientation {
        ImageOrientation::Left | ImageOrientation::Right => (image_height, image_width),
        ImageOrientation::Up | ImageOrientation::Down => (image_width, image_height),
    };

    let left = (min_x * output_width as f32).floor() as u32;
    let right = (max_x * output_width as f32).ceil() as u32;
    let top = ((1.0 - max_y) * output_height as f32).floor() as u32;
    let bottom = ((1.0 - min_y) * output_height as f32).ceil() as u32;
    Ok(PixelRect {
        x: left.min(output_width),
        y: top.min(output_height),
        width: right
            .min(output_width)
            .saturating_sub(left.min(output_width)),
        height: bottom
            .min(output_height)
            .saturating_sub(top.min(output_height)),
    })
}

fn transform_point(x: f32, y: f32, orientation: ImageOrientation) -> (f32, f32) {
    match orientation {
        ImageOrientation::Up => (x, y),
        ImageOrientation::Down => (1.0 - x, 1.0 - y),
        ImageOrientation::Left => (y, 1.0 - x),
        ImageOrientation::Right => (1.0 - y, x),
    }
}

/// The combined local findings for one capture.
#[derive(Clone, Debug, PartialEq)]
pub struct RecognitionResult {
    ocr: OcrResult,
    vision: VisionResult,
    partial: bool,
    source_image_hash: Option<crate::ImageHash>,
}

impl RecognitionResult {
    /// Creates a complete combined result from OCR and Vision findings.
    pub fn new(ocr: OcrResult, vision: VisionResult) -> Self {
        Self {
            ocr,
            vision,
            partial: false,
            source_image_hash: None,
        }
    }

    /// Creates a complete result explicitly bound to one exact image.
    pub fn for_image(ocr: OcrResult, vision: VisionResult, image: &Image) -> Self {
        Self {
            ocr,
            vision,
            partial: false,
            source_image_hash: Some(crate::ImageHash::of(image)),
        }
    }

    /// Creates a partial combined result for a recognizer that could not finish.
    pub fn partial(ocr: OcrResult, vision: VisionResult) -> Self {
        Self {
            ocr,
            vision,
            partial: true,
            source_image_hash: None,
        }
    }

    /// Returns OCR findings.
    pub const fn ocr(&self) -> &OcrResult {
        &self.ocr
    }

    /// Returns face and barcode findings.
    pub const fn vision(&self) -> &VisionResult {
        &self.vision
    }

    /// Returns whether either port reported an explicitly partial result.
    pub const fn is_partial(&self) -> bool {
        self.partial
    }

    /// Returns the image hash supplied by an image-bound recognition call.
    pub const fn source_image_hash(&self) -> Option<crate::ImageHash> {
        self.source_image_hash
    }
}

/// Runs OCR and visual detection for one capture without any network access.
pub fn recognize<O, V>(ocr: &O, vision: &V, capture: &CaptureId) -> Result<RecognitionResult>
where
    O: OcrPort,
    V: VisionPort,
{
    let ocr_result = ocr.recognize(capture)?;
    let vision_result = vision.detect(capture)?;
    let partial = ocr_result.is_partial() || vision_result.is_partial();
    Ok(RecognitionResult {
        ocr: ocr_result.into_inner(),
        vision: vision_result.into_inner(),
        partial,
        source_image_hash: None,
    })
}

#[cfg(test)]
mod tests {
    use super::{ImageOrientation, map_normalized_rect};
    use qaptr_domain::NormalizedRect;

    fn rect() -> NormalizedRect {
        NormalizedRect::new(0.25, 0.25, 0.25, 0.25).expect("test geometry is valid")
    }

    #[test]
    fn maps_up_to_hand_computed_pixels() {
        assert_eq!(
            map_normalized_rect(rect(), 100, 80, ImageOrientation::Up)
                .expect("mapping should succeed"),
            super::PixelRect {
                x: 25,
                y: 40,
                width: 25,
                height: 20,
            }
        );
    }

    #[test]
    fn maps_down_to_hand_computed_pixels() {
        assert_eq!(
            map_normalized_rect(rect(), 100, 80, ImageOrientation::Down)
                .expect("mapping should succeed"),
            super::PixelRect {
                x: 50,
                y: 20,
                width: 25,
                height: 20,
            }
        );
    }

    #[test]
    fn maps_left_and_right_with_swapped_dimensions() {
        assert_eq!(
            map_normalized_rect(rect(), 100, 80, ImageOrientation::Left)
                .expect("mapping should succeed"),
            super::PixelRect {
                x: 20,
                y: 25,
                width: 20,
                height: 25,
            }
        );
        assert_eq!(
            map_normalized_rect(rect(), 100, 80, ImageOrientation::Right)
                .expect("mapping should succeed"),
            super::PixelRect {
                x: 40,
                y: 50,
                width: 20,
                height: 25,
            }
        );
    }
}
