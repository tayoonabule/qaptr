//! In-process contract tests for the U13 provider gate.

use std::cell::Cell;

use qaptr_provider::{
    AuthenticationMode, AuthenticationStatus, Capability, CapabilityDescriptor,
    CapabilityRequirements, ExecutablePath, ProviderAdapter, ProviderDescriptor, ProviderDetection,
    ProviderEndpoint, ProviderError, ProviderGate, ProviderId, ProviderLocation, ProviderRequest,
    ProviderVersion, RawObservation, RawProviderResponse, RuntimeFailureKind,
};

struct FakeProvider {
    descriptor: ProviderDescriptor,
    detection: ProviderDetection,
    response: RawProviderResponse,
    detect_failure: Option<ProviderError>,
    invocation_count: Cell<u32>,
}

impl FakeProvider {
    fn new(capabilities: CapabilityDescriptor) -> Self {
        let id = ProviderId::new("fake").expect("test provider id is valid");
        let descriptor = ProviderDescriptor::new(
            id,
            "Fake provider",
            ProviderVersion::new(1, 0, 0),
            AuthenticationMode::ExistingCliSession,
            capabilities,
        )
        .expect("test provider descriptor is valid");
        let executable = ExecutablePath::new("/usr/local/bin/fake").expect("test path is absolute");
        Self {
            descriptor,
            detection: ProviderDetection::installed(
                ProviderLocation::Executable(executable),
                ProviderVersion::new(1, 2, 3),
                AuthenticationStatus::Authenticated,
            ),
            response: RawProviderResponse::new(
                vec![RawObservation::new("Observed", "A repeated workflow", 0.8)],
                None,
            ),
            detect_failure: None,
            invocation_count: Cell::new(0),
        }
    }

    fn endpoint_variant() -> Self {
        let mut fake = Self::new(CapabilityDescriptor::text_only());
        let endpoint =
            ProviderEndpoint::new("https://example.test").expect("test endpoint is valid");
        fake.detection = ProviderDetection::installed(
            ProviderLocation::Endpoint(endpoint),
            ProviderVersion::new(1, 2, 3),
            AuthenticationStatus::Authenticated,
        );
        fake
    }
}

impl ProviderAdapter for FakeProvider {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    fn detect(&self) -> Result<ProviderDetection, ProviderError> {
        if let Some(error) = &self.detect_failure {
            return Err(match error {
                ProviderError::RuntimeFailure { provider, kind } => ProviderError::RuntimeFailure {
                    provider: provider.clone(),
                    kind: kind.clone(),
                },
                _ => panic!("test detection failure must be a runtime failure"),
            });
        }
        Ok(self.detection.clone())
    }

    fn invoke(
        &self,
        invocation: qaptr_provider::ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError> {
        self.invocation_count
            .set(self.invocation_count.get().saturating_add(1));
        assert!(!invocation.request().context().is_empty());
        Ok(self.response.clone())
    }
}

#[test]
fn handshake_accepts_authenticated_new_enough_provider() {
    let fake = FakeProvider::new(CapabilityDescriptor::text_only());
    let gate = ProviderGate::new(fake);

    let verified = gate
        .detect_and_verify()
        .expect("authenticated current fake should pass");

    assert_eq!(verified.version(), ProviderVersion::new(1, 2, 3));
    assert!(!verified.descriptor().capabilities().accepts_images());
}

#[test]
fn endpoint_and_existing_session_are_supported_without_cli_special_cases() {
    let fake = FakeProvider::endpoint_variant();
    let gate = ProviderGate::new(fake);

    let verified = gate
        .detect_and_verify()
        .expect("endpoint fake should pass the same gate");

    assert!(matches!(
        verified.location(),
        ProviderLocation::Endpoint(endpoint) if endpoint.as_str() == "https://example.test"
    ));
}

#[test]
fn each_handshake_failure_is_a_distinct_typed_error() {
    let not_installed = FakeProvider {
        detection: ProviderDetection::not_installed(),
        ..FakeProvider::new(CapabilityDescriptor::text_only())
    };
    assert!(matches!(
        ProviderGate::new(not_installed).detect_and_verify(),
        Err(ProviderError::NotInstalled { .. })
    ));

    let not_authenticated = FakeProvider {
        detection: ProviderDetection::installed(
            ProviderLocation::Executable(
                ExecutablePath::new("/usr/local/bin/fake").expect("test path is absolute"),
            ),
            ProviderVersion::new(1, 2, 3),
            AuthenticationStatus::NotAuthenticated,
        ),
        ..FakeProvider::new(CapabilityDescriptor::text_only())
    };
    assert!(matches!(
        ProviderGate::new(not_authenticated).detect_and_verify(),
        Err(ProviderError::NotAuthenticated { .. })
    ));

    let too_old = FakeProvider {
        detection: ProviderDetection::installed(
            ProviderLocation::Executable(
                ExecutablePath::new("/usr/local/bin/fake").expect("test path is absolute"),
            ),
            ProviderVersion::new(0, 9, 9),
            AuthenticationStatus::Authenticated,
        ),
        ..FakeProvider::new(CapabilityDescriptor::text_only())
    };
    assert!(matches!(
        ProviderGate::new(too_old).detect_and_verify(),
        Err(ProviderError::TooOld { .. })
    ));

    let missing_capability = FakeProvider::new(CapabilityDescriptor::new(
        false, false, true, true, true, true, true,
    ));
    assert!(matches!(
        ProviderGate::new(missing_capability).detect_and_verify(),
        Err(ProviderError::CapabilityMissing {
            capability: Capability::NonInteractive,
            ..
        })
    ));

    let runtime_failure = FakeProvider {
        detect_failure: Some(ProviderError::RuntimeFailure {
            provider: ProviderId::new("fake").expect("test provider id is valid"),
            kind: RuntimeFailureKind::Detection,
        }),
        ..FakeProvider::new(CapabilityDescriptor::text_only())
    };
    assert!(matches!(
        ProviderGate::new(runtime_failure).detect_and_verify(),
        Err(ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::Detection,
            ..
        })
    ));
}

#[test]
fn image_work_is_refused_before_adapter_invocation() {
    let fake = FakeProvider::new(CapabilityDescriptor::text_only());
    let gate = ProviderGate::new(fake);
    let verified = gate
        .detect_and_verify()
        .expect("text-only fake should pass text gate");
    let request =
        ProviderRequest::with_images("sanitized context", 1).expect("one prepared image is valid");

    assert!(matches!(
        gate.invoke(&verified, request),
        Err(ProviderError::CapabilityMissing {
            capability: Capability::Images,
            ..
        })
    ));
    assert_eq!(gate.adapter().invocation_count.get(), 0);
}

#[test]
fn image_capability_is_checked_during_handshake_when_requested() {
    let fake = FakeProvider::new(CapabilityDescriptor::with_images());
    let gate = ProviderGate::new(fake);

    let verified = gate
        .detect_and_verify_with(CapabilityRequirements::with_images())
        .expect("image-capable fake should pass image gate");
    let response = gate
        .invoke(
            &verified,
            ProviderRequest::with_images("sanitized context", 2)
                .expect("two prepared images are valid"),
        )
        .expect("fake response should normalize");

    assert_eq!(response.observations().len(), 1);
}

#[test]
fn malformed_output_is_a_typed_runtime_failure() {
    let mut fake = FakeProvider::new(CapabilityDescriptor::text_only());
    fake.response =
        RawProviderResponse::new(vec![RawObservation::new("", "missing title", 0.5)], None);
    let gate = ProviderGate::new(fake);
    let verified = gate
        .detect_and_verify()
        .expect("fake should pass before malformed output is returned");

    assert!(matches!(
        gate.invoke(
            &verified,
            ProviderRequest::text("sanitized context").expect("context is valid")
        ),
        Err(ProviderError::RuntimeFailure {
            kind: RuntimeFailureKind::MalformedOutput { .. },
            ..
        })
    ));
}

#[test]
fn two_adapters_produce_the_same_normalized_shape() {
    let first = ProviderGate::new(FakeProvider::new(CapabilityDescriptor::text_only()));
    let second = ProviderGate::new(FakeProvider::endpoint_variant());
    let first_verified = first.detect_and_verify().expect("first fake should pass");
    let second_verified = second.detect_and_verify().expect("second fake should pass");
    let request = ProviderRequest::text("sanitized context").expect("context is valid");

    let first_response = first
        .invoke(&first_verified, request.clone())
        .expect("first response should normalize");
    let second_response = second
        .invoke(&second_verified, request)
        .expect("second response should normalize");

    assert_eq!(first_response, second_response);
}
