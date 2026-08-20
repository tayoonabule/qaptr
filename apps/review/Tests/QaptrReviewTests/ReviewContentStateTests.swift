import XCTest
@testable import QaptrReview

@MainActor
final class ReviewContentStateTests: XCTestCase {
    func testLoadErrorWinsOverObservationCount() {
        // A load error means the counts cannot be trusted, so it must take
        // precedence even when observations happen to be present from an
        // earlier successful refresh.
        XCTAssertEqual(
            ReviewContentState.resolve(hasLoadError: true, observationCount: 0),
            .error
        )
        XCTAssertEqual(
            ReviewContentState.resolve(hasLoadError: true, observationCount: 7),
            .error
        )
    }

    func testEmptyAndPopulatedStatesFollowObservationCount() {
        XCTAssertEqual(
            ReviewContentState.resolve(hasLoadError: false, observationCount: 0),
            .empty
        )
        XCTAssertEqual(
            ReviewContentState.resolve(hasLoadError: false, observationCount: 1),
            .observations
        )
        XCTAssertEqual(
            ReviewContentState.resolve(hasLoadError: false, observationCount: 42),
            .observations
        )
    }

    func testHeaderTitleIsDerivedFromTheRenderedBody() {
        // The header and the body were once two independent conditionals over
        // the same state, so they could disagree -- "What Qaptr found" above an
        // empty state. Pinning the mapping keeps the header honest about what
        // is actually rendered below it.
        XCTAssertEqual(ReviewContentState.error.headerTitle, "Review setup")
        XCTAssertEqual(ReviewContentState.empty.headerTitle, "Review")
        XCTAssertEqual(ReviewContentState.observations.headerTitle, "What Qaptr found")
    }

    func testEveryStateHasADistinctHeaderTitle() {
        // Two states sharing a title would make the header useless as a signal
        // for which body rendered.
        let titles = [
            ReviewContentState.error,
            ReviewContentState.empty,
            ReviewContentState.observations,
        ].map(\.headerTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testProbeNamesArePinnedWireFormat() {
        // The finished-analysis acceptance check reads these strings out of
        // QAPTR_REVIEW_CONTENT_FILE to decide whether findings actually
        // rendered, so a rename here would silently turn that check into a
        // false pass.
        XCTAssertEqual(ReviewContentState.error.probeName, "error")
        XCTAssertEqual(ReviewContentState.empty.probeName, "empty")
        XCTAssertEqual(ReviewContentState.observations.probeName, "observations")
    }

    func testProbeNamesAreDistinct() {
        let names = [
            ReviewContentState.error,
            ReviewContentState.empty,
            ReviewContentState.observations,
        ].map(\.probeName)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
