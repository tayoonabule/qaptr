//! Shared, platform-independent vocabulary for Qaptr.
//!
//! The domain crate contains no operating-system types, I/O, networking, image
//! bytes, provider code, or UI code. Its public values are validated at
//! construction so later crates can exchange typed domain data without
//! repeating basic invariant checks. Time is obtained through [`Clock`] so
//! domain logic can remain deterministic in tests.

mod units;

pub mod clock;
pub mod error;
pub mod ids;

pub use clock::{Clock, FixedClock, SystemClock};
pub use error::{DomainError, Result};
pub use ids::{CaptureId, ObservationId, SessionId, WorkflowId};
pub use units::{ByteSize, Confidence, Duration};
