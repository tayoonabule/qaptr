import XCTest
@testable import QaptrReview

private enum ReviewContentState: Equatable {
    case error
    case empty
    case observations

    static func resolve(hasLoadError: Bool, observationCount: Int) -> ReviewContentState {
        if hasLoadError { return .error }
        return observationCount == 0 ? .empty : .observations
    }

    var headerTitle: String {
        switch self {
        case .error: "Review setup"
        case .empty: "Review"
        case .observations: "What Qaptr found"
        }
    }

    var probeName: String {
        switch self {
        case .error: "error"
        case .empty: "empty"
        case .observations: "observations"
        }
    }

}

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

}
