//! The fail-closed privacy chokepoint.
//!
//! This module owns the only operation that turns a captured sample into a
//! provider-bound artifact. Every recognition, masking, coverage, sanitization,
//! partial-result, and deadline failure becomes a [`PrivacyExclusion`].

use std::time::{Duration, Instant};

use qaptr_domain::ports::{ContextSnapshot, OcrPort, VisionPort};
use qaptr_domain::{CaptureId, DomainError};
use thiserror::Error;

use crate::mask::{MaskError, map_recognized_detections, mask_image};
use crate::payload::{PreparationProof, PreparedPayload};
use crate::recognize::{ImageOrientation, recognize};
use crate::sanitize::{SanitizationError, sanitize_context};
use crate::{CoverageError, Image, RecallReport};

/// The complete preparation budget owned by U12.
pub const FULL_PREPARATION_BUDGET: Duration = Duration::from_millis(900);

/// The stage at which a preparation deadline was exceeded.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PreparationStage {
    /// Local OCR and visual recognition.
    Recognition,
    /// Mapping detections and masking an opted-in image.
    Masking,
    /// Structured context sanitization.
    Sanitization,
    /// Final proof assembly.
    Finalization,
}

/// A reason a capture was excluded from provider processing.
#[derive(Debug, Error)]
pub enum ExclusionReason {
    /// Recognition returned a typed domain failure, including a timeout.
    #[error("recognition failed: {0}")]
    Recognition(#[source] DomainError),
    /// Recognition explicitly returned an incomplete result.
    #[error("recognition was partial")]
    PartialRecognition,
    /// Detection mapping or image masking failed.
    #[error("masking failed: {0}")]
    Masking(#[source] MaskError),
    /// The output did not satisfy the machine-checkable coverage proof.
    #[error("coverage proof failed: {0}")]
    Coverage(#[source] CoverageError),
    /// Context contained an unsafe, malformed, or unclassifiable value.
    #[error("sanitization failed: {0}")]
    Sanitization(#[source] SanitizationError),
    /// The complete local pipeline exceeded its bounded preparation budget.
    #[error("{stage:?} exceeded preparation budget: {elapsed:?} > {budget:?}")]
    Timeout {
        /// The pipeline stage at which the deadline was observed.
        stage: PreparationStage,
        /// Elapsed preparation time at the observation point.
        elapsed: Duration,
        /// Configured end-to-end preparation budget.
        budget: Duration,
    },
}

/// A quiet, typed exclusion that can be turned into one user-facing notice.
#[derive(Debug, Error)]
#[error("capture {capture_id} excluded: {reason}")]
pub struct PrivacyExclusion {
    capture_id: CaptureId,
    reason: ExclusionReason,
}

impl PrivacyExclusion {
    /// Returns the excluded capture identifier.
    pub const fn capture_id(&self) -> &CaptureId {
        &self.capture_id
    }

    /// Returns the typed reason for exclusion.
    pub const fn reason(&self) -> &ExclusionReason {
        &self.reason
    }

    fn new(capture_id: CaptureId, reason: ExclusionReason) -> Self {
        Self { capture_id, reason }
    }
}

/// Input to the privacy gate.
///
/// An image may be supplied for local preparation but is not sent unless the
/// caller separately invokes [`Self::allow_image`]. The input owns the raw
/// image so the gate can consume it without retaining an unmasked copy in the
/// prepared artifact.
#[derive(Debug)]
pub struct PreparationInput {
    capture_id: CaptureId,
    context: ContextSnapshot,
    image: Option<Image>,
    orientation: ImageOrientation,
    image_allowed: bool,
}

impl PreparationInput {
    /// Creates a text-context-first input with no image payload.
    pub fn new(capture_id: CaptureId, context: ContextSnapshot) -> Self {
        Self {
            capture_id,
            context,
            image: None,
            orientation: ImageOrientation::Up,
            image_allowed: false,
        }
    }

    /// Attaches an image for local masking while keeping image sending off.
    pub fn with_image(mut self, image: Image, orientation: ImageOrientation) -> Self {
        self.image = Some(image);
        self.orientation = orientation;
        self
    }

    /// Explicitly opts this input into the already-attached masked image.
    pub fn allow_image(mut self) -> Self {
        self.image_allowed = true;
        self
    }

    /// Returns the capture identifier supplied to the gate.
    pub const fn capture_id(&self) -> &CaptureId {
        &self.capture_id
    }
}

/// The local privacy gate and its measured recall disclosure.
pub struct PrivacyGate {
    recall: RecallReport,
    budget: Duration,
}

impl PrivacyGate {
    /// Creates a gate with the plan's 900 ms end-to-end budget.
    pub const fn new(recall: RecallReport) -> Self {
        Self {
            recall,
            budget: FULL_PREPARATION_BUDGET,
        }
    }

    /// Creates a gate with a custom budget for deterministic boundary tests.
    /// Production callers should use [`Self::new`].
    pub const fn with_budget(recall: RecallReport, budget: Duration) -> Self {
        Self { recall, budget }
    }

    /// Returns the configured end-to-end budget.
    pub const fn budget(&self) -> Duration {
        self.budget
    }

    /// Prepares a provider payload or returns a typed exclusion.
    ///
    /// The operation is deliberately synchronous because the port contracts
    /// already require platform adapters to enforce their own bounded calls.
    /// The gate additionally observes the complete elapsed time and refuses to
    /// emit if the 900 ms end-to-end budget is exceeded.
    pub fn prepare<O, V>(
        &self,
        input: PreparationInput,
        ocr: &O,
        vision: &V,
    ) -> std::result::Result<PreparedPayload, PrivacyExclusion>
    where
        O: OcrPort,
        V: VisionPort,
    {
        let capture_id = input.capture_id.clone();
        let started = Instant::now();
        let recognition = recognize(ocr, vision, &input.capture_id).map_err(|error| {
            PrivacyExclusion::new(capture_id.clone(), ExclusionReason::Recognition(error))
        })?;
        self.check_budget(&capture_id, started, PreparationStage::Recognition)?;
        if recognition.is_partial() {
            return Err(PrivacyExclusion::new(
                capture_id,
                ExclusionReason::PartialRecognition,
            ));
        }

        let (masked_image, coverage) = if input.image_allowed {
            let image = input.image.as_ref().ok_or_else(|| {
                PrivacyExclusion::new(
                    capture_id.clone(),
                    ExclusionReason::Masking(MaskError::InvalidImageDimensions {
                        width: 0,
                        height: 0,
                    }),
                )
            })?;
            let detections = map_recognized_detections(
                &recognition,
                image.width(),
                image.height(),
                input.orientation,
            )
            .map_err(|error| Self::mask_exclusion(&capture_id, error))?;
            let masked = mask_image(image, &detections)
                .map_err(|error| Self::mask_exclusion(&capture_id, error))?;
            masked.verify(&detections).map_err(|error| {
                PrivacyExclusion::new(capture_id.clone(), ExclusionReason::Coverage(error))
            })?;
            let proof = masked.proof().clone();
            (Some(masked), Some(proof))
        } else {
            (None, None)
        };
        self.check_budget(&capture_id, started, PreparationStage::Masking)?;

        let sanitized = sanitize_context(&input.context).map_err(|error| {
            PrivacyExclusion::new(capture_id.clone(), ExclusionReason::Sanitization(error))
        })?;
        self.check_budget(&capture_id, started, PreparationStage::Sanitization)?;
        let proof = PreparationProof::new(self.recall.clone(), sanitized.classes(), coverage);
        self.check_budget(&capture_id, started, PreparationStage::Finalization)?;

        Ok(PreparedPayload::new(
            input.capture_id,
            sanitized,
            masked_image,
            proof,
        ))
    }

    fn check_budget(
        &self,
        capture_id: &CaptureId,
        started: Instant,
        stage: PreparationStage,
    ) -> std::result::Result<(), PrivacyExclusion> {
        let elapsed = started.elapsed();
        if elapsed > self.budget {
            return Err(PrivacyExclusion::new(
                capture_id.clone(),
                ExclusionReason::Timeout {
                    stage,
                    elapsed,
                    budget: self.budget,
                },
            ));
        }
        Ok(())
    }

    fn mask_exclusion(capture_id: &CaptureId, error: MaskError) -> PrivacyExclusion {
        match error {
            MaskError::Coverage(error) => {
                PrivacyExclusion::new(capture_id.clone(), ExclusionReason::Coverage(error))
            }
            other => PrivacyExclusion::new(capture_id.clone(), ExclusionReason::Masking(other)),
        }
    }
}
