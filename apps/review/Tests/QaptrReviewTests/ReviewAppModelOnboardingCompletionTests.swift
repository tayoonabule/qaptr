import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// Direct tests for `ReviewAppModel.onboardingCompletionInputs`, the pure,
/// bounded translation from already-known live state (permission status,
/// available displays, provider choice, provider connection) into checklist
/// 5.1's `OnboardingCompletionInputs`.
///
/// These tests never stand up a full `ReviewAppModel` (no bridge, Keychain,
/// or filesystem access is needed to exercise this decision logic).
@MainActor
final class ReviewAppModelOnboardingCompletionTests: XCTestCase {
    func testLoginItemRebindHonorsAnExplicitOptOut() {
        XCTAssertTrue(ReviewAppModel.shouldRebindLoginItem(userPreference: nil))
        XCTAssertTrue(ReviewAppModel.shouldRebindLoginItem(userPreference: true))
        XCTAssertFalse(ReviewAppModel.shouldRebindLoginItem(userPreference: false))
    }

    func testHasSelectedDisplayReflectsWhetherAnyDisplayIsAvailable() {
        let noDisplays = ReviewAppModel.onboardingCompletionInputs(
            screenRecordingStatus: .granted,
            availableDisplayCount: 0,
            provider: nil,
            providerConnectionKind: .notConnected
        )
        XCTAssertFalse(noDisplays.hasSelectedDisplay)

        let oneDisplay = ReviewAppModel.onboardingCompletionInputs(
            screenRecordingStatus: .granted,
            availableDisplayCount: 1,
            provider: nil,
            providerConnectionKind: .notConnected
        )
        XCTAssertTrue(oneDisplay.hasSelectedDisplay)
    }

    func testScreenRecordingStatusPassesThroughUnchanged() {
        for status: PermissionStatus in [.granted, .denied, .notDetermined, .unavailable] {
            let inputs = ReviewAppModel.onboardingCompletionInputs(
                screenRecordingStatus: status,
                availableDisplayCount: 1,
                provider: nil,
                providerConnectionKind: .notConnected
            )
            XCTAssertEqual(inputs.screenRecordingStatus, status)
        }
    }

    func testNoProviderSelectionIsUsableAsALegitimateCaptureOnlyChoice() {
        let inputs = ReviewAppModel.onboardingCompletionInputs(
            screenRecordingStatus: .granted,
            availableDisplayCount: 1,
            provider: nil,
            providerConnectionKind: .notConnected
        )
        XCTAssertTrue(inputs.hasUsableProvider)
    }

    func testOpenRouterIsUsableOnlyWhenActuallyConnected() {
        let connected = ReviewAppModel.onboardingCompletionInputs(
            screenRecordingStatus: .granted,
            availableDisplayCount: 1,
            provider: .openRouter,
            providerConnectionKind: .connected
        )
        XCTAssertTrue(connected.hasUsableProvider)

        let notYetConnected: [ProviderConnectionState.Kind] = [
            .notConnected, .needsKey, .configured, .checking, .failed(.invalidKey), .failed(.unavailable), .failed(.unableToSave),
        ]
        for kind in notYetConnected {
            let inputs = ReviewAppModel.onboardingCompletionInputs(
                screenRecordingStatus: .granted,
                availableDisplayCount: 1,
                provider: .openRouter,
                providerConnectionKind: kind
            )
            XCTAssertFalse(inputs.hasUsableProvider, "OpenRouter must not be usable while \(kind)")
        }
    }

    func testSavedKeyIsVisibleButDoesNotClaimVerifiedProviderConnection() {
        XCTAssertEqual(ProviderConnectionState.configured.title, "Key saved")
        XCTAssertEqual(
            ProviderConnectionState.configured.detail,
            "A key is saved. Paste it again to verify the provider."
        )
        let inputs = ReviewAppModel.onboardingCompletionInputs(
            screenRecordingStatus: .granted,
            availableDisplayCount: 1,
            provider: .openRouter,
            providerConnectionKind: .configured
        )
        XCTAssertFalse(inputs.hasUsableProvider)
    }

    func testCliProvidersAreUsableOnlyAfterTheirConnectionCheckSucceeds() {
        for provider: ProviderChoice in [.claudeCLI, .codexCLI, .jcodeCLI] {
            let connected = ReviewAppModel.onboardingCompletionInputs(
                screenRecordingStatus: .granted,
                availableDisplayCount: 1,
                provider: provider,
                providerConnectionKind: .connected
            )
            XCTAssertTrue(connected.hasUsableProvider, "\(provider) should be usable after verification")

            let notConnected = ReviewAppModel.onboardingCompletionInputs(
                screenRecordingStatus: .granted,
                availableDisplayCount: 1,
                provider: provider,
                providerConnectionKind: .notConnected
            )
            XCTAssertFalse(notConnected.hasUsableProvider, "\(provider) must not be usable before verification")
        }
    }

}
