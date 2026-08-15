import AppKit
import Foundation
import SwiftUI

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
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = ReviewAppModel()

    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.regular)
        let content = NSHostingView(rootView: RootView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
        window.makeKeyAndOrderFront(nil)
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
        self.window = window
        recordFirstPaintIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct QaptrReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
