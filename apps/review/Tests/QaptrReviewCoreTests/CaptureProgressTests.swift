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
    }

    func testPauseControlRoundTripsAndRejectsUnknownModes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qaptr-control-\(UUID().uuidString)")
        let store = CaptureControlStore(url: root.appendingPathComponent("capture-control.json"))
        try store.write(CaptureControl(mode: .paused))
        XCTAssertEqual(try store.read(), CaptureControl(mode: .paused))

        XCTAssertThrowsError(
            try JSONDecoder().decode(CaptureControl.self, from: Data("{\"mode\":\"later\"}".utf8))
        )
    }
}
