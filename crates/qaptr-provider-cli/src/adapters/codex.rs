//! Codex CLI adapter using the user's existing Codex OAuth/ChatGPT session.
//!
//! This module intentionally has no API-key input, credential field, or
//! credential environment variable. Codex authentication remains entirely
//! inside the installed Codex CLI.

use std::{path::PathBuf, sync::Arc};

use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, CapabilityDescriptor, ProviderAdapter,
    ProviderDescriptor, ProviderDetection, ProviderError, ProviderId, ProviderInvocation,
    ProviderLocation, ProviderRequestError, ProviderVersion, RawProviderResponse,
    RuntimeFailureKind,
};

use super::response::parse_response;
use super::{
    CliExecutor, CliInvocation, CliRuntime, CliRuntimeError, ExecutableDiscovery, add_support_path,
    analysis_prompt, default_discovery, home_directory, map_runtime_error,
};
use crate::VersionProbe;

const CODEX_COMMAND: &str = "codex";
const CODEX_MINIMUM_VERSION: ProviderVersion = ProviderVersion::new(0, 147, 0);

/// A Codex CLI adapter that uses only the CLI's existing local login.
pub struct CodexAdapter {
    executor: Arc<dyn CliExecutor>,
    discovery: ExecutableDiscovery,
    home: Option<PathBuf>,
    allow_auth_state_metadata: bool,
    descriptor: ProviderDescriptor,
}

impl CodexAdapter {
    /// Creates a production adapter using U14's real sandboxed runtime and
    /// explicit standard executable locations.
    pub fn new(runtime: CliRuntime) -> Result<Self, ProviderRequestError> {
        let mut adapter = Self::with_executor(Arc::new(runtime), default_discovery())?;
        adapter.allow_auth_state_metadata = true;
        Ok(adapter)
    }

    /// Creates an adapter with an injectable executor for deterministic tests.
    pub fn with_executor(
        executor: Arc<dyn CliExecutor>,
        discovery: ExecutableDiscovery,
    ) -> Result<Self, ProviderRequestError> {
        let id = ProviderId::new("codex")?;
        let descriptor = ProviderDescriptor::new(
            id,
            "Codex CLI",
            CODEX_MINIMUM_VERSION,
            AuthenticationMode::ExistingCliSession,
            CapabilityDescriptor::text_only(),
        )?;
        Ok(Self {
            executor,
            discovery,
            home: home_directory(),
            allow_auth_state_metadata: false,
            descriptor,
        })
    }

    /// Returns the minimum Codex version accepted by the capability gate.
    pub const fn minimum_version() -> ProviderVersion {
        CODEX_MINIMUM_VERSION
    }

    fn invocation(&self, executable: qaptr_provider::ExecutablePath) -> CliInvocation {
        let codex_home = self.home.as_ref().map(|home| home.join(".codex"));
        let mut invocation = CliInvocation::new(executable);
        if let Some(home) = &self.home {
            invocation = invocation.environment("HOME", home.as_os_str().to_owned());
        }
        if let Some(codex_home) = &codex_home {
            invocation = invocation.environment("CODEX_HOME", codex_home.as_os_str().to_owned());
        }
        add_support_path(invocation, codex_home.as_ref())
    }

    fn run_probe(&self, invocation: CliInvocation) -> Result<super::CliOutput, ProviderError> {
        self.executor
            .run(invocation)
            .map_err(|error| map_runtime_error(self.descriptor.id(), error))
    }

    fn authenticated(output: &[u8]) -> bool {
        let output = String::from_utf8_lossy(output).to_ascii_lowercase();
        !output.contains("not logged in")
            && (output.contains("logged in")
                || output.contains("authenticated")
                || output.contains("chatgpt"))
    }

    fn authentication_status(output: &[u8]) -> AuthenticationStatus {
        if Self::authenticated(output) {
            AuthenticationStatus::Authenticated
        } else {
            AuthenticationStatus::NotAuthenticated
        }
    }

    fn auth_state_metadata_exists(&self) -> bool {
        self.allow_auth_state_metadata
            && self
                .home
                .as_ref()
                .map(|home| home.join(".codex/auth.json"))
                .and_then(|path| std::fs::metadata(path).ok())
                .is_some_and(|metadata| metadata.is_file() && metadata.len() > 0)
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

impl ProviderAdapter for CodexAdapter {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        let location = self
            .discovery
            .find_for_provider(self.descriptor.id(), CODEX_COMMAND)?;
        let version_output = self.run_probe(self.invocation(location.clone()).arg("--version"))?;
        let version = VersionProbe::new(&String::from_utf8_lossy(version_output.stdout()))
            .map_err(|_| ProviderError::RuntimeFailure {
                provider: self.descriptor.id().clone(),
                kind: RuntimeFailureKind::VersionUnavailable,
            })?
            .version();
        let authentication = match self
            .executor
            .run(self.invocation(location.clone()).arg("login").arg("status"))
        {
            Ok(output) => {
                let status = Self::authentication_status(output.stdout());
                if status == AuthenticationStatus::NotAuthenticated
                    && self.auth_state_metadata_exists()
                {
                    AuthenticationStatus::Authenticated
                } else {
                    status
                }
            }
            Err(CliRuntimeError::NonZeroExit { stdout, .. }) => {
                if stdout.is_empty() && self.auth_state_metadata_exists() {
                    AuthenticationStatus::Authenticated
                } else {
                    Self::authentication_status(&stdout)
                }
            }
            Err(error) => return Err(map_runtime_error(self.descriptor.id(), error)),
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
        let prompt = analysis_prompt(invocation.request().context());
        let output = self.run_probe(
            self.invocation(executable)
                .arg("exec")
                .arg("--json")
                .arg("--ephemeral")
                .arg("--ignore-user-config")
                .arg("--ignore-rules")
                .arg("--skip-git-repo-check")
                .arg("--sandbox")
                .arg("read-only")
                .arg("--color")
                .arg("never")
                .arg("--disable")
                .arg("shell_tool")
                .stdin(prompt.into_bytes()),
        )?;
        parse_response(self.descriptor.id(), output.stdout())
    }
}
