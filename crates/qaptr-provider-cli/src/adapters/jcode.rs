//! Jcode CLI adapter using Jcode's existing local provider sessions.
//!
//! The adapter never receives or constructs a provider credential. Jcode owns
//! its configured OAuth or CLI-backed session and performs provider selection
//! internally when invoked with `--provider auto`.

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

const JCODE_COMMAND: &str = "jcode";
const JCODE_MINIMUM_VERSION: ProviderVersion = ProviderVersion::new(0, 75, 23);

/// A Jcode CLI adapter that leaves authentication inside Jcode.
pub struct JcodeAdapter {
    executor: Arc<dyn CliExecutor>,
    discovery: ExecutableDiscovery,
    home: Option<PathBuf>,
    descriptor: ProviderDescriptor,
}

impl JcodeAdapter {
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
        let id = ProviderId::new("jcode")?;
        let descriptor = ProviderDescriptor::new(
            id,
            "Jcode CLI",
            JCODE_MINIMUM_VERSION,
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

    /// Returns the minimum Jcode version accepted by the capability gate.
    pub const fn minimum_version() -> ProviderVersion {
        JCODE_MINIMUM_VERSION
    }

    fn invocation(&self, executable: qaptr_provider::ExecutablePath) -> CliInvocation {
        let jcode_home = self.home.as_ref().map(|home| home.join(".jcode"));
        let mut invocation = CliInvocation::new(executable);
        if let Some(home) = &self.home {
            invocation = invocation.environment("HOME", home.as_os_str().to_owned());
        }
        add_support_path(invocation, jcode_home.as_ref())
    }

    fn run_probe(&self, invocation: CliInvocation) -> Result<super::CliOutput, ProviderError> {
        self.executor
            .run(invocation)
            .map_err(|error| map_runtime_error(self.descriptor.id(), error))
    }

    fn authenticated(output: &[u8]) -> bool {
        String::from_utf8_lossy(output).lines().any(|line| {
            let fields: Vec<&str> = line.split('\t').collect();
            fields.len() >= 2
                && fields[1].eq_ignore_ascii_case("available")
                && matches!(fields[0], "jcode" | "openai" | "claude" | "grok-build")
        })
    }

    fn authentication_status(output: &[u8]) -> AuthenticationStatus {
        if Self::authenticated(output) {
            AuthenticationStatus::Authenticated
        } else {
            AuthenticationStatus::NotAuthenticated
        }
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

impl ProviderAdapter for JcodeAdapter {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        let location = self
            .discovery
            .find_for_provider(self.descriptor.id(), JCODE_COMMAND)?;
        let version_output = self.run_probe(self.invocation(location.clone()).arg("--version"))?;
        let version = VersionProbe::new(&String::from_utf8_lossy(version_output.stdout()))
            .map_err(|_| ProviderError::RuntimeFailure {
                provider: self.descriptor.id().clone(),
                kind: RuntimeFailureKind::VersionUnavailable,
            })?
            .version();
        let authentication = match self.executor.run(
            self.invocation(location.clone())
                .arg("auth")
                .arg("status")
                .arg("--quiet")
                .arg("--no-update"),
        ) {
            Ok(output) => Self::authentication_status(output.stdout()),
            Err(CliRuntimeError::NonZeroExit { stdout, .. }) => {
                Self::authentication_status(&stdout)
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
                .arg("run")
                .arg("--json")
                .arg("--quiet")
                .arg("--no-update")
                .arg("--no-selfdev")
                .arg("--provider")
                .arg("auto")
                .arg("--tool-profile")
                .arg("none")
                .arg("--disable-base-tools")
                .arg(prompt),
        )?;
        parse_response(self.descriptor.id(), output.stdout())
    }
}
