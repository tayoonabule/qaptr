//! U16 Codex adapter contract and detection tests.

use std::{
    fs,
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use qaptr_provider::{
    Capability, ProviderError, ProviderGate, ProviderRequest, ProviderVersion, RuntimeFailureKind,
};
use qaptr_provider_cli::{
    CliInvocation, CliOutput, CliRuntimeError, ExecutableDiscovery, OutputLimit, RuntimeLimits,
    Timeout,
    adapters::{CliExecutor, CodexAdapter},
};

static NEXT_DIRECTORY: AtomicUsize = AtomicUsize::new(0);

struct FakeExecutor {
    outputs: Mutex<Vec<Result<CliOutput, CliRuntimeError>>>,
}

impl FakeExecutor {
    fn new(outputs: Vec<Result<CliOutput, CliRuntimeError>>) -> Self {
        Self {
            outputs: Mutex::new(outputs),
        }
    }

    fn output(stdout: &str) -> Result<CliOutput, CliRuntimeError> {
        Ok(CliOutput::new(stdout.as_bytes().to_vec(), Vec::new()))
    }
}

impl CliExecutor for FakeExecutor {
    fn run(&self, _invocation: CliInvocation) -> Result<CliOutput, CliRuntimeError> {
        self.outputs
            .lock()
            .expect("fake lock is not poisoned")
            .remove(0)
    }
}

fn executable_directory(name: &str) -> PathBuf {
    let suffix = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
    let directory =
        std::env::temp_dir().join(format!("qaptr-u16-{name}-{}-{suffix}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).expect("test directory can be created");
    fs::copy("/usr/bin/true", directory.join(name)).expect("test executable can be copied");
    directory
}

fn discovery(name: &str) -> (ExecutableDiscovery, PathBuf) {
    let directory = executable_directory(name);
    (ExecutableDiscovery::new([directory.clone()]), directory)
}

fn adapter(
    name: &str,
    outputs: Vec<Result<CliOutput, CliRuntimeError>>,
) -> (CodexAdapter, PathBuf) {
    let (discovery, directory) = discovery(name);
    let adapter = CodexAdapter::with_executor(Arc::new(FakeExecutor::new(outputs)), discovery)
        .expect("Codex descriptor is valid");
    (adapter, directory)
}

#[test]
fn missing_codex_is_typed_not_installed() {
    let discovery = ExecutableDiscovery::new(Vec::<PathBuf>::new());
    let adapter = CodexAdapter::with_executor(Arc::new(FakeExecutor::new(Vec::new())), discovery)
        .expect("Codex descriptor is valid");

    assert!(matches!(
        ProviderGate::new(adapter).detect_and_verify(),
        Err(ProviderError::NotInstalled { .. })
    ));
}

#[test]
fn unauthenticated_codex_is_typed_not_authenticated() {
    let (adapter, directory) = adapter(
        "codex",
        vec![
            FakeExecutor::output("codex-cli 0.147.0"),
            FakeExecutor::output("Not logged in"),
        ],
    );
    let result = ProviderGate::new(adapter).detect_and_verify();
    let _ = fs::remove_dir_all(directory);

    assert!(matches!(
        result,
        Err(ProviderError::NotAuthenticated { .. })
    ));
}

#[test]
fn old_codex_is_refused_by_the_shared_gate() {
    let (adapter, directory) = adapter(
        "codex",
        vec![
            FakeExecutor::output("codex-cli 0.146.9"),
            FakeExecutor::output("Logged in using ChatGPT"),
        ],
    );
    let result = ProviderGate::new(adapter).detect_and_verify();
    let _ = fs::remove_dir_all(directory);

    assert!(matches!(
        result,
        Err(ProviderError::TooOld {
            found: ProviderVersion { .. },
            ..
        })
    ));
}

#[test]
fn malformed_codex_output_is_a_typed_runtime_failure() {
    let (adapter, directory) = adapter(
        "codex",
        vec![
            FakeExecutor::output("codex-cli 0.147.0"),
            FakeExecutor::output("Logged in using ChatGPT"),
            FakeExecutor::output("not json"),
        ],
    );
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Codex should pass the handshake");
    let result = gate.invoke(
        &verified,
        ProviderRequest::text("sanitized context").expect("context is valid"),
    );
    let _ = fs::remove_dir_all(directory);

    assert!(matches!(
        result,
        Err(ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::Invocation,
            ..
        })
    ));
}

#[test]
fn image_request_is_refused_before_codex_executor_runs() {
    let (adapter, directory) = adapter(
        "codex",
        vec![
            FakeExecutor::output("codex-cli 0.147.0"),
            FakeExecutor::output("Logged in using ChatGPT"),
        ],
    );
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Codex should pass the handshake");
    let result = gate.invoke(
        &verified,
        ProviderRequest::with_images("sanitized context", 1).expect("image request is valid"),
    );
    let _ = fs::remove_dir_all(directory);

    assert!(matches!(
        result,
        Err(ProviderError::CapabilityMissing {
            capability: Capability::Images,
            ..
        })
    ));
}

#[test]
#[ignore = "requires the installed release Codex CLI and local OAuth session"]
fn installed_codex_passes_real_detection() {
    let timeout = Timeout::new(Duration::from_secs(10)).expect("test timeout is non-zero");
    let output = OutputLimit::new(64 * 1024).expect("test output limit is non-zero");
    let adapter = CodexAdapter::new(qaptr_provider_cli::CliRuntime::new(RuntimeLimits::new(
        timeout, output,
    )))
    .expect("Codex descriptor is valid");
    let verified = ProviderGate::new(adapter)
        .detect_and_verify()
        .expect("installed Codex should pass detection");
    assert_eq!(verified.version(), ProviderVersion::new(0, 147, 0));
}
