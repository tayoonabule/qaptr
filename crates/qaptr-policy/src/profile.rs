//! Explicit, time-bounded detailed capture profile state.
//!
//! This module owns only the profile window. It does not schedule captures,
//! persist state, render a menu-bar item, or seal bundles. Callers use the
//! returned state to drive those boundaries. The window end is calculated once
//! at explicit activation and is never moved by later clock readings or by a
//! second activation attempt.

use std::time::SystemTime;

use qaptr_domain::{Clock, Duration};
use thiserror::Error;

/// Errors returned while starting or ending a detailed capture profile.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Error)]
pub enum ProfileError {
    /// A detailed profile must have a positive duration.
    #[error("detailed capture profile duration must be greater than zero")]
    InvalidDuration,
    /// The requested duration could not be represented as a `SystemTime`
    /// end bound.
    #[error("detailed capture profile end time overflowed")]
    EndTimeOverflow,
    /// An active profile already owns the capture window.
    #[error("detailed capture profile is already active")]
    AlreadyActive,
    /// There was no active profile to end.
    #[error("detailed capture profile is not active")]
    NotActive,
}

/// The immutable time window granted by an explicit detailed-capture start.
///
/// `ends_at` is fixed at construction. It is intentionally not recomputed from
/// a later `Clock` reading, which prevents a backward-moving wall clock from
/// extending the profile.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DetailedCaptureProfile {
    started_at: SystemTime,
    ends_at: SystemTime,
}

impl DetailedCaptureProfile {
    /// Creates a profile window from a start instant and positive duration.
    ///
    /// Most callers should use [`CaptureProfileLifecycle::start`] so the start
    /// remains explicitly tied to the injected [`Clock`].
    pub fn new(started_at: SystemTime, duration: Duration) -> Result<Self, ProfileError> {
        if duration.as_std().is_zero() {
            return Err(ProfileError::InvalidDuration);
        }
        let ends_at = started_at
            .checked_add(duration.as_std())
            .ok_or(ProfileError::EndTimeOverflow)?;
        Ok(Self {
            started_at,
            ends_at,
        })
    }

    /// Returns the instant at which detailed capture was explicitly started.
    pub const fn started_at(self) -> SystemTime {
        self.started_at
    }

    /// Returns the fixed instant at which detailed capture must end.
    pub const fn ends_at(self) -> SystemTime {
        self.ends_at
    }

    /// Returns whether the profile has reached its fixed end bound.
    pub fn is_expired<C: Clock>(self, clock: &C) -> bool {
        self.is_expired_at(clock.now())
    }

    fn is_expired_at(self, now: SystemTime) -> bool {
        now.duration_since(self.ends_at).is_ok()
    }
}

/// The capture mode exposed to the scheduler and visible-state boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CaptureProfileState {
    /// The helper must use its configured interval capture behavior.
    Interval,
    /// Detailed capture is active until the supplied fixed end bound.
    Detailed {
        /// The instant at which the user started detailed capture.
        started_at: SystemTime,
        /// The instant at which detailed capture ends automatically.
        ends_at: SystemTime,
    },
}

impl CaptureProfileState {
    /// Returns whether detailed capture is active.
    pub const fn is_detailed(self) -> bool {
        matches!(self, Self::Detailed { .. })
    }

    /// Returns the fixed detailed-capture end bound, if active.
    pub const fn ends_at(self) -> Option<SystemTime> {
        match self {
            Self::Interval => None,
            Self::Detailed { ends_at, .. } => Some(ends_at),
        }
    }
}

/// Owns at most one detailed capture profile at a time.
///
/// The lifecycle is intentionally process-local and cloneable profile state is
/// exposed through [`Self::active_profile`]. A caller that persists that small
/// state can restore it with [`Self::from_active_profile`]. On the first state
/// read after a restart, the fixed bound is compared with the injected clock,
/// so a window that elapsed while the app was not running is still expired.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CaptureProfileLifecycle {
    active: Option<DetailedCaptureProfile>,
}

impl CaptureProfileLifecycle {
    /// Creates a lifecycle in configured-interval mode.
    pub const fn new() -> Self {
        Self { active: None }
    }

    /// Restores one previously active profile without changing its end bound.
    ///
    /// The next call to [`Self::state`] or [`Self::start`] reconciles the
    /// restored profile with the supplied clock. This is sufficient for a
    /// restart because no process uptime or timer state is part of the window.
    pub const fn from_active_profile(profile: DetailedCaptureProfile) -> Self {
        Self {
            active: Some(profile),
        }
    }

    /// Explicitly starts one detailed profile using the supplied clock.
    ///
    /// A second start while the first window is active returns
    /// [`ProfileError::AlreadyActive`] and leaves the original end bound
    /// unchanged. If the old window has already expired, it is cleared first
    /// and the new explicit start is accepted.
    pub fn start<C: Clock>(
        &mut self,
        duration: Duration,
        clock: &C,
    ) -> Result<DetailedCaptureProfile, ProfileError> {
        self.reconcile(clock);
        if self.active.is_some() {
            return Err(ProfileError::AlreadyActive);
        }
        let profile = DetailedCaptureProfile::new(clock.now(), duration)?;
        self.active = Some(profile);
        Ok(profile)
    }

    /// Ends detailed capture immediately and returns to configured-interval mode.
    pub fn end(&mut self) -> Result<(), ProfileError> {
        if self.active.take().is_some() {
            Ok(())
        } else {
            Err(ProfileError::NotActive)
        }
    }

    /// Returns the current mode and clears a profile whose bound has elapsed.
    pub fn state<C: Clock>(&mut self, clock: &C) -> CaptureProfileState {
        self.reconcile(clock);
        match self.active {
            Some(profile) => CaptureProfileState::Detailed {
                started_at: profile.started_at(),
                ends_at: profile.ends_at(),
            },
            None => CaptureProfileState::Interval,
        }
    }

    /// Returns the active profile for persistence or restart restoration.
    ///
    /// This accessor does not read a clock. Call [`Self::state`] first when a
    /// caller needs a clock-reconciled value.
    pub const fn active_profile(&self) -> Option<DetailedCaptureProfile> {
        self.active
    }

    fn reconcile<C: Clock>(&mut self, clock: &C) {
        if self.active.is_some_and(|profile| profile.is_expired(clock)) {
            self.active = None;
        }
    }
}
