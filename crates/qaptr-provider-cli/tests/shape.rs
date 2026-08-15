//! Shared U15/U16 normalized response-shape test using in-process fakes.

mod support;

use std::{
    fs,
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

use qaptr_provider::ProviderGate;
use qaptr_provider_cli::{
    CliInvocation, CliOutput, CliRuntimeError, ExecutableDiscovery,
    adapters::{CliExecutor, CodexAdapter, JcodeAdapter},
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

fn directory(name: &str) -> PathBuf {
    let suffix = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
    let directory = std::env::temp_dir().join(format!(
        "qaptr-u16-shape-{name}-{}-{suffix}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).expect("test directory can be created");
    fs::copy("/usr/bin/true", directory.join(name)).expect("test executable can be copied");
    directory
}

fn response() -> &'static str {
    r#"{"observations":[{"title":"Repeated export","summary":"The same export path recurs.","confidence":0.8}],"workflow":{"title":"Export workflow","goal":"Produce a handoff export"}}"#
}

#[test]
fn codex_and_jcode_normalize_to_the_same_response_shape() {
    let codex_directory = directory("codex");
    let jcode_directory = directory("jcode");
    let codex = CodexAdapter::with_executor(
        Arc::new(FakeExecutor::new(vec![
            FakeExecutor::output("codex-cli 0.147.0"),
            FakeExecutor::output("Logged in using ChatGPT"),
            FakeExecutor::output(&format!(
                "{{\"type\":\"item.completed\",\"item\":{{\"type\":\"agent_message\",\"text\":{}}}}}",
                serde_json::to_string(response()).expect("response string serializes")
            )),
        ])),
        ExecutableDiscovery::new([codex_directory.clone()]),
    )
    .expect("Codex descriptor is valid");
    let jcode = JcodeAdapter::with_executor(
        Arc::new(FakeExecutor::new(vec![
            FakeExecutor::output("jcode v0.75.23-dev (22db449)"),
            FakeExecutor::output("openai\tavailable\tOAuth\tready"),
            FakeExecutor::output(response()),
        ])),
        ExecutableDiscovery::new([jcode_directory.clone()]),
    )
    .expect("Jcode descriptor is valid");

    let codex_gate = ProviderGate::new(codex);
    let jcode_gate = ProviderGate::new(jcode);
    let codex_verified = codex_gate
        .detect_and_verify()
        .expect("Codex fake passes the handshake");
    let jcode_verified = jcode_gate
        .detect_and_verify()
        .expect("Jcode fake passes the handshake");
    let payload = support::prepared_payload(false);
    let codex_response = codex_gate
        .invoke(&codex_verified, &payload)
        .expect("Codex response normalizes");
    let jcode_response = jcode_gate
        .invoke(&jcode_verified, &payload)
        .expect("Jcode response normalizes");

    let _ = fs::remove_dir_all(codex_directory);
    let _ = fs::remove_dir_all(jcode_directory);
    assert_eq!(codex_response, jcode_response);
}
