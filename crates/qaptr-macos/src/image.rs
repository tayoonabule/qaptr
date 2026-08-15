//! Exact-image local recognition for the privacy boundary.

use std::fs::{self, OpenOptions};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use qaptr_domain::{CaptureId, DomainError, Result};
use qaptr_privacy::{Image, ImageRecognizer, RecognitionResult};

use crate::error::MacosError;
use crate::{MacOcr, MacVision};

static TEMP_IMAGE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

/// A local Vision recognizer bound to the exact RGB image supplied by the
/// privacy gate.
#[derive(Clone, Debug)]
pub struct MacImageRecognizer {
    helper: PathBuf,
    timeout: Duration,
    temp_root: PathBuf,
}

impl MacImageRecognizer {
    /// Creates a recognizer using Qaptr's compiled Vision helper.
    pub fn new() -> Self {
        Self::with_helper(
            PathBuf::from(env!("QAPTR_VISION_HELPER")),
            Duration::from_secs(2),
        )
    }

    /// Creates a recognizer with an explicit helper and deadline.
    pub fn with_helper(helper: impl Into<PathBuf>, timeout: Duration) -> Self {
        Self::with_helper_in(helper, timeout, std::env::temp_dir())
    }

    /// Creates a recognizer with an explicit private temporary-file parent.
    ///
    /// The parent is useful for deterministic tests. Production callers should
    /// normally use [`Self::with_helper`] so the OS temporary directory is
    /// selected by the process environment.
    pub fn with_helper_in(
        helper: impl Into<PathBuf>,
        timeout: Duration,
        temp_root: impl Into<PathBuf>,
    ) -> Self {
        Self {
            helper: helper.into(),
            timeout,
            temp_root: temp_root.into(),
        }
    }

    /// Recognizes one exact image and returns only typed local findings.
    pub fn recognize_value(
        &self,
        image: &Image,
    ) -> std::result::Result<RecognitionResult, MacosError> {
        let temporary = PrivateImage::create(&self.temp_root)?;
        let result = (|| {
            let capture = CaptureId::new("capture").map_err(|error| MacosError::Recognition {
                operation: "image",
                message: error.to_string(),
            })?;
            write_png(&temporary.path, image)?;

            let ocr = MacOcr::with_helper(&temporary.root, &self.helper, self.timeout)
                .recognize_value(&capture)?;
            let vision = MacVision::with_helper(&temporary.root, &self.helper, self.timeout)
                .detect_value(&capture)?;
            Ok(RecognitionResult::for_image(ocr, vision, image))
        })();
        let cleanup = temporary.cleanup();
        match (result, cleanup) {
            (Ok(result), Ok(())) => Ok(result),
            (Err(error), _) => Err(error),
            (Ok(_), Err(error)) => Err(error),
        }
    }
}

impl Default for MacImageRecognizer {
    fn default() -> Self {
        Self::new()
    }
}

impl ImageRecognizer for MacImageRecognizer {
    fn recognize_image(&self, image: &Image) -> Result<RecognitionResult> {
        self.recognize_value(image).map_err(|error| match error {
            MacosError::RecognitionTimeout { operation } => DomainError::TimedOut { operation },
            other => DomainError::Failed {
                operation: "image recognition",
                reason: other.to_string(),
            },
        })
    }
}

struct PrivateImage {
    root: PathBuf,
    path: PathBuf,
    cleaned: bool,
}

impl PrivateImage {
    fn create(parent: &Path) -> std::result::Result<Self, MacosError> {
        fs::create_dir_all(parent)
            .map_err(|error| recognition_io_error("create temp root", error))?;
        for _ in 0..16 {
            let sequence = TEMP_IMAGE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let root = parent.join(format!(".qaptr-image-{}-{sequence}", std::process::id()));
            match fs::create_dir(&root) {
                Ok(()) => {
                    if let Err(error) =
                        fs::set_permissions(&root, fs::Permissions::from_mode(0o700))
                    {
                        let _ = fs::remove_dir_all(&root);
                        return Err(recognition_io_error(
                            "restrict temp directory permissions",
                            error,
                        ));
                    }
                    return Ok(Self {
                        path: root.join("capture.png"),
                        root,
                        cleaned: false,
                    });
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(recognition_io_error("create temp directory", error)),
            }
        }
        Err(MacosError::Recognition {
            operation: "image",
            message: "could not allocate a private temporary directory".to_owned(),
        })
    }

    fn cleanup(mut self) -> std::result::Result<(), MacosError> {
        let result = fs::remove_dir_all(&self.root)
            .map_err(|error| recognition_io_error("remove temp image", error));
        if result.is_ok() {
            self.cleaned = true;
        }
        result
    }
}

impl Drop for PrivateImage {
    fn drop(&mut self) {
        if !self.cleaned {
            let _ = fs::remove_dir_all(&self.root);
        }
    }
}

fn write_png(path: &Path, image: &Image) -> std::result::Result<(), MacosError> {
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| recognition_io_error("create temp image", error))?;
    let mut encoder = png::Encoder::new(file, image.width(), image.height());
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .map_err(|error| recognition_io_error("restrict temp image permissions", error))?;
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder
        .write_header()
        .map_err(|error| recognition_error("encode image header", error))?;
    writer
        .write_image_data(image.pixels())
        .map_err(|error| recognition_error("encode image", error))?;
    writer
        .finish()
        .map_err(|error| recognition_error("finish image", error))?;
    Ok(())
}

fn recognition_io_error(operation: &'static str, error: std::io::Error) -> MacosError {
    MacosError::Recognition {
        operation: "image",
        message: format!("{operation} failed: {error}"),
    }
}

fn recognition_error(operation: &'static str, error: impl std::fmt::Display) -> MacosError {
    MacosError::Recognition {
        operation: "image",
        message: format!("{operation} failed: {error}"),
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    use qaptr_privacy::{ImageHash, ImageRecognizer};

    use super::*;

    #[test]
    fn exact_image_recognition_deletes_private_png_before_return() {
        let parent = test_directory("recognizer");
        let root = parent.join("images");
        fs::create_dir(&root).expect("image root");
        let helper = parent.join("helper.sh");
        fs::write(&helper, "#!/bin/sh\nprintf 'ok\\n'\n").expect("helper script");
        let mut permissions = fs::metadata(&helper)
            .expect("helper metadata")
            .permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(&helper, permissions).expect("helper permissions");

        let image = Image::solid(2, 1, [1, 2, 3]).expect("image");
        let recognizer = MacImageRecognizer::with_helper_in(&helper, Duration::from_secs(1), &root);
        let result = recognizer
            .recognize_image(&image)
            .expect("recognition result");

        assert_eq!(result.source_image_hash(), Some(ImageHash::of(&image)));
        assert!(fs::read_dir(&root).expect("temp root").next().is_none());
        let _ = fs::remove_dir_all(parent);
    }

    fn test_directory(label: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            ".qaptr-{label}-{}-{}",
            std::process::id(),
            TEMP_IMAGE_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).expect("test directory");
        path
    }
}
