import XCTest
@testable import QaptrReview
import QaptrReviewCore

private struct CaptureControlTestCredentialStore: ProviderCredentialStoring {
    func containsOpenRouterKey() -> Bool { false }
    func saveOpenRouterKey(_ key: String) throws { _ = key }
    func removeOpenRouterKey() throws {}
}

private struct CaptureControlTestOpenRouterChecker: OpenRouterChecking {
    func check(apiKey: String) async -> ProviderConnectionState {
        _ = apiKey
        return .connected
    }
}

@MainActor
final class CaptureControlModelTests: XCTestCase {
    private func makeModel(
        intervalSeconds: Int = 120,
        intent: CaptureControlIntent = .running
    ) throws -> (ReviewAppModel, CaptureControlStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-capture-control-model-\(UUID().uuidString)")
        let controlStore = CaptureControlStore(url: root.appendingPathComponent("capture-control.json"))
        try controlStore.write(try CaptureControl(intervalSeconds: intervalSeconds, intent: intent))
        let progressReader = CaptureProgressReader(url: root.appendingPathComponent("capture-progress.json"))
        let model = ReviewAppModel(
            preferences: SettingsPreferences(store: InMemoryPreferenceStore()),
            credentialStore: CaptureControlTestCredentialStore(),
            openRouterChecker: CaptureControlTestOpenRouterChecker(),
            progressReader: progressReader,
            controlStore: controlStore
        )
        return (model, controlStore)
    }

    func testPauseAndResumePersistIntentWhilePreservingInterval() throws {
        let (model, controlStore) = try makeModel()
        XCTAssertEqual(model.captureControlIntent, .running)
        XCTAssertEqual(model.captureIntervalSeconds, 120)

        model.pauseCapture()
        XCTAssertEqual(model.captureControlIntent, .paused)
        XCTAssertEqual(
            try controlStore.read(),
            try CaptureControl(intervalSeconds: 120, intent: .paused)
        )

        model.setCaptureIntervalSeconds(300)
        XCTAssertEqual(
            try controlStore.read(),
            try CaptureControl(intervalSeconds: 300, intent: .paused)
        )

        model.resumeCapture()
        XCTAssertEqual(model.captureControlIntent, .running)
        XCTAssertEqual(
            try controlStore.read(),
            try CaptureControl(intervalSeconds: 300, intent: .running)
        )
    }

    func testModelLoadsPausedIntentFromExistingControlFile() throws {
        let (model, _) = try makeModel(intervalSeconds: 60, intent: .paused)
        XCTAssertEqual(model.captureControlIntent, .paused)
        XCTAssertEqual(model.captureIntervalSeconds, 60)
    }

    func testRefreshPublishesLivenessWhenAnOtherwiseUnchangedHelperSnapshotGoesStale() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-capture-liveness-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controlStore = CaptureControlStore(url: root.appendingPathComponent("capture-control.json"))
        try controlStore.write(try CaptureControl(intervalSeconds: 60, intent: .running))
        let progressURL = root.appendingPathComponent("capture-progress.json")

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        helper.arguments = ["0.1"]
        try helper.run()
        let progress = CaptureProgressSnapshot(
            state: .waiting,
            captureCount: 1,
            processID: Int64(helper.processIdentifier)
        )
        try JSONEncoder().encode(progress).write(to: progressURL, options: .atomic)

        let model = ReviewAppModel(
            preferences: SettingsPreferences(store: InMemoryPreferenceStore()),
            credentialStore: CaptureControlTestCredentialStore(),
            openRouterChecker: CaptureControlTestOpenRouterChecker(),
            progressReader: CaptureProgressReader(url: progressURL),
            controlStore: controlStore,
            helperHeartbeatProcessID: {
                helper.isRunning ? Int(helper.processIdentifier) : nil
            },
            storePath: root.appendingPathComponent("history.sqlite3")
        )
        XCTAssertTrue(model.captureHelperIsRunning)
        XCTAssertTrue(model.captureHelperProcessExists)

        helper.waitUntilExit()
        model.refreshCaptureProgress()

        XCTAssertFalse(model.captureHelperIsRunning)
        XCTAssertFalse(model.captureHelperProcessExists)
    }
}
