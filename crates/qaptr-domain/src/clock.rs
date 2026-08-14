//! The clock port and deterministic clock implementations.

use std::time::SystemTime;

/// Supplies the current instant to domain logic.
pub trait Clock {
    /// Returns the current instant according to this clock.
    fn now(&self) -> SystemTime;
}

/// A clock backed by the operating system's current time.
#[derive(Clone, Copy, Debug, Default)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> SystemTime {
        SystemTime::now()
    }
}

/// A clock that always returns one configured instant.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FixedClock {
    instant: SystemTime,
}

impl FixedClock {
    /// Creates a clock fixed at `instant`.
    pub const fn new(instant: SystemTime) -> Self {
        Self { instant }
    }
}

impl Clock for FixedClock {
    fn now(&self) -> SystemTime {
        self.instant
    }
}
