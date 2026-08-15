//! Explicit executable discovery without consulting a login shell.

use std::{path::PathBuf, sync::Arc};

use qaptr_provider::{ExecutablePath, ProviderError, ProviderId};
use thiserror::Error;

/// The result of checking one executable name without starting it.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExecutableProbeStatus {
    /// The search could not be completed because one or more candidates were
    /// inaccessible.
    Unavailable,
    /// The search completed and no executable was found.
    NotInstalled,
    /// An executable was found and its absolute path was resolved.
    Detected(ExecutablePath),
}

/// Errors produced while resolving a local CLI executable.
#[derive(Debug, Error)]
pub enum DiscoveryError {
    /// No executable with the requested name was found in the supplied paths.
    #[error("executable {name:?} was not found in the explicit search paths")]
    NotFound {
        /// Requested executable name.
        name: String,
    },
    /// The requested executable name was not a safe single path component.
    #[error("executable name must be a single relative path component: {name:?}")]
    InvalidName {
        /// Rejected executable name.
        name: String,
    },
    /// Filesystem metadata could not be read while searching.
    #[error("could not inspect executable candidate {path}: {source}")]
    Metadata {
        /// Candidate path that could not be inspected.
        path: PathBuf,
        /// Underlying metadata error.
        #[source]
        source: std::io::Error,
    },
}

/// Resolves CLI names using only directories explicitly provided by the app.
#[derive(Clone, Debug)]
pub struct ExecutableDiscovery {
    search_paths: Arc<[PathBuf]>,
}

impl ExecutableDiscovery {
    /// Creates a discovery object. The paths are not read until [`Self::find`].
    pub fn new(search_paths: impl IntoIterator<Item = PathBuf>) -> Self {
        Self {
            search_paths: search_paths.into_iter().collect(),
        }
    }

    /// Resolves a program name without consulting `PATH` or a shell.
    pub fn find(&self, name: &str) -> Result<ExecutablePath, DiscoveryError> {
        if name.is_empty()
            || name == "."
            || name == ".."
            || name.contains('/')
            || name.contains(std::path::MAIN_SEPARATOR)
        {
            return Err(DiscoveryError::InvalidName {
                name: name.to_owned(),
            });
        }

        for directory in &*self.search_paths {
            let candidate = directory.join(name);
            let metadata = candidate
                .metadata()
                .map_err(|source| DiscoveryError::Metadata {
                    path: candidate.clone(),
                    source,
                });
            let Ok(metadata) = metadata else {
                continue;
            };
            if metadata.is_file() && is_executable(&metadata) {
                let absolute =
                    candidate
                        .canonicalize()
                        .map_err(|source| DiscoveryError::Metadata {
                            path: candidate.clone(),
                            source,
                        })?;
                let value = absolute.to_string_lossy().into_owned();
                return ExecutablePath::new(value).map_err(|_| DiscoveryError::Metadata {
                    path: absolute,
                    source: std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        "canonical executable path was not absolute",
                    ),
                });
            }
        }

        Err(DiscoveryError::NotFound {
            name: name.to_owned(),
        })
    }

    /// Checks for an executable without invoking it.
    ///
    /// Unlike [`Self::find`], this preserves an inaccessible candidate as
    /// `Unavailable` instead of collapsing it into `NotInstalled`. This is
    /// the truthful, scalar surface used by app-facing status displays.
    pub fn probe(&self, name: &str) -> ExecutableProbeStatus {
        if name.is_empty()
            || name == "."
            || name == ".."
            || name.contains('/')
            || name.contains(std::path::MAIN_SEPARATOR)
        {
            return ExecutableProbeStatus::Unavailable;
        }

        let mut inaccessible = false;
        for directory in &*self.search_paths {
            let candidate = directory.join(name);
            let metadata = match candidate.metadata() {
                Ok(metadata) => metadata,
                Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
                    inaccessible = true;
                    continue;
                }
                Err(_) => continue,
            };
            if !metadata.is_file() || !is_executable(&metadata) {
                continue;
            }

            let Ok(absolute) = candidate.canonicalize() else {
                return ExecutableProbeStatus::Unavailable;
            };
            let value = absolute.to_string_lossy().into_owned();
            return match ExecutablePath::new(value) {
                Ok(path) => ExecutableProbeStatus::Detected(path),
                Err(_) => ExecutableProbeStatus::Unavailable,
            };
        }

        if inaccessible {
            ExecutableProbeStatus::Unavailable
        } else {
            ExecutableProbeStatus::NotInstalled
        }
    }

    /// Resolves an executable and maps absence into U13's provider taxonomy.
    pub fn find_for_provider(
        &self,
        provider: &ProviderId,
        name: &str,
    ) -> Result<ExecutablePath, ProviderError> {
        self.find(name).map_err(|error| match error {
            DiscoveryError::NotFound { .. } => ProviderError::NotInstalled {
                provider: provider.clone(),
            },
            _ => ProviderError::RuntimeFailure {
                provider: provider.clone(),
                kind: qaptr_provider::RuntimeFailureKind::Detection,
            },
        })
    }
}

#[cfg(unix)]
fn is_executable(metadata: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o111 != 0
}

#[cfg(not(unix))]
fn is_executable(_metadata: &std::fs::Metadata) -> bool {
    true
}
