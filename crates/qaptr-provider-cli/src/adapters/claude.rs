//! Claude Code CLI provider adapter.
//!
//! This adapter detects an already-authenticated local Claude Code installation
//! and invokes it only through [`CliRuntime`]. Qaptr never receives, stores, or
//! forwards Claude login tokens. The runtime clears the environment, disables
//! tools, uses an empty temporary working directory, and bounds output and time.
//!
//! # Invariants
//!
//! * The adapter exposes only [`ProviderAdapter`]. Its invocation method receives
//!   U13's gate-created proof and cannot be called with a caller-created value.
//! * Detection returns authentication state, not credentials or token material.
//! * Claude sessions are non-persistent and all output is schema-checked before
//!   it reaches the shared normalization gate.

use std::{path::PathBuf, sync::Arc};

use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, CapabilityDescriptor, ProviderAdapter,
    ProviderDescriptor, ProviderDetection, ProviderError, ProviderId, ProviderInvocation,
    ProviderLocation, ProviderRequestError, ProviderVersion, RawProviderResponse,
    RuntimeFailureKind,
};
use serde_json::Value;

use super::response::parse_response;
use super::{
    CliExecutor, CliInvocation, CliRuntime, ExecutableDiscovery, add_support_path,
    default_discovery, home_directory, map_runtime_error,
};
use crate::VersionProbe;

const CLAUDE_COMMAND: &str = "claude";
const CLAUDE_MINIMUM_VERSION: ProviderVersion = ProviderVersion::new(2, 1, 0);
const CLAUDE_CONFIG_FILE: &str = ".claude.json";
const CLAUDE_CONFIG_DIR: &str = ".claude";
const CLAUDE_SETUP_DIR: &str = ".config/claude-setup";

/// A Claude CLI adapter that uses only the CLI's existing local login.
pub struct ClaudeAdapter {
    executor: Arc<dyn CliExecutor>,
    discovery: ExecutableDiscovery,
    home: Option<PathBuf>,
    descriptor: ProviderDescriptor,
}

impl ClaudeAdapter {
    /// Creates a production adapter using U14's real sandboxed runtime and
    /// explicit standard executable locations.
    pub fn new(runtime: CliRuntime) -> Result<Self, ProviderRequestError> {
        Self::with_executor(Arc::new(runtime), default_discovery())
    }

    /// Creates an adapter with an injectable executor for deterministic tests.
    pub fn with_executor(
        executor: Arc<dyn CliExecutor>,
        discovery: ExecutableDiscovery,
    ) -> Result<Self, ProviderRequestError> {
        let id = ProviderId::new("claude-cli")?;
        let descriptor = ProviderDescriptor::new(
            id,
            "Claude CLI",
            CLAUDE_MINIMUM_VERSION,
            AuthenticationMode::ExistingCliSession,
            CapabilityDescriptor::text_only(),
        )?;
        Ok(Self {
            executor,
            discovery,
            home: home_directory(),
            descriptor,
        })
    }

    /// Returns the minimum Claude version accepted by the capability gate.
    pub const fn minimum_version() -> ProviderVersion {
        CLAUDE_MINIMUM_VERSION
    }

    fn invocation(&self, executable: qaptr_provider::ExecutablePath) -> CliInvocation {
        let executable_directory = PathBuf::from(executable.as_str())
            .parent()
            .map(PathBuf::from);
        let mut invocation = CliInvocation::new(executable);
        if let Some(directory) = executable_directory {
            invocation = add_support_path(invocation, Some(&directory));
        }
        if let Some(home) = &self.home {
            invocation = invocation.environment("HOME", home.as_os_str().to_owned());
            invocation = add_support_path(invocation, Some(&home.join(CLAUDE_CONFIG_DIR)));
            invocation = add_support_path(invocation, Some(&home.join(CLAUDE_CONFIG_FILE)));
            invocation = add_support_path(invocation, Some(&home.join(CLAUDE_SETUP_DIR)));
        }
        invocation
    }

    fn run_probe(&self, invocation: CliInvocation) -> Result<super::CliOutput, ProviderError> {
        self.executor
            .run(invocation)
            .map_err(|error| map_runtime_error(self.descriptor.id(), error))
    }

    fn executable_from(
        &self,
        invocation: &ProviderInvocation<'_>,
    ) -> Result<qaptr_provider::ExecutablePath, ProviderError> {
        if invocation.verified_provider().descriptor().id() != self.descriptor.id() {
            return Err(ProviderError::RuntimeFailure {
                provider: self.descriptor.id().clone(),
                kind: RuntimeFailureKind::MismatchedVerification,
            });
        }
        match invocation.verified_provider().location() {
            ProviderLocation::Executable(path) => Ok(path.clone()),
            ProviderLocation::Endpoint(_) => Err(ProviderError::RuntimeFailure {
                provider: self.descriptor.id().clone(),
                kind: RuntimeFailureKind::MismatchedVerification,
            }),
        }
    }
}

impl ProviderAdapter for ClaudeAdapter {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        let location = self
            .discovery
            .find_for_provider(self.descriptor.id(), CLAUDE_COMMAND)?;
        let version_output = self.run_probe(self.invocation(location.clone()).arg("--version"))?;
        let version = VersionProbe::new(&String::from_utf8_lossy(version_output.stdout()))
            .map_err(|_| ProviderError::RuntimeFailure {
                provider: self.descriptor.id().clone(),
                kind: RuntimeFailureKind::VersionUnavailable,
            })?
            .version();
        let auth_output =
            self.run_probe(self.invocation(location.clone()).arg("auth").arg("status"))?;
        let authenticated =
            parse_auth_status(auth_output.stdout()).map_err(|_| ProviderError::RuntimeFailure {
                provider: self.descriptor.id().clone(),
                kind: RuntimeFailureKind::Detection,
            })?;
        let authentication = if authenticated {
            AuthenticationStatus::Authenticated
        } else {
            AuthenticationStatus::NotAuthenticated
        };
        Ok(ProviderDetection::installed(
            ProviderLocation::Executable(location),
            version,
            authentication,
        ))
    }

    fn invoke(
        &self,
        invocation: ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError> {
        let executable = self.executable_from(&invocation)?;
        let prompt = super::analysis_prompt(invocation.request().context());
        let output = self.run_probe(
            self.invocation(executable)
                .arg("--print")
                .arg("--output-format")
                .arg("json")
                .arg("--no-session-persistence")
                .arg("--tools")
                .arg("")
                .arg("--safe-mode")
                .arg("--disable-slash-commands")
                .arg("--no-chrome")
                .arg("--permission-mode")
                .arg("dontAsk")
                .stdin(prompt.into_bytes()),
        )?;
        parse_response(self.descriptor.id(), output.stdout())
    }
}

/// Parses Claude's auth status JSON without exposing any status metadata.
pub fn parse_auth_status(output: &[u8]) -> Result<bool, serde_json::Error> {
    let value: Value = serde_json::from_slice(output)?;
    value
        .get("loggedIn")
        .and_then(Value::as_bool)
        .ok_or_else(|| {
            serde_json::Error::io(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Claude auth status omitted loggedIn",
            ))
        })
}
