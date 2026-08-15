//! Machine-checkable evidence that U10 covered every reported detection.
//!
//! A proof is intentionally scoped to the supplied recognizer detections. It
//! does not claim that the recognizers found every sensitive value in an image.
//! For an image payload, U12 also records a rerun over the exact masked bytes;
//! that rerun proves removal of originally detected regions, not discovery of
//! material missed by the published U9 recall limit.

use thiserror::Error;

use crate::PixelRect;
use crate::mask::{DetectionKind, DetectionSet, Image, ImageHash, MASK_COLOR, MappedDetection};

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
    image_hash: ImageHash,
    entries: Vec<CoverageEntry>,
    covered_pixel_count: u64,
    recognition_verification: Option<RecognitionVerification>,
}

/// Evidence from rerunning recognition over the masked output.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RecognitionVerification {
    masked_image_hash: ImageHash,
    rerun_detected_region_count: usize,
    residual_detected_region_count: usize,
}

impl RecognitionVerification {
    /// Returns the hash of the masked image that was checked.
    pub const fn masked_image_hash(self) -> ImageHash {
        self.masked_image_hash
    }

    /// Returns the number of regions reported by the rerun recognizer.
    pub const fn rerun_detected_region_count(self) -> usize {
        self.rerun_detected_region_count
    }

    /// Returns the number of originally detected regions still recognizable.
    pub const fn residual_detected_region_count(self) -> usize {
        self.residual_detected_region_count
    }

    /// Returns whether the rerun found no originally detected sensitive region.
    pub const fn has_no_residual_detected_regions(self) -> bool {
        self.residual_detected_region_count == 0
    }
}

impl CoverageProof {
    pub(crate) fn new(image: &Image, detections: &DetectionSet) -> Result<Self, CoverageError> {
        let image_width = image.width();
        let image_height = image.height();
        if image_width == 0 || image_height == 0 {
            return Err(CoverageError::InvalidImageDimensions {
                width: image_width,
                height: image_height,
            });
        }
        let mut entries = Vec::with_capacity(detections.detections().len());
        let mut covered_pixel_count = 0_u64;
        for detection in detections.detections() {
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
            image_hash: ImageHash::of(image),
            entries,
            covered_pixel_count,
            recognition_verification: None,
        })
    }

    pub(crate) fn bind_masked_image(&mut self, image: &Image) {
        self.image_hash = ImageHash::of(image);
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
        detections: &DetectionSet,
    ) -> Result<(), CoverageError> {
        if self.image_width != masked_image.width() || self.image_height != masked_image.height() {
            return Err(CoverageError::ImageDimensionsMismatch {
                proof_width: self.image_width,
                proof_height: self.image_height,
                image_width: masked_image.width(),
                image_height: masked_image.height(),
            });
        }
        if self.image_hash != ImageHash::of(masked_image) {
            return Err(CoverageError::ImageHashMismatch {
                expected: self.image_hash,
                actual: ImageHash::of(masked_image),
            });
        }
        self.verify_detections(detections.detections())?;
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

    /// Returns the masked-output recognition evidence, when a rerun was made.
    pub const fn recognition_verification(&self) -> Option<RecognitionVerification> {
        self.recognition_verification
    }

    pub(crate) fn verify_masked_recognition(
        &mut self,
        masked_image: &Image,
        rerun: &DetectionSet,
    ) -> Result<(), CoverageError> {
        let masked_image_hash = ImageHash::of(masked_image);
        if rerun.image_hash() != masked_image_hash {
            return Err(CoverageError::ImageHashMismatch {
                expected: masked_image_hash,
                actual: rerun.image_hash(),
            });
        }
        let mut residual_detected_region_count = 0;
        for rerun_detection in rerun.detections() {
            if self.entries.iter().any(|entry| {
                entry.kind == rerun_detection.kind()
                    && rectangles_overlap(entry.rect, rerun_detection.rect())
            }) {
                residual_detected_region_count += 1;
            }
        }
        if residual_detected_region_count != 0 {
            return Err(CoverageError::ResidualDetection {
                count: residual_detected_region_count,
            });
        }
        self.recognition_verification = Some(RecognitionVerification {
            masked_image_hash,
            rerun_detected_region_count: rerun.detections().len(),
            residual_detected_region_count,
        });
        Ok(())
    }
}

fn rectangles_overlap(first: PixelRect, second: PixelRect) -> bool {
    let first_right = first.x().saturating_add(first.width());
    let first_bottom = first.y().saturating_add(first.height());
    let second_right = second.x().saturating_add(second.width());
    let second_bottom = second.y().saturating_add(second.height());
    first.x() < second_right
        && second.x() < first_right
        && first.y() < second_bottom
        && second.y() < first_bottom
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
    /// The proof or rerun was checked against different image bytes.
    #[error("coverage proof is bound to image hash {expected}, but received {actual}")]
    ImageHashMismatch {
        /// Hash recorded by the proof.
        expected: ImageHash,
        /// Hash supplied to verification.
        actual: ImageHash,
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
    /// The masked image still produced a detection overlapping an original region.
    #[error("masked image still has {count} recognizable previously detected region(s)")]
    ResidualDetection {
        /// Number of residual regions found by the rerun.
        count: usize,
    },
    /// Proof area arithmetic overflowed.
    #[error("coverage area arithmetic overflowed")]
    ArithmeticOverflow,
}

#[cfg(test)]
mod tests {
    use crate::ImageOrientation;
    use crate::map_normalized_rect;
    use crate::mask::{
        DetectionKind, DetectionSet, Image, MASK_COLOR, MappedDetection, mask_image,
    };
    use qaptr_domain::NormalizedRect;

    #[test]
    fn empty_detection_set_is_a_valid_honest_proof() {
        let image = Image::solid(2, 2, [9, 8, 7]).expect("fixture image should be valid");
        let detections = DetectionSet::for_image(&image, Vec::new());
        let masked = mask_image(&image, &detections).expect("empty masking should succeed");
        assert_eq!(masked.proof().detected_region_count(), 0);
        assert_eq!(masked.proof().covered_pixel_count(), 0);
        assert_eq!(masked.image().pixel(0, 0), Some([9, 8, 7]));
        assert!(masked.verify(&detections).is_ok());
    }

    #[test]
    fn proof_matches_mapped_detection_and_pixels() {
        let image = Image::solid(8, 8, [255, 255, 255]).expect("fixture image should be valid");
        let normalized =
            NormalizedRect::new(0.25, 0.25, 0.25, 0.25).expect("fixture geometry should be valid");
        let rect = map_normalized_rect(normalized, 8, 8, ImageOrientation::Up)
            .expect("mapping should succeed");
        let detections = [MappedDetection::new(DetectionKind::Text, rect)];
        let detection_set = DetectionSet::for_image(&image, detections.to_vec());
        let masked = mask_image(&image, &detection_set).expect("masking should succeed");
        assert_eq!(masked.proof().entries()[0].rect(), rect);
        assert_eq!(masked.image().pixel(2, 4), Some(MASK_COLOR));
        assert!(masked.proof().verify_detections(&detections).is_ok());
        assert!(masked.verify(&detection_set).is_ok());
    }
}
