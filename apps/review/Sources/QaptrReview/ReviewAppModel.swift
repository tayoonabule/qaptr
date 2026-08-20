import Foundation
import AppKit
import QaptrReviewCore
import Observation

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

private enum HelperCommand {
    static let requestScreenRecording = Notification.Name("com.qaptr.review.command.requestScreenRecording")
    static let requestAccessibility = Notification.Name("com.qaptr.review.command.requestAccessibility")
    static let startCapture = Notification.Name("com.qaptr.review.command.startCapture")
}

private enum HelperPermission {
    case screenRecording
    case accessibility

    var notification: Notification.Name {
        switch self {
        case .screenRecording: HelperCommand.requestScreenRecording
        case .accessibility: HelperCommand.requestAccessibility
        }
    }

    var privacyAnchor: String {
        switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
    }
}

/// The single observable source of truth driving every SwiftUI view.
///
/// This model reads durable history and local status through `ReviewBridge`,
/// manages settings, and starts the native review-session state machine only
/// after a person explicitly asks to analyze captured screenshots. Provider
/// dispatch remains blocked behind the session's separate just-in-time consent.
@MainActor
@Observable
final class ReviewAppModel {
    private(set) var snapshot: ReviewSnapshot = .empty
    private(set) var reviewStatus: ReviewStatus? = nil
    private(set) var captureProgress: CaptureProgressSnapshot = .unavailable
    private(set) var captureIntervalSeconds = CaptureIntervalPolicy.defaultSeconds
    private(set) var captureControlIntent: CaptureControlIntent = .running
    private(set) var loadError: String?
    private(set) var reviewStatusError: String? = nil
    private(set) var settings: SettingsState = .placeholder
    private(set) var providerConnection = ProviderConnectionState.notConnected
    private(set) var cliProviderReadiness: [String: ProviderReadiness] = [:]
    private(set) var analysisSessionState: ReviewSessionState = .idle
    private(set) var analysisError: String?
    var providerSetupRequest: ProviderChoice?
    var onboardingCompleted: Bool

    let preferences: SettingsPreferences
    private let usesMockData: Bool
    private let bridge: ReviewBridge?
    private let progressReader: CaptureProgressReader
    private let controlStore: CaptureControlStore
    private let credentialStore: any ProviderCredentialStoring
    private let openRouterChecker: any OpenRouterChecking
    private let cliProviderChecker: any CLIProviderChecking
    private let analysisSessionFactory: AnalysisSessionFactory?
    private var analysisSessionController: (any AnalysisSessionControlling)?
    private var analysisPollingTask: Task<Void, Never>?

    init(
        preferences: SettingsPreferences = SettingsPreferences(store: UserDefaults.standard),
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore(),
        openRouterChecker: any OpenRouterChecking = OpenRouterConnectionChecker(),
        progressReader: CaptureProgressReader? = nil,
        controlStore: CaptureControlStore? = nil,
        cliProviderChecker: (any CLIProviderChecking)? = nil,
        analysisSessionFactory: AnalysisSessionFactory? = nil,
        storePath: URL? = nil
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
        let storePath = storePath ?? defaultStorePath()
        self.progressReader = progressReader ?? CaptureProgressReader(url: defaultCaptureProgressPath())
        self.controlStore = controlStore ?? CaptureControlStore(url: defaultCaptureControlPath())
        let resolvedBridge: ReviewBridge?
        if usesMockData {
            resolvedBridge = nil
            self.loadError = nil
        } else {
            do {
                try FileManager.default.createDirectory(
                    at: storePath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                resolvedBridge = try ReviewBridge(storePath: storePath)
            } catch {
                resolvedBridge = nil
                self.loadError = String(describing: error)
            }
        }
        self.bridge = resolvedBridge
        self.cliProviderChecker = cliProviderChecker ?? NativeCLIProviderChecker(bridge: resolvedBridge)
        if let analysisSessionFactory {
            self.analysisSessionFactory = analysisSessionFactory
        } else if let resolvedBridge {
            self.analysisSessionFactory = { providerID in
                NativeAnalysisSessionController(
                    session: try resolvedBridge.makeReviewSession(providerID: providerID)
                )
            }
        } else {
            self.analysisSessionFactory = nil
        }
        refreshCaptureProgress()
        refreshSettings()
        rebindLoginItemForCurrentBuildIfNeeded()
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

    /// Starts a provider-immutable native review session over the committed
    /// capture bundles. This does not grant provider consent: local preparation
    /// runs first and the UI must separately answer the emitted consent request.
    func startAnalysis() {
        guard analysisSessionState.allowedOperations.contains("start") else { return }
        guard let provider = settings.provider, provider != .openRouter else {
            analysisError = "Choose and connect a local CLI provider in Settings."
            return
        }
        guard providerConnection == .connected else {
            analysisError = "Reconnect the selected CLI provider in Settings before analyzing."
            return
        }
        guard let analysisSessionFactory else {
            analysisError = "Live analysis is not available in this build."
            return
        }
        do {
            let controller = try analysisSessionFactory(provider.rawValue)
            analysisSessionController = controller
            analysisError = nil
            applyAnalysisState(try controller.start(sessionID: UUID().uuidString.lowercased()))
            beginAnalysisPolling()
        } catch {
            analysisError = analysisMessage(for: error)
        }
    }

    /// Answers the exact pending just-in-time consent request. Declining keeps
    /// all preparation local and prevents the provider adapter from being invoked.
    func decideAnalysisConsent(granted: Bool) {
        guard analysisSessionState.phase == .readyForConsent,
              let analysisSessionController
        else { return }
        do {
            analysisError = nil
            applyAnalysisState(try analysisSessionController.decideConsent(granted: granted))
            beginAnalysisPolling()
        } catch {
            analysisError = analysisMessage(for: error)
        }
    }

    func cancelAnalysis() {
        guard analysisSessionState.allowedOperations.contains("cancel"),
              let analysisSessionController
        else { return }
        do {
            applyAnalysisState(try analysisSessionController.cancel())
            beginAnalysisPolling()
        } catch {
            analysisError = analysisMessage(for: error)
        }
    }

    func retryAnalysis() {
        guard analysisSessionState.allowedOperations.contains("retry"),
              let analysisSessionController
        else {
            startAnalysis()
            return
        }
        do {
            analysisError = nil
            applyAnalysisState(try analysisSessionController.retry())
            beginAnalysisPolling()
        } catch {
            analysisError = analysisMessage(for: error)
        }
    }

    var analysisCanStart: Bool {
        guard let provider = settings.provider else { return false }
        return provider != .openRouter
            && providerConnection == .connected
            && analysisSessionState.allowedOperations.contains("start")
    }

    private func beginAnalysisPolling() {
        analysisPollingTask?.cancel()
        let controller = analysisSessionController
        analysisPollingTask = Task { [weak self] in
            guard let self, let controller else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let state = try controller.state()
                    self.applyAnalysisState(state)
                    if state.phase == .readyForConsent || state.isTerminal { return }
                } catch {
                    self.analysisError = self.analysisMessage(for: error)
                    return
                }
            }
        }
    }

    private func applyAnalysisState(_ state: ReviewSessionState) {
        analysisSessionState = state
        if state.isTerminal {
            refresh()
        }
    }

    private func analysisMessage(for error: Error) -> String {
        let description = String(describing: error)
        if description.contains("no_committed_bundles") {
            return "No captured screenshots are ready to analyze yet."
        }
        if description.contains("provider_unavailable") {
            return "The selected CLI provider could not be verified. Reconnect it in Settings."
        }
        return description
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
            captureControlIntent = DevMockData.captureProgress.state == .paused ? .paused : .running
            settings.intervalSeconds = captureIntervalSeconds
            #endif
            return
        }
        captureProgress = (try? progressReader.read()) ?? .unavailable
        let control = (try? controlStore.read()) ?? .default
        captureControlIntent = control.intent
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
            let control = try CaptureControl(intervalSeconds: normalized, intent: captureControlIntent)
            try controlStore.write(control)
            captureIntervalSeconds = normalized
            settings.intervalSeconds = normalized
        } catch {
            // Keep the previous value when the control could not be persisted.
        }
    }

    /// Requests that the helper stop starting new capture ticks. The helper
    /// acknowledges the request by persisting `.paused` progress on its next
    /// control-file poll.
    func pauseCapture() {
        setCaptureControlIntent(.paused)
    }

    /// Requests that the helper prepare and resume capture from a clean tick
    /// schedule while preserving the selected interval.
    func resumeCapture() {
        setCaptureControlIntent(.running)
    }

    private func setCaptureControlIntent(_ intent: CaptureControlIntent) {
        guard intent != captureControlIntent else { return }
        do {
            let control = try CaptureControl(intervalSeconds: captureIntervalSeconds, intent: intent)
            try controlStore.write(control)
            captureControlIntent = intent
        } catch {
            // Keep the previous intent when the control could not be persisted.
        }
    }

    /// Reloads permission and login-item status without prompting.
    func refreshSettings() {
        refreshCaptureProgress()
        var next = settings
        next.intervalSeconds = captureIntervalSeconds
        next.availableDisplayIDs = DisplayEnumerator.currentDisplays().map(\.id)
        next.cacheLifetime = preferences.cacheLifetime
        next.provider = preferences.provider
        next.excludedApplications = preferences.excludedApplications
        next.excludedWindowTitles = preferences.excludedWindowTitles
        if let permissionSnapshot = currentHelperPermissionSnapshot() {
            next.screenRecordingStatus = permissionSnapshot.screenRecordingStatus
            next.accessibilityContextStatus = permissionSnapshot.accessibilityStatus
        } else {
            next.screenRecordingStatus = .notDetermined
            next.accessibilityContextStatus = .notDetermined
        }
        if let bridge {
            next.loginItemEnabled = bridge.loginItemEnabled()
        }
        settings = next
        if onboardingCompleted {
            if let provider = settings.provider, provider != .openRouter {
                if providerConnection == .notConnected {
                    verifyCLIProvider(provider)
                }
            } else {
                refreshProviderConnection()
            }
        } else {
            providerConnection = .notConnected
        }
        refreshCliProviderReadiness()
    }

    /// Refreshes only live local permission/display state. Onboarding polls this
    /// lightweight path while a macOS consent panel is open, without repeatedly
    /// checking providers or touching the network.
    func refreshPermissions() {
        var next = settings
        next.availableDisplayIDs = DisplayEnumerator.currentDisplays().map(\.id)
        if let permissionSnapshot = currentHelperPermissionSnapshot() {
            next.screenRecordingStatus = permissionSnapshot.screenRecordingStatus
            next.accessibilityContextStatus = permissionSnapshot.accessibilityStatus
        } else {
            next.screenRecordingStatus = .notDetermined
            next.accessibilityContextStatus = .notDetermined
        }
        if let bridge {
            next.loginItemEnabled = bridge.loginItemEnabled()
        }
        settings = next
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
    /// Reading OpenRouter's Keychain item is intentionally deferred until the
    /// person selects OpenRouter, so merely opening onboarding or Settings can
    /// never trigger a system password prompt.
    private func connectionState(for provider: ProviderChoice) -> ProviderConnectionState {
        _ = provider
        return .notConnected
    }

    /// Requests Screen Recording from the helper process that actually captures.
    func requestScreenRecording() {
        if settings.screenRecordingStatus == .denied {
            openPrivacySettings(anchor: HelperPermission.screenRecording.privacyAnchor)
            return
        }
        settings.screenRecordingStatus = .notDetermined
        requestHelperPermission(.screenRecording)
    }

    /// Requests Accessibility from the helper process that reads app/window names.
    func requestAccessibilityContext() {
        if settings.accessibilityContextStatus == .denied {
            openPrivacySettings(anchor: HelperPermission.accessibility.privacyAnchor)
            return
        }
        settings.accessibilityContextStatus = .notDetermined
        requestHelperPermission(.accessibility)
    }

    private func requestHelperPermission(_ permission: HelperPermission) {
        guard let helperURL = helperApplicationURL() else {
            setPermissionStatus(.unavailable, for: permission)
            return
        }

        if let snapshot = currentHelperPermissionSnapshot() {
            post(permission.notification, commandToken: snapshot.commandToken)
            refreshPermissionAfterSystemPrompt(permission)
            return
        }

        // A same-ID process without a current, path-bound v2 heartbeat is an
        // obsolete or wrong helper. Stop it before launching the exact nested
        // helper from this review bundle so it cannot hold the global lock or
        // swallow permission commands during an upgrade.
        for application in Self.runningHelperApplications {
            application.terminate()
        }

        Task { [weak self] in
            for _ in 0..<20 where !Self.runningHelperApplications.isEmpty {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            for application in Self.runningHelperApplications {
                application.forceTerminate()
            }
            for _ in 0..<10 where !Self.runningHelperApplications.isEmpty {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            self?.launchHelper(at: helperURL, requesting: permission)
        }
    }

    private func launchHelper(at helperURL: URL, requesting permission: HelperPermission) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--permission-only", "true"]
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil else {
                    self.setPermissionStatus(.unavailable, for: permission)
                    return
                }
                self.sendPermissionCommandWhenReady(permission)
            }
        }
    }

    private func sendPermissionCommandWhenReady(_ permission: HelperPermission) {
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                if let snapshot = self.currentHelperPermissionSnapshot() {
                    self.post(permission.notification, commandToken: snapshot.commandToken)
                    self.refreshPermissionAfterSystemPrompt(permission)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            self.setPermissionStatus(.unavailable, for: permission)
        }
    }

    private static var runningHelperApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.qaptr.helper")
    }

    private func helperApplicationURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["QAPTR_HELPER_APP_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let nested = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent("QaptrHelper.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.path) { return nested }
        return nil
    }

    private func currentHelperPermissionSnapshot() -> HelperPermissionSnapshot? {
        guard let helperURL = helperApplicationURL() else { return nil }
        return liveHelperPermissionSnapshot(expectedHelperBundleURL: helperURL)
    }

    private func post(_ notification: Notification.Name, commandToken: String) {
        DistributedNotificationCenter.default().post(name: notification, object: commandToken)
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

    /// The helper publishes every second. Poll long enough for a person to read
    /// and answer the macOS prompt instead of sampling three arbitrary moments.
    private func refreshPermissionAfterSystemPrompt(_ permission: HelperPermission) {
        Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                self.refreshPermissions()
                if self.permissionStatus(for: permission) == .granted { return }
            }
        }
    }

    private func permissionStatus(for permission: HelperPermission) -> PermissionStatus {
        switch permission {
        case .screenRecording: settings.screenRecordingStatus
        case .accessibility: settings.accessibilityContextStatus
        }
    }

    private func setPermissionStatus(_ status: PermissionStatus, for permission: HelperPermission) {
        switch permission {
        case .screenRecording: settings.screenRecordingStatus = status
        case .accessibility: settings.accessibilityContextStatus = status
        }
    }

    /// Sets whether Qaptr starts at login.
    func setLoginItemEnabled(_ enabled: Bool) {
        guard let bridge else { return }
        settings.loginItemEnabled = bridge.setLoginItemEnabled(enabled)
    }

    /// Re-registers once per packaged build so an upgrade cannot leave
    /// SMAppService pointing at a removed copy such as `~/Applications/Qaptr.app`.
    private func rebindLoginItemForCurrentBuildIfNeeded() {
        guard onboardingCompleted,
              Bundle.main.bundleIdentifier == "com.qaptr.review",
              let bridge,
              let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return
        }

        let markerKey = "com.qaptr.review.login-item-bound-build"
        let marker = "\(shortVersion)(\(buildVersion))"
        guard UserDefaults.standard.string(forKey: markerKey) != marker else { return }

        let enabled = bridge.setLoginItemEnabled(true)
        settings.loginItemEnabled = enabled
        if enabled {
            UserDefaults.standard.set(marker, forKey: markerKey)
        }
    }

    func setCacheLifetime(_ lifetime: CacheLifetime) {
        preferences.cacheLifetime = lifetime
        settings.cacheLifetime = lifetime
    }

    func setProvider(_ provider: ProviderChoice) {
        if settings.provider != provider {
            resetAnalysisSessionForProviderChange()
        }
        preferences.provider = provider
        settings.provider = provider
        if provider == .openRouter {
            refreshProviderConnection()
        } else {
            providerConnection = .notConnected
        }
    }

    /// Removes the provider preference without triggering a provider request.
    func clearProvider() {
        resetAnalysisSessionForProviderChange()
        preferences.provider = nil
        settings.provider = nil
        providerSetupRequest = nil
        providerConnection = .notConnected
    }

    private func resetAnalysisSessionForProviderChange() {
        analysisPollingTask?.cancel()
        if analysisSessionState.allowedOperations.contains("cancel") {
            _ = try? analysisSessionController?.cancel()
        }
        analysisSessionController = nil
        analysisSessionState = .idle
        analysisError = nil
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
            verifyCLIProvider(provider)
            return
        }
        providerSetupRequest = providerConnection.kind == .needsKey ? .openRouter : nil
    }

    private func verifyCLIProvider(_ provider: ProviderChoice) {
        guard provider != .openRouter else { return }
        providerConnection = .checking
        let checker = cliProviderChecker
        Task { [weak self] in
            let result = await checker.check(providerID: provider.rawValue)
            await MainActor.run {
                guard let self, self.settings.provider == provider else { return }
                switch result {
                case .connected:
                    self.providerConnection = .connected
                case .failed(let failure):
                    self.providerConnection = .failed(.cli(failure))
                }
            }
        }
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
            if let snapshot = currentHelperPermissionSnapshot() {
                post(HelperCommand.startCapture, commandToken: snapshot.commandToken)
            }
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
    /// as usable. Every selected provider, including a local CLI, must have
    /// completed its real connection check before onboarding can finish.
    nonisolated static func onboardingCompletionInputs(
        screenRecordingStatus: PermissionStatus,
        availableDisplayCount: Int,
        provider: ProviderChoice?,
        providerConnectionKind: ProviderConnectionState.Kind
    ) -> OnboardingCompletionInputs {
        let hasUsableProvider: Bool
        switch provider {
        case nil:
            hasUsableProvider = true
        case .openRouter, .claudeCLI, .codexCLI, .jcodeCLI:
            hasUsableProvider = providerConnectionKind == .connected
        }
        return OnboardingCompletionInputs(
            hasSelectedDisplay: availableDisplayCount > 0,
            screenRecordingStatus: screenRecordingStatus,
            hasUsableProvider: hasUsableProvider
        )
    }
}
