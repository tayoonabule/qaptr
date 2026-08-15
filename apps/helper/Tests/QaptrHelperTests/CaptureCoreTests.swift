import Foundation
import XCTest
@testable import QaptrHelperCore

final class CaptureCoreTests: XCTestCase {
    func testCaptureProgressCountsOnlySuccessfulSealsAcrossStates() {
        var tracker = CaptureProgressTracker()
        tracker.start(at: 100, processID: 42)
        XCTAssertEqual(tracker.progress.state, .waiting)
        XCTAssertEqual(tracker.progress.captureCount, 0)
        XCTAssertEqual(tracker.progress.version, CaptureProgress.schemaVersion)
        XCTAssertEqual(tracker.progress.revision, 1)

        tracker.beginCapture(at: 200)
        XCTAssertEqual(tracker.progress.state, .capturing)
        XCTAssertEqual(tracker.progress.revision, 2)
        XCTAssertEqual(tracker.progress.lastAttemptedAtMillis, 200)
        tracker.finishCapture(at: 300, successfulCaptures: 2)
        XCTAssertEqual(tracker.progress.state, .waiting)
        XCTAssertEqual(tracker.progress.captureCount, 2)
        XCTAssertEqual(tracker.progress.lastCaptureAtMillis, 300)
        XCTAssertEqual(tracker.progress.revision, 3)

        tracker.start(at: 400, processID: 42)
        XCTAssertEqual(tracker.progress.state, .waiting)
        XCTAssertEqual(tracker.progress.captureCount, 2)
        XCTAssertEqual(tracker.progress.revision, 4)

        tracker.beginCapture(at: 500)
        tracker.finishCapture(at: 600, successfulCaptures: 0)
        XCTAssertEqual(tracker.progress.captureCount, 2)
        XCTAssertEqual(tracker.progress.lastCaptureAtMillis, 300)
        XCTAssertEqual(tracker.progress.revision, 6)
    }

    func testStartupPreflightDeniedPersistsPermissionRequiredBeforeScheduling() throws {
        let store = try temporaryProgressStore()
        let coordinator = CaptureStartupCoordinator(
            preflight: ScriptedStartupPreflight(permissionGranted: false, displayIDs: ["display-1"])
        )
        var tracker = CaptureProgressTracker()

        XCTAssertEqual(
            coordinator.prepare(
                progressTracker: &tracker,
                progressStore: store,
                at: 100,
                processID: 42,
                activeIntervalSeconds: 60
            ),
            .permissionRequired
        )

        let persisted = try store.read()
        XCTAssertEqual(persisted.state, .permissionRequired)
        XCTAssertEqual(persisted.startedAtMillis, 100)
        XCTAssertEqual(persisted.lastAttemptedAtMillis, 100)
        XCTAssertEqual(persisted.activeIntervalSeconds, 60)
        XCTAssertEqual(persisted.selectedDisplayIDs, [])
    }

    func testStartupPreflightSuccessPersistsWaitingStateAndDisplays() throws {
        let store = try temporaryProgressStore()
        let coordinator = CaptureStartupCoordinator(
            preflight: ScriptedStartupPreflight(
                permissionGranted: true,
                displayIDs: [" display-2", "display-1", "display-2"]
            )
        )
        var tracker = CaptureProgressTracker()

        XCTAssertEqual(
            coordinator.prepare(
                progressTracker: &tracker,
                progressStore: store,
                at: 200,
                processID: 42,
                activeIntervalSeconds: 60
            ),
            .ready(selectedDisplayIDs: ["display-1", "display-2"])
        )

        let persisted = try store.read()
        XCTAssertEqual(persisted.state, .waiting)
        XCTAssertEqual(persisted.startedAtMillis, 200)
        XCTAssertEqual(persisted.updatedAtMillis, 200)
        XCTAssertEqual(persisted.processID, 42)
        XCTAssertEqual(persisted.selectedDisplayIDs, ["display-1", "display-2"])
        XCTAssertEqual(persisted.activeIntervalSeconds, 60)
        XCTAssertEqual(persisted.captureCount, 0)
    }

    func testCaptureProgressV1RoundTripsFieldsWithoutImages() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-progress-\(UUID().uuidString)")
            .appendingPathComponent("capture-progress.json")
        let store = CaptureProgressStore(url: url)
        let progress = CaptureProgress(
            state: .waiting,
            captureCount: 3,
            lastCaptureAtMillis: 900,
            startedAtMillis: 100,
            updatedAtMillis: 900,
            processID: 42,
            revision: 7,
            lastAttemptedAtMillis: 850,
            selectedDisplayIDs: ["display-2", "display-1", "display-2"],
            activeIntervalSeconds: 60,
            failureReason: "  intermittent\npermission  "
        )

        try store.write(progress)
        XCTAssertEqual(try store.read(), progress)
        let json = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(json.contains("\"version\":1"))
        XCTAssertTrue(json.contains("\"revision\":7"))
        XCTAssertTrue(json.contains("\"last_attempted_at_ms\":850"))
        XCTAssertTrue(json.contains("\"selected_display_ids\":[\"display-1\",\"display-2\"]"))
        XCTAssertTrue(json.contains("\"active_interval_seconds\":60"))
        XCTAssertTrue(json.contains("\"failure_reason\":\"intermittent permission\""))
        XCTAssertFalse(json.contains("image"))
        XCTAssertFalse(json.contains("image_data"))
    }

    func testCaptureProgressDecodesLegacyStatusAsV1Defaults() throws {
        let json = """
        {"state":"waiting","capture_count":2,"last_capture_at_ms":300,"started_at_ms":100,"updated_at_ms":300,"process_id":42}
        """

        let progress = try JSONDecoder().decode(CaptureProgress.self, from: Data(json.utf8))
        XCTAssertEqual(progress.version, CaptureProgress.schemaVersion)
        XCTAssertEqual(progress.revision, 0)
        XCTAssertNil(progress.lastAttemptedAtMillis)
        XCTAssertEqual(progress.selectedDisplayIDs, [])
        XCTAssertNil(progress.activeIntervalSeconds)
        XCTAssertNil(progress.failureReason)
    }

    func testTrackerTransitionsCarryV1FieldsAndConciseFailureReason() {
        var tracker = CaptureProgressTracker()
        tracker.start(
            at: 100,
            processID: 42,
            selectedDisplayIDs: [" display-2", "display-1", "display-2"],
            activeIntervalSeconds: 60
        )
        tracker.beginCapture(at: 200)

        XCTAssertEqual(tracker.progress.selectedDisplayIDs, ["display-1", "display-2"])
        XCTAssertEqual(tracker.progress.activeIntervalSeconds, 60)
        XCTAssertEqual(tracker.progress.lastAttemptedAtMillis, 200)

        let longReason = "first line\nsecond line " + String(repeating: "x", count: 300)
        tracker.markError(at: 300, failureReason: longReason)

        XCTAssertEqual(tracker.progress.revision, 3)
        XCTAssertEqual(tracker.progress.state, .error)
        XCTAssertEqual(tracker.progress.failureReason?.prefix(22), "first line second line")
        XCTAssertEqual(tracker.progress.failureReason?.count, 256)
    }

    func testMissedTicksDoNotCatchUp() throws {
        var planner = TickPlanner(interval: try CaptureInterval(seconds: 60))
        XCTAssertEqual(planner.action(at: 0), .capture)
        XCTAssertEqual(planner.action(at: 61), .capture)
        XCTAssertEqual(planner.action(at: 62), .wait)
        XCTAssertEqual(planner.action(at: 121), .capture)
        XCTAssertEqual(planner.action(at: 122), .wait)
    }

    func testCaptureIntervalAcceptsOnlyBoundedFiveSecondSteps() throws {
        XCTAssertEqual(try CaptureInterval(seconds: 5).seconds, 5)
        XCTAssertEqual(try CaptureInterval(seconds: 300).seconds, 300)

        for invalid in [0, 4, 6, 301] {
            XCTAssertThrowsError(try CaptureInterval(seconds: invalid))
        }
    }

    func testCaptureControlPersistsOnlyTheBoundedIntervalScalar() throws {
        let control = try CaptureControl(intervalSeconds: 60)
        let encoded = try JSONEncoder().encode(control)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertEqual(json, "{\"interval_seconds\":60}")
    }

    func testDetailedCaptureLifecycleUsesExplicitStartAndStop() {
        var lifecycle = DetailedCaptureLifecycle(
            transport: ScriptedDetailedCaptureTransport(
                start: .started(intervalSeconds: 120),
                stop: .stopped
            )
        )

        XCTAssertEqual(lifecycle.start(intervalSeconds: 120), .started(intervalSeconds: 120))
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.activeIntervalSeconds, 120)
        XCTAssertEqual(lifecycle.stop(), .stopped)
        XCTAssertEqual(lifecycle.state, .stopped)
        XCTAssertNil(lifecycle.activeIntervalSeconds)
    }

    func testDetailedCaptureLifecycleReportsHelperUnavailableAndPersistsInterval() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-detailed-capture-\(UUID().uuidString)")
        let controlStore = CaptureControlStore(url: root.appendingPathComponent("capture-control.json"))
        var lifecycle = DetailedCaptureLifecycle(
            transport: UnavailableDetailedCaptureTransport(),
            controlStore: controlStore
        )

        XCTAssertEqual(lifecycle.start(intervalSeconds: 300), .helperUnavailable)
        XCTAssertEqual(lifecycle.state, .helperUnavailable)
        XCTAssertEqual(try controlStore.read(), try CaptureControl(intervalSeconds: 300))
        XCTAssertEqual(lifecycle.stop(), .alreadyStopped)
    }

    func testDetailedCaptureLifecycleReportsPermissionDeniedAndStartupFailure() {
        var denied = DetailedCaptureLifecycle(
            transport: ScriptedDetailedCaptureTransport(
                start: .permissionDenied,
                stop: .alreadyStopped
            )
        )
        XCTAssertEqual(denied.start(intervalSeconds: 60), .permissionDenied)
        XCTAssertEqual(denied.state, .permissionDenied)

        var failed = DetailedCaptureLifecycle(
            transport: ScriptedDetailedCaptureTransport(
                start: .startupFailed("helper failed during startup"),
                stop: .stopFailed("helper did not acknowledge stop")
            )
        )
        XCTAssertEqual(
            failed.start(intervalSeconds: 60),
            .startupFailed("helper failed during startup")
        )
        XCTAssertEqual(failed.state, .startupFailed)
    }

    func testSecondHelperCannotClaimTheSameOwnershipLock() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-helper-lock-\(UUID().uuidString)")
        let first = try SingleInstanceLock(path: root)
        XCTAssertThrowsError(try SingleInstanceLock(path: root)) { error in
            XCTAssertEqual(error as? SingleInstanceError, .alreadyRunning)
        }
        _ = first
    }

    func testSecondCaptureIsRefusedWhileFirstIsInFlight() throws {
        let capture = BlockingCapture()
        let sealer = RecordingSealer()
        let coordinator = CaptureCoordinator(capture: capture, sealer: sealer)
        let firstStarted = expectation(description: "first capture starts")
        capture.onStart = { firstStarted.fulfill() }
        let firstFinished = expectation(description: "first capture finishes")
        DispatchQueue.global().async {
            _ = coordinator.runTick(
                displays: ["1"],
                context: SampledContext(application: "Editor"),
                capturedAtMillis: 1_000
            ) { _ in "capture-1" }
            firstFinished.fulfill()
        }
        wait(for: [firstStarted], timeout: 1)
        XCTAssertEqual(
            coordinator.runTick(
                displays: ["1"],
                context: SampledContext(application: "Editor"),
                capturedAtMillis: 1_000
            ) { _ in "capture-2" },
            [.refusedOverlap]
        )
        capture.release()
        wait(for: [firstFinished], timeout: 1)
        XCTAssertEqual(sealer.sealed.count, 1)
        XCTAssertEqual(sealer.capturedAtMillis, [1_000])
    }

    func testPermissionRevocationIsQuietlySkippedByTheCallerBoundary() {
        let coordinator = CaptureCoordinator(capture: ImmediateCapture(), sealer: RecordingSealer())
        XCTAssertEqual(
            coordinator.runTick(
                displays: ["1"],
                context: SampledContext(application: "Editor"),
                capturedAtMillis: 1_000,
                permissionGranted: false
            ) { _ in "capture-1" },
            [.skippedPermission]
        )
    }

    func testSealedEventPersistsWaitingStatusAndIncrementsCaptureCount() throws {
        var tracker = CaptureProgressTracker()
        tracker.start(at: 100, processID: 42, selectedDisplayIDs: ["display-1"], activeIntervalSeconds: 60)
        tracker.beginCapture(at: 200)
        let event = CaptureEvent.sealed(captureID: "capture-1", displayID: "display-1", width: 1_920, height: 1_080)

        if case .sealed = event {
            tracker.finishCapture(at: 300, successfulCaptures: 1, selectedDisplayIDs: ["display-1"], activeIntervalSeconds: 60)
        }
        let persisted = try persistAndRead(tracker.progress)

        XCTAssertEqual(persisted.state, .waiting)
        XCTAssertEqual(persisted.captureCount, 1)
        XCTAssertEqual(persisted.lastCaptureAtMillis, 300)
        XCTAssertNil(persisted.failureReason)
    }

    func testRefusedOverlapEventPersistsWaitingStatusWithoutCountingCapture() throws {
        var tracker = CaptureProgressTracker()
        tracker.start(at: 100, processID: 42)
        tracker.beginCapture(at: 200)
        let event = CaptureEvent.refusedOverlap

        if case .refusedOverlap = event {
            tracker.finishCapture(at: 300, successfulCaptures: 0)
        }
        let persisted = try persistAndRead(tracker.progress)

        XCTAssertEqual(persisted.state, .waiting)
        XCTAssertEqual(persisted.captureCount, 0)
        XCTAssertNil(persisted.lastCaptureAtMillis)
        XCTAssertNil(persisted.failureReason)
    }

    func testSkippedPermissionEventPersistsPermissionRequiredStatus() throws {
        var tracker = CaptureProgressTracker()
        let event = CaptureEvent.skippedPermission

        if case .skippedPermission = event {
            tracker.markPermissionRequired(at: 300, selectedDisplayIDs: ["display-1"], activeIntervalSeconds: 60)
        }
        let persisted = try persistAndRead(tracker.progress)

        XCTAssertEqual(persisted.state, .permissionRequired)
        XCTAssertEqual(persisted.lastAttemptedAtMillis, 300)
        XCTAssertEqual(persisted.selectedDisplayIDs, ["display-1"])
    }

    func testSkippedNoDisplaysEventPersistsNoDisplaysStatus() throws {
        var tracker = CaptureProgressTracker()
        let event = CaptureEvent.skippedNoDisplays

        if case .skippedNoDisplays = event {
            tracker.markNoDisplays(at: 300, selectedDisplayIDs: [], activeIntervalSeconds: 60)
        }
        let persisted = try persistAndRead(tracker.progress)

        XCTAssertEqual(persisted.state, .noDisplays)
        XCTAssertEqual(persisted.lastAttemptedAtMillis, 300)
        XCTAssertEqual(persisted.selectedDisplayIDs, [])
    }

    func testSkippedCaptureEventPersistsWaitingStatusAndFailureReason() throws {
        var tracker = CaptureProgressTracker()
        tracker.start(at: 100, processID: 42)
        tracker.beginCapture(at: 200)
        let event = CaptureEvent.skippedCapture(displayID: "display-1", reason: "camera unavailable")

        if case let .skippedCapture(displayID, reason) = event {
            tracker.finishCapture(
                at: 300,
                successfulCaptures: 0,
                selectedDisplayIDs: [displayID],
                activeIntervalSeconds: 60,
                failureReason: "capture failed on \(displayID): \(reason)"
            )
        }
        let persisted = try persistAndRead(tracker.progress)

        XCTAssertEqual(persisted.state, .waiting)
        XCTAssertEqual(persisted.captureCount, 0)
        XCTAssertEqual(persisted.failureReason, "capture failed on display-1: camera unavailable")
    }

    func testSkippedSealingEventPersistsWaitingStatusAndFailureReason() throws {
        var tracker = CaptureProgressTracker()
        tracker.start(at: 100, processID: 42)
        tracker.beginCapture(at: 200)
        let event = CaptureEvent.skippedSealing(displayID: "display-1", reason: "vault unavailable")

        if case let .skippedSealing(displayID, reason) = event {
            tracker.finishCapture(
                at: 300,
                successfulCaptures: 0,
                selectedDisplayIDs: [displayID],
                activeIntervalSeconds: 60,
                failureReason: "sealing failed on \(displayID): \(reason)"
            )
        }
        let persisted = try persistAndRead(tracker.progress)

        XCTAssertEqual(persisted.state, .waiting)
        XCTAssertEqual(persisted.captureCount, 0)
        XCTAssertEqual(persisted.failureReason, "sealing failed on display-1: vault unavailable")
    }

    func testBrowserContextDropsPathQueryAndFragment() {
        XCTAssertEqual(reducedBrowserHost(from: "https://example.com/private?q=secret#fragment"), "https://example.com")
        XCTAssertNil(reducedBrowserHost(from: "not a url"))
    }

    func testSealingFailureDoesNotProduceASealedEvent() throws {
        let capture = ImmediateCapture()
        let sealer = FailingSealer()
        let coordinator = CaptureCoordinator(capture: capture, sealer: sealer)
        XCTAssertEqual(
            coordinator.runTick(
                displays: ["1"],
                context: SampledContext(application: "Editor"),
                capturedAtMillis: 1_000
            ) { _ in "capture-1" },
            [.skippedSealing(displayID: "1", reason: "Error Domain=tests Code=1 \"intentional failure\" UserInfo={NSLocalizedDescription=intentional failure}")]
        )
    }

    func testFixtureIngestionSealsRecordsAndPersistsOnlyScalarStatus() throws {
        let manifest = try FixtureManifest(csv: """
        capture_id,source,captured_at_ms
        capture-01,text,0
        capture-02,rotated,600000
        """)
        let statusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-fixture-status-\(UUID().uuidString)")
            .appendingPathComponent("capture-progress.json")
        let sealer = RecordingSealer()

        let result = try FixtureIngestion.run(
            manifest: manifest,
            capture: ImmediateCapture(),
            sealer: sealer,
            context: SampledContext(application: "fixture"),
            progressStore: CaptureProgressStore(url: statusURL),
            intervalSeconds: 5,
            maxDimension: 1_920,
            processID: 42,
            at: 1_000
        )

        XCTAssertEqual(result, FixtureIngestionResult(attemptedCount: 2, sealedCount: 2, failedCount: 0))
        XCTAssertEqual(sealer.sealed, ["capture-01", "capture-02"])
        XCTAssertEqual(sealer.capturedAtMillis, [0, 600_000])
        let progress = try CaptureProgressStore(url: statusURL).read()
        XCTAssertEqual(progress.state, .waiting)
        XCTAssertEqual(progress.captureCount, 2)
        XCTAssertEqual(progress.lastCaptureAtMillis, 1_000)
        XCTAssertEqual(progress.selectedDisplayIDs, ["fixture"])
        let json = String(decoding: try Data(contentsOf: statusURL), as: UTF8.self)
        XCTAssertFalse(json.contains("image"))
        XCTAssertFalse(json.contains("text"))
        XCTAssertFalse(json.contains("600000"))
    }

    func testFixtureManifestRejectsUnsafeImagePaths() {
        XCTAssertThrowsError(
            try FixtureManifest(csv: """
            capture_id,source,captured_at_ms
            capture-01,../private.png,0
            """)
        ) { error in
            XCTAssertEqual(error as? FixtureManifestError, .invalidSource("../private.png"))
        }
    }
}

private extension CaptureCoreTests {
    func temporaryProgressStore() throws -> CaptureProgressStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-startup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return CaptureProgressStore(url: root.appendingPathComponent("capture-progress.json"))
    }

    func persistAndRead(_ progress: CaptureProgress) throws -> CaptureProgress {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-capture-event-status-\(UUID().uuidString)")
            .appendingPathComponent("capture-progress.json")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        let store = CaptureProgressStore(url: url)
        try store.write(progress)
        return try store.read()
    }
}

private struct ScriptedStartupPreflight: CaptureStartupPreflight {
    let permissionGranted: Bool
    let displayIDs: [String]

    func screenRecordingAccessGranted() -> Bool {
        permissionGranted
    }

    func availableDisplayIDs() throws -> [String] {
        displayIDs
    }
}

private final class BlockingCapture: ImageCapture, @unchecked Sendable {
    var onStart: (() -> Void)?
    private let started = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func capture(displayID: String, maxDimension: Int) throws -> CapturedFrame {
        _ = displayID
        _ = maxDimension
        onStart?()
        started.signal()
        releaseSemaphore.wait()
        return try CapturedFrame(imageData: Data([1]), width: 1, height: 1)
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private struct ScriptedDetailedCaptureTransport: DetailedCaptureTransport {
    let start: DetailedCaptureStartResult
    let stop: DetailedCaptureStopResult

    func startDetailedCapture(intervalSeconds: Int) -> DetailedCaptureStartResult {
        _ = intervalSeconds
        return start
    }

    func stopDetailedCapture() -> DetailedCaptureStopResult {
        stop
    }
}

private final class ImmediateCapture: ImageCapture, @unchecked Sendable {
    func capture(displayID: String, maxDimension: Int) throws -> CapturedFrame {
        _ = displayID
        _ = maxDimension
        return try CapturedFrame(imageData: Data([1]), width: 1, height: 1)
    }
}

private final class RecordingSealer: BundleSealer, @unchecked Sendable {
    private(set) var sealed: [String] = []
    private(set) var capturedAtMillis: [Int64] = []

    func seal(
        captureID: String,
        capturedAtMillis: Int64,
        frame: CapturedFrame,
        context: SampledContext
    ) throws {
        _ = frame
        _ = context
        sealed.append(captureID)
        self.capturedAtMillis.append(capturedAtMillis)
    }
}

private struct FailingSealer: BundleSealer {
    func seal(
        captureID: String,
        capturedAtMillis: Int64,
        frame: CapturedFrame,
        context: SampledContext
    ) throws {
        _ = captureID
        _ = capturedAtMillis
        _ = frame
        _ = context
        throw NSError(domain: "tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "intentional failure"])
    }
}
