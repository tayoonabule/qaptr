import XCTest
@testable import QaptrReview

/// Direct tests for `OnboardingView.liveCaptureDisplaysText`, the pure
/// decision behind checklist 5.1 row 162: showing selected displays from
/// live helper state, distinct from the system's merely-available display
/// count. This never invents a running-capture claim when the helper has
/// not reported one.
final class OnboardingViewLiveDisplaysTests: XCTestCase {
    func testReturnsNilWhenTheHelperIsNotRunning() {
        XCTAssertNil(
            OnboardingView.liveCaptureDisplaysText(helperIsRunning: false, selectedDisplayIDs: ["display-1"])
        )
    }

    func testReturnsNilWhenTheHelperIsNotRunningEvenWithStaleSelectedDisplays() {
        // A stopped/crashed helper's last-known selected displays must not
        // be presented as currently capturing.
        XCTAssertNil(
            OnboardingView.liveCaptureDisplaysText(
                helperIsRunning: false, selectedDisplayIDs: ["display-1", "display-2"]
            )
        )
    }

    func testReportsWaitingWhenRunningButNoDisplaySelectedYet() {
        let text = OnboardingView.liveCaptureDisplaysText(helperIsRunning: true, selectedDisplayIDs: [])
        XCTAssertEqual(text, "Capture is running but has not reported a selected screen yet.")
    }

    func testReportsSingularCountForOneSelectedDisplay() {
        let text = OnboardingView.liveCaptureDisplaysText(helperIsRunning: true, selectedDisplayIDs: ["display-1"])
        XCTAssertEqual(text, "Currently capturing 1 screen.")
    }

    func testReportsPluralCountForMultipleSelectedDisplays() {
        let text = OnboardingView.liveCaptureDisplaysText(
            helperIsRunning: true, selectedDisplayIDs: ["display-1", "display-2"]
        )
        XCTAssertEqual(text, "Currently capturing 2 screens.")
    }
}
