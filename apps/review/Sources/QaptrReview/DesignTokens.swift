import SwiftUI

/// A single dynamic NSColor factory shared by both the SwiftUI `Color`
/// token below and the AppKit window setup in `QaptrReviewApp.swift`
/// (which configures `NSWindow.backgroundColor` before any SwiftUI view
/// renders, so it cannot reach for a `Color` value). Keeping one function
/// as the source of truth avoids the light/dark RGB pair drifting out of
/// sync between the two call sites.
func qaptrSurfaceNSColor(appearance: NSAppearance) -> NSColor {
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark
        ? NSColor(red: 0.055, green: 0.055, blue: 0.052, alpha: 1)
        : NSColor(red: 0.984, green: 0.980, blue: 0.972, alpha: 1)
}

extension Color {
    /// The app's single background surface: a quiet off-white in light
    /// appearance, an off-black in dark appearance. Matches the website's
    /// own token choice (`--color-bg: #ffffff` was rejected there too in
    /// favor of a warm near-white/near-black pair) and the general
    /// principle that pure `#ffffff`/`#000000` reads as flat and synthetic
    /// next to real ink and paper. Defined once here rather than inline at
    /// each call site so every surface (Onboarding, Observation Sheet,
    /// Settings) and the window chrome itself share exactly one value.
    static let qaptrSurface = Color(nsColor: NSColor(name: nil, dynamicProvider: qaptrSurfaceNSColor))
}
