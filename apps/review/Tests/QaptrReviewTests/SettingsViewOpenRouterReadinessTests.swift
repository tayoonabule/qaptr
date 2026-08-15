import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// Direct tests for `SettingsView.showsOpenRouterKeyNotice`, the bounded,
/// model-only decision behind the OpenRouter recovery-action row.
///
/// These tests exercise pure decision logic driven only by
/// `ProviderConnectionState` (backed by local settings/Keychain reads) and
/// never touch the network. They assert the surface shows exactly one
/// concise status/recovery action when OpenRouter is selected and no key has
/// been saved, and stays silent for every other provider/connection
/// combination -- including states that could be mistaken for catalog or
/// model validation.
@MainActor
final class SettingsViewOpenRouterReadinessTests: XCTestCase {
    func testShowsRecoveryActionWhenOpenRouterIsSelectedAndNeedsKey() {
        XCTAssertTrue(
            SettingsView.showsOpenRouterKeyNotice(provider: .openRouter, connection: .needsKey)
        )
    }

    func testStaysSilentWhenNoProviderIsSelected() {
        XCTAssertFalse(
            SettingsView.showsOpenRouterKeyNotice(provider: nil, connection: .needsKey)
        )
    }

    func testStaysSilentForNonOpenRouterProvidersEvenIfConnectionSaysNeedsKey() {
        for provider in ProviderChoice.allCases where provider != .openRouter {
            XCTAssertFalse(
                SettingsView.showsOpenRouterKeyNotice(provider: provider, connection: .needsKey),
                "\(provider) must never show the OpenRouter key recovery action"
            )
        }
    }

    func testStaysSilentWhenOpenRouterIsAlreadyConnected() {
        XCTAssertFalse(
            SettingsView.showsOpenRouterKeyNotice(provider: .openRouter, connection: .connected)
        )
    }

    func testStaysSilentWhenOpenRouterIsNotYetConnected() {
        // `.notConnected` means no provider preference has triggered a key
        // check yet; this must not be conflated with "needs a key".
        XCTAssertFalse(
            SettingsView.showsOpenRouterKeyNotice(provider: .openRouter, connection: .notConnected)
        )
    }

    func testStaysSilentWhileOpenRouterIsChecking() {
        // Checking reflects an in-flight connection attempt, not a missing
        // key, and must not surface the "add a key" recovery action.
        XCTAssertFalse(
            SettingsView.showsOpenRouterKeyNotice(provider: .openRouter, connection: .checking)
        )
    }

    func testStaysSilentForEveryOpenRouterFailureKind() {
        // Failures (invalid key, unavailable check, unable to save) are
        // surfaced by `ProviderSetupSheet`'s own failure message, not by
        // this settings-row recovery action, so this row must stay silent
        // for all of them and never claim catalog/model validation occurred.
        let failures: [ProviderConnectionState.Failure] = [.invalidKey, .unavailable, .unableToSave]
        for failure in failures {
            XCTAssertFalse(
                SettingsView.showsOpenRouterKeyNotice(provider: .openRouter, connection: .failed(failure)),
                "Failure case \(failure) must not trigger the needs-key recovery action"
            )
        }
    }
}
