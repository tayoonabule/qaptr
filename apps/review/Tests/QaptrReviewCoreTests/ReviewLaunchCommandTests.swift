import XCTest

@testable import QaptrReviewCore

/// The launch-argument contract is the only path that can route a *cold*
/// launch, because a distributed notification posted before the app registers
/// its observers is dropped. These tests pin the wire format and the parser's
/// failure behavior so a rename cannot silently reintroduce that dropped
/// command.
final class ReviewLaunchCommandTests: XCTestCase {
    func testRawValuesArePinnedWireFormat() {
        // The helper builds these strings independently, so drift here breaks
        // cold-launch routing without any compile-time error.
        XCTAssertEqual(ReviewLaunchCommand.showObservations.rawValue, "show-observations")
        XCTAssertEqual(ReviewLaunchCommand.openSettings.rawValue, "open-settings")
        XCTAssertEqual(ReviewLaunchCommand.argumentFlag, "--qaptr-command")
    }

    func testParsesSeparateFlagAndValue() {
        let arguments = ["/path/to/QaptrReview", "--qaptr-command", "open-settings"]
        XCTAssertEqual(ReviewLaunchCommand.parse(arguments: arguments), .openSettings)
    }

    func testParsesInlineAssignmentForm() {
        let arguments = ["/path/to/QaptrReview", "--qaptr-command=show-observations"]
        XCTAssertEqual(ReviewLaunchCommand.parse(arguments: arguments), .showObservations)
    }

    func testParsesCommandAfterUnrelatedArguments() {
        let arguments = [
            "/path/to/QaptrReview",
            "-NSDocumentRevisionsDebugMode", "YES",
            "--qaptr-command", "show-observations",
        ]
        XCTAssertEqual(ReviewLaunchCommand.parse(arguments: arguments), .showObservations)
    }

    func testLaunchArgumentsRoundTripThroughTheParser() {
        // The helper sends exactly `launchArguments`; a normal launch prepends
        // the executable path, so the round trip must survive that prefix.
        for command in ReviewLaunchCommand.allCases {
            let arguments = ["/path/to/QaptrReview"] + command.launchArguments
            XCTAssertEqual(
                ReviewLaunchCommand.parse(arguments: arguments),
                command,
                "\(command.rawValue) did not round-trip"
            )
        }
    }

    func testNormalLaunchWithoutCommandYieldsNil() {
        // A plain user launch must not be routed anywhere unusual.
        XCTAssertNil(ReviewLaunchCommand.parse(arguments: ["/path/to/QaptrReview"]))
    }

    func testUnknownCommandValueYieldsNilRatherThanRouting() {
        let arguments = ["/path/to/QaptrReview", "--qaptr-command", "not-a-command"]
        XCTAssertNil(ReviewLaunchCommand.parse(arguments: arguments))
    }

    func testFlagWithNoValueYieldsNil() {
        // A truncated argument list must not crash or route arbitrarily.
        let arguments = ["/path/to/QaptrReview", "--qaptr-command"]
        XCTAssertNil(ReviewLaunchCommand.parse(arguments: arguments))
    }

    func testSimilarlyNamedFlagIsNotTreatedAsTheCommand() {
        let arguments = ["/path/to/QaptrReview", "--qaptr-command-extra", "open-settings"]
        XCTAssertNil(ReviewLaunchCommand.parse(arguments: arguments))
    }
}
