import Foundation
import XCTest
@testable import QaptrReviewCore

final class ReviewSessionStateDecoderTests: XCTestCase {
    func testDecodesReadyForConsentWithOnlyScalarSummaryFields() throws {
        let data = Data(#"""
{
          "version":1,
          "ok":true,
          "state":{
            "session_id":"session-1",
            "phase":"ready_for_consent",
            "captures_seen":3,
            "prepared_captures":2,
            "image_count":0,
            "exclusion_count":1,
            "observations_written":0,
            "consent_summary":{
              "provider":"jcode",
              "resolved_model":null,
              "model_label":"Provider default",
              "payload_kind":"text",
              "capture_count":2,
              "image_count":0,
              "exclusion_count":1
            },
            "result":null,
            "outcome":null,
            "error":null,
            "result_provider":null,
            "result_model_label":null,
            "allowed_operations":["state","decide_consent","cancel"]
          }
        }
"""#.utf8)

        let state = try ReviewSessionStateDecoder.decode(data)

        XCTAssertEqual(state.phase, .readyForConsent)
        XCTAssertEqual(state.capturesSeen, 3)
        XCTAssertEqual(state.preparedCaptures, 2)
        XCTAssertEqual(state.consentSummary?.provider, "jcode")
        XCTAssertEqual(state.consentSummary?.modelLabel, "Provider default")
        XCTAssertEqual(state.consentSummary?.imageCount, 0)
        XCTAssertEqual(state.allowedOperations, ["state", "decide_consent", "cancel"])
        XCTAssertFalse(state.isTerminal)
    }

    func testDecodesCompletedResultMetadata() throws {
        let data = Data(#"""
{
          "version":1,
          "ok":true,
          "state":{
            "session_id":"session-1",
            "phase":"completed",
            "captures_seen":1,
            "prepared_captures":1,
            "image_count":0,
            "exclusion_count":0,
            "observations_written":2,
            "consent_summary":null,
            "result":"completed",
            "outcome":"provider_completed",
            "error":null,
            "result_provider":"codex",
            "result_model_label":"Provider default",
            "allowed_operations":["state","start","retry"]
          }
        }
"""#.utf8)

        let state = try ReviewSessionStateDecoder.decode(data)

        XCTAssertTrue(state.isTerminal)
        XCTAssertEqual(state.observationsWritten, 2)
        XCTAssertEqual(state.resultProvider, "codex")
        XCTAssertEqual(state.resultModelLabel, "Provider default")
    }

    func testRejectsFailedNativeOperationAndMalformedState() {
        let failure = Data(#"{"version":1,"ok":false,"error":"session_busy","state":{}}"#.utf8)
        XCTAssertThrowsError(try ReviewSessionStateDecoder.decode(failure)) { error in
            XCTAssertEqual(
                error as? ReviewBridgeError,
                .reviewSessionUnavailable("session_busy")
            )
        }

        let malformed = Data(#"{"version":1,"ok":true,"state":{"phase":"idle"}}"#.utf8)
        XCTAssertThrowsError(try ReviewSessionStateDecoder.decode(malformed))
    }
}
