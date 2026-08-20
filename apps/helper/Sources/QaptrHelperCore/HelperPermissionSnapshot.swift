import Foundation

/// The helper's live macOS permission state.
///
/// Screen Recording and Accessibility are process-scoped TCC permissions. The
/// helper is the process that uses both capabilities, so it is the only process
/// that can report them truthfully through Apple's public preflight APIs.
public struct HelperPermissionSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 2

    public let version: Int
    public let screenRecordingGranted: Bool
    public let screenRecordingRequested: Bool
    public let accessibilityGranted: Bool
    public let accessibilityRequested: Bool
    public let processID: Int
    public let updatedAtMillis: Int64
    public let helperBundlePath: String
    public let commandToken: String

    public init(
        screenRecordingGranted: Bool,
        screenRecordingRequested: Bool,
        accessibilityGranted: Bool,
        accessibilityRequested: Bool,
        processID: Int,
        updatedAtMillis: Int64,
        helperBundlePath: String,
        commandToken: String
    ) {
        self.version = Self.schemaVersion
        self.screenRecordingGranted = screenRecordingGranted
        self.screenRecordingRequested = screenRecordingRequested
        self.accessibilityGranted = accessibilityGranted
        self.accessibilityRequested = accessibilityRequested
        self.processID = processID
        self.updatedAtMillis = updatedAtMillis
        self.helperBundlePath = helperBundlePath
        self.commandToken = commandToken
    }

    enum CodingKeys: String, CodingKey {
        case version
        case screenRecordingGranted = "screen_recording_granted"
        case screenRecordingRequested = "screen_recording_requested"
        case accessibilityGranted = "accessibility_granted"
        case accessibilityRequested = "accessibility_requested"
        case processID = "process_id"
        case updatedAtMillis = "updated_at_ms"
        case helperBundlePath = "helper_bundle_path"
        case commandToken = "command_token"
    }
}

/// Atomic persistence for the helper's small, image-free permission snapshot.
public struct HelperPermissionSnapshotStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() throws -> HelperPermissionSnapshot {
        try JSONDecoder().decode(HelperPermissionSnapshot.self, from: Data(contentsOf: url))
    }

    public func write(_ snapshot: HelperPermissionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
