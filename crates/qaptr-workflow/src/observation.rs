//! Deterministic conversion of normalized provider output into durable summaries.

use qaptr_domain::{CaptureId, ObservationId, SessionId};
use qaptr_provider::NormalizedResponse;
use qaptr_store::{ObservationRecord, UnixMillis};
use thiserror::Error;

/// The maximum number of observations retained from one analysis session.
pub const DEFAULT_OBSERVATION_LIMIT: usize = 3;

/// Errors raised while converting provider output into durable records.
#[derive(Debug, Error)]
pub enum ObservationError {
    /// The generated observation identifier could not be constructed.
    #[error("observation id could not be constructed: {0}")]
    InvalidId(#[source] qaptr_domain::DomainError),
}

/// Converts a normalized response into stable, bounded observation records.
///
/// The provider's confidence is copied without calibration or inflation. The
/// generated identifier is stable for a session, capture, and response index,
/// so replaying an interrupted analysis replaces the same row instead of
/// creating a duplicate.
pub fn records_from_response(
    session_id: &SessionId,
    capture_id: &CaptureId,
    response: &NormalizedResponse,
    created_at: UnixMillis,
    limit: usize,
) -> Result<Vec<ObservationRecord>, ObservationError> {
    response
        .observations()
        .iter()
        .take(limit)
        .enumerate()
        .map(|(index, observation)| {
            let id = ObservationId::new(format!("u17/{session_id}/{capture_id}/{index}"))
                .map_err(ObservationError::InvalidId)?;
            Ok(ObservationRecord {
                id,
                capture_id: Some(capture_id.clone()),
                session_id: session_id.clone(),
                title: observation.title().to_owned(),
                summary: observation.summary().to_owned(),
                confidence: observation.confidence(),
                created_at,
            })
        })
        .collect()
}
