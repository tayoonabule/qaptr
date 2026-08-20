import Foundation
import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

final class HelperPermissionStatusTests: XCTestCase {
    private let helperPath = "/Applications/Qaptr.app/Contents/Helper.app"

    func testFreshLiveSnapshotReportsTheHelpersPermissions() throws {
        let data = Data(
            """
            {"version":2,"screen_recording_granted":true,"screen_recording_requested":true,"accessibility_granted":false,"accessibility_requested":true,"process_id":42,"updated_at_ms":900,"helper_bundle_path":"/Applications/Qaptr.app/Contents/Helper.app","command_token":"token"}
            """.utf8
        )

        let snapshot = try HelperPermissionSnapshot.liveSnapshot(
            data: data,
            nowMillis: 1_000,
            expectedHelperBundlePath: helperPath,
            isProcessRunning: { $0 == 42 }
        )

        XCTAssertEqual(snapshot?.screenRecordingStatus, .granted)
        XCTAssertEqual(snapshot?.accessibilityStatus, .denied)
    }

    func testNeverRequestedPermissionRemainsNotDetermined() throws {
        let data = Data(
            """
            {"version":2,"screen_recording_granted":false,"screen_recording_requested":false,"accessibility_granted":false,"accessibility_requested":false,"process_id":42,"updated_at_ms":900,"helper_bundle_path":"/Applications/Qaptr.app/Contents/Helper.app","command_token":"token"}
            """.utf8
        )

        let snapshot = try HelperPermissionSnapshot.liveSnapshot(
            data: data,
            nowMillis: 1_000,
            expectedHelperBundlePath: helperPath,
            isProcessRunning: { _ in true }
        )

        XCTAssertEqual(snapshot?.screenRecordingStatus, .notDetermined)
        XCTAssertEqual(snapshot?.accessibilityStatus, .notDetermined)
    }

    func testStaleOrDeadSnapshotCannotClaimPermission() throws {
        let data = Data(
            """
            {"version":2,"screen_recording_granted":true,"screen_recording_requested":true,"accessibility_granted":true,"accessibility_requested":true,"process_id":42,"updated_at_ms":900,"helper_bundle_path":"/Applications/Qaptr.app/Contents/Helper.app","command_token":"token"}
            """.utf8
        )

        XCTAssertNil(
            try HelperPermissionSnapshot.liveSnapshot(
                data: data,
                nowMillis: 7_000,
                expectedHelperBundlePath: helperPath,
                isProcessRunning: { _ in true }
            )
        )
        XCTAssertNil(
            try HelperPermissionSnapshot.liveSnapshot(
                data: data,
                nowMillis: 1_000,
                expectedHelperBundlePath: helperPath,
                isProcessRunning: { _ in false }
            )
        )
    }

    func testUnsupportedSnapshotVersionIsIgnored() throws {
        let data = Data(
            """
            {"version":1,"screen_recording_granted":true,"screen_recording_requested":true,"accessibility_granted":true,"accessibility_requested":true,"process_id":42,"updated_at_ms":900,"helper_bundle_path":"/Applications/Qaptr.app/Contents/Helper.app","command_token":"token"}
            """.utf8
        )

        XCTAssertNil(
            try HelperPermissionSnapshot.liveSnapshot(
                data: data,
                nowMillis: 1_000,
                expectedHelperBundlePath: helperPath,
                isProcessRunning: { _ in true }
            )
        )
    }

    func testWrongBundlePathOrMissingCommandTokenIsIgnored() throws {
        let wrongPath = Data(
            """
            {"version":2,"screen_recording_granted":true,"screen_recording_requested":true,"accessibility_granted":true,"accessibility_requested":true,"process_id":42,"updated_at_ms":900,"helper_bundle_path":"/tmp/QaptrHelper.app","command_token":"token"}
            """.utf8
        )
        let missingToken = Data(
            """
            {"version":2,"screen_recording_granted":true,"screen_recording_requested":true,"accessibility_granted":true,"accessibility_requested":true,"process_id":42,"updated_at_ms":900,"helper_bundle_path":"/Applications/Qaptr.app/Contents/Helper.app","command_token":""}
            """.utf8
        )

        for data in [wrongPath, missingToken] {
            XCTAssertNil(
                try HelperPermissionSnapshot.liveSnapshot(
                    data: data,
                    nowMillis: 1_000,
                    expectedHelperBundlePath: helperPath,
                    isProcessRunning: { _ in true }
                )
            )
        }
    }
}
