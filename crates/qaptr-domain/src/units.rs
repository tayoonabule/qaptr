//! Validated scalar domain values.

use std::time::Duration as StdDuration;

use crate::{DomainError, Result};

/// A non-negative number of bytes.
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub struct ByteSize(u64);

impl ByteSize {
    /// Creates a byte size from a raw byte count.
    pub const fn new(bytes: u64) -> Self {
        Self(bytes)
    }

    /// Returns the number of bytes.
    pub const fn as_u64(self) -> u64 {
        self.0
    }
}

/// A non-negative domain duration backed by [`std::time::Duration`].
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub struct Duration(StdDuration);

impl Duration {
    /// Creates a duration from whole seconds.
    pub const fn from_secs(seconds: u64) -> Self {
        Self(StdDuration::from_secs(seconds))
    }

    /// Creates a duration from whole milliseconds.
    pub const fn from_millis(milliseconds: u64) -> Self {
        Self(StdDuration::from_millis(milliseconds))
    }

    /// Returns the duration as a standard-library duration.
    pub const fn as_std(self) -> StdDuration {
        self.0
    }

    /// Returns the duration in whole seconds.
    pub const fn as_secs(self) -> u64 {
        self.0.as_secs()
    }
}

/// A confidence value in the inclusive range from zero to one.
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
pub struct Confidence(f32);

impl Confidence {
    /// Creates a confidence value, rejecting non-finite values and values
    /// outside the inclusive range from zero to one.
    pub fn new(value: f32) -> Result<Self> {
        if value.is_finite() && (0.0..=1.0).contains(&value) {
            Ok(Self(value))
        } else {
            Err(DomainError::InvalidConfidence { value })
        }
    }

    /// Returns the confidence as a floating-point value.
    pub const fn as_f32(self) -> f32 {
        self.0
    }
}

impl TryFrom<f32> for Confidence {
    type Error = DomainError;

    fn try_from(value: f32) -> std::result::Result<Self, Self::Error> {
        Self::new(value)
    }
}
