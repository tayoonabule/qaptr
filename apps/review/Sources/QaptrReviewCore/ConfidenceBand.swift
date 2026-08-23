import Foundation

/// An honest, three-level confidence presentation.
///
/// Qaptr never invents certainty it does not have: an unmeasured or zero
/// score renders as `.low`, never silently promoted to a passing band.
public enum ConfidenceBand: String, Equatable, Sendable {
    case low
    case moderate
    case high

    public init(score: Double) {
        switch score {
        case ..<0.5:
            self = .low
        case ..<0.8:
            self = .moderate
        default:
            self = .high
        }
    }

    /// A short, plain-language label shown next to an observation or workflow.
    public var label: String {
        switch self {
        case .low: "Low confidence"
        case .moderate: "Moderate confidence"
        case .high: "High confidence"
        }
    }
}

/// Errors raised while decoding a review snapshot from the FFI bridge.
public enum ReviewSnapshotDecodeError: Error, Equatable {
    case invalidUTF8
    case invalidJSON(String)
    case unexpectedShape(String)
}

/// Decodes the JSON produced by `qaptr_store_snapshot_json`.
public enum ReviewSnapshotDecoder {
    public static func decode(_ data: Data) throws -> ReviewSnapshot {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ReviewSnapshotDecodeError.invalidJSON(String(describing: error))
        }
        guard let root = json as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("root is not an object")
        }

        let observations = try (root["observations"] as? [[String: Any]] ?? []).map(decodeObservation)
        let workflows = try (root["workflows"] as? [[String: Any]] ?? []).map(decodeWorkflow)
        let notices = try (root["notices"] as? [[String: Any]] ?? []).map(decodeNotice)
        let candidateFields = root["workflow_candidates"] as? [[String: Any]] ?? []
        guard candidateFields.count <= 3 else {
            throw ReviewSnapshotDecodeError.unexpectedShape("snapshot contains more than three workflow candidates")
        }
        let candidates = try candidateFields.map(decodeWorkflowCandidate)
        guard Set(candidates.map(\.id)).count == candidates.count,
              Set(candidates.map(\.rank)).count == candidates.count
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("workflow candidates contain duplicate ids or ranks")
        }
        return ReviewSnapshot(
            observations: observations,
            workflows: workflows,
            notices: notices,
            workflowCandidates: candidates
        )
    }

    static func decodeObservation(_ fields: [String: Any]) throws -> QaptrObservation {
        guard
            let id = fields["id"] as? String,
            let sessionID = fields["session_id"] as? String,
            let title = fields["title"] as? String,
            let summary = fields["summary"] as? String,
            let confidence = fields["confidence"] as? Double,
            let createdAtMillis = (fields["created_at_ms"] as? NSNumber)?.int64Value
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("observation missing a required field")
        }
        return QaptrObservation(
            id: id,
            captureID: fields["capture_id"] as? String,
            sessionID: sessionID,
            title: title,
            summary: summary,
            confidence: confidence,
            createdAtMillis: createdAtMillis
        )
    }

    static func decodeWorkflow(_ fields: [String: Any]) throws -> WorkflowSummary {
        guard
            let id = fields["id"] as? String,
            let sessionID = fields["session_id"] as? String,
            let title = fields["title"] as? String,
            let goal = fields["goal"] as? String,
            let evidenceConfidence = fields["evidence_confidence"] as? Double,
            let createdAtMillis = (fields["created_at_ms"] as? NSNumber)?.int64Value
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("workflow missing a required field")
        }
        return WorkflowSummary(
            id: id,
            sessionID: sessionID,
            title: title,
            goal: goal,
            evidenceConfidence: evidenceConfidence,
            createdAtMillis: createdAtMillis
        )
    }

    static func decodeWorkflowCandidate(_ fields: [String: Any]) throws -> WorkflowCandidate {
        guard
            let id = nonEmptyString(fields, "id"),
            let analysisSessionID = nonEmptyString(fields, "analysis_session_id"),
            let rank = (fields["rank"] as? NSNumber)?.intValue,
            (1...3).contains(rank),
            let title = nonEmptyString(fields, "title"),
            let rationale = nonEmptyString(fields, "rationale"),
            let evidenceStatusValue = fields["evidence_status"] as? String,
            let evidenceStatus = WorkflowEvidenceStatus(rawValue: evidenceStatusValue),
            let evidenceConfidence = fields["evidence_confidence"] as? Double,
            (0...1).contains(evidenceConfidence),
            let evidenceBasis = nonEmptyString(fields, "evidence_basis"),
            let evidenceCaptureCount = (fields["evidence_capture_count"] as? NSNumber)?.intValue,
            evidenceCaptureCount >= 0,
            let createdAtMillis = (fields["created_at_ms"] as? NSNumber)?.int64Value,
            let revisedAtMillis = (fields["revised_at_ms"] as? NSNumber)?.int64Value
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("workflow candidate missing or invalid required field")
        }

        let interval = (fields["recommended_interval_seconds"] as? NSNumber)?.intValue
        let duration = (fields["recommended_duration_seconds"] as? NSNumber)?.intValue
        let recommendation: WorkflowCaptureRecommendation?
        switch (interval, duration) {
        case (nil, nil):
            recommendation = nil
        case let (interval?, duration?)
            where CaptureIntervalPolicy.isValid(interval)
                && DetailedSessionDuration.allCases.map(\.seconds).contains(duration):
            recommendation = WorkflowCaptureRecommendation(
                intervalSeconds: interval,
                durationSeconds: duration
            )
        default:
            throw ReviewSnapshotDecodeError.unexpectedShape("workflow candidate has an incomplete recommendation")
        }

        return WorkflowCandidate(
            id: id,
            analysisSessionID: analysisSessionID,
            rank: rank,
            title: title,
            rationale: rationale,
            evidenceStatus: evidenceStatus,
            evidenceConfidence: evidenceConfidence,
            evidenceBasis: evidenceBasis,
            evidenceCaptureCount: evidenceCaptureCount,
            observedStartAtMillis: (fields["observed_start_at_ms"] as? NSNumber)?.int64Value,
            observedEndAtMillis: (fields["observed_end_at_ms"] as? NSNumber)?.int64Value,
            recommendation: recommendation,
            createdAtMillis: createdAtMillis,
            revisedAtMillis: revisedAtMillis
        )
    }

    private static func decodeNotice(_ fields: [String: Any]) throws -> ExclusionNotice {
        guard
            let id = fields["id"] as? String,
            let count = (fields["count"] as? NSNumber)?.intValue,
            let text = fields["text"] as? String,
            let createdAtMillis = (fields["created_at_ms"] as? NSNumber)?.int64Value
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("notice missing a required field")
        }
        return ExclusionNotice(id: id, createdAtMillis: createdAtMillis, count: count, text: text)
    }

    private static func nonEmptyString(_ fields: [String: Any], _ key: String) -> String? {
        guard let value = fields[key] as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
