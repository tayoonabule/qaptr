//! Shared process boundary for the local Vision-framework helper.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use qaptr_domain::{CaptureId, Confidence, NormalizedRect};

use crate::error::MacosError;

/// One line returned by the local Vision helper.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct RecognitionRecord {
    /// The helper record kind, such as `text`, `face`, or `barcode`.
    pub(crate) kind: String,
    /// Base64-encoded text for OCR records, absent for visual findings.
    pub(crate) text_base64: Option<String>,
    /// Vision confidence.
    pub(crate) confidence: Confidence,
    /// Vision-normalized geometry.
    pub(crate) geometry: NormalizedRect,
}

/// Runs the compiled helper against one capture image and parses its records.
pub(crate) fn run_helper(
    helper: &Path,
    image_root: &Path,
    capture: &CaptureId,
    operation: &'static str,
    timeout: Duration,
) -> Result<Vec<RecognitionRecord>, MacosError> {
    let image_path = image_path(image_root, capture, operation)?;
    let mut child = Command::new(helper)
        .arg(operation)
        .arg(&image_path)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| MacosError::Recognition {
            operation,
            message: format!("could not start {}: {error}", helper.display()),
        })?;

    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let output = child
                    .wait_with_output()
                    .map_err(|error| MacosError::Recognition {
                        operation,
                        message: format!("could not collect helper output: {error}"),
                    })?;
                if !status.success() {
                    return Err(MacosError::Recognition {
                        operation,
                        message: bounded_message(&output.stderr),
                    });
                }
                return parse_records(&output.stdout, operation);
            }
            Ok(None) if started.elapsed() >= timeout => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(MacosError::RecognitionTimeout { operation });
            }
            Ok(None) => std::thread::yield_now(),
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(MacosError::Recognition {
                    operation,
                    message: format!("could not poll helper: {error}"),
                });
            }
        }
    }
}

fn image_path(
    image_root: &Path,
    capture: &CaptureId,
    operation: &'static str,
) -> Result<PathBuf, MacosError> {
    let value = capture.as_str();
    if value.is_empty()
        || value
            .chars()
            .any(|character| !(character.is_ascii_alphanumeric() || "-_".contains(character)))
    {
        return Err(MacosError::Recognition {
            operation,
            message: "capture id contains an unsafe image path component".to_owned(),
        });
    }
    let path = image_root.join(format!("{value}.png"));
    if !path.is_file() {
        return Err(MacosError::Recognition {
            operation,
            message: format!("capture image does not exist: {}", path.display()),
        });
    }
    Ok(path)
}

fn parse_records(
    stdout: &[u8],
    operation: &'static str,
) -> Result<Vec<RecognitionRecord>, MacosError> {
    let output = std::str::from_utf8(stdout).map_err(|error| MacosError::Recognition {
        operation,
        message: format!("helper returned non-UTF-8 output: {error}"),
    })?;
    let mut records = Vec::new();
    for line in output
        .lines()
        .filter(|line| !line.is_empty() && *line != "ok")
    {
        let fields: Vec<&str> = line.split('\t').collect();
        let (kind, text_base64, confidence, x, y, width, height) = match fields.as_slice() {
            [kind, text, confidence, x, y, width, height] if *kind == "text" => (
                (*kind).to_owned(),
                Some((*text).to_owned()),
                confidence,
                x,
                y,
                width,
                height,
            ),
            [kind, confidence, x, y, width, height] if *kind == "face" || *kind == "barcode" => {
                ((*kind).to_owned(), None, confidence, x, y, width, height)
            }
            _ => {
                return Err(MacosError::Recognition {
                    operation,
                    message: format!("malformed helper record: {line}"),
                });
            }
        };
        let confidence = parse_number(confidence, operation, "confidence")?;
        let geometry = NormalizedRect::new(
            parse_number(x, operation, "x")?,
            parse_number(y, operation, "y")?,
            parse_number(width, operation, "width")?,
            parse_number(height, operation, "height")?,
        )
        .map_err(|error| MacosError::Recognition {
            operation,
            message: error.to_string(),
        })?;
        let confidence = Confidence::new(confidence).map_err(|error| MacosError::Recognition {
            operation,
            message: error.to_string(),
        })?;
        records.push(RecognitionRecord {
            kind,
            text_base64,
            confidence,
            geometry,
        });
    }
    Ok(records)
}

fn parse_number(value: &str, operation: &'static str, name: &str) -> Result<f32, MacosError> {
    value
        .parse::<f32>()
        .map_err(|error| MacosError::Recognition {
            operation,
            message: format!("invalid {name} value {value:?}: {error}"),
        })
}

fn bounded_message(stderr: &[u8]) -> String {
    let message = String::from_utf8_lossy(stderr).trim().to_owned();
    if message.len() > 512 {
        message.chars().take(512).collect()
    } else if message.is_empty() {
        "helper exited unsuccessfully".to_owned()
    } else {
        message
    }
}

pub(crate) fn decode_base64(value: &str) -> Result<String, MacosError> {
    let bytes = decode_base64_bytes(value).ok_or_else(|| MacosError::Recognition {
        operation: "ocr",
        message: "helper returned invalid base64 text".to_owned(),
    })?;
    String::from_utf8(bytes).map_err(|error| MacosError::Recognition {
        operation: "ocr",
        message: format!("helper returned non-UTF-8 text: {error}"),
    })
}

fn decode_base64_bytes(value: &str) -> Option<Vec<u8>> {
    let mut output = Vec::with_capacity(value.len() * 3 / 4);
    let mut buffer = 0_u32;
    let mut bits = 0_u8;
    for byte in value.bytes() {
        if byte == b'=' {
            break;
        }
        let digit = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        } as u32;
        buffer = (buffer << 6) | digit;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            output.push((buffer >> bits) as u8);
            if bits > 0 {
                buffer &= (1 << bits) - 1;
            } else {
                buffer = 0;
            }
        }
    }
    Some(output)
}
