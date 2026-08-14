//! Small, bounded version probes used by future concrete CLI adapters.

use std::str::FromStr;

use qaptr_provider::{ProviderError, ProviderId, ProviderVersion};
use thiserror::Error;

/// Errors produced when parsing a CLI version line.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum VersionProbeError {
    /// No dotted numeric version was found in the output.
    #[error("no semantic version was found in CLI output")]
    Missing,
    /// A version component was outside the range accepted by the provider contract.
    #[error("CLI version component is not a valid unsigned integer")]
    InvalidComponent,
}

/// Parses the first `major.minor.patch` sequence in CLI output.
pub fn parse_version(output: &str) -> Result<ProviderVersion, VersionProbeError> {
    output
        .split_whitespace()
        .map(|token| {
            token.trim_matches(|character: char| !character.is_ascii_digit() && character != '.')
        })
        .find_map(|token| {
            let mut components = token.split('.');
            let major = components.next()?.parse::<u32>().ok()?;
            let minor = components.next()?.parse::<u32>().ok()?;
            let patch = components.next()?.parse::<u32>().ok()?;
            if components.next().is_some() {
                return None;
            }
            Some(ProviderVersion::new(major, minor, patch))
        })
        .ok_or(VersionProbeError::Missing)
}

/// A typed version probe result that maps cleanly onto U13's taxonomy.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VersionProbe {
    version: ProviderVersion,
}

impl VersionProbe {
    /// Parses a version probe result.
    pub fn new(output: &str) -> Result<Self, VersionProbeError> {
        Ok(Self {
            version: parse_version(output)?,
        })
    }

    /// Returns the parsed version.
    pub const fn version(self) -> ProviderVersion {
        self.version
    }

    /// Converts malformed probe output into the shared provider taxonomy.
    pub fn into_provider_result(
        self,
        provider: &ProviderId,
    ) -> Result<ProviderVersion, ProviderError> {
        if self.version == ProviderVersion::new(0, 0, 0) {
            return Err(ProviderError::RuntimeFailure {
                provider: provider.clone(),
                kind: qaptr_provider::RuntimeFailureKind::VersionUnavailable,
            });
        }
        Ok(self.version)
    }
}

impl FromStr for VersionProbe {
    type Err = VersionProbeError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::new(value)
    }
}
