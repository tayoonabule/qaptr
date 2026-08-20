import AppKit
import Foundation
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    let model = ReviewAppModel()
    let navigation = ReviewNavigation()

    private static let openSettingsNotification = Notification.Name("com.qaptr.review.command.openSettings")
    private static let showObservationsNotification = Notification.Name("com.qaptr.review.command.showObservations")

    override init() {
        super.init()
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
        NSApp.setActivationPolicy(.regular)
        let content = NSHostingView(rootView: RootView(model: model, navigation: navigation))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            // Let the SwiftUI surface render beneath the transparent titlebar.
            // This keeps the rail's fill and divider continuous through the
            // traffic-light area instead of stopping at the content-layout
            // boundary below it.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Qaptr"
        // A transparent titlebar with "unified" style removes the hairline
        // seam AppKit otherwise draws between the traffic-light title bar
        // and the content view, so the two read as one continuous surface
        // instead of a bar sitting visibly on top of a separate pane below
        // it. `titlebarSeparatorStyle = .none` additionally suppresses the
        // separator some AppKit versions still draw under
        // `NSVisualEffectView`-less content even with a transparent bar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        if #available(macOS 13.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        // Match the window's own background to the app's off-white/off-
        // black surface token (defined once in DesignTokens.swift) so the
        // transparent titlebar shows the same color as the content beneath
        // it, rather than AppKit's default window background peeking
        // through as a mismatched sliver behind the traffic-light controls.
        window.backgroundColor = NSColor(name: nil, dynamicProvider: qaptrSurfaceNSColor)
        window.contentView = content
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
        recordFirstPaintIfRequested()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = notification
        model.refreshSettings()
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

@main
struct QaptrReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
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
