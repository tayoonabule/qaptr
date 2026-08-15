//! Writer-side detection of image material smuggled through scalar text fields.

use crate::{Result, StoreError};

const MIN_BASE64_RUN: usize = 128;

pub(crate) fn validate_text(field: &'static str, value: &str) -> Result<()> {
    let lower = value.to_ascii_lowercase();
    if lower.contains("data:image/")
        || starts_with_image_magic(value.as_bytes())
        || has_known_base64_image_prefix(value)
        || has_long_base64_run(value)
    {
        return Err(StoreError::EncodedImageMaterial {
            field: field.to_owned(),
        });
    }
    Ok(())
}

fn starts_with_image_magic(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG\r\n\x1a\n")
        || bytes.starts_with(&[0xff, 0xd8, 0xff])
        || bytes.starts_with(b"GIF87a")
        || bytes.starts_with(b"GIF89a")
        || bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP")
        || bytes.starts_with(b"BM")
        || bytes.starts_with(b"II*\0")
        || bytes.starts_with(b"MM\0*")
}

fn has_known_base64_image_prefix(value: &str) -> bool {
    [
        "iVBORw0KGgo",
        "/9j/",
        "R0lGOD",
        "UklGR",
        "Qk0",
        "SUkq",
        "TU0A",
    ]
    .iter()
    .any(|prefix| value.contains(prefix))
}

fn has_long_base64_run(value: &str) -> bool {
    value
        .split(|character: char| {
            !character.is_ascii_alphanumeric() && !matches!(character, '+' | '/' | '=')
        })
        .any(|run| run.len() >= MIN_BASE64_RUN && run.len().is_multiple_of(4))
}

#[cfg(test)]
mod tests {
    use super::validate_text;
    use crate::StoreError;

    #[test]
    fn accepts_a_long_human_summary() {
        let summary =
            "The export step was repeated after the recipient asked for a CSV. ".repeat(100);
        assert!(validate_text("observations.summary", &summary).is_ok());
    }

    #[test]
    fn rejects_a_base64_encoded_png_prefix() {
        let encoded = format!("iVBORw0KGgo{}", "A".repeat(120));
        assert!(matches!(
            validate_text("observations.summary", &encoded),
            Err(StoreError::EncodedImageMaterial { .. })
        ));
    }

    #[test]
    fn rejects_data_image_urls() {
        assert!(matches!(
            validate_text("observations.summary", "data:image/png;base64,AAAA"),
            Err(StoreError::EncodedImageMaterial { .. })
        ));
    }
}
