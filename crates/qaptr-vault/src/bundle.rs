//! Bundle payload types and the on-disk manifest.

use std::{
    fmt, str,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use qaptr_domain::CaptureId;

use crate::{FORMAT_VERSION, VaultError};

/// The sampled, structured context associated with a capture.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SampledContext(Vec<u8>);

impl SampledContext {
    /// Creates context bytes for a capture.
    pub fn new(bytes: impl Into<Vec<u8>>) -> Self {
        Self(bytes.into())
    }

    /// Returns the serialized context bytes.
    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

/// Plaintext image bytes supplied to the sealing boundary by the capture
/// helper. This type is intentionally not present in [`OpenedBundle`] as a
/// public field.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BundleInput {
    /// Bundle identity and generation metadata.
    pub metadata: BundleMetadata,
    /// Downscaled image bytes to encrypt.
    pub image: Vec<u8>,
    /// Point-in-time sampled context to encrypt.
    pub context: SampledContext,
    /// Derived artifacts to encrypt alongside the image and context.
    pub derived_artifacts: Vec<u8>,
}

impl BundleInput {
    /// Creates a bundle input after validating the ids.
    pub fn new(
        capture_id: CaptureId,
        generation_id: crate::GenerationId,
        captured_at: SystemTime,
        image: Vec<u8>,
        context: SampledContext,
        derived_artifacts: Vec<u8>,
    ) -> Self {
        Self {
            metadata: BundleMetadata {
                capture_id,
                generation_id,
                captured_at,
            },
            image,
            context,
            derived_artifacts,
        }
    }
}

/// Non-sensitive metadata needed to locate and authenticate a bundle.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BundleMetadata {
    /// Stable capture identifier.
    pub capture_id: CaptureId,
    /// Key generation used to encrypt all members.
    pub generation_id: crate::GenerationId,
    /// Instant at which the capture was made.
    pub captured_at: SystemTime,
}

impl BundleMetadata {
    pub(crate) fn manifest(&self) -> crate::Result<String> {
        let captured_at_ms = self
            .captured_at
            .duration_since(UNIX_EPOCH)
            .map_err(|_| VaultError::InvalidTimestamp(self.capture_id.to_string()))?
            .as_millis();
        let captured_at_ms = u64::try_from(captured_at_ms)
            .map_err(|_| VaultError::InvalidTimestamp(self.capture_id.to_string()))?;
        Ok(format!(
            "version={FORMAT_VERSION}\ncapture_id={}\ngeneration_id={}\ncaptured_at_ms={captured_at_ms}\n",
            self.capture_id, self.generation_id
        ))
    }

    pub(crate) fn from_manifest(
        bytes: &[u8],
        expected_capture_id: &CaptureId,
    ) -> crate::Result<Self> {
        let manifest = str::from_utf8(bytes)
            .map_err(|_| VaultError::InvalidManifest(expected_capture_id.to_string()))?;
        let mut version = None;
        let mut capture_id = None;
        let mut generation_id = None;
        let mut captured_at_ms = None;
        for line in manifest.lines() {
            let (key, value) = line
                .split_once('=')
                .ok_or_else(|| VaultError::InvalidManifest(expected_capture_id.to_string()))?;
            match key {
                "version" => version = value.parse::<u8>().ok(),
                "capture_id" => capture_id = Some(value.to_owned()),
                "generation_id" => generation_id = Some(value.to_owned()),
                "captured_at_ms" => captured_at_ms = value.parse::<u64>().ok(),
                _ => return Err(VaultError::InvalidManifest(expected_capture_id.to_string())),
            }
        }
        if version != Some(FORMAT_VERSION)
            || capture_id.as_deref() != Some(expected_capture_id.as_str())
        {
            return Err(VaultError::InvalidManifest(expected_capture_id.to_string()));
        }
        let capture_id = CaptureId::new(
            capture_id
                .ok_or_else(|| VaultError::InvalidManifest(expected_capture_id.to_string()))?,
        )
        .map_err(|_| VaultError::InvalidManifest(expected_capture_id.to_string()))?;
        let generation_id = generation_id
            .ok_or_else(|| VaultError::InvalidManifest(expected_capture_id.to_string()))?
            .parse()?;
        let captured_at = UNIX_EPOCH
            .checked_add(Duration::from_millis(captured_at_ms.ok_or_else(|| {
                VaultError::InvalidManifest(expected_capture_id.to_string())
            })?))
            .ok_or_else(|| VaultError::InvalidManifest(expected_capture_id.to_string()))?;
        Ok(Self {
            capture_id,
            generation_id,
            captured_at,
        })
    }
}

/// An opened bundle whose image is reserved for the privacy boundary.
pub struct OpenedBundle {
    metadata: BundleMetadata,
    image: PrivacyImage,
    context: SampledContext,
    derived_artifacts: Vec<u8>,
}

impl OpenedBundle {
    pub(crate) fn new(
        metadata: BundleMetadata,
        image: Vec<u8>,
        context: Vec<u8>,
        derived_artifacts: Vec<u8>,
    ) -> Self {
        Self {
            metadata,
            image: PrivacyImage::new(image),
            context: SampledContext::new(context),
            derived_artifacts,
        }
    }

    /// Returns bundle metadata without exposing image bytes.
    pub fn metadata(&self) -> &BundleMetadata {
        &self.metadata
    }

    /// Returns sampled context bytes for sanitization.
    pub fn context(&self) -> &SampledContext {
        &self.context
    }

    /// Returns derived artifacts for privacy processing.
    pub fn derived_artifacts(&self) -> &[u8] {
        &self.derived_artifacts
    }

    /// Grants the decrypted image to the privacy processing callback.
    ///
    /// This is the sole image plaintext boundary. The callback is deliberately
    /// scoped to the call and the image is not returned as a `Vec<u8>`.
    pub fn with_image_for_privacy<R>(&self, callback: impl FnOnce(&PrivacyImage) -> R) -> R {
        callback(&self.image)
    }
}

/// Decrypted image material reserved for the privacy crate.
pub struct PrivacyImage(Vec<u8>);

impl PrivacyImage {
    pub(crate) fn new(bytes: Vec<u8>) -> Self {
        Self(bytes)
    }

    /// Provides a read-only view to the privacy callback.
    pub fn with_bytes<R>(&self, callback: impl FnOnce(&[u8]) -> R) -> R {
        callback(&self.0)
    }
}

impl fmt::Debug for PrivacyImage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("PrivacyImage([redacted])")
    }
}
