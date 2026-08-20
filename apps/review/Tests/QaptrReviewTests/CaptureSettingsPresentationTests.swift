import XCTest
@testable import QaptrReview
import QaptrReviewCore

final class CaptureSettingsPresentationTests: XCTestCase {
    func testHealthyCaptureCanBePaused() {
        let presentation = CaptureSettingsPresentation.present(
            intent: .running,
            progress: CaptureProgressSnapshot(state: .waiting, captureCount: 2),
            helperIsRunning: true,
            helperProcessExists: true
        )

        XCTAssertEqual(presentation.title, "Capture running")
        XCTAssertEqual(presentation.action, .pause)
        XCTAssertEqual(presentation.actionLabel, "Pause")
    }

    func testStaleWaitingSnapshotOffersAHelperRestart() {
        let presentation = CaptureSettingsPresentation.present(
            intent: .running,
            progress: CaptureProgressSnapshot(state: .waiting, captureCount: 2),
            helperIsRunning: false,
            helperProcessExists: false
        )

        XCTAssertEqual(presentation.title, "Capture needs attention")
        XCTAssertEqual(presentation.detail, "The background helper is not responding.")
        XCTAssertEqual(presentation.action, .restart)
        XCTAssertEqual(presentation.actionLabel, "Try again")
    }

    func testPermissionFailureRoutesToPrivacyInsteadOfRetryingBlindly() {
        let presentation = CaptureSettingsPresentation.present(
            intent: .running,
            progress: CaptureProgressSnapshot(state: .permissionRequired, captureCount: 0),
            helperIsRunning: false,
            helperProcessExists: true
        )

        XCTAssertEqual(presentation.title, "Screen Recording required")
        XCTAssertEqual(presentation.action, .openPrivacy)
        XCTAssertEqual(presentation.actionLabel, "Review privacy")
    }

    func testNoDisplayStateDoesNotOfferAnActionThatCannotHelp() {
        let presentation = CaptureSettingsPresentation.present(
            intent: .running,
            progress: CaptureProgressSnapshot(state: .noDisplays, captureCount: 0),
            helperIsRunning: false,
            helperProcessExists: true
        )

        XCTAssertEqual(presentation.title, "No display available")
        XCTAssertEqual(presentation.detail, "Connect a display before Qaptr can capture.")
        XCTAssertNil(presentation.action)
        XCTAssertNil(presentation.actionLabel)
    }

    func testPausedIntentRemainsThePrimaryTruth() {
        let presentation = CaptureSettingsPresentation.present(
            intent: .paused,
            progress: CaptureProgressSnapshot(state: .waiting, captureCount: 2),
            helperIsRunning: true,
            helperProcessExists: true
        )

        XCTAssertEqual(presentation.title, "Capture paused")
        XCTAssertEqual(presentation.action, .resume)
        XCTAssertEqual(presentation.actionLabel, "Resume")
    }
}
