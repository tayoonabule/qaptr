//! The local visual-detection port.

use crate::{CaptureId, Confidence};

use super::PortResult;

/// A visual class that Qaptr may mask before provider processing.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum VisionKind {
    /// A detected face.
    Face,
    /// A detected barcode or QR code.
    Barcode,
}

/// One visual finding in a capture.
#[derive(Clone, Debug, PartialEq)]
pub struct VisionFinding {
    kind: VisionKind,
    confidence: Confidence,
}

impl VisionFinding {
    /// Creates a visual finding.
    pub const fn new(kind: VisionKind, confidence: Confidence) -> Self {
        Self { kind, confidence }
    }

    /// Returns the finding kind.
    pub const fn kind(&self) -> VisionKind {
        self.kind
    }

    /// Returns the detector confidence.
    pub const fn confidence(&self) -> Confidence {
        self.confidence
    }
}

/// The visual findings for one capture.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct VisionResult {
    findings: Vec<VisionFinding>,
}

impl VisionResult {
    /// Creates a vision result from findings.
    pub fn new(findings: Vec<VisionFinding>) -> Self {
        Self { findings }
    }

    /// Returns the detected findings.
    pub fn findings(&self) -> &[VisionFinding] {
        &self.findings
    }
}

/// Detects local visual regions that may require masking.
pub trait VisionPort {
    /// Runs visual detection for a previously captured sample.
    fn detect(&self, capture: &CaptureId) -> PortResult<VisionResult>;
}

/// Short alias for callers that prefer the domain noun.
pub use VisionPort as Vision;
