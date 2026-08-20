import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// A deterministic, in-memory stand-in for `KeychainProviderCredentialStore`
/// so provider-selection behavior is testable without touching the real
/// macOS Keychain.
private final class FakeProviderCredentialStore: ProviderCredentialStoring {
    var storedKey: String?
    private(set) var containsCallCount = 0

    func containsOpenRouterKey() -> Bool {
        containsCallCount += 1
        return storedKey != nil
    }

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

private actor DelayedOpenRouterChecker: OpenRouterChecking {
    private var continuation: CheckedContinuation<ProviderConnectionState, Never>?
    private(set) var started = false

    func check(apiKey: String) async -> ProviderConnectionState {
        _ = apiKey
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ result: ProviderConnectionState) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private struct FakeCLIProviderChecker: CLIProviderChecking {
    var result: CLIProviderConnectionResult = .connected

    func check(providerID: String) async -> CLIProviderConnectionResult {
        _ = providerID
        return result
    }
}

private actor MutableCLIProviderChecker: CLIProviderChecking {
    private var result: CLIProviderConnectionResult

    init(result: CLIProviderConnectionResult) {
        self.result = result
    }

    func check(providerID: String) async -> CLIProviderConnectionResult {
        _ = providerID
        return result
    }

    func setResult(_ result: CLIProviderConnectionResult) {
        self.result = result
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
    private func makeModel(
        storedKey: String? = nil,
        cliResult: CLIProviderConnectionResult = .connected,
        openRouterChecker: any OpenRouterChecking = FakeOpenRouterChecker(),
        cliProviderChecker: (any CLIProviderChecking)? = nil,
        onboardingCompleted: Bool = false
    ) -> (ReviewAppModel, FakeProviderCredentialStore) {
        let credentialStore = FakeProviderCredentialStore()
        credentialStore.storedKey = storedKey
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.onboardingCompleted = onboardingCompleted
        let model = ReviewAppModel(
            preferences: preferences,
            credentialStore: credentialStore,
            openRouterChecker: openRouterChecker,
            cliProviderChecker: cliProviderChecker ?? FakeCLIProviderChecker(result: cliResult)
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

    func testOnboardingAndPassiveRowsDoNotReadKeychain() {
        let (model, credentialStore) = makeModel(storedKey: "sk-existing")

        _ = model.providerRowPresentation(for: .openRouter)
        _ = model.providerRowPresentation(for: .claudeCLI)

        XCTAssertEqual(credentialStore.containsCallCount, 0)
        XCTAssertEqual(model.providerConnection, .notConnected)
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

    func testSelectedCLIShowsConnectedOnlyAfterItsVerificationSucceeds() async {
        let (model, _) = makeModel()

        model.connectProvider(.codexCLI)
        XCTAssertEqual(model.providerConnection, .checking)
        await waitUntil { model.providerConnection == .connected }

        XCTAssertEqual(model.providerConnection, .connected)
        XCTAssertEqual(model.settings.provider, .codexCLI)
    }

    func testSelectedCLIFailureStaysAnErrorWithSafeRecoveryCopy() async {
        let (model, _) = makeModel(cliResult: .failed(.notAuthenticated))

        model.connectProvider(.claudeCLI)
        await waitUntil { model.providerConnection == .failed(.cli(.notAuthenticated)) }

        XCTAssertEqual(model.providerConnection, .failed(.cli(.notAuthenticated)))
        XCTAssertEqual(
            model.providerRowPresentation(for: .claudeCLI).reason,
            "Sign in with this CLI, then select it again."
        )
    }

    func testSwitchingToACLIAndBackPreservesTheSavedOpenRouterKey() async {
        let (model, credentialStore) = makeModel(storedKey: "sk-existing")

        model.connectProvider(.jcodeCLI)
        await waitUntil { model.providerConnection == .connected }
        model.connectProvider(.openRouter)

        XCTAssertEqual(credentialStore.storedKey, "sk-existing")
        XCTAssertEqual(model.providerConnection, .configured)
        XCTAssertNil(model.providerSetupRequest)
    }

    func testStaleOpenRouterCheckCannotConnectANewlySelectedCLI() async {
        let delayedChecker = DelayedOpenRouterChecker()
        let (model, _) = makeModel(
            cliResult: .failed(.notAuthenticated),
            openRouterChecker: delayedChecker
        )

        model.connectProvider(.openRouter)
        model.startOpenRouterConnectionCheck("sk-delayed")
        await waitUntil { await delayedChecker.started }

        model.connectProvider(.claudeCLI)
        await waitUntil { model.providerConnection == .failed(.cli(.notAuthenticated)) }
        await delayedChecker.resolve(.connected)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.settings.provider, .claudeCLI)
        XCTAssertEqual(model.providerConnection, .failed(.cli(.notAuthenticated)))
        XCTAssertFalse(model.analysisCanStart)
    }

    func testSettingsRefreshRechecksSelectedCLIAuthentication() async {
        let checker = MutableCLIProviderChecker(result: .connected)
        let (model, _) = makeModel(
            cliProviderChecker: checker,
            onboardingCompleted: true
        )

        model.connectProvider(.jcodeCLI)
        await waitUntil { model.providerConnection == .connected }

        await checker.setResult(.failed(.notAuthenticated))
        model.refreshSettings()
        await waitUntil { model.providerConnection == .failed(.cli(.notAuthenticated)) }

        XCTAssertFalse(model.analysisCanStart)
    }

    func testKeySavedStateIsDistinctFromConnectedState() {
        // `configured` (a local Keychain key exists) must never claim the
        // stronger `connected` (network-verified) state.
        XCTAssertNotEqual(ProviderConnectionState.configured, ProviderConnectionState.connected)
        XCTAssertEqual(ProviderConnectionState.configured.title, "Key saved")
        XCTAssertEqual(ProviderConnectionState.connected.title, "Connected")
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let completed = await condition()
        XCTAssertTrue(completed)
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
