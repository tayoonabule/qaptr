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

    public init(observations: [QaptrObservation], workflows: [WorkflowSummary], notices: [ExclusionNotice]) {
        self.observations = observations
        self.workflows = workflows
        self.notices = notices
    }

    /// An empty snapshot, shown before any capture has been analyzed.
    public static let empty = ReviewSnapshot(observations: [], workflows: [], notices: [])

    /// Observations ordered most-recent-first, the order the sheet displays.
    public var recentObservations: [QaptrObservation] {
        observations.sorted { $0.createdAtMillis > $1.createdAtMillis }
    }
}
