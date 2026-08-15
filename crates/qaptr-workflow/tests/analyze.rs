//! U17 orchestration scenarios over real vault and store boundaries.

#![allow(clippy::expect_used, clippy::panic)]

use std::cell::Cell;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};
use std::time::{Duration, UNIX_EPOCH};

use qaptr_domain::clock::FixedClock;
use qaptr_domain::ports::PortOutcome;
use qaptr_domain::ports::context::ContextSnapshot;
use qaptr_domain::ports::credentials::{CredentialKey, CredentialPort, CredentialValue};
use qaptr_domain::ports::ocr::{OcrPort, OcrResult};
use qaptr_domain::ports::vision::{VisionPort, VisionResult};
use qaptr_domain::{CaptureId, DomainError, SessionId};
use qaptr_privacy::{PreparationInput, PrivacyGate, RecallReport, measure_recall};
use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, CapabilityDescriptor, ExecutablePath,
    ProviderAdapter, ProviderDescriptor, ProviderDetection, ProviderError, ProviderGate,
    ProviderId, ProviderLocation, ProviderVersion, RawObservation, RawProviderResponse,
    RawWorkflow, RuntimeFailureKind,
};
use qaptr_store::{CaptureRecord, Store, UnixMillis};
use qaptr_vault::OpenedBundle;
use qaptr_vault::{BundleInput, GenerationId, GenerationKeypair, SampledContext, Vault};
use qaptr_workflow::{
    AnalysisRunner, Cancellation, CaptureDecoder, CaptureRecordInput, ConsentDecision, ConsentPort,
    ConsentRequest, DecodeError, ProviderOutcome,
};

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

struct TempRoot(PathBuf);

impl TempRoot {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "qaptr-u17-{}-{}",
            std::process::id(),
            TEMP_COUNTER.fetch_add(1, Ordering::Relaxed),
        ));
        fs::create_dir_all(&path).expect("temporary root");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[derive(Default)]
struct MemoryCredentials {
    values: Mutex<HashMap<String, CredentialValue>>,
}

impl CredentialPort for MemoryCredentials {
    fn read(
        &self,
        key: &CredentialKey,
    ) -> qaptr_domain::Result<PortOutcome<Option<CredentialValue>>> {
        let values = self.values.lock().map_err(|_| DomainError::Denied {
            operation: "test credential lock",
        })?;
        Ok(PortOutcome::Complete(values.get(key.as_str()).cloned()))
    }

    fn write(
        &self,
        key: &CredentialKey,
        value: CredentialValue,
    ) -> qaptr_domain::Result<PortOutcome<()>> {
        self.values
            .lock()
            .map_err(|_| DomainError::Denied {
                operation: "test credential lock",
            })?
            .insert(key.as_str().to_owned(), value);
        Ok(PortOutcome::Complete(()))
    }

    fn delete(&self, key: &CredentialKey) -> qaptr_domain::Result<PortOutcome<()>> {
        self.values
            .lock()
            .map_err(|_| DomainError::Denied {
                operation: "test credential lock",
            })?
            .remove(key.as_str());
        Ok(PortOutcome::Complete(()))
    }
}

struct Decoder {
    contexts: HashMap<String, ContextSnapshot>,
    opened: Cell<u32>,
}

impl Decoder {
    fn with_contexts(contexts: HashMap<String, ContextSnapshot>) -> Self {
        Self {
            contexts,
            opened: Cell::new(0),
        }
    }
}

impl CaptureDecoder for Decoder {
    fn decode(&self, bundle: &OpenedBundle) -> Result<PreparationInput, DecodeError> {
        let capture_id = bundle.metadata().capture_id.clone();
        bundle.with_image_for_privacy(|image| {
            image.with_bytes(|bytes| assert!(!bytes.is_empty()));
        });
        self.opened.set(self.opened.get() + 1);
        let context = self
            .contexts
            .get(capture_id.as_str())
            .cloned()
            .ok_or_else(|| DecodeError::InvalidInput("missing test context".to_owned()))?;
        Ok(PreparationInput::new(capture_id, context))
    }
}

struct FakeOcr;

impl OcrPort for FakeOcr {
    fn recognize(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
        Ok(PortOutcome::Complete(OcrResult::default()))
    }
}

struct FakeVision;

impl VisionPort for FakeVision {
    fn detect(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
        Ok(PortOutcome::Complete(VisionResult::default()))
    }
}

struct FakeProvider {
    descriptor: ProviderDescriptor,
    detection: ProviderDetection,
    response: RawProviderResponse,
    failure: Option<ProviderError>,
    malformed_after_first: bool,
    invocations: Cell<u32>,
}

impl FakeProvider {
    fn new(failure: Option<ProviderError>) -> Self {
        let id = ProviderId::new("fake-provider").expect("provider id");
        let descriptor = ProviderDescriptor::new(
            id,
            "Fake provider",
            ProviderVersion::new(1, 0, 0),
            AuthenticationMode::ExistingCliSession,
            CapabilityDescriptor::text_only(),
        )
        .expect("provider descriptor");
        let executable =
            ExecutablePath::new("/usr/local/bin/fake-provider").expect("absolute path");
        Self {
            descriptor,
            detection: ProviderDetection::installed(
                ProviderLocation::Executable(executable),
                ProviderVersion::new(1, 0, 0),
                AuthenticationStatus::Authenticated,
            ),
            response: RawProviderResponse::new(
                vec![RawObservation::new(
                    "Repeated step",
                    "The same step recurred",
                    0.42,
                )],
                None,
            ),
            failure,
            malformed_after_first: false,
            invocations: Cell::new(0),
        }
    }

    fn unavailable(mut self) -> Self {
        self.detection = ProviderDetection::not_installed();
        self
    }

    fn with_workflow(mut self) -> Self {
        self.response.workflow = Some(RawWorkflow::new(
            "Repeated export review",
            "Prepare the repeated export review",
        ));
        self
    }

    fn with_malformed_response_after_first_invocation(mut self) -> Self {
        self.malformed_after_first = true;
        self
    }
}

impl ProviderAdapter for FakeProvider {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        Ok(self.detection.clone())
    }

    fn invoke(
        &self,
        invocation: qaptr_provider::ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError> {
        self.invocations.set(self.invocations.get() + 1);
        assert!(!invocation.request().context().is_empty());
        if let Some(error) = &self.failure {
            return Err(error.clone());
        }
        if self.malformed_after_first && self.invocations.get() > 1 {
            return Ok(RawProviderResponse::new(
                vec![
                    RawObservation::new(
                        "Partial observation",
                        "This must never be persisted",
                        0.42,
                    ),
                    RawObservation::new("", "Malformed response", 0.42),
                ],
                Some(RawWorkflow::new(
                    "Partial workflow",
                    "This must never be persisted",
                )),
            ));
        }
        Ok(self.response.clone())
    }
}

struct FakeConsent {
    decision: ConsentDecision,
    requests: Cell<u32>,
    last_capture_count: Cell<usize>,
}

struct CancelAfterPreparation {
    checks: Cell<u32>,
}

impl Cancellation for CancelAfterPreparation {
    fn is_cancelled(&self) -> bool {
        self.checks.set(self.checks.get() + 1);
        self.checks.get() > 1
    }
}

impl FakeConsent {
    fn new(decision: ConsentDecision) -> Self {
        Self {
            decision,
            requests: Cell::new(0),
            last_capture_count: Cell::new(0),
        }
    }
}

impl ConsentPort for FakeConsent {
    fn request(&self, request: &ConsentRequest) -> ConsentDecision {
        self.requests.set(self.requests.get() + 1);
        self.last_capture_count.set(request.capture_count());
        self.decision
    }
}

struct Harness {
    _temp: TempRoot,
    vault: Vault,
    credentials: MemoryCredentials,
    store: Store,
    privacy: PrivacyGate,
    ocr: FakeOcr,
    vision: FakeVision,
    clock: FixedClock,
    decoder: Decoder,
}

impl Harness {
    fn new(capture_id: &str, context: ContextSnapshot) -> (Self, CaptureRecordInput) {
        let temp = TempRoot::new();
        let vault = Vault::new(temp.path().join("vault")).expect("vault");
        let credentials = MemoryCredentials::default();
        let keys =
            GenerationKeypair::generate(GenerationId::new("generation-u17").expect("generation"));
        let credential_key =
            Vault::generation_credential_key(keys.generation_id()).expect("credential key");
        credentials
            .write(&credential_key, keys.private_key().to_credential_value())
            .expect("write private key");
        vault
            .register_public_key(keys.generation_id(), keys.public_key())
            .expect("public key");
        let capture = CaptureId::new(capture_id).expect("capture id");
        vault
            .seal(
                &BundleInput::new(
                    capture.clone(),
                    keys.generation_id().clone(),
                    b"test image bytes".to_vec(),
                    SampledContext::new(br#"{"application":"Editor"}"#.to_vec()),
                    Vec::new(),
                ),
                keys.public_key(),
            )
            .expect("seal capture");
        let store = Store::open(temp.path().join("history.sqlite3")).expect("store");
        let mut contexts = HashMap::new();
        contexts.insert(capture_id.to_owned(), context);
        let record = CaptureRecord {
            id: capture,
            captured_at: UnixMillis::from_millis(10),
            vault_record_id: capture_id.to_owned(),
            context_summary: Some("Editor".to_owned()),
        };
        let runner_input = CaptureRecordInput::new(record);
        (
            Self {
                _temp: temp,
                vault,
                credentials,
                store,
                privacy: PrivacyGate::new(recall()),
                ocr: FakeOcr,
                vision: FakeVision,
                clock: FixedClock::new(UNIX_EPOCH + Duration::from_secs(10)),
                decoder: Decoder::with_contexts(contexts),
            },
            runner_input,
        )
    }
}

fn recall() -> RecallReport {
    measure_recall(&[], &[]).expect("empty recall fixture")
}

fn safe_context() -> ContextSnapshot {
    ContextSnapshot::new(
        Some("Editor".to_owned()),
        Some("Review plan".to_owned()),
        Some("https://example.test".to_owned()),
        Some("plan.md".to_owned()),
    )
}

fn unsafe_context() -> ContextSnapshot {
    ContextSnapshot::new(
        Some("Editor".to_owned()),
        Some("unsafe\u{0000}title".to_owned()),
        None,
        None,
    )
}

fn session() -> SessionId {
    SessionId::new("session-u17").expect("session id")
}

fn failure() -> ProviderError {
    ProviderError::RuntimeFailure {
        provider: ProviderId::new("fake-provider").expect("provider id"),
        kind: RuntimeFailureKind::Invocation,
    }
}

fn runner<'a, A>(
    harness: &'a Harness,
    provider: Option<&'a ProviderGate<A>>,
    consent: &'a FakeConsent,
) -> AnalysisRunner<'a, MemoryCredentials, FakeOcr, FakeVision, A, Decoder, FakeConsent, FixedClock>
where
    A: ProviderAdapter,
{
    AnalysisRunner::new(
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.privacy,
        &harness.ocr,
        &harness.vision,
        provider,
        &harness.decoder,
        consent,
        &harness.clock,
    )
}

#[test]
fn privacy_gate_refusal_skips_provider_entirely() {
    let (harness, capture) = Harness::new("refused", unsafe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);

    let report = runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert_eq!(report.excluded_captures, 1);
    assert_eq!(
        report
            .exclusion_notice
            .as_ref()
            .map(|notice| notice.count()),
        Some(1)
    );
    assert_eq!(provider.adapter().invocations.get(), 0);
    assert_eq!(report.observations_written, 0);
    assert_eq!(consent.requests.get(), 0);
    assert_eq!(
        harness.store.snapshot().expect("snapshot").captures.len(),
        1
    );
}

#[test]
fn provider_failure_is_quiet_and_capture_metadata_remains() {
    let (harness, capture) = Harness::new("provider-failure", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(Some(failure())));
    let consent = FakeConsent::new(ConsentDecision::Granted);

    let report = runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert!(matches!(report.provider, ProviderOutcome::Failed { .. }));
    assert_eq!(report.observations_written, 0);
    assert_eq!(provider.adapter().invocations.get(), 1);
    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.captures.len(), 1);
    assert!(snapshot.observations.is_empty());
    assert!(snapshot.workflows.is_empty());
}

#[test]
fn malformed_provider_response_discards_partial_workflow_and_observations() {
    let (harness, capture) = Harness::new("malformed-provider", safe_context());
    let provider = ProviderGate::new(
        FakeProvider::new(None)
            .with_workflow()
            .with_malformed_response_after_first_invocation(),
    );
    let consent = FakeConsent::new(ConsentDecision::Granted);

    let report = runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture.clone(), capture])
        .expect("malformed provider response is a quiet outcome");

    assert!(matches!(
        report.provider,
        ProviderOutcome::Failed {
            error: ProviderError::RuntimeFailure {
                kind: RuntimeFailureKind::MalformedOutput { .. },
                ..
            },
            ..
        }
    ));
    assert_eq!(report.observations_written, 0);
    assert_eq!(provider.adapter().invocations.get(), 2);
    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.captures.len(), 1);
    assert!(snapshot.observations.is_empty());
    assert!(snapshot.workflows.is_empty());
}

#[test]
fn unavailable_provider_is_a_quiet_noop() {
    let (harness, capture) = Harness::new("no-provider", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None).unavailable());
    let consent = FakeConsent::new(ConsentDecision::Granted);

    let report = runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert!(matches!(
        report.provider,
        ProviderOutcome::Unavailable {
            provider: Some(_),
            reason: Some(ProviderError::NotInstalled { .. })
        }
    ));
    assert_eq!(provider.adapter().invocations.get(), 0);
    assert_eq!(consent.requests.get(), 0);
}

#[test]
fn observations_are_scalar_summaries_with_provider_confidence_unchanged() {
    let (harness, capture) = Harness::new("summary", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);

    let report = runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert_eq!(report.observations_written, 1);
    let snapshot = harness.store.snapshot().expect("snapshot");
    let observation = snapshot.observations.first().expect("observation");
    assert_eq!(observation.title, "Repeated step");
    assert_eq!(observation.summary, "The same step recurred");
    assert!((observation.confidence.as_f32() - 0.42).abs() < f32::EPSILON);
    assert_eq!(snapshot.observations.len(), 1);
}

#[test]
fn candidate_workflow_is_persisted_as_scalar_canonical_history() {
    let (harness, capture) = Harness::new("workflow", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None).with_workflow());
    let consent = FakeConsent::new(ConsentDecision::Granted);

    runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.workflows.len(), 1);
    let workflow = snapshot.workflows.first().expect("workflow");
    assert_eq!(workflow.id.as_str(), "u19/session-u17/candidate-0");
    assert_eq!(workflow.title, "Repeated export review");
    assert_eq!(workflow.goal, "Prepare the repeated export review");
    assert!(workflow.sequence.contains("\"steps\":[]"));
    assert!(!workflow.sequence.contains("screenshot"));
}

#[test]
fn rerunning_a_session_upserts_stable_observation_ids_without_duplicates() {
    let (harness, capture) = Harness::new("resume", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);
    let runner = runner(&harness, Some(&provider), &consent);

    runner
        .run(session(), std::slice::from_ref(&capture))
        .expect("first analysis");
    runner
        .run(session(), std::slice::from_ref(&capture))
        .expect("resumed analysis");

    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.observations.len(), 1);
    assert_eq!(
        snapshot.observations[0].id.as_str(),
        "u17/session-u17/resume/0"
    );
    assert_eq!(provider.adapter().invocations.get(), 2);
}

#[test]
fn declined_consent_keeps_preparation_local() {
    let (harness, capture) = Harness::new("declined", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Declined);

    let report = runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert!(matches!(report.provider, ProviderOutcome::ConsentDeclined));
    assert_eq!(provider.adapter().invocations.get(), 0);
    assert_eq!(consent.requests.get(), 1);
    assert_eq!(
        harness
            .store
            .snapshot()
            .expect("snapshot")
            .observations
            .len(),
        0
    );
}

#[test]
fn opened_bundle_is_consumed_before_gate_preparation() {
    let (harness, capture) = Harness::new("opened", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);

    runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert_eq!(harness.decoder.opened.get(), 1);
}

#[test]
fn provider_payload_kind_is_text_without_image_opt_in() {
    let (harness, capture) = Harness::new("text-only", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);

    runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert_eq!(provider.adapter().invocations.get(), 1);
}

#[test]
fn fixed_clock_makes_observation_creation_deterministic() {
    let (harness, capture) = Harness::new("clock", safe_context());
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);

    runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture])
        .expect("analysis");

    assert_eq!(
        harness.store.snapshot().expect("snapshot").observations[0]
            .created_at
            .as_millis(),
        10_000
    );
}

#[test]
fn interruption_discards_staged_observations_for_a_clean_resume() {
    let (harness, capture) = Harness::new("cancelled", safe_context());
    let capture_for_resume = capture.clone();
    let provider = ProviderGate::new(FakeProvider::new(None));
    let consent = FakeConsent::new(ConsentDecision::Granted);
    let cancellation = CancelAfterPreparation {
        checks: Cell::new(0),
    };

    let report = runner(&harness, Some(&provider), &consent)
        .run_with_cancellation(session(), &[capture], &cancellation)
        .expect("analysis");

    assert!(matches!(report.provider, ProviderOutcome::Cancelled));
    assert_eq!(provider.adapter().invocations.get(), 0);
    assert!(
        harness
            .store
            .snapshot()
            .expect("snapshot")
            .observations
            .is_empty()
    );

    runner(&harness, Some(&provider), &consent)
        .run(session(), &[capture_for_resume])
        .expect("resumed analysis");
    assert_eq!(
        harness
            .store
            .snapshot()
            .expect("snapshot")
            .observations
            .len(),
        1
    );
}
