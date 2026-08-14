//! Generation-oriented retention execution for the encrypted vault.

use std::collections::BTreeSet;

use qaptr_domain::ports::CredentialPort;

use crate::{GenerationId, Result, Vault};

/// Counts the completed work of one retention pass.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ReapReport {
    /// Number of distinct generations processed.
    pub generations_processed: usize,
    /// Number of bundle directories removed by the processed generations.
    pub bundles_removed: usize,
}

/// Executes a retention plan against a vault.
pub struct Reaper<'vault, 'credentials, C> {
    vault: &'vault Vault,
    credentials: &'credentials C,
}

impl<'vault, 'credentials, C: CredentialPort> Reaper<'vault, 'credentials, C> {
    pub(crate) const fn new(vault: &'vault Vault, credentials: &'credentials C) -> Self {
        Self { vault, credentials }
    }

    /// Destroys each generation in `generations`, ignoring duplicate entries.
    ///
    /// A generation is the unit of work because its private key protects all
    /// of its bundles. Each generation call is serialized by the vault lock,
    /// and the operation is idempotent: a second pass reports zero remaining
    /// bundles without failing when the credential is already absent. A caller
    /// may stop between generations and safely resume with the same plan.
    pub fn reap(&self, generations: &[GenerationId]) -> Result<ReapReport> {
        let unique = generations.iter().cloned().collect::<BTreeSet<_>>();
        let mut report = ReapReport::default();
        for generation in unique {
            report.generations_processed += 1;
            report.bundles_removed += self
                .vault
                .destroy_generation(&generation, self.credentials)?;
        }
        Ok(report)
    }
}
