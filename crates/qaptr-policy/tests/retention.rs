//! U8 retention and pre-seal exclusion scenarios.

use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration as StdDuration, UNIX_EPOCH},
};

use qaptr_domain::{
    CaptureId, Confidence, FixedClock, ObservationId, SessionId, WorkflowId,
    ports::{ContextSnapshot, CredentialKey, CredentialPort, CredentialValue, PortOutcome},
};
use qaptr_policy::{
    CaptureDecision, ExclusionReason, ExclusionRules, RetentionBundle, RetentionPolicy,
    enforce_retention, seal_if_allowed,
};
use qaptr_store::{
    CaptureRecord, NoticeReason, NoticeRecord, ObservationRecord, Store, UnixMillis, WorkflowRecord,
};
use qaptr_vault::{
    BundleInput, GenerationId, GenerationKeypair, SampledContext, Vault, VaultError,
};

#[derive(Default)]
struct MemoryCredentials {
    values: Mutex<HashMap<String, CredentialValue>>,
}

impl CredentialPort for MemoryCredentials {
    fn read(
        &self,
        key: &CredentialKey,
    ) -> qaptr_domain::ports::PortResult<Option<CredentialValue>> {
        let value = self
            .values
            .lock()
            .map_err(|_| qaptr_domain::DomainError::Denied {
                operation: "credential lock",
            })?
            .get(key.as_str())
            .cloned();
        Ok(PortOutcome::Complete(value))
    }

    fn write(
        &self,
        key: &CredentialKey,
        value: CredentialValue,
    ) -> qaptr_domain::ports::PortResult<()> {
        self.values
            .lock()
            .map_err(|_| qaptr_domain::DomainError::Denied {
                operation: "credential lock",
            })?
            .insert(key.as_str().to_owned(), value);
        Ok(PortOutcome::Complete(()))
    }

    fn delete(&self, key: &CredentialKey) -> qaptr_domain::ports::PortResult<()> {
        self.values
            .lock()
            .map_err(|_| qaptr_domain::DomainError::Denied {
                operation: "credential lock",
            })?
            .remove(key.as_str());
        Ok(PortOutcome::Complete(()))
    }
}

fn keypair(id: &str) -> GenerationKeypair {
    GenerationKeypair::generate(GenerationId::new(id).expect("test generation id"))
}

fn input(id: &str, generation: &GenerationId) -> BundleInput {
    BundleInput::new(
        CaptureId::new(id).expect("test capture id"),
        generation.clone(),
        UNIX_EPOCH + StdDuration::from_secs(1),
        b"image bytes".to_vec(),
        SampledContext::new(b"context".to_vec()),
        b"derived bytes".to_vec(),
    )
}

fn configure_generation(vault: &Vault, credentials: &MemoryCredentials, keys: &GenerationKeypair) {
    let key = Vault::generation_credential_key(keys.generation_id()).expect("credential key");
    credentials
        .write(&key, keys.private_key().to_credential_value())
        .expect("credential write");
    vault
        .register_public_key(keys.generation_id(), keys.public_key())
        .expect("public key registration");
}

fn capture_record(id: &str, at: i64) -> CaptureRecord {
    CaptureRecord {
        id: CaptureId::new(id).expect("test capture id"),
        captured_at: UnixMillis::from_millis(at),
        vault_record_id: format!("vault-{id}"),
        context_summary: Some("summary only".to_owned()),
    }
}

fn observation(capture_id: &str) -> ObservationRecord {
    ObservationRecord {
        id: ObservationId::new("observation-1").expect("test observation id"),
        capture_id: Some(CaptureId::new(capture_id).expect("test capture id")),
        session_id: SessionId::new("session-1").expect("test session id"),
        title: "Export report".to_owned(),
        summary: "The report was exported.".to_owned(),
        confidence: Confidence::new(0.9).expect("test confidence"),
        created_at: UnixMillis::from_millis(2_000),
    }
}

fn workflow() -> WorkflowRecord {
    WorkflowRecord {
        id: WorkflowId::new("workflow-1").expect("test workflow id"),
        session_id: SessionId::new("session-1").expect("test session id"),
        title: "Export report".to_owned(),
        goal: "Export a report".to_owned(),
        context: "Review context".to_owned(),
        tools: "Spreadsheet".to_owned(),
        sequence: "Open; export".to_owned(),
        decisions: "Use CSV".to_owned(),
        variations: "PDF is acceptable".to_owned(),
        evidence_confidence: Confidence::new(0.8).expect("test confidence"),
        created_at: UnixMillis::from_millis(3_000),
    }
}

#[test]
fn expired_generation_is_unreadable_while_derived_history_survives() {
    let root = tempfile::tempdir().expect("vault directory");
    let vault = Vault::new(root.path().join("vault")).expect("vault");
    let store = Store::open(root.path().join("history.sqlite3")).expect("store");
    let credentials = MemoryCredentials::default();
    let keys = keypair("generation-expired");
    configure_generation(&vault, &credentials, &keys);
    let capture = CaptureId::new("capture-expired").expect("capture id");
    vault
        .seal(
            &input(capture.as_str(), keys.generation_id()),
            keys.public_key(),
        )
        .expect("seal");
    store
        .put_capture(&capture_record(capture.as_str(), 1_000))
        .expect("capture");
    store
        .put_observation(&observation(capture.as_str()))
        .expect("observation");
    store.put_workflow(&workflow()).expect("workflow");

    let policy = RetentionPolicy::new(qaptr_domain::Duration::from_secs(10));
    let clock = FixedClock::new(UNIX_EPOCH + StdDuration::from_secs(20));
    let report = enforce_retention(&policy, &vault, &store, &credentials, &clock)
        .expect("retention cascade");

    assert_eq!(report.generations_reaped, 1);
    assert_eq!(report.bundles_removed, 1);
    assert_eq!(report.captures_removed, 1);
    assert!(matches!(
        vault.open(&capture, &credentials),
        Err(VaultError::BundleNotFound(_))
    ));
    let snapshot = store.snapshot().expect("history snapshot");
    assert_eq!(snapshot.observations.len(), 1);
    assert_eq!(snapshot.workflows.len(), 1);
    assert!(snapshot.observations[0].capture_id.is_none());
}

#[test]
fn retention_is_idempotent_and_clock_movement_backwards_is_safe() {
    let generation = GenerationId::new("generation-policy").expect("generation id");
    let metadata = qaptr_vault::BundleMetadata {
        capture_id: CaptureId::new("capture-policy").expect("capture id"),
        generation_id: generation.clone(),
        captured_at: UNIX_EPOCH + StdDuration::from_secs(100),
    };
    let captured_at = UNIX_EPOCH + StdDuration::from_secs(100);
    let policy = RetentionPolicy::new(qaptr_domain::Duration::from_secs(10));
    let longer_policy = RetentionPolicy::new(qaptr_domain::Duration::from_secs(30));
    let before_capture = FixedClock::new(UNIX_EPOCH + StdDuration::from_secs(99));
    let after_capture = FixedClock::new(UNIX_EPOCH + StdDuration::from_secs(110));
    let bundle = RetentionBundle::new(metadata, captured_at);

    assert!(!policy.is_expired(captured_at, &before_capture));
    assert!(!longer_policy.is_expired(captured_at, &after_capture));
    assert_eq!(
        policy.expired_generations(std::slice::from_ref(&bundle), &before_capture),
        Vec::new()
    );
    assert_eq!(
        policy.expired_generations(std::slice::from_ref(&bundle), &after_capture),
        vec![generation]
    );
}

#[test]
fn a_reaper_pass_can_stop_between_generations_and_resume_without_half_deleted_bundles() {
    let root = tempfile::tempdir().expect("vault directory");
    let vault = Vault::new(root.path()).expect("vault");
    let credentials = MemoryCredentials::default();
    let first = keypair("generation-first");
    let second = keypair("generation-second");
    configure_generation(&vault, &credentials, &first);
    configure_generation(&vault, &credentials, &second);
    let first_capture = CaptureId::new("capture-first").expect("capture id");
    let second_capture = CaptureId::new("capture-second").expect("capture id");
    vault
        .seal(
            &input(first_capture.as_str(), first.generation_id()),
            first.public_key(),
        )
        .expect("first seal");
    vault
        .seal(
            &input(second_capture.as_str(), second.generation_id()),
            second.public_key(),
        )
        .expect("second seal");

    let reaper = vault.reaper(&credentials);
    let first_report = reaper
        .reap(std::slice::from_ref(first.generation_id()))
        .expect("first pass");
    assert_eq!(first_report.bundles_removed, 1);
    assert!(vault.open(&second_capture, &credentials).is_ok());
    let resumed = reaper
        .reap(&[
            first.generation_id().clone(),
            second.generation_id().clone(),
        ])
        .expect("resumed pass");
    assert_eq!(resumed.bundles_removed, 1);
    let repeated = reaper
        .reap(&[
            first.generation_id().clone(),
            second.generation_id().clone(),
        ])
        .expect("repeated pass");
    assert_eq!(repeated.bundles_removed, 0);
}

#[test]
fn excluded_application_never_creates_a_bundle_and_notice_has_no_capture_content() {
    let root = tempfile::tempdir().expect("vault directory");
    let vault = Vault::new(root.path()).expect("vault");
    let keys = keypair("generation-exclusion");
    let capture = CaptureId::new("capture-excluded").expect("capture id");
    let mut rules = ExclusionRules::new();
    rules.exclude_application("Secret Editor");
    let context = ContextSnapshot::new(
        Some("Secret Editor".to_owned()),
        Some("private-window-title".to_owned()),
        None,
        None,
    );

    let decision = seal_if_allowed(
        &vault,
        &input(capture.as_str(), keys.generation_id()),
        keys.public_key(),
        &context,
        &rules,
    )
    .expect("policy decision");
    assert_eq!(
        decision,
        CaptureDecision::Excluded(ExclusionReason::Application)
    );
    assert!(!root.path().join("bundles").join(capture.as_str()).exists());

    let notice = NoticeRecord::new(
        "notice-1",
        UnixMillis::from_millis(4_000),
        1,
        NoticeReason::ApplicationExcluded,
    )
    .expect("notice");
    assert_eq!(
        notice.text(),
        "1 capture was excluded because the application is excluded."
    );
    assert!(!notice.text().contains("Secret Editor"));
    assert!(!notice.text().contains("private-window-title"));
    assert!(!notice.text().contains("capture-excluded"));
}

#[test]
fn excluded_window_never_creates_a_bundle() {
    let root = tempfile::tempdir().expect("vault directory");
    let vault = Vault::new(root.path()).expect("vault");
    let keys = keypair("generation-window-exclusion");
    let capture = CaptureId::new("capture-window-excluded").expect("capture id");
    let mut rules = ExclusionRules::new();
    rules.exclude_window("private-window-title");
    let context = ContextSnapshot::new(
        Some("Editor".to_owned()),
        Some("private-window-title".to_owned()),
        None,
        None,
    );

    let decision = seal_if_allowed(
        &vault,
        &input(capture.as_str(), keys.generation_id()),
        keys.public_key(),
        &context,
        &rules,
    )
    .expect("policy decision");
    assert_eq!(decision, CaptureDecision::Excluded(ExclusionReason::Window));
    assert!(!root.path().join("bundles").join(capture.as_str()).exists());
}
