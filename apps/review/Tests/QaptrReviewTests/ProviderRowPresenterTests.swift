import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// Direct tests for `ProviderRowPresenter`, the pure decision behind
/// checklist 5.1/3.4 row 122/171: readiness, a short reason, and exactly one
/// next action per provider row. These never touch the network, Keychain, or
/// a real CLI executable -- every case is driven by an explicit input value.
final class ProviderRowPresenterTests: XCTestCase {

    // MARK: - OpenRouter

    func testOpenRouterNotConnectedShowsNoReasonOrAction() {
        let presentation = ProviderRowPresenter.present(
            provider: .openRouter, connection: .notConnected, cliReadiness: nil
        )
        XCTAssertEqual(presentation.statusLabel, "Not connected")
        XCTAssertNil(presentation.reason)
        XCTAssertNil(presentation.nextAction)
    }

    func testOpenRouterNeedsKeyShowsAddKeyAction() {
        let presentation = ProviderRowPresenter.present(
            provider: .openRouter, connection: .needsKey, cliReadiness: nil
        )
        XCTAssertEqual(presentation.statusLabel, "Add a key")
        XCTAssertNotNil(presentation.reason)
        XCTAssertEqual(presentation.nextAction, .addKey)
    }

    func testOpenRouterConfiguredShowsChangeKeyActionAndNeverClaimsConnected() {
        let presentation = ProviderRowPresenter.present(
            provider: .openRouter, connection: .configured, cliReadiness: nil
        )
        XCTAssertEqual(presentation.statusLabel, "Key saved")
        XCTAssertNotEqual(presentation.statusLabel, "Connected")
        XCTAssertEqual(presentation.nextAction, .changeKey)
    }

    func testOpenRouterConnectedShowsNoReasonButStillOffersChangeKey() {
        let presentation = ProviderRowPresenter.present(
            provider: .openRouter, connection: .connected, cliReadiness: nil
        )
        XCTAssertEqual(presentation.statusLabel, "Connected")
        XCTAssertNil(presentation.reason)
        XCTAssertEqual(presentation.nextAction, .changeKey)
    }

    func testOpenRouterFailureShowsTheUnderlyingFailureMessage() {
        for failure: ProviderConnectionState.Failure in [.invalidKey, .unavailable, .unableToSave] {
            let presentation = ProviderRowPresenter.present(
                provider: .openRouter, connection: .failed(failure), cliReadiness: nil
            )
            XCTAssertEqual(presentation.statusLabel, "Try again")
            XCTAssertEqual(presentation.reason, failure.message)
            XCTAssertEqual(presentation.nextAction, .changeKey)
        }
    }

    // MARK: - CLI providers

    func testCliProviderWithNoReadinessSnapshotYetIsNotCheckedRatherThanReady() {
        for provider: ProviderChoice in [.claudeCLI, .codexCLI, .jcodeCLI] {
            let presentation = ProviderRowPresenter.present(
                provider: provider, connection: .notConnected, cliReadiness: nil
            )
            XCTAssertEqual(presentation.statusLabel, "Not checked")
            XCTAssertNotNil(presentation.reason)
            XCTAssertNil(presentation.nextAction, "\(provider) has no in-app recovery action yet")
        }
    }

    func testDetectedCliProviderNeverClaimsUsable() {
        let readiness = ProviderReadiness(id: "codex", state: .detected, usable: false)
        let presentation = ProviderRowPresenter.present(
            provider: .codexCLI, connection: .notConnected, cliReadiness: readiness
        )
        XCTAssertEqual(presentation.statusLabel, "Installed")
        XCTAssertNotEqual(presentation.statusLabel, "Ready")
        XCTAssertNotEqual(presentation.statusLabel, "Connected")
        XCTAssertNil(presentation.nextAction)
        XCTAssertNotNil(presentation.reason)
    }

    func testNotInstalledCliProviderShowsAnInstallReason() {
        let readiness = ProviderReadiness(id: "codex", state: .notInstalled, usable: false)
        let presentation = ProviderRowPresenter.present(
            provider: .codexCLI, connection: .notConnected, cliReadiness: readiness
        )
        XCTAssertEqual(presentation.statusLabel, "Not installed")
        XCTAssertNotNil(presentation.reason)
        XCTAssertNil(presentation.nextAction)
    }

    func testUnavailableCliReadinessNeverClaimsInstalledOrNotInstalled() {
        let readiness = ProviderReadiness(id: "codex", state: .unavailable, usable: false)
        let presentation = ProviderRowPresenter.present(
            provider: .codexCLI, connection: .notConnected, cliReadiness: readiness
        )
        XCTAssertEqual(presentation.statusLabel, "Unavailable")
        XCTAssertNotNil(presentation.reason)
    }

    func testEveryPresentationShowsAtMostOneNextAction() {
        let cliStates: [ProviderInstallationState] = [.detected, .notInstalled, .unavailable]
        for provider: ProviderChoice in [.claudeCLI, .codexCLI, .jcodeCLI] {
            for state in cliStates {
                let readiness = ProviderReadiness(id: provider.rawValue, state: state, usable: false)
                let presentation = ProviderRowPresenter.present(
                    provider: provider, connection: .notConnected, cliReadiness: readiness
                )
                // Every case here already has at most one nextAction by
                // construction (Optional), but this asserts the invariant
                // explicitly so a future case addition cannot regress it.
                XCTAssertNil(presentation.nextAction, "\(provider)/\(state) must not yet offer an in-app CLI action")
            }
        }
    }
}
