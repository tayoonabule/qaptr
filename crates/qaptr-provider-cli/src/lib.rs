//! Safe local execution primitives for already-authenticated CLI providers.
//!
//! This crate owns process isolation, not provider-specific command lines. It
//! never accepts credentials, never invokes a shell, never inherits the
//! caller's environment, and never returns unbounded child output. Provider
//! adapters can use [`CliRuntime::run_for_provider`] from their existing
//! [`qaptr_provider::ProviderAdapter`] implementation without changing that
//! trait.
//!
//! # Invariants
//!
//! * Every child is started through `/usr/bin/sandbox-exec` with a generated
//!   deny-by-default profile.
//! * The child receives an explicitly cleared environment and only the
//!   variables supplied by the caller.
//! * Arguments are passed as operating-system argument values. No command
//!   string is ever parsed or interpolated by a shell.
//! * A child that exceeds its wall-clock or output budget is terminated, and
//!   the process group is signalled so descendants do not remain orphaned.
//! * The runtime owns an empty temporary working directory and removes it
//!   after each invocation.

pub mod adapters;
pub mod detection;
mod discovery;
mod probe;
mod runtime;

pub use detection::{
    CliDetectionStatus, CliPathProbe, CliProcessProbe, CliProvider, detect_cli,
    detect_cli_installation, detect_cli_with_process_probe,
};
pub use discovery::{DiscoveryError, ExecutableDiscovery, ExecutableProbeStatus};
pub use probe::{VersionProbe, VersionProbeError, parse_version};
pub use runtime::{
    CliInvocation, CliOutput, CliRuntime, CliRuntimeError, OutputLimit, RuntimeLimits, Timeout,
};
