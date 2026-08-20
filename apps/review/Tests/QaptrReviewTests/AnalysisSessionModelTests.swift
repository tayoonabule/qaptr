import Foundation
import XCTest
import QaptrReviewCore
@testable import QaptrReview

@MainActor
final class AnalysisSessionModelTests: XCTestCase {
    func testVerifiedCLIFlowWaitsForExplicitConsentAndCompletes() async throws {
        let fixture = try makeFixture()
        let session = FakeAnalysisSession(
            states: [
                makeState(phase: .readyForConsent, consent: consentSummary),
                makeState(
                    phase: .completed,
                    observationsWritten: 2,
                    outcome: "provider_completed",
                    allowed: ["state", "start", "retry"]
                ),
            ]
        )
        let recorder = ProviderRecorder()
        let model = ReviewAppModel(
            preferences: fixture.preferences,
            credentialStore: EmptyCredentialStore(),
            openRouterChecker: UnusedOpenRouterChecker(),
            progressReader: fixture.progressReader,
            controlStore: fixture.controlStore,
            cliProviderChecker: ConnectedCLIChecker(),
            analysisSessionFactory: { providerID in
                recorder.providerID = providerID
                return session
            },
            storePath: fixture.storePath
        )

        model.connectProvider(.jcodeCLI)
        await waitUntil { model.providerConnection == .connected }
        model.startAnalysis()

        XCTAssertEqual(recorder.providerID, "jcode")
        XCTAssertEqual(model.analysisSessionState.phase, .ingesting)
        XCTAssertEqual(session.consentDecisions, [])

        await waitUntil { model.analysisSessionState.phase == .readyForConsent }
        XCTAssertEqual(model.analysisSessionState.consentSummary, consentSummary)
        XCTAssertEqual(session.consentDecisions, [])

        model.decideAnalysisConsent(granted: true)
        XCTAssertEqual(session.consentDecisions, [true])
        await waitUntil { model.analysisSessionState.phase == .completed }
        XCTAssertEqual(model.analysisSessionState.observationsWritten, 2)
        XCTAssertNil(model.analysisError)
    }

    func testDecliningConsentCompletesWithoutInvokingAgain() async throws {
        let fixture = try makeFixture()
        let session = FakeAnalysisSession(states: [makeState(phase: .readyForConsent, consent: consentSummary)])
        let model = ReviewAppModel(
            preferences: fixture.preferences,
            credentialStore: EmptyCredentialStore(),
            openRouterChecker: UnusedOpenRouterChecker(),
            progressReader: fixture.progressReader,
            controlStore: fixture.controlStore,
            cliProviderChecker: ConnectedCLIChecker(),
            analysisSessionFactory: { _ in session },
            storePath: fixture.storePath
        )

        model.connectProvider(.codexCLI)
        await waitUntil { model.providerConnection == .connected }
        model.startAnalysis()
        await waitUntil { model.analysisSessionState.phase == .readyForConsent }
        session.decisionResult = makeState(
            phase: .completed,
            outcome: "consent_declined",
            allowed: ["state", "start", "retry"]
        )

        model.decideAnalysisConsent(granted: false)

        XCTAssertEqual(session.consentDecisions, [false])
        XCTAssertEqual(model.analysisSessionState.phase, .completed)
        XCTAssertEqual(model.analysisSessionState.outcome, "consent_declined")
        XCTAssertEqual(model.analysisSessionState.observationsWritten, 0)
    }

    func testAnalysisRequiresAConnectedCLIProvider() throws {
        let fixture = try makeFixture()
        let model = ReviewAppModel(
            preferences: fixture.preferences,
            credentialStore: EmptyCredentialStore(),
            openRouterChecker: UnusedOpenRouterChecker(),
            progressReader: fixture.progressReader,
            controlStore: fixture.controlStore,
            cliProviderChecker: ConnectedCLIChecker(),
            analysisSessionFactory: { _ in XCTFail("factory must not be called"); return FakeAnalysisSession(states: []) },
            storePath: fixture.storePath
        )

        model.startAnalysis()

        XCTAssertEqual(model.analysisError, "Choose and connect a local CLI provider in Settings.")
        XCTAssertEqual(model.analysisSessionState, .idle)
    }

    private func makeFixture() throws -> (
        preferences: SettingsPreferences,
        progressReader: CaptureProgressReader,
        controlStore: CaptureControlStore,
        storePath: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-analysis-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let progressURL = root.appendingPathComponent("capture-progress.json")
        let controlURL = root.appendingPathComponent("capture-control.json")
        try CaptureControlStore(url: controlURL).write(.default)
        return (
            SettingsPreferences(store: InMemoryPreferenceStore()),
            CaptureProgressReader(url: progressURL),
            CaptureControlStore(url: controlURL),
            root.appendingPathComponent("history.sqlite3")
        )
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
}

private let consentSummary = ReviewConsentSummary(
    provider: "jcode",
    resolvedModel: nil,
    modelLabel: "Provider default",
    payloadKind: "text",
    captureCount: 2,
    imageCount: 0,
    exclusionCount: 1
)

private func makeState(
    phase: ReviewSessionPhase,
    consent: ReviewConsentSummary? = nil,
    observationsWritten: Int = 0,
    outcome: String? = nil,
    allowed: Set<String>? = nil
) -> ReviewSessionState {
    ReviewSessionState(
        sessionID: "session-test",
        phase: phase,
        capturesSeen: 3,
        preparedCaptures: 2,
        imageCount: 0,
        exclusionCount: 1,
        observationsWritten: observationsWritten,
        consentSummary: consent,
        result: phase == .completed ? "completed" : nil,
        outcome: outcome,
        error: nil,
        resultProvider: phase == .completed && outcome == "provider_completed" ? "jcode" : nil,
        resultModelLabel: phase == .completed && outcome == "provider_completed" ? "Provider default" : nil,
        allowedOperations: allowed ?? ["state", "cancel"]
    )
}

private final class FakeAnalysisSession: AnalysisSessionControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ReviewSessionState]
    var decisionResult = makeState(phase: .analyzing)
    private(set) var consentDecisions: [Bool] = []

    init(states: [ReviewSessionState]) {
        self.states = states
    }

    func state() throws -> ReviewSessionState {
        lock.withLock {
            states.isEmpty ? decisionResult : states.removeFirst()
        }
    }

    func start(sessionID: String) throws -> ReviewSessionState {
        _ = sessionID
        return makeState(phase: .ingesting)
    }

    func decideConsent(granted: Bool) throws -> ReviewSessionState {
        lock.withLock {
            consentDecisions.append(granted)
            return decisionResult
        }
    }

    func cancel() throws -> ReviewSessionState { makeState(phase: .cancelled, allowed: ["state", "start", "retry"]) }
    func retry() throws -> ReviewSessionState { makeState(phase: .ingesting) }
}

private final class ProviderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var providerID: String? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private struct ConnectedCLIChecker: CLIProviderChecking {
    func check(providerID: String) async -> CLIProviderConnectionResult {
        _ = providerID
        return .connected
    }
}

private struct UnusedOpenRouterChecker: OpenRouterChecking {
    func check(apiKey: String) async -> ProviderConnectionState {
        _ = apiKey
        return .failed(.unavailable)
    }
}

private struct EmptyCredentialStore: ProviderCredentialStoring {
    func containsOpenRouterKey() -> Bool { false }
    func saveOpenRouterKey(_ key: String) throws { _ = key }
    func removeOpenRouterKey() throws {}
}
