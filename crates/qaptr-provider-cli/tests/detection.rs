//! Deterministic tests for the non-invasive scalar CLI detection surface.

use std::sync::atomic::{AtomicUsize, Ordering};

use qaptr_provider::{AuthenticationStatus, ExecutablePath};
use qaptr_provider_cli::{
    CliDetectionStatus, CliPathProbe, CliProcessProbe, CliProvider, ExecutableProbeStatus,
    detect_cli, detect_cli_with_process_probe,
};

struct FakePathProbe {
    status: ExecutableProbeStatus,
}

impl CliPathProbe for FakePathProbe {
    fn probe_path(&self, _provider: CliProvider) -> ExecutableProbeStatus {
        self.status.clone()
    }
}

struct FakeProcessProbe {
    authentication: Option<AuthenticationStatus>,
    calls: AtomicUsize,
}

impl CliProcessProbe for FakeProcessProbe {
    fn probe_authentication(
        &self,
        _provider: CliProvider,
        _executable: &ExecutablePath,
    ) -> Option<AuthenticationStatus> {
        self.calls.fetch_add(1, Ordering::Relaxed);
        self.authentication
    }
}

fn executable() -> ExecutablePath {
    ExecutablePath::new("/tmp/fake-cli").expect("fixture path is absolute")
}

#[test]
fn production_safe_detection_preserves_unavailable_and_not_installed() {
    for status in [
        (
            ExecutableProbeStatus::Unavailable,
            CliDetectionStatus::Unavailable,
        ),
        (
            ExecutableProbeStatus::NotInstalled,
            CliDetectionStatus::NotInstalled,
        ),
    ] {
        let probe = FakePathProbe { status: status.0 };
        let detected = detect_cli(CliProvider::Claude, &probe);
        assert_eq!(detected, status.1);
        assert_eq!(detected.authentication(), None);
    }
}

#[test]
fn detected_without_an_auth_probe_is_not_claimed_authenticated() {
    let probe = FakePathProbe {
        status: ExecutableProbeStatus::Detected(executable()),
    };

    assert_eq!(
        detect_cli(CliProvider::Codex, &probe),
        CliDetectionStatus::Detected {
            authentication: None,
        }
    );
}

#[test]
fn injected_auth_probe_can_supply_only_a_proven_typed_result() {
    let path_probe = FakePathProbe {
        status: ExecutableProbeStatus::Detected(executable()),
    };
    let authenticated = FakeProcessProbe {
        authentication: Some(AuthenticationStatus::Authenticated),
        calls: AtomicUsize::new(0),
    };
    let unauthenticated = FakeProcessProbe {
        authentication: Some(AuthenticationStatus::NotAuthenticated),
        calls: AtomicUsize::new(0),
    };

    assert_eq!(
        detect_cli_with_process_probe(CliProvider::Jcode, &path_probe, Some(&authenticated))
            .authentication(),
        Some(AuthenticationStatus::Authenticated)
    );
    assert_eq!(
        detect_cli_with_process_probe(CliProvider::Jcode, &path_probe, Some(&unauthenticated))
            .authentication(),
        Some(AuthenticationStatus::NotAuthenticated)
    );
    assert_eq!(authenticated.calls.load(Ordering::Relaxed), 1);
    assert_eq!(unauthenticated.calls.load(Ordering::Relaxed), 1);
}

#[test]
fn missing_or_unavailable_paths_never_call_the_process_probe() {
    let process_probe = FakeProcessProbe {
        authentication: Some(AuthenticationStatus::Authenticated),
        calls: AtomicUsize::new(0),
    };

    for status in [
        ExecutableProbeStatus::Unavailable,
        ExecutableProbeStatus::NotInstalled,
    ] {
        let path_probe = FakePathProbe { status };
        let result =
            detect_cli_with_process_probe(CliProvider::Claude, &path_probe, Some(&process_probe));
        assert!(!result.is_detected());
    }

    assert_eq!(process_probe.calls.load(Ordering::Relaxed), 0);
}
