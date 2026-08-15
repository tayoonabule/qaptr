import Foundation
import QaptrReviewCore
import Observation

/// The review app's bundle identifier, matched by the U22 packaging pipeline
/// and by `MacPermissions`/TCC lookups in `qaptr-review-ffi`.
let reviewBundleIdentifier = "com.qaptr.review"

/// The default durable-history database location under the app's support
/// directory, matching `qaptr-store`'s SQLite WAL file.
func defaultStorePath() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("Qaptr", isDirectory: true).appendingPathComponent("history.sqlite3")
}

/// The single observable source of truth driving every SwiftUI view.
///
/// This model never launches a tool, executes an automation, or invokes a
/// provider. It only reads durable history and permission/login-item status
/// through `ReviewBridge`, and reads/writes local settings preferences.
@MainActor
@Observable
final class ReviewAppModel {
    private(set) var snapshot: ReviewSnapshot = .empty
    private(set) var loadError: String?
    private(set) var settings: SettingsState = .placeholder
    var onboardingCompleted: Bool

    let preferences: SettingsPreferences
    private let bridge: ReviewBridge?

    init(preferences: SettingsPreferences = SettingsPreferences(store: UserDefaults.standard)) {
        self.preferences = preferences
        self.onboardingCompleted = preferences.onboardingCompleted
        let storePath = defaultStorePath()
        do {
            try FileManager.default.createDirectory(
                at: storePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            self.bridge = try ReviewBridge(storePath: storePath, bundleIdentifier: reviewBundleIdentifier)
        } catch {
            self.bridge = nil
            self.loadError = String(describing: error)
        }
        refreshSettings()
    }

    /// Reloads the durable-history snapshot from `qaptr-store`.
    func refresh() {
        guard let bridge else { return }
        do {
            snapshot = try bridge.snapshot()
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    /// Reloads permission and login-item status without prompting.
    func refreshSettings() {
        var next = settings
        next.availableDisplayIDs = DisplayEnumerator.currentDisplays().map(\.id)
        next.cacheLifetime = preferences.cacheLifetime
        next.provider = preferences.provider
        next.excludedApplications = preferences.excludedApplications
        next.excludedWindowTitles = preferences.excludedWindowTitles
        if let bridge {
            next.screenRecordingStatus = bridge.permissionState(.screenCapture)
            next.accessibilityContextStatus = bridge.permissionState(.accessibilityContext)
            next.loginItemEnabled = bridge.loginItemEnabled()
        }
        settings = next
    }

    /// Requests Screen Recording through the native prompt.
    func requestScreenRecording() {
        guard let bridge else { return }
        settings.screenRecordingStatus = bridge.requestPermission(.screenCapture)
    }

    /// Requests the optional accessibility-context permission.
    func requestAccessibilityContext() {
        guard let bridge else { return }
        settings.accessibilityContextStatus = bridge.requestPermission(.accessibilityContext)
    }

    /// Sets whether Qaptr starts at login.
    func setLoginItemEnabled(_ enabled: Bool) {
        guard let bridge else { return }
        settings.loginItemEnabled = bridge.setLoginItemEnabled(enabled)
    }

    func setCacheLifetime(_ lifetime: CacheLifetime) {
        preferences.cacheLifetime = lifetime
        settings.cacheLifetime = lifetime
    }

    func setProvider(_ provider: ProviderChoice) {
        preferences.provider = provider
        settings.provider = provider
    }

    func addExcludedApplication(_ raw: String) {
        preferences.addExcludedApplication(raw)
        settings.excludedApplications = preferences.excludedApplications
    }

    func removeExcludedApplication(_ entry: String) {
        preferences.removeExcludedApplication(entry)
        settings.excludedApplications = preferences.excludedApplications
    }

    func addExcludedWindowTitle(_ raw: String) {
        preferences.addExcludedWindowTitle(raw)
        settings.excludedWindowTitles = preferences.excludedWindowTitles
    }

    func removeExcludedWindowTitle(_ entry: String) {
        preferences.removeExcludedWindowTitle(entry)
        settings.excludedWindowTitles = preferences.excludedWindowTitles
    }

    func completeOnboarding() {
        preferences.onboardingCompleted = true
        onboardingCompleted = true
    }
}
