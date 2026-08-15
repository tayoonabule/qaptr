//! U18 detailed capture profile lifecycle scenarios.

use std::time::{Duration as StdDuration, SystemTime, UNIX_EPOCH};

use qaptr_domain::{CaptureId, Clock, Duration, FixedClock, ports::ContextSnapshot};
use qaptr_policy::{
    CaptureDecision, CaptureProfileLifecycle, CaptureProfileState, ExclusionReason, ExclusionRules,
    ProfileError, seal_if_allowed,
};
use qaptr_vault::{
    BundleInput, GenerationId, GenerationKeypair, SampledContext, Vault, VaultError,
};

#[derive(Clone, Copy, Debug)]
struct TestClock {
    now: SystemTime,
}

impl TestClock {
    fn new(now: SystemTime) -> Self {
        Self { now }
    }

    fn set(&mut self, now: SystemTime) {
        self.now = now;
    }
}

impl Clock for TestClock {
    fn now(&self) -> SystemTime {
        self.now
    }
}

fn instant(seconds: u64) -> SystemTime {
    UNIX_EPOCH + StdDuration::from_secs(seconds)
}

#[test]
fn detailed_profile_expires_automatically_at_its_bound() {
    let mut clock = TestClock::new(instant(100));
    let mut lifecycle = CaptureProfileLifecycle::new();
    let profile = lifecycle
        .start(Duration::from_secs(30), &clock)
        .expect("start detailed profile");

    assert_eq!(profile.started_at(), instant(100));
    assert_eq!(profile.ends_at(), instant(130));
    assert_eq!(
        lifecycle.state(&clock),
        CaptureProfileState::Detailed {
            started_at: instant(100),
            ends_at: instant(130),
        }
    );

    clock.set(instant(130));
    assert_eq!(lifecycle.state(&clock), CaptureProfileState::Sparse);
    assert_eq!(lifecycle.active_profile(), None);
}

#[test]
fn profile_expiry_is_observed_after_restart_even_if_the_app_was_not_running() {
    let start_clock = FixedClock::new(instant(100));
    let mut running = CaptureProfileLifecycle::new();
    let profile = running
        .start(Duration::from_secs(30), &start_clock)
        .expect("start detailed profile");

    let mut restarted = CaptureProfileLifecycle::from_active_profile(profile);
    let after_window = FixedClock::new(instant(131));
    assert_eq!(restarted.state(&after_window), CaptureProfileState::Sparse);
    assert_eq!(restarted.active_profile(), None);
}

#[test]
fn moving_the_clock_backwards_does_not_extend_or_reactivate_the_window() {
    let mut clock = TestClock::new(instant(100));
    let mut lifecycle = CaptureProfileLifecycle::new();
    lifecycle
        .start(Duration::from_secs(30), &clock)
        .expect("start detailed profile");

    clock.set(instant(120));
    assert!(lifecycle.state(&clock).is_detailed());
    clock.set(instant(90));
    assert!(lifecycle.state(&clock).is_detailed());
    clock.set(instant(130));
    assert_eq!(lifecycle.state(&clock), CaptureProfileState::Sparse);

    clock.set(instant(110));
    assert_eq!(lifecycle.state(&clock), CaptureProfileState::Sparse);
}

#[test]
fn a_second_start_is_rejected_without_stacking_or_extending_the_first_window() {
    let mut clock = TestClock::new(instant(100));
    let mut lifecycle = CaptureProfileLifecycle::new();
    let first = lifecycle
        .start(Duration::from_secs(30), &clock)
        .expect("start first profile");

    clock.set(instant(110));
    assert_eq!(
        lifecycle.start(Duration::from_secs(300), &clock),
        Err(ProfileError::AlreadyActive)
    );
    assert_eq!(lifecycle.active_profile(), Some(first));
    assert_eq!(lifecycle.state(&clock).ends_at(), Some(instant(130)));
}

#[test]
fn ending_early_returns_to_sparse_mode_immediately() {
    let clock = FixedClock::new(instant(100));
    let mut lifecycle = CaptureProfileLifecycle::new();
    lifecycle
        .start(Duration::from_secs(30), &clock)
        .expect("start detailed profile");

    lifecycle.end().expect("end detailed profile");
    assert_eq!(lifecycle.state(&clock), CaptureProfileState::Sparse);
    assert_eq!(lifecycle.end(), Err(ProfileError::NotActive));
}

#[test]
fn excluded_application_stays_excluded_while_detailed_profile_is_active() {
    let root = tempfile::tempdir().expect("vault directory");
    let vault = Vault::new(root.path()).expect("vault");
    let keys = GenerationKeypair::generate(
        GenerationId::new("generation-profile-exclusion").expect("generation id"),
    );
    let capture = CaptureId::new("capture-profile-excluded").expect("capture id");
    let input = BundleInput::new(
        capture.clone(),
        keys.generation_id().clone(),
        b"image bytes".to_vec(),
        SampledContext::new(b"context".to_vec()),
        b"derived bytes".to_vec(),
    );
    let context = ContextSnapshot::new(
        Some("Secret Editor".to_owned()),
        Some("private-window".to_owned()),
        None,
        None,
    );
    let mut rules = ExclusionRules::new();
    rules.exclude_application("Secret Editor");

    let clock = FixedClock::new(instant(100));
    let mut lifecycle = CaptureProfileLifecycle::new();
    assert!(
        lifecycle
            .start(Duration::from_secs(30), &clock)
            .expect("start detailed profile")
            .ends_at()
            > clock.now()
    );

    let decision = seal_if_allowed(&vault, &input, keys.public_key(), &context, &rules)
        .expect("exclusion decision");
    assert_eq!(
        decision,
        CaptureDecision::Excluded(ExclusionReason::Application)
    );
    assert!(matches!(
        vault.bundle_metadata(&capture),
        Err(VaultError::BundleNotFound(_))
    ));
    assert!(matches!(
        lifecycle.state(&clock),
        CaptureProfileState::Detailed { .. }
    ));
}
