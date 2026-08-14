//! Concrete CLI adapters for the required local providers.
//!
//! The adapters in this module are deliberately small provider-specific command
//! descriptions over the shared [`CliRuntime`]. They do not own credentials and
//! cannot receive one through [`qaptr_provider::ProviderAdapter`]. Every public
//! invocation is made with a [`qaptr_provider::ProviderInvocation`] proof created
//! by [`qaptr_provider::ProviderGate`].
//!
//! # Invariants
//!
//! * Codex and Jcode use only the authentication state already owned by their
//!   installed CLIs. No API-key environment variable or credential parameter is
//!   constructed here.
//! * Each adapter advertises text-only capability. Image requests are rejected
//!   by the shared provider gate before an adapter invocation is possible.
//! * CLI output is bounded by U14 and is parsed into the same raw response shape
//!   before U13 performs normalization and schema validation.

mod response;

pub mod claude;
pub mod codex;
pub mod jcode;

use std::path::PathBuf;

use qaptr_provider::{ProviderError, ProviderId};

pub use codex::CodexAdapter;
pub use jcode::JcodeAdapter;

use super::{CliInvocation, CliOutput, CliRuntime, CliRuntimeError, ExecutableDiscovery};

/// The execution seam shared by concrete CLI adapters.
///
/// The production implementation is [`CliRuntime`]. The seam exists solely so
/// response-shape and gate tests can use deterministic in-process fakes without
/// replacing the OS-enforced runtime in production.
pub trait CliExecutor: Send + Sync {
    /// Runs one already-constructed direct-argument invocation.
    fn run(&self, invocation: CliInvocation) -> Result<CliOutput, CliRuntimeError>;
}

impl CliExecutor for CliRuntime {
    fn run(&self, invocation: CliInvocation) -> Result<CliOutput, CliRuntimeError> {
        CliRuntime::run(self, invocation)
    }
}

/// Returns the explicit executable search paths used by the built-in adapters.
pub(crate) fn default_search_paths() -> Vec<PathBuf> {
    let mut paths = vec![
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/usr/local/bin"),
        PathBuf::from("/usr/bin"),
        PathBuf::from("/bin"),
    ];
    if let Some(home) = home_directory() {
        paths.insert(0, home.join(".local/bin"));
    }
    paths
}

/// Returns the user's home directory without consulting a login shell.
pub(crate) fn home_directory() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

/// Constructs an explicit discovery object for the built-in search locations.
pub(crate) fn default_discovery() -> ExecutableDiscovery {
    ExecutableDiscovery::new(default_search_paths())
}

/// Adds a support directory to an invocation without changing its command line.
pub(crate) fn add_support_path(invocation: CliInvocation, path: Option<&PathBuf>) -> CliInvocation {
    match path {
        Some(path) => invocation.support_path(path.clone()),
        None => invocation,
    }
}

/// Maps a runtime failure to the provider taxonomy at the adapter boundary.
pub(crate) fn map_runtime_error(provider: &ProviderId, error: CliRuntimeError) -> ProviderError {
    error.into_provider_error(provider)
}

/// Maps malformed or undecodable provider output to a typed runtime failure.
pub(crate) fn malformed_output(provider: &ProviderId) -> ProviderError {
    ProviderError::RuntimeFailure {
        provider: provider.clone(),
        kind: qaptr_provider::RuntimeFailureKind::Invocation,
    }
}

/// Returns the prompt contract shared by Codex and Jcode.
pub(crate) fn analysis_prompt(context: &str) -> String {
    format!(
        "Analyze this sanitized Qaptr context. Return only JSON matching this exact shape: {{\"observations\":[{{\"title\":string,\"summary\":string,\"confidence\":number}}],\"workflow\":{{\"title\":string,\"goal\":string}} or null}}. Do not call tools, write files, or include markdown fences. Context:\n{context}"
    )
}
