#![allow(missing_docs)]

use qaptr_domain::ports::ContextSnapshot;
use qaptr_privacy::{
    ContextField, SanitizationError, SensitiveClass, sanitize_context, sanitize_field,
    sanitize_path, sanitize_text, sanitize_url,
};

#[test]
fn embedded_url_credentials_and_query_tokens_are_removed() {
    let sanitized = sanitize_url(
        "https://alice:fixture-password@example.test/dashboard?access_token=fixture-token",
    )
    .expect("the URL has a valid host");

    assert_eq!(sanitized.value(), "https://example.test");
    assert!(sanitized.classes().contains(&SensitiveClass::Credential));
    assert!(sanitized.classes().contains(&SensitiveClass::ApiKey));
    assert!(!sanitized.value().contains("fixture-password"));
    assert!(!sanitized.value().contains("fixture-token"));
}

#[test]
fn ordinary_text_and_surnames_survive_text_sanitization() {
    let sanitized = sanitize_text("Review the project with Alice Smith").expect("safe text");

    assert_eq!(sanitized.value(), "Review the project with Alice Smith");
    assert!(sanitized.classes().is_empty());
}

#[test]
fn email_and_phone_are_redacted_without_hiding_surrounding_text() {
    let sanitized = sanitize_text("Call 415-555-0123 or email alice@example.test.")
        .expect("email and phone fixture are valid");

    assert_eq!(
        sanitized.value(),
        "Call [REDACTED_PHONE] or email [REDACTED_EMAIL]."
    );
    assert!(sanitized.classes().contains(&SensitiveClass::EmailAddress));
    assert!(sanitized.classes().contains(&SensitiveClass::PhoneNumber));
}

#[test]
fn embedded_url_query_is_removed_from_a_window_title() {
    let sanitized =
        sanitize_text("Docs — https://example.test/search?q=work&access_token=fixture-token")
            .expect("the title contains a valid URL");

    assert_eq!(sanitized.value(), "Docs — https://example.test");
    assert!(!sanitized.value().contains("fixture-token"));
}

#[test]
fn home_path_is_generalized_without_the_username() {
    let sanitized = sanitize_path("/Users/real.person/Documents/quarterly-plan.docx")
        .expect("the path is safe text");

    assert_eq!(sanitized.value(), "~/Documents/quarterly-plan.docx");
    assert!(!sanitized.value().contains("real.person"));
}

#[test]
fn sanitization_is_idempotent() {
    let once = sanitize_text(
        "Review fixture.email@example.test password=fixture-password-123 at 123 Main Street",
    )
    .expect("fixture text is valid");
    let twice = sanitize_text(once.value()).expect("sanitized text is valid");

    assert_eq!(once.value(), twice.value());
}

#[test]
fn unknown_and_malformed_values_fail_closed() {
    assert_eq!(
        sanitize_field(ContextField::Unknown, "unclassified")
            .expect_err("unknown fields must not pass through"),
        SanitizationError::UnclassifiableField {
            field: ContextField::Unknown,
        }
    );
    assert_eq!(
        sanitize_url("https://").expect_err("a URL without a host must be rejected"),
        SanitizationError::InvalidUrl
    );
}

#[test]
fn sanitization_is_deterministic() {
    let input = "Safari — https://example.test/?token=fixture-token — fixture.email@example.test";
    let first = sanitize_text(input).expect("fixture text is valid");
    let second = sanitize_text(input).expect("the same fixture remains valid");

    assert_eq!(first, second);
}

#[test]
fn sampled_context_is_sanitized_as_structured_fields() {
    let snapshot = ContextSnapshot::new(
        Some("Safari".to_owned()),
        Some("Review password=fixture-password-123".to_owned()),
        Some("https://example.test".to_owned()),
        Some("fixture.email@example.test plan".to_owned()),
    );

    let sanitized = sanitize_context(&snapshot).expect("all sampled fields are classified");
    assert_eq!(sanitized.get(ContextField::Application), Some("Safari"));
    assert_eq!(
        sanitized.get(ContextField::WindowTitle),
        Some("Review [REDACTED_CREDENTIAL]")
    );
    assert_eq!(
        sanitized.get(ContextField::Url),
        Some("https://example.test")
    );
    assert_eq!(
        sanitized.get(ContextField::DocumentName),
        Some("[REDACTED_EMAIL] plan")
    );
}

#[cfg(feature = "corpus")]
#[test]
fn labeled_fixture_corpus_retains_no_known_secret() {
    for line in include_str!("../../../fixtures/privacy/context/ground_truth.csv").lines() {
        let mut columns = line.splitn(3, '|');
        let _label = columns.next().expect("fixture has a label");
        let secret = columns.next().expect("fixture has a secret");
        let input = columns.next().expect("fixture has input");
        let sanitized = sanitize_text(input).expect("fixture text is valid");
        assert!(!sanitized.value().contains(secret));
    }
}
