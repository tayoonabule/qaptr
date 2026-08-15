import Foundation
import XCTest
@testable import QaptrHelperCore

final class CaptureCoreTests: XCTestCase {
    func testCaptureProgressCountsOnlySuccessfulSealsAcrossStates() {
        var tracker = CaptureProgressTracker()
        tracker.start(at: 100, processID: 42)
        XCTAssertEqual(tracker.progress.state, .waiting)
        XCTAssertEqual(tracker.progress.captureCount, 0)

        tracker.beginCapture(at: 200)
        XCTAssertEqual(tracker.progress.state, .capturing)
        tracker.finishCapture(at: 300, successfulCaptures: 2)
        XCTAssertEqual(tracker.progress.state, .waiting)
        XCTAssertEqual(tracker.progress.captureCount, 2)
        XCTAssertEqual(tracker.progress.lastCaptureAtMillis, 300)

        tracker.start(at: 400, processID: 42)
        XCTAssertEqual(tracker.progress.state, .waiting)
        XCTAssertEqual(tracker.progress.captureCount, 2)

        tracker.beginCapture(at: 500)
        tracker.finishCapture(at: 600, successfulCaptures: 0)
        XCTAssertEqual(tracker.progress.captureCount, 2)
        XCTAssertEqual(tracker.progress.lastCaptureAtMillis, 300)
    }

    func testCaptureProgressStoreRoundTripsOnlyScalarStatus() throws {
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
            processID: 42
        )

        try store.write(progress)
        XCTAssertEqual(try store.read(), progress)
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("image"))
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
