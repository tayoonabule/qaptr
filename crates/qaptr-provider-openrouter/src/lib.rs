//! OpenRouter's BYOK provider adapter.
//!
//! The adapter owns no API key. It retains only the credential-port key name and
//! reads the secret for the duration of detection or invocation. It never writes
//! credentials, persists HTTP responses, or accepts raw capture bytes.
//!
//! # Invariants
//!
//! * Every provider call enters through [`qaptr_provider::ProviderGate`]. The
//!   private invocation proof in U13 prevents callers from constructing a direct
//!   adapter invocation.
//! * The credential value exists only in the stack of one transport call and is
//!   never stored in the adapter or serialized into diagnostics.
//! * HTTP failures and malformed JSON are returned as typed provider failures.

mod catalog;
mod client;

pub use OpenRouterCatalogCache as CatalogCache;
pub use catalog::{CATALOG_ENDPOINT, CatalogParseError, MAX_CATALOG_MODELS, parse_catalog};
pub use client::{
    CatalogTransport, HttpResponse, HttpTransport, MAX_RESPONSE_BYTES, OpenRouterHttpClient,
    TransportError,
};

use std::time::SystemTime;

use qaptr_domain::{
    Duration, FixedClock,
    ports::{CredentialKey, CredentialPort, PortOutcome},
};
use qaptr_policy::ModelCatalog;
use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, CapabilityDescriptor, ProviderAdapter,
    ProviderDescriptor, ProviderDetection, ProviderEndpoint, ProviderError, ProviderId,
    ProviderInvocation, ProviderLocation, ProviderRequestError, ProviderVersion, RawObservation,
    RawProviderResponse, RawWorkflow, RuntimeFailureKind,
};
use serde_json::{Value, json};
use thiserror::Error;

const PROVIDER_ID: &str = "openrouter";
const DISPLAY_NAME: &str = "OpenRouter";
const ENDPOINT: &str = "https://openrouter.ai/api/v1/chat/completions";
const CREDENTIAL_NAME: &str = "openrouter.api_key";
const MINIMUM_VERSION: ProviderVersion = ProviderVersion::new(1, 0, 0);

/// Errors raised while constructing an OpenRouter adapter.
#[derive(Debug, Error)]
pub enum OpenRouterConfigError {
    /// A U13 provider value could not be constructed.
    #[error("invalid OpenRouter provider configuration: {0}")]
    Provider(#[from] ProviderRequestError),
    /// The credential port rejected the fixed logical key.
    #[error("invalid OpenRouter credential key: {0}")]
    CredentialKey(#[source] qaptr_domain::DomainError),
}

/// Errors returned while fetching or validating the OpenRouter model catalog.
#[derive(Debug, Error)]
pub enum OpenRouterCatalogError {
    /// The credential port or provider readiness check failed.
    #[error("OpenRouter catalog authentication failed: {0}")]
    Provider(#[from] ProviderError),
    /// The catalog transport failed without retaining its response body.
    #[error("OpenRouter catalog transport failed: {0}")]
    Transport(#[from] TransportError),
    /// OpenRouter rate-limited the catalog request.
    #[error("OpenRouter catalog request was rate limited")]
    RateLimited,
    /// OpenRouter returned a non-success status other than rate limiting.
    #[error("OpenRouter catalog request returned an unsuccessful status")]
    HttpStatus,
    /// The response did not contain a safe compatible model set.
    #[error("OpenRouter catalog response was rejected: {0}")]
    Parse(#[from] CatalogParseError),
}

/// A bounded, single-entry cache for validated OpenRouter catalog snapshots.
///
/// The cache stores only the policy-safe [`ModelCatalog`] projection. It does
/// not store credentials, provider responses, or endpoint metadata. Each
/// lookup still reads the current credential before a cache hit is returned,
/// so caching cannot turn an unauthenticated provider into a ready one.
#[derive(Debug, Default)]
pub struct OpenRouterCatalogCache {
    entry: Option<CachedCatalog>,
}

#[derive(Debug)]
struct CachedCatalog {
    catalog: ModelCatalog,
    freshness_window: Duration,
}

impl OpenRouterCatalogCache {
    /// Creates an empty catalog cache with capacity for one snapshot.
    pub const fn new() -> Self {
        Self { entry: None }
    }

    /// Removes the cached snapshot, forcing the next lookup to fetch.
    pub fn invalidate(&mut self) {
        self.entry = None;
    }

    /// Returns a fresh cached snapshot or fetches and validates a new one.
    ///
    /// `now` is supplied by the caller so cache behavior is deterministic and
    /// tests never need a real clock or network. Expired entries are never
    /// returned as a fallback. A failed refresh invalidates the prior entry,
    /// so a transient failure cannot later reactivate an expired snapshot.
    pub fn get_or_fetch<C, H>(
        &mut self,
        adapter: &OpenRouterAdapter<C, H>,
        now: SystemTime,
        freshness_window: Duration,
    ) -> Result<ModelCatalog, OpenRouterCatalogError>
    where
        C: CredentialPort,
        H: CatalogTransport,
    {
        let provider = adapter.descriptor.id().clone();
        let key = adapter.read_key(&provider, RuntimeFailureKind::Detection)?;
        if let Some(entry) = &self.entry
            && entry.freshness_window == freshness_window
            && entry.catalog.is_fresh(&FixedClock::new(now))
        {
            return Ok(entry.catalog.clone());
        }

        self.invalidate();
        let catalog = adapter.fetch_catalog_with_key(&key, now, freshness_window)?;
        self.entry = Some(CachedCatalog {
            catalog: catalog.clone(),
            freshness_window,
        });
        Ok(catalog)
    }
}

/// A credential-port-backed OpenRouter adapter.
#[derive(Debug)]
pub struct OpenRouterAdapter<C, H = OpenRouterHttpClient> {
    credentials: C,
    client: H,
    descriptor: ProviderDescriptor,
    endpoint: ProviderEndpoint,
    credential_key: CredentialKey,
    model: String,
}

impl<C> OpenRouterAdapter<C, OpenRouterHttpClient> {
    /// Creates an adapter using the production ureq transport.
    pub fn with_default_client(
        credentials: C,
        model: impl Into<String>,
    ) -> Result<Self, OpenRouterConfigError> {
        Self::new(credentials, OpenRouterHttpClient::default(), model)
    }
}

impl<C, H> OpenRouterAdapter<C, H> {
    /// Creates an OpenRouter adapter around a credential port and HTTP client.
    pub fn new(
        credentials: C,
        client: H,
        model: impl Into<String>,
    ) -> Result<Self, OpenRouterConfigError> {
        let id = ProviderId::new(PROVIDER_ID)?;
        let descriptor = ProviderDescriptor::new(
            id,
            DISPLAY_NAME,
            MINIMUM_VERSION,
            AuthenticationMode::CredentialPort,
            CapabilityDescriptor::text_only(),
        )?;
        let endpoint = ProviderEndpoint::new(ENDPOINT)?;
        let credential_key =
            CredentialKey::new(CREDENTIAL_NAME).map_err(OpenRouterConfigError::CredentialKey)?;
        let model = model.into();
        if model.trim().is_empty() {
            return Err(OpenRouterConfigError::Provider(
                ProviderRequestError::EmptyField {
                    field: "OpenRouter model",
                },
            ));
        }
        Ok(Self {
            credentials,
            client,
            descriptor,
            endpoint,
            credential_key,
            model,
        })
    }

    /// Returns the logical credential key used by this adapter.
    pub fn credential_key(&self) -> &CredentialKey {
        &self.credential_key
    }

    /// Returns the configured model name.
    pub fn model(&self) -> &str {
        &self.model
    }

    /// Fetches a transient, validated model catalog snapshot.
    ///
    /// The credential is read only for this call. The returned snapshot holds
    /// only validated model identifiers and freshness metadata; it retains no
    /// key, endpoint response, or provider payload.
    pub fn fetch_catalog(
        &self,
        fetched_at: SystemTime,
        freshness_window: Duration,
    ) -> Result<ModelCatalog, OpenRouterCatalogError>
    where
        C: CredentialPort,
        H: CatalogTransport,
    {
        let provider = self.descriptor.id().clone();
        let key = self.read_key(&provider, RuntimeFailureKind::Detection)?;
        self.fetch_catalog_with_key(&key, fetched_at, freshness_window)
    }

    fn fetch_catalog_with_key(
        &self,
        key: &str,
        fetched_at: SystemTime,
        freshness_window: Duration,
    ) -> Result<ModelCatalog, OpenRouterCatalogError>
    where
        H: CatalogTransport,
    {
        let response = self.client.get_json(CATALOG_ENDPOINT, key)?;
        if response.status == 429 {
            return Err(OpenRouterCatalogError::RateLimited);
        }
        if !(200..300).contains(&response.status) {
            return Err(OpenRouterCatalogError::HttpStatus);
        }
        let validated = parse_catalog(&response.body)?;
        Ok(ModelCatalog::new(validated, fetched_at, freshness_window))
    }

    fn read_key(
        &self,
        provider: &ProviderId,
        kind: RuntimeFailureKind,
    ) -> Result<String, ProviderError>
    where
        C: CredentialPort,
    {
        let outcome = self.credentials.read(&self.credential_key).map_err(|_| {
            ProviderError::RuntimeFailure {
                provider: provider.clone(),
                kind: kind.clone(),
            }
        })?;
        if matches!(outcome, PortOutcome::Partial(_)) {
            return Err(ProviderError::RuntimeFailure {
                provider: provider.clone(),
                kind,
            });
        }
        match outcome.into_inner() {
            Some(value) if !value.expose().trim().is_empty() => Ok(value.expose().to_owned()),
            _ => Err(ProviderError::NotAuthenticated {
                provider: provider.clone(),
            }),
        }
    }
}

impl<C, H> ProviderAdapter for OpenRouterAdapter<C, H>
where
    C: CredentialPort,
    H: HttpTransport,
{
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        let provider = self.descriptor.id().clone();
        let _key = self.read_key(&provider, RuntimeFailureKind::Detection)?;
        Ok(ProviderDetection::installed(
            ProviderLocation::Endpoint(self.endpoint.clone()),
            MINIMUM_VERSION,
            AuthenticationStatus::Authenticated,
        ))
    }

    fn invoke(
        &self,
        invocation: ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError> {
        let provider = self.descriptor.id().clone();
        let key = self.read_key(&provider, RuntimeFailureKind::Invocation)?;
        let request = invocation.request();
        let body = json!({
            "model": self.model,
            "messages": [{"role": "user", "content": request.context()}],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "qaptr_provider_response",
                    "strict": true,
                    "schema": response_schema(),
                }
            }
        });
        let response = self
            .client
            .post_json(self.endpoint.as_str(), &key, &body.to_string())
            .map_err(|error| ProviderError::RuntimeFailure {
                provider: provider.clone(),
                kind: error.runtime_failure_kind(),
            })?;
        if response.status == 429 {
            return Err(ProviderError::RuntimeFailure {
                provider,
                kind: RuntimeFailureKind::RateLimited,
            });
        }
        if !(200..300).contains(&response.status) {
            return Err(ProviderError::RuntimeFailure {
                provider,
                kind: RuntimeFailureKind::Invocation,
            });
        }
        parse_response(&response.body).map_err(|_| ProviderError::RuntimeFailure {
            provider,
            kind: RuntimeFailureKind::MalformedOutput {
                error: qaptr_provider::SchemaError::EmptyField {
                    object: "OpenRouter response",
                    field: "structured output",
                },
            },
        })
    }
}

fn response_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "observations": {"type": "array", "items": {
                "type": "object", "additionalProperties": false,
                "properties": {
                    "title": {"type": "string"},
                    "summary": {"type": "string"},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1}
                },
                "required": ["title", "summary", "confidence"]
            }},
            "workflow": {"anyOf": [
                {"type": "null"},
                {"type": "object", "additionalProperties": false,
                 "properties": {"title": {"type": "string"}, "goal": {"type": "string"}},
                 "required": ["title", "goal"]}
            ]}
        },
        "required": ["observations", "workflow"]
    })
}

/// Parses the structured JSON content returned by OpenRouter.
pub fn parse_response(body: &str) -> Result<RawProviderResponse, serde_json::Error> {
    let envelope: Value = serde_json::from_str(body)?;
    let payload = match envelope
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
        .and_then(Value::as_str)
    {
        Some(content) => serde_json::from_str(content)?,
        None => envelope,
    };
    raw_response(payload)
}

fn raw_response(value: Value) -> Result<RawProviderResponse, serde_json::Error> {
    let observations = value
        .get("observations")
        .and_then(Value::as_array)
        .cloned()
        .ok_or_else(|| invalid_type("observations"))?
        .into_iter()
        .map(|observation| {
            Ok(RawObservation::new(
                required_string(&observation, "title")?,
                required_string(&observation, "summary")?,
                observation
                    .get("confidence")
                    .and_then(Value::as_f64)
                    .map(|value| value as f32)
                    .ok_or_else(|| invalid_type("confidence"))?,
            ))
        })
        .collect::<Result<Vec<_>, serde_json::Error>>()?;
    let workflow = match value.get("workflow") {
        None | Some(Value::Null) => None,
        Some(workflow) => Some(RawWorkflow::new(
            required_string(workflow, "title")?,
            required_string(workflow, "goal")?,
        )),
    };
    Ok(RawProviderResponse::new(observations, workflow))
}

fn required_string(value: &Value, field: &'static str) -> Result<String, serde_json::Error> {
    value
        .get(field)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .ok_or_else(|| invalid_type(field))
}

fn invalid_type(field: &'static str) -> serde_json::Error {
    serde_json::Error::io(std::io::Error::new(
        std::io::ErrorKind::InvalidData,
        format!("missing or invalid {field}"),
    ))
}
