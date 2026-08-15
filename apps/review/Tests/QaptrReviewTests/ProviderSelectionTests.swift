import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// A deterministic, in-memory stand-in for `KeychainProviderCredentialStore`
/// so provider-selection behavior is testable without touching the real
/// macOS Keychain.
private final class FakeProviderCredentialStore: ProviderCredentialStoring {
    var storedKey: String?

    func containsOpenRouterKey() -> Bool { storedKey != nil }

    func saveOpenRouterKey(_ key: String) throws {
        storedKey = key
    }

    func removeOpenRouterKey() throws {
        storedKey = nil
    }
}

/// A deterministic stand-in for `OpenRouterConnectionChecker` that never
/// touches the network. Tests configure `result` up front; `startOpenRouterConnectionCheck`
/// is not exercised by these tests, so the async body is never invoked in
/// this file, but the type must still conform.
private struct FakeOpenRouterChecker: OpenRouterChecking {
    var result: ProviderConnectionState = .connected

    func check(apiKey: String) async -> ProviderConnectionState {
        result
    }
}

/// Direct tests for `ReviewAppModel.connectProvider` / `openProviderSetup`,
/// the provider-selection behavior reported by the user: selecting
/// OpenRouter must refresh truthful saved/verified state, but must only
/// auto-open the setup sheet when no key exists yet. A saved key must not
/// trigger the sheet just from re-selecting the provider; only the explicit
/// "Change key" action (`openProviderSetup`) does that.
@MainActor
final class ProviderSelectionTests: XCTestCase {
    private func makeModel(storedKey: String? = nil) -> (ReviewAppModel, FakeProviderCredentialStore) {
        let credentialStore = FakeProviderCredentialStore()
        credentialStore.storedKey = storedKey
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        let model = ReviewAppModel(
            preferences: preferences,
            credentialStore: credentialStore,
            openRouterChecker: FakeOpenRouterChecker()
        )
        return (model, credentialStore)
    }

    func testSelectingOpenRouterWithNoSavedKeyAutoOpensSetup() {
        let (model, _) = makeModel(storedKey: nil)

        model.connectProvider(.openRouter)

        XCTAssertEqual(model.settings.provider, .openRouter)
        XCTAssertEqual(model.providerConnection, .needsKey)
        XCTAssertEqual(model.providerSetupRequest, .openRouter, "No key exists yet, so setup must open automatically")
    }

    func testSelectingOpenRouterWithASavedKeyDoesNotAutoOpenSetup() {
        let (model, _) = makeModel(storedKey: "sk-existing")

        model.connectProvider(.openRouter)

        XCTAssertEqual(model.settings.provider, .openRouter)
        XCTAssertEqual(model.providerConnection, .configured, "A saved key must report configured, not needsKey")
        XCTAssertNil(model.providerSetupRequest, "A saved key must not force the setup sheet open just by selecting it")
    }

    func testReselectingAnAlreadySelectedSavedKeyProviderStillDoesNotOpenSetup() {
        let (model, _) = makeModel(storedKey: "sk-existing")
        model.connectProvider(.openRouter)
        XCTAssertNil(model.providerSetupRequest)

        // Clicking the already-selected provider row again (the exact bug
        // report) must not reopen the sheet.
        model.connectProvider(.openRouter)

        XCTAssertNil(model.providerSetupRequest)
        XCTAssertEqual(model.providerConnection, .configured)
    }

    func testOpenProviderSetupIsTheExplicitChangeKeyAction() {
        let (model, _) = makeModel(storedKey: "sk-existing")
        model.connectProvider(.openRouter)
        XCTAssertNil(model.providerSetupRequest)

        model.openProviderSetup()

        XCTAssertEqual(model.providerSetupRequest, .openRouter, "The explicit Change key action must always open the sheet")
    }

    func testOpenProviderSetupIsANoOpWhenOpenRouterIsNotTheSelectedProvider() {
        let (model, _) = makeModel(storedKey: "sk-existing")
        model.connectProvider(.claudeCLI)

        model.openProviderSetup()

        XCTAssertNil(model.providerSetupRequest, "Change key must never open OpenRouter setup for an unrelated provider")
    }

    func testSelectingANonOpenRouterProviderNeverRequestsSetup() {
        let (model, _) = makeModel(storedKey: nil)

        for provider: ProviderChoice in [.claudeCLI, .codexCLI, .jcodeCLI] {
            model.connectProvider(provider)
            XCTAssertNil(model.providerSetupRequest, "\(provider) must never request the OpenRouter setup sheet")
        }
    }

    func testKeySavedStateIsDistinctFromConnectedState() {
        // `configured` (a local Keychain key exists) must never claim the
        // stronger `connected` (network-verified) state.
        XCTAssertNotEqual(ProviderConnectionState.configured, ProviderConnectionState.connected)
        XCTAssertEqual(ProviderConnectionState.configured.title, "Key saved")
        XCTAssertEqual(ProviderConnectionState.connected.title, "Connected")
    }
}

/// Direct tests for `SettingsView.showsOpenRouterChangeKeyAction`, the pure
/// decision behind the explicit, accessible "Change key" action. This row
/// must appear once a key exists in any form (saved, checking, connected, or
/// a failed re-check) so a saved key is never a dead end, but must stay
/// silent before any key exists (that state is covered by the separate
/// "Add key" recovery notice instead).
@MainActor
final class SettingsViewOpenRouterChangeKeyActionTests: XCTestCase {
    func testShowsForConfiguredSavedKey() {
        XCTAssertTrue(
            SettingsView.showsOpenRouterChangeKeyAction(provider: .openRouter, connection: .configured)
        )
    }

    func testShowsWhenConnected() {
        XCTAssertTrue(
            SettingsView.showsOpenRouterChangeKeyAction(provider: .openRouter, connection: .connected)
        )
    }

    func testShowsWhileChecking() {
        XCTAssertTrue(
            SettingsView.showsOpenRouterChangeKeyAction(provider: .openRouter, connection: .checking)
        )
    }

    func testShowsForEveryFailureKindSinceAKeyWasAlreadySubmitted() {
        let failures: [ProviderConnectionState.Failure] = [.invalidKey, .unavailable, .unableToSave]
        for failure in failures {
            XCTAssertTrue(
                SettingsView.showsOpenRouterChangeKeyAction(provider: .openRouter, connection: .failed(failure)),
                "Failure case \(failure) must still offer a way to change the key"
            )
        }
    }

    func testStaysSilentBeforeAnyKeyExists() {
        XCTAssertFalse(
            SettingsView.showsOpenRouterChangeKeyAction(provider: .openRouter, connection: .needsKey)
        )
    }

    func testStaysSilentWhenNotYetConnected() {
        XCTAssertFalse(
            SettingsView.showsOpenRouterChangeKeyAction(provider: .openRouter, connection: .notConnected)
        )
    }

    func testStaysSilentForNonOpenRouterProviders() {
        for provider in ProviderChoice.allCases where provider != .openRouter {
            XCTAssertFalse(
                SettingsView.showsOpenRouterChangeKeyAction(provider: provider, connection: .configured),
                "\(provider) must never show the OpenRouter change-key action"
            )
        }
    }

    func testStaysSilentWhenNoProviderIsSelected() {
        XCTAssertFalse(
            SettingsView.showsOpenRouterChangeKeyAction(provider: nil, connection: .configured)
        )
    }
}
