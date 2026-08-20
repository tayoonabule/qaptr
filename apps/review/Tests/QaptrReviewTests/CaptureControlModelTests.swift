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
}
