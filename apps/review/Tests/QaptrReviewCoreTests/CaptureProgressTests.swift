import Foundation
import XCTest
@testable import QaptrReviewCore

final class CaptureProgressSnapshotTests: XCTestCase {
    func testDecodesCaptureEvidenceAndDistinguishesNoObservationProgress() throws {
        let json = """
        {
          "state": "waiting",
          "capture_count": 3,
          "last_capture_at_ms": 900,
          "started_at_ms": 100,
          "updated_at_ms": 900,
          "process_id": 42
        }
        """
        let progress = try JSONDecoder().decode(CaptureProgressSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(progress.captureCount, 3)
        XCTAssertEqual(progress.lastCaptureAtMillis, 900)
        XCTAssertEqual(progress.state, .waiting)
    }

    func testMissingOrMalformedProgressStaysUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-progress-reader-\(UUID().uuidString)")
        let reader = CaptureProgressReader(url: root.appendingPathComponent("capture-progress.json"))
        XCTAssertThrowsError(try reader.read())

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: reader.url)
        XCTAssertThrowsError(try reader.read())
        XCTAssertNil(CaptureProgressSnapshot.unavailable.captureCount)
        XCTAssertEqual(CaptureProgressSnapshot.unavailable.readiness, .neverConfigured)
    }

    func testIntervalControlRoundTripsAsOneScalar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-control-\(UUID().uuidString)")
        let store = CaptureControlStore(url: root.appendingPathComponent("capture-control.json"))
        try store.write(try CaptureControl(intervalSeconds: 120))
        XCTAssertEqual(try store.read(), try CaptureControl(intervalSeconds: 120))
        let encoded = String(decoding: try Data(contentsOf: store.url), as: UTF8.self)
        XCTAssertEqual(encoded, "{\"interval_seconds\":120}")
    }

    func testIntervalPolicyClampsAndHumanizes() throws {
        XCTAssertEqual(CaptureIntervalPolicy.normalized(1), 5)
        XCTAssertEqual(CaptureIntervalPolicy.normalized(7), 5)
        XCTAssertEqual(CaptureIntervalPolicy.normalized(8), 10)
        XCTAssertEqual(CaptureIntervalPolicy.normalized(999), 300)
        XCTAssertEqual(CaptureIntervalPolicy.humanized(5), "5 seconds")
        XCTAssertEqual(CaptureIntervalPolicy.humanized(60), "1 minute")
        XCTAssertEqual(CaptureIntervalPolicy.humanized(300), "5 minutes")

        XCTAssertThrowsError(try CaptureControl(intervalSeconds: 6)) { error in
            XCTAssertEqual(error as? CaptureControlError, .invalidInterval(6))
        }
    }

    func testPresetChoicesCoverTheFullFiveSecondToFiveMinuteRange() {
        XCTAssertEqual(CaptureIntervalPreset.allCases.map(\.seconds).first, 5)
        XCTAssertEqual(CaptureIntervalPreset.allCases.map(\.seconds).last, 300)
        XCTAssertEqual(CaptureIntervalPreset.allCases.map(\.seconds), CaptureIntervalPreset.allCases.map(\.seconds).sorted())
    }

    func testUnavailableDetailedCaptureClientNeverClaimsItStarted() {
        let client = UnavailableDetailedCaptureCommandClient()
        XCTAssertEqual(client.startDetailedCapture(intervalSeconds: 120), .helperUnavailable)
        XCTAssertEqual(client.stopDetailedCapture(), .helperUnavailable)
    }

    func testDetailedCaptureStatePreservesTruthfulOutcomes() {
        let denied = DetailedCaptureState().applying(.permissionDenied)
        XCTAssertEqual(denied.lifecycle, .permissionRequired)
        XCTAssertEqual(denied.outcome, .permissionDenied)

        let unavailable = DetailedCaptureState(intervalSeconds: 120).applying(.helperUnavailable)
        XCTAssertEqual(unavailable.lifecycle, .error)
        XCTAssertEqual(unavailable.intervalSeconds, 120)

        let failed = DetailedCaptureState().applying(.startupFailed("launch failed"))
        XCTAssertEqual(failed.lifecycle, .error)
        XCTAssertEqual(failed.outcome, .startupFailed("launch failed"))
    }

    // MARK: - V1 schema round trip

    func testV1FieldsRoundTripAndStayForwardCompatible() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-progress-v1-\(UUID().uuidString)")
        let reader = CaptureProgressReader(url: root.appendingPathComponent("capture-progress.json"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // A helper on a newer schema version with an unknown extra field.
        // Decoding must not fail, and unrecognized data must not appear.
        let json = """
        {
          "version": 2,
          "revision": 9,
          "state": "waiting",
          "capture_count": 4,
          "last_capture_at_ms": 900,
          "last_attempted_at_ms": 850,
          "started_at_ms": 100,
          "updated_at_ms": 900,
          "process_id": 42,
          "selected_display_ids": ["display-2", "display-1"],
          "active_interval_seconds": 60,
          "failure_reason": "intermittent permission",
          "some_future_field": {"nested": true}
        }
        """
        try Data(json.utf8).write(to: reader.url)

        let progress = try reader.read()
        XCTAssertEqual(progress.version, 2)
        XCTAssertEqual(progress.revision, 9)
        XCTAssertEqual(progress.lastAttemptedAtMillis, 850)
        XCTAssertEqual(progress.selectedDisplayIDs, ["display-2", "display-1"])
        XCTAssertEqual(progress.activeIntervalSeconds, 60)
        XCTAssertEqual(progress.failureReason, "intermittent permission")
    }

    func testUnrecognizedStateDecodesToUnknownInsteadOfFailingTheWholeSnapshot() throws {
        let json = """
        {
          "state": "some_future_state_this_build_has_never_heard_of",
          "capture_count": 4,
          "last_capture_at_ms": 900,
          "started_at_ms": 100,
          "updated_at_ms": 900,
          "process_id": 42
        }
        """
        let progress = try JSONDecoder().decode(CaptureProgressSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(progress.state, .unknown)
        XCTAssertEqual(progress.captureCount, 4)
        XCTAssertEqual(progress.lastCaptureAtMillis, 900)
        // Truthful degradation: an unrecognized state is reported as
        // unavailable, never guessed as ready or actively capturing.
        XCTAssertEqual(progress.readiness, .captureFailed)
        XCTAssertEqual(progress.statusLabel, "Capture status unavailable")
        // The unknown state may in fact represent success, so it must not
        // get the generic "capture attempt did not succeed" reason.
        XCTAssertEqual(progress.actionableReason, "Update Qaptr to interpret the capture helper status.")
    }

    func testLegacyStatusWithoutV1FieldsDecodesToSafeDefaults() throws {
        let json = """
        {"state":"waiting","capture_count":2,"last_capture_at_ms":300,"started_at_ms":100,"updated_at_ms":300,"process_id":42}
        """
        let progress = try JSONDecoder().decode(CaptureProgressSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(progress.version, CaptureProgressSnapshot.schemaVersion)
        XCTAssertEqual(progress.revision, 0)
        XCTAssertNil(progress.lastAttemptedAtMillis)
        XCTAssertEqual(progress.selectedDisplayIDs, [])
        XCTAssertNil(progress.activeIntervalSeconds)
        XCTAssertNil(progress.failureReason)
    }

    // MARK: - Readiness mapping (the six states the UI is allowed to show)

    func testNeverConfiguredWhenCaptureCountIsAbsent() {
        XCTAssertEqual(CaptureProgressSnapshot.unavailable.readiness, .neverConfigured)
    }

    func testPermissionDeniedReadiness() {
        let snapshot = CaptureProgressSnapshot(state: .permissionRequired, captureCount: 0, processID: 1)
        XCTAssertEqual(snapshot.readiness, .permissionDenied)
    }

    func testWaitingForFirstTickWhenStartingWithNoCapturesYet() {
        let starting = CaptureProgressSnapshot(state: .starting, captureCount: 0, processID: 1)
        XCTAssertEqual(starting.readiness, .waitingForFirstTick)

        let waitingNoCaptures = CaptureProgressSnapshot(state: .waiting, captureCount: 0, processID: 1)
        XCTAssertEqual(waitingNoCaptures.readiness, .waitingForFirstTick)
    }

    func testCapturingReadinessRequiresALiveHelperProcess() {
        let alive = CaptureProgressSnapshot(state: .capturing, captureCount: 1, processID: Int64(ProcessInfo.processInfo.processIdentifier))
        XCTAssertEqual(alive.readiness, .capturing)

        // A capturing state left behind by a crashed process (an implausible
        // PID) must not be reported as live activity.
        let stale = CaptureProgressSnapshot(state: .capturing, captureCount: 1, processID: 999_999_999)
        XCTAssertEqual(stale.readiness, .captureFailed)
    }

    func testCaptureFailedReadinessForErrorAndNoDisplayStates() {
        let error = CaptureProgressSnapshot(state: .error, captureCount: 0, processID: 1, failureReason: "disk write failed")
        XCTAssertEqual(error.readiness, .captureFailed)
        XCTAssertEqual(error.actionableReason, "disk write failed")

        let noDisplays = CaptureProgressSnapshot(state: .noDisplays, captureCount: 0, processID: 1)
        XCTAssertEqual(noDisplays.readiness, .captureFailed)
    }

    func testCaptureReadyRequiresAtLeastOneSuccessfulCapture() {
        let ready = CaptureProgressSnapshot(state: .waiting, captureCount: 5, processID: 1)
        XCTAssertEqual(ready.readiness, .captureReady)
        XCTAssertNil(ready.actionableReason)

        let stoppedButHadCaptures = CaptureProgressSnapshot(state: .stopped, captureCount: 5, processID: nil)
        XCTAssertEqual(stoppedButHadCaptures.readiness, .captureReady)
    }

    func testActionableReasonPrefersHelperSuppliedReasonOverGenericCopy() {
        let snapshot = CaptureProgressSnapshot(
            state: .permissionRequired,
            captureCount: 0,
            processID: 1,
            failureReason: "Screen Recording permission not granted"
        )
        XCTAssertEqual(snapshot.actionableReason, "Screen Recording permission not granted")
    }
}
