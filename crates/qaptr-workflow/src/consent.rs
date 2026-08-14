//! Just-in-time provider consent for an analysis session.

use qaptr_provider::ProviderId;

/// The information shown before the first provider request in a session.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConsentRequest {
    provider: ProviderId,
    capture_count: usize,
    image_count: usize,
    exclusion_count: usize,
}

impl ConsentRequest {
    /// Creates a consent request with the exact payload summary to display.
    pub fn new(
        provider: ProviderId,
        capture_count: usize,
        image_count: usize,
        exclusion_count: usize,
    ) -> Self {
        Self {
            provider,
            capture_count,
            image_count,
            exclusion_count,
        }
    }

    /// Returns the selected provider.
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    /// Returns the number of captures prepared for this request.
    pub const fn capture_count(&self) -> usize {
        self.capture_count
    }

    /// Returns the number of masked image payloads included in this request.
    pub const fn image_count(&self) -> usize {
        self.image_count
    }

    /// Returns the number of captures excluded by the local privacy gate.
    pub const fn exclusion_count(&self) -> usize {
        self.exclusion_count
    }
}

/// The person's decision about sending prepared data to a provider.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ConsentDecision {
    /// Permit provider requests for the current analysis session.
    Granted,
    /// Keep all preparation local and make no provider request.
    Declined,
}

/// The review app's consent prompt boundary.
pub trait ConsentPort {
    /// Requests consent immediately before the first provider invocation.
    fn request(&self, request: &ConsentRequest) -> ConsentDecision;
}
