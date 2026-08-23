import Foundation

/// One durable observation surfaced on the Observation Sheet.
///
/// Confidence is carried through unmodified from the durable record. This
/// type never invents a confidence value: a missing or zero score renders as
/// honestly low, never rounded up for presentation.
public struct QaptrObservation: Identifiable, Equatable, Sendable {
    public let id: String
    public let captureID: String?
    public let sessionID: String
    public let title: String
    public let summary: String
    public let confidence: Double
    public let createdAtMillis: Int64

    public init(
        id: String,
        captureID: String?,
        sessionID: String,
        title: String,
        summary: String,
        confidence: Double,
        createdAtMillis: Int64
    ) {
        self.id = id
        self.captureID = captureID
        self.sessionID = sessionID
        self.title = title
        self.summary = summary
        self.confidence = confidence
        self.createdAtMillis = createdAtMillis
    }

    /// The honest confidence band shown next to the observation.
    public var confidenceBand: ConfidenceBand {
        ConfidenceBand(score: confidence)
    }
}

/// A canonical workflow summary, without any source images.
public struct WorkflowSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let title: String
    public let goal: String
    public let evidenceConfidence: Double
    public let createdAtMillis: Int64

    public init(
        id: String,
        sessionID: String,
        title: String,
        goal: String,
        evidenceConfidence: Double,
        createdAtMillis: Int64
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.goal = goal
        self.evidenceConfidence = evidenceConfidence
        self.createdAtMillis = createdAtMillis
    }

    public var confidenceBand: ConfidenceBand {
        ConfidenceBand(score: evidenceConfidence)
    }
}

/// The three evidence states a persisted workflow candidate may report.
///
/// These values are decoded from the native workflow result. The SwiftUI layer
/// never derives them from confidence thresholds or observation counts.
public enum WorkflowEvidenceStatus: String, Equatable, Sendable {
    case enoughInformation = "enough_information"
    case needsMoreDetail = "needs_more_detail"
    case needsMoreFrequentObservation = "needs_more_frequent_observation"
}

/// A bounded recommendation emitted with a candidate that needs more evidence.
public struct WorkflowCaptureRecommendation: Equatable, Sendable {
    public let intervalSeconds: Int
    public let durationSeconds: Int

    public init(intervalSeconds: Int, durationSeconds: Int) {
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
    }
}

/// One persisted, provider-produced workflow hypothesis.
///
/// The record contains scalar explanation and provenance only. It never carries
/// source screenshots, provider payloads, credentials, or raw model output.
public struct WorkflowCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let analysisSessionID: String
    public let rank: Int
    public let title: String
    public let rationale: String
    public let evidenceStatus: WorkflowEvidenceStatus
    public let evidenceConfidence: Double
    public let evidenceBasis: String
    public let evidenceCaptureCount: Int
    public let observedStartAtMillis: Int64?
    public let observedEndAtMillis: Int64?
    public let recommendation: WorkflowCaptureRecommendation?
    public let createdAtMillis: Int64
    public let revisedAtMillis: Int64

    public init(
        id: String,
        analysisSessionID: String,
        rank: Int,
        title: String,
        rationale: String,
        evidenceStatus: WorkflowEvidenceStatus,
        evidenceConfidence: Double,
        evidenceBasis: String,
        evidenceCaptureCount: Int,
        observedStartAtMillis: Int64?,
        observedEndAtMillis: Int64?,
        recommendation: WorkflowCaptureRecommendation?,
        createdAtMillis: Int64,
        revisedAtMillis: Int64
    ) {
        self.id = id
        self.analysisSessionID = analysisSessionID
        self.rank = rank
        self.title = title
        self.rationale = rationale
        self.evidenceStatus = evidenceStatus
        self.evidenceConfidence = evidenceConfidence
        self.evidenceBasis = evidenceBasis
        self.evidenceCaptureCount = evidenceCaptureCount
        self.observedStartAtMillis = observedStartAtMillis
        self.observedEndAtMillis = observedEndAtMillis
        self.recommendation = recommendation
        self.createdAtMillis = createdAtMillis
        self.revisedAtMillis = revisedAtMillis
    }

    public var confidenceBand: ConfidenceBand {
        ConfidenceBand(score: evidenceConfidence)
    }
}

/// A quiet, count-and-reason exclusion notice with no capture content.
public struct ExclusionNotice: Identifiable, Equatable, Sendable {
    public let id: String
    public let createdAtMillis: Int64
    public let count: Int
    public let text: String

    public init(id: String, createdAtMillis: Int64, count: Int, text: String) {
        self.id = id
        self.createdAtMillis = createdAtMillis
        self.count = count
        self.text = text
    }
}

/// The complete, decoded durable-history view shown by the review app.
public struct ReviewSnapshot: Equatable, Sendable {
    public let observations: [QaptrObservation]
    public let workflows: [WorkflowSummary]
    public let notices: [ExclusionNotice]
    public let workflowCandidates: [WorkflowCandidate]

    public init(
        observations: [QaptrObservation],
        workflows: [WorkflowSummary],
        notices: [ExclusionNotice],
        workflowCandidates: [WorkflowCandidate] = []
    ) {
        self.observations = observations
        self.workflows = workflows
        self.notices = notices
        self.workflowCandidates = workflowCandidates
    }

    /// An empty snapshot, shown before any capture has been analyzed.
    public static let empty = ReviewSnapshot(observations: [], workflows: [], notices: [])

    /// Observations ordered most-recent-first, the order the sheet displays.
    public var recentObservations: [QaptrObservation] {
        observations.sorted { $0.createdAtMillis > $1.createdAtMillis }
    }

    /// Candidates in the provider-supplied rank order shown by the review app.
    public var rankedWorkflowCandidates: [WorkflowCandidate] {
        workflowCandidates.sorted { $0.rank < $1.rank }
    }
}

/// The durable-history store's open/ready state, as reported by the bridge.
public struct ReviewStoreStatus: Equatable, Sendable {
    public let ready: Bool

    public init(ready: Bool) {
        self.ready = ready
    }
}

/// The review session's durable-history counts.
///
/// This never reports a live capture or analysis session: it only describes
/// what has already been durably recorded.
public struct ReviewSessionStatus: Equatable, Sendable {
    public let state: String
    public let historyAvailable: Bool
    public let observationCount: Int
    public let workflowCount: Int
    public let noticeCount: Int

    public init(
        state: String,
        historyAvailable: Bool,
        observationCount: Int,
        workflowCount: Int,
        noticeCount: Int
    ) {
        self.state = state
        self.historyAvailable = historyAvailable
        self.observationCount = observationCount
        self.workflowCount = workflowCount
        self.noticeCount = noticeCount
    }
}

/// Live-analysis availability.
///
/// The passive status endpoint reports whether the provider-aware session ABI
/// is present. `provider` remains absent until a separate live session selects
/// one, so this snapshot never invents an active session or provider name.
public struct ReviewAnalysisStatus: Equatable, Sendable {
    public let state: String
    public let provider: String?
    public let reason: String?

    public init(state: String, provider: String?, reason: String?) {
        self.state = state
        self.provider = provider
        self.reason = reason
    }
}

/// The complete, decoded status returned by `qaptr_review_status_json`.
///
/// This is a scalar summary only: store readiness, durable-history counts,
/// and live-analysis availability. It never carries observation or workflow
/// content; use [`ReviewSnapshot`] for that.
public struct ReviewStatus: Equatable, Sendable {
    public let store: ReviewStoreStatus
    public let reviewSession: ReviewSessionStatus
    public let analysis: ReviewAnalysisStatus

    public init(store: ReviewStoreStatus, reviewSession: ReviewSessionStatus, analysis: ReviewAnalysisStatus) {
        self.store = store
        self.reviewSession = reviewSession
        self.analysis = analysis
    }
}

/// Decodes the JSON produced by `qaptr_review_status_json`.
public enum ReviewStatusDecoder {
    public static func decode(_ data: Data) throws -> ReviewStatus {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ReviewSnapshotDecodeError.invalidJSON(String(describing: error))
        }
        guard let root = json as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("root is not an object")
        }
        guard let storeFields = root["store"] as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("status missing a \"store\" object")
        }
        guard let sessionFields = root["review_session"] as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("status missing a \"review_session\" object")
        }
        guard let analysisFields = root["analysis"] as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("status missing an \"analysis\" object")
        }

        guard let ready = storeFields["ready"] as? Bool else {
            throw ReviewSnapshotDecodeError.unexpectedShape("store status missing \"ready\"")
        }

        guard
            let sessionState = sessionFields["state"] as? String,
            let historyAvailable = sessionFields["history_available"] as? Bool,
            let observationCount = (sessionFields["observation_count"] as? NSNumber)?.intValue,
            let workflowCount = (sessionFields["workflow_count"] as? NSNumber)?.intValue,
            let noticeCount = (sessionFields["notice_count"] as? NSNumber)?.intValue
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("review session status missing a required field")
        }

        guard let analysisState = analysisFields["state"] as? String else {
            throw ReviewSnapshotDecodeError.unexpectedShape("analysis status missing \"state\"")
        }

        return ReviewStatus(
            store: ReviewStoreStatus(ready: ready),
            reviewSession: ReviewSessionStatus(
                state: sessionState,
                historyAvailable: historyAvailable,
                observationCount: observationCount,
                workflowCount: workflowCount,
                noticeCount: noticeCount
            ),
            analysis: ReviewAnalysisStatus(
                state: analysisState,
                provider: analysisFields["provider"] as? String,
                reason: analysisFields["reason"] as? String
            )
        )
    }
}
