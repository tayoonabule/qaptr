import AppKit
import Foundation

/// Enumerates real attached displays for the settings display selector.
///
/// This lives in the app target (not `QaptrReviewCore`) because it is the one
/// place AppKit's `NSScreen` is appropriate to call directly; the capture
/// helper already owns its own independent display enumeration through
/// ScreenCaptureKit and is not touched by this type.
enum DisplayEnumerator {
    struct DisplayDescriptor: Identifiable, Equatable {
        let id: String
        let name: String
    }

    static func currentDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.enumerated().map { index, screen in
            let numericID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .stringValue ?? String(index)
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            return DisplayDescriptor(id: numericID, name: name)
        }
    }
}
