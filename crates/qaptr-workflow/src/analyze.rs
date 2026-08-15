//! In-process preparation, provider dispatch, and durable observation analysis.
//!
//! # Invariants
//!
//! - The review app is the only owner of this task. No worker executable,
//!   shell, automation, or tool is launched here.
//! - A provider request is constructed only from a [`qaptr_privacy::PreparedPayload`] returned
//!   by U12's [`PrivacyGate`]. A privacy exclusion is never converted into a
//!   fallback request.
//! - Vault opening and local preparation happen before consent and provider
//!   invocation. The capture metadata is durable before either operation, so a
//!   provider failure cannot lose the sealed capture.
//! - Observation writes are staged and committed in one transaction. A
//!   cancellation or provider failure therefore leaves no partial observation
//!   batch, while deterministic ids make a later run resumable.

use std::fmt;

use qaptr_domain::clock::Clock;
use qaptr_domain::ports::{CredentialPort, OcrPort, VisionPort};
use qaptr_domain::{CaptureId, SessionId};
use qaptr_policy::ModelId;
use qaptr_privacy::{PreparationInput, PrivacyGate};
use qaptr_provider::{ProviderAdapter, ProviderError, ProviderGate, ProviderId};
use qaptr_store::{CaptureRecord, Store, StoreError, UnixMillis};
use qaptr_vault::{OpenedBundle, Vault, VaultError};
use thiserror::Error;

use crate::consent::{ConsentDecision, ConsentPort, ConsentRequest};
use crate::document::{ConfidenceAssessment, WorkflowDocument, WorkflowError};
use crate::observation::{DEFAULT_OBSERVATION_LIMIT, ObservationError, records_from_response};

/// One sealed capture and its durable scalar metadata.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CaptureRecordInput {
    /// The capture metadata to upsert before opening the vault bundle.
    pub record: CaptureRecord,
}

impl CaptureRecordInput {
    /// Creates an analysis input from durable capture metadata.
    pub const fn new(record: CaptureRecord) -> Self {
        Self { record }
    }

    /// Returns the stable capture identifier.
    pub const fn capture_id(&self) -> &CaptureId {
        &self.record.id
    }
}

/// Errors raised while decoding an opened bundle into U12's input type.
#[derive(Debug, Error)]
pub enum DecodeError {
    /// The sealed bundle did not contain a usable local preparation input.
    #[error("capture bundle could not be decoded: {0}")]
    InvalidInput(String),
}

/// The review-app boundary that decodes sealed members into local gate input.
///
/// Implementations may inspect image bytes only inside
/// [`OpenedBundle::with_image_for_privacy`]. They must return a
/// [`PreparationInput`], never a provider payload or raw bytes for another
/// caller to retain.
pub trait CaptureDecoder {
    /// Decodes one already-opened bundle for local privacy preparation.
    fn decode(&self, bundle: &OpenedBundle) -> Result<PreparationInput, DecodeError>;
}

/// A cooperative cancellation boundary for the in-process analysis task.
pub trait Cancellation {
    /// Returns whether the current run should stop before the next boundary.
    fn is_cancelled(&self) -> bool;
}

/// A cancellation source that never requests cancellation.
#[derive(Clone, Copy, Debug, Default)]
pub struct NeverCancelled;

impl Cancellation for NeverCancelled {
    fn is_cancelled(&self) -> bool {
        false
    }
}

/// A quiet, user-visible summary of one aggregated privacy exclusion notice.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExclusionNotice {
    count: usize,
}

impl ExclusionNotice {
    fn new(count: usize) -> Self {
        Self { count }
    }

    /// Returns the number of excluded captures represented by this notice.
    pub const fn count(&self) -> usize {
        self.count
    }

    /// Returns the one-line notice shown to the person.
    pub fn text(&self) -> String {
        let noun = if self.count == 1 {
            "capture"
        } else {
            "captures"
        };
        let verb = if self.count == 1 { "was" } else { "were" };
        let pronoun = if self.count == 1 { "it" } else { "they" };
        format!(
            "{} {noun} {verb} excluded because {pronoun} could not be safely prepared.",
            self.count,
        )
    }
}

/// The provider-side result of one analysis session.
#[derive(Debug)]
pub enum ProviderOutcome {
    /// No provider was selected or the selected provider failed its handshake.
    Unavailable {
        /// The selected provider, when one was configured.
        provider: Option<ProviderId>,
        /// The typed handshake reason, when one was available.
        reason: Option<ProviderError>,
    },
    /// The person declined just-in-time consent.
    ConsentDeclined,
    /// All staged provider responses were persisted successfully.
    Completed {
        /// The provider that produced the responses.
        provider: ProviderId,
    },
    /// The provider failed after local preparation. Capture metadata remains.
    Failed {
        /// The provider that failed.
        provider: ProviderId,
        /// The typed provider failure.
        error: ProviderError,
    },
    /// The task stopped before committing its staged observations.
    Cancelled,
    /// No prepared payload remained after local fail-closed preparation.
    NotAttempted,
}

impl ProviderOutcome {
    /// Returns whether a provider adapter was invoked.
    pub const fn was_invoked(&self) -> bool {
        matches!(self, Self::Completed { .. } | Self::Failed { .. })
    }
}

/// The durable and user-facing result of one analysis run.
pub struct AnalysisReport {
    /// The session used for stable observation identity.
    pub session_id: SessionId,
    /// Number of sealed capture records supplied to the run.
    pub captures_seen: usize,
    /// Number of captures that passed U12 preparation.
    pub prepared_captures: usize,
    /// Number of captures excluded by U12.
    pub excluded_captures: usize,
    /// Number of observations committed to qaptr-store.
    pub observations_written: usize,
    /// One aggregated exclusion notice, if any capture was excluded.
    pub exclusion_notice: Option<ExclusionNotice>,
    /// The quiet provider outcome.
    pub provider: ProviderOutcome,
}

/// Errors that indicate a local orchestration or persistence problem.
#[derive(Debug, Error)]
pub enum AnalysisError {
    /// The vault could not open a sealed capture.
    #[error("capture vault failed: {0}")]
    Vault(#[source] VaultError),
    /// Durable history could not be written.
    #[error("analysis history failed: {0}")]
    Store(#[source] StoreError),
    /// An opened bundle could not be converted into U12 input.
    #[error("capture decode failed: {0}")]
    Decode(#[source] DecodeError),
    /// A decoder returned input for a different capture.
    #[error("capture decoder returned {actual}, expected {expected}")]
    CaptureMismatch {
        /// The id returned by the decoder.
        actual: CaptureId,
        /// The id from the sealed bundle.
        expected: CaptureId,
    },
    /// A normalized response could not become durable observations.
    #[error("observation conversion failed: {0}")]
    Observation(#[source] ObservationError),
    /// A provider workflow candidate could not become a canonical document.
    #[error("workflow conversion failed: {0}")]
    Workflow(#[source] WorkflowError),
}

/// The in-process analysis orchestrator owned by the review app.
pub struct AnalysisRunner<'a, C, O, V, A, D, P, K>
where
    C: CredentialPort,
    O: OcrPort,
    V: VisionPort,
    A: ProviderAdapter,
    D: CaptureDecoder,
    P: ConsentPort,
    K: Clock,
{
    vault: &'a Vault,
    credentials: &'a C,
    store: &'a Store,
    privacy: &'a PrivacyGate,
    ocr: &'a O,
    vision: &'a V,
    provider: Option<&'a ProviderGate<A>>,
    decoder: &'a D,
    consent: &'a P,
    clock: &'a K,
    observation_limit: usize,
}

impl<'a, C, O, V, A, D, P, K> AnalysisRunner<'a, C, O, V, A, D, P, K>
where
    C: CredentialPort,
    O: OcrPort,
    V: VisionPort,
    A: ProviderAdapter,
    D: CaptureDecoder,
    P: ConsentPort,
    K: Clock,
{
    /// Creates an orchestrator. No provider is invoked by construction.
    #[allow(clippy::too_many_arguments)]
    pub const fn new(
        vault: &'a Vault,
        credentials: &'a C,
        store: &'a Store,
        privacy: &'a PrivacyGate,
        ocr: &'a O,
        vision: &'a V,
        provider: Option<&'a ProviderGate<A>>,
        decoder: &'a D,
        consent: &'a P,
        clock: &'a K,
    ) -> Self {
        Self {
            vault,
            credentials,
            store,
            privacy,
            ocr,
            vision,
            provider,
            decoder,
            consent,
            clock,
            observation_limit: DEFAULT_OBSERVATION_LIMIT,
        }
    }

    /// Sets the per-capture observation bound for a deterministic review policy.
    pub const fn with_observation_limit(mut self, limit: usize) -> Self {
        self.observation_limit = limit;
        self
    }

    /// Runs local preparation, consent, provider dispatch, and one observation
    /// transaction. Provider failures are represented in [`ProviderOutcome`].
    pub fn run(
        &self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
    ) -> Result<AnalysisReport, AnalysisError> {
        self.run_with_resolved_model(session_id, captures, None)
    }

    /// Runs analysis with a model resolved for this request before consent.
    pub fn run_with_resolved_model(
        &self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
        resolved_model: Option<ModelId>,
    ) -> Result<AnalysisReport, AnalysisError> {
        self.run_with_cancellation_and_resolved_model(
            session_id,
            captures,
            &NeverCancelled,
            resolved_model,
        )
    }

    /// Runs analysis with cooperative cancellation between capture and provider
    /// boundaries. Staged observations are discarded when cancellation occurs.
    pub fn run_with_cancellation<X: Cancellation>(
        &self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
        cancellation: &X,
    ) -> Result<AnalysisReport, AnalysisError> {
        self.run_with_cancellation_and_resolved_model(session_id, captures, cancellation, None)
    }

    /// Runs analysis with cancellation and a model resolved for this request.
    pub fn run_with_cancellation_and_resolved_model<X: Cancellation>(
        &self,
        session_id: SessionId,
        captures: &[CaptureRecordInput],
        cancellation: &X,
        resolved_model: Option<ModelId>,
    ) -> Result<AnalysisReport, AnalysisError> {
        let created_at =
            UnixMillis::from_system_time(self.clock.now()).map_err(AnalysisError::Store)?;
        let mut prepared = Vec::new();
        let mut exclusions = Vec::new();

        for capture in captures {
            if cancellation.is_cancelled() {
                return Ok(cancelled_report(
                    session_id,
                    captures.len(),
                    prepared.len(),
                    exclusions.len(),
                ));
            }
            self.store
                .put_capture(&capture.record)
                .map_err(AnalysisError::Store)?;
            let opened = self
                .vault
                .open(capture.capture_id(), self.credentials)
                .map_err(AnalysisError::Vault)?;
            let input = self
                .decoder
                .decode(&opened)
                .map_err(AnalysisError::Decode)?;
            if input.capture_id() != capture.capture_id() {
                return Err(AnalysisError::CaptureMismatch {
                    actual: input.capture_id().clone(),
                    expected: capture.capture_id().clone(),
                });
            }
            match self.privacy.prepare(input, self.ocr, self.vision) {
                Ok(payload) => prepared.push(payload),
                Err(exclusion) => exclusions.push(exclusion),
            }
        }

        let exclusion_notice =
            (!exclusions.is_empty()).then(|| ExclusionNotice::new(exclusions.len()));
        if cancellation.is_cancelled() {
            return Ok(cancelled_report(
                session_id,
                captures.len(),
                prepared.len(),
                exclusions.len(),
            ));
        }
        if prepared.is_empty() {
            return Ok(AnalysisReport {
                session_id,
                captures_seen: captures.len(),
                prepared_captures: 0,
                excluded_captures: exclusions.len(),
                observations_written: 0,
                exclusion_notice,
                provider: ProviderOutcome::NotAttempted,
            });
        }

        let Some(provider) = self.provider else {
            return Ok(AnalysisReport {
                session_id,
                captures_seen: captures.len(),
                prepared_captures: prepared.len(),
                excluded_captures: exclusions.len(),
                observations_written: 0,
                exclusion_notice,
                provider: ProviderOutcome::Unavailable {
                    provider: None,
                    reason: None,
                },
            });
        };

        let verified = match provider.detect_and_verify() {
            Ok(verified) => verified,
            Err(reason) => {
                return Ok(AnalysisReport {
                    session_id,
                    captures_seen: captures.len(),
                    prepared_captures: prepared.len(),
                    excluded_captures: exclusions.len(),
                    observations_written: 0,
                    exclusion_notice,
                    provider: ProviderOutcome::Unavailable {
                        provider: Some(provider.adapter().descriptor().id().clone()),
                        reason: Some(reason),
                    },
                });
            }
        };

        let image_count = prepared
            .iter()
            .filter(|payload| payload.masked_image().is_some())
            .count();
        let payload_kind = if image_count > 0 {
            qaptr_provider::ProviderPayloadKind::Images
        } else {
            qaptr_provider::ProviderPayloadKind::Text
        };
        let consent_request = ConsentRequest::new(
            verified.descriptor().id().clone(),
            resolved_model,
            payload_kind,
            prepared.len(),
            image_count,
            exclusions.len(),
        );
        if self.consent.request(&consent_request) == ConsentDecision::Declined {
            return Ok(AnalysisReport {
                session_id,
                captures_seen: captures.len(),
                prepared_captures: prepared.len(),
                excluded_captures: exclusions.len(),
                observations_written: 0,
                exclusion_notice,
                provider: ProviderOutcome::ConsentDeclined,
            });
        }

        let mut observations = Vec::new();
        let mut workflow = None;
        for payload in &prepared {
            if cancellation.is_cancelled() {
                return Ok(cancelled_report(
                    session_id,
                    captures.len(),
                    prepared.len(),
                    exclusions.len(),
                ));
            }
            let response = match provider.invoke(&verified, payload) {
                Ok(response) => response,
                Err(error) => {
                    return Ok(AnalysisReport {
                        session_id,
                        captures_seen: captures.len(),
                        prepared_captures: prepared.len(),
                        excluded_captures: exclusions.len(),
                        observations_written: 0,
                        exclusion_notice,
                        provider: ProviderOutcome::Failed {
                            provider: verified.descriptor().id().clone(),
                            error,
                        },
                    });
                }
            };
            if workflow.is_none()
                && let Some(candidate) = response.workflow()
            {
                let evidence = response
                    .observations()
                    .first()
                    .map(|observation| {
                        ConfidenceAssessment::scored(observation.confidence())
                            .with_basis("Inherited from the first observed response item")
                    })
                    .unwrap_or_else(ConfidenceAssessment::unknown);
                workflow = Some(
                    WorkflowDocument::from_candidate(
                        &session_id,
                        candidate,
                        0,
                        evidence,
                        Some(payload.capture_id().clone()),
                    )
                    .map_err(AnalysisError::Workflow)?,
                );
            }
            let remaining = self.observation_limit.saturating_sub(observations.len());
            observations.extend(
                records_from_response(
                    &session_id,
                    payload.capture_id(),
                    &response,
                    created_at,
                    remaining,
                )
                .map_err(AnalysisError::Observation)?,
            );
        }

        let observations_written = observations.len();
        let workflow_record = workflow
            .as_ref()
            .map(|workflow| workflow.to_record(created_at))
            .transpose()
            .map_err(AnalysisError::Workflow)?;
        self.store
            .transaction(|transaction| {
                for observation in &observations {
                    transaction.put_observation(observation)?;
                }
                if let Some(workflow) = &workflow_record {
                    transaction.put_workflow(workflow)?;
                }
                Ok(())
            })
            .map_err(AnalysisError::Store)?;

        Ok(AnalysisReport {
            session_id,
            captures_seen: captures.len(),
            prepared_captures: prepared.len(),
            excluded_captures: exclusions.len(),
            observations_written,
            exclusion_notice,
            provider: ProviderOutcome::Completed {
                provider: verified.descriptor().id().clone(),
            },
        })
    }
}

fn cancelled_report(
    session_id: SessionId,
    captures_seen: usize,
    prepared_captures: usize,
    excluded_captures: usize,
) -> AnalysisReport {
    AnalysisReport {
        session_id,
        captures_seen,
        prepared_captures,
        excluded_captures,
        observations_written: 0,
        exclusion_notice: (!matches!(excluded_captures, 0))
            .then(|| ExclusionNotice::new(excluded_captures)),
        provider: ProviderOutcome::Cancelled,
    }
}

impl fmt::Debug for AnalysisReport {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AnalysisReport")
            .field("session_id", &self.session_id)
            .field("captures_seen", &self.captures_seen)
            .field("prepared_captures", &self.prepared_captures)
            .field("excluded_captures", &self.excluded_captures)
            .field("observations_written", &self.observations_written)
            .field("exclusion_notice", &self.exclusion_notice)
            .field("provider", &self.provider)
            .finish()
    }
}
