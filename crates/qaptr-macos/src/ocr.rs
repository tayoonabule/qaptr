//! Vision-framework text recognition exposed through the domain OCR port.

use std::path::PathBuf;
use std::time::Duration;

use qaptr_domain::ports::ocr::{OcrPort, OcrResult, TextRegion};
use qaptr_domain::ports::{PortOutcome, PortResult};
use qaptr_domain::{CaptureId, DomainError};

use crate::error::MacosError;
use crate::recognition::{decode_base64, run_helper};

/// Default recognition deadline used by the review app.
pub const DEFAULT_RECOGNITION_TIMEOUT: Duration = Duration::from_millis(500);

/// A local Vision-framework OCR adapter backed by the review app's image root.
#[derive(Clone, Debug)]
pub struct MacOcr {
    image_root: PathBuf,
    helper: PathBuf,
    timeout: Duration,
}

impl MacOcr {
    /// Creates an adapter using the Vision helper compiled with this crate.
    pub fn new(image_root: impl Into<PathBuf>) -> Self {
        Self::with_helper(
            image_root,
            PathBuf::from(env!("QAPTR_VISION_HELPER")),
            DEFAULT_RECOGNITION_TIMEOUT,
        )
    }

    /// Creates an adapter with an explicit helper and deadline for tests.
    pub fn with_helper(
        image_root: impl Into<PathBuf>,
        helper: impl Into<PathBuf>,
        timeout: Duration,
    ) -> Self {
        Self {
            image_root: image_root.into(),
            helper: helper.into(),
            timeout,
        }
    }

    /// Runs OCR and returns the native error before it is converted to a port
    /// error.
    pub fn recognize_value(&self, capture: &CaptureId) -> Result<OcrResult, MacosError> {
        let records = run_helper(&self.helper, &self.image_root, capture, "ocr", self.timeout)?;
        records
            .into_iter()
            .map(|record| {
                let text = record.text_base64.ok_or_else(|| MacosError::Recognition {
                    operation: "ocr",
                    message: "OCR helper returned a non-text record".to_owned(),
                })?;
                let text = decode_base64(&text)?;
                Ok(TextRegion::with_geometry(
                    text,
                    record.confidence,
                    record.geometry,
                ))
            })
            .collect::<Result<Vec<_>, MacosError>>()
            .map(OcrResult::new)
    }
}

impl OcrPort for MacOcr {
    fn recognize(&self, capture: &CaptureId) -> PortResult<OcrResult> {
        self.recognize_value(capture)
            .map(PortOutcome::Complete)
            .map_err(|error| map_error(error, "ocr"))
    }
}

fn map_error(error: MacosError, operation: &'static str) -> DomainError {
    match error {
        MacosError::RecognitionTimeout { .. } => DomainError::TimedOut { operation },
        other => DomainError::Failed {
            operation,
            reason: other.to_string(),
        },
    }
}
