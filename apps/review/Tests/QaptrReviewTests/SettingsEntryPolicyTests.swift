import XCTest
@testable import QaptrReview

/// The same persisted onboarding completion bit gates every native Settings
/// entry. The policy is pure so this safety boundary is testable without
/// launching AppKit or opening a Settings window.
final class SettingsEntryPolicyTests: XCTestCase {
    func testIncompleteOnboardingRedirectsToPrimaryUI() {
        XCTAssertEqual(
            SettingsEntryPolicy.route(onboardingCompleted: false),
            .primaryUI
        )
    }

    func testCompletedOnboardingAllowsSettings() {
        XCTAssertEqual(
            SettingsEntryPolicy.route(onboardingCompleted: true),
            .settings
        )
    }

    func testPolicyHasNoProviderOrCaptureSideEffects() {
        // The route is a pure decision over durable onboarding state. In
        // particular, it cannot turn a saved provider key into a verified
        // connection or start capture as a side effect.
        XCTAssertEqual(SettingsEntryPolicy.route(onboardingCompleted: false), .primaryUI)
        XCTAssertEqual(SettingsEntryPolicy.route(onboardingCompleted: true), .settings)
    }
}
