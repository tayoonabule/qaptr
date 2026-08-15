//! Privacy-boundary building blocks and the fail-closed provider gate.
//!
//! This crate never makes network calls or stores image bytes durably. The only
//! provider-bound artifact is [`PreparedPayload`], which can only be created by
//! [`PrivacyGate`]. Recognition, masking, coverage verification, and context
//! sanitization all run locally before that artifact can exist.
//!
//! Image preparation uses an exact-image recognizer, binds detections to the
//! image hash, and reruns recognition over the masked bytes. This proves that
//! reported regions were removed; it does not prove discovery of material
//! missed by U9's published 5/6 (0.833) recall result.

pub mod classes;
pub mod coverage;
mod gate;
pub mod mask;
mod payload;
pub mod recall;
pub mod recognize;
pub mod sanitize;

pub use classes::{SensitiveClass, SensitiveFinding, detect_findings};
pub use coverage::{CoverageEntry, CoverageError, CoverageProof, RecognitionVerification};
pub use gate::{
    ExclusionReason, FULL_PREPARATION_BUDGET, PreparationInput, PreparationStage, PrivacyExclusion,
    PrivacyGate,
};
pub use mask::{
    DILATION_PIXELS, DetectionKind, DetectionSet, Image, ImageHash, MASK_COLOR, MappedDetection,
    MaskError, MaskedImage, map_recognized_detections, mask_image,
};
pub use payload::{PreparationProof, PreparedPayload};
pub use recall::{
    DEFAULT_IOU_THRESHOLD, RecallError, RecallReport, measure_recall, measure_recall_with_threshold,
};
pub use recognize::{
    ImageOrientation, ImageRecognizer, PixelRect, RecognitionProvenance, RecognitionResult,
    map_normalized_rect, recognize,
};
pub use sanitize::{
    ContextField, SanitizationError, SanitizedContext, SanitizedValue, sanitize_context,
    sanitize_field, sanitize_path, sanitize_text, sanitize_text_field, sanitize_url,
};
