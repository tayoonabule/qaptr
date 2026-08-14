import Foundation
import Darwin

@_silgen_name("flock")
private func qaptrFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// The helper's sparse or detailed capture cadence.
public struct CaptureInterval: Equatable, Sendable {
    /// The interval in seconds. It must be positive and finite.
    public let seconds: TimeInterval

    /// Creates a validated interval.
    public init(seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds > 0 else {
            throw CaptureCoreError.invalidInterval(seconds)
        }
        self.seconds = seconds
    }
}

/// Errors raised by the platform-independent helper coordination layer.
public enum CaptureCoreError: Error, Equatable, Sendable {
    case invalidInterval(TimeInterval)
    case captureFailed(String)
    case sealingFailed(String)
}

/// Errors raised while claiming the single helper process slot.
public enum SingleInstanceError: Error, Equatable, Sendable {
    case alreadyRunning
    case lockUnavailable
}

/// An advisory lock that enforces one Qaptr helper process per user.
public final class SingleInstanceLock: @unchecked Sendable {
    private let descriptor: Int32

    /// Opens and exclusively claims `path` without blocking.
    public init(path: URL) throws {
        let parent = path.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw SingleInstanceError.lockUnavailable
        }
        let descriptor = Darwin.open(path.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw SingleInstanceError.lockUnavailable
        }
        guard qaptrFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw SingleInstanceError.alreadyRunning
        }
        self.descriptor = descriptor
    }

    deinit {
        _ = qaptrFlock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

/// The result of asking the cadence planner whether a tick is due.
public enum TickAction: Equatable, Sendable {
    case capture
    case wait
}

/// A monotonic cadence planner that deliberately drops missed ticks.
public struct TickPlanner: Sendable {
    private let interval: TimeInterval
    private var nextDue: TimeInterval?

    /// Creates a planner with no catch-up state.
    public init(interval: CaptureInterval) {
        self.interval = interval.seconds
        self.nextDue = nil
    }

    /// Returns one capture at most and schedules the next tick from `now`.
    ///
    /// When the process was asleep or busy past multiple due times, the next
    /// deadline is reset to `now + interval`. This is the invariant that
    /// prevents wake or latency catch-up bursts.
    public mutating func action(at now: TimeInterval) -> TickAction {
        guard now.isFinite else {
            return .wait
        }
        guard let due = nextDue else {
            nextDue = now + interval
            return .capture
        }
        guard now >= due else {
            return .wait
        }
        nextDue = now + interval
        return .capture
    }
}

/// A process-local single-flight gate for ScreenCaptureKit.
public final class SingleFlightGate: @unchecked Sendable {
    private let lock = NSLock()
    private var occupied = false

    /// Creates an empty gate.
    public init() {}

    /// Attempts to reserve the only capture slot.
    public func acquire() -> Lease? {
        lock.lock()
        defer { lock.unlock() }
        guard !occupied else {
            return nil
        }
        occupied = true
        return Lease(release: release)
    }

    private func release() {
        lock.lock()
        occupied = false
        lock.unlock()
    }

    /// A single-flight reservation released when the value is destroyed.
    public final class Lease: @unchecked Sendable {
        private var releaseReservation: (() -> Void)?

        fileprivate init(release: @escaping () -> Void) {
            self.releaseReservation = release
        }

        deinit {
            releaseReservation?()
            releaseReservation = nil
        }
    }
}

/// A point-in-time context sample. It contains no clipboard or keystroke data.
public struct SampledContext: Codable, Equatable, Sendable {
    public let application: String?
    public let windowTitle: String?
    public let browserHost: String?
    public let documentName: String?

    /// Creates a context snapshot.
    public init(
        application: String?,
        windowTitle: String? = nil,
        browserHost: String? = nil,
        documentName: String? = nil
    ) {
        self.application = application
        self.windowTitle = windowTitle
        self.browserHost = browserHost
        self.documentName = documentName
    }

    /// Encodes the context for the vault's opaque context member.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

/// A pre-scaled image returned by the capture adapter.
public struct CapturedFrame: Sendable {
    public let imageData: Data
    public let width: Int
    public let height: Int

    /// Creates a captured frame after validating its dimensions.
    public init(imageData: Data, width: Int, height: Int) throws {
        guard width > 0, height > 0, !imageData.isEmpty else {
            throw CaptureCoreError.captureFailed("empty captured frame")
        }
        self.imageData = imageData
        self.width = width
        self.height = height
    }
}

/// The boundary used by the helper to perform one already-downscaled capture.
public protocol ImageCapture: Sendable {
    func capture(displayID: String, maxDimension: Int) throws -> CapturedFrame
}

/// The write-only boundary used by the helper to seal a capture.
public protocol BundleSealer: Sendable {
    func seal(captureID: String, frame: CapturedFrame, context: SampledContext) throws
}

/// A single capture tick's observable result.
public enum CaptureEvent: Equatable, Sendable {
    case sealed(captureID: String, displayID: String, width: Int, height: Int)
    case refusedOverlap
    case skippedPermission
    case skippedNoDisplays
    case skippedCapture(displayID: String, reason: String)
    case skippedSealing(displayID: String, reason: String)
}

/// Coordinates one scheduled tick without owning any macOS types.
public final class CaptureCoordinator: @unchecked Sendable {
    private let capture: ImageCapture
    private let sealer: BundleSealer
    private let gate: SingleFlightGate

    /// Creates a coordinator with explicit capture and sealing boundaries.
    public init(capture: ImageCapture, sealer: BundleSealer, gate: SingleFlightGate = SingleFlightGate()) {
        self.capture = capture
        self.sealer = sealer
        self.gate = gate
    }

    /// Runs one tick. A second caller is refused immediately, never queued.
    public func runTick(
        displays: [String],
        context: SampledContext,
        maxDimension: Int = 1_920,
        permissionGranted: Bool = true,
        captureID: (String) -> String
    ) -> [CaptureEvent] {
        guard let lease = gate.acquire() else {
            return [.refusedOverlap]
        }
        defer { _ = lease }
        guard permissionGranted else {
            return [.skippedPermission]
        }
        guard !displays.isEmpty else {
            return [.skippedNoDisplays]
        }

        var events: [CaptureEvent] = []
        for displayID in displays {
            let id = captureID(displayID)
            do {
                let frame = try capture.capture(displayID: displayID, maxDimension: maxDimension)
                do {
                    try sealer.seal(captureID: id, frame: frame, context: context)
                    events.append(.sealed(
                        captureID: id,
                        displayID: displayID,
                        width: frame.width,
                        height: frame.height
                    ))
                } catch {
                    events.append(.skippedSealing(displayID: displayID, reason: String(describing: error)))
                }
            } catch {
                events.append(.skippedCapture(displayID: displayID, reason: String(describing: error)))
            }
        }
        return events
    }
}

/// Reduces a URL to its scheme and hostname, dropping path, query, and fragment.
public func reducedBrowserHost(from value: String) -> String? {
    guard let url = URL(string: value), let host = url.host else {
        return nil
    }
    let scheme = url.scheme.map { "\($0)://" } ?? ""
    return "\(scheme)\(host)"
}
