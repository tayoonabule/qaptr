//! Integration tests for the shared domain vocabulary.

use std::time::{Duration as StdDuration, SystemTime};

use qaptr_domain::{ByteSize, CaptureId, Clock, Confidence, Duration, FixedClock};

#[test]
fn ids_reject_empty_values() {
    let error = CaptureId::new("").expect_err("an empty id must be rejected");

    assert_eq!(error.to_string(), "capture id must not be empty");
}

#[test]
fn confidence_rejects_values_above_one() {
    let error = Confidence::new(1.01).expect_err("confidence above one must be rejected");

    assert_eq!(
        error.to_string(),
        "confidence must be finite and between 0 and 1, got 1.01"
    );
}

#[test]
fn fixed_clock_produces_deterministic_timestamps() {
    let start = SystemTime::UNIX_EPOCH + StdDuration::from_secs(42);
    let clock = FixedClock::new(start);

    assert_eq!(clock.now(), start);
}

#[test]
fn scalar_values_preserve_their_units() {
    assert_eq!(ByteSize::new(512).as_u64(), 512);
    assert_eq!(
        Duration::from_millis(1_500).as_std(),
        StdDuration::from_millis(1_500)
    );
}
