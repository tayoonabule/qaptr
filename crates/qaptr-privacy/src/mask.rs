//! Deterministic, irreversible masking over U9's mapped pixel geometry.
//!
//! The masking API deliberately accepts [`MappedDetection`] values rather than
//! normalized rectangles. Callers that start with a [`RecognitionResult`] must
//! use [`map_recognized_detections`], which delegates every coordinate conversion
//! to U9's [`crate::map_normalized_rect`] function. Masking never recomputes a
//! scale factor or an orientation transform.

use std::fmt;

use qaptr_domain::ports::vision::VisionKind;
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::coverage::{CoverageError, CoverageProof};
use crate::{ImageOrientation, PixelRect, RecognitionResult, map_normalized_rect};

/// The opaque RGB value written over every masked pixel.
///
/// A constant opaque fill is intentional. Blurring and translucent overlays
/// can preserve recoverable information, while an opaque replacement cannot.
pub const MASK_COLOR: [u8; 3] = [0, 0, 0];

/// Number of pixels added around each mapped detection on every side.
pub const DILATION_PIXELS: u32 = 1;

/// An RGB image held only for the duration of local privacy preparation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Image {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

/// A cryptographic identity for the exact RGB image bytes used by recognition.
///
/// The hash covers the dimensions and row-major RGB bytes. It is provenance,
/// not a claim that recognition detects every sensitive value.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct ImageHash([u8; 32]);

impl ImageHash {
    /// Computes the identity of an image from its exact dimensions and bytes.
    pub fn of(image: &Image) -> Self {
        let mut hasher = Sha256::new();
        hasher.update(image.width.to_be_bytes());
        hasher.update(image.height.to_be_bytes());
        hasher.update(&image.pixels);
        Self(hasher.finalize().into())
    }

    /// Returns the raw SHA-256 digest.
    pub const fn as_bytes(self) -> [u8; 32] {
        self.0
    }
}

impl fmt::Display for ImageHash {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        for byte in self.0 {
            write!(formatter, "{byte:02x}")?;
        }
        Ok(())
    }
}

impl Image {
    /// Creates an RGB image from an exactly sized byte buffer.
    pub fn new(width: u32, height: u32, pixels: Vec<u8>) -> Result<Self, MaskError> {
        if width == 0 || height == 0 {
            return Err(MaskError::InvalidImageDimensions { width, height });
        }
        let expected = expected_byte_len(width, height)?;
        if pixels.len() != expected {
            return Err(MaskError::InvalidPixelBuffer {
                expected,
                actual: pixels.len(),
            });
        }
        Ok(Self {
            width,
            height,
            pixels,
        })
    }

    /// Creates a solid-color RGB image, useful for deterministic fixtures.
    pub fn solid(width: u32, height: u32, color: [u8; 3]) -> Result<Self, MaskError> {
        let pixel_count = u64::from(width)
            .checked_mul(u64::from(height))
            .ok_or(MaskError::ArithmeticOverflow)?;
        let byte_count = pixel_count
            .checked_mul(3)
            .ok_or(MaskError::ArithmeticOverflow)?;
        let capacity = usize::try_from(byte_count).map_err(|_| MaskError::ArithmeticOverflow)?;
        let mut pixels = Vec::with_capacity(capacity);
        for _ in 0..pixel_count {
            pixels.extend_from_slice(&color);
        }
        Self::new(width, height, pixels)
    }

    /// Returns the image width in pixels.
    pub const fn width(&self) -> u32 {
        self.width
    }

    /// Returns the image height in pixels.
    pub const fn height(&self) -> u32 {
        self.height
    }

    /// Returns the owned RGB bytes in row-major, top-left-origin order.
    pub fn pixels(&self) -> &[u8] {
        &self.pixels
    }

    /// Returns one RGB pixel, or `None` for coordinates outside the image.
    pub fn pixel(&self, x: u32, y: u32) -> Option<[u8; 3]> {
        if x >= self.width || y >= self.height {
            return None;
        }
        let offset = pixel_offset(self.width, x, y).ok()?;
        Some([
            self.pixels[offset],
            self.pixels[offset + 1],
            self.pixels[offset + 2],
        ])
    }

    fn set_pixel(&mut self, x: u32, y: u32, color: [u8; 3]) -> Result<(), MaskError> {
        let offset = pixel_offset(self.width, x, y)?;
        let end = offset.checked_add(3).ok_or(MaskError::ArithmeticOverflow)?;
        let length = self.pixels.len();
        if end > length {
            return Err(MaskError::InvalidPixelBuffer {
                expected: length,
                actual: length,
            });
        }
        let destination = &mut self.pixels[offset..end];
        destination.copy_from_slice(&color);
        Ok(())
    }
}

/// A detected sensitive region after U9's canonical mapping into pixel space.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MappedDetection {
    kind: DetectionKind,
    rect: PixelRect,
}

/// The ordered detection set produced for one exact image.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DetectionSet {
    image_hash: ImageHash,
    detections: Vec<MappedDetection>,
}

impl DetectionSet {
    /// Creates a detection set bound to an image hash.
    pub fn new(image_hash: ImageHash, detections: Vec<MappedDetection>) -> Self {
        Self {
            image_hash,
            detections,
        }
    }

    /// Binds an existing mapped detection list to the exact image bytes.
    pub fn for_image(image: &Image, detections: impl Into<Vec<MappedDetection>>) -> Self {
        Self::new(ImageHash::of(image), detections.into())
    }

    /// Returns the hash of the image recognized for this set.
    pub const fn image_hash(&self) -> ImageHash {
        self.image_hash
    }

    /// Returns the ordered mapped detections.
    pub fn detections(&self) -> &[MappedDetection] {
        &self.detections
    }
}

impl MappedDetection {
    /// Creates a mapped detection from U9's [`PixelRect`].
    pub const fn new(kind: DetectionKind, rect: PixelRect) -> Self {
        Self { kind, rect }
    }

    /// Returns the recognizer class that produced this detection.
    pub const fn kind(self) -> DetectionKind {
        self.kind
    }

    /// Returns the exact pixel geometry supplied by U9.
    pub const fn rect(self) -> PixelRect {
        self.rect
    }
}

/// The sensitive classes whose detected regions are masked.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum DetectionKind {
    /// A text region returned by OCR.
    Text,
    /// A face returned by Vision.
    Face,
    /// A barcode or QR code returned by Vision.
    Barcode,
}

impl fmt::Display for DetectionKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Self::Text => "text",
            Self::Face => "face",
            Self::Barcode => "barcode",
        };
        formatter.write_str(name)
    }
}

/// A masked RGB image and the proof that all supplied detections were covered.
/// The gate augments this proof with a recognizer rerun over the masked bytes.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MaskedImage {
    image: Image,
    proof: CoverageProof,
}

impl MaskedImage {
    /// Returns the masked image bytes.
    pub const fn image(&self) -> &Image {
        &self.image
    }

    /// Returns the machine-checkable coverage proof.
    pub const fn proof(&self) -> &CoverageProof {
        &self.proof
    }

    /// Verifies the proof against the exact image-bound detection set and pixels.
    pub fn verify(&self, detections: &DetectionSet) -> Result<(), CoverageError> {
        self.proof.verify(&self.image, detections)
    }

    /// Records a recognizer rerun over this masked image.
    pub fn verify_masked_recognition(&mut self, rerun: &DetectionSet) -> Result<(), CoverageError> {
        self.proof.verify_masked_recognition(&self.image, rerun)
    }
}

/// Maps every U9 recognition result into a single ordered pixel-space set.
///
/// This is the only U10 entry point that consumes normalized recognizer output.
/// It delegates each individual rectangle to U9's tested mapping function and
/// stores the resulting [`PixelRect`] unchanged for the masker.
pub fn map_recognized_detections(
    recognition: &RecognitionResult,
    image: &Image,
    orientation: ImageOrientation,
) -> Result<DetectionSet, MaskError> {
    if let Some(expected) = recognition.source_image_hash()
        && expected != ImageHash::of(image)
    {
        return Err(MaskError::ImageHashMismatch {
            expected,
            actual: ImageHash::of(image),
        });
    }
    if recognition.is_partial() {
        return Err(MaskError::PartialRecognition);
    }
    let mut detections = Vec::new();
    for (index, region) in recognition.ocr().regions().iter().enumerate() {
        let geometry = region.geometry().ok_or(MaskError::MissingGeometry {
            kind: DetectionKind::Text,
            index,
        })?;
        let rect = map_normalized_rect(geometry, image.width(), image.height(), orientation)
            .map_err(MaskError::Mapping)?;
        detections.push(MappedDetection::new(DetectionKind::Text, rect));
    }
    for (index, finding) in recognition.vision().findings().iter().enumerate() {
        let geometry = finding.geometry().ok_or(MaskError::MissingGeometry {
            kind: detection_kind(finding.kind()),
            index,
        })?;
        let rect = map_normalized_rect(geometry, image.width(), image.height(), orientation)
            .map_err(MaskError::Mapping)?;
        detections.push(MappedDetection::new(detection_kind(finding.kind()), rect));
    }
    Ok(DetectionSet::new(ImageHash::of(image), detections))
}

/// Masks every supplied mapped detection with an opaque, one-pixel-dilated fill.
///
/// The proof records the recognizer-detected regions only. It makes no claim
/// about sensitive material that no recognizer reported, matching R-P5 and R-P6.
pub fn mask_image(image: &Image, detections: &DetectionSet) -> Result<MaskedImage, MaskError> {
    if detections.image_hash() != ImageHash::of(image) {
        return Err(MaskError::ImageHashMismatch {
            expected: detections.image_hash(),
            actual: ImageHash::of(image),
        });
    }
    let mut masked = image.clone();
    for detection in detections.detections() {
        validate_rect(detection.rect(), image.width(), image.height())?;
        let rect = dilated_rect(detection.rect(), image.width(), image.height());
        for y in rect.y..rect.bottom {
            for x in rect.x..rect.right {
                masked.set_pixel(x, y, MASK_COLOR)?;
            }
        }
    }
    let mut proof = CoverageProof::new(image, detections)?;
    proof.bind_masked_image(&masked);
    Ok(MaskedImage {
        image: masked,
        proof,
    })
}

fn detection_kind(kind: VisionKind) -> DetectionKind {
    match kind {
        VisionKind::Face => DetectionKind::Face,
        VisionKind::Barcode => DetectionKind::Barcode,
    }
}

fn expected_byte_len(width: u32, height: u32) -> Result<usize, MaskError> {
    let bytes = u64::from(width)
        .checked_mul(u64::from(height))
        .and_then(|pixels| pixels.checked_mul(3))
        .ok_or(MaskError::ArithmeticOverflow)?;
    usize::try_from(bytes).map_err(|_| MaskError::ArithmeticOverflow)
}

fn pixel_offset(width: u32, x: u32, y: u32) -> Result<usize, MaskError> {
    let index = u64::from(y)
        .checked_mul(u64::from(width))
        .and_then(|row| row.checked_add(u64::from(x)))
        .and_then(|pixel| pixel.checked_mul(3))
        .ok_or(MaskError::ArithmeticOverflow)?;
    usize::try_from(index).map_err(|_| MaskError::ArithmeticOverflow)
}

fn validate_rect(rect: PixelRect, width: u32, height: u32) -> Result<(), MaskError> {
    if rect.width() == 0 || rect.height() == 0 {
        return Err(MaskError::InvalidMappedRegion);
    }
    let right = rect
        .x()
        .checked_add(rect.width())
        .ok_or(MaskError::ArithmeticOverflow)?;
    let bottom = rect
        .y()
        .checked_add(rect.height())
        .ok_or(MaskError::ArithmeticOverflow)?;
    if right > width || bottom > height {
        return Err(MaskError::MappedRegionOutsideImage);
    }
    Ok(())
}

struct PixelBounds {
    x: u32,
    y: u32,
    right: u32,
    bottom: u32,
}

fn dilated_rect(rect: PixelRect, width: u32, height: u32) -> PixelBounds {
    let x = rect.x().saturating_sub(DILATION_PIXELS);
    let y = rect.y().saturating_sub(DILATION_PIXELS);
    let right = rect
        .x()
        .saturating_add(rect.width())
        .saturating_add(DILATION_PIXELS)
        .min(width);
    let bottom = rect
        .y()
        .saturating_add(rect.height())
        .saturating_add(DILATION_PIXELS)
        .min(height);
    PixelBounds {
        x,
        y,
        right,
        bottom,
    }
}

/// Errors raised before a provider-bound image can be accepted.
#[derive(Debug, Error)]
pub enum MaskError {
    /// The image dimensions are not usable.
    #[error("image dimensions must be non-zero, got {width}x{height}")]
    InvalidImageDimensions {
        /// The declared image width.
        width: u32,
        /// The declared image height.
        height: u32,
    },
    /// The RGB buffer does not match the declared dimensions.
    #[error("RGB buffer has {actual} bytes, expected {expected}")]
    InvalidPixelBuffer {
        /// The byte count implied by the image dimensions.
        expected: usize,
        /// The byte count supplied by the caller.
        actual: usize,
    },
    /// A recognizer returned a partial result, so the capture must fail closed.
    #[error("recognition was partial")]
    PartialRecognition,
    /// A recognized region had no geometry to mask.
    #[error("{kind} detection {index} has no geometry")]
    MissingGeometry {
        /// The recognizer class with missing geometry.
        kind: DetectionKind,
        /// The index within that recognizer's result list.
        index: usize,
    },
    /// U9 rejected the normalized geometry or dimensions.
    #[error("recognizer geometry mapping failed: {0}")]
    Mapping(#[source] qaptr_domain::DomainError),
    /// A mapped region cannot cover any pixel.
    #[error("mapped detection has zero width or height")]
    InvalidMappedRegion,
    /// A mapped region lies outside the image it is meant to mask.
    #[error("mapped detection lies outside the image")]
    MappedRegionOutsideImage,
    /// An image-size calculation overflowed.
    #[error("image size arithmetic overflowed")]
    ArithmeticOverflow,
    /// The generated proof could not be built.
    #[error("coverage proof failed: {0}")]
    Coverage(#[source] CoverageError),
    /// The detection set was computed for different image bytes.
    #[error("detection set is bound to image hash {expected}, but masking received {actual}")]
    ImageHashMismatch {
        /// Hash recorded when recognition produced the detections.
        expected: ImageHash,
        /// Hash of the image supplied to masking.
        actual: ImageHash,
    },
    /// An image recognizer was not supplied for the required verification rerun.
    #[error("masked image recognition verification was not configured")]
    MissingVerificationRecognizer,
}

impl From<CoverageError> for MaskError {
    fn from(error: CoverageError) -> Self {
        Self::Coverage(error)
    }
}

#[cfg(test)]
mod tests {
    use super::{Image, MASK_COLOR};

    #[test]
    fn image_rejects_wrong_buffer_size() {
        let result = Image::new(2, 2, vec![255; 3]);
        assert!(result.is_err());
    }

    #[test]
    fn solid_image_has_expected_pixels() {
        let image = Image::solid(2, 1, [17, 34, 51]).expect("fixture image should be valid");
        assert_eq!(image.pixel(1, 0), Some([17, 34, 51]));
        assert_ne!(image.pixel(1, 0), Some(MASK_COLOR));
    }
}
