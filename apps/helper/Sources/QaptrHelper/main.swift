import AppKit
import ApplicationServices
import Foundation
import QaptrHelperCore

private struct Options {
    let interval: CaptureInterval
    let maxDimension: Int
    let maximumCycles: Int?
    let vaultRoot: URL
    let generationID: String
    let fixtureManifest: URL?
    let fixtureImageRoot: URL?
    let permissionOnly: Bool

    static func parse(_ arguments: ArraySlice<String>) throws -> Self {
        var intervalSeconds = CaptureInterval.defaultSeconds
        var maxDimension = 1_920
        var maximumCycles: Int?
        var vaultRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr/vault", isDirectory: true)
        var generationID = "generation-1"
        var fixtureManifest: URL?
        var fixtureImageRoot: URL?
        var permissionOnly = false
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            index = arguments.index(after: index)
            guard index < arguments.endIndex else {
                throw HelperError.invalidArgument("missing value for \(argument)")
            }
            let value = arguments[index]
            index = arguments.index(after: index)
            switch argument {
            case "--interval-seconds":
                guard let parsed = Int(value),
                      (try? CaptureInterval(seconds: parsed)) != nil else {
                    throw HelperError.invalidArgument("invalid interval \(value)")
                }
                intervalSeconds = parsed
            case "--max-dimension":
                guard let parsed = Int(value), parsed > 0 else {
                    throw HelperError.invalidArgument("invalid max dimension \(value)")
                }
                maxDimension = parsed
            case "--cycles":
                guard let parsed = Int(value), parsed > 0 else {
                    throw HelperError.invalidArgument("invalid cycles \(value)")
                }
                maximumCycles = parsed
            case "--vault-root":
                vaultRoot = URL(fileURLWithPath: value, isDirectory: true)
            case "--generation-id":
                guard !value.isEmpty else {
                    throw HelperError.invalidArgument("empty generation id")
                }
                generationID = value
            case "--fixture-manifest":
                fixtureManifest = URL(fileURLWithPath: value)
            case "--fixture-image-root":
                fixtureImageRoot = URL(fileURLWithPath: value, isDirectory: true)
            case "--permission-only":
                guard let parsed = Bool(value) else {
                    throw HelperError.invalidArgument("invalid permission-only value \(value)")
                }
                permissionOnly = parsed
            default:
                throw HelperError.invalidArgument("unknown argument \(argument)")
            }
        }
        guard fixtureManifest == nil || fixtureImageRoot != nil else {
            throw HelperError.invalidArgument("--fixture-manifest requires --fixture-image-root")
        }
        return try Self(
            interval: CaptureInterval(seconds: intervalSeconds),
            maxDimension: maxDimension,
            maximumCycles: maximumCycles,
            vaultRoot: vaultRoot,
            generationID: generationID,
            fixtureManifest: fixtureManifest,
            fixtureImageRoot: fixtureImageRoot,
            permissionOnly: permissionOnly
        )
    }
}

private enum ReviewCommandNotification {
    static let openSettings = Notification.Name("com.qaptr.review.command.openSettings")
    static let showObservations = Notification.Name("com.qaptr.review.command.showObservations")
    static let showDetailedSummary = Notification.Name("com.qaptr.review.command.showDetailedSummary")
    static let requestScreenRecording = Notification.Name("com.qaptr.review.command.requestScreenRecording")
    static let requestAccessibility = Notification.Name("com.qaptr.review.command.requestAccessibility")
    static let startCapture = Notification.Name("com.qaptr.review.command.startCapture")
    static let startDetailedCapture = Notification.Name("com.qaptr.review.command.startDetailedCapture")
    static let stopDetailedCapture = Notification.Name("com.qaptr.review.command.stopDetailedCapture")
}

private enum HelperMenuState: Equatable {
    case normal(status: String, paused: Bool, captureCount: Int)
    case detailed(remainingSeconds: Int, detailedCount: Int, generalCount: Int)
    case analysisInProgress(phase: ReviewActivitySnapshot.Phase, captureCount: Int, message: String?)
    case analysisAvailable(captureCount: Int)
    case recovery(message: String, captureCount: Int)
}

private struct AnalysisMenuPresentation {
    let title: String
    let subtitle: String
    let symbolName: String

    init(phase: ReviewActivitySnapshot.Phase) {
        switch phase {
        case .preparing:
            title = "Preparing local review"
            subtitle = "Protecting captures on this Mac"
            symbolName = "lock.shield"
        case .waitingForConsent:
            title = "Approval ready"
            subtitle = "Review the privacy boundary in Qaptr"
            symbolName = "checkmark.shield"
        case .analyzing:
            title = "Qaptr is analyzing"
            subtitle = "The approved context is being reviewed"
            symbolName = "sparkles"
        case .resultReady:
            title = "Analysis available"
            subtitle = "Your capture summary is ready"
            symbolName = "sparkles"
        case .failed:
            title = "Analysis needs attention"
            subtitle = "The last analysis could not finish"
            symbolName = "exclamationmark.triangle"
        }
    }
}

private struct DetailedCaptureSession: Codable, Equatable {
    static let schemaVersion = 1

    let version: Int
    let sessionID: String
    let startedAtMillis: Int64
    let endsAtMillis: Int64
    let normalIntervalSeconds: Int
    let detailedIntervalSeconds: Int
    let baselineCaptureCount: Int

    init(
        sessionID: String,
        startedAtMillis: Int64,
        endsAtMillis: Int64,
        normalIntervalSeconds: Int,
        detailedIntervalSeconds: Int,
        baselineCaptureCount: Int
    ) {
        self.version = Self.schemaVersion
        self.sessionID = sessionID
        self.startedAtMillis = startedAtMillis
        self.endsAtMillis = endsAtMillis
        self.normalIntervalSeconds = normalIntervalSeconds
        self.detailedIntervalSeconds = detailedIntervalSeconds
        self.baselineCaptureCount = max(0, baselineCaptureCount)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sessionID = "session_id"
        case startedAtMillis = "started_at_ms"
        case endsAtMillis = "ends_at_ms"
        case normalIntervalSeconds = "normal_interval_seconds"
        case detailedIntervalSeconds = "detailed_interval_seconds"
        case baselineCaptureCount = "baseline_capture_count"
    }
}

private struct DetailedCaptureSummary: Codable, Equatable {
    let version: Int
    let sessionID: String
    let startedAtMillis: Int64
    let endedAtMillis: Int64
    let normalIntervalSeconds: Int
    let detailedIntervalSeconds: Int
    let detailedCaptureCount: Int
    let stopReason: String

    init(session: DetailedCaptureSession, endedAtMillis: Int64, detailedCaptureCount: Int, stopReason: String) {
        self.version = 1
        self.sessionID = session.sessionID
        self.startedAtMillis = session.startedAtMillis
        self.endedAtMillis = endedAtMillis
        self.normalIntervalSeconds = session.normalIntervalSeconds
        self.detailedIntervalSeconds = session.detailedIntervalSeconds
        self.detailedCaptureCount = max(0, detailedCaptureCount)
        self.stopReason = stopReason
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sessionID = "session_id"
        case startedAtMillis = "started_at_ms"
        case endedAtMillis = "ended_at_ms"
        case normalIntervalSeconds = "normal_interval_seconds"
        case detailedIntervalSeconds = "detailed_interval_seconds"
        case detailedCaptureCount = "detailed_capture_count"
        case stopReason = "stop_reason"
    }
}

private struct ReviewActivitySnapshot: Decodable {
    enum Phase: String, Decodable, Equatable {
        case preparing
        case waitingForConsent = "waiting_for_consent"
        case analyzing
        case resultReady = "result_ready"
        case failed
    }

    let phase: Phase
    let updatedAtMillis: Int64
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case phase
        case updatedAtMillis = "updated_at_ms"
        case message
    }
}

@MainActor
private final class HelperApplication: NSObject, NSApplicationDelegate {
    private let options: Options
    private let instanceLock: SingleInstanceLock
    private let capture = ScreenCaptureAdapter()
    private let startupCoordinator: CaptureStartupCoordinator
    private let context = PointInTimeContextSampler()
    private let coordinator: CaptureCoordinator
    private let progressStore: CaptureProgressStore
    private let controlStore: CaptureControlStore
    private let permissionStore: HelperPermissionSnapshotStore
    private let commandToken = UUID().uuidString
    private let permissionDefaults = UserDefaults.standard
    private var progressTracker: CaptureProgressTracker
    private var planner: TickPlanner
    private var activeInterval: CaptureInterval
    private var selectedDisplayIDs = Set<String>()
    private var cycle = 0
    private var timer: DispatchSourceTimer?
    private var captureEnabled: Bool
    private var captureIntent: CaptureControlIntent
    private var capturePrepared = false
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var detailedSession: DetailedCaptureSession?
    private var presentedMenuState: HelperMenuState?

    init(options: Options, instanceLock: SingleInstanceLock, sealer: BundleSealer) {
        self.options = options
        self.instanceLock = instanceLock
        self.startupCoordinator = CaptureStartupCoordinator(preflight: ScreenCaptureAdapter())
        self.coordinator = CaptureCoordinator(capture: capture, sealer: sealer)
        let progressStore = CaptureProgressStore(url: Self.captureProgressURL())
        self.progressStore = progressStore
        let controlStore = CaptureControlStore(url: Self.captureControlURL())
        self.controlStore = controlStore
        self.permissionStore = HelperPermissionSnapshotStore(url: Self.permissionStatusURL())
        self.progressTracker = CaptureProgressTracker(initial: (try? progressStore.read()) ?? .initial)
        let persistedControl = (try? controlStore.read())
            ?? (try? CaptureControl(intervalSeconds: options.interval.seconds))
            ?? .default
        self.activeInterval = (try? CaptureInterval(seconds: persistedControl.intervalSeconds)) ?? options.interval
        self.planner = TickPlanner(interval: self.activeInterval)
        self.captureEnabled = !options.permissionOnly
            && Self.finalConsentGranted
            && persistedControl.intent == .running
        self.captureIntent = .running
        super.init()
        self.detailedSession = Self.readDetailedSession()
        // Canonicalize missing or corrupt control data without discarding the
        // persisted lifecycle intent.
        try? controlStore.write(persistedControl)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(requestScreenRecordingPermission(_:)),
            name: ReviewCommandNotification.requestScreenRecording,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(requestAccessibilityPermission(_:)),
            name: ReviewCommandNotification.requestAccessibility,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(startCapture(_:)),
            name: ReviewCommandNotification.startCapture,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(startDetailedCaptureCommand(_:)),
            name: ReviewCommandNotification.startDetailedCapture,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(stopDetailedCaptureCommand(_:)),
            name: ReviewCommandNotification.stopDetailedCapture,
            object: nil
        )
        syncControl(at: Self.currentTimestamp())
        if options.permissionOnly, !capture.screenRecordingAccessGranted() {
            permissionDefaults.set(true, forKey: Self.screenRecordingRequestedKey)
            // macOS does not register a nested LSUIElement login item in the
            // Screen Recording list reliably. Temporarily present the helper
            // as a regular app while it makes its process-scoped request, then
            // return to the accessory policy used during normal capture.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            _ = capture.requestScreenRecordingAccess()
            NSApp.setActivationPolicy(.accessory)
        }
        writePermissionStatus()
        configureStatusItem()
        refreshMenu()
        prepareCaptureIfNeeded()
        scheduleTimer()
    }

    private func prepareCaptureIfNeeded() {
        guard captureEnabled, !capturePrepared else { return }
        capturePrepared = true
        let timestamp = Self.currentTimestamp()
        let startupResult = startupCoordinator.prepare(
            progressTracker: &progressTracker,
            progressStore: progressStore,
            at: timestamp,
            processID: Int64(ProcessInfo.processInfo.processIdentifier),
            activeIntervalSeconds: activeInterval.seconds
        )
        switch startupResult {
        case let .ready(displayIDs):
            selectedDisplayIDs = Set(displayIDs)
            print("event=start pid=\(ProcessInfo.processInfo.processIdentifier) displays=\(displayIDs.joined(separator: ",")) interval_seconds=\(activeInterval.seconds)")
        case .permissionRequired:
            print("event=skip reason=screen_recording_permission")
        case .noDisplays:
            print("event=skip reason=no_displays")
        case let .startupFailed(reason):
            print("event=skip reason=startup_failed error=\(reason)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.cancel()
        timer = nil
        if let detailedSession {
            writeDetailedSummary(
                for: detailedSession,
                endedAtMillis: Self.currentTimestamp(),
                detailedCaptureCount: detailedCaptureCount(for: detailedSession),
                stopReason: "helper-terminated"
            )
            removeDetailedSession()
        }
        if captureIntent == .paused {
            progressTracker.pause(
                at: Self.currentTimestamp(),
                selectedDisplayIDs: Array(selectedDisplayIDs),
                activeIntervalSeconds: activeInterval.seconds
            )
        } else {
            progressTracker.stop(
                at: Self.currentTimestamp(),
                selectedDisplayIDs: Array(selectedDisplayIDs),
                activeIntervalSeconds: activeInterval.seconds
            )
        }
        persistProgress()
    }

    private func configureStatusItem() {
        statusItem.button?.toolTip = "Qaptr capture helper"
        statusItem.button?.setAccessibilityTitle("Qaptr capture helper")
        refreshMenu(force: true)
    }

    private func refreshMenu(force: Bool = false) {
        let state = menuState(at: Self.currentTimestamp())
        guard force || state != presentedMenuState else { return }
        presentedMenuState = state

        let menu = NSMenu()
        menu.autoenablesItems = false
        switch state {
        case let .normal(status, paused, captureCount):
            configureStatusItemButton(symbolName: paused ? "pause.circle" : "circle.fill", title: "Normal capture")
            addHeader("Normal capture", subtitle: status, to: menu)
            addItem(
                title: paused ? "Resume Capture" : "Pause Capture",
                action: #selector(toggleCapture(_:)),
                keyEquivalent: "p",
                to: menu
            )
            addItem(
                title: "Start Detailed Capture…",
                action: #selector(startDetailedCapture(_:)),
                to: menu
            )
            addItem(title: "General captures: \(captureCount)", enabled: false, to: menu)
            addSeparator(to: menu)
            addCommonActions(to: menu)
        case let .detailed(remainingSeconds, detailedCount, generalCount):
            configureStatusItemButton(symbolName: "scope", title: "Detailed capture")
            addHeader(
                "Detailed capture",
                subtitle: "\(formatDuration(remainingSeconds)) remaining",
                to: menu
            )
            addItem(title: "Detailed captures: \(detailedCount)", enabled: false, to: menu)
            addItem(title: "General captures: \(generalCount)", enabled: false, to: menu)
            addSeparator(to: menu)
            addItem(
                title: "Stop Detailed Capture and Review",
                action: #selector(stopDetailedCaptureAndReview(_:)),
                to: menu
            )
            addItem(
                title: "Return to Normal Capture",
                action: #selector(returnToNormalCapture(_:)),
                to: menu
            )
            addSeparator(to: menu)
            addCommonActions(to: menu)
        case let .analysisInProgress(phase, captureCount, message):
            let presentation = AnalysisMenuPresentation(phase: phase)
            configureStatusItemButton(symbolName: presentation.symbolName, title: presentation.title)
            addHeader(presentation.title, subtitle: message ?? presentation.subtitle, to: menu)
            addItem(title: "General captures: \(captureCount)", enabled: false, to: menu)
            if phase == .waitingForConsent {
                addItem(title: "Open Qaptr to review approval", action: #selector(showQaptr(_:)), keyEquivalent: "1", to: menu)
            } else {
                addItem(title: "Open Qaptr", action: #selector(showQaptr(_:)), keyEquivalent: "1", to: menu)
            }
            addSeparator(to: menu)
            addCommonActions(to: menu, includeShow: false)
        case let .analysisAvailable(captureCount):
            configureStatusItemButton(symbolName: "sparkles", title: "Analysis available")
            addHeader("Analysis available", subtitle: "Your capture summary is ready", to: menu)
            addItem(title: "General captures: \(captureCount)", enabled: false, to: menu)
            addItem(title: "Open Qaptr", action: #selector(showQaptr(_:)), keyEquivalent: "1", to: menu)
            addSeparator(to: menu)
            addCommonActions(to: menu, includeShow: false)
        case let .recovery(message, captureCount):
            configureStatusItemButton(symbolName: "exclamationmark.triangle", title: "Qaptr needs attention")
            addHeader("Qaptr needs attention", subtitle: message, to: menu)
            addItem(title: "General captures: \(captureCount)", enabled: false, to: menu)
            addItem(
                title: "Retry Capture",
                action: #selector(retryCapture(_:)),
                to: menu
            )
            addSeparator(to: menu)
            addCommonActions(to: menu)
        }
        statusItem.menu = menu
    }

    private func configureStatusItemButton(symbolName: String, title: String) {
        let button = statusItem.button
        button?.title = ""
        button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button?.image?.isTemplate = true
        button?.toolTip = title
        button?.setAccessibilityTitle(title)
    }

    private func addHeader(_ title: String, subtitle: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: "\(title)\n\(subtitle)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        item.setAccessibilityLabel("\(title). \(subtitle)")
        menu.addItem(item)
    }

    private func addItem(
        title: String,
        action: Selector? = nil,
        keyEquivalent: String = "",
        enabled: Bool = true,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action == nil ? nil : self
        item.isEnabled = enabled
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = [.command]
        }
        item.setAccessibilityLabel(title)
        menu.addItem(item)
    }

    private func addSeparator(to menu: NSMenu) {
        menu.addItem(.separator())
    }

    private func addCommonActions(to menu: NSMenu, includeShow: Bool = true) {
        if includeShow {
            addItem(title: "Open Qaptr", action: #selector(showQaptr(_:)), keyEquivalent: "1", to: menu)
        }
        addItem(title: "Open Settings", action: #selector(openReviewSettings(_:)), keyEquivalent: ",", to: menu)
        addItem(title: "Quit Qaptr Helper", action: #selector(quit(_:)), keyEquivalent: "q", to: menu)
    }

    @objc private func showQaptr(_ sender: Any?) {
        _ = sender
        openReviewApp(requestSettings: false)
    }

    @objc private func toggleCapture(_ sender: Any?) {
        _ = sender
        let intent: CaptureControlIntent = captureIntent == .running ? .paused : .running
        writeControl(intervalSeconds: activeInterval.seconds, intent: intent)
        syncControl(at: Self.currentTimestamp())
        refreshMenu(force: true)
    }

    @objc private func startDetailedCapture(_ sender: Any?) {
        _ = sender
        guard detailedSession == nil else { return }
        guard captureIntent == .running, Self.finalConsentGranted else {
            refreshMenu(force: true)
            return
        }

        let now = Self.currentTimestamp()
        let detailedInterval = Self.validInterval(
            permissionDefaults.integer(forKey: Self.detailedIntervalKey),
            fallback: 5
        )
        let durationSeconds = max(
            30,
            permissionDefaults.integer(forKey: Self.detailedDurationKey) == 0
                ? 300
                : permissionDefaults.integer(forKey: Self.detailedDurationKey)
        )
        let session = DetailedCaptureSession(
            sessionID: UUID().uuidString,
            startedAtMillis: now,
            endsAtMillis: now + Int64(durationSeconds) * 1_000,
            normalIntervalSeconds: activeInterval.seconds,
            detailedIntervalSeconds: detailedInterval,
            baselineCaptureCount: progressTracker.progress.captureCount
        )
        guard writeDetailedSession(session) else {
            print("event=detailed_capture_failed reason=session_persistence")
            return
        }
        detailedSession = session
        guard writeControl(intervalSeconds: detailedInterval, intent: .running) else {
            detailedSession = nil
            removeDetailedSession()
            refreshMenu(force: true)
            return
        }
        syncControl(at: now)
        refreshMenu(force: true)
    }

    @objc private func stopDetailedCaptureAndReview(_ sender: Any?) {
        _ = sender
        finishDetailedCapture(stopReason: "manual-stop", resumeNormalCapture: false)
    }

    @objc private func returnToNormalCapture(_ sender: Any?) {
        _ = sender
        finishDetailedCapture(stopReason: "returned-to-normal", resumeNormalCapture: true)
    }

    @objc private func retryCapture(_ sender: Any?) {
        _ = sender
        if !capture.screenRecordingAccessGranted() {
            permissionDefaults.set(true, forKey: Self.screenRecordingRequestedKey)
            _ = capture.requestScreenRecordingAccess()
        }
        captureEnabled = captureIntent == .running && Self.finalConsentGranted
        capturePrepared = false
        prepareCaptureIfNeeded()
        refreshMenu(force: true)
    }

    @objc private func openReviewSettings(_ sender: Any?) {
        _ = sender
        openReviewApp(requestSettings: true)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func finishDetailedCapture(stopReason: String, resumeNormalCapture: Bool) {
        guard let session = detailedSession else { return }
        let now = Self.currentTimestamp()
        let count = detailedCaptureCount(for: session)
        writeDetailedSummary(
            for: session,
            endedAtMillis: now,
            detailedCaptureCount: count,
            stopReason: stopReason
        )
        guard writeControl(
            intervalSeconds: session.normalIntervalSeconds,
            intent: resumeNormalCapture ? .running : .paused
        ) else {
            refreshMenu(force: true)
            return
        }
        detailedSession = nil
        removeDetailedSession()
        syncControl(at: now)
        refreshMenu(force: true)
        openDetailedSummary(sessionID: session.sessionID)
    }

    @objc private func requestAccessibilityPermission(_ notification: Notification) {
        guard accepts(notification) else { return }
        permissionDefaults.set(true, forKey: Self.accessibilityRequestedKey)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        writePermissionStatus()
    }

    @objc private func requestScreenRecordingPermission(_ notification: Notification) {
        guard accepts(notification) else { return }
        permissionDefaults.set(true, forKey: Self.screenRecordingRequestedKey)
        _ = capture.requestScreenRecordingAccess()
        writePermissionStatus()
    }

    @objc private func startCapture(_ notification: Notification) {
        guard accepts(notification), Self.finalConsentGranted else { return }
        captureEnabled = captureIntent == .running
        prepareCaptureIfNeeded()
    }

    @objc private func startDetailedCaptureCommand(_ notification: Notification) {
        guard accepts(notification), Self.finalConsentGranted else { return }
        startDetailedCapture(nil)
    }

    @objc private func stopDetailedCaptureCommand(_ notification: Notification) {
        guard accepts(notification) else { return }
        finishDetailedCapture(stopReason: "review-request", resumeNormalCapture: true)
    }

    private func accepts(_ notification: Notification) -> Bool {
        notification.object as? String == commandToken
    }

    /// The helper is an accessory app, so these shortcuts are available while
    /// its status menu is open. This intentionally does not install a global
    /// hotkey or claim one: global registration needs a separate permissions
    /// and lifecycle design and is not safe to infer from an NSMenu shortcut.
    private func openReviewApp(requestSettings: Bool) {
        let command = requestSettings ? "open_settings" : "show_qaptr"
        guard let reviewAppURL else {
            print("event=command_failed command=\(command) reason=review_app_not_found")
            return
        }

        // Pass the intent as a launch argument as well as posting the
        // notification. A cold launch cannot be routed by notification alone:
        // the post below can land before the newly spawned app registers its
        // observers, which silently dropped the command and opened the app on
        // its default surface. macOS delivers these arguments only when it
        // actually spawns a new instance, so the two paths cover the warm and
        // cold cases without double-applying the command.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ReviewLaunchCommandRequest
            .forSettingsRequest(requestSettings)
            .launchArguments

        NSWorkspace.shared.openApplication(at: reviewAppURL, configuration: configuration) { _, error in
            if let error {
                print("event=command_failed command=\(command) detail=\(error)")
                return
            }
            DistributedNotificationCenter.default().post(
                name: requestSettings
                    ? ReviewCommandNotification.openSettings
                    : ReviewCommandNotification.showObservations,
                object: nil
            )
        }
    }

    private func openDetailedSummary(sessionID: String) {
        guard let reviewAppURL else {
            print("event=command_failed command=show_detailed_summary reason=review_app_not_found")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ReviewLaunchCommandRequest.showObservations.launchArguments
        NSWorkspace.shared.openApplication(at: reviewAppURL, configuration: configuration) { _, error in
            if let error {
                print("event=command_failed command=show_detailed_summary detail=\(error)")
                return
            }
            DistributedNotificationCenter.default().post(
                name: ReviewCommandNotification.showDetailedSummary,
                object: sessionID
            )
        }
    }

    private var reviewAppURL: URL? {
        HelperRuntimePaths.reviewApplicationURL(
            environment: ProcessInfo.processInfo.environment,
            helperBundleURL: Bundle.main.bundleURL
        )
    }

    private func scheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            self.writePermissionStatus()
            self.syncControl(at: Self.currentTimestamp())
            self.expireDetailedCaptureIfNeeded(at: Self.currentTimestamp())
            self.refreshMenu()
            guard self.captureEnabled,
                  self.planner.action(at: ProcessInfo.processInfo.systemUptime) == .capture else {
                return
            }
            self.runTick()
        }
        self.timer = timer
        timer.resume()
    }

    private func syncControl(at timestamp: Int64) {
        guard let control = try? controlStore.read(),
              let interval = try? CaptureInterval(seconds: control.intervalSeconds) else {
            return
        }

        if interval != activeInterval {
            activeInterval = interval
            planner = TickPlanner(interval: interval)
            print("event=control interval_seconds=\(interval.seconds)")
        }

        guard control.intent != captureIntent else {
            if control.intent == .paused {
                captureEnabled = false
            }
            return
        }

        captureIntent = control.intent
        switch control.intent {
        case .paused:
            captureEnabled = false
            capturePrepared = false
            planner = TickPlanner(interval: activeInterval)
            progressTracker.pause(
                at: timestamp,
                selectedDisplayIDs: Array(selectedDisplayIDs),
                activeIntervalSeconds: activeInterval.seconds
            )
            persistProgress()
            updateStatus("Q")
            print("event=control intent=paused interval_seconds=\(activeInterval.seconds)")
        case .running:
            captureEnabled = !options.permissionOnly && Self.finalConsentGranted
            capturePrepared = false
            planner = TickPlanner(interval: activeInterval)
            print("event=control intent=running interval_seconds=\(activeInterval.seconds)")
            if captureEnabled {
                prepareCaptureIfNeeded()
            }
        }
    }

    private func menuState(at timestamp: Int64) -> HelperMenuState {
        let captureCount = progressTracker.progress.captureCount
        if let session = detailedSession {
            return .detailed(
                remainingSeconds: max(0, Int((session.endsAtMillis - timestamp) / 1_000)),
                detailedCount: detailedCaptureCount(for: session),
                generalCount: session.baselineCaptureCount
            )
        }
        if let activity = readReviewActivity() {
            switch activity.phase {
            case .resultReady:
                return .analysisAvailable(captureCount: captureCount)
            case .failed:
                return .recovery(
                    message: activity.message ?? "The last analysis could not finish",
                    captureCount: captureCount
                )
            case .preparing, .waitingForConsent, .analyzing:
                return .analysisInProgress(
                    phase: activity.phase,
                    captureCount: captureCount,
                    message: activity.message
                )
            }
        }
        if progressTracker.progress.state == .permissionRequired {
            return .recovery(message: "Screen Recording permission is required", captureCount: captureCount)
        }
        if progressTracker.progress.state == .noDisplays {
            return .recovery(message: "No display is available to capture", captureCount: captureCount)
        }
        if progressTracker.progress.state == .error {
            return .recovery(
                message: progressTracker.progress.failureReason ?? "Capture needs attention",
                captureCount: captureCount
            )
        }
        let status: String
        switch progressTracker.progress.state {
        case .capturing:
            status = "Capturing now"
        case .paused:
            status = "Capture paused"
        case .starting:
            status = "Starting capture"
        default:
            status = captureIntent == .paused ? "Capture paused" : "Capture is on"
        }
        return .normal(
            status: status,
            paused: captureIntent == .paused,
            captureCount: captureCount
        )
    }

    private func expireDetailedCaptureIfNeeded(at timestamp: Int64) {
        guard let session = detailedSession, timestamp >= session.endsAtMillis else { return }
        finishDetailedCapture(stopReason: "expired", resumeNormalCapture: true)
    }

    private func detailedCaptureCount(for session: DetailedCaptureSession) -> Int {
        max(0, progressTracker.progress.captureCount - session.baselineCaptureCount)
    }

    @discardableResult
    private func writeControl(intervalSeconds: Int, intent: CaptureControlIntent) -> Bool {
        do {
            try controlStore.write(try CaptureControl(intervalSeconds: intervalSeconds, intent: intent))
            return true
        } catch {
            print("event=control_failed interval_seconds=\(intervalSeconds) intent=\(intent.rawValue) detail=\(error)")
            return false
        }
    }

    private func writeDetailedSession(_ session: DetailedCaptureSession) -> Bool {
        do {
            let data = try JSONEncoder().encode(session)
            try writeAtomically(data, to: Self.detailedSessionURL())
            return true
        } catch {
            print("event=detailed_capture_failed reason=session_write detail=\(error)")
            return false
        }
    }

    private func writeDetailedSummary(
        for session: DetailedCaptureSession,
        endedAtMillis: Int64,
        detailedCaptureCount: Int,
        stopReason: String
    ) {
        let summary = DetailedCaptureSummary(
            session: session,
            endedAtMillis: endedAtMillis,
            detailedCaptureCount: detailedCaptureCount,
            stopReason: stopReason
        )
        do {
            let data = try JSONEncoder().encode(summary)
            try writeAtomically(data, to: Self.detailedSummaryURL())
        } catch {
            print("event=detailed_summary_failed detail=\(error)")
        }
    }

    private func removeDetailedSession() {
        try? FileManager.default.removeItem(at: Self.detailedSessionURL())
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func readReviewActivity() -> ReviewActivitySnapshot? {
        guard let data = try? Data(contentsOf: Self.reviewActivityURL()) else { return nil }
        return try? JSONDecoder().decode(ReviewActivitySnapshot.self, from: data)
    }

    private func runTick() {
        cycle += 1
        guard capture.screenRecordingAccessGranted() else {
            progressTracker.markPermissionRequired(
                at: Self.currentTimestamp(),
                selectedDisplayIDs: Array(selectedDisplayIDs),
                activeIntervalSeconds: activeInterval.seconds,
                failureReason: "Screen Recording permission not granted"
            )
            persistProgress()
            updateStatus("Q")
            print("event=skip cycle=\(cycle) reason=screen_recording_permission")
            stopAfterLimitIfNeeded()
            return
        }

        do {
            progressTracker.beginCapture(
                at: Self.currentTimestamp(),
                selectedDisplayIDs: Array(selectedDisplayIDs),
                activeIntervalSeconds: activeInterval.seconds
            )
            persistProgress()
            let current = Set(try capture.availableDisplayIDs())
            selectedDisplayIDs = current
            let displays = current.sorted()
            let events = coordinator.runTick(
                displays: displays,
                context: context.sample(),
                capturedAtMillis: Self.currentTimestamp(),
                maxDimension: options.maxDimension,
                permissionGranted: true
            ) { displayID in
                "capture-\(Int(Date().timeIntervalSince1970 * 1_000))-\(displayID)-\(cycle)"
            }
            for event in events {
                log(event)
            }
            let successfulCaptures = events.reduce(into: 0) { count, event in
                if case .sealed = event {
                    count += 1
                }
            }
            let firstFailureReason = events.compactMap { event -> String? in
                switch event {
                case let .skippedCapture(displayID, reason):
                    return "capture failed on \(displayID): \(reason)"
                case let .skippedSealing(displayID, reason):
                    return "sealing failed on \(displayID): \(reason)"
                default:
                    return nil
                }
            }.first
            if displays.isEmpty {
                progressTracker.markNoDisplays(
                    at: Self.currentTimestamp(),
                    selectedDisplayIDs: displays,
                    activeIntervalSeconds: activeInterval.seconds,
                    failureReason: "no selected displays are currently attached"
                )
            } else {
                progressTracker.finishCapture(
                    at: Self.currentTimestamp(),
                    successfulCaptures: successfulCaptures,
                    selectedDisplayIDs: displays,
                    activeIntervalSeconds: activeInterval.seconds,
                    failureReason: firstFailureReason
                )
            }
            persistProgress()
            updateStatus(events.contains { if case .sealed = $0 { return true }; return false } ? "●" : "Q")
        } catch {
            progressTracker.markError(
                at: Self.currentTimestamp(),
                selectedDisplayIDs: Array(selectedDisplayIDs),
                activeIntervalSeconds: activeInterval.seconds,
                failureReason: "display enumeration failed: \(error)"
            )
            persistProgress()
            print("event=skip cycle=\(cycle) reason=display_enumeration error=\(error)")
        }
        stopAfterLimitIfNeeded()
    }

    private func stopAfterLimitIfNeeded() {
        guard let maximumCycles = options.maximumCycles, cycle >= maximumCycles else {
            return
        }
        timer?.cancel()
        timer = nil
        NSApp.terminate(nil)
    }

    private func updateStatus(_ title: String) {
        _ = title
        refreshMenu(force: true)
    }

    private func persistProgress() {
        do {
            try progressStore.write(progressTracker.progress)
        } catch {
            print("event=skip reason=progress_status_unavailable detail=\(error)")
        }
    }

    /// Publishes the TCC state of the process that actually owns and uses both
    /// permissions. QaptrReview cannot query these public APIs on the helper's
    /// behalf because macOS always evaluates the calling process.
    private func writePermissionStatus() {
        let snapshot = HelperPermissionSnapshot(
            screenRecordingGranted: capture.screenRecordingAccessGranted(),
            screenRecordingRequested: permissionDefaults.bool(forKey: Self.screenRecordingRequestedKey),
            accessibilityGranted: context.accessibilityPermissionGranted,
            accessibilityRequested: permissionDefaults.bool(forKey: Self.accessibilityRequestedKey),
            processID: Int(ProcessInfo.processInfo.processIdentifier),
            updatedAtMillis: Self.currentTimestamp(),
            helperBundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path,
            commandToken: commandToken
        )
        do {
            try permissionStore.write(snapshot)
        } catch {
            print("event=skip reason=permission_status_unavailable detail=\(error)")
        }
    }

    private static func captureProgressURL() -> URL {
        captureProgressURLOverride()
    }

    private static func captureControlURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_CAPTURE_CONTROL_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("capture-control.json")
    }

    private static func permissionStatusURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_PERMISSION_STATUS_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("permission-status.json")
    }

    private static func detailedSessionURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_DETAILED_SESSION_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("detailed-capture-session.json")
    }

    private static func detailedSummaryURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_DETAILED_SUMMARY_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("detailed-capture-summary.json")
    }

    private static func reviewActivityURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_REVIEW_ACTIVITY_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("review-activity.json")
    }

    private static func readDetailedSession() -> DetailedCaptureSession? {
        guard let data = try? Data(contentsOf: detailedSessionURL()) else { return nil }
        return try? JSONDecoder().decode(DetailedCaptureSession.self, from: data)
    }

    private static func validInterval(_ value: Int, fallback: Int) -> Int {
        guard (try? CaptureInterval(seconds: value)) != nil else { return fallback }
        return value
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private static let screenRecordingRequestedKey = "com.qaptr.helper.permission.screen-recording-requested"
    private static let accessibilityRequestedKey = "com.qaptr.helper.permission.accessibility-requested"
    private static let detailedIntervalKey = "com.qaptr.helper.detailed.interval-seconds"
    private static let detailedDurationKey = "com.qaptr.helper.detailed.duration-seconds"
    private static let onboardingCompletedKey = "com.qaptr.review.onboarding.completed"

    private static var finalConsentGranted: Bool {
        UserDefaults(suiteName: "com.qaptr.review")?.bool(forKey: onboardingCompletedKey) == true
    }

    private func log(_ event: CaptureEvent) {
        switch event {
        case let .sealed(captureID, displayID, width, height):
            print("event=sealed capture_id=\(captureID) display_id=\(displayID) output=\(width)x\(height)")
        case .refusedOverlap:
            print("event=skip reason=capture_in_flight")
        case .skippedPermission:
            print("event=skip reason=screen_recording_permission")
        case .skippedNoDisplays:
            print("event=skip reason=selected_displays_unavailable")
        case let .skippedCapture(displayID, reason):
            print("event=skip display_id=\(displayID) reason=capture_failed detail=\(reason)")
        case let .skippedSealing(displayID, reason):
            print("event=skip display_id=\(displayID) reason=sealing_failed detail=\(reason)")
        }
    }
}

private func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    if minutes > 0 {
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }
    return "\(remainder)s"
}

private struct UnavailableSealer: BundleSealer {
    let reason: String

    func seal(
        captureID: String,
        capturedAtMillis: Int64,
        frame: CapturedFrame,
        context: SampledContext
    ) throws {
        _ = captureID
        _ = capturedAtMillis
        _ = frame
        _ = context
        throw NSError(
            domain: "com.qaptr.helper.vault",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }
}

private enum HelperError: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case let .invalidArgument(message):
            message
        }
    }
}

private func captureProgressURLOverride() -> URL {
    if let override = ProcessInfo.processInfo.environment["QAPTR_CAPTURE_PROGRESS_PATH"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
        .appendingPathComponent("capture-progress.json")
}

@MainActor
private enum QaptrHelperMain {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            let resolvedLockPath = HelperRuntimePaths.lockURL(
                environment: ProcessInfo.processInfo.environment,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
            let instanceLock: SingleInstanceLock
            do {
                instanceLock = try SingleInstanceLock(path: resolvedLockPath)
            } catch SingleInstanceError.alreadyRunning {
                throw HelperError.invalidArgument("another Qaptr helper instance is already running")
            } catch {
                throw HelperError.invalidArgument("could not acquire helper ownership lock")
            }
            let sealer: any BundleSealer
            do {
                sealer = try RustVaultSealer(root: options.vaultRoot, generationID: options.generationID)
            } catch {
                print("event=skip reason=vault_unavailable detail=\(error)")
                sealer = UnavailableSealer(reason: String(describing: error))
            }
            if let fixtureManifestURL = options.fixtureManifest,
               let fixtureImageRoot = options.fixtureImageRoot {
                let manifest = try FixtureManifest(data: Data(contentsOf: fixtureManifestURL))
                let result = try FixtureIngestion.run(
                    manifest: manifest,
                    capture: FixtureImageCapture(root: fixtureImageRoot),
                    sealer: sealer,
                    context: SampledContext(application: "Qaptr fixture"),
                    progressStore: CaptureProgressStore(url: captureProgressURLOverride()),
                    intervalSeconds: options.interval.seconds,
                    maxDimension: options.maxDimension,
                    processID: Int64(ProcessInfo.processInfo.processIdentifier),
                    at: Int64(Date().timeIntervalSince1970 * 1_000)
                )
                print("event=fixture_ingestion attempted=\(result.attemptedCount) sealed=\(result.sealedCount) failed=\(result.failedCount)")
                return
            }
            let application = NSApplication.shared
            let delegate = HelperApplication(options: options, instanceLock: instanceLock, sealer: sealer)
            application.delegate = delegate
            application.run()
        } catch {
            FileHandle.standardError.write(Data("qaptr helper stopped: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

QaptrHelperMain.main()
