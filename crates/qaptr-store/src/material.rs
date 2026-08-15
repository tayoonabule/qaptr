//! Writer-side detection of image material smuggled through scalar text fields.

use crate::{Result, StoreError};

const MIN_BASE64_RUN: usize = 128;

pub(crate) fn validate_text(field: &'static str, value: &str) -> Result<()> {
    let lower = value.to_ascii_lowercase();
    let compact = compact_ascii_whitespace(&lower);
    if compact.contains("data:image/")
        || starts_with_image_magic(value.trim_start().as_bytes())
        || has_known_base64_image_prefix(value)
        || has_decoded_base64_image_prefix(value)
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
    let prefixes = [
        "iVBORw0KGgo",
        "/9j/",
        "R0lGOD",
        "UklGR",
        "Qk0",
        "SUkq",
        "TU0A",
    ];
    for_each_base64_run(value, |run| {
        prefixes.iter().any(|prefix| run.contains(prefix))
    })
}

fn has_long_base64_run(value: &str) -> bool {
    value
        .split(|character: char| {
            !character.is_ascii_alphanumeric() && !matches!(character, '+' | '/' | '=')
        })
        .any(|run| run.len() >= MIN_BASE64_RUN && run.len().is_multiple_of(4))
}

fn has_decoded_base64_image_prefix(value: &str) -> bool {
    for_each_base64_run(value, |run| {
        if run.len() < 16 {
            return false;
        }
        starts_with_image_magic(&decode_base64_prefix(run.as_bytes()))
    })
}

fn for_each_base64_run(value: &str, mut predicate: impl FnMut(&str) -> bool) -> bool {
    let mut run = String::new();
    for character in value.chars() {
        if character.is_ascii_alphanumeric() || matches!(character, '+' | '/' | '=') {
            run.push(character);
        } else if character.is_ascii_whitespace() {
            continue;
        } else {
            if predicate(&run) {
                return true;
            }
            run.clear();
        }
    }
    predicate(&run)
}

fn compact_ascii_whitespace(value: &str) -> String {
    value
        .chars()
        .filter(|character| !character.is_ascii_whitespace())
        .collect()
}

fn decode_base64_prefix(value: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(12);
    let mut buffer = 0_u32;
    let mut bits = 0_u8;
    for &byte in value {
        if byte == b'=' {
            break;
        }
        let Some(digit) = base64_digit(byte) else {
            break;
        };
        buffer = (buffer << 6) | u32::from(digit);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            output.push((buffer >> bits) as u8);
            if output.len() == 16 {
                break;
            }
            if bits == 0 {
                buffer = 0;
            } else {
                buffer &= (1 << bits) - 1;
            }
        }
    }
    output
}

fn base64_digit(byte: u8) -> Option<u8> {
    match byte {
        b'A'..=b'Z' => Some(byte - b'A'),
        b'a'..=b'z' => Some(byte - b'a' + 26),
        b'0'..=b'9' => Some(byte - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
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
    fn rejects_a_whitespace_interleaved_base64_png_prefix() {
        let encoded = "iV BO\nRw0K GgoA".to_owned() + &"A".repeat(120);
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
