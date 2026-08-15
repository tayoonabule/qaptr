//! Review-app-owned decoding of sealed members into local privacy input.

use std::io::Cursor;
use std::sync::Arc;

use qaptr_domain::ports::ContextSnapshot;
use qaptr_privacy::{Image, ImageOrientation, ImageRecognizer, PreparationInput};
use qaptr_vault::{OpenedBundle, PrivacyImage};
use qaptr_workflow::{CaptureDecoder, DecodeError};
use thiserror::Error;

use qaptr_macos::MacImageRecognizer;

/// Maximum serialized helper context accepted by the review app.
pub const MAX_CONTEXT_BYTES: usize = 8 * 1024;
/// Maximum UTF-8 length of one helper context scalar.
pub const MAX_CONTEXT_FIELD_BYTES: usize = 512;
/// Maximum sealed PNG member size accepted before decoding.
pub const MAX_PNG_BYTES: usize = 16 * 1024 * 1024;
/// Maximum width or height accepted from a sealed PNG member.
pub const MAX_IMAGE_DIMENSION: u32 = 4096;
/// Maximum decoded pixel count accepted from a sealed PNG member.
pub const MAX_IMAGE_PIXELS: u64 = 16 * 1024 * 1024;

/// A bounded, local-only decoder for one already-opened sealed bundle.
pub struct LocalBundleDecoder {
    recognizer: Arc<dyn ImageRecognizer>,
}

impl LocalBundleDecoder {
    /// Creates a decoder with an exact-image recognizer supplied by the caller.
    pub fn new(recognizer: Arc<dyn ImageRecognizer>) -> Self {
        Self { recognizer }
    }

    /// Creates the production macOS decoder and its local Vision recognizer.
    pub fn for_macos() -> Self {
        Self::new(Arc::new(MacImageRecognizer::new()))
    }

    /// Decodes only bounded scalar context and a bounded PNG image.
    ///
    /// The decrypted image is borrowed exclusively through
    /// [`OpenedBundle::with_image_for_privacy`]. The returned input is a local
    /// privacy value and is never serialized or returned over the C ABI.
    pub fn decode(
        &self,
        bundle: &OpenedBundle,
    ) -> std::result::Result<PreparationInput, LocalDecodeError> {
        let context = decode_context(bundle.context().as_bytes())?;
        let image = bundle.with_image_for_privacy(decode_privacy_image)?;
        Ok(
            PreparationInput::new(bundle.metadata().capture_id.clone(), context)
                .with_image(image, ImageOrientation::Up)
                .with_image_recognizer(self.recognizer.clone()),
        )
    }
}

impl CaptureDecoder for LocalBundleDecoder {
    fn decode(&self, bundle: &OpenedBundle) -> std::result::Result<PreparationInput, DecodeError> {
        Self::decode(self, bundle).map_err(|error| DecodeError::InvalidInput(error.to_string()))
    }
}

/// Decodes a sealed image while retaining no reference to the vault image.
pub fn decode_privacy_image(image: &PrivacyImage) -> std::result::Result<Image, LocalDecodeError> {
    image.with_bytes(decode_png)
}

/// Decodes the helper's JSON context into the four domain scalar fields.
pub fn decode_context(bytes: &[u8]) -> std::result::Result<ContextSnapshot, LocalDecodeError> {
    if bytes.len() > MAX_CONTEXT_BYTES {
        return Err(LocalDecodeError::ContextTooLarge {
            actual: bytes.len(),
            maximum: MAX_CONTEXT_BYTES,
        });
    }
    let value: serde_json::Value = serde_json::from_slice(bytes)
        .map_err(|error| LocalDecodeError::MalformedContext(error.to_string()))?;
    let object = value.as_object().ok_or_else(|| {
        LocalDecodeError::MalformedContext("context must be a JSON object".to_owned())
    })?;
    for key in object.keys() {
        if !matches!(
            key.as_str(),
            "application" | "windowTitle" | "browserHost" | "documentName"
        ) {
            return Err(LocalDecodeError::MalformedContext(format!(
                "unsupported context field {key:?}"
            )));
        }
    }
    let application = scalar(object, "application")?;
    let window_title = scalar(object, "windowTitle")?;
    let browser_host = scalar(object, "browserHost")?;
    let document_name = scalar(object, "documentName")?;
    Ok(ContextSnapshot::new(
        application,
        window_title,
        browser_host,
        document_name,
    ))
}

/// Errors raised before any local preparation input can be constructed.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum LocalDecodeError {
    /// The serialized context exceeded its bound.
    #[error("context is too large: {actual} bytes > {maximum} bytes")]
    ContextTooLarge {
        /// Actual serialized context length.
        actual: usize,
        /// Maximum serialized context length.
        maximum: usize,
    },
    /// The serialized context was not an allowed scalar object.
    #[error("malformed helper context: {0}")]
    MalformedContext(String),
    /// A single scalar context field exceeded its bound.
    #[error("context field {field} is too large: {actual} bytes > {maximum} bytes")]
    ContextFieldTooLarge {
        /// Name of the oversized context field.
        field: &'static str,
        /// Actual UTF-8 field length.
        actual: usize,
        /// Maximum UTF-8 field length.
        maximum: usize,
    },
    /// The PNG member exceeded its compressed byte bound.
    #[error("PNG image is too large: {actual} bytes > {maximum} bytes")]
    ImageTooLarge {
        /// Actual encoded PNG length.
        actual: usize,
        /// Maximum encoded PNG length.
        maximum: usize,
    },
    /// The PNG member could not be decoded safely.
    #[error("malformed PNG image: {0}")]
    MalformedImage(String),
    /// The PNG dimensions exceeded the local preparation policy.
    #[error("PNG dimensions are too large: {width}x{height}")]
    ImageDimensions {
        /// PNG width in pixels.
        width: u32,
        /// PNG height in pixels.
        height: u32,
    },
    /// The PNG's pixel count exceeded the local preparation policy.
    #[error("PNG pixel count is too large: {pixels} > {maximum}")]
    ImagePixels {
        /// Decoded pixel count.
        pixels: u64,
        /// Maximum decoded pixel count.
        maximum: u64,
    },
    /// The PNG color layout is not supported by the RGB privacy image.
    #[error("unsupported PNG color layout: {0}")]
    UnsupportedImage(String),
}

fn scalar(
    object: &serde_json::Map<String, serde_json::Value>,
    field: &'static str,
) -> std::result::Result<Option<String>, LocalDecodeError> {
    let Some(value) = object.get(field) else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    let value = value.as_str().ok_or_else(|| {
        LocalDecodeError::MalformedContext(format!("context field {field} is not a string"))
    })?;
    if value.len() > MAX_CONTEXT_FIELD_BYTES {
        return Err(LocalDecodeError::ContextFieldTooLarge {
            field,
            actual: value.len(),
            maximum: MAX_CONTEXT_FIELD_BYTES,
        });
    }
    Ok(Some(value.to_owned()))
}

fn decode_png(bytes: &[u8]) -> std::result::Result<Image, LocalDecodeError> {
    if bytes.len() > MAX_PNG_BYTES {
        return Err(LocalDecodeError::ImageTooLarge {
            actual: bytes.len(),
            maximum: MAX_PNG_BYTES,
        });
    }
    let mut decoder = png::Decoder::new(Cursor::new(bytes));
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder
        .read_info()
        .map_err(|error| LocalDecodeError::MalformedImage(error.to_string()))?;
    let info = reader.info();
    validate_dimensions(info.width, info.height)?;
    let output_size = reader.output_buffer_size();
    if output_size > MAX_PNG_BYTES {
        return Err(LocalDecodeError::ImageTooLarge {
            actual: output_size,
            maximum: MAX_PNG_BYTES,
        });
    }
    let mut output = vec![0_u8; output_size];
    let frame = reader
        .next_frame(&mut output)
        .map_err(|error| LocalDecodeError::MalformedImage(error.to_string()))?;
    validate_dimensions(frame.width, frame.height)?;
    let rgb = to_rgb(&output[..frame.buffer_size()], &frame)?;
    Image::new(frame.width, frame.height, rgb)
        .map_err(|error| LocalDecodeError::MalformedImage(error.to_string()))
}

fn validate_dimensions(width: u32, height: u32) -> std::result::Result<(), LocalDecodeError> {
    if width == 0 || height == 0 || width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION {
        return Err(LocalDecodeError::ImageDimensions { width, height });
    }
    let pixels = u64::from(width) * u64::from(height);
    if pixels > MAX_IMAGE_PIXELS {
        return Err(LocalDecodeError::ImagePixels {
            pixels,
            maximum: MAX_IMAGE_PIXELS,
        });
    }
    Ok(())
}

fn to_rgb(bytes: &[u8], frame: &png::OutputInfo) -> std::result::Result<Vec<u8>, LocalDecodeError> {
    if frame.bit_depth != png::BitDepth::Eight {
        return Err(LocalDecodeError::UnsupportedImage(format!(
            "bit depth {:?}",
            frame.bit_depth
        )));
    }
    let channels = match frame.color_type {
        png::ColorType::Grayscale => 1,
        png::ColorType::GrayscaleAlpha => 2,
        png::ColorType::Rgb => 3,
        png::ColorType::Rgba => 4,
        png::ColorType::Indexed => {
            return Err(LocalDecodeError::UnsupportedImage(
                "indexed color".to_owned(),
            ));
        }
    };
    let expected_row = usize::try_from(frame.width)
        .ok()
        .and_then(|width| width.checked_mul(channels))
        .ok_or_else(|| LocalDecodeError::MalformedImage("row size overflow".to_owned()))?;
    let expected = expected_row
        .checked_mul(usize::try_from(frame.height).unwrap_or(usize::MAX))
        .ok_or_else(|| LocalDecodeError::MalformedImage("pixel size overflow".to_owned()))?;
    if bytes.len() != expected {
        return Err(LocalDecodeError::MalformedImage(format!(
            "decoded buffer has {} bytes, expected {expected}",
            bytes.len()
        )));
    }
    let capacity = usize::try_from(u64::from(frame.width) * u64::from(frame.height) * 3)
        .map_err(|_| LocalDecodeError::MalformedImage("RGB size overflow".to_owned()))?;
    let mut rgb = Vec::with_capacity(capacity);
    for pixel in bytes.chunks_exact(channels) {
        match frame.color_type {
            png::ColorType::Grayscale | png::ColorType::GrayscaleAlpha => {
                rgb.extend_from_slice(&[pixel[0], pixel[0], pixel[0]]);
            }
            png::ColorType::Rgb | png::ColorType::Rgba => rgb.extend_from_slice(&pixel[..3]),
            png::ColorType::Indexed => unreachable!("indexed color returned above"),
        }
    }
    Ok(rgb)
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, UNIX_EPOCH};

    use qaptr_domain::CaptureId;
    use qaptr_privacy::RecognitionResult;
    use qaptr_vault::{BundleInput, GenerationId, GenerationKeypair, SampledContext, Vault};

    use super::*;

    #[test]
    fn malformed_context_is_rejected() {
        let error = decode_context(br#"[\"not an object\"]"#).expect_err("context must fail");
        assert!(matches!(error, LocalDecodeError::MalformedContext(_)));
    }

    #[test]
    fn oversized_context_is_rejected_before_json_work() {
        let bytes = vec![b'x'; MAX_CONTEXT_BYTES + 1];
        assert_eq!(
            decode_context(&bytes),
            Err(LocalDecodeError::ContextTooLarge {
                actual: MAX_CONTEXT_BYTES + 1,
                maximum: MAX_CONTEXT_BYTES,
            })
        );
    }

    #[test]
    fn oversized_context_field_is_rejected() {
        let value = format!(
            "{{\"application\":\"{}\"}}",
            "x".repeat(MAX_CONTEXT_FIELD_BYTES + 1)
        );
        assert_eq!(
            decode_context(value.as_bytes()),
            Err(LocalDecodeError::ContextFieldTooLarge {
                field: "application",
                actual: MAX_CONTEXT_FIELD_BYTES + 1,
                maximum: MAX_CONTEXT_FIELD_BYTES,
            })
        );
    }

    #[test]
    fn oversized_png_is_rejected_before_decode() {
        let bytes = vec![0_u8; MAX_PNG_BYTES + 1];
        assert_eq!(
            decode_png(&bytes),
            Err(LocalDecodeError::ImageTooLarge {
                actual: MAX_PNG_BYTES + 1,
                maximum: MAX_PNG_BYTES,
            })
        );
    }

    #[test]
    fn malformed_png_is_rejected() {
        let error = decode_png(b"not a png").expect_err("PNG must fail");
        assert!(matches!(error, LocalDecodeError::MalformedImage(_)));
    }

    #[test]
    fn sealed_bundle_decodes_to_text_first_local_preparation_input() {
        let root = tempfile::tempdir().expect("vault root");
        let vault = Vault::new(root.path()).expect("vault");
        let generation = GenerationId::new("generation-1").expect("generation");
        let keypair = GenerationKeypair::generate(generation.clone());
        vault
            .register_public_key(&generation, keypair.public_key())
            .expect("public key");
        let capture = CaptureId::new("capture-1").expect("capture");
        let image = png_fixture();
        vault
            .seal(
                &BundleInput::new(
                    capture.clone(),
                    generation,
                    UNIX_EPOCH + Duration::from_secs(1),
                    image,
                    SampledContext::new(br#"{"application":"Editor"}"#.to_vec()),
                    Vec::new(),
                ),
                keypair.public_key(),
            )
            .expect("sealed bundle");
        let opened = vault
            .open_with_private_key(&capture, keypair.private_key())
            .expect("opened bundle");
        let decoder = LocalBundleDecoder::new(Arc::new(NoopRecognizer));
        let input = decoder.decode(&opened).expect("local preparation input");

        assert_eq!(input.capture_id(), &capture);
        let debug = format!("{input:?}");
        assert!(debug.contains("image: Some(\"present\")"));
        assert!(!debug.contains("[1, 2, 3]"));
    }

    fn png_fixture() -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut encoder = png::Encoder::new(&mut bytes, 1, 1);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header");
        writer.write_image_data(&[1, 2, 3]).expect("PNG pixels");
        writer.finish().expect("PNG finish");
        bytes
    }

    #[derive(Debug)]
    struct NoopRecognizer;

    impl ImageRecognizer for NoopRecognizer {
        fn recognize_image(&self, image: &Image) -> qaptr_domain::Result<RecognitionResult> {
            Ok(RecognitionResult::for_image(
                qaptr_domain::ports::OcrResult::default(),
                qaptr_domain::ports::VisionResult::default(),
                image,
            ))
        }
    }
}
