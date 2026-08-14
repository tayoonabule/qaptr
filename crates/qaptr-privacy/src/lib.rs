//! Privacy-boundary building blocks for local recognition.
//!
//! This crate never makes network calls, stores image bytes, masks pixels, or
//! sanitizes context. It only combines the U2 OCR and Vision ports and maps
//! their normalized geometry into the production image's pixel space. The
//! macOS Vision implementation lives in `qaptr-macos`; this crate remains
//! platform-independent so U10 and U12 can use the same mapping on every OS.

pub mod recognize;

pub use recognize::{
    ImageOrientation, PixelRect, RecognitionResult, map_normalized_rect, recognize,
};
