//! U16 Jcode adapter contract and detection tests.

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
    adapters::{CliExecutor, JcodeAdapter},
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

fn adapter(
    name: &str,
    outputs: Vec<Result<CliOutput, CliRuntimeError>>,
) -> (JcodeAdapter, PathBuf) {
    let directory = executable_directory(name);
    let discovery = ExecutableDiscovery::new([directory.clone()]);
    let adapter = JcodeAdapter::with_executor(Arc::new(FakeExecutor::new(outputs)), discovery)
        .expect("Jcode descriptor is valid");
    (adapter, directory)
}

#[test]
fn missing_jcode_is_typed_not_installed() {
    let adapter = JcodeAdapter::with_executor(
        Arc::new(FakeExecutor::new(Vec::new())),
        ExecutableDiscovery::new(Vec::<PathBuf>::new()),
    )
    .expect("Jcode descriptor is valid");

    assert!(matches!(
        ProviderGate::new(adapter).detect_and_verify(),
        Err(ProviderError::NotInstalled { .. })
    ));
}

#[test]
fn unauthenticated_jcode_is_typed_not_authenticated() {
    let (adapter, directory) = adapter(
        "jcode",
        vec![
            FakeExecutor::output("jcode v0.75.23-dev (22db449)"),
            FakeExecutor::output("openai\tnot_configured\tOAuth\tnot configured"),
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
fn old_jcode_is_refused_by_the_shared_gate() {
    let (adapter, directory) = adapter(
        "jcode",
        vec![
            FakeExecutor::output("jcode v0.75.22"),
            FakeExecutor::output("openai\tavailable\tOAuth\tready"),
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
fn malformed_jcode_output_is_a_typed_runtime_failure() {
    let (adapter, directory) = adapter(
        "jcode",
        vec![
            FakeExecutor::output("jcode v0.75.23-dev (22db449)"),
            FakeExecutor::output("openai\tavailable\tOAuth\tready"),
            FakeExecutor::output("not json"),
        ],
    );
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Jcode should pass the handshake");
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
fn image_request_is_refused_before_jcode_executor_runs() {
    let (adapter, directory) = adapter(
        "jcode",
        vec![
            FakeExecutor::output("jcode v0.75.23-dev (22db449)"),
            FakeExecutor::output("openai\tavailable\tOAuth\tready"),
        ],
    );
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("fake Jcode should pass the handshake");
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
#[ignore = "requires the installed release Jcode CLI and local authenticated provider session"]
fn installed_jcode_passes_real_detection() {
    let timeout = Timeout::new(Duration::from_secs(10)).expect("test timeout is non-zero");
    let output = OutputLimit::new(64 * 1024).expect("test output limit is non-zero");
    let adapter = JcodeAdapter::new(qaptr_provider_cli::CliRuntime::new(RuntimeLimits::new(
        timeout, output,
    )))
    .expect("Jcode descriptor is valid");
    let verified = ProviderGate::new(adapter)
        .detect_and_verify()
        .expect("installed Jcode should pass detection");
    assert_eq!(verified.version(), ProviderVersion::new(0, 75, 23));
}
