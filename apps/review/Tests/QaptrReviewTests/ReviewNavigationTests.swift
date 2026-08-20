import XCTest
@testable import QaptrReview

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
}
