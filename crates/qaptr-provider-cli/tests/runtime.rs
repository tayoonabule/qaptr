//! Real-process U14 isolation tests.

#![cfg(target_os = "macos")]

use std::{path::PathBuf, time::Duration};

use qaptr_provider::{ExecutablePath, ProviderError, ProviderId, RuntimeFailureKind};
use qaptr_provider_cli::{
    CliInvocation, CliRuntime, CliRuntimeError, OutputLimit, RuntimeLimits, Timeout,
};

fn runtime(timeout: Duration, output: usize) -> CliRuntime {
    let timeout = Timeout::new(timeout).expect("test timeout is non-zero");
    let output = OutputLimit::new(output).expect("test output limit is non-zero");
    CliRuntime::new(RuntimeLimits::new(timeout, output))
}

fn executable(path: &str) -> ExecutablePath {
    ExecutablePath::new(path).expect("test executable path is absolute")
}

#[test]
fn timeout_kills_a_real_process_and_maps_to_typed_timeout() {
    let invocation = CliInvocation::new(executable("/bin/sleep")).arg("2");
    let error = runtime(Duration::from_millis(75), 4096)
        .run(invocation)
        .expect_err("sleep must exceed the wall-clock budget");
    assert!(matches!(error, CliRuntimeError::TimedOut));

    let provider = ProviderId::new("test-cli").expect("test provider id is valid");
    let invocation = CliInvocation::new(executable("/bin/sleep")).arg("2");
    let error = runtime(Duration::from_millis(75), 4096)
        .run_for_provider(&provider, invocation)
        .expect_err("sleep must exceed the wall-clock budget");
    assert!(matches!(
        error,
        ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::TimedOut,
            ..
        }
    ));
}

#[test]
fn oversized_output_is_refused_without_retaining_unbounded_bytes() {
    let invocation = CliInvocation::new(executable("/usr/bin/yes")).arg("qaptr");
    let error = runtime(Duration::from_secs(2), 1024)
        .run(invocation)
        .expect_err("yes must exceed the output budget");
    assert!(matches!(
        error,
        CliRuntimeError::OutputLimitExceeded { limit: 1024, .. }
    ));
}

#[test]
fn sandbox_denies_real_access_to_the_user_home() {
    let home = std::env::var_os("HOME").expect("macOS test has a home directory");
    let denied_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    assert!(denied_path.starts_with(&home));
    let invocation = CliInvocation::new(executable("/bin/cat")).arg(denied_path);
    let error = runtime(Duration::from_secs(2), 4096)
        .run(invocation)
        .expect_err("sandboxed ls must not read the user home");
    match error {
        CliRuntimeError::NonZeroExit { stderr, .. } => {
            let stderr = String::from_utf8_lossy(&stderr);
            assert!(
                stderr.contains("Operation not permitted"),
                "stderr: {stderr}"
            );
        }
        other => panic!("expected sandbox denial, got {other:?}"),
    }
}

#[test]
fn nonexistent_binary_maps_to_not_installed() {
    let provider = ProviderId::new("missing-cli").expect("test provider id is valid");
    let invocation = CliInvocation::new(executable("/definitely/not/a/real/qaptr-u14-executable"));
    let error = runtime(Duration::from_secs(1), 4096)
        .run_for_provider(&provider, invocation)
        .expect_err("missing executable must be unavailable");
    assert!(matches!(error, ProviderError::NotInstalled { .. }));
}

#[test]
fn metacharacters_are_passed_as_literal_arguments_without_shell_interpretation() {
    let invocation = CliInvocation::new(executable("/bin/echo"))
        .arg("$(printf injected)")
        .arg("; touch /tmp/qaptr-u14-must-not-exist")
        .arg("`echo backticks`");
    let output = runtime(Duration::from_secs(2), 4096)
        .run(invocation)
        .expect("echo should receive adversarial arguments literally");
    let stdout = String::from_utf8_lossy(output.stdout());
    assert_eq!(
        stdout,
        "$(printf injected) ; touch /tmp/qaptr-u14-must-not-exist `echo backticks`\n"
    );
}

#[test]
fn environment_is_cleared_before_allowlisted_values_are_added() {
    let invocation =
        CliInvocation::new(executable("/usr/bin/env")).environment("QAPTR_ONLY", "yes");
    let output = runtime(Duration::from_secs(2), 4096)
        .run(invocation)
        .expect("env should run with the explicit environment");
    let stdout = String::from_utf8_lossy(output.stdout());
    let lines: Vec<&str> = stdout.lines().collect();
    assert_eq!(lines.len(), 2);
    assert!(lines.contains(&"QAPTR_ONLY=yes"));
    assert!(lines.iter().any(|line| line.starts_with("TMPDIR=")));
}

#[test]
fn prompt_is_sent_over_stdin_without_becoming_an_argument() {
    let invocation = CliInvocation::new(executable("/bin/cat")).stdin(b"prompt\n".to_vec());
    let output = runtime(Duration::from_secs(2), 4096)
        .run(invocation)
        .expect("cat should receive the prompt on stdin");
    assert_eq!(output.stdout(), b"prompt\n");
}
