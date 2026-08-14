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
//! - A detailed capture profile is explicitly started, owns one immutable end
//!   bound, and returns to sparse mode once that bound is reached.
//! - Profile expiry is evaluated through [`qaptr_domain::Clock`], so a review
//!   app restart cannot make an already-ended window active again.

mod exclusions;
mod profile;
mod retention;

pub use exclusions::{
    seal_if_allowed, CaptureDecision, ExclusionReason, ExclusionRules, PolicyError,
};
pub use profile::{
    CaptureProfileLifecycle, CaptureProfileState, DetailedCaptureProfile, ProfileError,
};
pub use retention::{
    enforce_retention, RetentionBundle, RetentionError, RetentionPolicy, RetentionReport,
};
