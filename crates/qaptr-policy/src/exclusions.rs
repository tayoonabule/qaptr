//! Pre-seal application and window exclusion rules.

use std::collections::BTreeSet;

use qaptr_domain::ports::ContextSnapshot;
use qaptr_vault::{BundleInput, BundleMetadata, GenerationPublicKey, Vault, VaultError};
use thiserror::Error;

/// Why a capture was excluded before sealing.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExclusionReason {
    /// The active application is on the exclusion list.
    Application,
    /// The active window title is on the exclusion list.
    Window,
}

/// The result of applying exclusion rules to one capture.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CaptureDecision {
    /// The capture was sealed and can be referenced by its vault metadata.
    Sealed(BundleMetadata),
    /// The capture was rejected before any vault directory was created.
    Excluded(ExclusionReason),
}

/// Errors returned while applying an allowed capture to the vault.
#[derive(Debug, Error)]
pub enum PolicyError {
    /// The vault could not seal an allowed capture.
    #[error(transparent)]
    Vault(#[from] VaultError),
}

/// Exact-match application and window exclusion lists.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ExclusionRules {
    applications: BTreeSet<String>,
    windows: BTreeSet<String>,
}

impl ExclusionRules {
    /// Creates empty exclusion lists.
    pub const fn new() -> Self {
        Self {
            applications: BTreeSet::new(),
            windows: BTreeSet::new(),
        }
    }

    /// Adds an exact application name to the exclusion list.
    pub fn exclude_application(&mut self, application: impl Into<String>) {
        self.applications.insert(application.into());
    }

    /// Adds an exact window title to the exclusion list.
    pub fn exclude_window(&mut self, window_title: impl Into<String>) {
        self.windows.insert(window_title.into());
    }

    /// Returns the first matching exclusion reason without exposing the value
    /// in the result.
    pub fn reason(&self, context: &ContextSnapshot) -> Option<ExclusionReason> {
        if context
            .application()
            .is_some_and(|application| self.applications.contains(application))
        {
            return Some(ExclusionReason::Application);
        }
        context
            .window_title()
            .is_some_and(|window| self.windows.contains(window))
            .then_some(ExclusionReason::Window)
    }

    /// Returns whether this context must be excluded before sealing.
    pub fn excludes(&self, context: &ContextSnapshot) -> bool {
        self.reason(context).is_some()
    }
}

/// Applies exclusions before invoking [`Vault::seal`].
pub fn seal_if_allowed(
    vault: &Vault,
    input: &BundleInput,
    public_key: &GenerationPublicKey,
    context: &ContextSnapshot,
    rules: &ExclusionRules,
) -> Result<CaptureDecision, PolicyError> {
    if let Some(reason) = rules.reason(context) {
        return Ok(CaptureDecision::Excluded(reason));
    }
    Ok(CaptureDecision::Sealed(vault.seal(input, public_key)?))
}
