import Foundation
import XCTest
@testable import QaptrReviewCore

final class ProviderReadinessDecoderTests: XCTestCase {
    func testDecodesPathOnlySnapshotWithoutClaimingUsability() throws {
        let json = """
        {
          "version": 1,
          "providers": [
            { "id": "claude-cli", "state": "detected", "usable": false },
            { "id": "codex", "state": "not_installed", "usable": false },
            { "id": "jcode", "state": "unavailable", "usable": false }
          ]
        }
        """

        let snapshot = try ProviderReadinessDecoder.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.providers.count, 3)
        XCTAssertEqual(snapshot.providers[0].id, "claude-cli")
        XCTAssertEqual(snapshot.providers[0].state, .detected)
        XCTAssertFalse(snapshot.providers[0].usable)
        XCTAssertEqual(snapshot.providers[1].state, .notInstalled)
        XCTAssertEqual(snapshot.providers[2].state, .unavailable)
    }

    func testRejectsEmptyData() {
        XCTAssertThrowsError(try ProviderReadinessDecoder.decode(Data()))
    }

    func testRejectsMalformedProviderEntry() {
        let json = "{\"version\":1,\"providers\":[{\"id\":\"codex\",\"state\":\"detected\"}]}"
        XCTAssertThrowsError(try ProviderReadinessDecoder.decode(Data(json.utf8))) { error in
            XCTAssertEqual(
                error as? ReviewSnapshotDecodeError,
                .unexpectedShape("provider readiness missing a required field")
            )
        }
    }

    func testRejectsAUsabilityClaimFromPathOnlyData() {
        let json = "{\"version\":1,\"providers\":[{\"id\":\"codex\",\"state\":\"detected\",\"usable\":true}]}"
        XCTAssertThrowsError(try ProviderReadinessDecoder.decode(Data(json.utf8))) { error in
            XCTAssertEqual(
                error as? ReviewSnapshotDecodeError,
                .unexpectedShape("path-only readiness cannot claim usability")
            )
        }
    }

    func testRejectsTruncatedData() {
        let truncated = Data(#"{"version":1,"providers":[{"id":"codex"}"#.utf8)
        XCTAssertThrowsError(try ProviderReadinessDecoder.decode(truncated))
    }

    func testAcceptsAnEmptyProviderListWithoutInventingReadiness() throws {
        let json = #"{"version":1,"providers":[]}"#
        let snapshot = try ProviderReadinessDecoder.decode(Data(json.utf8))
        XCTAssertTrue(snapshot.providers.isEmpty)
    }
}
