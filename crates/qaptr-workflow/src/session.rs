//! Review-app-owned lifecycle coordination above [`AnalysisRunner`].
//!
//! The runner owns the privacy and provider boundaries. This coordinator owns
//! the review-session lifecycle around it: deterministic capture ingestion,
//! retention before analysis, cooperative cancellation, retry of sealed
//! captures, and coarse progress suitable for a UI bridge. It deliberately
//! exposes summaries and state, never vault members or provider payloads.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use qaptr_domain::clock::Clock;
use qaptr_domain::ports::{CredentialPort, OcrPort, VisionPort};
use qaptr_domain::{CaptureId, SessionId};
use qaptr_policy::{ModelId, RetentionError, RetentionPolicy, enforce_retention};
use qaptr_provider::{ProviderAdapter, ProviderId};
use qaptr_store::{Store, StoreError};
use qaptr_vault::Vault;
use thiserror::Error;

use crate::{
    AnalysisError, AnalysisReport, AnalysisRunner, Cancellation, CaptureRecordInput,
    ProviderOutcome,
};

/// A coarse lifecycle state safe to mirror across the review bridge.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ReviewProgress {
    /// Sealed capture metadata is being deduplicated and made eligible.
    Ingesting {
        /// Number of deduplicated capture records seen.
        captures_seen: usize,
    },
    /// Local privacy preparation is running. No provider request has occurred.
    Preparing {
        /// Number of eligible capture records being prepared.
        captures_seen: usize,
    },
    /// The runner has finished local preparation and is about to request consent.
    ReadyForConsent {
        /// Number of capture records supplied to the session.
        captures_seen: usize,
        /// Number of captures that passed local preparation.
        prepared_captures: usize,
        /// Number of captures excluded by the local privacy gate.
        excluded_captures: usize,
        /// Selected provider, when one was configured.
        provider: Option<ProviderId>,
    },
    /// Provider analysis is in flight.
    Analyzing {
        /// Number of prepared captures being sent after consent.
        captures: usize,
    },
    /// The session finished and durable scalar history can be refreshed.
    Completed {
        /// Number of capture records supplied to the session.
        captures_seen: usize,
        /// Number of scalar observations committed by the runner.
        observations_written: usize,
    },
    /// The session stopped cooperatively without committing staged results.
    Cancelled {
        /// Number of capture records seen before cancellation.
        captures_seen: usize,
    },
    /// The session failed before a trustworthy completed result existed.
    Failed {
        /// A concise recovery-oriented message safe for the UI.
        message: String,
    },
}

impl ReviewProgress {
    /// Returns a bridge-stable lowercase state name.
    pub const fn state_name(&self) -> &'static str {
        match self {
            Self::Ingesting { .. } => "ingesting",
            Self::Preparing { .. } => "preparing",
            Self::ReadyForConsent { .. } => "ready_for_consent",
            Self::Analyzing { .. } => "analyzing",
            Self::Completed { .. } => "completed",
            Self::Cancelled { .. } => "cancelled",
            Self::Failed { .. } => "failed",
        }
    }
}

/// A cloneable cancellation handle for a running review session.
#[derive(Clone, Debug, Default)]
pub struct SessionCancellation {
    cancelled: Arc<AtomicBool>,
}

impl SessionCancellation {
    /// Creates a reset cancellation handle.
    pub fn new() -> Self {
        Self::default()
    }

    /// Requests cooperative cancellation at the next runner boundary.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    /// Clears a previous request before a new attempt or retry.
    pub fn reset(&self) {
        self.cancelled.store(false, Ordering::Release);
    }

    /// Returns whether cancellation has been requested.
    pub fn is_requested(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }
}

impl Cancellation for SessionCancellation {
    fn is_cancelled(&self) -> bool {
        self.is_requested()
    }
}

/// Errors raised by the review-session lifecycle rather than by provider data.
#[derive(Debug, Error)]
pub enum ReviewSessionError {
    /// Local analysis or persistence failed inside the runner.
    #[error(transparent)]
    Analysis(#[from] AnalysisError),
    /// Retention could not safely complete before preparation.
    #[error("review retention failed: {0}")]
    Retention(#[from] RetentionError),
    /// The durable history snapshot could not be read while ingesting.
    #[error("review history could not be read: {0}")]
    Store(#[from] StoreError),
    /// Retry was requested before a session had an eligible capture set.
    #[error("no review session is available to retry")]
    NothingToRetry,
}

/// A production-shaped coordinator that is the review app's lifecycle owner.
///
/// Construction is side-effect free. The supplied runner remains the only
/// owner of vault opening, local preparation, provider dispatch, and scalar
/// observation persistence. This wrapper owns when those operations happen and
/// provides the restart-safe lifecycle around them.
pub struct ReviewSessionCoordinator<'a, C, O, V, A, D, P, K>
where
    C: CredentialPort,
    O: OcrPort,
    V: VisionPort,
    A: ProviderAdapter,
    D: crate::CaptureDecoder,
    P: crate::ConsentPort,
    K: Clock,
{
    runner: &'a AnalysisRunner<'a, C, O, V, A, D, P, K>,
    vault: &'a Vault,
    credentials: &'a C,
    store: &'a Store,
    clock: &'a K,
    retention: Option<RetentionPolicy>,
    cancellation: SessionCancellation,
    last_session: Option<SessionId>,
    last_captures: Option<Vec<CaptureRecordInput>>,
}

impl<'a, C, O, V, A, D, P, K> ReviewSessionCoordinator<'a, C, O, V, A, D, P, K>
where
    C: CredentialPort,
    O: OcrPort,
    V: VisionPort,
    A: ProviderAdapter,
    D: crate::CaptureDecoder,
    P: crate::ConsentPort,
    K: Clock,
{
    /// Creates a coordinator without opening the vault or invoking a provider.
    pub fn new(
        runner: &'a AnalysisRunner<'a, C, O, V, A, D, P, K>,
        vault: &'a Vault,
        credentials: &'a C,
        store: &'a Store,
        clock: &'a K,
    ) -> Self {
        Self::with_cancellation(
            runner,
            vault,
            credentials,
            store,
            clock,
            SessionCancellation::new(),
        )
    }

    /// Creates a coordinator with a caller-owned cancellation handle.
    ///
    /// The review bridge uses this constructor to publish the same handle
    /// before it lists committed bundles. That closes the cancellation window
    /// between ingestion and coordinator construction.
    pub fn with_cancellation(
        runner: &'a AnalysisRunner<'a, C, O, V, A, D, P, K>,
        vault: &'a Vault,
        credentials: &'a C,
        store: &'a Store,
        clock: &'a K,
        cancellation: SessionCancellation,
    ) -> Self {
        Self {
            runner,
            vault,
            credentials,
            store,
            clock,
            retention: None,
            cancellation,
            last_session: None,
            last_captures: None,
        }
    }

    /// Applies retention before the next preparation pass.
    pub const fn with_retention_policy(mut self, policy: RetentionPolicy) -> Self {
        self.retention = Some(policy);
        self
    }

    /// Returns a handle that can cancel this coordinator's current attempt.
    pub fn cancellation(&self) -> SessionCancellation {
        self.cancellation.clone()
    }

    /// Requests cancellation without requiring access to the runner.
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }

    /// Starts a fresh session from sealed capture metadata.
    ///
    /// Inputs are deduplicated by stable capture id before any vault access.
    /// Retry stores this exact metadata set and therefore reuses sealed
    /// captures without reusing a stale provider verification decision.
    pub fn start<F>(
        &mut self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
        progress: F,
    ) -> Result<AnalysisReport, ReviewSessionError>
    where
        F: FnMut(ReviewProgress),
    {
        self.start_with_resolved_model(session_id, captures, None, progress)
    }

    /// Starts a fresh session with the model resolved for this request.
    pub fn start_with_resolved_model<F>(
        &mut self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
        resolved_model: Option<ModelId>,
        progress: F,
    ) -> Result<AnalysisReport, ReviewSessionError>
    where
        F: FnMut(ReviewProgress),
    {
        self.start_with_resolved_model_mode(session_id, captures, resolved_model, progress, false)
    }

    fn start_with_resolved_model_mode<F>(
        &mut self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
        resolved_model: Option<ModelId>,
        mut progress: F,
        allow_reprocessing: bool,
    ) -> Result<AnalysisReport, ReviewSessionError>
    where
        F: FnMut(ReviewProgress),
    {
        self.last_session = Some(session_id.clone());
        let mut eligible = deduplicate(captures);
        if !allow_reprocessing {
            let represented = self
                .store
                .snapshot()?
                .captures
                .into_iter()
                .map(|capture| capture.id)
                .collect::<BTreeSet<_>>();
            eligible.retain(|capture| !represented.contains(capture.capture_id()));
        }
        self.last_captures = Some(eligible.clone());
        progress(ReviewProgress::Ingesting {
            captures_seen: eligible.len(),
        });

        if self.cancellation.is_requested() {
            progress(ReviewProgress::Cancelled {
                captures_seen: eligible.len(),
            });
            let report = self
                .runner
                .run_with_cancellation(session_id, &[], &self.cancellation)?;
            return Ok(report);
        }

        self.store.transaction(|transaction| {
            for capture in &eligible {
                transaction.put_capture(&capture.record)?;
            }
            Ok(())
        })?;

        if let Some(policy) = self.retention {
            enforce_retention(
                &policy,
                self.vault,
                self.store,
                self.credentials,
                self.clock,
            )?;

            let remaining = self
                .store
                .snapshot()?
                .captures
                .into_iter()
                .map(|capture| capture.id)
                .collect::<std::collections::BTreeSet<_>>();
            eligible.retain(|capture| remaining.contains(capture.capture_id()));
        }

        self.last_captures = Some(eligible.clone());

        if self.cancellation.is_requested() {
            progress(ReviewProgress::Cancelled {
                captures_seen: eligible.len(),
            });
            let report = self
                .runner
                .run_with_cancellation(session_id, &[], &self.cancellation)?;
            return Ok(report);
        }
        progress(ReviewProgress::Preparing {
            captures_seen: eligible.len(),
        });

        let report = self.runner.run_with_cancellation_and_resolved_model(
            session_id,
            &eligible,
            &self.cancellation,
            resolved_model,
        )?;
        emit_report_progress(&report, &mut progress);
        Ok(report)
    }

    /// Retries the last sealed-capture set with fresh provider/model checks.
    pub fn retry<F>(&mut self, progress: F) -> Result<AnalysisReport, ReviewSessionError>
    where
        F: FnMut(ReviewProgress),
    {
        let session_id = self
            .last_session
            .clone()
            .ok_or(ReviewSessionError::NothingToRetry)?;
        let captures = self
            .last_captures
            .clone()
            .ok_or(ReviewSessionError::NothingToRetry)?;
        self.cancellation.reset();
        self.start_with_resolved_model_mode(session_id, &captures, None, progress, true)
    }

    /// Returns the last deduplicated input set, without exposing vault data.
    pub fn last_capture_ids(&self) -> Vec<CaptureId> {
        self.last_captures
            .as_deref()
            .unwrap_or_default()
            .iter()
            .map(|capture| capture.capture_id().clone())
            .collect()
    }
}

fn deduplicate(captures: &[CaptureRecordInput]) -> Vec<CaptureRecordInput> {
    let mut unique = BTreeMap::new();
    for capture in captures {
        unique
            .entry(capture.capture_id().clone())
            .or_insert_with(|| capture.clone());
    }
    unique.into_values().collect()
}

fn emit_report_progress<F: FnMut(ReviewProgress)>(report: &AnalysisReport, progress: &mut F) {
    match &report.provider {
        ProviderOutcome::Cancelled => progress(ReviewProgress::Cancelled {
            captures_seen: report.captures_seen,
        }),
        ProviderOutcome::Unavailable { provider, .. } if report.prepared_captures > 0 => {
            progress(ReviewProgress::ReadyForConsent {
                captures_seen: report.captures_seen,
                prepared_captures: report.prepared_captures,
                excluded_captures: report.excluded_captures,
                provider: provider.clone(),
            });
            progress(ReviewProgress::Failed {
                message: "provider unavailable; check provider setup and retry".to_owned(),
            });
        }
        ProviderOutcome::ConsentDeclined => progress(ReviewProgress::Completed {
            captures_seen: report.captures_seen,
            observations_written: 0,
        }),
        ProviderOutcome::Failed { .. } => progress(ReviewProgress::Failed {
            message: "provider analysis failed; no partial observations were committed".to_owned(),
        }),
        ProviderOutcome::NotAttempted => progress(ReviewProgress::Completed {
            captures_seen: report.captures_seen,
            observations_written: 0,
        }),
        ProviderOutcome::Completed { .. } => {
            progress(ReviewProgress::Analyzing {
                captures: report.prepared_captures,
            });
            progress(ReviewProgress::Completed {
                captures_seen: report.captures_seen,
                observations_written: report.observations_written,
            });
        }
        ProviderOutcome::Unavailable { .. } => progress(ReviewProgress::Failed {
            message: "no provider is configured; choose a provider and retry".to_owned(),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        collections::HashMap,
        sync::Mutex,
        time::{Duration, UNIX_EPOCH},
    };

    use qaptr_domain::clock::FixedClock;
    use qaptr_domain::ports::credentials::{CredentialKey, CredentialValue};
    use qaptr_domain::ports::ocr::OcrResult;
    use qaptr_domain::ports::vision::VisionResult;
    use qaptr_domain::ports::{CredentialPort, PortOutcome};
    use qaptr_domain::ports::{OcrPort, VisionPort};
    use qaptr_privacy::{PrivacyGate, measure_recall};
    use qaptr_provider::{
        ProviderDescriptor, ProviderDetection, ProviderError, ProviderGate, ProviderInvocation,
        RawProviderResponse,
    };
    use qaptr_store::{CaptureRecord, UnixMillis};
    use qaptr_vault::{BundleInput, GenerationId, GenerationKeypair, SampledContext, Vault};

    #[derive(Default)]
    struct MemoryCredentials {
        values: Mutex<HashMap<String, CredentialValue>>,
    }

    impl CredentialPort for MemoryCredentials {
        fn read(
            &self,
            key: &CredentialKey,
        ) -> qaptr_domain::Result<PortOutcome<Option<CredentialValue>>> {
            Ok(PortOutcome::Complete(
                self.values
                    .lock()
                    .expect("credential lock")
                    .get(key.as_str())
                    .cloned(),
            ))
        }

        fn write(
            &self,
            key: &CredentialKey,
            value: CredentialValue,
        ) -> qaptr_domain::Result<PortOutcome<()>> {
            self.values
                .lock()
                .expect("credential lock")
                .insert(key.as_str().to_owned(), value);
            Ok(PortOutcome::Complete(()))
        }

        fn delete(&self, key: &CredentialKey) -> qaptr_domain::Result<PortOutcome<()>> {
            self.values
                .lock()
                .expect("credential lock")
                .remove(key.as_str());
            Ok(PortOutcome::Complete(()))
        }
    }

    struct UnusedCredentials;

    impl CredentialPort for UnusedCredentials {
        fn read(
            &self,
            _key: &CredentialKey,
        ) -> qaptr_domain::Result<PortOutcome<Option<CredentialValue>>> {
            panic!("credentials must not be read before preparation")
        }

        fn write(
            &self,
            _key: &CredentialKey,
            _value: CredentialValue,
        ) -> qaptr_domain::Result<PortOutcome<()>> {
            panic!("credentials must not be written")
        }

        fn delete(&self, _key: &CredentialKey) -> qaptr_domain::Result<PortOutcome<()>> {
            panic!("credentials must not be deleted")
        }
    }

    struct UnusedOcr;
    impl OcrPort for UnusedOcr {
        fn recognize(
            &self,
            _capture: &qaptr_domain::CaptureId,
        ) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
            panic!("OCR must not run before preparation")
        }
    }

    struct UnusedVision;
    impl VisionPort for UnusedVision {
        fn detect(
            &self,
            _capture: &qaptr_domain::CaptureId,
        ) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
            panic!("vision must not run before preparation")
        }
    }

    struct UnusedDecoder;
    impl crate::CaptureDecoder for UnusedDecoder {
        fn decode(
            &self,
            _bundle: &qaptr_vault::OpenedBundle,
        ) -> Result<qaptr_privacy::PreparationInput, crate::DecodeError> {
            panic!("decoder must not run before preparation")
        }
    }

    struct UnusedConsent;
    impl crate::ConsentPort for UnusedConsent {
        fn request(&self, _request: &crate::ConsentRequest) -> crate::ConsentDecision {
            panic!("consent must not be requested after cancellation")
        }
    }

    struct UnusedProvider {
        descriptor: ProviderDescriptor,
    }

    impl qaptr_provider::ProviderAdapter for UnusedProvider {
        fn descriptor(&self) -> &ProviderDescriptor {
            &self.descriptor
        }

        fn detect(&self) -> Result<ProviderDetection, ProviderError> {
            panic!("provider must not be detected after cancellation")
        }

        fn invoke(
            &self,
            _invocation: ProviderInvocation<'_>,
        ) -> Result<RawProviderResponse, ProviderError> {
            panic!("provider must not be invoked after cancellation")
        }
    }

    #[test]
    fn cancellation_before_retention_returns_without_preparation() {
        let root =
            std::env::temp_dir().join(format!("qaptr-session-cancel-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("test root");
        let vault = Vault::new(root.join("vault")).expect("vault");
        let store = Store::open(root.join("history.sqlite3")).expect("store");
        let credentials = UnusedCredentials;
        let privacy = PrivacyGate::new(measure_recall(&[], &[]).expect("recall"));
        let ocr = UnusedOcr;
        let vision = UnusedVision;
        let decoder = UnusedDecoder;
        let consent = UnusedConsent;
        let clock = FixedClock::new(UNIX_EPOCH + Duration::from_secs(1));
        let runner = AnalysisRunner::new(
            &vault,
            &credentials,
            &store,
            &privacy,
            &ocr,
            &vision,
            None::<&ProviderGate<UnusedProvider>>,
            &decoder,
            &consent,
            &clock,
        );
        let mut coordinator =
            ReviewSessionCoordinator::new(&runner, &vault, &credentials, &store, &clock)
                .with_retention_policy(RetentionPolicy::new(qaptr_domain::Duration::from_secs(1)));
        let cancellation = coordinator.cancellation();
        cancellation.cancel();
        let mut states = Vec::new();

        let report = coordinator
            .start(
                SessionId::new("cancel-before-retention").expect("session"),
                &[],
                |state| states.push(state.state_name()),
            )
            .expect("cancelled session");

        assert!(matches!(report.provider, ProviderOutcome::Cancelled));
        assert_eq!(states, ["ingesting", "cancelled"]);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn cancellation_handle_is_shared_and_resettable() {
        let first = SessionCancellation::new();
        let second = first.clone();
        assert!(!second.is_requested());
        first.cancel();
        assert!(second.is_requested());
        second.reset();
        assert!(!first.is_requested());
    }

    #[test]
    fn duplicate_capture_metadata_is_deduplicated_before_durable_upsert() {
        let root = tempfile::tempdir().expect("test root");
        let store = Store::open(root.path().join("history.sqlite3")).expect("store");
        let first = CaptureRecordInput::new(CaptureRecord {
            id: CaptureId::new("capture-1").expect("capture id"),
            captured_at: UnixMillis::from_millis(1),
            vault_record_id: "capture-1".to_owned(),
            context_summary: Some("first".to_owned()),
        });
        let duplicate = CaptureRecordInput::new(CaptureRecord {
            id: first.capture_id().clone(),
            captured_at: UnixMillis::from_millis(2),
            vault_record_id: "different-metadata-must-not-win".to_owned(),
            context_summary: Some("duplicate".to_owned()),
        });
        let unique = deduplicate(&[first.clone(), duplicate]);
        assert_eq!(unique.as_slice(), std::slice::from_ref(&first));
        store
            .transaction(|transaction| {
                for capture in &unique {
                    transaction.put_capture(&capture.record)?;
                }
                Ok(())
            })
            .expect("durable metadata upsert");
        let snapshot = store.snapshot().expect("history snapshot");
        assert_eq!(snapshot.captures, [first.record]);
    }

    #[test]
    fn coordinator_applies_retention_before_preparation() {
        let root = tempfile::tempdir().expect("test root");
        let vault = Vault::new(root.path().join("vault")).expect("vault");
        let store = Store::open(root.path().join("history.sqlite3")).expect("store");
        let credentials = MemoryCredentials::default();
        let keys =
            GenerationKeypair::generate(GenerationId::new("generation-1").expect("generation id"));
        let capture_id = CaptureId::new("capture-expired").expect("capture id");
        let credential_key =
            Vault::generation_credential_key(keys.generation_id()).expect("credential key");
        credentials
            .write(&credential_key, keys.private_key().to_credential_value())
            .expect("credential write");
        vault
            .register_public_key(keys.generation_id(), keys.public_key())
            .expect("public key");
        vault
            .seal(
                &BundleInput::new(
                    capture_id.clone(),
                    keys.generation_id().clone(),
                    UNIX_EPOCH,
                    b"image".to_vec(),
                    SampledContext::new(b"context".to_vec()),
                    Vec::new(),
                ),
                keys.public_key(),
            )
            .expect("bundle");
        store
            .put_capture(&CaptureRecord {
                id: capture_id,
                captured_at: UnixMillis::from_millis(0),
                vault_record_id: "capture-expired".to_owned(),
                context_summary: None,
            })
            .expect("capture metadata");

        let privacy = PrivacyGate::new(measure_recall(&[], &[]).expect("recall"));
        let ocr = UnusedOcr;
        let vision = UnusedVision;
        let decoder = UnusedDecoder;
        let consent = UnusedConsent;
        let clock = FixedClock::new(UNIX_EPOCH + Duration::from_secs(2));
        let runner = AnalysisRunner::new(
            &vault,
            &credentials,
            &store,
            &privacy,
            &ocr,
            &vision,
            None::<&ProviderGate<UnusedProvider>>,
            &decoder,
            &consent,
            &clock,
        );
        let mut coordinator =
            ReviewSessionCoordinator::new(&runner, &vault, &credentials, &store, &clock)
                .with_retention_policy(RetentionPolicy::new(qaptr_domain::Duration::from_secs(1)));

        let report = coordinator
            .start(SessionId::new("retention").expect("session"), &[], |_| {})
            .expect("retention session");
        assert!(matches!(report.provider, ProviderOutcome::NotAttempted));
        assert!(vault.list_committed_bundles().expect("bundles").is_empty());
        assert!(store.snapshot().expect("snapshot").captures.is_empty());
    }

    #[test]
    fn progress_names_are_bridge_stable() {
        assert_eq!(
            ReviewProgress::Ingesting { captures_seen: 0 }.state_name(),
            "ingesting"
        );
        assert_eq!(
            ReviewProgress::Cancelled { captures_seen: 0 }.state_name(),
            "cancelled"
        );
        assert_eq!(
            ReviewProgress::Failed {
                message: "x".to_owned()
            }
            .state_name(),
            "failed"
        );
    }
}
