import Foundation

/// The typed result of a request to begin detailed capture.
public enum DetailedCaptureStartResult: Equatable, Sendable {
    case started(intervalSeconds: Int)
    case alreadyRunning(intervalSeconds: Int)
    case helperUnavailable
    case permissionDenied
    case startupFailed(String)
}

/// The typed result of a request to end detailed capture.
public enum DetailedCaptureStopResult: Equatable, Sendable {
    case stopped
    case alreadyStopped
    case helperUnavailable
    case stopFailed(String)
}

/// The narrow command boundary for a real helper integration.
///
/// This target deliberately provides no live RPC implementation. Until the
/// helper transport is connected, the default implementation returns
/// `.helperUnavailable` rather than claiming that capture started or stopped.
public protocol DetailedCaptureTransport: Sendable {
    func startDetailedCapture(intervalSeconds: Int) -> DetailedCaptureStartResult
    func stopDetailedCapture() -> DetailedCaptureStopResult
}

/// A truthful transport used until a process/RPC boundary is wired in.
public struct UnavailableDetailedCaptureTransport: DetailedCaptureTransport {
    public init() {}

    public func startDetailedCapture(intervalSeconds: Int) -> DetailedCaptureStartResult {
        _ = intervalSeconds
        return .helperUnavailable
    }

    public func stopDetailedCapture() -> DetailedCaptureStopResult {
        .helperUnavailable
    }
}

/// The locally observed state of the detailed-capture lifecycle.
public enum DetailedCaptureLifecycleState: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case helperUnavailable
    case permissionDenied
    case startupFailed
}

/// Coordinates explicit detailed-capture start/stop requests without
/// pretending that a helper command succeeded.
///
/// The optional control store persists only the validated interval scalar. It
/// is written before the transport request so a requested cadence survives an
/// unavailable helper and can be retried after the integration is installed.
public struct DetailedCaptureLifecycle: Sendable {
    private let transport: any DetailedCaptureTransport
    private let controlStore: CaptureControlStore?

    public private(set) var state: DetailedCaptureLifecycleState = .stopped
    public private(set) var activeIntervalSeconds: Int?

    public init(
        transport: any DetailedCaptureTransport = UnavailableDetailedCaptureTransport(),
        controlStore: CaptureControlStore? = nil
    ) {
        self.transport = transport
        self.controlStore = controlStore
    }

    public mutating func start(intervalSeconds: Int) -> DetailedCaptureStartResult {
        guard let interval = try? CaptureInterval(seconds: intervalSeconds) else {
            state = .startupFailed
            return .startupFailed("invalid interval: \(intervalSeconds)")
        }
        if state == .running || state == .starting {
            return .alreadyRunning(intervalSeconds: activeIntervalSeconds ?? interval.seconds)
        }

        if let controlStore {
            do {
                try controlStore.write(try CaptureControl(intervalSeconds: interval.seconds))
            } catch {
                state = .startupFailed
                return .startupFailed("interval persistence failed: \(error)")
            }
        }

        activeIntervalSeconds = interval.seconds
        state = .starting
        let result = transport.startDetailedCapture(intervalSeconds: interval.seconds)
        switch result {
        case .started:
            state = .running
            return .started(intervalSeconds: interval.seconds)
        case let .alreadyRunning(activeInterval):
            state = .running
            activeIntervalSeconds = activeInterval
            return .alreadyRunning(intervalSeconds: activeInterval)
        case .helperUnavailable:
            state = .helperUnavailable
        case .permissionDenied:
            state = .permissionDenied
        case .startupFailed:
            state = .startupFailed
        }
        return result
    }

    public mutating func stop() -> DetailedCaptureStopResult {
        guard state == .running || state == .starting else {
            return .alreadyStopped
        }

        let result = transport.stopDetailedCapture()
        switch result {
        case .stopped:
            state = .stopped
            activeIntervalSeconds = nil
        case .helperUnavailable:
            state = .helperUnavailable
        case .stopFailed:
            state = .startupFailed
        case .alreadyStopped:
            state = .stopped
            activeIntervalSeconds = nil
        }
        return result
    }
}
