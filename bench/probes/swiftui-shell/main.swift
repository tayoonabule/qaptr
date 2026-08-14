import AppKit
import CoreGraphics
import SwiftUI

private func writeLine(_ line: String, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
}

private func outputPath(_ key: String, fallback: String) -> String {
    ProcessInfo.processInfo.environment[key] ?? fallback
}

private func recordScreenCapturePermission() {
    let before = CGPreflightScreenCaptureAccess()
    let request = ProcessInfo.processInfo.environment["QAPTR_U3_REQUEST_TCC"] == "1"
    let requested = request ? CGRequestScreenCaptureAccess() : false
    let after = CGPreflightScreenCaptureAccess()
    let record = "before=\(before ? 1 : 0) requested=\(requested ? 1 : 0) after=\(after ? 1 : 0) pid=\(ProcessInfo.processInfo.processIdentifier)"
    writeLine(record, to: outputPath("QAPTR_U3_TCC_FILE", fallback: "/tmp/qaptr-u3-swiftui-tcc"))
}

private struct ObservationSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Qaptr")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Observation Sheet")
                .font(.system(size: 17, weight: .medium))
            Text("A small, focused view of recent work.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Review shell prototype")
                .font(.system(size: 15, weight: .regular))
            Spacer()
        }
        .padding(28)
        .frame(width: 460, height: 300)
        .background(.background)
        .onAppear {
            writeLine(
                "\(UInt64(Date().timeIntervalSince1970 * 1_000_000_000))",
                to: outputPath("QAPTR_U3_PAINT_FILE", fallback: "/tmp/qaptr-u3-swiftui-paint")
            )
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordScreenCapturePermission()
        let content = NSHostingView(rootView: ObservationSheet())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Qaptr SwiftUI Shell"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

@main
struct QaptrSwiftUIShellProbe: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
