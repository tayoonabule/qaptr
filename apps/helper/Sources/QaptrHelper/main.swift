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
    static let requestScreenRecording = Notification.Name("com.qaptr.review.command.requestScreenRecording")
    static let requestAccessibility = Notification.Name("com.qaptr.review.command.requestAccessibility")
    static let startCapture = Notification.Name("com.qaptr.review.command.startCapture")
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
        syncControl(at: Self.currentTimestamp())
        writePermissionStatus()
        configureStatusItem()
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
        statusItem.button?.title = "Q"
        statusItem.button?.toolTip = "Qaptr capture helper"
        let menu = NSMenu()

        let showQaptr = NSMenuItem(
            title: "Show Capture Observations",
            action: #selector(showQaptr(_:)),
            keyEquivalent: "1"
        )
        showQaptr.target = self
        showQaptr.keyEquivalentModifierMask = [.command]
        menu.addItem(showQaptr)

        let openSettings = NSMenuItem(
            title: "Open Settings",
            action: #selector(openReviewSettings(_:)),
            keyEquivalent: ","
        )
        openSettings.target = self
        openSettings.keyEquivalentModifierMask = [.command]
        menu.addItem(openSettings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func showQaptr(_ sender: Any?) {
        _ = sender
        openReviewApp(requestSettings: false)
    }

    @objc private func openReviewSettings(_ sender: Any?) {
        _ = sender
        openReviewApp(requestSettings: true)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
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

        NSWorkspace.shared.openApplication(at: reviewAppURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
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
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.title = title
        }
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

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private static let screenRecordingRequestedKey = "com.qaptr.helper.permission.screen-recording-requested"
    private static let accessibilityRequestedKey = "com.qaptr.helper.permission.accessibility-requested"
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
