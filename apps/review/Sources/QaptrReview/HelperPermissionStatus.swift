import Darwin
import Foundation
import QaptrReviewCore

/// A live permission report written by `com.qaptr.helper`.
///
/// Apple's Screen Recording and Accessibility preflight APIs always inspect
/// the current process. Reading them from QaptrReview therefore answers the
/// wrong question. This small file is the process boundary between the helper
/// that owns the permissions and the review UI that presents them.
struct HelperPermissionSnapshot: Decodable, Equatable {
    static let schemaVersion = 2
    static let maximumAgeMillis: Int64 = 5_000

    let version: Int
    let screenRecordingGranted: Bool
    let screenRecordingRequested: Bool
    let accessibilityGranted: Bool
    let accessibilityRequested: Bool
    let processID: Int
    let updatedAtMillis: Int64
    let helperBundlePath: String
    let commandToken: String

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

    var screenRecordingStatus: PermissionStatus {
        if screenRecordingGranted { return .granted }
        return screenRecordingRequested ? .denied : .notDetermined
    }

    var accessibilityStatus: PermissionStatus {
        if accessibilityGranted { return .granted }
        return accessibilityRequested ? .denied : .notDetermined
    }

    static func liveSnapshot(
        data: Data,
        nowMillis: Int64,
        expectedHelperBundlePath: String,
        isProcessRunning: (Int) -> Bool
    ) throws -> Self? {
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard snapshot.version == schemaVersion,
              snapshot.updatedAtMillis <= nowMillis,
              nowMillis - snapshot.updatedAtMillis <= maximumAgeMillis,
              isProcessRunning(snapshot.processID),
              snapshot.helperBundlePath == expectedHelperBundlePath,
              !snapshot.commandToken.isEmpty
        else {
            return nil
        }
        return snapshot
    }
}

func defaultHelperPermissionPath() -> URL {
    if let override = ProcessInfo.processInfo.environment["QAPTR_PERMISSION_STATUS_PATH"],
       !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("Qaptr", isDirectory: true)
        .appendingPathComponent("permission-status.json")
}

func liveHelperPermissionSnapshot(expectedHelperBundleURL: URL) -> HelperPermissionSnapshot? {
    guard let data = try? Data(contentsOf: defaultHelperPermissionPath()) else {
        return nil
    }
    let nowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
    return try? HelperPermissionSnapshot.liveSnapshot(
        data: data,
        nowMillis: nowMillis,
        expectedHelperBundlePath: expectedHelperBundleURL.resolvingSymlinksInPath().standardizedFileURL.path,
        isProcessRunning: { kill(Int32($0), 0) == 0 }
    )
}
