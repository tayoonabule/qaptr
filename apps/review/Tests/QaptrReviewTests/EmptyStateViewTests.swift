import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// Direct tests for `EmptyStateView.title`/`.detail`, the pure decision
/// behind checklist 4.1 row 135: honest, distinct empty states for no
/// captures yet, every capture excluded during local privacy preparation,
/// captures waiting for analysis, and unavailable analysis.
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

    func testCapturesWaitForAnalysisRatherThanClaimingNothingWasFound() {
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 5, notices: []),
            "5 screenshots are waiting for analysis."
        )
        XCTAssertEqual(
            EmptyStateView.detail(captureCount: 5, statusLabel: "Background capture active", notices: []),
            "Qaptr has not produced an observation yet."
        )
    }

    func testUnavailableAnalysisExplainsWhyCapturedScreenshotsProduceNoObservations() {
        XCTAssertEqual(
            EmptyStateView.title(captureCount: 1, notices: [], analysisState: "unavailable"),
            "1 screenshot captured. Analysis is unavailable."
        )
        XCTAssertEqual(
            EmptyStateView.detail(
                captureCount: 1,
                statusLabel: "Background capture active",
                notices: [],
                analysisState: "unavailable"
            ),
            "This build can capture screenshots, but it cannot turn them into observations yet."
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
