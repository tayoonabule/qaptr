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
            .notConnected, .needsKey, .checking, .failed(.invalidKey), .failed(.unavailable), .failed(.unableToSave),
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

    func testCliProvidersDoNotBlockCompletionSinceNoReadinessCheckExistsYet() {
        // This is a truthfully reported gap, not a fake pass: no CLI
        // readiness check exists anywhere in the codebase yet (a separate,
        // still-open checklist 5.1 item), so treating a CLI provider
        // selection as blocking would durably brick onboarding with no
        // recovery UI. Matching the provider's pre-existing behavior (no
        // block) is the truthful choice until that check exists.
        for provider: ProviderChoice in [.claudeCLI, .codexCLI, .jcodeCLI] {
            let inputs = ReviewAppModel.onboardingCompletionInputs(
                screenRecordingStatus: .granted,
                availableDisplayCount: 1,
                provider: provider,
                providerConnectionKind: .notConnected
            )
            XCTAssertTrue(inputs.hasUsableProvider, "\(provider) should not block onboarding completion")
        }
    }

}
