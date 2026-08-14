//! Privacy-boundary building blocks for local recognition and context safety.
//!
//! This crate never makes network calls, stores image bytes, or constructs a
//! provider payload. Recognition and context sanitization are platform-
//! independent, deterministic stages. Pixel masking remains a separate stage;
//! the macOS Vision implementation lives in `qaptr-macos`.

pub mod classes;
pub mod recognize;
pub mod sanitize;

pub use classes::{SensitiveClass, SensitiveFinding, detect_findings};
pub use recognize::{
    ImageOrientation, PixelRect, RecognitionResult, map_normalized_rect, recognize,
};
pub use sanitize::{
    ContextField, SanitizationError, SanitizedContext, SanitizedValue, sanitize_context,
    sanitize_field, sanitize_path, sanitize_text, sanitize_text_field, sanitize_url,
};
