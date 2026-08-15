import AppKit
import CoreGraphics
import Foundation
import QaptrHelperCore

private struct Options {
    let interval: CaptureInterval
    let maxDimension: Int
    let maximumCycles: Int?
    let vaultRoot: URL
    let generationID: String

    static func parse(_ arguments: ArraySlice<String>) throws -> Self {
        var intervalSeconds = CaptureInterval.defaultSeconds
        var maxDimension = 1_920
        var maximumCycles: Int?
        var vaultRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr/vault", isDirectory: true)
        var generationID = "generation-1"
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
            default:
                throw HelperError.invalidArgument("unknown argument \(argument)")
            }
        }
        return try Self(
            interval: CaptureInterval(seconds: intervalSeconds),
            maxDimension: maxDimension,
            maximumCycles: maximumCycles,
            vaultRoot: vaultRoot,
            generationID: generationID
        )
    }
}

private enum ReviewCommandNotification {
    static let openSettings = Notification.Name("com.qaptr.review.command.openSettings")
}

@MainActor
private final class HelperApplication: NSObject, NSApplicationDelegate {
    private let options: Options
    private let instanceLock: SingleInstanceLock
    private let capture = ScreenCaptureAdapter()
    private let context = PointInTimeContextSampler()
    private let coordinator: CaptureCoordinator
    private let progressStore: CaptureProgressStore
    private let controlStore: CaptureControlStore
    private var progressTracker: CaptureProgressTracker
    private var planner: TickPlanner
    private var activeInterval: CaptureInterval
    private var selectedDisplayIDs = Set<String>()
    private var cycle = 0
    private var timer: DispatchSourceTimer?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(options: Options, instanceLock: SingleInstanceLock, sealer: BundleSealer) {
        self.options = options
        self.instanceLock = instanceLock
        self.coordinator = CaptureCoordinator(capture: capture, sealer: sealer)
        let progressStore = CaptureProgressStore(url: Self.captureProgressURL())
        self.progressStore = progressStore
        let controlStore = CaptureControlStore(url: Self.captureControlURL())
        self.controlStore = controlStore
        self.progressTracker = CaptureProgressTracker(initial: (try? progressStore.read()) ?? .initial)
        let persistedControl = (try? controlStore.read())
            ?? (try? CaptureControl(intervalSeconds: options.interval.seconds))
            ?? .default
        self.activeInterval = (try? CaptureInterval(seconds: persistedControl.intervalSeconds)) ?? options.interval
        self.planner = TickPlanner(interval: self.activeInterval)
        super.init()
        // Canonicalize missing or corrupt control data as the scalar interval.
        try? controlStore.write(
            (try? CaptureControl(intervalSeconds: self.activeInterval.seconds)) ?? .default
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        progressTracker.start(
            at: Self.currentTimestamp(),
            processID: Int64(ProcessInfo.processInfo.processIdentifier)
        )
        persistProgress()
        do {
            selectedDisplayIDs = Set(try capture.availableDisplayIDs())
            guard !selectedDisplayIDs.isEmpty else {
                progressTracker.markNoDisplays(at: Self.currentTimestamp())
                persistProgress()
                print("event=skip reason=no_displays")
                scheduleTimer()
                return
            }
            print("event=start pid=\(ProcessInfo.processInfo.processIdentifier) displays=\(selectedDisplayIDs.sorted().joined(separator: ",")) interval_seconds=\(options.interval.seconds)")
        } catch {
            progressTracker.markError(at: Self.currentTimestamp())
            persistProgress()
            print("event=skip reason=display_enumeration error=\(error)")
        }
        scheduleTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        timer?.cancel()
        timer = nil
        progressTracker.stop(at: Self.currentTimestamp())
        persistProgress()
    }

    private func configureStatusItem() {
        statusItem.button?.title = "Q"
        statusItem.button?.toolTip = "Qaptr capture helper"
        let menu = NSMenu()

        let showQaptr = NSMenuItem(
            title: "Show Qaptr / Observations",
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
            guard requestSettings else { return }
            DistributedNotificationCenter.default().post(
                name: ReviewCommandNotification.openSettings,
                object: nil
            )
        }
    }

    private var reviewAppURL: URL? {
        if let override = ProcessInfo.processInfo.environment["QAPTR_REVIEW_APP_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let nested = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("QaptrReview.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.qaptr.review")
    }

    private func scheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.qaptr.helper.capture"))
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if let control = try? self.controlStore.read(),
                   let interval = try? CaptureInterval(seconds: control.intervalSeconds),
                   interval != self.activeInterval {
                    self.activeInterval = interval
                    self.planner = TickPlanner(interval: interval)
                    print("event=control interval_seconds=\(interval.seconds)")
                }
                guard self.planner.action(at: ProcessInfo.processInfo.systemUptime) == .capture else {
                    return
                }
                self.runTick()
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func runTick() {
        cycle += 1
        guard CGPreflightScreenCaptureAccess() else {
            progressTracker.markPermissionRequired(at: Self.currentTimestamp())
            persistProgress()
            updateStatus("Q")
            print("event=skip cycle=\(cycle) reason=screen_recording_permission")
            stopAfterLimitIfNeeded()
            return
        }

        do {
            progressTracker.beginCapture(at: Self.currentTimestamp())
            persistProgress()
            let current = Set(try capture.availableDisplayIDs())
            let displays = selectedDisplayIDs.intersection(current).sorted()
            let events = coordinator.runTick(
                displays: displays,
                context: context.sample(),
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
            if displays.isEmpty {
                progressTracker.markNoDisplays(at: Self.currentTimestamp())
            } else {
                progressTracker.finishCapture(
                    at: Self.currentTimestamp(),
                    successfulCaptures: successfulCaptures
                )
            }
            persistProgress()
            updateStatus(events.contains { if case .sealed = $0 { return true }; return false } ? "●" : "Q")
        } catch {
            progressTracker.markError(at: Self.currentTimestamp())
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

    private static func captureProgressURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_CAPTURE_PROGRESS_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("capture-progress.json")
    }

    private static func captureControlURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QAPTR_CAPTURE_CONTROL_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("capture-control.json")
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
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

    func seal(captureID: String, frame: CapturedFrame, context: SampledContext) throws {
        _ = captureID
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

@MainActor
private enum QaptrHelperMain {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            let lockPath = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QAPTR_HELPER_LOCK_PATH"] ?? "")
            let resolvedLockPath = lockPath.path.isEmpty
                ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Qaptr/helper.lock")
                : lockPath
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
