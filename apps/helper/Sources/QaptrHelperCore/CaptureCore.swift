import Foundation
import Darwin

@_silgen_name("flock")
private func qaptrFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// The helper's bounded capture interval.
public struct CaptureInterval: Equatable, Sendable {
    public static let minimumSeconds = 5
    public static let maximumSeconds = 1_800
    public static let stepSeconds = 5
    public static let defaultSeconds = 60

    /// The interval in whole seconds. It is constrained to the same values
    /// exposed by the review app's cadence choices.
    public let seconds: Int

    /// Creates a validated interval.
    public init(seconds: Int) throws {
        guard (Self.minimumSeconds...Self.maximumSeconds).contains(seconds),
              seconds.isMultiple(of: Self.stepSeconds) else {
            throw CaptureCoreError.invalidInterval(TimeInterval(seconds))
        }
        self.seconds = seconds
    }

    public init(timeInterval: TimeInterval) throws {
        guard timeInterval.isFinite,
              timeInterval.rounded() == timeInterval,
              let seconds = Int(exactly: timeInterval) else {
            throw CaptureCoreError.invalidInterval(timeInterval)
        }
        try self.init(seconds: seconds)
    }

    public var timeInterval: TimeInterval { TimeInterval(seconds) }
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

/// The result of asking the interval planner whether a tick is due.
public enum TickAction: Equatable, Sendable {
    case capture
    case wait
}

/// A monotonic interval planner that deliberately drops missed ticks.
public struct TickPlanner: Sendable {
    private let interval: TimeInterval
    private var nextDue: TimeInterval?

    /// Creates a planner with no catch-up state.
    public init(interval: CaptureInterval) {
        self.interval = interval.timeInterval
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

/// The helper's durable, scalar capture state. This never contains image data.
public enum CaptureProgressState: String, Codable, Equatable, Sendable {
    case starting
    case waiting
    case capturing
    case permissionRequired
    case noDisplays
    case error
    case stopped
}

/// The only mutable capture setting exposed to the review app.
public struct CaptureControl: Codable, Equatable, Sendable {
    public let intervalSeconds: Int

    private init(uncheckedIntervalSeconds: Int) {
        self.intervalSeconds = uncheckedIntervalSeconds
    }

    public init(intervalSeconds: Int = CaptureInterval.defaultSeconds) throws {
        _ = try CaptureInterval(seconds: intervalSeconds)
        self.init(uncheckedIntervalSeconds: intervalSeconds)
    }

    public static let `default` = CaptureControl(uncheckedIntervalSeconds: CaptureInterval.defaultSeconds)

    private enum CodingKeys: String, CodingKey {
        case intervalSeconds = "interval_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let interval = try container.decodeIfPresent(Int.self, forKey: .intervalSeconds) {
            guard let control = try? CaptureControl(intervalSeconds: interval) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .intervalSeconds,
                    in: container,
                    debugDescription: "interval_seconds must be a multiple of 5 from 5 through 1800"
                )
            }
            self = control
            return
        }
        throw DecodingError.keyNotFound(
            CodingKeys.intervalSeconds,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "missing interval_seconds")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intervalSeconds, forKey: .intervalSeconds)
    }
}

/// Atomic persistence for the scalar capture interval control.
public struct CaptureControlStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() throws -> CaptureControl {
        try JSONDecoder().decode(CaptureControl.self, from: Data(contentsOf: url))
    }

    public func write(_ control: CaptureControl) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(control)
        try data.write(to: url, options: .atomic)
    }
}

/// The small status record shared by the capture helper and review app.
///
/// `captureCount` counts successfully sealed screenshots, not attempts. The
/// review app can therefore distinguish real capture progress from an empty
/// analysis result without seeing image contents.
public struct CaptureProgress: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let version: Int
    public let revision: Int64
    public let state: CaptureProgressState
    public let captureCount: Int
    public let lastCaptureAtMillis: Int64?
    public let lastAttemptedAtMillis: Int64?
    public let startedAtMillis: Int64?
    public let updatedAtMillis: Int64
    public let processID: Int64?
    public let selectedDisplayIDs: [String]
    public let activeIntervalSeconds: Int?
    public let failureReason: String?

    public init(
        state: CaptureProgressState,
        captureCount: Int = 0,
        lastCaptureAtMillis: Int64? = nil,
        startedAtMillis: Int64? = nil,
        updatedAtMillis: Int64 = 0,
        processID: Int64? = nil,
        version: Int = CaptureProgress.schemaVersion,
        revision: Int64 = 0,
        lastAttemptedAtMillis: Int64? = nil,
        selectedDisplayIDs: [String] = [],
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        self.version = max(Self.schemaVersion, version)
        self.revision = max(0, revision)
        self.state = state
        self.captureCount = max(0, captureCount)
        self.lastCaptureAtMillis = lastCaptureAtMillis
        self.lastAttemptedAtMillis = lastAttemptedAtMillis
        self.startedAtMillis = startedAtMillis
        self.updatedAtMillis = updatedAtMillis
        self.processID = processID
        self.selectedDisplayIDs = Self.normalizedDisplayIDs(selectedDisplayIDs)
        self.activeIntervalSeconds = activeIntervalSeconds
        self.failureReason = Self.conciseFailureReason(failureReason)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case revision
        case state
        case captureCount = "capture_count"
        case lastCaptureAtMillis = "last_capture_at_ms"
        case lastAttemptedAtMillis = "last_attempted_at_ms"
        case startedAtMillis = "started_at_ms"
        case updatedAtMillis = "updated_at_ms"
        case processID = "process_id"
        case selectedDisplayIDs = "selected_display_ids"
        case activeIntervalSeconds = "active_interval_seconds"
        case failureReason = "failure_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            state: try container.decode(CaptureProgressState.self, forKey: .state),
            captureCount: try container.decodeIfPresent(Int.self, forKey: .captureCount) ?? 0,
            lastCaptureAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastCaptureAtMillis),
            startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis),
            updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
            processID: try container.decodeIfPresent(Int64.self, forKey: .processID),
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.schemaVersion,
            revision: try container.decodeIfPresent(Int64.self, forKey: .revision) ?? 0,
            lastAttemptedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastAttemptedAtMillis),
            selectedDisplayIDs: try container.decodeIfPresent([String].self, forKey: .selectedDisplayIDs) ?? [],
            activeIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .activeIntervalSeconds),
            failureReason: try container.decodeIfPresent(String.self, forKey: .failureReason)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(revision, forKey: .revision)
        try container.encode(state, forKey: .state)
        try container.encode(captureCount, forKey: .captureCount)
        try container.encodeIfPresent(lastCaptureAtMillis, forKey: .lastCaptureAtMillis)
        try container.encodeIfPresent(lastAttemptedAtMillis, forKey: .lastAttemptedAtMillis)
        try container.encodeIfPresent(startedAtMillis, forKey: .startedAtMillis)
        try container.encode(updatedAtMillis, forKey: .updatedAtMillis)
        try container.encodeIfPresent(processID, forKey: .processID)
        try container.encode(selectedDisplayIDs, forKey: .selectedDisplayIDs)
        try container.encodeIfPresent(activeIntervalSeconds, forKey: .activeIntervalSeconds)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

    private static func normalizedDisplayIDs(_ displayIDs: [String]) -> [String] {
        Array(
            Set(
                displayIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    private static func conciseFailureReason(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let singleLine = reason
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(256))
    }

    public static let initial = CaptureProgress(state: .stopped)
}

/// Deterministic state machine for capture-progress transitions.
public struct CaptureProgressTracker: Sendable {
    public private(set) var progress: CaptureProgress

    public init(initial: CaptureProgress = .initial) {
        self.progress = initial
    }

    public mutating func start(
        at timestamp: Int64,
        processID: Int64,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil
    ) {
        progress = CaptureProgress(
            state: .waiting,
            captureCount: progress.captureCount,
            lastCaptureAtMillis: progress.lastCaptureAtMillis,
            startedAtMillis: timestamp,
            updatedAtMillis: timestamp,
            processID: processID,
            version: progress.version,
            revision: nextRevision(),
            lastAttemptedAtMillis: progress.lastAttemptedAtMillis,
            selectedDisplayIDs: selectedDisplayIDs ?? progress.selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds ?? progress.activeIntervalSeconds
        )
    }

    public mutating func beginCapture(
        at timestamp: Int64,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil
    ) {
        progress = replacing(
            state: .capturing,
            updatedAtMillis: timestamp,
            lastAttemptedAtMillis: timestamp,
            selectedDisplayIDs: selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds,
            failureReason: nil
        )
    }

    public mutating func finishCapture(
        at timestamp: Int64,
        successfulCaptures: Int,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        let count = max(0, successfulCaptures)
        progress = replacing(
            state: .waiting,
            updatedAtMillis: timestamp,
            captureCount: progress.captureCount + count,
            lastCaptureAtMillis: count > 0 ? timestamp : progress.lastCaptureAtMillis,
            selectedDisplayIDs: selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds,
            failureReason: failureReason
        )
    }

    public mutating func markPermissionRequired(
        at timestamp: Int64,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        progress = replacing(
            state: .permissionRequired,
            updatedAtMillis: timestamp,
            lastAttemptedAtMillis: timestamp,
            selectedDisplayIDs: selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds,
            failureReason: failureReason
        )
    }

    public mutating func markNoDisplays(
        at timestamp: Int64,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        progress = replacing(
            state: .noDisplays,
            updatedAtMillis: timestamp,
            lastAttemptedAtMillis: timestamp,
            selectedDisplayIDs: selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds,
            failureReason: failureReason
        )
    }

    public mutating func markError(
        at timestamp: Int64,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        progress = replacing(
            state: .error,
            updatedAtMillis: timestamp,
            lastAttemptedAtMillis: timestamp,
            selectedDisplayIDs: selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds,
            failureReason: failureReason
        )
    }

    public mutating func stop(
        at timestamp: Int64,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        progress = replacing(
            state: .stopped,
            updatedAtMillis: timestamp,
            selectedDisplayIDs: selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds,
            failureReason: failureReason
        )
    }

    private func replacing(
        state: CaptureProgressState,
        updatedAtMillis: Int64,
        captureCount: Int? = nil,
        lastCaptureAtMillis: Int64? = nil,
        lastAttemptedAtMillis: Int64? = nil,
        selectedDisplayIDs: [String]? = nil,
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) -> CaptureProgress {
        CaptureProgress(
            state: state,
            captureCount: captureCount ?? progress.captureCount,
            lastCaptureAtMillis: lastCaptureAtMillis ?? progress.lastCaptureAtMillis,
            startedAtMillis: progress.startedAtMillis,
            updatedAtMillis: updatedAtMillis,
            processID: progress.processID,
            version: max(CaptureProgress.schemaVersion, progress.version),
            revision: nextRevision(),
            lastAttemptedAtMillis: lastAttemptedAtMillis ?? progress.lastAttemptedAtMillis,
            selectedDisplayIDs: selectedDisplayIDs ?? progress.selectedDisplayIDs,
            activeIntervalSeconds: activeIntervalSeconds ?? progress.activeIntervalSeconds,
            failureReason: failureReason
        )
    }

    private func nextRevision() -> Int64 {
        progress.revision == Int64.max ? Int64.max : progress.revision + 1
    }
}

/// Atomic persistence for the scalar helper status record.
public struct CaptureProgressStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() throws -> CaptureProgress {
        try JSONDecoder().decode(CaptureProgress.self, from: Data(contentsOf: url))
    }

    public func write(_ progress: CaptureProgress) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(progress)
        try data.write(to: url, options: .atomic)
    }
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
