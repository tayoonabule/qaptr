//! In-process OpenRouter adapter contract tests.

mod support;

use std::rc::Rc;

use qaptr_domain::{
    Duration,
    ports::{CredentialKey, CredentialPort, CredentialValue, PortOutcome, PortResult},
};
use qaptr_policy::ModelId;
use qaptr_provider::{ProviderError, ProviderGate, RuntimeFailureKind};
use qaptr_provider_openrouter::{
    CatalogTransport, HttpResponse, HttpTransport, OpenRouterAdapter, TransportError,
};

#[derive(Debug)]
struct FakeCredentials {
    value: Option<CredentialValue>,
    partial: bool,
    writes: Rc<std::cell::Cell<u32>>,
}

impl FakeCredentials {
    fn configured(value: &str) -> Self {
        Self {
            value: Some(CredentialValue::new(value)),
            partial: false,
            writes: Rc::new(std::cell::Cell::new(0)),
        }
    }
}

impl CredentialPort for FakeCredentials {
    fn read(&self, _key: &CredentialKey) -> PortResult<Option<CredentialValue>> {
        if self.partial {
            Ok(PortOutcome::Partial(self.value.clone()))
        } else {
            Ok(PortOutcome::Complete(self.value.clone()))
        }
    }

    fn write(&self, _key: &CredentialKey, _value: CredentialValue) -> PortResult<()> {
        self.writes.set(self.writes.get().saturating_add(1));
        Ok(PortOutcome::Complete(()))
    }

    fn delete(&self, _key: &CredentialKey) -> PortResult<()> {
        Ok(PortOutcome::Complete(()))
    }
}

#[derive(Debug)]
struct FakeHttp {
    response: Result<HttpResponse, TransportError>,
    calls: Rc<std::cell::Cell<u32>>,
}

impl FakeHttp {
    fn response(body: &str) -> Self {
        Self {
            response: Ok(HttpResponse {
                status: 200,
                body: body.to_owned(),
            }),
            calls: Rc::new(std::cell::Cell::new(0)),
        }
    }
}

impl HttpTransport for FakeHttp {
    fn post_json(
        &self,
        _endpoint: &str,
        _bearer_token: &str,
        _body: &str,
    ) -> Result<HttpResponse, TransportError> {
        self.calls.set(self.calls.get().saturating_add(1));
        self.response.clone()
    }
}

impl CatalogTransport for FakeHttp {
    fn get_json(
        &self,
        _endpoint: &str,
        _bearer_token: &str,
    ) -> Result<HttpResponse, TransportError> {
        self.calls.set(self.calls.get().saturating_add(1));
        self.response.clone()
    }
}

fn adapter(body: &str) -> OpenRouterAdapter<FakeCredentials, FakeHttp> {
    OpenRouterAdapter::new(
        FakeCredentials::configured("test-key"),
        FakeHttp::response(body),
        "test-model",
    )
    .expect("fixed OpenRouter test configuration is valid")
}

const RESPONSE: &str = r#"{"observations":[{"title":"Observed","summary":"A repeated workflow","confidence":0.8}],"workflow":{"title":"Workflow","goal":"Repeat the steps"}}"#;

const CATALOG_RESPONSE: &str = r#"{
    "data": [
        {"id": "provider/structured", "architecture": {
            "input_modalities": ["text"], "output_modalities": ["text"]
        }, "supported_parameters": ["structured_outputs"]},
        {"id": "provider/unstructured", "architecture": {
            "input_modalities": ["text"], "output_modalities": ["text"]
        }, "supported_parameters": ["tools"]}
    ]
}"#;

#[test]
fn catalog_fetch_returns_only_capability_qualified_models() {
    let adapter = adapter(CATALOG_RESPONSE);
    let catalog = adapter
        .fetch_catalog(std::time::UNIX_EPOCH, Duration::from_secs(900))
        .expect("compatible catalog fixture should validate");

    assert_eq!(
        catalog
            .validated()
            .iter()
            .map(ModelId::as_str)
            .collect::<Vec<_>>(),
        ["provider/structured"]
    );
    assert_eq!(catalog.fetched_at(), std::time::UNIX_EPOCH);
}

#[test]
fn catalog_fetch_rejects_malformed_and_unstructured_entries() {
    let adapter = adapter(
        r#"{"data":[null,{},
            {"id":"unstructured","architecture":{"input_modalities":["text"],"output_modalities":["text"]},"supported_parameters":["tools"]}
        ]}"#,
    );

    let error = adapter
        .fetch_catalog(std::time::UNIX_EPOCH, Duration::from_secs(900))
        .expect_err("catalog without a compatible model must fail closed");
    assert!(matches!(
        error,
        qaptr_provider_openrouter::OpenRouterCatalogError::Parse(
            qaptr_provider_openrouter::CatalogParseError::NoCompatibleModels
        )
    ));
}

#[test]
fn gate_routes_openrouter_to_the_shared_normalized_shape() {
    let gate = ProviderGate::new(adapter(RESPONSE));
    let verified = gate
        .detect_and_verify()
        .expect("configured OpenRouter fake should pass the gate");
    let response = gate
        .invoke(&verified, &support::prepared_payload(false))
        .expect("valid fixture should normalize");

    assert_eq!(response.observations().len(), 1);
    assert_eq!(response.observations()[0].title(), "Observed");
    assert_eq!(
        response.workflow().expect("workflow is present").goal(),
        "Repeat the steps"
    );
}

#[test]
fn missing_key_is_not_authenticated_and_is_never_written() {
    let writes = Rc::new(std::cell::Cell::new(0));
    let credentials = FakeCredentials {
        value: None,
        partial: false,
        writes: Rc::clone(&writes),
    };
    let adapter = OpenRouterAdapter::new(credentials, FakeHttp::response(RESPONSE), "model")
        .expect("fixed OpenRouter test configuration is valid");
    let gate = ProviderGate::new(adapter);
    assert!(matches!(
        gate.detect_and_verify(),
        Err(ProviderError::NotAuthenticated { .. })
    ));
    assert_eq!(writes.get(), 0);
}

#[test]
fn image_request_is_refused_by_gate_before_http_transport() {
    let calls = Rc::new(std::cell::Cell::new(0));
    let adapter = OpenRouterAdapter::new(
        FakeCredentials::configured("test-key"),
        FakeHttp {
            response: Ok(HttpResponse {
                status: 200,
                body: RESPONSE.to_owned(),
            }),
            calls: Rc::clone(&calls),
        },
        "model",
    )
    .expect("fixed OpenRouter test configuration is valid");
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("configured OpenRouter fake should pass the gate");
    let error = gate
        .invoke(&verified, &support::prepared_payload(true))
        .expect_err("images are unsupported");
    assert!(matches!(error, ProviderError::CapabilityMissing { .. }));
    assert_eq!(calls.get(), 0);
}

#[test]
fn malformed_output_is_typed_and_transport_failures_are_typed() {
    let gate = ProviderGate::new(adapter(
        "{\"observations\":[{\"title\":\"missing summary\"}]}",
    ));
    let verified = gate
        .detect_and_verify()
        .expect("configured OpenRouter fake should pass the gate");
    let error = gate
        .invoke(&verified, &support::prepared_payload(false))
        .expect_err("malformed fixture must be rejected");
    assert!(matches!(
        error,
        ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::MalformedOutput { .. },
            ..
        }
    ));

    let adapter = OpenRouterAdapter::new(
        FakeCredentials::configured("test-key"),
        FakeHttp {
            response: Err(TransportError::Network),
            calls: Rc::new(std::cell::Cell::new(0)),
        },
        "model",
    )
    .expect("fixed OpenRouter test configuration is valid");
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("detection does not call HTTP");
    let error = gate
        .invoke(&verified, &support::prepared_payload(false))
        .expect_err("network failure must be typed");
    assert!(matches!(
        error,
        ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::Network,
            ..
        }
    ));
}

#[test]
fn rate_limit_is_a_typed_failure_without_partial_response() {
    let adapter = OpenRouterAdapter::new(
        FakeCredentials::configured("test-key"),
        FakeHttp {
            response: Ok(HttpResponse {
                status: 429,
                body: String::from("rate limited"),
            }),
            calls: Rc::new(std::cell::Cell::new(0)),
        },
        "model",
    )
    .expect("fixed OpenRouter test configuration is valid");
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("detection does not call HTTP");
    let error = gate
        .invoke(&verified, &support::prepared_payload(false))
        .expect_err("rate limit must not return a partial response");
    assert!(matches!(
        error,
        ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::RateLimited,
            ..
        }
    ));
}

#[test]
fn credential_port_is_read_only_for_the_adapter() {
    let writes = Rc::new(std::cell::Cell::new(0));
    let credentials = FakeCredentials {
        value: Some(CredentialValue::new("test-key")),
        partial: false,
        writes: Rc::clone(&writes),
    };
    let adapter = OpenRouterAdapter::new(credentials, FakeHttp::response(RESPONSE), "model")
        .expect("fixed OpenRouter test configuration is valid");
    let gate = ProviderGate::new(adapter);
    let verified = gate
        .detect_and_verify()
        .expect("configured fake should pass");
    let _ = gate
        .invoke(&verified, &support::prepared_payload(false))
        .expect("fixture should normalize");
    assert_eq!(writes.get(), 0);
}
