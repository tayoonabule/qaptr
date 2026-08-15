//! Deterministic `ReviewSessionCoordinator` lifecycle over real vault/store
//! boundaries with a fake provider behind the current gate boundary.
//!
//! These scenarios cover the smallest production-shaped slice: sealed capture
//! ingestion through the coordinator reaches `Preparing` before any provider
//! request is attempted, and a declined consent decision makes zero provider
//! calls while still completing the session.

#![allow(clippy::expect_used, clippy::panic)]

use std::cell::Cell;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
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
use qaptr_privacy::{PreparationInput, PrivacyGate, measure_recall};
use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, CapabilityDescriptor, ExecutablePath,
    ProviderAdapter, ProviderDescriptor, ProviderDetection, ProviderError, ProviderGate,
    ProviderId, ProviderLocation, ProviderVersion, RawObservation, RawProviderResponse,
};
use qaptr_store::{CaptureRecord, Store, UnixMillis};
use qaptr_vault::OpenedBundle;
use qaptr_vault::{BundleInput, GenerationId, GenerationKeypair, SampledContext, Vault};
use qaptr_workflow::{
    CaptureDecoder, CaptureRecordInput, ConsentDecision, ConsentPort, ConsentRequest, DecodeError,
    ProviderOutcome, ReviewSessionCoordinator,
};

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

struct TempRoot(PathBuf);

impl TempRoot {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "qaptr-session-coordinator-{}-{}",
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
    decoded: Rc<Cell<usize>>,
}

impl Decoder {
    fn with_contexts(contexts: HashMap<String, ContextSnapshot>) -> Self {
        Self {
            contexts,
            decoded: Rc::new(Cell::new(0)),
        }
    }
}

impl CaptureDecoder for Decoder {
    fn decode(&self, bundle: &OpenedBundle) -> Result<PreparationInput, DecodeError> {
        let capture_id = bundle.metadata().capture_id.clone();
        bundle.with_image_for_privacy(|image| {
            image.with_bytes(|bytes| assert!(!bytes.is_empty()));
        });
        let context = self
            .contexts
            .get(capture_id.as_str())
            .cloned()
            .ok_or_else(|| DecodeError::InvalidInput("missing test context".to_owned()))?;
        self.decoded.set(self.decoded.get() + 1);
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

/// A provider adapter that records whether it was ever detected or invoked,
/// so tests can assert zero calls behind the consent boundary.
struct RecordingProvider {
    descriptor: ProviderDescriptor,
    detections: Cell<u32>,
    invocations: Cell<u32>,
    expected_preparations: Option<(Rc<Cell<usize>>, usize)>,
}

impl RecordingProvider {
    fn new() -> Self {
        Self::with_preparation_counter(None)
    }

    fn new_with_preparation_counter(prepared: Rc<Cell<usize>>, expected: usize) -> Self {
        Self::with_preparation_counter(Some((prepared, expected)))
    }

    fn with_preparation_counter(expected_preparations: Option<(Rc<Cell<usize>>, usize)>) -> Self {
        let id = ProviderId::new("fake-provider").expect("provider id");
        let descriptor = ProviderDescriptor::new(
            id,
            "Fake provider",
            ProviderVersion::new(1, 0, 0),
            AuthenticationMode::ExistingCliSession,
            CapabilityDescriptor::text_only(),
        )
        .expect("provider descriptor");
        Self {
            descriptor,
            detections: Cell::new(0),
            invocations: Cell::new(0),
            expected_preparations,
        }
    }
}

impl ProviderAdapter for RecordingProvider {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        self.detections.set(self.detections.get() + 1);
        if let Some((prepared, expected)) = &self.expected_preparations {
            assert_eq!(prepared.get(), *expected);
        }
        let executable =
            ExecutablePath::new("/usr/local/bin/fake-provider").expect("absolute path");
        Ok(ProviderDetection::installed(
            ProviderLocation::Executable(executable),
            ProviderVersion::new(1, 0, 0),
            AuthenticationStatus::Authenticated,
        ))
    }

    fn invoke(
        &self,
        invocation: qaptr_provider::ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError> {
        self.invocations.set(self.invocations.get() + 1);
        assert!(!invocation.request().context().is_empty());
        Ok(RawProviderResponse::new(
            vec![RawObservation::new(
                "Repeated step",
                "The same step recurred",
                0.42,
            )],
            None,
        ))
    }
}

struct FakeConsent {
    decision: ConsentDecision,
    requests: Cell<u32>,
}

impl FakeConsent {
    fn new(decision: ConsentDecision) -> Self {
        Self {
            decision,
            requests: Cell::new(0),
        }
    }
}

impl ConsentPort for FakeConsent {
    fn request(&self, _request: &ConsentRequest) -> ConsentDecision {
        self.requests.set(self.requests.get() + 1);
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
        let (harness, mut captures) = Self::new_many(vec![(capture_id, context)]);
        (harness, captures.pop().expect("one capture"))
    }

    fn new_many(captures: Vec<(&str, ContextSnapshot)>) -> (Self, Vec<CaptureRecordInput>) {
        let temp = TempRoot::new();
        let vault = Vault::new(temp.path().join("vault")).expect("vault");
        let credentials = MemoryCredentials::default();
        let keys = GenerationKeypair::generate(
            GenerationId::new("generation-session-coordinator").expect("generation"),
        );
        let credential_key =
            Vault::generation_credential_key(keys.generation_id()).expect("credential key");
        credentials
            .write(&credential_key, keys.private_key().to_credential_value())
            .expect("write private key");
        vault
            .register_public_key(keys.generation_id(), keys.public_key())
            .expect("public key");
        let store = Store::open(temp.path().join("history.sqlite3")).expect("store");
        let mut decoder_contexts = HashMap::new();
        let runner_inputs = captures
            .into_iter()
            .map(|(capture_id, context)| {
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
                decoder_contexts.insert(capture_id.to_owned(), context);
                CaptureRecordInput::new(CaptureRecord {
                    id: capture,
                    captured_at: UnixMillis::from_millis(10),
                    vault_record_id: capture_id.to_owned(),
                    context_summary: Some("Editor".to_owned()),
                })
            })
            .collect();
        (
            Self {
                _temp: temp,
                vault,
                credentials,
                store,
                privacy: PrivacyGate::new(measure_recall(&[], &[]).expect("empty recall fixture")),
                ocr: FakeOcr,
                vision: FakeVision,
                clock: FixedClock::new(UNIX_EPOCH + Duration::from_secs(10)),
                decoder: Decoder::with_contexts(decoder_contexts),
            },
            runner_inputs,
        )
    }
}

fn safe_context() -> ContextSnapshot {
    ContextSnapshot::new(
        Some("Editor".to_owned()),
        Some("Review plan".to_owned()),
        Some("https://example.test".to_owned()),
        Some("plan.md".to_owned()),
    )
}

fn session_id(name: &str) -> SessionId {
    SessionId::new(name).expect("session id")
}

/// Ingesting a sealed capture through the coordinator reaches `Preparing`
/// before the runner ever detects or invokes a provider, and consent granted
/// afterward commits observations exactly once.
#[test]
fn eligible_sealed_capture_prepares_before_any_provider_request() {
    let (harness, capture) = Harness::new("coordinator-granted", safe_context());
    let adapter = RecordingProvider::new();
    let provider = ProviderGate::new(adapter);
    let consent = FakeConsent::new(ConsentDecision::Granted);
    let runner = qaptr_workflow::AnalysisRunner::new(
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.privacy,
        &harness.ocr,
        &harness.vision,
        Some(&provider),
        &harness.decoder,
        &consent,
        &harness.clock,
    );
    let mut coordinator = ReviewSessionCoordinator::new(
        &runner,
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.clock,
    );

    let mut states = Vec::new();
    let report = coordinator
        .start(session_id("coordinator-granted"), &[capture], |state| {
            states.push(state.state_name())
        })
        .expect("coordinator session");

    // Preparation runs, and the recorded state order places "preparing"
    // strictly before the provider is ever detected or invoked.
    assert_eq!(
        states,
        vec!["ingesting", "preparing", "analyzing", "completed"]
    );
    assert_eq!(provider.adapter().detections.get(), 1);
    assert_eq!(provider.adapter().invocations.get(), 1);
    assert_eq!(consent.requests.get(), 1);
    assert!(matches!(report.provider, ProviderOutcome::Completed { .. }));
    assert_eq!(report.observations_written, 1);
    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.captures.len(), 1);
    assert_eq!(snapshot.observations.len(), 1);
    assert_eq!(
        coordinator.last_capture_ids(),
        vec![CaptureId::new("coordinator-granted").expect("capture id")]
    );
}

/// The checklist 2.4 vertical slice exercises twenty-four sealed captures
/// through the real vault, privacy, adapter, and coordinator boundaries.
#[test]
fn twenty_four_captures_prepare_before_provider_and_keep_safe_observations() {
    let excluded_id = "coordinator-capture-12";
    let captures = (0..24)
        .map(|index| {
            let id = format!("coordinator-capture-{index:02}");
            let context = if id == excluded_id {
                ContextSnapshot::new(
                    Some("Editor".to_owned()),
                    Some("unsafe\u{0000}title".to_owned()),
                    None,
                    None,
                )
            } else {
                safe_context()
            };
            (id, context)
        })
        .collect::<Vec<_>>();
    let capture_refs = captures
        .iter()
        .map(|(id, context)| (id.as_str(), context.clone()))
        .collect();
    let (harness, captures) = Harness::new_many(capture_refs);
    let adapter = RecordingProvider::new_with_preparation_counter(
        harness.decoder.decoded.clone(),
        captures.len(),
    );
    let provider = ProviderGate::new(adapter);
    let consent = FakeConsent::new(ConsentDecision::Granted);
    let runner = qaptr_workflow::AnalysisRunner::new(
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.privacy,
        &harness.ocr,
        &harness.vision,
        Some(&provider),
        &harness.decoder,
        &consent,
        &harness.clock,
    )
    .with_observation_limit(24);
    let mut coordinator = ReviewSessionCoordinator::new(
        &runner,
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.clock,
    );

    let mut states = Vec::new();
    let report = coordinator
        .start(session_id("coordinator-24-captures"), &captures, |state| {
            states.push(state.state_name())
        })
        .expect("coordinator session");

    assert_eq!(
        states,
        vec!["ingesting", "preparing", "analyzing", "completed"]
    );
    assert_eq!(harness.decoder.decoded.get(), 24);
    assert_eq!(report.captures_seen, 24);
    assert_eq!(report.prepared_captures, 23);
    assert_eq!(report.excluded_captures, 1);
    assert_eq!(report.observations_written, 23);
    assert_eq!(
        report
            .exclusion_notice
            .as_ref()
            .map(|notice| (notice.count(), notice.text())),
        Some((
            1,
            "1 capture was excluded because it could not be safely prepared.".to_owned()
        ))
    );
    assert!(matches!(report.provider, ProviderOutcome::Completed { .. }));
    assert_eq!(provider.adapter().detections.get(), 1);
    assert_eq!(provider.adapter().invocations.get(), 23);
    assert_eq!(consent.requests.get(), 1);

    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.captures.len(), 24);
    assert_eq!(snapshot.observations.len(), 23);
    assert!(snapshot.observations.iter().all(|observation| {
        observation
            .capture_id
            .as_ref()
            .is_some_and(|capture_id| capture_id.as_str() != excluded_id)
    }));
}

/// Declined consent keeps everything local: the provider is detected (the
/// runner must know who to ask consent for) but never invoked, and the
/// coordinator still reports a completed session with zero observations.
#[test]
fn declined_consent_through_coordinator_makes_zero_provider_calls() {
    let (harness, capture) = Harness::new("coordinator-declined", safe_context());
    let adapter = RecordingProvider::new();
    let provider = ProviderGate::new(adapter);
    let consent = FakeConsent::new(ConsentDecision::Declined);
    let runner = qaptr_workflow::AnalysisRunner::new(
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.privacy,
        &harness.ocr,
        &harness.vision,
        Some(&provider),
        &harness.decoder,
        &consent,
        &harness.clock,
    );
    let mut coordinator = ReviewSessionCoordinator::new(
        &runner,
        &harness.vault,
        &harness.credentials,
        &harness.store,
        &harness.clock,
    );

    let mut states = Vec::new();
    let report = coordinator
        .start(session_id("coordinator-declined"), &[capture], |state| {
            states.push(state.state_name())
        })
        .expect("coordinator session");

    assert_eq!(states, vec!["ingesting", "preparing", "completed"]);
    assert_eq!(consent.requests.get(), 1);
    // Consent gates the provider invocation, never the handshake needed to
    // know which provider to ask consent for.
    assert_eq!(provider.adapter().invocations.get(), 0);
    assert!(matches!(report.provider, ProviderOutcome::ConsentDeclined));
    assert_eq!(report.observations_written, 0);
    let snapshot = harness.store.snapshot().expect("snapshot");
    assert_eq!(snapshot.captures.len(), 1);
    assert_eq!(snapshot.observations.len(), 0);
    assert_eq!(
        coordinator.last_capture_ids(),
        vec![CaptureId::new("coordinator-declined").expect("capture id")]
    );
}
