import Foundation
import XCTest
@testable import QaptrReviewCore

final class WorkflowCandidateDecoderTests: XCTestCase {
    func testDecodesAndRanksTypedWorkflowCandidates() throws {
        let json = """
        {
          "observations": [],
          "workflows": [],
          "notices": [],
          "workflow_candidates": [
            {
              "id": "candidate-2",
              "analysis_session_id": "session-1",
              "rank": 2,
              "title": "Prepare the weekly report",
              "rationale": "The same document and spreadsheet appeared together.",
              "evidence_status": "needs_more_detail",
              "evidence_confidence": 0.72,
              "evidence_basis": "Four captures show preparation but not the final handoff.",
              "evidence_capture_count": 4,
              "observed_start_at_ms": 1000,
              "observed_end_at_ms": 4000,
              "recommended_interval_seconds": 15,
              "recommended_duration_seconds": 1800,
              "created_at_ms": 5000,
              "revised_at_ms": 5000
            },
            {
              "id": "candidate-1",
              "analysis_session_id": "session-1",
              "rank": 1,
              "title": "Validate a product change",
              "rationale": "Implementation and verification repeated in sequence.",
              "evidence_status": "enough_information",
              "evidence_confidence": 0.91,
              "evidence_basis": "Eight captures show the same sequence.",
              "evidence_capture_count": 8,
              "created_at_ms": 5000,
              "revised_at_ms": 5000
            }
          ]
        }
        """

        let snapshot = try ReviewSnapshotDecoder.decode(Data(json.utf8))

        XCTAssertEqual(snapshot.workflowCandidates.count, 2)
        XCTAssertEqual(snapshot.rankedWorkflowCandidates.map(\.id), ["candidate-1", "candidate-2"])
        XCTAssertEqual(snapshot.rankedWorkflowCandidates[0].evidenceStatus, .enoughInformation)
        XCTAssertEqual(
            snapshot.rankedWorkflowCandidates[1].recommendation,
            WorkflowCaptureRecommendation(intervalSeconds: 15, durationSeconds: 1800)
        )
    }

    func testLegacySnapshotRemainsCompatibleWithoutCandidateField() throws {
        let snapshot = try ReviewSnapshotDecoder.decode(
            Data("{\"observations\":[],\"workflows\":[],\"notices\":[]}".utf8)
        )

        XCTAssertTrue(snapshot.workflowCandidates.isEmpty)
        XCTAssertEqual(snapshot, .empty)
    }

    func testRejectsDuplicateRanksInsteadOfChoosingForTheProvider() {
        let candidate = """
        {
          "analysis_session_id":"s",
          "rank":1,
          "title":"Candidate",
          "rationale":"Grounded rationale",
          "evidence_status":"needs_more_detail",
          "evidence_confidence":0.5,
          "evidence_basis":"Two captures",
          "evidence_capture_count":2,
          "created_at_ms":1,
          "revised_at_ms":1
        }
        """
        let json = """
        {
          "observations":[],
          "workflows":[],
          "notices":[],
          "workflow_candidates":[
            {"id":"one",\(candidate.dropFirst().dropLast())},
            {"id":"two",\(candidate.dropFirst().dropLast())}
          ]
        }
        """

        XCTAssertThrowsError(try ReviewSnapshotDecoder.decode(Data(json.utf8)))
    }

    func testRejectsUnsupportedEvidenceStatus() {
        let json = """
        {
          "observations":[],
          "workflows":[],
          "notices":[],
          "workflow_candidates":[{
            "id":"one",
            "analysis_session_id":"s",
            "rank":1,
            "title":"Candidate",
            "rationale":"Grounded rationale",
            "evidence_status":"probably_enough",
            "evidence_confidence":0.5,
            "evidence_basis":"Two captures",
            "evidence_capture_count":2,
            "created_at_ms":1,
            "revised_at_ms":1
          }]
        }
        """

        XCTAssertThrowsError(try ReviewSnapshotDecoder.decode(Data(json.utf8)))
    }

    func testRejectsOutOfPolicyConfidenceAndRecommendation() {
        let json = """
        {
          "observations":[],
          "workflows":[],
          "notices":[],
          "workflow_candidates":[{
            "id":"one",
            "analysis_session_id":"s",
            "rank":1,
            "title":"Candidate",
            "rationale":"Grounded rationale",
            "evidence_status":"needs_more_detail",
            "evidence_confidence":1.2,
            "evidence_basis":"Two captures",
            "evidence_capture_count":2,
            "recommended_interval_seconds":7,
            "recommended_duration_seconds":900,
            "created_at_ms":1,
            "revised_at_ms":1
          }]
        }
        """

        XCTAssertThrowsError(try ReviewSnapshotDecoder.decode(Data(json.utf8)))
    }
}
