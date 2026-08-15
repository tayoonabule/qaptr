import SwiftUI

/// Qaptr's shared design tokens for the native utility surfaces.
///
/// The native app intentionally stays on the light product canvas: white
/// surfaces, hairline borders, compact 4pt spacing, and one blue interaction
/// accent. Cards use borders rather than decorative gradients or heavy shadow.
enum QaptrHex {
    static let canvasWhite = NSColor(qaptrHex: 0xFF_FF_FF)
    static let paperMist = NSColor(qaptrHex: 0xF5_F5_F5)
    static let ash = NSColor(qaptrHex: 0xE5_E5_E5)
    static let smoke = NSColor(qaptrHex: 0xD4_D4_D4)
    static let pebble = NSColor(qaptrHex: 0xC8_C8_C8)
    static let midnightInk = NSColor(qaptrHex: 0x0A_0A_0A)
    static let charcoal = NSColor(qaptrHex: 0x17_17_17)
    static let graphite = NSColor(qaptrHex: 0x26_26_26)
    static let slate = NSColor(qaptrHex: 0x40_40_40)
    static let steel = NSColor(qaptrHex: 0x52_52_52)
    static let fog = NSColor(qaptrHex: 0x73_73_73)
    static let silver = NSColor(qaptrHex: 0xA3_A3_A3)
    static let electricBlue = NSColor(qaptrHex: 0x25_63_EB)
    static let deepSapphire = NSColor(qaptrHex: 0x1E_40_AF)
    static let softMint = NSColor(qaptrHex: 0xDC_FC_E7)
    static let vividGreen = NSColor(qaptrHex: 0x16_A3_4A)
    static let tangerine = NSColor(qaptrHex: 0xEA_58_0C)
    static let lavender = NSColor(qaptrHex: 0x7C_3A_ED)
    static let error = NSColor(qaptrHex: 0xB4_23_18)
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

private func qaptrDynamicColor(light: NSColor, dark: NSColor) -> Color {
    // Qaptr is deliberately a white-canvas utility app. Keeping the dynamic
    // factory preserves the AppKit/SwiftUI boundary without introducing a
    // second visual theme that is outside the product design system.
    _ = dark
    return Color(nsColor: light)
}

/// The AppKit window surface. The content and titlebar always share the same
/// white canvas, so no system gray can leak through around the traffic lights.
func qaptrSurfaceNSColor(appearance: NSAppearance) -> NSColor {
    _ = appearance
    return QaptrHex.canvasWhite
}

extension Color {
    static let qaptrSurface = qaptrDynamicColor(light: QaptrHex.canvasWhite, dark: QaptrHex.canvasWhite)
    static let qaptrSurfaceRaised = Color(nsColor: QaptrHex.paperMist)
    static let qaptrPaperMist = Color(nsColor: QaptrHex.paperMist)
    static let qaptrInk = Color(nsColor: QaptrHex.charcoal)
    static let qaptrInkSoft = Color(nsColor: QaptrHex.steel)
    static let qaptrInkMuted = Color(nsColor: QaptrHex.fog)
    static let qaptrSlate = Color(nsColor: QaptrHex.slate)
    static let qaptrHairline = Color(nsColor: QaptrHex.ash)
    static let qaptrBorderStrong = Color(nsColor: QaptrHex.smoke)
    static let qaptrInputBorder = Color(nsColor: QaptrHex.midnightInk)
    static let qaptrAccent = Color(nsColor: QaptrHex.electricBlue)
    static let qaptrAccentStrong = Color(nsColor: QaptrHex.deepSapphire)
    static let qaptrAccentInk = Color.white
    static let qaptrPrimaryAction = Color(nsColor: QaptrHex.midnightInk)
    static let qaptrSuccess = Color(nsColor: QaptrHex.vividGreen)
    static let qaptrSoftMint = Color(nsColor: QaptrHex.softMint)
    static let qaptrWarning = Color(nsColor: QaptrHex.tangerine)
    static let qaptrLavender = Color(nsColor: QaptrHex.lavender)
    static let qaptrError = Color(nsColor: QaptrHex.error)

    // Compatibility names used by the existing state and accessibility copy.
    static let qaptrAccentTint = Color(nsColor: QaptrHex.electricBlue).opacity(0.10)
    static let qaptrAccentTintStrong = Color(nsColor: QaptrHex.electricBlue).opacity(0.16)
    static let qaptrLive = Color(nsColor: QaptrHex.vividGreen)
}

enum QaptrRadius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let feature: CGFloat = 16
    static let input: CGFloat = 6
}

/// The compact 4pt spacing scale used by every native surface.
enum QaptrSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// Satoshi-like medium display voice with a system sans body voice.
enum QaptrType {
    static func display(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func headline(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func title(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium)
    }

    static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size)
    }

    static func meta(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

enum QaptrMotion {
    static func easeOut(_ duration: Double = 0.2) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    static let press = Animation.easeOut(duration: 0.12)
}

/// A real product card surface: white fill, one ash border, no decorative
/// elevation. The component keeps padding and radius consistent everywhere.
struct QaptrCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = QaptrSpace.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
                    .strokeBorder(Color.qaptrHairline, lineWidth: 1)
            }
    }
}
