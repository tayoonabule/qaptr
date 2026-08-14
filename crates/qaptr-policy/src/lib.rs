//! Deterministic capture eligibility and retention policy for Qaptr.
//!
//! # Invariants
//!
//! - Policy decisions contain no image bytes, filesystem handles, or platform
//!   types.
//! - Retention reads time only through the [`qaptr_domain::Clock`] port.
//! - A clock that moves backwards never marks a bundle expired.
//! - Excluded applications and windows are rejected before the vault seal
//!   operation is called.
//! - Exclusion notices use only counts and reason categories. They never carry
//!   application names, window titles, capture ids, or payload material.

mod exclusions;
mod retention;

pub use exclusions::{
    CaptureDecision, ExclusionReason, ExclusionRules, PolicyError, seal_if_allowed,
};
pub use retention::{
    RetentionBundle, RetentionError, RetentionPolicy, RetentionReport, enforce_retention,
};
