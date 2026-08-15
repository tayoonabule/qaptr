//! App-owned, atomic Markdown export saving.

use std::path::{Path, PathBuf};

use qaptr_vault::VaultError;
use thiserror::Error;

use crate::{Cancellation, WorkflowDocument};

/// The four Markdown audiences supported by the workflow export surface.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MarkdownExportVariant {
    /// A descriptive, non-executing automation procedure.
    Automation,
    /// A document for aligning people and tools around the workflow.
    Handoff,
    /// A guided walkthrough for onboarding.
    Onboarding,
    /// A formal standard operating procedure.
    Sop,
}

impl MarkdownExportVariant {
    fn render(self, workflow: &WorkflowDocument) -> String {
        match self {
            Self::Automation => super::render_automation(workflow),
            Self::Handoff => super::render_handoff(workflow),
            Self::Onboarding => super::render_onboarding(workflow),
            Self::Sop => super::render_sop(workflow),
        }
    }
}

/// Errors raised while saving an app-owned Markdown export.
#[derive(Debug, Error)]
pub enum ExportError {
    /// Cancellation was observed before the atomic write began.
    #[error("Markdown export was cancelled before writing")]
    Cancelled,
    /// The atomic filesystem operation failed.
    #[error("could not write Markdown export to {destination}: {source}")]
    Write {
        /// The caller-owned destination selected for the export.
        destination: PathBuf,
        /// The underlying filesystem failure.
        #[source]
        source: Box<VaultError>,
    },
}

/// Saves one scalar-only workflow rendering to a caller-selected destination.
///
/// The destination is supplied by the app, such as a native save panel. This
/// function does not choose a developer path, create parent directories, read
/// capture or provider material, or launch an app, agent, or automation. The
/// rendered Markdown is written through the vault's atomic filesystem seam.
/// Cancellation is cooperative and observed before the write begins; an OS
/// write already in progress cannot be truthfully reported as cancelled.
pub fn save_markdown_export(
    workflow: &WorkflowDocument,
    variant: MarkdownExportVariant,
    destination: impl AsRef<Path>,
    cancellation: &impl Cancellation,
) -> Result<(), ExportError> {
    if cancellation.is_cancelled() {
        return Err(ExportError::Cancelled);
    }

    let destination = destination.as_ref().to_owned();
    let markdown = variant.render(workflow);

    if cancellation.is_cancelled() {
        return Err(ExportError::Cancelled);
    }

    qaptr_vault::atomic_write(&destination, markdown.as_bytes()).map_err(|source| {
        ExportError::Write {
            destination,
            source: Box::new(source),
        }
    })
}
