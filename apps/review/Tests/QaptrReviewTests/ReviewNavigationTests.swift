import XCTest
@testable import QaptrReview
import QaptrReviewCore

@MainActor
final class ReviewNavigationTests: XCTestCase {
    func testNavigationStartsOnReviewAndCanRouteToSettingsAndBack() {
        let navigation = ReviewNavigation()
        XCTAssertEqual(navigation.surface, .review)

        navigation.surface = .settings
        XCTAssertEqual(navigation.surface, .settings)

        navigation.surface = .review
        XCTAssertEqual(navigation.surface, .review)
    }

    func testSurfaceProbeNamesArePinnedWireFormat() {
        // The cold-launch acceptance check reads these strings out of
        // QAPTR_REVIEW_SURFACE_FILE to decide whether routing worked, so a
        // rename here would silently turn that check into a false pass.
        XCTAssertEqual(ReviewSurface.review.probeName, "review")
        XCTAssertEqual(ReviewSurface.settings.probeName, "settings")
    }

    func testCaptureStatusDistinguishesPausedFromNeedsAttention() {
        XCTAssertEqual(
            CaptureStatusPresentation.present(intent: .running, helperIsRunning: true),
            .live
        )
        XCTAssertEqual(
            CaptureStatusPresentation.present(intent: .paused, helperIsRunning: true),
            .paused
        )
        XCTAssertEqual(
            CaptureStatusPresentation.present(intent: .running, helperIsRunning: false),
            .needsAttention
        )
        XCTAssertEqual(CaptureStatusPresentation.needsAttention.accessibilityLabel, "Capture needs attention")
    }
}
