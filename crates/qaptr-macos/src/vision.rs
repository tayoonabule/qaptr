//! Vision-framework face and barcode detection exposed through the domain port.

use std::path::PathBuf;
use std::time::Duration;

use qaptr_domain::ports::vision::{VisionFinding, VisionKind, VisionPort, VisionResult};
use qaptr_domain::ports::{PortOutcome, PortResult};
use qaptr_domain::{CaptureId, DomainError};

use crate::error::MacosError;
use crate::ocr::DEFAULT_RECOGNITION_TIMEOUT;
use crate::recognition::run_helper;

/// A local Vision-framework visual detector for faces and barcodes.
#[derive(Clone, Debug)]
pub struct MacVision {
    image_root: PathBuf,
    helper: PathBuf,
    timeout: Duration,
}

impl MacVision {
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

    /// Runs face and barcode detection and returns the native error before it
    /// is converted to a port error.
    pub fn detect_value(&self, capture: &CaptureId) -> Result<VisionResult, MacosError> {
        let records = run_helper(
            &self.helper,
            &self.image_root,
            capture,
            "vision",
            self.timeout,
        )?;
        records
            .into_iter()
            .map(|record| {
                let kind = match record.kind.as_str() {
                    "face" => VisionKind::Face,
                    "barcode" => VisionKind::Barcode,
                    other => {
                        return Err(MacosError::Recognition {
                            operation: "vision",
                            message: format!("Vision helper returned unexpected kind: {other}"),
                        });
                    }
                };
                Ok(VisionFinding::with_geometry(
                    kind,
                    record.confidence,
                    record.geometry,
                ))
            })
            .collect::<Result<Vec<_>, MacosError>>()
            .map(VisionResult::new)
    }
}

impl VisionPort for MacVision {
    fn detect(&self, capture: &CaptureId) -> PortResult<VisionResult> {
        self.detect_value(capture)
            .map(PortOutcome::Complete)
            .map_err(|error| match error {
                MacosError::RecognitionTimeout { .. } => DomainError::TimedOut {
                    operation: "vision",
                },
                other => DomainError::Failed {
                    operation: "vision",
                    reason: other.to_string(),
                },
            })
    }
}
