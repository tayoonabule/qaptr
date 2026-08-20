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
