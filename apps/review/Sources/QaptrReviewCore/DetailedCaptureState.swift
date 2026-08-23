import Foundation

/// The scalar outcome vocabulary the review surface may receive from the
/// helper lifecycle seam. It intentionally has no image, privacy, workflow,
/// or provider payload.
public enum DetailedCaptureActionOutcome: Equatable, Sendable {
    case started(intervalSeconds: Int)
    case alreadyRunning(intervalSeconds: Int)
    case stopped
    case alreadyStopped
    case helperUnavailable
    case permissionDenied
    case startupFailed(String)
    case stopFailed(String)
}

/// The review-core side of the helper command boundary. The production review
/// app uses the helper's distributed-notification transport; this unavailable
/// implementation remains useful for explicit failure-state tests.
public protocol DetailedCaptureCommandClient: Sendable {
    func startDetailedCapture(intervalSeconds: Int) -> DetailedCaptureActionOutcome
    func stopDetailedCapture() -> DetailedCaptureActionOutcome
}

public struct UnavailableDetailedCaptureCommandClient: DetailedCaptureCommandClient {
    public init() {}

    public func startDetailedCapture(intervalSeconds: Int) -> DetailedCaptureActionOutcome {
        _ = intervalSeconds
        return .helperUnavailable
    }

    public func stopDetailedCapture() -> DetailedCaptureActionOutcome {
        .helperUnavailable
    }
}

/// The scalar state that can be rendered without inventing a helper result.
public struct DetailedCaptureState: Equatable, Sendable {
    public let lifecycle: CaptureProgressState
    public let intervalSeconds: Int?
    public let outcome: DetailedCaptureActionOutcome?

    public init(
        lifecycle: CaptureProgressState = .stopped,
        intervalSeconds: Int? = nil,
        outcome: DetailedCaptureActionOutcome? = nil
    ) {
        self.lifecycle = lifecycle
        self.intervalSeconds = intervalSeconds
        self.outcome = outcome
    }

    public func applying(_ outcome: DetailedCaptureActionOutcome) -> Self {
        switch outcome {
        case let .started(intervalSeconds), let .alreadyRunning(intervalSeconds):
            return Self(lifecycle: .capturing, intervalSeconds: intervalSeconds, outcome: outcome)
        case .stopped, .alreadyStopped:
            return Self(lifecycle: .stopped, intervalSeconds: nil, outcome: outcome)
        case .helperUnavailable:
            return Self(lifecycle: .error, intervalSeconds: intervalSeconds, outcome: outcome)
        case .permissionDenied:
            return Self(lifecycle: .permissionRequired, intervalSeconds: intervalSeconds, outcome: outcome)
        case .startupFailed, .stopFailed:
            return Self(lifecycle: .error, intervalSeconds: intervalSeconds, outcome: outcome)
        }
    }
}
