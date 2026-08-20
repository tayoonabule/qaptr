import XCTest

@testable import QaptrHelperCore

/// The helper and the review app are separate SwiftPM packages, so nothing at
/// compile time links the strings the helper sends to the strings the review
/// app parses. These tests pin the helper's half of that wire format.
///
/// If either side is renamed, this fails alongside
/// `ReviewLaunchCommandTests` in the review package, which is the intended
/// signal: cold-launch routing would otherwise regress silently, with the app
/// opening on its default surface and no error anywhere.
final class HelperReviewCommandContractTests: XCTestCase {
    func testRawValuesMatchTheReviewAppsExpectedWireFormat() {
        XCTAssertEqual(ReviewLaunchCommandRequest.showObservations.rawValue, "show-observations")
        XCTAssertEqual(ReviewLaunchCommandRequest.openSettings.rawValue, "open-settings")
        XCTAssertEqual(ReviewLaunchCommandRequest.argumentFlag, "--qaptr-command")
    }

    func testLaunchArgumentsAreTheFlagFollowedByTheValue() {
        XCTAssertEqual(
            ReviewLaunchCommandRequest.openSettings.launchArguments,
            ["--qaptr-command", "open-settings"]
        )
        XCTAssertEqual(
            ReviewLaunchCommandRequest.showObservations.launchArguments,
            ["--qaptr-command", "show-observations"]
        )
    }

    func testSettingsRequestMapsToTheMatchingCommand() {
        // `requestSettings` is the helper's internal menu flag; this mapping is
        // what keeps "Open Settings" and "Show Capture Observations" routed to
        // different surfaces on a cold launch.
        XCTAssertEqual(
            ReviewLaunchCommandRequest.forSettingsRequest(true),
            .openSettings
        )
        XCTAssertEqual(
            ReviewLaunchCommandRequest.forSettingsRequest(false),
            .showObservations
        )
    }

    func testEveryCommandProducesExactlyTwoArguments() {
        // `NSWorkspace.OpenConfiguration.arguments` is positional, so an extra
        // or missing element would shift the value the review app reads.
        for command in ReviewLaunchCommandRequest.allCases {
            XCTAssertEqual(
                command.launchArguments.count,
                2,
                "\(command.rawValue) produced malformed launch arguments"
            )
            XCTAssertEqual(command.launchArguments.first, ReviewLaunchCommandRequest.argumentFlag)
            XCTAssertEqual(command.launchArguments.last, command.rawValue)
        }
    }
}
