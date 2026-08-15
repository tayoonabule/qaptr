//! The only provider-bound payload type in the privacy crate.
//!
//! `PreparedPayload` has private state and a crate-private constructor. The
//! gate is the only module that can create one, so callers can only obtain a
//! provider payload after recognition, masking, coverage verification, and
//! context sanitization have all succeeded.

use std::collections::BTreeSet;

use qaptr_domain::CaptureId;

use crate::{CoverageProof, MaskedImage, RecallReport, SanitizedContext, SensitiveClass};

/// A provider-bound payload that has passed the complete local privacy gate.
///
/// # Invariant
///
/// Every instance was created by [`crate::PrivacyGate::prepare`]. Its context
/// is sanitized, and its optional image is masked and backed by a verified
/// coverage proof plus a masked-output recognizer rerun. The type never stores
/// the original image and does not claim to recover recognizer misses.
///
/// ```compile_fail
/// use qaptr_privacy::PreparedPayload;
///
/// // The constructor is crate-private, so provider callers cannot forge this
/// // artifact or bypass the privacy gate.
/// let _ = PreparedPayload::new();
/// ```
pub struct PreparedPayload {
    capture_id: CaptureId,
    context: SanitizedContext,
    image: Option<MaskedImage>,
    proof: PreparationProof,
}

impl PreparedPayload {
    /// Returns the capture identifier associated with this payload.
    pub const fn capture_id(&self) -> &CaptureId {
        &self.capture_id
    }

    /// Returns the sanitized structured context.
    pub const fn context(&self) -> &SanitizedContext {
        &self.context
    }

    /// Returns the masked image when image sending was explicitly enabled.
    pub const fn masked_image(&self) -> Option<&MaskedImage> {
        self.image.as_ref()
    }

    /// Returns the evidence produced by every privacy stage.
    pub const fn proof(&self) -> &PreparationProof {
        &self.proof
    }

    pub(crate) fn new(
        capture_id: CaptureId,
        context: SanitizedContext,
        image: Option<MaskedImage>,
        proof: PreparationProof,
    ) -> Self {
        Self {
            capture_id,
            context,
            image,
            proof,
        }
    }
}

/// Machine-checkable evidence attached to a prepared payload.
///
/// The recall report is deliberately carried through unchanged. It records
/// measured recognizer limitations and must not be interpreted as a claim of
/// perfect detection.
pub struct PreparationProof {
    recall: RecallReport,
    sanitized_classes: BTreeSet<SensitiveClass>,
    coverage: Option<CoverageProof>,
}

impl PreparationProof {
    /// Returns the measured recognizer recall disclosure.
    pub const fn recall(&self) -> &RecallReport {
        &self.recall
    }

    /// Returns the sensitive classes replaced in structured context.
    pub const fn sanitized_classes(&self) -> &BTreeSet<SensitiveClass> {
        &self.sanitized_classes
    }

    /// Returns the image coverage proof, when local image preparation ran.
    ///
    /// This remains available when image transmission is disabled so callers
    /// can distinguish a locally prepared image from a text-only payload.
    pub const fn coverage(&self) -> Option<&CoverageProof> {
        self.coverage.as_ref()
    }

    /// Returns the number of recognizer-detected image regions covered.
    pub fn masked_region_count(&self) -> usize {
        self.coverage
            .as_ref()
            .map_or(0, CoverageProof::detected_region_count)
    }

    pub(crate) fn new(
        recall: RecallReport,
        sanitized_classes: BTreeSet<SensitiveClass>,
        coverage: Option<CoverageProof>,
    ) -> Self {
        Self {
            recall,
            sanitized_classes,
            coverage,
        }
    }
}

impl std::fmt::Debug for PreparedPayload {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PreparedPayload")
            .field("capture_id", &self.capture_id)
            .field("context", &self.context)
            .field("image", &self.image.as_ref().map(|_| "masked"))
            .field("proof", &self.proof)
            .finish()
    }
}

impl std::fmt::Debug for PreparationProof {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PreparationProof")
            .field("recall", &self.recall)
            .field("sanitized_classes", &self.sanitized_classes)
            .field("coverage", &self.coverage)
            .finish()
    }
}

impl PartialEq for PreparedPayload {
    fn eq(&self, other: &Self) -> bool {
        self.capture_id == other.capture_id
            && self.context == other.context
            && self.image == other.image
            && self.proof == other.proof
    }
}

impl PartialEq for PreparationProof {
    fn eq(&self, other: &Self) -> bool {
        self.recall == other.recall
            && self.sanitized_classes == other.sanitized_classes
            && self.coverage == other.coverage
    }
}
