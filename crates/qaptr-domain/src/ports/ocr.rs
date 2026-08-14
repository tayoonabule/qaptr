//! The local optical-character-recognition port.

use crate::{CaptureId, Confidence, NormalizedRect};

use super::PortResult;

/// One text region recognized in a capture.
#[derive(Clone, Debug, PartialEq)]
pub struct TextRegion {
    text: String,
    confidence: Confidence,
    geometry: Option<NormalizedRect>,
}

impl TextRegion {
    /// Creates a recognized text region.
    pub fn new(text: impl Into<String>, confidence: Confidence) -> Self {
        Self {
            text: text.into(),
            confidence,
            geometry: None,
        }
    }

    /// Creates a recognized region with Vision-normalized geometry.
    pub const fn with_geometry(
        text: String,
        confidence: Confidence,
        geometry: NormalizedRect,
    ) -> Self {
        Self {
            text,
            confidence,
            geometry: Some(geometry),
        }
    }

    /// Returns the recognized text.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Returns the recognizer confidence.
    pub const fn confidence(&self) -> Confidence {
        self.confidence
    }

    /// Returns the normalized geometry when supplied by a native recognizer.
    pub const fn geometry(&self) -> Option<NormalizedRect> {
        self.geometry
    }
}

/// The recognized text for one capture.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct OcrResult {
    regions: Vec<TextRegion>,
}

impl OcrResult {
    /// Creates an OCR result from recognized regions.
    pub fn new(regions: Vec<TextRegion>) -> Self {
        Self { regions }
    }

    /// Returns the recognized regions.
    pub fn regions(&self) -> &[TextRegion] {
        &self.regions
    }
}

/// Recognizes text locally for one captured sample.
pub trait OcrPort {
    /// Runs OCR for a previously captured sample.
    fn recognize(&self, capture: &CaptureId) -> PortResult<OcrResult>;
}

/// Short alias for callers that prefer the domain noun.
pub use OcrPort as Ocr;
