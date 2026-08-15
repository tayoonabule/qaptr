//! Safe, scalar status detection for the supported local CLIs.
//!
//! This module never starts a provider, reads credentials, or asks a provider
//! to analyze anything. The production convenience path is executable-only:
//! it can report `Detected` when a command is present, but leaves
//! authentication unknown. Authentication is included only when an explicitly
//! injected process probe supplies a typed result, which keeps tests
//! deterministic and makes the proof boundary visible to callers.

use qaptr_provider::{AuthenticationStatus, ExecutablePath};

use crate::{ExecutableDiscovery, ExecutableProbeStatus};

/// One of the supported CLI installations.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum CliProvider {
    /// Anthropic's Claude Code CLI.
    Claude,
    /// OpenAI's Codex CLI.
    Codex,
    /// The Jcode CLI.
    Jcode,
}

impl CliProvider {
    /// Returns the stable provider identifier used by qaptr-provider.
    pub const fn id(self) -> &'static str {
        match self {
            Self::Claude => "claude-cli",
            Self::Codex => "codex",
            Self::Jcode => "jcode",
        }
    }

    /// Returns the executable name searched by this provider.
    pub const fn command(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Jcode => "jcode",
        }
    }
}

/// The only status values a UI needs for a local CLI installation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CliDetectionStatus {
    /// The executable probe could not complete truthfully.
    Unavailable,
    /// The executable was not found in the explicitly supplied search paths.
    NotInstalled,
    /// The executable was found. Authentication is `None` unless separately
    /// proven by a caller-owned, injected process probe.
    Detected {
        /// Authentication state, when a probe proved it without ambiguity.
        authentication: Option<AuthenticationStatus>,
    },
}

impl CliDetectionStatus {
    /// Returns whether an executable was found.
    pub const fn is_detected(&self) -> bool {
        matches!(self, Self::Detected { .. })
    }

    /// Returns the authentication state only when it was proven.
    pub const fn authentication(&self) -> Option<AuthenticationStatus> {
        match self {
            Self::Detected { authentication } => *authentication,
            Self::Unavailable | Self::NotInstalled => None,
        }
    }
}

/// A path-only seam for deterministic status detection.
pub trait CliPathProbe {
    /// Probes the executable for one provider without starting it.
    fn probe_path(&self, provider: CliProvider) -> ExecutableProbeStatus;
}

impl CliPathProbe for ExecutableDiscovery {
    fn probe_path(&self, provider: CliProvider) -> ExecutableProbeStatus {
        self.probe(provider.command())
    }
}

/// An optional authentication seam. Production detection does not provide one.
/// Tests or a future, separately reviewed integration may inject a probe that
/// can prove authentication without exposing credentials to this API.
pub trait CliProcessProbe {
    /// Returns a typed authentication result, or `None` when it cannot prove one.
    fn probe_authentication(
        &self,
        provider: CliProvider,
        executable: &ExecutablePath,
    ) -> Option<AuthenticationStatus>;
}

/// Detects one CLI using only an injected path probe.
pub fn detect_cli(provider: CliProvider, path_probe: &impl CliPathProbe) -> CliDetectionStatus {
    detect_cli_with_process_probe(provider, path_probe, None)
}

/// Detects one supported CLI in the standard non-invasive search locations.
///
/// This is intentionally path-only. A `Detected` result means the executable
/// is present and executable; it does not imply that the provider is logged in.
pub fn detect_cli_installation(provider: CliProvider) -> CliDetectionStatus {
    let discovery = ExecutableDiscovery::new(crate::adapters::default_search_paths());
    detect_cli(provider, &discovery)
}

/// Detects one CLI and optionally records authentication from an injected probe.
///
/// Passing `None` is the production-safe mode. It never launches a binary or
/// reads provider state, so a detected executable remains authentication-unknown.
pub fn detect_cli_with_process_probe(
    provider: CliProvider,
    path_probe: &impl CliPathProbe,
    process_probe: Option<&dyn CliProcessProbe>,
) -> CliDetectionStatus {
    match path_probe.probe_path(provider) {
        ExecutableProbeStatus::Unavailable => CliDetectionStatus::Unavailable,
        ExecutableProbeStatus::NotInstalled => CliDetectionStatus::NotInstalled,
        ExecutableProbeStatus::Detected(executable) => CliDetectionStatus::Detected {
            authentication: process_probe
                .and_then(|probe| probe.probe_authentication(provider, &executable)),
        },
    }
}
