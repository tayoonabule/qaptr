//! Small synchronous HTTP transport used by the OpenRouter adapter.

use std::time::Duration;

use thiserror::Error;

/// Maximum response body retained by the OpenRouter transport.
pub const MAX_RESPONSE_BYTES: u64 = 512 * 1024;

/// A bounded HTTP response body.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpResponse {
    /// HTTP status code.
    pub status: u16,
    /// Response body retained for schema parsing.
    pub body: String,
}

/// Transport failures kept separate from provider response-schema failures.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum TransportError {
    /// The HTTP stack could not connect, send, or decode the response.
    #[error("OpenRouter network request failed")]
    Network,
}

impl TransportError {
    pub(crate) const fn runtime_failure_kind(self) -> qaptr_provider::RuntimeFailureKind {
        match self {
            Self::Network => qaptr_provider::RuntimeFailureKind::Network,
        }
    }
}

/// The minimal HTTP operation required by the adapter.
pub trait HttpTransport {
    /// Sends one JSON POST and returns the bounded response body.
    fn post_json(
        &self,
        endpoint: &str,
        bearer_token: &str,
        body: &str,
    ) -> Result<HttpResponse, TransportError>;
}

/// The minimal catalog operation required by the OpenRouter configuration
/// path.
pub trait CatalogTransport {
    /// Sends one authenticated JSON GET and returns the bounded response body.
    fn get_json(&self, endpoint: &str, bearer_token: &str) -> Result<HttpResponse, TransportError>;
}

/// Production OpenRouter transport backed by ureq and rustls.
#[derive(Clone, Debug)]
pub struct OpenRouterHttpClient {
    agent: ureq::Agent,
}

impl Default for OpenRouterHttpClient {
    fn default() -> Self {
        let config = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(30)))
            .build();
        Self {
            agent: config.into(),
        }
    }
}

impl HttpTransport for OpenRouterHttpClient {
    fn post_json(
        &self,
        endpoint: &str,
        bearer_token: &str,
        body: &str,
    ) -> Result<HttpResponse, TransportError> {
        let response = self
            .agent
            .post(endpoint)
            .header("Authorization", format!("Bearer {bearer_token}"))
            .header("Content-Type", "application/json")
            .send(body)
            .map_err(|_| TransportError::Network)?;
        let status = response.status();
        let body = response
            .into_body()
            .with_config()
            .limit(MAX_RESPONSE_BYTES)
            .read_to_string()
            .map_err(|_| TransportError::Network)?;
        Ok(HttpResponse {
            status: status.into(),
            body,
        })
    }
}

impl CatalogTransport for OpenRouterHttpClient {
    fn get_json(&self, endpoint: &str, bearer_token: &str) -> Result<HttpResponse, TransportError> {
        let response = self
            .agent
            .get(endpoint)
            .header("Authorization", format!("Bearer {bearer_token}"))
            .header("Accept", "application/json")
            .call()
            .map_err(|_| TransportError::Network)?;
        let status = response.status();
        let body = response
            .into_body()
            .with_config()
            .limit(MAX_RESPONSE_BYTES)
            .read_to_string()
            .map_err(|_| TransportError::Network)?;
        Ok(HttpResponse {
            status: status.into(),
            body,
        })
    }
}
