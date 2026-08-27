import AppKit
import Foundation
import QaptrReviewCore
import SwiftUI

// Hallmark: Native macOS scene routes remain stable while review surfaces use the studied-DNA layout.

/// Optional first-paint instrumentation, matching the U3 probe's timing
/// contract so the same measurement script pattern applies to production.
private func recordFirstPaintIfRequested() {
  guard let path = ProcessInfo.processInfo.environment["QAPTR_REVIEW_PAINT_FILE"] else {
    return
  }
  let nanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
  try? "\(nanoseconds)\n".write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
}

/// Optional surface instrumentation, following the same env-gated,
/// write-once contract as the first-paint probe above.
///
/// The routing this records is otherwise only observable by looking at the
/// window, which is impossible when the screen is locked and unreliable over
/// the accessibility API for a background app. Recording the resolved surface
/// makes cold-launch routing verifiable from a script, which is how the launch
/// argument contract is exercised against a real signed build rather than only
/// in unit tests.
private func recordResolvedSurfaceIfRequested(_ surface: ReviewSurface) {
  guard let path = ProcessInfo.processInfo.environment["QAPTR_REVIEW_SURFACE_FILE"] else {
    return
  }
  try? "\(surface.probeName)\n".write(
    to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windowController: NSWindowController?
  let model = ReviewAppModel()
  let navigation = ReviewNavigation()

  private static let openSettingsNotification = Notification.Name(
    "com.qaptr.review.command.openSettings")
  private static let showObservationsNotification = Notification.Name(
    "com.qaptr.review.command.showObservations")

  override init() {
    super.init()
    QaptrFont.register()
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(handleOpenSettingsNotification(_:)),
      name: Self.openSettingsNotification,
      object: nil
    )
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(handleShowObservationsNotification(_:)),
      name: Self.showObservationsNotification,
      object: nil
    )
  }

  deinit {
    DistributedNotificationCenter.default().removeObserver(self)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    _ = notification
    guard claimSingleInstance() else {
      NSApp.terminate(nil)
      return
    }
    NSApp.setActivationPolicy(.regular)
    let content = NSHostingView(rootView: RootView(model: model, navigation: navigation))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 845, height: 737),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = model.onboardingCompleted ? "Qaptr" : "Qaptr Setup"
    // A transparent titlebar with "unified" style removes the hairline
    // seam AppKit otherwise draws between the traffic-light title bar
    // and the content view, so the two read as one continuous surface
    // instead of a bar sitting visibly on top of a separate pane below
    // it. `titlebarSeparatorStyle = .none` additionally suppresses the
    // separator some AppKit versions still draw under
    // `NSVisualEffectView`-less content even with a transparent bar.
    window.titlebarAppearsTransparent = true
    // The Figma title bar (node 16:5594) draws its own "Qaptr Home" /
    // "Qaptr Settings" label alongside a 14×14 logo-mini mark, positioned
    // to sit beside the real traffic lights rather than duplicating
    // AppKit's centered native title. `window.title` stays set (Mission
    // Control, Cmd-`, and Dock menus still read it); only the drawn native
    // title text is hidden so it doesn't double up with the in-content one.
    window.titleVisibility = .hidden
    if #available(macOS 13.0, *) {
      window.titlebarSeparatorStyle = .none
    }
    // Match the window's own background to the app's off-white/off-
    // black surface token (defined once in DesignTokens.swift) so the
    // transparent titlebar shows the same color as the content beneath
    // it, rather than AppKit's default window background peeking
    // through as a mismatched sliver behind the traffic-light controls.
    // Materials need a transparent AppKit host so they can sample the gradient
    // behind each SwiftUI surface. An opaque window turns every material into a
    // nearly flat white fill, which is visibly different from the Figma glass.
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = content
    window.contentView?.wantsLayer = true
    window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    window.center()
    // A window controller owns the AppKit close/reopen lifecycle. Keeping
    // it on the delegate preserves this same window and SwiftUI model after
    // Close so Dock and helper-menu reopen commands can show the in-flight
    // analysis again instead of creating a fresh session.
    let windowController = NSWindowController(window: window)
    self.windowController = windowController
    windowController.showWindow(nil)
    // AppKit auto-assigns the first key-view-loop-eligible control as
    // first responder whenever a window becomes key with none set,
    // which for this window means the first onboarding button always
    // renders with a focus ring on launch, and again on every stage
    // change, as if pre-selected rather than tab-reached. Clearing the
    // first responder after the window is key removes that ring until
    // the user actually presses Tab, while keyboard focus still works
    // normally from that point on.
    window.makeFirstResponder(nil)
    NSApp.activate(ignoringOtherApps: true)
    restartPackagedHelperForFreshPermissionState()
    applyLaunchCommandIfPresent()
    // Recorded after routing, so the probe reflects the surface the user
    // actually lands on rather than the one the command asked for; the
    // settings command is policy-checked and can legitimately resolve
    // elsewhere when onboarding is incomplete.
    recordResolvedSurfaceIfRequested(navigation.surface)
    recordFirstPaintIfRequested()
  }

  /// SwiftPM's executable target can be launched directly without a stable
  /// application bundle identifier. Match both the bundle identifier and the
  /// executable name so repeated `swift run`, mock launches, and packaged
  /// launches all converge on one menu-bar extra and one main window.
  private func claimSingleInstance() -> Bool {
    let currentPID = NSRunningApplication.current.processIdentifier
    let currentExecutable = Bundle.main.executableURL?.lastPathComponent ?? "QaptrReview"
    let bundleID = Bundle.main.bundleIdentifier
    let candidates: [NSRunningApplication]
    if let bundleID {
      candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    } else {
      candidates = NSWorkspace.shared.runningApplications
    }

    guard let existing = candidates.first(where: { application in
      guard application.processIdentifier != currentPID else { return false }
      guard let executable = application.executableURL else { return false }
      return executable.lastPathComponent == currentExecutable
        || executable.lastPathComponent == "QaptrReview"
    }) else {
      return true
    }

    existing.activate(options: [.activateAllWindows])
    return false
  }

  /// TCC can cache Screen Recording and Accessibility decisions for the
  /// lifetime of the helper process. The system permission sheet explicitly
  /// tells the user to quit and reopen the app, but the helper is a separate
  /// login-item process and would otherwise survive that reopen with its old
  /// cached decision. Restart only the helper inside this exact packaged app
  /// before offering capture or routing onboarding commands.
  private func restartPackagedHelperForFreshPermissionState() {
    guard let helperURL = packagedHelperURL else { return }
    let helperPath = helperURL.path
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.qaptr.helper")
      .filter { application in
        guard let executableURL = application.executableURL else { return false }
        return executableURL.path.hasPrefix(helperPath + "/Contents/")
      }
    for application in running {
      application.terminate()
    }

    if !model.onboardingCompleted {
      // During first-run onboarding the helper is intentionally started
      // in permission-only mode. Without this relaunch, the native
      // Screen Recording sheet's required "Quit & Reopen" action leaves
      // the review app with no live helper heartbeat, so onboarding
      // falls back to "Not yet requested" even after the user granted
      // the permission in System Settings.
      Task {
        for _ in 0..<20 where !Self.runningPackagedHelpers(matching: helperPath).isEmpty {
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for application in Self.runningPackagedHelpers(matching: helperPath) {
          application.forceTerminate()
        }
        for _ in 0..<10 where !Self.runningPackagedHelpers(matching: helperPath).isEmpty {
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--permission-only", "true"]
        _ = try? await NSWorkspace.shared.openApplication(
          at: helperURL,
          configuration: configuration
        )
      }
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self else { return }
      guard
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.qaptr.helper")
          .filter({ $0.executableURL?.path.hasPrefix(helperPath + "/Contents/") == true })
          .isEmpty
      else { return }
      self.offerCaptureStartIfNeeded()
    }
  }

  private var packagedHelperURL: URL? {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LoginItems", isDirectory: true)
      .appendingPathComponent("QaptrHelper.app", isDirectory: true)
      .alsoIfExists()
  }

  private static func runningPackagedHelpers(matching helperPath: String) -> [NSRunningApplication]
  {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.qaptr.helper")
      .filter { $0.executableURL?.path.hasPrefix(helperPath + "/Contents/") == true }
  }

  /// The packaged launcher used to offer this prompt before opening the
  /// nested review app. The review app is now the top-level product, so keep
  /// the same returning-user behavior here.
  private func offerCaptureStartIfNeeded() {
    guard model.onboardingCompleted,
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.qaptr.helper").isEmpty,
      let helperURL = packagedHelperURL
    else { return }

    let alert = NSAlert()
    alert.messageText = "Start Qaptr capture?"
    alert.informativeText =
      "Qaptr will start periodic, local screen captures at your configured interval. macOS may still require Screen Recording permission for Qaptr Helper. No provider request is made."
    alert.addButton(withTitle: "Start Capture")
    alert.addButton(withTitle: "Not Now")
    if alert.runModal() == .alertFirstButtonReturn {
      _ = NSWorkspace.shared.open(helperURL)
    }
  }

  /// Honors a command the helper passed as a launch argument.
  ///
  /// A cold launch cannot be routed by distributed notification: the helper
  /// posts as soon as the open call succeeds, which can precede this
  /// delegate's observer registration, so the notification is dropped and the
  /// window would open on its default surface. Reading the argument here runs
  /// after the window exists and routes through the same policy-checked entry
  /// points as the warm path, so both paths share one set of rules.
  private func applyLaunchCommandIfPresent() {
    guard
      let command = ReviewLaunchCommand.parse(
        arguments: ProcessInfo.processInfo.arguments
      )
    else { return }
    switch command {
    case .showObservations:
      showObservations()
    case .openSettings:
      openSettings()
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    _ = notification
    model.refreshSettings()
    model.refreshPermissions()
    if !model.onboardingCompleted,
      model.settings.screenRecordingStatus != .granted
    {
      restartPackagedHelperForFreshPermissionState()
    }
    model.refreshCaptureProgress()
  }

  func showMainWindow() {
    guard let windowController, let window = windowController.window else { return }
    NSApp.activate(ignoringOtherApps: true)
    windowController.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
  }

  func showObservations() {
    navigation.surface = .review
    showMainWindow()
  }

  /// Routes the existing main window to Qaptr's native Settings surface.
  func openSettings() {
    switch SettingsEntryPolicy.route(onboardingCompleted: model.onboardingCompleted) {
    case .settings:
      navigation.surface = .settings
      showMainWindow()
    case .primaryUI:
      // Settings must not become a back door around onboarding's final
      // privacy/capture-consent step. Return to the primary UI instead.
      showMainWindow()
    }
  }

  @objc private func handleOpenSettingsNotification(_ notification: Notification) {
    _ = notification
    openSettings()
  }

  @objc private func handleShowObservationsNotification(_ notification: Notification) {
    _ = notification
    showObservations()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Closing a window is not consent to cancel an in-flight analysis.
    // Keep the retained AppKit window and model alive; explicit Quit still
    // terminates the application and its native session.
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag { showMainWindow() }
    return true
  }
}

extension URL {
  fileprivate func alsoIfExists() -> URL? {
    FileManager.default.fileExists(atPath: path) ? self : nil
  }
}

@main
struct QaptrReviewApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      QaptrMenuBarView(model: appDelegate.model, appDelegate: appDelegate)
    } label: {
      QaptrTitleMark(size: 14)
    }
    .menuBarExtraStyle(.window)

    Settings {
      NativeSettingsEntryView(
        model: appDelegate.model,
        redirectToPrimaryUI: appDelegate.showMainWindow
      )
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…", action: appDelegate.openSettings)
          .keyboardShortcut(",", modifiers: [.command])
      }
      CommandGroup(after: .windowArrangement) {
        Button("Show Capture Observations", action: appDelegate.showObservations)
          .keyboardShortcut("1", modifiers: [.command])
      }
    }
  }
}

/// The background app's primary control surface. Every label is derived from
/// the same model used by the main window, so the menu bar cannot drift from
/// the strip and, importantly, cannot approve or invoke a provider itself.
private struct QaptrMenuBarView: View {
  @Bindable var model: ReviewAppModel
  let appDelegate: AppDelegate

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        HStack(spacing: QaptrSpace.sm) {
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine)
              .font(QaptrType.body(13))
              .foregroundStyle(Color.qaptrFigmaText)
          }
        }

        Divider().overlay(Color.qaptrHairline)

        if model.analysisSessionState.phase == .readyForConsent {
          Button("Review and approve") {
            appDelegate.showMainWindow()
          }
        } else {
          Button("Analyze now", action: model.startAnalysis)
            .disabled(!model.analysisCanStart)
        }

        if model.detailedCaptureState.lifecycle == .capturing {
          Button("Stop & review", action: model.stopDetailedCapture)
        } else if model.captureControlIntent == .paused {
          Button("Resume capture", action: model.resumeCapture)
        } else {
          Button("Pause capture", action: model.pauseCapture)
        }

        Button("Open Qaptr", action: appDelegate.showMainWindow)
        Button("Settings…", action: appDelegate.openSettings)

        Divider().overlay(Color.qaptrHairline)
        Button("Quit Qaptr") { NSApp.terminate(nil) }
      }
    }
    .padding(QaptrSpace.xs)
    .background { FigmaGlassSurface(radius: QaptrRadius.feature) }
    .frame(width: 300)
  }

  private var statusLine: String {
    if model.detailedCaptureState.lifecycle == .capturing {
      return "Watching closely · detailed capture"
    }
    switch model.analysisSessionState.phase {
    case .ingesting, .preparing, .analyzing:
      return "Analyzing on this Mac…"
    case .readyForConsent:
      return "Ready for your approval"
    default:
      break
    }
    if model.captureControlIntent == .paused { return "Capture paused" }
    switch model.captureProgress.state {
    case .permissionRequired: return "Screen Recording was turned off"
    case .noDisplays: return "No display connected"
    case .error, .stopped, .unknown:
      return "Capture stopped in the background"
    case .starting, .waiting, .capturing, .paused:
      let count = model.captureProgress.captureCount ?? 0
      return "Capturing quietly · \(count) today"
    }
  }

  private var statusColor: Color {
    if model.analysisSessionState.phase == .readyForConsent { return Color.qaptrAccent }
    if model.captureControlIntent == .paused { return Color.qaptrWarning }
    switch model.captureProgress.state {
    case .error, .stopped, .unknown, .permissionRequired, .noDisplays: return Color.qaptrWarning
    default: return Color.qaptrSuccess
    }
  }
}
