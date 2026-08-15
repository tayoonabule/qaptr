//! Pure, deterministic Markdown exports for a canonical [`WorkflowDocument`].

use std::fmt::Write as _;

use crate::document::{Artifact, ConfidenceAssessment, Provenance, WorkflowDocument};

pub mod automation;
pub mod handoff;
pub mod onboarding;
pub mod save;
pub mod sop;

/// Renders the Workflow as a non-executing automation procedure.
pub fn render_automation(workflow: &WorkflowDocument) -> String {
    automation::render(workflow)
}

/// Renders the Workflow as a team handoff document.
pub fn render_handoff(workflow: &WorkflowDocument) -> String {
    handoff::render(workflow)
}

/// Renders the Workflow as an onboarding guide.
pub fn render_onboarding(workflow: &WorkflowDocument) -> String {
    onboarding::render(workflow)
}

/// Renders the Workflow as a formal standard operating procedure.
pub fn render_sop(workflow: &WorkflowDocument) -> String {
    sop::render(workflow)
}

pub use save::{ExportError, MarkdownExportVariant, save_markdown_export};

pub(crate) fn heading(output: &mut String, level: usize, title: &str) {
    let _ = writeln!(output, "{} {title}\n", "#".repeat(level));
}

pub(crate) fn bullet(output: &mut String, label: &str, value: &str) {
    let indentation = if label.starts_with("  ") { "  " } else { "" };
    let label = label.trim_start();
    let _ = writeln!(output, "{indentation}- **{label}:** {}", safe_text(value));
}

pub(crate) fn confidence(output: &mut String, label: &str, assessment: &ConfidenceAssessment) {
    bullet(output, label, &confidence_text(assessment));
}

pub(crate) fn confidence_text(assessment: &ConfidenceAssessment) -> String {
    let mut value = match assessment.score() {
        Some(score) => {
            let percentage = score.as_f32() * 100.0;
            let level = if percentage < 50.0 {
                "LOW"
            } else if percentage < 80.0 {
                "MODERATE"
            } else {
                "HIGH"
            };
            format!("{level} ({percentage:.0}%)")
        }
        None => "UNKNOWN (not measured)".to_owned(),
    };
    if let Some(basis) = assessment.basis() {
        value.push_str(" — ");
        value.push_str(&safe_text(basis));
    }
    value
}

pub(crate) fn render_artifact_list(
    output: &mut String,
    heading_text: &str,
    artifacts: &[Artifact],
    empty_text: &str,
) {
    heading(output, 2, heading_text);
    if artifacts.is_empty() {
        let _ = writeln!(output, "{empty_text}\n");
        return;
    }
    for artifact in artifacts {
        let requirement = if artifact.required {
            "required"
        } else {
            "optional"
        };
        let description = artifact
            .description
            .as_deref()
            .map(safe_text)
            .unwrap_or_else(|| "No description was captured.".to_owned());
        let _ = writeln!(
            output,
            "- **{}** ({requirement}) — {description}",
            safe_text(&artifact.name)
        );
        confidence(output, "  Evidence", &artifact.confidence);
    }
    output.push('\n');
}

pub(crate) fn render_provenance(output: &mut String, provenance: &Provenance, empty_text: &str) {
    if provenance.is_empty() {
        let _ = writeln!(output, "{empty_text}");
        return;
    }
    if let Some(session_id) = &provenance.session_id {
        bullet(output, "Session", session_id.as_str());
    }
    if !provenance.observation_ids.is_empty() {
        let observations = provenance
            .observation_ids
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ");
        bullet(output, "Observations", &observations);
    }
    if !provenance.capture_ids.is_empty() {
        let captures = provenance
            .capture_ids
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ");
        bullet(output, "Captures", &captures);
    }
    if let Some(note) = &provenance.note {
        bullet(output, "Note", note);
    }
}

/// Replaces known redaction-token forms with natural-language prose.
///
/// Exports may be shared outside Qaptr. They therefore must not repeat the
/// class of a sanitized value such as an email, face, barcode, or API key.
pub(crate) fn safe_text(value: &str) -> String {
    const SENSITIVE_MARKERS: &[&str] = &[
        "[REDACTED_EMAIL]",
        "[EMAIL_REDACTED]",
        "<REDACTED_EMAIL>",
        "<EMAIL_REDACTED>",
        "{{REDACTED_EMAIL}}",
        "{{EMAIL_REDACTED}}",
        "[REDACTED_API_KEY]",
        "[API_KEY_REDACTED]",
        "<REDACTED_API_KEY>",
        "<API_KEY_REDACTED>",
        "{{REDACTED_API_KEY}}",
        "{{API_KEY_REDACTED}}",
        "[REDACTED_SECRET]",
        "[SECRET_REDACTED]",
        "<REDACTED_SECRET>",
        "<SECRET_REDACTED>",
        "{{REDACTED_SECRET}}",
        "{{SECRET_REDACTED}}",
        "[REDACTED_TOKEN]",
        "[TOKEN_REDACTED]",
        "<REDACTED_TOKEN>",
        "<TOKEN_REDACTED>",
        "{{REDACTED_TOKEN}}",
        "{{TOKEN_REDACTED}}",
        "[REDACTED_FACE]",
        "[FACE_REDACTED]",
        "<REDACTED_FACE>",
        "<FACE_REDACTED>",
        "{{REDACTED_FACE}}",
        "{{FACE_REDACTED}}",
        "[REDACTED_BARCODE]",
        "[BARCODE_REDACTED]",
        "<REDACTED_BARCODE>",
        "<BARCODE_REDACTED>",
        "{{REDACTED_BARCODE}}",
        "{{BARCODE_REDACTED}}",
    ];
    SENSITIVE_MARKERS
        .iter()
        .fold(value.to_owned(), |text, marker| {
            text.replace(marker, "a sensitive value")
        })
}
