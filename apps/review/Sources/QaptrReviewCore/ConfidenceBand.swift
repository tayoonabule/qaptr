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
        return ReviewSnapshot(observations: observations, workflows: workflows, notices: notices)
    }

    private static func decodeObservation(_ fields: [String: Any]) throws -> QaptrObservation {
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

    private static func decodeWorkflow(_ fields: [String: Any]) throws -> WorkflowSummary {
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
}
