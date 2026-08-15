import Darwin
import Foundation

/// States written by the background capture helper.
public enum CaptureProgressState: String, Codable, Equatable, Sendable {
    case starting
    case waiting
    case capturing
    case permissionRequired
    case noDisplays
    case error
    case stopped
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
/// count.
public struct CaptureProgressSnapshot: Codable, Equatable, Sendable {
    public let state: CaptureProgressState
    public let captureCount: Int?
    public let lastCaptureAtMillis: Int64?
    public let startedAtMillis: Int64?
    public let updatedAtMillis: Int64?
    public let processID: Int64?

    public init(
        state: CaptureProgressState,
        captureCount: Int?,
        lastCaptureAtMillis: Int64? = nil,
        startedAtMillis: Int64? = nil,
        updatedAtMillis: Int64? = nil,
        processID: Int64? = nil
    ) {
        self.state = state
        self.captureCount = captureCount
        self.lastCaptureAtMillis = lastCaptureAtMillis
        self.startedAtMillis = startedAtMillis
        self.updatedAtMillis = updatedAtMillis
        self.processID = processID
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case captureCount = "capture_count"
        case lastCaptureAtMillis = "last_capture_at_ms"
        case startedAtMillis = "started_at_ms"
        case updatedAtMillis = "updated_at_ms"
        case processID = "process_id"
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
        }
    }

    public var lastCaptureDate: Date? {
        guard let lastCaptureAtMillis else { return nil }
        return Date(timeIntervalSince1970: Double(lastCaptureAtMillis) / 1_000)
    }
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
