//! App-owned review-session driver for the scalar JSON v1 C ABI.
//!
//! The worker owns the vault, store, local privacy pipeline, and lifecycle
//! coordinator. The C ABI owns only bounded JSON requests and scalar state.
//! Provider construction is deliberately conservative in this first slice:
//! no configured provider is selected, so a production session reports a
//! truthful unavailable result and never reaches consent or provider dispatch.

use std::path::PathBuf;
use std::sync::{
    Arc, Condvar, Mutex,
    atomic::{AtomicBool, Ordering},
    mpsc::{self, Receiver, Sender},
};
use std::thread;
use std::time::Duration;

use qaptr_domain::{SessionId, SystemClock};
use qaptr_macos::{MacCredentials, MacOcr, MacVision};
use qaptr_privacy::{PrivacyGate, measure_recall};
use qaptr_provider::{
    AuthenticationMode, CapabilityDescriptor, ProviderAdapter, ProviderDescriptor,
    ProviderDetection, ProviderError, ProviderGate, ProviderId, ProviderInvocation,
    ProviderPayloadKind, ProviderVersion, RawProviderResponse,
};
use qaptr_store::{CaptureRecord, Store, UnixMillis};
use qaptr_vault::Vault;
use qaptr_workflow::{
    AnalysisReport, AnalysisRunner, CaptureRecordInput, ConsentDecision, ConsentPort,
    ConsentRequest, ProviderOutcome, ReviewProgress, ReviewSessionCoordinator,
};
use serde_json::{Map, Value, json};

use crate::local::LocalBundleDecoder;

/// Maximum request size accepted by the JSON v1 operation boundary.
pub(crate) const MAX_REQUEST_BYTES: usize = 4 * 1024;
/// Maximum scalar identifier length accepted by the JSON v1 operation boundary.
pub(crate) const MAX_ID_BYTES: usize = 256;

const VERSION: u64 = 1;
const OPERATION_ERROR: &str = "invalid_operation";
const MALFORMED_REQUEST: &str = "malformed_request";
const SESSION_BUSY: &str = "session_busy";
const SESSION_UNAVAILABLE: &str = "session_unavailable";
const NO_BUNDLES: &str = "no_committed_bundles";
const RETRY_UNAVAILABLE: &str = "retry_unavailable";
const LOCAL_REVIEW_FAILED: &str = "local_review_failed";
const PROVIDER_UNAVAILABLE: &str = "provider_unavailable";
const PROVIDER_FAILED: &str = "provider_failed";

struct UnavailableProvider {
    descriptor: ProviderDescriptor,
}

impl UnavailableProvider {
    fn new() -> Self {
        Self {
            descriptor: ProviderDescriptor::new(
                ProviderId::new("unconfigured").expect("static provider id"),
                "No provider configured",
                ProviderVersion::new(1, 0, 0),
                AuthenticationMode::ExistingCliSession,
                CapabilityDescriptor::text_only(),
            )
            .expect("static provider descriptor"),
        }
    }
}

impl ProviderAdapter for UnavailableProvider {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        Ok(ProviderDetection::not_installed())
    }

    fn invoke(
        &self,
        _invocation: ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError> {
        Err(ProviderError::NotInstalled {
            provider: self.descriptor.id().clone(),
        })
    }
}

#[derive(Clone, Debug)]
struct ConsentSummaryState {
    provider: String,
    resolved_model: Option<String>,
    payload_kind: &'static str,
    capture_count: usize,
    image_count: usize,
    exclusion_count: usize,
}

#[derive(Clone, Debug)]
struct DriverState {
    session_id: Option<String>,
    phase: &'static str,
    captures_seen: usize,
    prepared_captures: usize,
    image_count: usize,
    exclusion_count: usize,
    observations_written: usize,
    consent_summary: Option<ConsentSummaryState>,
    result: Option<&'static str>,
    outcome: Option<&'static str>,
    error: Option<&'static str>,
}

impl Default for DriverState {
    fn default() -> Self {
        Self {
            session_id: None,
            phase: "idle",
            captures_seen: 0,
            prepared_captures: 0,
            image_count: 0,
            exclusion_count: 0,
            observations_written: 0,
            consent_summary: None,
            result: None,
            outcome: None,
            error: None,
        }
    }
}

impl DriverState {
    fn allowed_operations(&self) -> Vec<&'static str> {
        let mut operations = vec!["state"];
        operations.extend(match self.phase {
            "idle" => ["start"].as_slice(),
            "ingesting" | "preparing" | "analyzing" => ["cancel"].as_slice(),
            "ready_for_consent" => ["decide_consent", "cancel"].as_slice(),
            "completed" | "failed" | "cancelled" => ["start", "retry"].as_slice(),
            _ => [].as_slice(),
        });
        operations
    }

    fn to_json(&self) -> Value {
        let consent_summary = self.consent_summary.as_ref().map(|summary| {
            json!({
                "provider": summary.provider,
                "resolved_model": summary.resolved_model,
                "payload_kind": summary.payload_kind,
                "capture_count": summary.capture_count,
                "image_count": summary.image_count,
                "exclusion_count": summary.exclusion_count,
            })
        });
        json!({
            "session_id": self.session_id,
            "phase": self.phase,
            "captures_seen": self.captures_seen,
            "prepared_captures": self.prepared_captures,
            "image_count": self.image_count,
            "exclusion_count": self.exclusion_count,
            "observations_written": self.observations_written,
            "consent_summary": consent_summary,
            "result": self.result,
            "outcome": self.outcome,
            "error": self.error,
            "allowed_operations": self.allowed_operations(),
        })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PendingConsent {
    Waiting,
    Granted,
    Declined,
    Cancelled,
}

struct ConsentControl {
    decision: Mutex<Option<PendingConsent>>,
    wake: Condvar,
}

impl ConsentControl {
    fn new() -> Self {
        Self {
            decision: Mutex::new(None),
            wake: Condvar::new(),
        }
    }

    fn reset(&self) {
        *self
            .decision
            .lock()
            .unwrap_or_else(|poison| poison.into_inner()) = None;
    }

    fn request(&self, request: &ConsentRequest, shared: &SharedState) -> ConsentDecision {
        shared.set_consent_summary(request);
        let mut decision = self
            .decision
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        *decision = Some(PendingConsent::Waiting);
        loop {
            if shared.cancel_requested.load(Ordering::Acquire) {
                *decision = Some(PendingConsent::Cancelled);
            }
            match *decision {
                Some(PendingConsent::Granted) => {
                    *decision = None;
                    return ConsentDecision::Granted;
                }
                Some(PendingConsent::Declined | PendingConsent::Cancelled) => {
                    *decision = None;
                    return ConsentDecision::Declined;
                }
                Some(PendingConsent::Waiting) | None => {
                    decision = self
                        .wake
                        .wait(decision)
                        .unwrap_or_else(|poison| poison.into_inner());
                }
            }
        }
    }

    fn decide(&self, decision: PendingConsent, shared: &SharedState) -> bool {
        let mut pending = self
            .decision
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if !matches!(*pending, Some(PendingConsent::Waiting)) {
            return false;
        }
        *pending = Some(decision);
        if decision == PendingConsent::Granted {
            shared.set_phase("analyzing");
        }
        self.wake.notify_all();
        true
    }

    fn cancel(&self) {
        let mut pending = self
            .decision
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if matches!(*pending, Some(PendingConsent::Waiting)) {
            *pending = Some(PendingConsent::Cancelled);
            self.wake.notify_all();
        }
    }
}

#[derive(Clone)]
struct ConsentBroker {
    control: Arc<ConsentControl>,
    shared: Arc<SharedState>,
}

impl ConsentBroker {
    fn new(control: Arc<ConsentControl>, shared: Arc<SharedState>) -> Self {
        Self { control, shared }
    }
}

impl ConsentPort for ConsentBroker {
    fn request(&self, request: &ConsentRequest) -> ConsentDecision {
        self.control.request(request, &self.shared)
    }
}

struct SharedState {
    state: Mutex<DriverState>,
    control: Arc<ConsentControl>,
    cancel_requested: AtomicBool,
    active_cancellation: Mutex<Option<qaptr_workflow::SessionCancellation>>,
}

impl SharedState {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(DriverState::default()),
            control: Arc::new(ConsentControl::new()),
            cancel_requested: AtomicBool::new(false),
            active_cancellation: Mutex::new(None),
        })
    }

    fn snapshot(&self) -> DriverState {
        self.state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .clone()
    }

    fn set_phase(&self, phase: &'static str) {
        self.state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .phase = phase;
    }

    fn begin(&self, session_id: &SessionId) {
        self.cancel_requested.store(false, Ordering::Release);
        self.control.reset();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        *state = DriverState {
            session_id: Some(session_id.as_str().to_owned()),
            phase: "ingesting",
            ..DriverState::default()
        };
    }

    fn set_active_cancellation(&self, cancellation: Option<qaptr_workflow::SessionCancellation>) {
        *self
            .active_cancellation
            .lock()
            .unwrap_or_else(|poison| poison.into_inner()) = cancellation;
    }

    fn cancel(&self) {
        self.cancel_requested.store(true, Ordering::Release);
        if let Some(cancellation) = self
            .active_cancellation
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .as_ref()
        {
            cancellation.cancel();
        }
        self.control.cancel();
    }

    fn set_consent_summary(&self, request: &ConsentRequest) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        state.phase = "ready_for_consent";
        state.prepared_captures = request.capture_count();
        state.image_count = request.image_count();
        state.exclusion_count = request.exclusion_count();
        state.consent_summary = Some(ConsentSummaryState {
            provider: request.provider().as_str().to_owned(),
            resolved_model: request
                .resolved_model()
                .map(|model| model.as_str().to_owned()),
            payload_kind: match request.payload_kind() {
                ProviderPayloadKind::Text => "text",
                ProviderPayloadKind::Images => "images",
            },
            capture_count: request.capture_count(),
            image_count: request.image_count(),
            exclusion_count: request.exclusion_count(),
        });
    }

    fn apply_progress(&self, progress: ReviewProgress) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        match progress {
            ReviewProgress::Ingesting { captures_seen } => {
                state.phase = "ingesting";
                state.captures_seen = captures_seen;
            }
            ReviewProgress::Preparing { captures_seen } => {
                state.phase = "preparing";
                state.captures_seen = captures_seen;
            }
            ReviewProgress::ReadyForConsent {
                captures_seen,
                prepared_captures,
                excluded_captures,
                provider,
            } => {
                state.phase = "ready_for_consent";
                state.captures_seen = captures_seen;
                state.prepared_captures = prepared_captures;
                state.exclusion_count = excluded_captures;
                if let Some(provider) = provider {
                    state.consent_summary = Some(ConsentSummaryState {
                        provider: provider.as_str().to_owned(),
                        resolved_model: None,
                        payload_kind: "text",
                        capture_count: prepared_captures,
                        image_count: 0,
                        exclusion_count: excluded_captures,
                    });
                }
            }
            ReviewProgress::Analyzing { captures } => {
                state.phase = "analyzing";
                state.prepared_captures = captures;
            }
            ReviewProgress::Completed {
                captures_seen,
                observations_written,
            } => {
                state.phase = "completed";
                state.captures_seen = captures_seen;
                state.observations_written = observations_written;
            }
            ReviewProgress::Cancelled { captures_seen } => {
                state.phase = "cancelled";
                state.captures_seen = captures_seen;
            }
            ReviewProgress::Failed { .. } => {
                state.phase = "failed";
            }
        }
    }

    fn finish_report(&self, report: &AnalysisReport) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        state.captures_seen = report.captures_seen;
        state.prepared_captures = report.prepared_captures;
        state.exclusion_count = report.excluded_captures;
        state.observations_written = report.observations_written;
        if self.cancel_requested.load(Ordering::Acquire)
            && matches!(&report.provider, ProviderOutcome::ConsentDeclined)
        {
            state.phase = "cancelled";
            state.result = None;
            state.outcome = Some("cancelled");
            state.error = None;
            return;
        }
        match &report.provider {
            ProviderOutcome::Completed { .. } => {
                state.phase = "completed";
                state.result = Some("analysis_completed");
                state.outcome = Some("provider_completed");
            }
            ProviderOutcome::ConsentDeclined => {
                state.phase = "completed";
                state.result = Some("completed_without_provider");
                state.outcome = Some("consent_declined");
            }
            ProviderOutcome::Unavailable { .. } => {
                state.phase = "failed";
                state.outcome = Some(PROVIDER_UNAVAILABLE);
                state.error = Some(PROVIDER_UNAVAILABLE);
            }
            ProviderOutcome::Failed { .. } => {
                state.phase = "failed";
                state.outcome = Some(PROVIDER_FAILED);
                state.error = Some(PROVIDER_FAILED);
            }
            ProviderOutcome::Cancelled => {
                state.phase = "cancelled";
                state.outcome = Some("cancelled");
            }
            ProviderOutcome::NotAttempted => {
                state.phase = "completed";
                state.result = Some("completed_without_provider");
                state.outcome = Some("no_eligible_payload");
            }
        }
    }

    fn fail(&self, error: &'static str) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        state.phase = "failed";
        state.result = None;
        state.outcome = None;
        state.error = Some(error);
    }
}

struct ProductionResources {
    vault: Vault,
    credentials: MacCredentials,
    store: Store,
    privacy: PrivacyGate,
    ocr: MacOcr,
    vision: MacVision,
    decoder: LocalBundleDecoder,
    clock: SystemClock,
    consent: ConsentBroker,
    provider: ProviderGate<UnavailableProvider>,
}

impl ProductionResources {
    fn new(
        vault_root: PathBuf,
        store_path: PathBuf,
        control: Arc<ConsentControl>,
        shared: Arc<SharedState>,
    ) -> Result<Self, ()> {
        let vault = Vault::new(vault_root).map_err(|_| ())?;
        let image_root = vault.root().to_path_buf();
        let store = Store::open(store_path).map_err(|_| ())?;
        let recall = measure_recall(&[], &[]).map_err(|_| ())?;
        Ok(Self {
            vault,
            credentials: MacCredentials::new(),
            store,
            privacy: PrivacyGate::new(recall),
            ocr: MacOcr::new(image_root.clone()),
            vision: MacVision::new(image_root),
            decoder: LocalBundleDecoder::for_macos(),
            clock: SystemClock,
            consent: ConsentBroker::new(control, shared),
            provider: ProviderGate::new(UnavailableProvider::new()),
        })
    }
}

enum WorkerCommand {
    Start {
        session_id: SessionId,
        acknowledged: Sender<()>,
    },
    Retry {
        acknowledged: Sender<()>,
    },
    Shutdown,
}

/// App-owned review session handle backing the scalar JSON ABI.
pub struct ReviewSessionDriver {
    shared: Arc<SharedState>,
    commands: Sender<WorkerCommand>,
    _worker: thread::JoinHandle<()>,
}

impl ReviewSessionDriver {
    /// Creates a driver whose worker owns the vault and history store.
    pub(crate) fn new(vault_root: PathBuf, store_path: PathBuf) -> Self {
        let shared = SharedState::new();
        let (commands, receiver) = mpsc::channel();
        let worker_shared = shared.clone();
        let worker_control = shared.control.clone();
        let worker = thread::spawn(move || {
            worker_loop(
                vault_root,
                store_path,
                receiver,
                worker_shared,
                worker_control,
            );
        });
        Self {
            shared,
            commands,
            _worker: worker,
        }
    }

    /// Dispatches one bounded JSON v1 request and returns a scalar JSON result.
    pub(crate) fn request(&self, input: &[u8]) -> Value {
        if input.len() > MAX_REQUEST_BYTES {
            return self.response(Some(MALFORMED_REQUEST));
        }
        let operation = match parse_operation(input) {
            Ok(operation) => operation,
            Err(error) => return self.response(Some(error)),
        };
        match operation {
            Operation::State => self.response(None),
            Operation::Start { session_id } => {
                if self.start(session_id) {
                    self.response(None)
                } else {
                    self.response(Some(SESSION_BUSY))
                }
            }
            Operation::Cancel => {
                if !self.allowed("cancel") {
                    return self.response(Some(OPERATION_ERROR));
                }
                self.shared.cancel();
                self.response(None)
            }
            Operation::Retry => {
                if !self.allowed("retry") {
                    return self.response(Some(OPERATION_ERROR));
                }
                self.shared.begin(
                    &SessionId::new(
                        self.shared
                            .snapshot()
                            .session_id
                            .unwrap_or_else(|| "retry".to_owned()),
                    )
                    .expect("state session ids are validated before storage"),
                );
                let (acknowledged, receiver) = mpsc::channel();
                if self
                    .commands
                    .send(WorkerCommand::Retry { acknowledged })
                    .is_err()
                    || receiver.recv_timeout(Duration::from_secs(2)).is_err()
                {
                    self.shared.fail(SESSION_UNAVAILABLE);
                }
                self.response(None)
            }
            Operation::DecideConsent { decision } => {
                if !self.allowed("decide_consent") {
                    return self.response(Some(OPERATION_ERROR));
                }
                if !self.shared.control.decide(decision, &self.shared) {
                    return self.response(Some(OPERATION_ERROR));
                }
                self.response(None)
            }
        }
    }

    fn start(&self, session_id: SessionId) -> bool {
        if !self.allowed("start") {
            return false;
        }
        self.shared.begin(&session_id);
        let (acknowledged, receiver) = mpsc::channel();
        if self
            .commands
            .send(WorkerCommand::Start {
                session_id,
                acknowledged,
            })
            .is_err()
            || receiver.recv_timeout(Duration::from_secs(2)).is_err()
        {
            self.shared.fail(SESSION_UNAVAILABLE);
        }
        true
    }

    fn allowed(&self, operation: &str) -> bool {
        self.shared
            .snapshot()
            .allowed_operations()
            .contains(&operation)
    }

    fn response(&self, error: Option<&'static str>) -> Value {
        let state = self.shared.snapshot();
        match error {
            Some(error) => json!({
                "version": VERSION,
                "ok": false,
                "error": error,
                "state": state.to_json(),
            }),
            None => json!({
                "version": VERSION,
                "ok": true,
                "state": state.to_json(),
            }),
        }
    }
}

impl Drop for ReviewSessionDriver {
    fn drop(&mut self) {
        self.shared.cancel();
        let _ = self.commands.send(WorkerCommand::Shutdown);
    }
}

fn worker_loop(
    vault_root: PathBuf,
    store_path: PathBuf,
    receiver: Receiver<WorkerCommand>,
    shared: Arc<SharedState>,
    control: Arc<ConsentControl>,
) {
    let mut resources =
        ProductionResources::new(vault_root, store_path, control, shared.clone()).ok();
    let mut last_captures = None;
    let mut last_session = None;
    while let Ok(command) = receiver.recv() {
        match command {
            WorkerCommand::Start {
                session_id,
                acknowledged,
            } => {
                let _ = acknowledged.send(());
                last_session = Some(session_id.clone());
                let Some(resources) = resources.as_mut() else {
                    shared.fail(SESSION_UNAVAILABLE);
                    continue;
                };
                let captures = match committed_captures(&resources.vault) {
                    Ok(captures) if captures.is_empty() => {
                        shared.fail(NO_BUNDLES);
                        continue;
                    }
                    Ok(captures) => captures,
                    Err(()) => {
                        shared.fail(SESSION_UNAVAILABLE);
                        continue;
                    }
                };
                last_captures = Some(captures.clone());
                run_attempt(resources, &shared, session_id, &captures);
            }
            WorkerCommand::Retry { acknowledged } => {
                let _ = acknowledged.send(());
                let (Some(resources), Some(session_id)) =
                    (resources.as_mut(), last_session.clone())
                else {
                    shared.fail(RETRY_UNAVAILABLE);
                    continue;
                };
                let captures = match last_captures.clone() {
                    Some(captures) => captures,
                    None => match committed_captures(&resources.vault) {
                        Ok(captures) => captures,
                        Err(()) => {
                            shared.fail(SESSION_UNAVAILABLE);
                            continue;
                        }
                    },
                };
                if captures.is_empty() {
                    shared.fail(NO_BUNDLES);
                    continue;
                }
                last_captures = Some(captures.clone());
                run_attempt(resources, &shared, session_id, &captures);
            }
            WorkerCommand::Shutdown => break,
        }
    }
}

fn run_attempt(
    resources: &mut ProductionResources,
    shared: &Arc<SharedState>,
    session_id: SessionId,
    captures: &[CaptureRecordInput],
) {
    shared.control.reset();
    let runner = AnalysisRunner::new(
        &resources.vault,
        &resources.credentials,
        &resources.store,
        &resources.privacy,
        &resources.ocr,
        &resources.vision,
        Some(&resources.provider),
        &resources.decoder,
        &resources.consent,
        &resources.clock,
    );
    let mut coordinator = ReviewSessionCoordinator::new(
        &runner,
        &resources.vault,
        &resources.credentials,
        &resources.store,
        &resources.clock,
    );
    shared.set_active_cancellation(Some(coordinator.cancellation()));
    let result = coordinator.start(session_id, captures, |progress| {
        shared.apply_progress(progress)
    });
    shared.set_active_cancellation(None);
    match result {
        Ok(report) => shared.finish_report(&report),
        Err(_) => shared.fail(LOCAL_REVIEW_FAILED),
    }
}

fn committed_captures(vault: &Vault) -> Result<Vec<CaptureRecordInput>, ()> {
    vault
        .list_committed_bundles()
        .map_err(|_| ())?
        .into_iter()
        .map(|metadata| {
            let captured_at = UnixMillis::from_system_time(metadata.captured_at).map_err(|_| ())?;
            Ok(CaptureRecordInput::new(CaptureRecord {
                id: metadata.capture_id.clone(),
                captured_at,
                vault_record_id: metadata.capture_id.as_str().to_owned(),
                context_summary: None,
            }))
        })
        .collect()
}

#[derive(Debug, Eq, PartialEq)]
enum Operation {
    State,
    Start { session_id: SessionId },
    DecideConsent { decision: PendingConsent },
    Cancel,
    Retry,
}

fn parse_operation(input: &[u8]) -> Result<Operation, &'static str> {
    let value: Value = serde_json::from_slice(input).map_err(|_| MALFORMED_REQUEST)?;
    let object = value.as_object().ok_or(MALFORMED_REQUEST)?;
    for key in object.keys() {
        if !matches!(
            key.as_str(),
            "version" | "operation" | "session_id" | "decision"
        ) {
            return Err(MALFORMED_REQUEST);
        }
    }
    if object.get("version").and_then(Value::as_u64) != Some(VERSION) {
        return Err(MALFORMED_REQUEST);
    }
    let operation = object
        .get("operation")
        .and_then(Value::as_str)
        .ok_or(MALFORMED_REQUEST)?;
    match operation {
        "state" => Ok(Operation::State),
        "start" => {
            let session_id = bounded_string(object, "session_id")?;
            Ok(Operation::Start {
                session_id: SessionId::new(session_id).map_err(|_| MALFORMED_REQUEST)?,
            })
        }
        "cancel" => Ok(Operation::Cancel),
        "retry" => Ok(Operation::Retry),
        "decide_consent" => {
            let decision = match bounded_string(object, "decision")?.as_str() {
                "grant" => PendingConsent::Granted,
                "decline" => PendingConsent::Declined,
                _ => return Err(MALFORMED_REQUEST),
            };
            Ok(Operation::DecideConsent { decision })
        }
        _ => Err(MALFORMED_REQUEST),
    }
}

fn bounded_string(object: &Map<String, Value>, key: &'static str) -> Result<String, &'static str> {
    let value = object
        .get(key)
        .and_then(Value::as_str)
        .ok_or(MALFORMED_REQUEST)?;
    if value.is_empty() || value.len() > MAX_ID_BYTES {
        return Err(MALFORMED_REQUEST);
    }
    Ok(value.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::time::{Duration, UNIX_EPOCH};

    use qaptr_policy::ModelId;

    fn request() -> ConsentRequest {
        ConsentRequest::new(
            ProviderId::new("fixture-provider").expect("provider"),
            Some(ModelId::new("fixture-model").expect("model")),
            ProviderPayloadKind::Text,
            2,
            0,
            1,
        )
    }

    fn wait_for_consent(shared: &Arc<SharedState>) {
        for _ in 0..1000 {
            if shared.snapshot().phase == "ready_for_consent" {
                return;
            }
            thread::yield_now();
        }
        panic!("consent request did not become visible");
    }

    #[test]
    fn state_json_is_scalar_and_has_no_image_material() {
        let shared = SharedState::new();
        let value = shared.snapshot().to_json();
        assert_eq!(value["phase"], "idle");
        assert_eq!(value["image_count"], 0);
        assert!(value.get("image_bytes").is_none());
        assert!(value.to_string().find("base64").is_none());
    }

    #[test]
    fn consent_blocks_until_explicit_grant_then_allows_the_seam() {
        let shared = SharedState::new();
        let broker = ConsentBroker::new(shared.control.clone(), shared.clone());
        let invoked = Arc::new(AtomicUsize::new(0));
        let invoked_on_worker = invoked.clone();
        let join = thread::spawn(move || {
            let decision = ConsentPort::request(&broker, &request());
            if decision == ConsentDecision::Granted {
                invoked_on_worker.fetch_add(1, Ordering::AcqRel);
            }
            decision
        });
        wait_for_consent(&shared);
        assert_eq!(invoked.load(Ordering::Acquire), 0);
        assert!(shared.control.decide(PendingConsent::Granted, &shared));
        assert_eq!(
            join.join().expect("consent worker"),
            ConsentDecision::Granted
        );
        assert_eq!(invoked.load(Ordering::Acquire), 1);
    }

    #[test]
    fn consent_decline_never_opens_the_provider_seam() {
        let shared = SharedState::new();
        let broker = ConsentBroker::new(shared.control.clone(), shared.clone());
        let invoked = Arc::new(AtomicUsize::new(0));
        let invoked_on_worker = invoked.clone();
        let join = thread::spawn(move || {
            let decision = ConsentPort::request(&broker, &request());
            if decision == ConsentDecision::Granted {
                invoked_on_worker.fetch_add(1, Ordering::AcqRel);
            }
            decision
        });
        wait_for_consent(&shared);
        assert!(shared.control.decide(PendingConsent::Declined, &shared));
        assert_eq!(
            join.join().expect("consent worker"),
            ConsentDecision::Declined
        );
        assert_eq!(invoked.load(Ordering::Acquire), 0);
    }

    #[test]
    fn consent_cancel_unblocks_without_provider_dispatch() {
        let shared = SharedState::new();
        let broker = ConsentBroker::new(shared.control.clone(), shared.clone());
        let shared_for_worker = shared.clone();
        let join = thread::spawn(move || ConsentPort::request(&broker, &request()));
        wait_for_consent(&shared);
        shared_for_worker.cancel();
        assert_eq!(
            join.join().expect("consent worker"),
            ConsentDecision::Declined
        );
    }

    #[test]
    fn parser_rejects_unknown_fields_and_wrong_version() {
        assert_eq!(
            parse_operation(br#"{"version":1,"operation":"state","extra":1}"#),
            Err(MALFORMED_REQUEST)
        );
        assert_eq!(
            parse_operation(br#"{"version":2,"operation":"state"}"#),
            Err(MALFORMED_REQUEST)
        );
    }

    #[test]
    fn parser_accepts_all_v1_operations() {
        assert!(matches!(
            parse_operation(br#"{"version":1,"operation":"state"}"#),
            Ok(Operation::State)
        ));
        assert!(matches!(
            parse_operation(br#"{"version":1,"operation":"start","session_id":"s"}"#),
            Ok(Operation::Start { .. })
        ));
        assert!(matches!(
            parse_operation(br#"{"version":1,"operation":"decide_consent","decision":"grant"}"#),
            Ok(Operation::DecideConsent {
                decision: PendingConsent::Granted
            })
        ));
        assert!(matches!(
            parse_operation(br#"{"version":1,"operation":"cancel"}"#),
            Ok(Operation::Cancel)
        ));
        assert!(matches!(
            parse_operation(br#"{"version":1,"operation":"retry"}"#),
            Ok(Operation::Retry)
        ));
    }

    #[test]
    fn state_allowed_operations_are_phase_specific() {
        let mut state = DriverState::default();
        assert_eq!(state.allowed_operations(), vec!["state", "start"]);
        state.phase = "ready_for_consent";
        assert_eq!(
            state.allowed_operations(),
            vec!["state", "decide_consent", "cancel"]
        );
        state.phase = "failed";
        assert_eq!(state.allowed_operations(), vec!["state", "start", "retry"]);
    }

    #[test]
    fn consent_summary_is_scalar_and_contains_no_payload() {
        let shared = SharedState::new();
        shared.set_consent_summary(&request());
        let value = shared.snapshot().to_json();
        assert_eq!(value["consent_summary"]["provider"], "fixture-provider");
        assert_eq!(value["consent_summary"]["resolved_model"], "fixture-model");
        assert_eq!(value["consent_summary"]["payload_kind"], "text");
        assert!(value["consent_summary"].get("payload").is_none());
    }

    #[test]
    fn committed_capture_conversion_uses_vault_api_and_scalar_metadata() {
        let root = tempfile::tempdir().expect("temp root");
        let vault = Vault::new(root.path()).expect("vault");
        assert!(committed_captures(&vault).expect("list").is_empty());
        let _ =
            UnixMillis::from_system_time(UNIX_EPOCH + Duration::from_secs(1)).expect("timestamp");
    }

    fn wait_for_terminal_state(driver: &ReviewSessionDriver) -> Value {
        for _ in 0..1000 {
            let response = driver.request(br#"{"version":1,"operation":"state"}"#);
            let phase = response["state"]["phase"].as_str().unwrap_or_default();
            if matches!(phase, "completed" | "failed" | "cancelled") {
                return response;
            }
            thread::yield_now();
        }
        panic!("driver did not reach a terminal state");
    }

    #[test]
    fn driver_json_shape_is_versioned_and_scalar() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        );
        let response = driver.request(br#"{"version":1,"operation":"state"}"#);
        assert_eq!(response["version"], VERSION);
        assert_eq!(response["ok"], true);
        assert_eq!(response["state"]["phase"], "idle");
        assert!(response["state"]["consent_summary"].is_null());
        assert!(response["state"].get("image_bytes").is_none());
        assert!(response.to_string().find("provider_payload").is_none());
    }

    #[test]
    fn driver_reports_missing_committed_bundles_without_layout_scanning() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        );
        let started =
            driver.request(br#"{"version":1,"operation":"start","session_id":"missing-bundles"}"#);
        assert_eq!(started["ok"], true);
        let terminal = wait_for_terminal_state(&driver);
        assert_eq!(terminal["state"]["phase"], "failed");
        assert_eq!(terminal["state"]["error"], NO_BUNDLES);
        assert_eq!(terminal["state"]["captures_seen"], 0);
        assert!(terminal.to_string().find("bundles/").is_none());
    }

    #[test]
    fn driver_retry_after_missing_bundles_restarts_ingestion_and_fails_truthfully() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        );
        driver.request(br#"{"version":1,"operation":"start","session_id":"retryable"}"#);
        let first = wait_for_terminal_state(&driver);
        assert_eq!(first["state"]["phase"], "failed");
        let retried = driver.request(br#"{"version":1,"operation":"retry"}"#);
        assert_eq!(retried["ok"], true);
        let second = wait_for_terminal_state(&driver);
        assert_eq!(second["state"]["phase"], "failed");
        assert_eq!(second["state"]["error"], NO_BUNDLES);
    }

    #[test]
    fn driver_rejects_cancel_and_consent_when_not_allowed() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        );
        let cancel = driver.request(br#"{"version":1,"operation":"cancel"}"#);
        assert_eq!(cancel["ok"], false);
        assert_eq!(cancel["error"], OPERATION_ERROR);
        let consent =
            driver.request(br#"{"version":1,"operation":"decide_consent","decision":"grant"}"#);
        assert_eq!(consent["ok"], false);
        assert_eq!(consent["error"], OPERATION_ERROR);
    }
}
