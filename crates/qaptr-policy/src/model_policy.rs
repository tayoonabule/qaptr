//! Typed, versioned model-selection policy.
//!
//! This module resolves which model a provider request should use from a
//! preferred default, an explicit fallback order, and an optional user
//! override. Resolution is pure: it never fetches a model catalog, never
//! contacts a provider, and never runs before consent. Callers (the
//! OpenRouter catalog transport, a CLI adapter's default-model lookup, or a
//! settings UI) are responsible for producing the already-known validated
//! model set and provider-readiness input passed to [`resolve_model`], or a
//! [`ModelCatalog`] snapshot passed to [`resolve_from_catalog`].
//!
//! # Invariants
//!
//! - [`ModelPolicy`] is versioned so a future fallback-semantics change is
//!   explicit and comparable, never a silent behavior change.
//! - An explicit override that the caller did not validate blocks resolution
//!   with [`ModelReadiness::OverrideUnavailable`] rather than silently
//!   substituting the preferred or a fallback model.
//! - A stale or unavailable catalog blocks resolution rather than resolving
//!   to a possibly-wrong cached model.
//! - [`ModelCatalog`] freshness is derived only through the [`qaptr_domain::Clock`]
//!   port; a non-monotonic clock can delay recognizing staleness but never
//!   fabricates freshness.
//! - [`resolve_model`] and [`resolve_from_catalog`] perform no I/O and require
//!   no credential, network client, or provider adapter.

use std::{fmt, time::SystemTime};

use qaptr_domain::{Clock, Duration};
use thiserror::Error;

/// Errors returned while constructing model-policy configuration values.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum ModelPolicyError {
    /// A required textual field was empty.
    #[error("{field} must not be empty")]
    EmptyField {
        /// The name of the empty field.
        field: &'static str,
    },
}

/// A stable, non-empty model identifier as reported by a provider or CLI.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct ModelId(String);

impl ModelId {
    /// Creates a model identifier, rejecting an empty value.
    pub fn new(value: impl Into<String>) -> Result<Self, ModelPolicyError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(ModelPolicyError::EmptyField { field: "model id" });
        }
        Ok(Self(value))
    }

    /// Returns the model identifier.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ModelId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

/// The current model-policy schema version.
///
/// Bump [`PolicyVersion::CURRENT`] whenever fallback-selection semantics
/// change so a persisted policy from an older build is recognizably stale
/// rather than silently reinterpreted.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PolicyVersion(u32);

impl PolicyVersion {
    /// The model-policy schema version produced by this build.
    pub const CURRENT: Self = Self(1);

    /// Returns the raw version number.
    pub const fn value(self) -> u32 {
        self.0
    }
}

/// A versioned, ordered preferred-then-fallback model list for one provider.
///
/// The list contains no secret material and no network endpoint; it is safe
/// to persist as non-secret configuration.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ModelPolicy {
    version: PolicyVersion,
    preferred: ModelId,
    fallbacks: Vec<ModelId>,
}

impl ModelPolicy {
    /// Creates a policy at the current schema version.
    pub const fn new(preferred: ModelId, fallbacks: Vec<ModelId>) -> Self {
        Self {
            version: PolicyVersion::CURRENT,
            preferred,
            fallbacks,
        }
    }

    /// Creates a single-model policy with no fallback ordering.
    ///
    /// This is the shape used for a CLI provider whose adapter resolves its
    /// own documented default model rather than offering a fallback list.
    pub const fn single(preferred: ModelId) -> Self {
        Self::new(preferred, Vec::new())
    }

    /// Returns the schema version this policy was constructed at.
    pub const fn version(&self) -> PolicyVersion {
        self.version
    }

    /// Returns the versioned preferred model.
    pub fn preferred(&self) -> &ModelId {
        &self.preferred
    }

    /// Returns the fallback models in selection order.
    pub fn fallbacks(&self) -> &[ModelId] {
        &self.fallbacks
    }
}

/// Provider-side readiness supplied by the caller before model resolution.
///
/// This intentionally mirrors provider readiness, not model readiness, so a
/// missing/unauthenticated provider is never conflated with an unavailable
/// model.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProviderReadinessInput {
    /// No provider has been selected yet.
    NoProvider,
    /// The selected provider failed its handshake or detection.
    ProviderUnavailable,
    /// The provider is installed/configured but has no usable login.
    AuthenticationNeeded,
    /// The provider passed its handshake and can be asked to resolve a model.
    Ready,
}

/// The already-known, already-validated model set used for resolution.
///
/// `catalog_fresh` covers both "the OpenRouter catalog fetch succeeded within
/// its freshness window" and "the CLI's own default-model lookup succeeded".
/// `validated` must contain only models that satisfied the required
/// structured-output/capability check; this type performs no such check
/// itself.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ModelAvailability {
    validated: Vec<ModelId>,
    catalog_fresh: bool,
}

impl ModelAvailability {
    /// Creates an availability snapshot from an already-validated model list.
    pub const fn new(validated: Vec<ModelId>, catalog_fresh: bool) -> Self {
        Self {
            validated,
            catalog_fresh,
        }
    }

    /// Returns whether the supplied model was validated.
    pub fn contains(&self, model: &ModelId) -> bool {
        self.validated.contains(model)
    }
}

/// A model catalog/configuration snapshot with a bounded freshness window.
///
/// This is the pure, time-based companion to [`ModelAvailability`]. Instead of
/// requiring every caller to compute its own `catalog_fresh` boolean, a
/// catalog transport (the OpenRouter catalog fetch, a CLI adapter's own
/// default-model lookup) records the already-validated model list plus the
/// instant it was fetched, and freshness is derived only through the injected
/// [`Clock`]. This type performs no I/O, holds no credential, and contacts no
/// provider or catalog endpoint itself.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ModelCatalog {
    validated: Vec<ModelId>,
    fetched_at: SystemTime,
    freshness_window: Duration,
}

impl ModelCatalog {
    /// Creates a catalog snapshot from an already-validated model list, the
    /// instant it was fetched, and the duration it remains usable for.
    pub const fn new(
        validated: Vec<ModelId>,
        fetched_at: SystemTime,
        freshness_window: Duration,
    ) -> Self {
        Self {
            validated,
            fetched_at,
            freshness_window,
        }
    }

    /// Returns whether the supplied model was validated in this snapshot.
    pub fn contains(&self, model: &ModelId) -> bool {
        self.validated.contains(model)
    }

    /// Returns the validated models recorded in this snapshot.
    pub fn validated(&self) -> &[ModelId] {
        &self.validated
    }

    /// Returns the instant this snapshot was fetched.
    pub const fn fetched_at(&self) -> SystemTime {
        self.fetched_at
    }

    /// Returns whether this snapshot is still within its freshness window at
    /// the instant supplied by `clock`.
    ///
    /// A clock reading at or before `fetched_at` (including one that moved
    /// backwards) is treated as stale rather than fresh, matching the
    /// retention policy's fail-closed handling of a non-monotonic clock: it
    /// can delay recognizing staleness but never fabricate freshness.
    pub fn is_fresh<C: Clock>(&self, clock: &C) -> bool {
        self.is_fresh_at(clock.now())
    }

    fn is_fresh_at(&self, now: SystemTime) -> bool {
        match now.duration_since(self.fetched_at) {
            Ok(age) => age < self.freshness_window.as_std(),
            Err(_) => false,
        }
    }

    /// Converts this snapshot into the [`ModelAvailability`] input required by
    /// [`resolve_model`], evaluating freshness through `clock`.
    pub fn availability<C: Clock>(&self, clock: &C) -> ModelAvailability {
        ModelAvailability::new(self.validated.clone(), self.is_fresh(clock))
    }
}

/// The resolved model-readiness state shown to the person and recorded in
/// result metadata, with a concise machine-checkable reason.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ModelReadiness {
    /// No provider has been selected.
    NoProvider,
    /// The provider itself is unavailable; model resolution did not run.
    ProviderUnavailable,
    /// The provider needs authentication before a model can be resolved.
    AuthenticationNeeded,
    /// The model catalog/configuration lookup is stale or unavailable.
    CatalogStaleOrUnavailable,
    /// The preferred model was unavailable; a validated fallback was chosen.
    PreferredUnavailableWithFallback {
        /// The fallback model selected instead of the preferred model.
        selected: ModelId,
    },
    /// An explicit user override was requested but is not validated.
    ///
    /// Resolution stops here rather than silently falling back, so analysis
    /// cannot proceed with a model the person did not choose.
    OverrideUnavailable {
        /// The unavailable override the person configured.
        requested: ModelId,
    },
    /// A specific model was resolved and is safe to use for one request.
    Ready {
        /// The resolved model.
        model: ModelId,
    },
}

/// A non-blocking notice emitted when the preferred model is unavailable.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ModelReadinessNotice {
    /// A validated fallback was selected in the policy's declared order.
    FallbackSelected {
        /// The fallback model selected for the request.
        selected: ModelId,
    },
}

impl ModelReadinessNotice {
    /// Returns the concise notice suitable for a status surface or log.
    pub fn text(&self) -> String {
        match self {
            Self::FallbackSelected { selected } => {
                format!("Preferred model unavailable; using fallback model {selected}.")
            }
        }
    }
}

impl ModelReadiness {
    /// Returns the resolved model, if resolution reached a ready state.
    pub const fn model(&self) -> Option<&ModelId> {
        match self {
            Self::Ready { model } | Self::PreferredUnavailableWithFallback { selected: model } => {
                Some(model)
            }
            _ => None,
        }
    }

    /// Returns whether resolution reached a state safe to invoke a provider.
    pub const fn is_ready(&self) -> bool {
        matches!(
            self,
            Self::Ready { .. } | Self::PreferredUnavailableWithFallback { .. }
        )
    }

    /// Returns whether resolution is blocked by an error state.
    pub const fn is_error(&self) -> bool {
        matches!(
            self,
            Self::ProviderUnavailable
                | Self::AuthenticationNeeded
                | Self::CatalogStaleOrUnavailable
                | Self::OverrideUnavailable { .. }
        )
    }

    /// Returns the non-blocking notice produced by fallback selection.
    pub fn notice(&self) -> Option<ModelReadinessNotice> {
        match self {
            Self::PreferredUnavailableWithFallback { selected } => {
                Some(ModelReadinessNotice::FallbackSelected {
                    selected: selected.clone(),
                })
            }
            _ => None,
        }
    }
}

/// Resolves a model from policy, an optional override, and known-validated
/// availability, performing no I/O and no provider or catalog request.
///
/// Order of checks: provider readiness, catalog freshness, explicit override,
/// preferred model, then fallbacks in order. An override always takes
/// precedence over the preferred/fallback policy and never falls back
/// silently when invalid.
pub fn resolve_model(
    policy: &ModelPolicy,
    override_model: Option<&ModelId>,
    availability: &ModelAvailability,
    provider: ProviderReadinessInput,
) -> ModelReadiness {
    match provider {
        ProviderReadinessInput::NoProvider => return ModelReadiness::NoProvider,
        ProviderReadinessInput::ProviderUnavailable => {
            return ModelReadiness::ProviderUnavailable;
        }
        ProviderReadinessInput::AuthenticationNeeded => {
            return ModelReadiness::AuthenticationNeeded;
        }
        ProviderReadinessInput::Ready => {}
    }
    if !availability.catalog_fresh {
        return ModelReadiness::CatalogStaleOrUnavailable;
    }
    if let Some(requested) = override_model {
        return if availability.contains(requested) {
            ModelReadiness::Ready {
                model: requested.clone(),
            }
        } else {
            ModelReadiness::OverrideUnavailable {
                requested: requested.clone(),
            }
        };
    }
    if availability.contains(policy.preferred()) {
        return ModelReadiness::Ready {
            model: policy.preferred().clone(),
        };
    }
    for fallback in policy.fallbacks() {
        if availability.contains(fallback) {
            return ModelReadiness::PreferredUnavailableWithFallback {
                selected: fallback.clone(),
            };
        }
    }
    ModelReadiness::CatalogStaleOrUnavailable
}

/// Resolves a model directly from a [`ModelCatalog`] snapshot, deriving
/// catalog freshness through `clock` before delegating to [`resolve_model`].
///
/// This is the integration entry point a settings UI or CLI adapter should
/// call once it has a versioned policy, an optional override, and a catalog
/// snapshot from its own transport. It performs no I/O itself: freshness is a
/// pure function of the snapshot's `fetched_at` instant and the supplied
/// clock.
pub fn resolve_from_catalog<C: Clock>(
    policy: &ModelPolicy,
    override_model: Option<&ModelId>,
    catalog: &ModelCatalog,
    provider: ProviderReadinessInput,
    clock: &C,
) -> ModelReadiness {
    let availability = catalog.availability(clock);
    resolve_model(policy, override_model, &availability, provider)
}

#[cfg(test)]
mod tests {
    use std::time::{Duration as StdDuration, UNIX_EPOCH};

    use qaptr_domain::FixedClock;

    use super::*;

    fn model(value: &str) -> ModelId {
        ModelId::new(value).expect("test model id is valid")
    }

    fn policy() -> ModelPolicy {
        ModelPolicy::new(
            model("preferred"),
            vec![model("fallback-1"), model("fallback-2")],
        )
    }

    fn instant(seconds: u64) -> SystemTime {
        UNIX_EPOCH + StdDuration::from_secs(seconds)
    }

    #[test]
    fn empty_model_id_is_rejected() {
        assert_eq!(
            ModelId::new("   "),
            Err(ModelPolicyError::EmptyField { field: "model id" })
        );
    }

    #[test]
    fn policy_reports_the_current_version() {
        assert_eq!(policy().version().value(), PolicyVersion::CURRENT.value());
    }

    #[test]
    fn no_provider_short_circuits_before_catalog_or_override_checks() {
        let availability = ModelAvailability::new(vec![], false);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::NoProvider,
        );
        assert_eq!(readiness, ModelReadiness::NoProvider);
        assert!(!readiness.is_ready());
    }

    #[test]
    fn provider_unavailable_blocks_resolution() {
        let availability = ModelAvailability::new(vec![model("preferred")], true);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::ProviderUnavailable,
        );
        assert_eq!(readiness, ModelReadiness::ProviderUnavailable);
    }

    #[test]
    fn authentication_needed_blocks_resolution() {
        let availability = ModelAvailability::new(vec![model("preferred")], true);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::AuthenticationNeeded,
        );
        assert_eq!(readiness, ModelReadiness::AuthenticationNeeded);
    }

    #[test]
    fn stale_catalog_blocks_resolution_even_when_preferred_would_validate() {
        let availability = ModelAvailability::new(vec![model("preferred")], false);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(readiness, ModelReadiness::CatalogStaleOrUnavailable);
    }

    #[test]
    fn malformed_catalog_with_no_validated_models_is_stale_or_unavailable() {
        let availability = ModelAvailability::new(vec![], true);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(readiness, ModelReadiness::CatalogStaleOrUnavailable);
    }

    #[test]
    fn preferred_model_is_selected_when_validated() {
        let availability = ModelAvailability::new(vec![model("preferred")], true);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(
            readiness,
            ModelReadiness::Ready {
                model: model("preferred")
            }
        );
        assert!(readiness.is_ready());
        assert_eq!(readiness.model(), Some(&model("preferred")));
    }

    #[test]
    fn first_validated_fallback_is_selected_when_preferred_is_unavailable() {
        let availability = ModelAvailability::new(vec![model("fallback-2")], true);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(
            readiness,
            ModelReadiness::PreferredUnavailableWithFallback {
                selected: model("fallback-2")
            }
        );
        assert!(readiness.is_ready());
        assert_eq!(
            readiness.notice(),
            Some(ModelReadinessNotice::FallbackSelected {
                selected: model("fallback-2")
            })
        );
        assert_eq!(
            readiness.notice().expect("fallback notice").text(),
            "Preferred model unavailable; using fallback model fallback-2."
        );
    }

    #[test]
    fn fallback_order_prefers_the_earlier_entry_when_both_validate() {
        let availability =
            ModelAvailability::new(vec![model("fallback-1"), model("fallback-2")], true);
        let readiness = resolve_model(
            &policy(),
            None,
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(
            readiness,
            ModelReadiness::PreferredUnavailableWithFallback {
                selected: model("fallback-1")
            }
        );
    }

    #[test]
    fn unavailable_override_blocks_resolution_without_falling_back() {
        let availability = ModelAvailability::new(vec![model("preferred")], true);
        let override_model = model("explicit-override");
        let readiness = resolve_model(
            &policy(),
            Some(&override_model),
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(
            readiness,
            ModelReadiness::OverrideUnavailable {
                requested: model("explicit-override")
            }
        );
        assert!(!readiness.is_ready());
        assert!(readiness.is_error());
        assert!(readiness.notice().is_none());
    }

    #[test]
    fn validated_override_takes_precedence_over_the_preferred_model() {
        let availability =
            ModelAvailability::new(vec![model("preferred"), model("explicit-override")], true);
        let override_model = model("explicit-override");
        let readiness = resolve_model(
            &policy(),
            Some(&override_model),
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(
            readiness,
            ModelReadiness::Ready {
                model: model("explicit-override")
            }
        );
    }

    #[test]
    fn cli_provider_default_policy_resolves_with_no_fallback_list() {
        let cli_policy = ModelPolicy::single(model("cli-default"));
        let availability = ModelAvailability::new(vec![model("cli-default")], true);
        let readiness = resolve_model(
            &cli_policy,
            None,
            &availability,
            ProviderReadinessInput::Ready,
        );
        assert_eq!(
            readiness,
            ModelReadiness::Ready {
                model: model("cli-default")
            }
        );
        assert!(cli_policy.fallbacks().is_empty());
    }

    #[test]
    fn catalog_is_fresh_strictly_within_its_window() {
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        assert!(catalog.is_fresh(&FixedClock::new(instant(100))));
        assert!(catalog.is_fresh(&FixedClock::new(instant(159))));
    }

    #[test]
    fn catalog_is_stale_once_the_freshness_window_elapses() {
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        assert!(!catalog.is_fresh(&FixedClock::new(instant(160))));
        assert!(!catalog.is_fresh(&FixedClock::new(instant(500))));
    }

    #[test]
    fn catalog_is_stale_when_the_clock_moved_backwards() {
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        assert!(!catalog.is_fresh(&FixedClock::new(instant(50))));
    }

    #[test]
    fn catalog_availability_reflects_freshness_and_validated_models() {
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        let fresh = catalog.availability(&FixedClock::new(instant(100)));
        assert!(fresh.contains(&model("preferred")));
        assert!(!fresh.contains(&model("other")));

        let stale = catalog.availability(&FixedClock::new(instant(1_000)));
        assert!(stale.contains(&model("preferred")));
        assert_eq!(catalog.validated(), &[model("preferred")]);
        assert_eq!(catalog.fetched_at(), instant(100));
    }

    #[test]
    fn resolve_from_catalog_selects_the_preferred_model_when_fresh() {
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        let readiness = resolve_from_catalog(
            &policy(),
            None,
            &catalog,
            ProviderReadinessInput::Ready,
            &FixedClock::new(instant(100)),
        );
        assert_eq!(
            readiness,
            ModelReadiness::Ready {
                model: model("preferred")
            }
        );
    }

    #[test]
    fn resolve_from_catalog_blocks_resolution_once_the_catalog_is_stale() {
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        let readiness = resolve_from_catalog(
            &policy(),
            None,
            &catalog,
            ProviderReadinessInput::Ready,
            &FixedClock::new(instant(1_000)),
        );
        assert_eq!(readiness, ModelReadiness::CatalogStaleOrUnavailable);
    }

    #[test]
    fn resolve_from_catalog_short_circuits_on_provider_readiness_before_freshness() {
        // Even a stale catalog must not mask a NoProvider/unavailable state:
        // provider readiness is checked first inside resolve_model.
        let catalog = ModelCatalog::new(
            vec![model("preferred")],
            instant(100),
            Duration::from_secs(60),
        );
        let readiness = resolve_from_catalog(
            &policy(),
            None,
            &catalog,
            ProviderReadinessInput::NoProvider,
            &FixedClock::new(instant(1_000)),
        );
        assert_eq!(readiness, ModelReadiness::NoProvider);
    }
}
