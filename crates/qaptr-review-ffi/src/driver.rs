//! App-owned review-session driver for the scalar JSON v1 C ABI.
//!
//! The worker owns the vault, store, local privacy pipeline, and lifecycle
//! coordinator. The C ABI owns only bounded JSON requests and scalar state.
//! Provider construction is deliberately conservative in this first slice:
//! no configured provider is selected, so a production session reports a
//! truthful unavailable result and never reaches consent or provider dispatch.

use std::path::PathBuf;
#[cfg(test)]
use std::sync::Barrier;
use std::sync::{
    Arc, Condvar, Mutex,
    atomic::{AtomicBool, Ordering},
    mpsc::{self, Receiver, Sender},
};
use std::thread;
use std::time::Duration;

use qaptr_domain::{Duration as DomainDuration, SessionId, SystemClock};
use qaptr_macos::{MacCredentials, MacOcr, MacVision};
use qaptr_policy::RetentionPolicy;
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
    ConsentRequest, ProviderOutcome, ReviewProgress, ReviewSessionCoordinator, SessionCancellation,
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
const MUTATION_REPLAY_CAPACITY: &str = "mutation_replay_capacity";
const MUTATION_REPLAY_IN_PROGRESS: &str = "mutation_replay_in_progress";
const MUTATION_TOKEN_REQUIRED: &str = "mutation_token_required";
const MUTATION_TOKEN_REUSED: &str = "mutation_token_reused";
const MAX_PENDING_MUTATIONS: usize = 64;
const PRODUCTION_RETENTION: RetentionPolicy =
    RetentionPolicy::new(DomainDuration::from_secs(24 * 60 * 60));

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
    /// The resolved model identifier, or the honest
    /// [`qaptr_workflow::PROVIDER_DEFAULT_MODEL_LABEL`] when the provider's
    /// own documented default model will be used instead. Never blank.
    model_label: String,
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
    /// The provider that produced the terminal result, when analysis actually
    /// invoked one. This is scalar result metadata for the same provider
    /// verified and used for the request; it is never inferred or guessed.
    result_provider: Option<String>,
    /// The resolved model identifier for the terminal result, or the honest
    /// [`qaptr_workflow::PROVIDER_DEFAULT_MODEL_LABEL`] when the provider
    /// used its own documented default model. `None` only when no provider
    /// was invoked at all.
    result_model_label: Option<String>,
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
            result_provider: None,
            result_model_label: None,
        }
    }
}

impl DriverState {
    fn retry_requires_reprocessing(&self) -> bool {
        matches!(self.phase, "failed" | "cancelled")
            || (self.phase == "completed" && self.outcome == Some("consent_declined"))
    }

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
                "model_label": summary.model_label,
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
            "result_provider": self.result_provider,
            "result_model_label": self.result_model_label,
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
        let mut decision = self
            .decision
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        *decision = Some(PendingConsent::Waiting);
        // Install the pending decision before publishing ready_for_consent.
        // Otherwise a fast caller can observe the state transition and race
        // decide_consent before there is anything for it to decide.
        shared.set_consent_summary(request);
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
        if decision == PendingConsent::Granted {
            let mut state = shared
                .state
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            if state.phase != "ready_for_consent" {
                return false;
            }
            state.phase = "analyzing";
        }
        *pending = Some(decision);
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

    fn begin_if_allowed(&self, session_id: &SessionId) -> bool {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if !state.allowed_operations().contains(&"start") {
            return false;
        }
        self.control.reset();
        self.cancel_requested.store(false, Ordering::Release);
        *state = DriverState {
            session_id: Some(session_id.as_str().to_owned()),
            phase: "ingesting",
            ..DriverState::default()
        };
        true
    }

    fn begin_retry_if_allowed(&self) -> bool {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if !state.allowed_operations().contains(&"retry") {
            return false;
        }
        let Some(session_id) = state
            .session_id
            .as_deref()
            .and_then(|value| SessionId::new(value.to_owned()).ok())
        else {
            return false;
        };
        self.control.reset();
        self.cancel_requested.store(false, Ordering::Release);
        *state = DriverState {
            session_id: Some(session_id.as_str().to_owned()),
            phase: "ingesting",
            ..DriverState::default()
        };
        true
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

    fn cancel_if_allowed(&self) -> bool {
        let allowed = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .allowed_operations()
            .contains(&"cancel");
        if allowed {
            self.cancel();
        }
        allowed
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
            model_label: request.model_label(),
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
                        model_label: qaptr_workflow::PROVIDER_DEFAULT_MODEL_LABEL.to_owned(),
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
            ProviderOutcome::Completed {
                provider,
                resolved_model,
            } => {
                state.phase = "completed";
                state.result = Some("analysis_completed");
                state.outcome = Some("provider_completed");
                state.result_provider = Some(provider.as_str().to_owned());
                state.result_model_label =
                    Some(qaptr_workflow::model_label(resolved_model.as_ref()));
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
            ProviderOutcome::Failed {
                provider,
                resolved_model,
                ..
            } => {
                state.phase = "failed";
                state.outcome = Some(PROVIDER_FAILED);
                state.error = Some(PROVIDER_FAILED);
                state.result_provider = Some(provider.as_str().to_owned());
                state.result_model_label =
                    Some(qaptr_workflow::model_label(resolved_model.as_ref()));
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
        reprocess: bool,
    },
    Shutdown,
}

type ListingHook = Arc<dyn Fn(&SessionCancellation) + Send + Sync>;

struct PendingMutation {
    request_token: u64,
    input: Vec<u8>,
    response: Option<Value>,
}

/// App-owned review session handle backing the scalar JSON ABI.
pub struct ReviewSessionDriver {
    shared: Arc<SharedState>,
    commands: Sender<WorkerCommand>,
    worker: Mutex<Option<thread::JoinHandle<()>>>,
    pending_mutations: Mutex<Vec<PendingMutation>>,
    #[cfg(test)]
    executed_mutations: std::sync::atomic::AtomicUsize,
}

impl ReviewSessionDriver {
    /// Creates a driver whose worker owns the vault and history store.
    pub(crate) fn new(vault_root: PathBuf, store_path: PathBuf) -> Self {
        Self::new_with_listing_hook(vault_root, store_path, None)
    }

    fn new_with_listing_hook(
        vault_root: PathBuf,
        store_path: PathBuf,
        listing_hook: Option<ListingHook>,
    ) -> Self {
        Self::new_with_hooks(vault_root, store_path, None, listing_hook)
    }

    fn new_with_hooks(
        vault_root: PathBuf,
        store_path: PathBuf,
        acknowledgement_hook: Option<ListingHook>,
        listing_hook: Option<ListingHook>,
    ) -> Self {
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
                acknowledgement_hook,
                listing_hook,
            );
        });
        Self {
            shared,
            commands,
            worker: Mutex::new(Some(worker)),
            pending_mutations: Mutex::new(Vec::new()),
            #[cfg(test)]
            executed_mutations: std::sync::atomic::AtomicUsize::new(0),
        }
    }

    #[cfg(test)]
    fn new_with_listing_barrier(
        vault_root: PathBuf,
        store_path: PathBuf,
        entered: Arc<Barrier>,
        release: Arc<AtomicBool>,
    ) -> Self {
        let hook: ListingHook = Arc::new(move |cancellation| {
            entered.wait();
            while !release.load(Ordering::Acquire) && !cancellation.is_requested() {
                thread::yield_now();
            }
        });
        Self::new_with_listing_hook(vault_root, store_path, Some(hook))
    }

    #[cfg(test)]
    fn new_with_acknowledgement_barrier(
        vault_root: PathBuf,
        store_path: PathBuf,
        entered: Arc<Barrier>,
        release: Arc<AtomicBool>,
    ) -> Self {
        let hook: ListingHook = Arc::new(move |_cancellation| {
            entered.wait();
            while !release.load(Ordering::Acquire) {
                thread::yield_now();
            }
        });
        Self::new_with_hooks(vault_root, store_path, Some(hook), None)
    }

    /// Dispatches one bounded JSON v1 request and returns a scalar JSON result.
    #[cfg(test)]
    pub(crate) fn request(&self, input: &[u8]) -> Value {
        if input.len() > MAX_REQUEST_BYTES {
            return self.response(Some(MALFORMED_REQUEST));
        }
        let operation = match parse_operation(input) {
            Ok(operation) => operation,
            Err(error) => return self.response(Some(error)),
        };
        self.execute(operation)
    }

    /// Executes a request once for the C ABI's two-pass output contract.
    ///
    /// Mutating requests are replayed by an explicit caller-owned token. The
    /// token must remain stable across the size and output passes, so those
    /// passes may migrate across threads without cross-delivery. Abandoned
    /// entries are bounded by [`MAX_PENDING_MUTATIONS`].
    pub(crate) fn request_once(&self, request_token: u64, input: &[u8]) -> Value {
        if input.len() > MAX_REQUEST_BYTES {
            return self.response(Some(MALFORMED_REQUEST));
        }
        let operation = match parse_operation(input) {
            Ok(operation) => operation,
            Err(error) => return self.response(Some(error)),
        };
        if !operation.is_mutating() {
            return self.execute(operation);
        }
        if request_token == 0 {
            return self.response(Some(MUTATION_TOKEN_REQUIRED));
        }
        let mut pending = self
            .pending_mutations
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if let Some(previous) = pending
            .iter()
            .find(|entry| entry.request_token == request_token)
        {
            if previous.input.as_slice() != input {
                return self.response(Some(MUTATION_TOKEN_REUSED));
            }
            return previous
                .response
                .clone()
                .unwrap_or_else(|| self.response(Some(MUTATION_REPLAY_IN_PROGRESS)));
        }
        if pending.len() >= MAX_PENDING_MUTATIONS {
            return self.response(Some(MUTATION_REPLAY_CAPACITY));
        }
        pending.push(PendingMutation {
            request_token,
            input: input.to_vec(),
            response: None,
        });
        drop(pending);

        #[cfg(test)]
        self.executed_mutations.fetch_add(1, Ordering::AcqRel);
        let response = self.execute(operation);
        let mut pending = self
            .pending_mutations
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if let Some(entry) = pending
            .iter_mut()
            .find(|entry| entry.request_token == request_token && entry.input.as_slice() == input)
        {
            entry.response = Some(response.clone());
        }
        response
    }

    /// Marks a pending mutating request delivered once its caller supplied a
    /// writable buffer large enough for the complete response.
    pub(crate) fn finish_pending_mutation(&self, request_token: u64, input: &[u8]) {
        let mut pending = self
            .pending_mutations
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if let Some(index) = pending.iter().position(|entry| {
            entry.request_token == request_token
                && entry.input.as_slice() == input
                && entry.response.is_some()
        }) {
            pending.remove(index);
        }
    }

    #[cfg(test)]
    fn executed_mutations(&self) -> usize {
        self.executed_mutations.load(Ordering::Acquire)
    }

    #[cfg(test)]
    fn pending_mutation_count(&self) -> usize {
        self.pending_mutations
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .len()
    }

    fn execute(&self, operation: Operation) -> Value {
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
                if !self.shared.cancel_if_allowed() {
                    return self.response(Some(OPERATION_ERROR));
                }
                self.response(None)
            }
            Operation::Retry => {
                let reprocess = self.shared.snapshot().retry_requires_reprocessing();
                if !self.shared.begin_retry_if_allowed() {
                    return self.response(Some(OPERATION_ERROR));
                }
                let (acknowledged, receiver) = mpsc::channel();
                if self
                    .commands
                    .send(WorkerCommand::Retry {
                        acknowledged,
                        reprocess,
                    })
                    .is_err()
                    || receiver.recv_timeout(Duration::from_secs(2)).is_err()
                {
                    self.shared.fail(SESSION_UNAVAILABLE);
                }
                self.response(None)
            }
            Operation::DecideConsent { decision } => {
                if !self.shared.control.decide(decision, &self.shared) {
                    return self.response(Some(OPERATION_ERROR));
                }
                self.response(None)
            }
        }
    }

    fn start(&self, session_id: SessionId) -> bool {
        if !self.shared.begin_if_allowed(&session_id) {
            return false;
        }
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
        if let Some(worker) = self
            .worker
            .get_mut()
            .unwrap_or_else(|poison| poison.into_inner())
            .take()
        {
            let _ = worker.join();
        }
    }
}

fn worker_loop(
    vault_root: PathBuf,
    store_path: PathBuf,
    receiver: Receiver<WorkerCommand>,
    shared: Arc<SharedState>,
    control: Arc<ConsentControl>,
    acknowledgement_hook: Option<ListingHook>,
    listing_hook: Option<ListingHook>,
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
                last_session = Some(session_id.clone());
                let cancellation = SessionCancellation::new();
                if shared.cancel_requested.load(Ordering::Acquire) {
                    cancellation.cancel();
                }
                shared.set_active_cancellation(Some(cancellation.clone()));
                if let Some(acknowledgement_hook) = acknowledgement_hook.as_ref() {
                    acknowledgement_hook(&cancellation);
                }
                let _ = acknowledged.send(());
                let Some(resources) = resources.as_mut() else {
                    shared.set_active_cancellation(None);
                    shared.fail(SESSION_UNAVAILABLE);
                    continue;
                };
                let captures = match committed_captures(
                    &resources.vault,
                    &cancellation,
                    listing_hook.as_ref(),
                ) {
                    Ok(captures) if captures.is_empty() => {
                        shared.set_active_cancellation(None);
                        shared.fail(NO_BUNDLES);
                        continue;
                    }
                    Ok(captures) => captures,
                    Err(()) => {
                        shared.set_active_cancellation(None);
                        shared.fail(SESSION_UNAVAILABLE);
                        continue;
                    }
                };
                last_captures = Some(captures.clone());
                run_attempt(
                    resources,
                    &shared,
                    session_id,
                    &captures,
                    cancellation,
                    false,
                );
            }
            WorkerCommand::Retry {
                acknowledged,
                reprocess,
            } => {
                let (Some(resources), Some(session_id)) =
                    (resources.as_mut(), last_session.clone())
                else {
                    let _ = acknowledged.send(());
                    shared.fail(RETRY_UNAVAILABLE);
                    continue;
                };
                let cancellation = SessionCancellation::new();
                if shared.cancel_requested.load(Ordering::Acquire) {
                    cancellation.cancel();
                }
                shared.set_active_cancellation(Some(cancellation.clone()));
                if let Some(acknowledgement_hook) = acknowledgement_hook.as_ref() {
                    acknowledgement_hook(&cancellation);
                }
                let _ = acknowledged.send(());
                let captures = match last_captures.clone() {
                    Some(captures) => captures,
                    None => match committed_captures(
                        &resources.vault,
                        &cancellation,
                        listing_hook.as_ref(),
                    ) {
                        Ok(captures) => captures,
                        Err(()) => {
                            shared.set_active_cancellation(None);
                            shared.fail(SESSION_UNAVAILABLE);
                            continue;
                        }
                    },
                };
                if captures.is_empty() {
                    shared.set_active_cancellation(None);
                    shared.fail(NO_BUNDLES);
                    continue;
                }
                last_captures = Some(captures.clone());
                run_attempt(
                    resources,
                    &shared,
                    session_id,
                    &captures,
                    cancellation,
                    reprocess,
                );
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
    cancellation: SessionCancellation,
    reprocess: bool,
) {
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
    let mut coordinator = ReviewSessionCoordinator::with_cancellation(
        &runner,
        &resources.vault,
        &resources.credentials,
        &resources.store,
        &resources.clock,
        cancellation,
    )
    .with_retention_policy(PRODUCTION_RETENTION);
    let result = if reprocess {
        coordinator.retry_with_captures(session_id, captures, |progress| {
            shared.apply_progress(progress)
        })
    } else {
        coordinator.start(session_id, captures, |progress| {
            shared.apply_progress(progress)
        })
    };
    shared.set_active_cancellation(None);
    match result {
        Ok(report) => shared.finish_report(&report),
        Err(_) => shared.fail(LOCAL_REVIEW_FAILED),
    }
}

fn committed_captures(
    vault: &Vault,
    cancellation: &SessionCancellation,
    listing_hook: Option<&ListingHook>,
) -> Result<Vec<CaptureRecordInput>, ()> {
    let metadata = vault.list_committed_bundles().map_err(|_| ())?;
    if let Some(listing_hook) = listing_hook {
        listing_hook(cancellation);
    }
    metadata
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

impl Operation {
    fn is_mutating(&self) -> bool {
        matches!(
            self,
            Self::Start { .. } | Self::DecideConsent { .. } | Self::Cancel | Self::Retry
        )
    }
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
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Arc, Barrier};
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    use qaptr_policy::ModelId;
    use qaptr_vault::{BundleInput, GenerationId, GenerationKeypair, SampledContext};

    fn seed_committed_bundle(vault_root: &std::path::Path) {
        let vault = Vault::new(vault_root).expect("vault");
        let keypair =
            GenerationKeypair::generate(GenerationId::new("generation-1").expect("generation id"));
        let captured_at = SystemTime::now();
        vault
            .seal(
                &BundleInput::new(
                    qaptr_domain::CaptureId::new("capture-1").expect("capture id"),
                    keypair.generation_id().clone(),
                    captured_at,
                    b"encrypted image input".to_vec(),
                    SampledContext::new(br#"{"application":"Test"}"#.to_vec()),
                    Vec::new(),
                ),
                keypair.public_key(),
            )
            .expect("seal bundle");
    }

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

    #[derive(Debug)]
    struct TwoPassResult {
        first_required: usize,
        final_required: usize,
        response: Option<Value>,
    }

    fn abi_size_pass(handle: usize, request_token: u64, request: &'static [u8]) -> usize {
        // SAFETY: the test keeps the boxed driver alive until all worker threads
        // have joined, and the request is a static byte slice.
        unsafe {
            crate::qaptr_review_session_json(
                handle as *mut ReviewSessionDriver,
                request_token,
                request.as_ptr(),
                request.len(),
                std::ptr::null_mut(),
                0,
            )
        }
    }

    fn abi_final_pass(
        handle: usize,
        request_token: u64,
        request: &'static [u8],
        required: usize,
    ) -> TwoPassResult {
        let mut output = vec![0_u8; required];
        // SAFETY: the test keeps the boxed driver alive until all worker threads
        // have joined, and `output` has exactly the requested capacity.
        let final_required = unsafe {
            crate::qaptr_review_session_json(
                handle as *mut ReviewSessionDriver,
                request_token,
                request.as_ptr(),
                request.len(),
                output.as_mut_ptr(),
                output.len(),
            )
        };
        let response = (final_required <= output.len())
            .then(|| serde_json::from_slice(&output[..final_required - 1]).expect("response JSON"));
        TwoPassResult {
            first_required: required,
            final_required,
            response,
        }
    }

    fn interleave_identical_two_passes(
        handle: usize,
        first_token: u64,
        second_token: u64,
        request: &'static [u8],
        before_second_first_pass: impl FnOnce(),
        after_second_first_pass: impl FnOnce(),
    ) -> (TwoPassResult, TwoPassResult) {
        let (first_ready, first_ready_rx) = mpsc::channel();
        let (first_release, first_release_rx) = mpsc::channel();
        let (first_done, first_done_rx) = mpsc::channel();
        let first_thread = thread::spawn(move || {
            let required = abi_size_pass(handle, first_token, request);
            first_ready.send(required).expect("first size pass");
            first_release_rx.recv().expect("first release");
            first_done
                .send(abi_final_pass(handle, first_token, request, required))
                .expect("first final pass");
        });
        let first_required = first_ready_rx.recv().expect("first caller ready");

        before_second_first_pass();

        let (second_ready, second_ready_rx) = mpsc::channel();
        let (second_release, second_release_rx) = mpsc::channel();
        let second_thread = thread::spawn(move || {
            let required = abi_size_pass(handle, second_token, request);
            second_ready.send(required).expect("second size pass");
            second_release_rx.recv().expect("second release");
            abi_final_pass(handle, second_token, request, required)
        });
        let second_required = second_ready_rx.recv().expect("second caller ready");

        after_second_first_pass();
        first_release.send(()).expect("release first caller");
        let first_result = first_done_rx.recv().expect("first final result");
        second_release.send(()).expect("release second caller");
        let second_result = second_thread.join().expect("second caller");
        first_thread.join().expect("first caller");

        assert_eq!(first_result.first_required, first_required);
        assert_eq!(second_result.first_required, second_required);
        (first_result, second_result)
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
    fn immediate_grant_after_ready_state_is_not_lost() {
        let shared = SharedState::new();
        let broker = ConsentBroker::new(shared.control.clone(), shared.clone());
        let shared_for_decider = shared.clone();
        let control_for_decider = shared.control.clone();
        let decider = thread::spawn(move || {
            for _ in 0..1000 {
                if shared_for_decider.snapshot().phase == "ready_for_consent" {
                    return control_for_decider
                        .decide(PendingConsent::Granted, &shared_for_decider);
                }
                thread::yield_now();
            }
            false
        });
        let worker = thread::spawn(move || ConsentPort::request(&broker, &request()));
        assert!(decider.join().expect("consent decider"));
        assert_eq!(
            worker.join().expect("consent worker"),
            ConsentDecision::Granted
        );
    }

    #[test]
    fn invalid_start_and_retry_preserve_pending_consent() {
        let shared = SharedState::new();
        let broker = ConsentBroker::new(shared.control.clone(), shared.clone());
        let worker = thread::spawn(move || ConsentPort::request(&broker, &request()));
        wait_for_consent(&shared);

        assert!(!shared.begin_if_allowed(&SessionId::new("invalid-start").expect("session")));
        assert!(!shared.begin_retry_if_allowed());
        assert!(shared.control.decide(PendingConsent::Granted, &shared));
        assert_eq!(
            worker.join().expect("consent worker"),
            ConsentDecision::Granted
        );
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
    fn retry_reprocessing_is_limited_to_incomplete_work() {
        let mut state = DriverState {
            phase: "failed",
            ..DriverState::default()
        };
        assert!(state.retry_requires_reprocessing());

        state.phase = "completed";
        state.outcome = Some("consent_declined");
        assert!(state.retry_requires_reprocessing());

        state.outcome = Some("provider_completed");
        assert!(!state.retry_requires_reprocessing());
    }

    #[test]
    fn consent_summary_is_scalar_and_contains_no_payload() {
        let shared = SharedState::new();
        shared.set_consent_summary(&request());
        let value = shared.snapshot().to_json();
        assert_eq!(value["consent_summary"]["provider"], "fixture-provider");
        assert_eq!(value["consent_summary"]["resolved_model"], "fixture-model");
        assert_eq!(value["consent_summary"]["model_label"], "fixture-model");
        assert_eq!(value["consent_summary"]["payload_kind"], "text");
        assert!(value["consent_summary"].get("payload").is_none());
    }

    #[test]
    fn consent_summary_model_label_is_an_honest_provider_default_without_a_resolved_model() {
        let shared = SharedState::new();
        let cli_request = ConsentRequest::new(
            ProviderId::new("codex-cli").expect("provider"),
            None,
            ProviderPayloadKind::Text,
            1,
            0,
            0,
        );
        shared.set_consent_summary(&cli_request);
        let value = shared.snapshot().to_json();
        assert!(value["consent_summary"]["resolved_model"].is_null());
        assert_eq!(
            value["consent_summary"]["model_label"],
            qaptr_workflow::PROVIDER_DEFAULT_MODEL_LABEL
        );
    }

    #[test]
    fn finish_report_records_resolved_provider_and_model_label_as_scalar_result_metadata() {
        use qaptr_provider::RuntimeFailureKind;

        let shared = SharedState::new();
        let completed = AnalysisReport {
            session_id: SessionId::new("result-metadata-completed").expect("session"),
            captures_seen: 1,
            prepared_captures: 1,
            excluded_captures: 0,
            observations_written: 1,
            exclusion_notice: None,
            provider: ProviderOutcome::Completed {
                provider: ProviderId::new("openrouter").expect("provider"),
                resolved_model: Some(ModelId::new("gpt-test").expect("model")),
            },
        };
        shared.finish_report(&completed);
        let value = shared.snapshot().to_json();
        assert_eq!(value["result_provider"], "openrouter");
        assert_eq!(value["result_model_label"], "gpt-test");

        let failed = AnalysisReport {
            session_id: SessionId::new("result-metadata-failed").expect("session"),
            captures_seen: 1,
            prepared_captures: 1,
            excluded_captures: 0,
            observations_written: 0,
            exclusion_notice: None,
            provider: ProviderOutcome::Failed {
                provider: ProviderId::new("codex-cli").expect("provider"),
                resolved_model: None,
                error: ProviderError::RuntimeFailure {
                    provider: ProviderId::new("codex-cli").expect("provider"),
                    kind: RuntimeFailureKind::Invocation,
                },
            },
        };
        shared.finish_report(&failed);
        let after_failure = shared.snapshot().to_json();
        assert_eq!(after_failure["result_provider"], "codex-cli");
        assert_eq!(
            after_failure["result_model_label"],
            qaptr_workflow::PROVIDER_DEFAULT_MODEL_LABEL
        );
    }

    #[test]
    fn committed_capture_conversion_uses_vault_api_and_scalar_metadata() {
        let root = tempfile::tempdir().expect("temp root");
        let vault = Vault::new(root.path()).expect("vault");
        let cancellation = SessionCancellation::new();
        assert!(
            committed_captures(&vault, &cancellation, None)
                .expect("list")
                .is_empty()
        );
        let _ =
            UnixMillis::from_system_time(UNIX_EPOCH + Duration::from_secs(1)).expect("timestamp");
    }

    #[test]
    fn review_session_json_two_pass_does_not_repeat_mutation() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = Box::new(ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        ));
        let handle = Box::into_raw(driver);
        let request = br#"{"version":1,"operation":"start","session_id":"two-pass"}"#;

        let required = unsafe {
            crate::qaptr_review_session_json(
                handle,
                1,
                request.as_ptr(),
                request.len(),
                std::ptr::null_mut(),
                0,
            )
        };
        assert!(required > 1);
        let mut undersized = vec![0_u8; required - 1];
        let retry_required = unsafe {
            crate::qaptr_review_session_json(
                handle,
                1,
                request.as_ptr(),
                request.len(),
                undersized.as_mut_ptr(),
                undersized.len(),
            )
        };
        assert_eq!(retry_required, required);
        let mut output = vec![0_u8; required];
        let final_required = unsafe {
            crate::qaptr_review_session_json(
                handle,
                1,
                request.as_ptr(),
                request.len(),
                output.as_mut_ptr(),
                output.len(),
            )
        };
        assert_eq!(final_required, required);
        assert_eq!(unsafe { &*handle }.executed_mutations(), 1);
        unsafe { crate::qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn tokenized_two_pass_survives_thread_migration() {
        let root = tempfile::tempdir().expect("temp root");
        let handle = Box::into_raw(Box::new(ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        )));
        let request = br#"{"version":1,"operation":"start","session_id":"migrated"}"#;
        let handle_value = handle as usize;
        let size_thread = thread::spawn(move || abi_size_pass(handle_value, 61, request));
        let required = size_thread.join().expect("size pass");
        let final_thread =
            thread::spawn(move || abi_final_pass(handle_value, 61, request, required));
        let result = final_thread.join().expect("output pass");

        assert_eq!(result.final_required, required);
        assert_eq!(result.response.expect("response")["version"], VERSION);
        assert_eq!(unsafe { &*handle }.executed_mutations(), 1);
        assert_eq!(unsafe { &*handle }.pending_mutation_count(), 0);
        unsafe { crate::qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn abandoned_size_passes_are_bounded_and_tokens_cannot_be_reused() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        );
        let request = br#"{"version":1,"operation":"start","session_id":"abandoned"}"#;
        for token in 1..=MAX_PENDING_MUTATIONS as u64 {
            let response = driver.request_once(token, request);
            assert_ne!(response["error"], MUTATION_REPLAY_CAPACITY);
        }
        assert_eq!(driver.pending_mutation_count(), MAX_PENDING_MUTATIONS);
        assert_eq!(
            driver.request_once(MAX_PENDING_MUTATIONS as u64 + 1, request)["error"],
            MUTATION_REPLAY_CAPACITY
        );
        assert_eq!(driver.pending_mutation_count(), MAX_PENDING_MUTATIONS);

        let different_request = br#"{"version":1,"operation":"cancel"}"#;
        assert_eq!(
            driver.request_once(1, different_request)["error"],
            MUTATION_TOKEN_REUSED
        );
    }

    #[test]
    fn identical_interleaved_start_passes_keep_each_callers_response() {
        let root = tempfile::tempdir().expect("temp root");
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        let handle = Box::into_raw(Box::new(ReviewSessionDriver::new_with_listing_barrier(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
            entered.clone(),
            release.clone(),
        )));
        let request = br#"{"version":1,"operation":"start","session_id":"same-start"}"#;
        let (first, second) = interleave_identical_two_passes(
            handle as usize,
            11,
            12,
            request,
            || {
                entered.wait();
            },
            || release.store(true, Ordering::Release),
        );

        assert_eq!(first.final_required, first.first_required);
        assert_eq!(second.final_required, second.first_required);
        assert_eq!(first.response.as_ref().expect("first response")["ok"], true);
        assert_eq!(
            second.response.as_ref().expect("second response")["error"],
            SESSION_BUSY
        );
        // The listing worker is released before destruction so Drop can join it.
        release.store(true, Ordering::Release);
        // SAFETY: all C ABI calls have completed and the pointer came from
        // Box::into_raw above.
        unsafe { crate::qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn identical_interleaved_retry_passes_do_not_cross_replay_slots() {
        let root = tempfile::tempdir().expect("temp root");
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        let handle = Box::into_raw(Box::new(ReviewSessionDriver::new_with_listing_barrier(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
            entered.clone(),
            release.clone(),
        )));
        let driver = unsafe { &*handle };
        assert_eq!(
            driver.request(br#"{"version":1,"operation":"start","session_id":"retry"}"#)["ok"],
            true
        );
        entered.wait();
        release.store(true, Ordering::Release);
        assert_eq!(wait_for_terminal_state(driver)["state"]["phase"], "failed");
        release.store(false, Ordering::Release);

        let request = br#"{"version":1,"operation":"retry"}"#;
        let (first, second) = interleave_identical_two_passes(
            handle as usize,
            21,
            22,
            request,
            || {
                entered.wait();
            },
            || release.store(true, Ordering::Release),
        );
        assert_eq!(first.final_required, first.first_required);
        assert_eq!(second.final_required, second.first_required);
        assert_eq!(first.response.as_ref().expect("first response")["ok"], true);
        assert_eq!(
            second.response.as_ref().expect("second response")["error"],
            OPERATION_ERROR
        );
        release.store(true, Ordering::Release);
        // SAFETY: all C ABI calls have completed and the pointer came from
        // Box::into_raw above.
        unsafe { crate::qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn identical_interleaved_cancel_passes_keep_terminal_rejection_owned() {
        let root = tempfile::tempdir().expect("temp root");
        seed_committed_bundle(&root.path().join("vault"));
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        let handle = Box::into_raw(Box::new(ReviewSessionDriver::new_with_listing_barrier(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
            entered.clone(),
            release.clone(),
        )));
        let driver = unsafe { &*handle };
        assert_eq!(
            driver.request(br#"{"version":1,"operation":"start","session_id":"cancel"}"#)["ok"],
            true
        );
        entered.wait();

        let request = br#"{"version":1,"operation":"cancel"}"#;
        let (first, second) = interleave_identical_two_passes(
            handle as usize,
            31,
            32,
            request,
            || {
                release.store(true, Ordering::Release);
                assert_eq!(
                    wait_for_terminal_state(driver)["state"]["phase"],
                    "cancelled"
                );
            },
            || {},
        );
        assert_eq!(first.final_required, first.first_required);
        assert_eq!(second.final_required, second.first_required);
        assert_eq!(first.response.as_ref().expect("first response")["ok"], true);
        assert_eq!(
            second.response.as_ref().expect("second response")["error"],
            OPERATION_ERROR
        );
        // SAFETY: all C ABI calls have completed and the pointer came from
        // Box::into_raw above.
        unsafe { crate::qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn identical_interleaved_consent_passes_keep_grant_and_rejection_separate() {
        let root = tempfile::tempdir().expect("temp root");
        let handle = Box::into_raw(Box::new(ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        )));
        let driver = unsafe { &*handle };
        {
            let mut state = driver
                .shared
                .state
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            state.phase = "ready_for_consent";
        }
        *driver
            .shared
            .control
            .decision
            .lock()
            .unwrap_or_else(|poison| poison.into_inner()) = Some(PendingConsent::Waiting);

        let request = br#"{"version":1,"operation":"decide_consent","decision":"grant"}"#;
        let (first, second) =
            interleave_identical_two_passes(handle as usize, 41, 42, request, || {}, || {});
        assert_eq!(first.final_required, first.first_required);
        assert_eq!(second.final_required, second.first_required);
        assert_eq!(first.response.as_ref().expect("first response")["ok"], true);
        assert_eq!(
            second.response.as_ref().expect("second response")["error"],
            OPERATION_ERROR
        );
        // SAFETY: all C ABI calls have completed and the pointer came from
        // Box::into_raw above.
        unsafe { crate::qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn interleaved_distinct_two_pass_mutations_keep_each_response() {
        let root = tempfile::tempdir().expect("temp root");
        let driver = Arc::new(ReviewSessionDriver::new(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
        ));
        let first = br#"{"version":1,"operation":"start","session_id":"first"}"#;
        let second = br#"{"version":1,"operation":"cancel"}"#;
        let callers = Arc::new(Barrier::new(3));
        let first_driver = driver.clone();
        let first_callers = callers.clone();
        let first_thread = thread::spawn(move || {
            first_callers.wait();
            let response = first_driver.request_once(51, first);
            first_driver.finish_pending_mutation(51, first);
            response
        });
        let second_driver = driver.clone();
        let second_callers = callers.clone();
        let second_thread = thread::spawn(move || {
            second_callers.wait();
            let response = second_driver.request_once(52, second);
            second_driver.finish_pending_mutation(52, second);
            response
        });
        callers.wait();

        let first_response = first_thread.join().expect("first mutation");
        let second_response = second_thread.join().expect("second mutation");
        assert_eq!(driver.executed_mutations(), 2);
        assert_eq!(first_response["version"], VERSION);
        assert_eq!(second_response["version"], VERSION);
    }

    #[test]
    fn concurrent_starts_have_one_atomic_winner() {
        let root = tempfile::tempdir().expect("temp root");
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        let driver = Arc::new(ReviewSessionDriver::new_with_listing_barrier(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
            entered.clone(),
            release.clone(),
        ));
        seed_committed_bundle(&root.path().join("vault"));
        let start_barrier = Arc::new(Barrier::new(3));
        let first = {
            let driver = driver.clone();
            let start_barrier = start_barrier.clone();
            std::thread::spawn(move || {
                start_barrier.wait();
                driver.request(br#"{"version":1,"operation":"start","session_id":"one"}"#)
            })
        };
        let second = {
            let driver = driver.clone();
            let start_barrier = start_barrier.clone();
            std::thread::spawn(move || {
                start_barrier.wait();
                driver.request(br#"{"version":1,"operation":"start","session_id":"two"}"#)
            })
        };
        start_barrier.wait();
        let first_response = first.join().expect("first start");
        let second_response = second.join().expect("second start");
        entered.wait();
        release.store(true, Ordering::Release);
        let responses = [first_response, second_response];
        let ok_count = responses
            .iter()
            .filter(|response| response["ok"] == true)
            .count();
        assert_eq!(ok_count, 1);
        assert_eq!(
            responses
                .iter()
                .filter(|response| response["error"] == SESSION_BUSY)
                .count(),
            1
        );
    }

    #[test]
    fn cancellation_during_listing_reaches_coordinator_before_decode() {
        let root = tempfile::tempdir().expect("temp root");
        seed_committed_bundle(&root.path().join("vault"));
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        let driver = ReviewSessionDriver::new_with_listing_barrier(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
            entered.clone(),
            release,
        );
        let started =
            driver.request(br#"{"version":1,"operation":"start","session_id":"listing-cancel"}"#);
        assert_eq!(started["ok"], true);
        entered.wait();
        let cancelled = driver.request(br#"{"version":1,"operation":"cancel"}"#);
        assert_eq!(cancelled["ok"], true);
        let terminal = wait_for_terminal_state(&driver);
        assert_eq!(terminal["state"]["phase"], "cancelled");
    }

    #[test]
    fn cancellation_before_start_ack_reaches_worker_preparation() {
        let root = tempfile::tempdir().expect("temp root");
        seed_committed_bundle(&root.path().join("vault"));
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        let driver = Arc::new(ReviewSessionDriver::new_with_acknowledgement_barrier(
            root.path().join("vault"),
            root.path().join("history.sqlite3"),
            entered.clone(),
            release.clone(),
        ));
        let starting = {
            let driver = driver.clone();
            thread::spawn(move || {
                driver.request(br#"{"version":1,"operation":"start","session_id":"ack-cancel"}"#)
            })
        };

        entered.wait();
        let cancelled = driver.request(br#"{"version":1,"operation":"cancel"}"#);
        assert_eq!(cancelled["ok"], true);
        release.store(true, Ordering::Release);
        assert_eq!(starting.join().expect("start request")["ok"], true);
        assert_eq!(
            wait_for_terminal_state(&driver)["state"]["phase"],
            "cancelled"
        );
    }

    #[test]
    fn destroy_joins_worker_and_allows_immediate_reopen() {
        let root = tempfile::tempdir().expect("temp root");
        let vault_path = root.path().join("vault");
        let store_path = root.path().join("history.sqlite3");
        seed_committed_bundle(&vault_path);
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(AtomicBool::new(false));
        {
            let driver = ReviewSessionDriver::new_with_listing_barrier(
                vault_path.clone(),
                store_path.clone(),
                entered.clone(),
                release,
            );
            assert_eq!(
                driver.request(br#"{"version":1,"operation":"start","session_id":"destroy"}"#,)["ok"],
                true
            );
            entered.wait();
        }
        let reopened = ReviewSessionDriver::new(vault_path, store_path);
        assert_eq!(
            reopened.request(br#"{"version":1,"operation":"state"}"#)["state"]["phase"],
            "idle"
        );
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
