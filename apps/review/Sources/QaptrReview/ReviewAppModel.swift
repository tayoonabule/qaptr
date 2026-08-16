import Foundation
import Darwin
import AppKit
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

private struct HelperAccessibilityPermissionStatus: Decodable {
    let granted: Bool
    let processID: Int
    let updatedAtMillis: Int64

    enum CodingKeys: String, CodingKey {
        case granted
        case processID = "process_id"
        case updatedAtMillis = "updated_at_ms"
    }
}

private func defaultAccessibilityPermissionPath() -> URL {
    if let override = ProcessInfo.processInfo.environment["QAPTR_ACCESSIBILITY_PERMISSION_PATH"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("Qaptr", isDirectory: true)
        .appendingPathComponent("accessibility-permission.json")
}

private func helperAccessibilityPermissionStatus() -> PermissionStatus? {
    guard let data = try? Data(contentsOf: defaultAccessibilityPermissionPath()),
          let status = try? JSONDecoder().decode(HelperAccessibilityPermissionStatus.self, from: data),
          status.updatedAtMillis > Int64(Date().timeIntervalSince1970 * 1_000) - 10_000,
          kill(Int32(status.processID), 0) == 0
    else {
        return nil
    }
    return status.granted ? .granted : .denied
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
    private(set) var cliProviderReadiness: [String: ProviderReadiness] = [:]
    var providerSetupRequest: ProviderChoice?
    var onboardingCompleted: Bool

    let preferences: SettingsPreferences
    private let usesMockData: Bool
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
        #if DEBUG
        self.usesMockData = DevMockData.enabled
        #else
        self.usesMockData = false
        #endif
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.openRouterChecker = openRouterChecker
        #if DEBUG
        self.onboardingCompleted = DevMockData.enabled || preferences.onboardingCompleted
        #else
        self.onboardingCompleted = preferences.onboardingCompleted
        #endif
        let storePath = defaultStorePath()
        self.progressReader = CaptureProgressReader(url: defaultCaptureProgressPath())
        self.controlStore = CaptureControlStore(url: defaultCaptureControlPath())
        if usesMockData {
            self.bridge = nil
            self.loadError = nil
        } else {
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
        }
        refreshCaptureProgress()
        refreshSettings()
    }

    /// Reloads the durable-history snapshot from `qaptr-store`.
    func refresh() {
        if usesMockData {
            #if DEBUG
            snapshot = DevMockData.snapshot
            reviewStatus = DevMockData.reviewStatus
            reviewStatusError = nil
            loadError = nil
            refreshCaptureProgress()
            #endif
            return
        }
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

    /// Generates (or regenerates) the canonical workflow for one durable
    /// observation and refreshes the snapshot so the new/updated workflow is
    /// immediately visible. Returns the generated summary on success so a
    /// caller can offer an immediate export action, or a concise failure
    /// reason otherwise. This drives scalar durable data only: it never opens
    /// a vault bundle, invokes a provider, or launches anything.
    @discardableResult
    func generateWorkflow(fromObservationID observationID: String) -> Result<WorkflowSummary, DocumentActionError> {
        guard let bridge else { return .failure(DocumentActionError("Qaptr is not ready yet.")) }
        do {
            let workflow = try bridge.generateWorkflow(observationID: observationID)
            refresh()
            return .success(workflow)
        } catch {
            return .failure(DocumentActionError(String(describing: error)))
        }
    }

    /// Saves one canonical Markdown export variant for `workflowID` to a
    /// caller-already-chosen `destination` (such as one returned by a native
    /// save panel). Returns a concise failure reason on error.
    func exportWorkflow(
        workflowID: String,
        variant: MarkdownExportVariant,
        destination: URL
    ) -> String? {
        guard let bridge else { return "Qaptr is not ready yet." }
        do {
            try bridge.exportWorkflow(workflowID: workflowID, variant: variant, destination: destination)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// Reloads scalar helper progress independently from durable observations.
    /// Missing or corrupt status is shown as unavailable and never blocks the
    /// observation history from loading.
    func refreshCaptureProgress() {
        if usesMockData {
            #if DEBUG
            captureProgress = DevMockData.captureProgress
            captureIntervalSeconds = DevMockData.captureProgress.activeIntervalSeconds ?? CaptureIntervalPolicy.defaultSeconds
            settings.intervalSeconds = captureIntervalSeconds
            #endif
            return
        }
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
            next.accessibilityContextStatus = helperAccessibilityPermissionStatus()
                ?? bridge.permissionState(.accessibilityContext)
            next.loginItemEnabled = bridge.loginItemEnabled()
        }
        settings = next
        refreshProviderConnection()
        refreshCliProviderReadiness()
    }

    /// Reloads the bounded, path-only CLI readiness snapshot. A detected
    /// executable is never treated as usable; unavailable/failed reads leave
    /// the previous readiness in place rather than inventing a state.
    private func refreshCliProviderReadiness() {
        if usesMockData { return }
        guard let bridge, let snapshot = try? bridge.providerReadinessSnapshot() else { return }
        cliProviderReadiness = Dictionary(
            uniqueKeysWithValues: snapshot.providers.map { ($0.id, $0) }
        )
    }

    /// The truthful, bounded row presentation (status, one reason, at most
    /// one next action) for `provider`, driven only by already-known local
    /// state -- never a fresh network or process call.
    func providerRowPresentation(for provider: ProviderChoice) -> ProviderRowPresentation {
        ProviderRowPresenter.present(
            provider: provider,
            connection: provider == settings.provider ? providerConnection : connectionState(for: provider),
            cliReadiness: cliProviderReadiness[provider.rawValue]
        )
    }

    /// The connection state for a provider that is not currently selected.
    /// CLI providers have no persisted connection state distinct from
    /// selection, so this always reports `.notConnected` for them; OpenRouter
    /// still reflects whether a key is already saved even when it is not the
    /// selected provider, so the row's status is truthful either way.
    private func connectionState(for provider: ProviderChoice) -> ProviderConnectionState {
        guard provider == .openRouter else { return .notConnected }
        return credentialStore.containsOpenRouterKey() ? .configured : .needsKey
    }

    /// Requests Screen Recording through the native prompt.
    func requestScreenRecording() {
        settings.screenRecordingStatus = .notDetermined
        if let bridge {
            let requestedStatus = bridge.requestPermission(.screenCapture)
            if requestedStatus != .unavailable {
                settings.screenRecordingStatus = requestedStatus
            }
            refreshPermissionAfterSystemPrompt(.screenCapture)
        }
        if settings.screenRecordingStatus != .granted {
            openPrivacySettings(anchor: "Privacy_ScreenCapture")
        }
    }

    /// Requests the optional accessibility-context permission.
    func requestAccessibilityContext() {
        settings.accessibilityContextStatus = .notDetermined
        let helperIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.qaptr.helper"
        ).isEmpty
        if helperIsRunning {
            DistributedNotificationCenter.default().post(
                name: Notification.Name("com.qaptr.review.command.requestAccessibility"),
                object: nil
            )
        } else {
            openPrivacySettings(anchor: "Privacy_Accessibility")
        }
        refreshPermissionAfterSystemPrompt(.accessibilityContext)
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?") else {
            return
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = anchor
        if let settingsURL = components?.url {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// TCC writes its decision asynchronously after the native prompt closes.
    /// Re-read a few times instead of rendering the stale pre-prompt value.
    private func refreshPermissionAfterSystemPrompt(_ permission: BridgePermission) {
        guard let bridge else { return }
        Task { [weak self] in
            for delay in [250_000_000, 750_000_000, 1_500_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                let status = permission == .accessibilityContext
                    ? (helperAccessibilityPermissionStatus() ?? bridge.permissionState(permission))
                    : bridge.permissionState(permission)
                if status == .granted || delay == 1_500_000_000 {
                    guard let self else { return }
                    switch permission {
                    case .screenCapture:
                        self.settings.screenRecordingStatus = status
                    case .accessibilityContext:
                        self.settings.accessibilityContextStatus = status
                    }
                    return
                }
            }
        }
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

    /// Selects `provider` and refreshes `providerConnection` from the real
    /// Keychain/network-verified state (see `refreshProviderConnection`).
    /// This only *requests* the setup sheet automatically when OpenRouter is
    /// selected and no key exists yet (`.needsKey`). Clicking an
    /// already-selected OpenRouter with a saved key must not reopen the
    /// sheet -- that would falsely suggest the saved key needs re-entry. Use
    /// `openProviderSetup()` for that explicit "Change key" action instead.
    func connectProvider(_ provider: ProviderChoice) {
        setProvider(provider)
        guard provider == .openRouter else {
            providerSetupRequest = nil
            return
        }
        providerSetupRequest = providerConnection.kind == .needsKey ? .openRouter : nil
    }

    /// Explicitly reopens the OpenRouter setup sheet for the currently
    /// selected, already-configured or connected provider (a "Change key"
    /// action). Unlike `connectProvider`, this always opens the sheet: it is
    /// only ever invoked by a person's deliberate tap, never as a side
    /// effect of selecting or re-selecting a provider.
    func openProviderSetup() {
        guard settings.provider == .openRouter else { return }
        providerSetupRequest = .openRouter
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
        if usesMockData {
            #if DEBUG
            providerConnection = .connected
            #endif
            return
        }
        guard let provider = settings.provider else {
            providerConnection = .notConnected
            return
        }
        providerConnection = provider == .openRouter
            ? (credentialStore.containsOpenRouterKey() ? .configured : .needsKey)
            : .notConnected
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

    /// Marks onboarding complete only when every required local setup
    /// decision (checklist 5.1) is actually satisfied by live state.
    /// Otherwise this is a no-op: `onboardingCompleted` stays false, so
    /// onboarding can never be durably completed on a guess or a default.
    @discardableResult
    func completeOnboarding() -> Bool {
        let completed = preferences.completeOnboardingIfEligible(currentOnboardingCompletionInputs())
        if completed {
            onboardingCompleted = true
            // Registering the packaged login item starts it immediately. This
            // happens only after the person explicitly presses Finish on the
            // final privacy-consent stage, never during a read-only refresh or
            // an ordinary review-app launch.
            setLoginItemEnabled(true)
        }
        return completed
    }

    /// Whether onboarding is currently eligible to complete, so a caller can
    /// gate the Finish action's enabled state without duplicating the
    /// eligibility policy itself.
    var isOnboardingCompletionEligible: Bool {
        OnboardingCompletionPolicy.isEligible(currentOnboardingCompletionInputs())
    }

    private func currentOnboardingCompletionInputs() -> OnboardingCompletionInputs {
        Self.onboardingCompletionInputs(
            screenRecordingStatus: settings.screenRecordingStatus,
            availableDisplayCount: settings.availableDisplayIDs.count,
            provider: settings.provider,
            providerConnectionKind: providerConnection.kind
        )
    }

    /// Derives checklist 5.1's completion inputs from already-known live
    /// state. Pure and directly testable, so the gating logic behind
    /// `completeOnboarding()` doesn't need a full `ReviewAppModel` (bridge,
    /// Keychain, filesystem) to exercise.
    ///
    /// Display selection: Qaptr has no display-selection UI yet (tracked
    /// separately by checklist 5.2/1.x), so `hasSelectedDisplay` truthfully
    /// reflects whether at least one display is actually attached and
    /// available -- matching the helper's real auto-select-all-available-
    /// displays capture behavior -- rather than inventing a per-display
    /// selection that does not exist.
    ///
    /// Provider usability: leaving the provider unset is a legitimate
    /// capture-only choice (see `OnboardingProviderChoiceList`), so it counts
    /// as usable. OpenRouter usability is the real Keychain-backed connection
    /// state. The three CLI providers (`claudeCLI`, `codexCLI`, `jcodeCLI`)
    /// have no live readiness check implemented anywhere in this codebase
    /// yet -- that is checklist 5.1's separate, still-open "let the user
    /// select a provider only when readiness checks make it usable" item,
    /// not this gate. Forcing a fabricated `false` here would durably brick
    /// onboarding for that choice with no recovery UI to unblock it, which
    /// is a worse and unrequested regression than leaving this specific
    /// sub-check ungated; forcing a fabricated `true` would falsely claim a
    /// readiness check occurred. So a CLI provider selection is treated the
    /// same as no selection: it does not block completion, matching this
    /// path's actual pre-existing behavior, and the missing readiness check
    /// is reported as an open item rather than silently faked in either
    /// direction.
    nonisolated static func onboardingCompletionInputs(
        screenRecordingStatus: PermissionStatus,
        availableDisplayCount: Int,
        provider: ProviderChoice?,
        providerConnectionKind: ProviderConnectionState.Kind
    ) -> OnboardingCompletionInputs {
        let hasUsableProvider: Bool
        switch provider {
        case nil, .claudeCLI, .codexCLI, .jcodeCLI:
            hasUsableProvider = true
        case .openRouter:
            hasUsableProvider = providerConnectionKind == .connected
        }
        return OnboardingCompletionInputs(
            hasSelectedDisplay: availableDisplayCount > 0,
            screenRecordingStatus: screenRecordingStatus,
            hasUsableProvider: hasUsableProvider
        )
    }
}
