import Foundation

/// The platform boundary used to preflight helper capture before scheduling.
///
/// Implementations must only report the current permission state. They must
/// not request permission or start capture as a side effect.
public protocol CaptureStartupPreflight: Sendable {
    func screenRecordingAccessGranted() -> Bool
    func availableDisplayIDs() throws -> [String]
}

/// The result of helper startup preparation. Preparation never captures or
/// schedules a timer. The caller may schedule only after the result and its
/// corresponding progress record have been persisted.
public enum CaptureStartupResult: Equatable, Sendable {
    case ready(selectedDisplayIDs: [String])
    case permissionRequired
    case noDisplays
    case startupFailed(String)
}

/// Owns the helper's permission and display preflight plus startup status.
public struct CaptureStartupCoordinator: Sendable {
    private let preflight: any CaptureStartupPreflight

    public init(preflight: any CaptureStartupPreflight) {
        self.preflight = preflight
    }

    /// Persists `.starting`, performs a read-only preflight, then persists the
    /// truthful terminal startup state before returning.
    public func prepare(
        progressTracker: inout CaptureProgressTracker,
        progressStore: CaptureProgressStore,
        at timestamp: Int64,
        processID: Int64,
        activeIntervalSeconds: Int
    ) -> CaptureStartupResult {
        progressTracker.beginStartup(
            at: timestamp,
            processID: processID,
            activeIntervalSeconds: activeIntervalSeconds
        )
        do {
            try progressStore.write(progressTracker.progress)
        } catch {
            return .startupFailed("startup progress persistence failed: \(error)")
        }

        let result: CaptureStartupResult
        if !preflight.screenRecordingAccessGranted() {
            progressTracker.markPermissionRequired(
                at: timestamp,
                selectedDisplayIDs: [],
                activeIntervalSeconds: activeIntervalSeconds,
                failureReason: "Screen Recording permission not granted"
            )
            result = .permissionRequired
        } else {
            do {
                let displayIDs = Self.normalizedDisplayIDs(try preflight.availableDisplayIDs())
                if displayIDs.isEmpty {
                    progressTracker.markNoDisplays(
                        at: timestamp,
                        selectedDisplayIDs: [],
                        activeIntervalSeconds: activeIntervalSeconds,
                        failureReason: "no displays available"
                    )
                    result = .noDisplays
                } else {
                    progressTracker.start(
                        at: timestamp,
                        processID: processID,
                        selectedDisplayIDs: displayIDs,
                        activeIntervalSeconds: activeIntervalSeconds
                    )
                    result = .ready(selectedDisplayIDs: displayIDs)
                }
            } catch {
                progressTracker.markError(
                    at: timestamp,
                    selectedDisplayIDs: [],
                    activeIntervalSeconds: activeIntervalSeconds,
                    failureReason: "display enumeration failed: \(error)"
                )
                result = .startupFailed("display enumeration failed: \(error)")
            }
        }

        do {
            try progressStore.write(progressTracker.progress)
        } catch {
            progressTracker.markError(
                at: timestamp,
                selectedDisplayIDs: progressTracker.progress.selectedDisplayIDs,
                activeIntervalSeconds: activeIntervalSeconds,
                failureReason: "startup progress persistence failed: \(error)"
            )
            return .startupFailed("startup progress persistence failed: \(error)")
        }
        return result
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
}
