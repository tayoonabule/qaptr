import Darwin
import Foundation

/// States written by the background capture helper.
///
/// `.unknown` exists purely for forward compatibility: if a newer helper
/// schema writes a state string this build has never heard of, decoding
/// degrades to `.unknown` instead of throwing and losing every other field
/// in the snapshot. It is never written by this build.
public enum CaptureProgressState: String, Equatable, Sendable {
    case starting
    case waiting
    case capturing
    case permissionRequired
    case noDisplays
    case error
    case stopped
    case unknown
}

extension CaptureProgressState: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptureProgressState(rawValue: raw) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The canonical interval bounds shared by the review slider and control file.
public enum CaptureIntervalPolicy {
    public static let minimumSeconds = 5
    public static let maximumSeconds = 300
    public static let stepSeconds = 5
    public static let defaultSeconds = 60

    public static func isValid(_ seconds: Int) -> Bool {
        (minimumSeconds...maximumSeconds).contains(seconds) && seconds.isMultiple(of: stepSeconds)
    }

    /// Clamps to the supported range and rounds to the nearest supported step.
    public static func normalized(_ seconds: Int) -> Int {
        let bounded = min(max(seconds, minimumSeconds), maximumSeconds)
        let stepped = Int((Double(bounded) / Double(stepSeconds)).rounded()) * stepSeconds
        return min(max(stepped, minimumSeconds), maximumSeconds)
    }

    public static func humanized(_ seconds: Int) -> String {
        let normalized = normalized(seconds)
        guard normalized % 60 == 0 else { return "\(normalized) seconds" }
        let minutes = normalized / 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

public enum CaptureControlError: Error, Equatable, Sendable {
    case invalidInterval(Int)
}

public struct CaptureControl: Codable, Equatable, Sendable {
    public let intervalSeconds: Int

    private init(uncheckedIntervalSeconds: Int) {
        self.intervalSeconds = uncheckedIntervalSeconds
    }

    public init(intervalSeconds: Int = CaptureIntervalPolicy.defaultSeconds) throws {
        guard CaptureIntervalPolicy.isValid(intervalSeconds) else {
            throw CaptureControlError.invalidInterval(intervalSeconds)
        }
        self.init(uncheckedIntervalSeconds: intervalSeconds)
    }

    public static let `default` = CaptureControl(uncheckedIntervalSeconds: CaptureIntervalPolicy.defaultSeconds)

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
                    debugDescription: "interval_seconds must be a multiple of 5 from 5 through 300"
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

public struct CaptureControlStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() throws -> CaptureControl {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptureControl.self, from: data)
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

/// Scalar capture evidence shared through Application Support.
///
/// This file contains no image bytes, paths, or provider data. A missing or
/// malformed file remains unknown rather than being turned into a made-up
/// count. `version`/`revision` let the review app recognize a fresh write
/// from the helper (including across schema upgrades) without inspecting
/// image material. Decoding a status written by a newer schema version keeps
/// forward-compatibility: unknown fields are ignored, and any field this
/// build does not yet know about degrades to its safe default rather than
/// failing the read.
public struct CaptureProgressSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let version: Int
    public let revision: Int64
    public let state: CaptureProgressState
    public let captureCount: Int?
    public let lastCaptureAtMillis: Int64?
    public let lastAttemptedAtMillis: Int64?
    public let startedAtMillis: Int64?
    public let updatedAtMillis: Int64?
    public let processID: Int64?
    public let selectedDisplayIDs: [String]
    public let activeIntervalSeconds: Int?
    public let failureReason: String?

    public init(
        state: CaptureProgressState,
        captureCount: Int?,
        lastCaptureAtMillis: Int64? = nil,
        startedAtMillis: Int64? = nil,
        updatedAtMillis: Int64? = nil,
        processID: Int64? = nil,
        version: Int = CaptureProgressSnapshot.schemaVersion,
        revision: Int64 = 0,
        lastAttemptedAtMillis: Int64? = nil,
        selectedDisplayIDs: [String] = [],
        activeIntervalSeconds: Int? = nil,
        failureReason: String? = nil
    ) {
        self.version = max(Self.schemaVersion, version)
        self.revision = max(0, revision)
        self.state = state
        self.captureCount = captureCount
        self.lastCaptureAtMillis = lastCaptureAtMillis
        self.lastAttemptedAtMillis = lastAttemptedAtMillis
        self.startedAtMillis = startedAtMillis
        self.updatedAtMillis = updatedAtMillis
        self.processID = processID
        self.selectedDisplayIDs = selectedDisplayIDs
        self.activeIntervalSeconds = activeIntervalSeconds
        self.failureReason = failureReason
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
            captureCount: try container.decodeIfPresent(Int.self, forKey: .captureCount),
            lastCaptureAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastCaptureAtMillis),
            startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis),
            updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis),
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
        try container.encodeIfPresent(captureCount, forKey: .captureCount)
        try container.encodeIfPresent(lastCaptureAtMillis, forKey: .lastCaptureAtMillis)
        try container.encodeIfPresent(lastAttemptedAtMillis, forKey: .lastAttemptedAtMillis)
        try container.encodeIfPresent(startedAtMillis, forKey: .startedAtMillis)
        try container.encodeIfPresent(updatedAtMillis, forKey: .updatedAtMillis)
        try container.encodeIfPresent(processID, forKey: .processID)
        try container.encode(selectedDisplayIDs, forKey: .selectedDisplayIDs)
        try container.encodeIfPresent(activeIntervalSeconds, forKey: .activeIntervalSeconds)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

    public static let unavailable = CaptureProgressSnapshot(state: .stopped, captureCount: nil)

    /// A waiting or active capture state is only called active while the
    /// helper process that wrote it still exists. This prevents a stale file
    /// after a crash from claiming that background capture is running.
    public var helperIsRunning: Bool {
        guard state != .stopped, let processID, processID > 0 else {
            return false
        }
        return Darwin.kill(pid_t(processID), 0) == 0
    }

    public var statusLabel: String {
        switch state {
        case .starting:
            "Starting"
        case .waiting:
            helperIsRunning ? "Background capture active" : "Helper not running"
        case .capturing:
            helperIsRunning ? "Capturing now" : "Capture interrupted"
        case .permissionRequired:
            "Screen Recording permission required"
        case .noDisplays:
            "No display available"
        case .error:
            "Capture unavailable"
        case .stopped:
            "Not running"
        case .unknown:
            "Capture status unavailable"
        }
    }

    public var lastCaptureDate: Date? {
        guard let lastCaptureAtMillis else { return nil }
        return Date(timeIntervalSince1970: Double(lastCaptureAtMillis) / 1_000)
    }

    /// The six truthful capture states the review app is allowed to show.
    /// Every combination of the raw helper `state` and derived evidence
    /// (missing file, stale process, capture history) maps to exactly one of
    /// these. There is no seventh "unknown but probably fine" bucket.
    public var readiness: CaptureReadiness {
        guard captureCount != nil else {
            return .neverConfigured
        }
        switch state {
        case .permissionRequired:
            return .permissionDenied
        case .error, .noDisplays:
            return .captureFailed
        case .capturing:
            return helperIsRunning ? .capturing : .captureFailed
        case .starting:
            return .waitingForFirstTick
        case .waiting, .stopped:
            return (captureCount ?? 0) > 0 ? .captureReady : .waitingForFirstTick
        case .unknown:
            // A state string this build does not recognize (e.g. written by
            // a newer helper schema) is truthfully unavailable rather than
            // guessed as ready or actively capturing.
            return .captureFailed
        }
    }

    /// A concise, actionable reason shown only for unavailable/failed states.
    /// Returns nil when the state does not warrant a reason (e.g. capturing
    /// normally, or already showing ready captures).
    public var actionableReason: String? {
        if let failureReason, !failureReason.isEmpty {
            return failureReason
        }
        if state == .unknown {
            // An unrecognized state maps to `.captureFailed` for safety, but
            // it may in fact represent a successful new state this build
            // simply cannot interpret yet. Say that truthfully instead of
            // claiming a capture attempt failed.
            return "Update Qaptr to interpret the capture helper status."
        }
        switch readiness {
        case .neverConfigured:
            return "The capture helper has not reported any status yet."
        case .permissionDenied:
            return "Grant Screen Recording permission in System Settings, then reopen Qaptr."
        case .captureFailed:
            return "The last capture attempt did not succeed."
        case .waitingForFirstTick, .capturing, .captureReady:
            return nil
        }
    }
}

/// The six truthful, mutually exclusive capture states the review app shows.
/// This is intentionally closed: every `CaptureProgressSnapshot` maps to
/// exactly one case through `readiness`, so the UI never needs a fallback
/// "unknown" branch.
public enum CaptureReadiness: Equatable, Sendable {
    case neverConfigured
    case permissionDenied
    case waitingForFirstTick
    case capturing
    case captureFailed
    case captureReady
}

/// Reads the helper's atomic scalar progress file.
public struct CaptureProgressReader: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() throws -> CaptureProgressSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptureProgressSnapshot.self, from: data)
    }
}
