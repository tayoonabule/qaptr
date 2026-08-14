//! The local optical-character-recognition port.

use crate::{CaptureId, Confidence};

use super::PortResult;

/// One text region recognized in a capture.
#[derive(Clone, Debug, PartialEq)]
pub struct TextRegion {
    text: String,
    confidence: Confidence,
}

impl TextRegion {
    /// Creates a recognized text region.
    pub fn new(text: impl Into<String>, confidence: Confidence) -> Self {
        Self {
            text: text.into(),
            confidence,
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
