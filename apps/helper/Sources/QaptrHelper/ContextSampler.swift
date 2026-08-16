import AppKit
import ApplicationServices
import Foundation
import QaptrHelperCore

struct PointInTimeContextSampler {
    var accessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    func sample() -> SampledContext {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let windowTitle = frontmost.flatMap(focusedWindowTitle(for:))
        return SampledContext(application: frontmost?.localizedName, windowTitle: windowTitle)
    }

    private func focusedWindowTitle(for application: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow
        else {
            return nil
        }
        let focusedWindowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedWindowElement,
            kAXTitleAttribute as CFString,
            &title
        ) == .success else {
            return nil
        }
        return title as? String
    }
}
