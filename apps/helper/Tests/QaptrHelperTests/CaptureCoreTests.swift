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
            _ = coordinator.runTick(displays: ["1"], context: SampledContext(application: "Editor")) { _ in "capture-1" }
            firstFinished.fulfill()
        }
        wait(for: [firstStarted], timeout: 1)
        XCTAssertEqual(
            coordinator.runTick(displays: ["1"], context: SampledContext(application: "Editor")) { _ in "capture-2" },
            [.refusedOverlap]
        )
        capture.release()
        wait(for: [firstFinished], timeout: 1)
        XCTAssertEqual(sealer.sealed.count, 1)
    }

    func testPermissionRevocationIsQuietlySkippedByTheCallerBoundary() {
        let coordinator = CaptureCoordinator(capture: ImmediateCapture(), sealer: RecordingSealer())
        XCTAssertEqual(
            coordinator.runTick(
                displays: ["1"],
                context: SampledContext(application: "Editor"),
                permissionGranted: false
            ) { _ in "capture-1" },
            [.skippedPermission]
        )
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
            coordinator.runTick(displays: ["1"], context: SampledContext(application: "Editor")) { _ in "capture-1" },
            [.skippedSealing(displayID: "1", reason: "Error Domain=tests Code=1 \"intentional failure\" UserInfo={NSLocalizedDescription=intentional failure}")]
        )
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

private final class ImmediateCapture: ImageCapture, @unchecked Sendable {
    func capture(displayID: String, maxDimension: Int) throws -> CapturedFrame {
        _ = displayID
        _ = maxDimension
        return try CapturedFrame(imageData: Data([1]), width: 1, height: 1)
    }
}

private final class RecordingSealer: BundleSealer, @unchecked Sendable {
    private(set) var sealed: [String] = []
    func seal(captureID: String, frame: CapturedFrame, context: SampledContext) throws {
        _ = frame
        _ = context
        sealed.append(captureID)
    }
}

private struct FailingSealer: BundleSealer {
    func seal(captureID: String, frame: CapturedFrame, context: SampledContext) throws {
        _ = captureID
        _ = frame
        _ = context
        throw NSError(domain: "tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "intentional failure"])
    }
}
