import SwiftUI

/// A single dynamic NSColor factory shared by both the SwiftUI `Color` token
/// below and the AppKit window setup in `QaptrReviewApp.swift`.
func qaptrSurfaceNSColor(appearance: NSAppearance) -> NSColor {
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark
        ? NSColor(red: 0.055, green: 0.055, blue: 0.052, alpha: 1)
        : NSColor(red: 0.984, green: 0.980, blue: 0.972, alpha: 1)
}

extension Color {
    /// The app's shared off-white / off-black base surface.
    static let qaptrSurface = Color(nsColor: NSColor(name: nil, dynamicProvider: qaptrSurfaceNSColor))

    /// One warm accent shared across selection, progress, and deliberate action.
    static let qaptrAccent = Color(nsColor: .systemOrange)

    /// A subtle interaction wash. It is used only for an actual hover or a
    /// selected control, never as decorative card chrome.
    static let qaptrControlFill = Color.primary.opacity(0.055)

    /// The one rule used by all compositional dividers.
    static let qaptrRule = Color.primary.opacity(0.12)
}
