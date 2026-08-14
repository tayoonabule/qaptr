//! Real TCC status integration tests.

#![cfg(target_os = "macos")]

use qaptr_domain::ports::permissions::{Permission, PermissionState};
use qaptr_macos::MacPermissions;

#[test]
#[ignore = "reads the real per-user TCC database and never requests access"]
fn status_query_is_read_only_and_reports_a_native_state() {
    let bundle_identifier = std::env::var("QAPTR_TEST_BUNDLE_IDENTIFIER")
        .unwrap_or_else(|_| "com.qaptr.review".to_owned());
    let adapter = MacPermissions::new(bundle_identifier).expect("test bundle identifier is valid");

    let screen = adapter
        .state_value(Permission::ScreenCapture)
        .expect("screen recording status query must not fail");
    let accessibility = adapter
        .state_value(Permission::AccessibilityContext)
        .expect("accessibility status query must not fail");

    assert!(matches!(
        screen,
        PermissionState::Granted | PermissionState::Denied | PermissionState::NotDetermined
    ));
    assert!(matches!(
        accessibility,
        PermissionState::Granted | PermissionState::Denied | PermissionState::NotDetermined
    ));
}
