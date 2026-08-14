//! Machine-checkable evidence that U10 covered every reported detection.
//!
//! A proof is intentionally scoped to the supplied recognizer detections. It
//! does not claim that the recognizers found every sensitive value in an image.

use thiserror::Error;

use crate::PixelRect;
use crate::mask::{DetectionKind, Image, MASK_COLOR, MappedDetection};

/// Proof metadata for one recognizer-detected region.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CoverageEntry {
    kind: DetectionKind,
    rect: PixelRect,
    pixel_count: u64,
}

impl CoverageEntry {
    /// Returns the recognizer class recorded in this proof entry.
    pub const fn kind(self) -> DetectionKind {
        self.kind
    }

    /// Returns the exact mapped detection geometry recorded in this proof.
    pub const fn rect(self) -> PixelRect {
        self.rect
    }

    /// Returns the number of original detection pixels that must be masked.
    pub const fn pixel_count(self) -> u64 {
        self.pixel_count
    }
}

/// A proof that every supplied detection was covered in a specific image.
///
/// The proof contains no inferred or unrecognized regions. Its entries are an
/// ordered copy of the detection set, which makes accidental omission or
/// replacement of a detection observable to a verifier.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CoverageProof {
    image_width: u32,
    image_height: u32,
    entries: Vec<CoverageEntry>,
    covered_pixel_count: u64,
}

impl CoverageProof {
    pub(crate) fn new(
        image_width: u32,
        image_height: u32,
        detections: &[MappedDetection],
    ) -> Result<Self, CoverageError> {
        if image_width == 0 || image_height == 0 {
            return Err(CoverageError::InvalidImageDimensions {
                width: image_width,
                height: image_height,
            });
        }
        let mut entries = Vec::with_capacity(detections.len());
        let mut covered_pixel_count = 0_u64;
        for detection in detections {
            let rect = detection.rect();
            validate_rect(rect, image_width, image_height)?;
            let pixel_count = u64::from(rect.width())
                .checked_mul(u64::from(rect.height()))
                .ok_or(CoverageError::ArithmeticOverflow)?;
            covered_pixel_count = covered_pixel_count
                .checked_add(pixel_count)
                .ok_or(CoverageError::ArithmeticOverflow)?;
            entries.push(CoverageEntry {
                kind: detection.kind(),
                rect,
                pixel_count,
            });
        }
        Ok(Self {
            image_width,
            image_height,
            entries,
            covered_pixel_count,
        })
    }

    /// Returns the image width used to produce the proof.
    pub const fn image_width(&self) -> u32 {
        self.image_width
    }

    /// Returns the image height used to produce the proof.
    pub const fn image_height(&self) -> u32 {
        self.image_height
    }

    /// Returns the ordered proof entries, one for each reported detection.
    pub fn entries(&self) -> &[CoverageEntry] {
        &self.entries
    }

    /// Returns the number of detected regions represented by this proof.
    pub fn detected_region_count(&self) -> usize {
        self.entries.len()
    }

    /// Returns the sum of the areas of the reported detection rectangles.
    ///
    /// Overlapping detections are intentionally counted separately here. This
    /// is detection coverage evidence, not an estimate of unique image area.
    pub const fn covered_pixel_count(&self) -> u64 {
        self.covered_pixel_count
    }

    /// Verifies that the proof entries match the detection set exactly.
    pub fn verify_detections(&self, detections: &[MappedDetection]) -> Result<(), CoverageError> {
        if self.entries.len() != detections.len() {
            return Err(CoverageError::DetectionCountMismatch {
                proof: self.entries.len(),
                detections: detections.len(),
            });
        }
        for (index, (entry, detection)) in self.entries.iter().zip(detections).enumerate() {
            if entry.kind != detection.kind() || entry.rect != detection.rect() {
                return Err(CoverageError::DetectionMismatch { index });
            }
        }
        Ok(())
    }

    /// Verifies the proof against both the exact detection set and output pixels.
    pub fn verify(
        &self,
        masked_image: &Image,
        detections: &[MappedDetection],
    ) -> Result<(), CoverageError> {
        if self.image_width != masked_image.width() || self.image_height != masked_image.height() {
            return Err(CoverageError::ImageDimensionsMismatch {
                proof_width: self.image_width,
                proof_height: self.image_height,
                image_width: masked_image.width(),
                image_height: masked_image.height(),
            });
        }
        self.verify_detections(detections)?;
        for (index, entry) in self.entries.iter().enumerate() {
            let rect = entry.rect;
            for y in rect.y()..rect.y() + rect.height() {
                for x in rect.x()..rect.x() + rect.width() {
                    if masked_image.pixel(x, y) != Some(MASK_COLOR) {
                        return Err(CoverageError::UnmaskedPixel { index, x, y });
                    }
                }
            }
        }
        Ok(())
    }
}

fn validate_rect(rect: PixelRect, width: u32, height: u32) -> Result<(), CoverageError> {
    if rect.width() == 0 || rect.height() == 0 {
        return Err(CoverageError::InvalidRegion);
    }
    let right = rect
        .x()
        .checked_add(rect.width())
        .ok_or(CoverageError::ArithmeticOverflow)?;
    let bottom = rect
        .y()
        .checked_add(rect.height())
        .ok_or(CoverageError::ArithmeticOverflow)?;
    if right > width || bottom > height {
        return Err(CoverageError::RegionOutsideImage);
    }
    Ok(())
}

/// Errors produced while validating a coverage proof.
#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum CoverageError {
    /// The proof or image has a zero dimension.
    #[error("coverage image dimensions must be non-zero, got {width}x{height}")]
    InvalidImageDimensions {
        /// The proof image width.
        width: u32,
        /// The proof image height.
        height: u32,
    },
    /// A detection has no pixels to cover.
    #[error("coverage region has zero width or height")]
    InvalidRegion,
    /// A detection is not contained by the image.
    #[error("coverage region lies outside the image")]
    RegionOutsideImage,
    /// Proof and detection lists have different lengths.
    #[error("proof has {proof} detections but input has {detections}")]
    DetectionCountMismatch {
        /// The number of entries in the proof.
        proof: usize,
        /// The number of supplied detections.
        detections: usize,
    },
    /// A proof entry differs from its corresponding detection.
    #[error("proof detection {index} differs from the input detection")]
    DetectionMismatch {
        /// The mismatching detection index.
        index: usize,
    },
    /// Proof and output image dimensions differ.
    #[error("proof image is {proof_width}x{proof_height}, output is {image_width}x{image_height}")]
    ImageDimensionsMismatch {
        /// The width recorded in the proof.
        proof_width: u32,
        /// The height recorded in the proof.
        proof_height: u32,
        /// The width of the output image.
        image_width: u32,
        /// The height of the output image.
        image_height: u32,
    },
    /// An output pixel inside a detected region was not replaced by the mask.
    #[error("detected region {index} leaves pixel ({x}, {y}) unmasked")]
    UnmaskedPixel {
        /// The detection entry containing the unmasked pixel.
        index: usize,
        /// The unmasked pixel's x coordinate.
        x: u32,
        /// The unmasked pixel's y coordinate.
        y: u32,
    },
    /// Proof area arithmetic overflowed.
    #[error("coverage area arithmetic overflowed")]
    ArithmeticOverflow,
}

#[cfg(test)]
mod tests {
    use crate::ImageOrientation;
    use crate::map_normalized_rect;
    use crate::mask::{DetectionKind, Image, MASK_COLOR, MappedDetection, mask_image};
    use qaptr_domain::NormalizedRect;

    #[test]
    fn empty_detection_set_is_a_valid_honest_proof() {
        let image = Image::solid(2, 2, [9, 8, 7]).expect("fixture image should be valid");
        let masked = mask_image(&image, &[]).expect("empty masking should succeed");
        assert_eq!(masked.proof().detected_region_count(), 0);
        assert_eq!(masked.proof().covered_pixel_count(), 0);
        assert_eq!(masked.image().pixel(0, 0), Some([9, 8, 7]));
        assert!(masked.verify(&[]).is_ok());
    }

    #[test]
    fn proof_matches_mapped_detection_and_pixels() {
        let image = Image::solid(8, 8, [255, 255, 255]).expect("fixture image should be valid");
        let normalized =
            NormalizedRect::new(0.25, 0.25, 0.25, 0.25).expect("fixture geometry should be valid");
        let rect = map_normalized_rect(normalized, 8, 8, ImageOrientation::Up)
            .expect("mapping should succeed");
        let detections = [MappedDetection::new(DetectionKind::Text, rect)];
        let masked = mask_image(&image, &detections).expect("masking should succeed");
        assert_eq!(masked.proof().entries()[0].rect(), rect);
        assert_eq!(masked.image().pixel(2, 4), Some(MASK_COLOR));
        assert!(masked.proof().verify_detections(&detections).is_ok());
        assert!(masked.verify(&detections).is_ok());
    }
}
