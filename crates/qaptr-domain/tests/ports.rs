//! Contract tests for the platform-independent U2 ports.

#![cfg(feature = "testing")]

use qaptr_domain::ports::capture::{CapturePort, CaptureRequest, CaptureSample, DisplayId};
use qaptr_domain::ports::context::{AccessibilityContextPort, ContextRequest, ContextSnapshot};
use qaptr_domain::ports::credentials::{CredentialKey, CredentialPort, CredentialValue};
use qaptr_domain::ports::ocr::{OcrPort, OcrResult};
use qaptr_domain::ports::vision::{VisionPort, VisionResult};
use qaptr_domain::ports::{LoginItemPort, LoginItemState, PortOutcome};
use qaptr_domain::testing::{
    InMemoryAccessibilityContext, InMemoryCapture, InMemoryCredentials, InMemoryLoginItem,
    InMemoryOcr, InMemoryVision,
};
use qaptr_domain::{CaptureId, Confidence};

fn capture_sample() -> CaptureSample {
    CaptureSample::new(
        CaptureId::new("capture-1").expect("test id is valid"),
        DisplayId::new("display-1").expect("test display is valid"),
        1280,
        720,
    )
    .expect("test sample is valid")
}

fn capture_request() -> CaptureRequest {
    CaptureRequest::new(
        DisplayId::new("display-1").expect("test display is valid"),
        1280,
        720,
    )
    .expect("test request is valid")
}

fn capture_id() -> CaptureId {
    CaptureId::new("capture-1").expect("test id is valid")
}

#[test]
fn every_port_has_a_compiling_in_memory_double() {
    fn assert_capture<T: CapturePort>() {}
    fn assert_ocr<T: OcrPort>() {}
    fn assert_vision<T: VisionPort>() {}
    fn assert_context<T: AccessibilityContextPort>() {}
    fn assert_credentials<T: CredentialPort>() {}
    fn assert_login_item<T: LoginItemPort>() {}

    assert_capture::<InMemoryCapture>();
    assert_ocr::<InMemoryOcr>();
    assert_vision::<InMemoryVision>();
    assert_context::<InMemoryAccessibilityContext>();
    assert_credentials::<InMemoryCredentials>();
    assert_login_item::<InMemoryLoginItem>();
}

#[test]
fn capture_double_simulates_complete_partial_denied_and_timeout() {
    let request = capture_request();
    assert!(matches!(
        InMemoryCapture::ready(capture_sample())
            .capture(&request)
            .expect("complete capture should succeed"),
        PortOutcome::Complete(_)
    ));
    assert!(
        InMemoryCapture::partial(capture_sample())
            .capture(&request)
            .expect("partial capture should succeed")
            .is_partial()
    );
    assert_eq!(
        InMemoryCapture::denied()
            .capture(&request)
            .expect_err("denial should be returned"),
        qaptr_domain::DomainError::Denied {
            operation: "capture"
        }
    );
    assert_eq!(
        InMemoryCapture::timed_out()
            .capture(&request)
            .expect_err("timeout should be returned"),
        qaptr_domain::DomainError::TimedOut {
            operation: "capture"
        }
    );
}

#[test]
fn processing_and_context_doubles_simulate_partial_results() {
    let ocr = InMemoryOcr::partial(OcrResult::default())
        .recognize(&capture_id())
        .expect("partial OCR should succeed");
    assert!(ocr.is_partial());

    let vision = InMemoryVision::partial(VisionResult::default())
        .detect(&capture_id())
        .expect("partial vision should succeed");
    assert!(vision.is_partial());

    let context = InMemoryAccessibilityContext::partial(ContextSnapshot::default())
        .sample(&ContextRequest::new(capture_id()))
        .expect("partial context should succeed");
    assert!(context.is_partial());
}

#[test]
fn processing_and_context_doubles_simulate_denial_and_timeout() {
    assert_eq!(
        InMemoryOcr::denied()
            .recognize(&capture_id())
            .expect_err("OCR denial should be returned"),
        qaptr_domain::DomainError::Denied { operation: "ocr" }
    );
    assert_eq!(
        InMemoryVision::timed_out()
            .detect(&capture_id())
            .expect_err("vision timeout should be returned"),
        qaptr_domain::DomainError::TimedOut {
            operation: "vision"
        }
    );
    assert_eq!(
        InMemoryAccessibilityContext::denied()
            .sample(&ContextRequest::new(capture_id()))
            .expect_err("context denial should be returned"),
        qaptr_domain::DomainError::Denied {
            operation: "accessibility context"
        }
    );
}

#[test]
fn credential_and_login_doubles_cover_all_outcomes() {
    let key = CredentialKey::new("provider").expect("test key is valid");
    let value = CredentialValue::new("secret");
    assert!(matches!(
        InMemoryCredentials::ready(Some(value.clone()))
            .read(&key)
            .expect("credential read should succeed"),
        PortOutcome::Complete(Some(_))
    ));
    assert!(
        InMemoryCredentials::partial(None)
            .read(&key)
            .expect("partial credential read should succeed")
            .is_partial()
    );
    assert_eq!(
        InMemoryCredentials::denied()
            .write(&key, value.clone())
            .expect_err("credential denial should be returned"),
        qaptr_domain::DomainError::Denied {
            operation: "credential write"
        }
    );
    assert_eq!(
        InMemoryCredentials::timed_out()
            .delete(&key)
            .expect_err("credential timeout should be returned"),
        qaptr_domain::DomainError::TimedOut {
            operation: "credential delete"
        }
    );

    assert!(
        InMemoryLoginItem::partial(LoginItemState::Enabled)
            .status()
            .expect("partial login-item state should succeed")
            .is_partial()
    );
    assert_eq!(
        InMemoryLoginItem::denied()
            .set_enabled(true)
            .expect_err("login-item denial should be returned"),
        qaptr_domain::DomainError::Denied {
            operation: "login-item registration"
        }
    );
    assert_eq!(
        InMemoryLoginItem::timed_out()
            .status()
            .expect_err("login-item timeout should be returned"),
        qaptr_domain::DomainError::TimedOut {
            operation: "login-item status"
        }
    );
}

#[test]
fn port_sources_are_platform_neutral() {
    let sources = [
        include_str!("../src/ports/mod.rs"),
        include_str!("../src/ports/capture.rs"),
        include_str!("../src/ports/ocr.rs"),
        include_str!("../src/ports/vision.rs"),
        include_str!("../src/ports/context.rs"),
        include_str!("../src/ports/credentials.rs"),
    ];
    for source in sources {
        assert!(!source.contains("std::os"));
        assert!(!source.contains("CoreGraphics"));
        assert!(!source.contains("AppKit"));
        assert!(!source.contains("ScreenCaptureKit"));
    }
}

#[test]
fn confidence_and_context_types_remain_domain_values() {
    let confidence = Confidence::new(0.5).expect("test confidence is valid");
    let snapshot = ContextSnapshot::new(
        Some("Editor".to_owned()),
        Some("Notes".to_owned()),
        Some("example.com".to_owned()),
        None,
    );
    assert_eq!(snapshot.application(), Some("Editor"));
    assert_eq!(confidence.as_f32(), 0.5);
}
