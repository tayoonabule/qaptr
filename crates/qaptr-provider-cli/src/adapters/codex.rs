//! Codex CLI adapter using the user's existing Codex OAuth/ChatGPT session.
//!
//! This module intentionally has no API-key input, credential field, or
//! credential environment variable. Codex authentication remains entirely
//! inside the installed Codex CLI.

use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, CapabilityDescriptor, ProviderAdapter,
    ProviderDescriptor, ProviderDetection, ProviderError, ProviderId, ProviderInvocation,
    ProviderLocation, ProviderRequestError, ProviderVersion, RawProviderResponse,
    RuntimeFailureKind,
};
use serde_json::Value;

use super::response::parse_response;
use super::{
    CliExecutor, CliInvocation, CliRuntime, CliRuntimeError, ExecutableDiscovery, add_support_path,
    analysis_prompt, default_discovery, home_directory, map_runtime_error,
};
use crate::VersionProbe;

const CODEX_COMMAND: &str = "codex";
const CODEX_MINIMUM_VERSION: ProviderVersion = ProviderVersion::new(0, 147, 0);
const CODEX_AUTH_FILE: &str = ".codex/auth.json";
const CODEX_AUTH_FILE_MAX_BYTES: u64 = 64 * 1024;

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
            && !output.contains("api key")
            && !output.contains("api-key")
            && !output.contains("apikey")
            && !output.contains("openai_api_key")
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
                .is_some_and(|home| auth_state_metadata_is_usable(&home.join(CODEX_AUTH_FILE)))
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

/// Accepts only the local ChatGPT OAuth shape, never API-key metadata.
///
/// The file is used only as a bounded authentication hint when the sandboxed
/// status probe cannot report a result. Token values are not returned, logged,
/// or forwarded to the provider.
fn auth_state_metadata_is_usable(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > CODEX_AUTH_FILE_MAX_BYTES {
        return false;
    }

    let Ok(contents) = std::fs::read(path) else {
        return false;
    };
    let Ok(Value::Object(object)) = serde_json::from_slice(&contents) else {
        return false;
    };

    if object.get("auth_mode").and_then(Value::as_str) != Some("chatgpt") {
        return false;
    }

    // A non-null OPENAI_API_KEY means this is API-key authentication, even if
    // an attacker also adds an OAuth-looking auth_mode or tokens object.
    if object
        .get("OPENAI_API_KEY")
        .is_some_and(|value| !value.is_null())
    {
        return false;
    }

    let Some(Value::Object(tokens)) = object.get("tokens") else {
        return false;
    };
    ["access_token", "refresh_token", "id_token"]
        .into_iter()
        .all(|name| {
            tokens
                .get(name)
                .and_then(Value::as_str)
                .is_some_and(|value| !value.is_empty())
        })
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

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::PathBuf,
        sync::atomic::{AtomicUsize, Ordering},
    };

    use super::{AuthenticationStatus, auth_state_metadata_is_usable};

    static NEXT_AUTH_FILE: AtomicUsize = AtomicUsize::new(0);

    fn auth_file(contents: &str) -> PathBuf {
        let suffix = NEXT_AUTH_FILE.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "qaptr-codex-auth-{}-{suffix}.json",
            std::process::id()
        ));
        fs::write(&path, contents).expect("test auth metadata can be written");
        path
    }

    fn oauth_auth_file(extra: &str) -> PathBuf {
        auth_file(&format!(
            r#"{{
                "auth_mode": "chatgpt",
                "tokens": {{
                    "access_token": "oauth-access",
                    "refresh_token": "oauth-refresh",
                    "id_token": "oauth-id"
                }}{extra}
            }}"#
        ))
    }

    #[test]
    fn auth_mode_apikey_is_not_authenticated() {
        let path = auth_file(
            r#"{
                "auth_mode": "apikey",
                "OPENAI_API_KEY": "test-api-key"
            }"#,
        );

        assert!(!auth_state_metadata_is_usable(&path));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn openai_api_key_metadata_is_not_authenticated() {
        let path = oauth_auth_file(
            r#",
                "OPENAI_API_KEY": "test-api-key""#,
        );

        assert!(!auth_state_metadata_is_usable(&path));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn fake_chatgpt_auth_file_without_oauth_tokens_is_not_authenticated() {
        let path = auth_file(r#"{"auth_mode":"chatgpt"}"#);

        assert!(!auth_state_metadata_is_usable(&path));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn chatgpt_oauth_auth_file_is_authenticated() {
        let path = oauth_auth_file("");

        assert!(auth_state_metadata_is_usable(&path));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn api_key_status_text_is_not_authenticated() {
        assert_eq!(
            super::CodexAdapter::authentication_status(b"Logged in using API key"),
            AuthenticationStatus::NotAuthenticated
        );
    }
}
