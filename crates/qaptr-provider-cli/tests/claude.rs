//! Claude CLI adapter contract and real-discovery tests.

#![cfg(target_os = "macos")]

use std::{
    collections::VecDeque,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{SystemTime, UNIX_EPOCH},
};

use qaptr_provider::{
    Capability, ProviderError, ProviderGate, ProviderRequest, ProviderVersion, RuntimeFailureKind,
};
use qaptr_provider_cli::adapters::{CliExecutor, claude::ClaudeAdapter};
use qaptr_provider_cli::{
    CliInvocation, CliOutput, CliRuntime, CliRuntimeError, ExecutableDiscovery, OutputLimit,
    RuntimeLimits, Timeout,
};

static NEXT_FIXTURE_ID: AtomicU64 = AtomicU64::new(0);

#[derive(Debug)]
struct FakeExecutor {
    outputs: Mutex<VecDeque<Result<CliOutput, CliRuntimeError>>>,
}

impl FakeExecutor {
    fn new(outputs: impl IntoIterator<Item = Result<CliOutput, CliRuntimeError>>) -> Arc<Self> {
        Arc::new(Self {
            outputs: Mutex::new(outputs.into_iter().collect()),
        })
    }
}

impl CliExecutor for FakeExecutor {
    fn run(&self, _invocation: CliInvocation) -> Result<CliOutput, CliRuntimeError> {
        self.outputs
            .lock()
            .expect("test executor mutex is not poisoned")
            .pop_front()
            .expect("test supplied enough CLI outputs")
    }
}

fn executable_discovery() -> (ExecutableDiscovery, PathBuf) {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("test clock is after Unix epoch")
        .as_nanos();
    let sequence = NEXT_FIXTURE_ID.fetch_add(1, Ordering::Relaxed);
    let directory = std::env::temp_dir().join(format!("qaptr-u15-claude-{stamp}-{sequence}"));
    fs::create_dir(&directory).expect("test directory can be created");
    let executable = directory.join("claude");
    fs::write(&executable, b"fake").expect("test executable can be written");
    let mut permissions = fs::metadata(&executable)
        .expect("test executable metadata exists")
        .permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&executable, permissions).expect("test executable can be made executable");
    (ExecutableDiscovery::new([directory]), executable)
}

fn output(value: &str) -> Result<CliOutput, CliRuntimeError> {
    Ok(CliOutput::new(value.as_bytes().to_vec(), Vec::new()))
}

const RESPONSE: &str = r#"{"result":"{\"observations\":[{\"title\":\"Observed\",\"summary\":\"A repeated workflow\",\"confidence\":0.8}],\"workflow\":{\"title\":\"Workflow\",\"goal\":\"Repeat the steps\"}}"}"#;

fn adapter_with_outputs(
    version: &str,
    authenticated: bool,
    response: &str,
) -> (ClaudeAdapter, Arc<FakeExecutor>) {
    let (discovery, _executable) = executable_discovery();
    let executor = FakeExecutor::new([
        output(version),
        output(if authenticated {
            r#"{"loggedIn":true}"#
        } else {
            r#"{"loggedIn":false}"#
        }),
        output(response),
    ]);
    let adapter = ClaudeAdapter::with_executor(executor.clone(), discovery)
        .expect("fixed Claude test configuration is valid");
    (adapter, executor)
}

#[test]
fn missing_cli_is_a_typed_not_installed_error() {
    let discovery = ExecutableDiscovery::new([PathBuf::from("/definitely/missing/u15")]);
    let executor = FakeExecutor::new([]);
    let adapter = ClaudeAdapter::with_executor(executor, discovery)
        .expect("fixed Claude test configuration is valid");
    assert!(matches!(
        ProviderGate::new(adapter).detect_and_verify(),
        Err(ProviderError::NotInstalled { .. })
    ));
}

#[test]
fn unauthenticated_cli_is_a_typed_not_authenticated_error() {
    let (adapter, _executor) = adapter_with_outputs("2.1.228", false, RESPONSE);
    assert!(matches!(
        ProviderGate::new(adapter).detect_and_verify(),
        Err(ProviderError::NotAuthenticated { .. })
    ));
}

#[test]
fn old_cli_is_refused_by_the_shared_gate() {
    let (adapter, _executor) = adapter_with_outputs("2.0.99", true, RESPONSE);
    assert!(matches!(
        ProviderGate::new(adapter).detect_and_verify(),
        Err(ProviderError::TooOld { .. })
    ));
}

#[test]
fn malformed_provider_output_is_a_typed_runtime_failure() {
    let (adapter, _executor) = adapter_with_outputs("2.1.228", true, r#"{"result":"not JSON"}"#);
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Claude should pass detection");
    let error = gate
        .invoke(
            &verified,
            ProviderRequest::text("sanitized context").expect("context is non-empty"),
        )
        .expect_err("malformed output must be rejected");
    assert!(matches!(
        error,
        ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::Invocation,
            ..
        }
    ));
}

#[test]
fn claude_normalizes_through_the_same_gate_response_shape() {
    let (adapter, _executor) = adapter_with_outputs("2.1.228", true, RESPONSE);
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Claude should pass detection");
    let response = gate
        .invoke(
            &verified,
            ProviderRequest::text("sanitized context").expect("context is non-empty"),
        )
        .expect("fixed response should normalize");
    assert_eq!(response.observations().len(), 1);
    assert_eq!(response.observations()[0].title(), "Observed");
    assert_eq!(response.observations()[0].summary(), "A repeated workflow");
    assert_eq!(
        response.workflow().expect("workflow is present").goal(),
        "Repeat the steps"
    );
}

#[test]
fn image_request_cannot_bypass_the_gate() {
    let (adapter, executor) = adapter_with_outputs("2.1.228", true, RESPONSE);
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Claude should pass detection");
    let error = gate
        .invoke(
            &verified,
            ProviderRequest::with_images("sanitized context", 1)
                .expect("one prepared image is valid"),
        )
        .expect_err("text-only Claude adapter must refuse images");
    assert!(matches!(
        error,
        ProviderError::CapabilityMissing {
            capability: Capability::Images,
            ..
        }
    ));
    let remaining = executor
        .outputs
        .lock()
        .expect("test executor mutex is not poisoned")
        .len();
    assert_eq!(remaining, 1, "gate must not consume an invocation output");
}

#[test]
fn auth_status_parser_rejects_malformed_probe() {
    assert!(qaptr_provider_cli::adapters::claude::parse_auth_status(b"{}").is_err());
}

#[test]
#[ignore = "requires a genuine installed Claude Code CLI and local authenticated session"]
fn installed_claude_passes_real_detection() {
    let timeout =
        Timeout::new(std::time::Duration::from_secs(10)).expect("test timeout is non-zero");
    let output = OutputLimit::new(64 * 1024).expect("test output limit is non-zero");
    let adapter = ClaudeAdapter::new(CliRuntime::new(RuntimeLimits::new(timeout, output)))
        .expect("Claude descriptor is valid");
    let verified = ProviderGate::new(adapter)
        .detect_and_verify()
        .expect("a genuine installed Claude CLI should pass detection");
    assert!(verified.version() >= ClaudeAdapter::minimum_version());
    assert_eq!(verified.version(), ProviderVersion::new(2, 1, 228));
}
