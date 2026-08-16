//! Just-in-time provider consent for an analysis session.

use qaptr_policy::ModelId;
use qaptr_provider::{ProviderId, ProviderPayloadKind};

/// The honest label shown when no caller-visible model identifier was
/// resolved, because the provider adapter resolves its own documented
/// default model (for example, a CLI provider with no explicit override).
///
/// This is deliberately never blank or null in a person-facing surface: a
/// missing resolved model is a truthful "provider default" state, not an
/// unknown or absent one.
pub const PROVIDER_DEFAULT_MODEL_LABEL: &str = "provider default";

/// Returns the model identifier to display, or [`PROVIDER_DEFAULT_MODEL_LABEL`]
/// when no explicit model was resolved for this request.
pub fn model_label(resolved_model: Option<&ModelId>) -> String {
    resolved_model.map_or_else(
        || PROVIDER_DEFAULT_MODEL_LABEL.to_owned(),
        ToString::to_string,
    )
}

/// The information shown before the first provider request in a session.
///
/// The resolved model is immutable for the lifetime of one consent request:
/// it is supplied once at construction from the model resolution already
/// performed before consent, and this type exposes no setter that could
/// change it after the person has seen the summary.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConsentRequest {
    provider: ProviderId,
    resolved_model: Option<ModelId>,
    payload_kind: ProviderPayloadKind,
    capture_count: usize,
    image_count: usize,
    exclusion_count: usize,
}

impl ConsentRequest {
    /// Creates a consent request with the exact payload summary to display.
    ///
    /// `resolved_model` is the immutable model resolved for this request
    /// before consent was requested, or `None` when the provider adapter
    /// resolves its own model without a caller-visible identifier.
    /// `payload_kind` reflects whether the prepared payload includes a
    /// masked image, consistent with `image_count`.
    pub fn new(
        provider: ProviderId,
        resolved_model: Option<ModelId>,
        payload_kind: ProviderPayloadKind,
        capture_count: usize,
        image_count: usize,
        exclusion_count: usize,
    ) -> Self {
        Self {
            provider,
            resolved_model,
            payload_kind,
            capture_count,
            image_count,
            exclusion_count,
        }
    }

    /// Returns the selected provider.
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    /// Returns the model resolved for this request, when one was resolved.
    ///
    /// This value cannot change after construction: it is the same model
    /// identifier that will be used for the one provider request this
    /// consent decision governs.
    pub const fn resolved_model(&self) -> Option<&ModelId> {
        self.resolved_model.as_ref()
    }

    /// Returns the resolved model identifier, or the honest
    /// [`PROVIDER_DEFAULT_MODEL_LABEL`] when the provider's own documented
    /// default model will be used instead of a caller-visible identifier.
    pub fn model_label(&self) -> String {
        model_label(self.resolved_model())
    }

    /// Returns the sanitized payload kind requested from the provider.
    pub const fn payload_kind(&self) -> ProviderPayloadKind {
        self.payload_kind
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

#[cfg(test)]
mod tests {
    use super::*;

    fn provider(value: &str) -> ProviderId {
        ProviderId::new(value).expect("test provider id is valid")
    }

    fn model(value: &str) -> ModelId {
        ModelId::new(value).expect("test model id is valid")
    }

    #[test]
    fn resolved_model_reports_the_model_supplied_at_construction() {
        let request = ConsentRequest::new(
            provider("openrouter"),
            Some(model("gpt-test")),
            ProviderPayloadKind::Text,
            3,
            0,
            1,
        );
        assert_eq!(request.resolved_model(), Some(&model("gpt-test")));
        assert_eq!(request.payload_kind(), ProviderPayloadKind::Text);
    }

    #[test]
    fn resolved_model_is_none_when_no_model_was_resolved() {
        let request = ConsentRequest::new(
            provider("codex-cli"),
            None,
            ProviderPayloadKind::Images,
            1,
            1,
            0,
        );
        assert_eq!(request.resolved_model(), None);
        assert_eq!(request.payload_kind(), ProviderPayloadKind::Images);
    }

    #[test]
    fn model_label_reports_the_resolved_model_identifier() {
        let resolved = model("gpt-test");
        assert_eq!(model_label(Some(&resolved)), "gpt-test");
    }

    #[test]
    fn model_label_reports_an_honest_provider_default_when_unresolved() {
        assert_eq!(model_label(None), PROVIDER_DEFAULT_MODEL_LABEL);
        assert_eq!(PROVIDER_DEFAULT_MODEL_LABEL, "provider default");
    }

    #[test]
    fn consent_request_model_label_matches_the_free_function() {
        let with_model = ConsentRequest::new(
            provider("openrouter"),
            Some(model("gpt-test")),
            ProviderPayloadKind::Text,
            1,
            0,
            0,
        );
        assert_eq!(with_model.model_label(), "gpt-test");

        let cli_default = ConsentRequest::new(
            provider("codex-cli"),
            None,
            ProviderPayloadKind::Text,
            1,
            0,
            0,
        );
        assert_eq!(cli_default.model_label(), PROVIDER_DEFAULT_MODEL_LABEL);
    }

    #[test]
    fn consent_request_summary_fields_match_construction_inputs() {
        let request = ConsentRequest::new(
            provider("claude-cli"),
            Some(model("claude-test")),
            ProviderPayloadKind::Images,
            5,
            2,
            3,
        );
        assert_eq!(request.provider(), &provider("claude-cli"));
        assert_eq!(request.capture_count(), 5);
        assert_eq!(request.image_count(), 2);
        assert_eq!(request.exclusion_count(), 3);
    }
}
