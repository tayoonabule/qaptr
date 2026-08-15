import SwiftUI

/// Qaptr's shared design tokens: color, type, space, and motion.
///
/// Every color value here is the exact sRGB conversion of the OKLCH palette
/// defined once in `web/src/styles/tokens.css` (paper `oklch(100% 0 0)` /
/// dark `oklch(9% 0 0)`, accent `oklch(72% 0.16 65)` warm amber). The app and
/// the website are not "inspired by" the same palette -- they render the
/// same numbers, so a person moving between the marketing site and the
/// native app sees one continuous surface rather than two loosely matched
/// ones.
///
/// Typography mirrors the website's two-voice pairing: a serif display face
/// (New York, matching the web's `--font-serif`) for titles the person reads
/// as a heading, and the system sans for everything they read as an
/// instruction or a control label. A monospaced caps voice marks the small
/// section eyebrows, matching the website's `--font-mono` metadata role.
enum QaptrHex {
    // Light
    static let paperLight = NSColor(qaptrHex: 0xFF_FF_FF)
    static let paperLight2 = NSColor(qaptrHex: 0xF5_F5_F5)
    static let inkLight = NSColor(qaptrHex: 0x16_16_16)
    static let inkSoftLight = NSColor(qaptrHex: 0x55_55_55)
    static let hairlineLight = NSColor(qaptrHex: 0xD7_D7_D7)
    static let accentInkLight = NSColor(qaptrHex: 0x4E_1E_00)

    // Dark
    static let paperDark = NSColor(qaptrHex: 0x02_02_02)
    static let paperDark2 = NSColor(qaptrHex: 0x09_09_09)
    static let inkDark = NSColor(qaptrHex: 0xEE_EE_EE)
    static let inkSoftDark = NSColor(qaptrHex: 0x98_98_98)
    static let hairlineDark = NSColor(qaptrHex: 0x24_24_24)
    static let accentInkDark = NSColor(qaptrHex: 0xFC_C0_87)

    // Theme-invariant
    static let accent = NSColor(qaptrHex: 0xE7_8C_08)
    static let error = NSColor(qaptrHex: 0xBA_2B_2E)
}

private extension NSColor {
    convenience init(qaptrHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func qaptrIsDarkAppearance(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

private func qaptrDynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { qaptrIsDarkAppearance($0) ? dark : light }))
}

/// A single dynamic NSColor factory shared by the SwiftUI `Color.qaptrSurface`
/// token below and the AppKit window setup in `QaptrReviewApp.swift`, so the
/// transparent titlebar and the SwiftUI content beneath it always agree.
func qaptrSurfaceNSColor(appearance: NSAppearance) -> NSColor {
    qaptrIsDarkAppearance(appearance) ? QaptrHex.paperDark : QaptrHex.paperLight
}

extension Color {
    /// The app's base window surface. Numerically identical to the
    /// website's `--color-paper`.
    static let qaptrSurface = qaptrDynamicColor(light: QaptrHex.paperLight, dark: QaptrHex.paperDark)

    /// A barely-distinct raised surface, used only for the rare place a
    /// control needs to read as a distinct hit target (e.g. a hovered row).
    /// Never used to draw a card or a panel.
    static let qaptrSurfaceRaised = qaptrDynamicColor(light: QaptrHex.paperLight2, dark: QaptrHex.paperDark2)

    /// Primary text.
    static let qaptrInk = qaptrDynamicColor(light: QaptrHex.inkLight, dark: QaptrHex.inkDark)

    /// Secondary text: detail lines, captions, inactive state.
    static let qaptrInkSoft = qaptrDynamicColor(light: QaptrHex.inkSoftLight, dark: QaptrHex.inkSoftDark)

    /// The one rule used by every divider in the app. No boxes, no card
    /// borders -- sections are separated by this hairline alone.
    static let qaptrHairline = qaptrDynamicColor(light: QaptrHex.hairlineLight, dark: QaptrHex.hairlineDark)

    /// The one warm accent: selection, progress, and the one deliberate
    /// primary action per screen. Matches the website's `--color-accent`
    /// exactly and does not shift between light and dark.
    static let qaptrAccent = Color(nsColor: QaptrHex.accent)

    /// The ink color used *on top of* an accent-filled surface (a primary
    /// button's label). Matches the website's `--color-accent-ink` pairing.
    static let qaptrAccentInk = qaptrDynamicColor(light: QaptrHex.accentInkLight, dark: QaptrHex.accentInkDark)

    /// The one error color, used only for an actual failure message.
    static let qaptrError = Color(nsColor: QaptrHex.error)
}

/// The 4pt spacing scale, sized for a compact utility window rather than the
/// website's marketing canvas.
enum QaptrSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// The three-voice type system: serif display, system body, mono meta.
enum QaptrType {
    /// A page-level title (the Observation Sheet's or an onboarding stage's
    /// headline). New York, matching the website's display voice.
    static func display(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// A dialog or detail-sheet title.
    static func headline(_ size: CGFloat = 19) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// A section or row title in the system sans.
    static func title(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Ordinary reading text.
    static func body(_ size: CGFloat = 13.5) -> Font {
        .system(size: size)
    }

    /// A short secondary line beneath a title.
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size)
    }

    /// A tracked, uppercase section eyebrow in the mono meta voice, matching
    /// the website's `--font-mono` metadata role.
    static func meta(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// The one named easing used by every state change in the app, matching the
/// website's `--ease-out`. There is no second easing and no spring: a
/// structural surface switch (Observation Sheet <-> Settings, one onboarding
/// stage to the next) crossfades on this curve; nothing bounces.
enum QaptrMotion {
    static func easeOut(_ duration: Double = 0.2) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    /// The single press-feedback duration shared by every button style.
    static let press = Animation.easeOut(duration: 0.12)
}
