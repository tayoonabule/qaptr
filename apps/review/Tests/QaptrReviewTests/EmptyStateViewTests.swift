import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// Direct tests for `EmptyStateView.title`/`.detail`, the pure decision
/// behind checklist 4.1 row 135: honest, distinct empty states for no
/// captures yet, every capture excluded during local privacy preparation,
/// and captures prepared with nothing worth reporting.
final class EmptyStateViewTests: XCTestCase {
    func testNoCapturesYet() {
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 0, notices: []),
            "No screenshots have been captured yet."
        )
        XCTAssertTrue(
            EmptyStateView.detail(captureCount: 0, statusLabel: "Not running", notices: [])
                .contains("Not running")
        )
    }

    func testCapturesPreparedButNothingWorthReportingWhenNoExclusionExists() {
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 5, notices: []),
            "5 screenshots are ready. Nothing new was found."
        )
        XCTAssertEqual(
            EmptyStateView.detail(captureCount: 5, statusLabel: "Background capture active", notices: []),
            "Qaptr did not find a note to show."
        )
    }

    func testSingularCaptureCountPhrasing() {
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 1, notices: []),
            "1 screenshot is ready. Nothing new was found."
        )
    }

    func testEveryCaptureExcludedIsDistinctFromNothingWorthReporting() {
        let notice = ExclusionNotice(id: "n1", createdAtMillis: 0, count: 3, text: "3 captures were skipped.")
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 3, notices: [notice]),
            "Every recent screenshot was excluded before analysis."
        )
        XCTAssertTrue(
            EmptyStateView.detail(captureCount: 3, statusLabel: "ignored", notices: [notice])
                .contains("privacy preparation")
        )
    }

    func testExclusionNoticeDoesNotApplyBeforeAnyCaptureExists() {
        // A notice with no actual captures yet must never claim exclusion;
        // that would misrepresent a capture history that does not exist.
        let notice = ExclusionNotice(id: "n1", createdAtMillis: 0, count: 3, text: "3 captures were skipped.")
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 0, notices: [notice]),
            "No screenshots have been captured yet."
        )
    }

    func testUnavailableCaptureCountFallsBackToStillGettingReady() {
        XCTAssertEqual(EmptyStateView.title(captureCount: nil, notices: []), "No observations yet.")
        XCTAssertEqual(
            EmptyStateView.detail(captureCount: nil, statusLabel: "ignored", notices: []),
            "Qaptr is still getting ready."
        )
    }
}
