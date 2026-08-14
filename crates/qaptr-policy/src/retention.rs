//! Pure retention decisions over sealed-bundle metadata.

use std::{
    collections::BTreeMap,
    time::{Duration as StdDuration, SystemTime, UNIX_EPOCH},
};

use qaptr_domain::{CaptureId, Clock, Duration, ports::CredentialPort};
use qaptr_store::Store;
use qaptr_vault::{BundleMetadata, GenerationId, Vault, VaultError};
use thiserror::Error;

/// Errors returned while executing the retention cascade.
#[derive(Debug, Error)]
pub enum RetentionError {
    /// The vault could not destroy a generation.
    #[error(transparent)]
    Vault(#[from] VaultError),
    /// Durable history could not be updated.
    #[error(transparent)]
    Store(#[from] qaptr_store::StoreError),
    /// A stored capture timestamp could not be represented as a system time.
    #[error("capture {capture_id} has an invalid timestamp")]
    InvalidTimestamp {
        /// The affected capture.
        capture_id: CaptureId,
    },
}

/// Metadata needed to decide whether a bundle's retention cohort has expired.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RetentionBundle {
    /// Non-sensitive identity and generation metadata from the vault.
    pub metadata: BundleMetadata,
    /// Instant at which the capture was made.
    pub captured_at: SystemTime,
}

impl RetentionBundle {
    /// Creates a retention candidate from vault metadata and capture time.
    pub const fn new(metadata: BundleMetadata, captured_at: SystemTime) -> Self {
        Self {
            metadata,
            captured_at,
        }
    }
}

/// User-selected lifetime for ephemeral capture bundles.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RetentionPolicy {
    lifetime: Duration,
}

impl RetentionPolicy {
    /// Creates a policy with the supplied non-negative lifetime.
    pub const fn new(lifetime: Duration) -> Self {
        Self { lifetime }
    }

    /// Returns the configured lifetime.
    pub const fn lifetime(self) -> Duration {
        self.lifetime
    }

    /// Returns whether one capture is expired at the instant supplied by
    /// `clock`.
    ///
    /// A backwards-moving clock returns `false`, preserving the invariant
    /// that time movement cannot cause premature deletion.
    pub fn is_expired<C: Clock>(&self, captured_at: SystemTime, clock: &C) -> bool {
        self.is_expired_at(captured_at, clock.now())
    }

    /// Finds retention cohorts whose every bundle is expired.
    ///
    /// A generation is the vault's erasure cohort. The reaper destroys a
    /// generation key, so a mixed cohort is deliberately retained rather than
    /// deleting only part of a generation and leaving the cohort inconsistent.
    pub fn expired_generations<C: Clock>(
        &self,
        bundles: &[RetentionBundle],
        clock: &C,
    ) -> Vec<GenerationId> {
        let now = clock.now();
        let mut cohorts = BTreeMap::<GenerationId, bool>::new();
        for bundle in bundles {
            let expired = self.is_expired_at(bundle.captured_at, now);
            cohorts
                .entry(bundle.metadata.generation_id.clone())
                .and_modify(|all_expired| *all_expired &= expired)
                .or_insert(expired);
        }
        cohorts
            .into_iter()
            .filter_map(|(generation, all_expired)| all_expired.then_some(generation))
            .collect()
    }

    fn is_expired_at(&self, captured_at: SystemTime, now: SystemTime) -> bool {
        now.duration_since(captured_at)
            .is_ok_and(|age| age >= self.lifetime.as_std())
    }
}

/// Counts the completed stages of one retention cascade.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RetentionReport {
    /// Number of generation keys processed by the vault reaper.
    pub generations_reaped: usize,
    /// Number of bundle directories removed by the vault reaper.
    pub bundles_removed: usize,
    /// Number of durable capture metadata rows removed after vault success.
    pub captures_removed: usize,
}

/// Applies retention to the vault and then removes only the corresponding
/// capture metadata. Observations and workflows are not touched.
pub fn enforce_retention<C: CredentialPort, K: Clock>(
    policy: &RetentionPolicy,
    vault: &Vault,
    store: &Store,
    credentials: &C,
    clock: &K,
) -> Result<RetentionReport, RetentionError> {
    let snapshot = store.snapshot()?;
    let mut candidates = Vec::with_capacity(snapshot.captures.len());
    for capture in snapshot.captures {
        let captured_at = UNIX_EPOCH
            .checked_add(StdDuration::from_millis(
                u64::try_from(capture.captured_at.as_millis()).map_err(|_| {
                    RetentionError::InvalidTimestamp {
                        capture_id: capture.id.clone(),
                    }
                })?,
            ))
            .ok_or_else(|| RetentionError::InvalidTimestamp {
                capture_id: capture.id.clone(),
            })?;
        match vault.bundle_metadata(&capture.id) {
            Ok(metadata) => {
                candidates.push((capture.id, RetentionBundle::new(metadata, captured_at)))
            }
            Err(VaultError::BundleNotFound(_)) => {}
            Err(error) => return Err(error.into()),
        }
    }

    let bundles = candidates
        .iter()
        .map(|(_, bundle)| bundle.clone())
        .collect::<Vec<_>>();
    let generations = policy.expired_generations(&bundles, clock);
    let reaped = vault.reaper(credentials).reap(&generations)?;
    let expired_generations = generations
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
    let expired_captures = candidates
        .into_iter()
        .filter_map(|(capture_id, bundle)| {
            expired_generations
                .contains(&bundle.metadata.generation_id)
                .then_some(capture_id)
        })
        .collect::<Vec<_>>();
    let captures_removed = store.delete_captures(&expired_captures)?;

    Ok(RetentionReport {
        generations_reaped: reaped.generations_processed,
        bundles_removed: reaped.bundles_removed,
        captures_removed,
    })
}
