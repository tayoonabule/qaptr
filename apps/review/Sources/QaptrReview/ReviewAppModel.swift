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

/// The helper's scalar progress file. It is intentionally separate from the
/// durable history database and contains no screenshot material.
func defaultCaptureProgressPath() -> URL {
    if let override = ProcessInfo.processInfo.environment["QAPTR_CAPTURE_PROGRESS_PATH"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("Qaptr", isDirectory: true).appendingPathComponent("capture-progress.json")
}

func defaultCaptureControlPath() -> URL {
    if let override = ProcessInfo.processInfo.environment["QAPTR_CAPTURE_CONTROL_PATH"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("Qaptr", isDirectory: true).appendingPathComponent("capture-control.json")
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
    private(set) var reviewStatus: ReviewStatus? = nil
    private(set) var captureProgress: CaptureProgressSnapshot = .unavailable
    private(set) var captureIntervalSeconds = CaptureIntervalPolicy.defaultSeconds
    private(set) var loadError: String?
    private(set) var reviewStatusError: String? = nil
    private(set) var settings: SettingsState = .placeholder
    private(set) var providerConnection = ProviderConnectionState.notConnected
    var providerSetupRequest: ProviderChoice?
    var onboardingCompleted: Bool

    let preferences: SettingsPreferences
    private let bridge: ReviewBridge?
    private let progressReader: CaptureProgressReader
    private let controlStore: CaptureControlStore
    private let credentialStore: any ProviderCredentialStoring
    private let openRouterChecker: any OpenRouterChecking

    init(
        preferences: SettingsPreferences = SettingsPreferences(store: UserDefaults.standard),
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore(),
        openRouterChecker: any OpenRouterChecking = OpenRouterConnectionChecker()
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.openRouterChecker = openRouterChecker
        self.onboardingCompleted = preferences.onboardingCompleted
        let storePath = defaultStorePath()
        self.progressReader = CaptureProgressReader(url: defaultCaptureProgressPath())
        self.controlStore = CaptureControlStore(url: defaultCaptureControlPath())
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
        refreshCaptureProgress()
        refreshSettings()
    }

    /// Reloads the durable-history snapshot from `qaptr-store`.
    func refresh() {
        refreshCaptureProgress()
        guard let bridge else { return }
        do {
            reviewStatus = try bridge.reviewStatus()
            reviewStatusError = nil
        } catch {
            reviewStatus = nil
            reviewStatusError = String(describing: error)
        }
        do {
            snapshot = try bridge.snapshot()
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    /// Reloads scalar helper progress independently from durable observations.
    /// Missing or corrupt status is shown as unavailable and never blocks the
    /// observation history from loading.
    func refreshCaptureProgress() {
        captureProgress = (try? progressReader.read()) ?? .unavailable
        let control = (try? controlStore.read()) ?? .default
        captureIntervalSeconds = control.intervalSeconds
        settings.intervalSeconds = control.intervalSeconds
        // Missing or corrupt control files fall back to the safe default and
        // are rewritten canonically. This writes no image data.
        try? controlStore.write(control)
    }

    /// Persists the only mutable capture setting. The helper polls this scalar
    /// control file and applies it without opening or exposing image material.
    func setCaptureIntervalSeconds(_ seconds: Int) {
        let normalized = CaptureIntervalPolicy.normalized(seconds)
        do {
            let control = try CaptureControl(intervalSeconds: normalized)
            try controlStore.write(control)
            captureIntervalSeconds = normalized
            settings.intervalSeconds = normalized
        } catch {
            // Keep the previous value when the control could not be persisted.
        }
    }

    /// Reloads permission and login-item status without prompting.
    func refreshSettings() {
        var next = settings
        next.intervalSeconds = captureIntervalSeconds
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
        refreshProviderConnection()
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
        refreshProviderConnection()
    }

    /// Removes the provider preference without triggering a provider request.
    func clearProvider() {
        preferences.provider = nil
        settings.provider = nil
        providerSetupRequest = nil
        providerConnection = .notConnected
    }

    func connectProvider(_ provider: ProviderChoice) {
        setProvider(provider)
        guard provider == .openRouter else { return }
        providerSetupRequest = .openRouter
        providerConnection = credentialStore.containsOpenRouterKey() ? .notConnected : .needsKey
    }

    func dismissProviderSetup() {
        providerSetupRequest = nil
    }

    func startOpenRouterConnectionCheck(_ key: String) {
        providerConnection = .checking
        do {
            try credentialStore.saveOpenRouterKey(key)
        } catch {
            providerConnection = .failed(.unableToSave)
            return
        }
        let checker = openRouterChecker
        Task { [weak self] in
            let result = await checker.check(apiKey: key)
            await MainActor.run {
                self?.providerConnection = result
                if result == .connected { self?.providerSetupRequest = nil }
            }
        }
    }

    func disconnectProvider() {
        if settings.provider == .openRouter { try? credentialStore.removeOpenRouterKey() }
        clearProvider()
    }

    private func refreshProviderConnection() {
        guard let provider = settings.provider else {
            providerConnection = .notConnected
            return
        }
        providerConnection = provider == .openRouter && !credentialStore.containsOpenRouterKey() ? .needsKey : .notConnected
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
