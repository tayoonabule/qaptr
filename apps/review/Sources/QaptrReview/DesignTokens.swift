import SwiftUI

// Hallmark · studied-DNA: Micro live-site · macrostructure: workbench ledger
// Pre-emit critique: philosophy 5 · hierarchy 5 · execution 4 · specificity 5 · restraint 5 · variety 4

/// Qaptr's shared design tokens for the native utility surfaces.
///
/// The palette follows Micro's warm-paper work plane with an Azure-to-Teal
/// signal. Existing names remain intentionally stable because settings,
/// onboarding, and provider sheets consume this compatibility surface.
enum QaptrHex {
  static let canvasWhite = NSColor(qaptrHex: 0xF8_FA_FB)
  static let paperMist = NSColor(qaptrHex: 0xEE_F3_F5)
  static let ash = NSColor(qaptrHex: 0xD9_E3_E7)
  static let smoke = NSColor(qaptrHex: 0xBF_CE_D3)
  static let pebble = NSColor(qaptrHex: 0xA8_B9_BF)
  static let midnightInk = NSColor(qaptrHex: 0x12_2B_35)
  static let charcoal = NSColor(qaptrHex: 0x1D_38_42)
  static let graphite = NSColor(qaptrHex: 0x31_4D_57)
  static let slate = NSColor(qaptrHex: 0x4A_62_69)
  static let steel = NSColor(qaptrHex: 0x5E_72_76)
  static let fog = NSColor(qaptrHex: 0x7B_8A_8B)
  static let silver = NSColor(qaptrHex: 0xA7_B1_AE)
  static let electricBlue = NSColor(qaptrHex: 0x1B_77_F2)
  static let deepSapphire = NSColor(qaptrHex: 0x0E_55_BB)
  static let softMint = NSColor(qaptrHex: 0xD7_F0_E8)
  static let vividGreen = NSColor(qaptrHex: 0x0B_8F_7A)
  static let tangerine = NSColor(qaptrHex: 0xD9_6B_38)
  static let lavender = NSColor(qaptrHex: 0x6D_66_B2)
  static let error = NSColor(qaptrHex: 0xB4_23_18)
  static let teal = NSColor(qaptrHex: 0x00_9E_9A)
  // Figma Main App variables.
  static let figmaPrimary = NSColor(qaptrHex: 0x00_88_FF)
  static let figmaOrange = NSColor(qaptrHex: 0xFF_8D_28)
  static let figmaRed = NSColor(qaptrHex: 0xFF_38_3C)
  static let figmaSecondaryFill = NSColor(qaptrHex: 0xE6_E6_E6)
  // Literal fill on the onboarding "Primary CTA Button" layer (Figma nodes
  // 27:1207 / 27:1214). It is a distinct action blue from `figmaPrimary` and
  // is not backed by a Figma variable, only a hardcoded layer fill.
  static let figmaActionBlue = NSColor(qaptrHex: 0x25_63_EB)
}

extension NSColor {
  fileprivate convenience init(qaptrHex hex: UInt32) {
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
  // Keep the content surface transparent so materials can sample the
  // window's gradient. The AppKit window still supplies a white fallback.
  static let qaptrSurface = Color.clear
  static let qaptrGlassCanvas = Color(nsColor: QaptrHex.canvasWhite)
  static let qaptrSurfaceRaised = Color(nsColor: QaptrHex.paperMist)
  static let qaptrPaperMist = Color(nsColor: QaptrHex.paperMist)
  static let qaptrInk = Color(nsColor: QaptrHex.charcoal)
  static let qaptrLabelPrimary = Color.black.opacity(0.85)
  static let qaptrLabelSecondary = Color.black.opacity(0.62)
  static let qaptrFillSecondary = Color(nsColor: QaptrHex.figmaSecondaryFill)
  static let qaptrInkSoft = Color(nsColor: QaptrHex.steel)
  static let qaptrInkMuted = Color(nsColor: QaptrHex.fog)
  static let qaptrSlate = Color(nsColor: QaptrHex.slate)
  static let qaptrHairline = Color(nsColor: QaptrHex.ash)
  static let qaptrBorderStrong = Color(nsColor: QaptrHex.smoke)
  static let qaptrInputBorder = Color(nsColor: QaptrHex.midnightInk)
  static let qaptrAccent = Color(nsColor: QaptrHex.figmaPrimary)
  static let qaptrAccentStrong = Color(nsColor: QaptrHex.deepSapphire)
  // The onboarding "Primary CTA Button" fill (Figma nodes 27:1207 / 27:1214).
  // Kept distinct from `qaptrAccent` because Figma's Liquid Glass buttons use
  // this specific action blue, not the app's `Accents/Blue` variable.
  static let qaptrCTAAction = Color(nsColor: QaptrHex.figmaActionBlue)
  static let qaptrSignalGradient = LinearGradient(
    colors: [
      Color(nsColor: QaptrHex.electricBlue), Color(red: 0.302, green: 0.608, blue: 1.0),
      Color(nsColor: QaptrHex.teal),
    ],
    startPoint: .leading,
    endPoint: .trailing
  )
  static let qaptrAccentInk = Color.white
  static let qaptrPrimaryAction = Color(nsColor: QaptrHex.midnightInk)
  static let qaptrSuccess = Color(nsColor: QaptrHex.vividGreen)
  static let qaptrSoftMint = Color(nsColor: QaptrHex.softMint)
  static let qaptrWarning = Color(nsColor: QaptrHex.figmaOrange)
  static let qaptrLavender = Color(nsColor: QaptrHex.lavender)
  static let qaptrError = Color(nsColor: QaptrHex.figmaRed)
  // Main App Figma surface tokens. Keep repeated layer values centralized so
  // the presentation can stay tokenized instead of scattering color literals.
  static let qaptrFigmaCanvasBlue = Color(nsColor: NSColor(qaptrHex: 0xC7_D1_E6))
  static let qaptrFigmaCanvasWhite = Color.white
  static let qaptrFigmaCardLight = Color.white.opacity(0.25)
  static let qaptrFigmaCardDark = Color(nsColor: NSColor(qaptrHex: 0xBF_BF_BF)).opacity(0.08)
  static let qaptrFigmaCardMultiply = Color.white.opacity(0.10)
  static let qaptrFigmaCardBorder = Color(nsColor: NSColor(qaptrHex: 0xDB_DB_DB))
  static let qaptrFigmaText = Color(nsColor: NSColor(qaptrHex: 0x11_18_27))
  static let qaptrFigmaBody = Color(nsColor: NSColor(qaptrHex: 0x4B_55_63))
  static let qaptrFigmaMuted = Color(nsColor: NSColor(qaptrHex: 0x64_74_8B))
  static let qaptrFigmaAction = Color(nsColor: NSColor(qaptrHex: 0x25_63_EB))
  static let qaptrFigmaToolbar = Color.black.opacity(0.03)
  static let qaptrFigmaTitlebar = Color.white.opacity(0.60)
  static let qaptrFigmaHairline = Color.black.opacity(0.05)

  // Compatibility names used by the existing state and accessibility copy.
  static let qaptrAccentTint = Color(nsColor: QaptrHex.electricBlue).opacity(0.10)
  static let qaptrAccentTintStrong = Color(nsColor: QaptrHex.electricBlue).opacity(0.16)
  static let qaptrLive = Color(nsColor: QaptrHex.vividGreen)
  static let qaptrTeal = Color(nsColor: QaptrHex.teal)
  static let qaptrPaper = Color(nsColor: QaptrHex.canvasWhite)
}

enum QaptrRadius {
  static let control: CGFloat = 8
  static let card: CGFloat = 12
  static let cta: CGFloat = 12
  static let feature: CGFloat = 16
  static let glass: CGFloat = 24
  static let input: CGFloat = 6
  static let secondarySurface: CGFloat = 20
}

/// The compact 4pt spacing scale used by every native surface.
enum QaptrSpace {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 6
  static let sm: CGFloat = 10
  static let md: CGFloat = 14
  static let lg: CGFloat = 20
  static let xl: CGFloat = 28
  static let xxl: CGFloat = 40
  static let xxxl: CGFloat = 56

  // Semantic aliases retain the established scale while making intent clear.
  static let section: CGFloat = xl
  static let page: CGFloat = xxl
  static let hero: CGFloat = xxxl
}

enum QaptrControlMetrics {
  static let height: CGFloat = 44
}

/// A crisp system sans display voice with a system sans body voice. The native
/// app should feel precise and editorial, not soft or toy-like.
enum QaptrType {
  enum Size {
    static let display: CGFloat = 30
    static let headline: CGFloat = 20
    static let title: CGFloat = 14
    static let body: CGFloat = 14
    static let caption: CGFloat = 12
    static let meta: CGFloat = 11
  }

  enum Weight {
    static let regular: Font.Weight = .regular
    static let medium: Font.Weight = .medium
    static let semibold: Font.Weight = .semibold
  }

  /// Distinct editorial display role. New York is a native macOS serif and
  /// safely falls back to the platform system serif when unavailable.
  static func editorial(_ size: CGFloat = Size.display) -> Font {
    QaptrFont.custom(size)
  }

  static func display(_ size: CGFloat = Size.display) -> Font {
    editorial(size)
  }

  static func headline(_ size: CGFloat = Size.headline) -> Font {
    QaptrFont.custom(size, weight: Weight.medium)
  }

  static func title(_ size: CGFloat = Size.title) -> Font {
    QaptrFont.custom(size, weight: Weight.medium)
  }

  static func body(_ size: CGFloat = Size.body) -> Font {
    QaptrFont.custom(size)
  }

  static func caption(_ size: CGFloat = Size.caption) -> Font {
    QaptrFont.custom(size)
  }

  static func meta(_ size: CGFloat = Size.meta) -> Font {
    QaptrFont.custom(size, weight: Weight.semibold)
  }
}

/// Shared edge and shadow values for the Figma glass surfaces.
enum QaptrEffect {
  static let hairlineWidth: CGFloat = 1
  static let glassHighlightOpacity: Double = 0.82
  static let glassHairlineOpacity: Double = 0.55
  static let secondaryHighlightOpacity: Double = 0.88
  static let secondaryHairlineOpacity: Double = 0.62
  static let cardHighlightOpacity: Double = 0.62
  static let panelShadowOpacity: Double = 0.10
  static let panelShadowRadius: CGFloat = 28
  static let panelShadowY: CGFloat = 14
  static let secondaryShadowOpacity: Double = 0.12
  static let secondaryShadowRadius: CGFloat = 24
  static let secondaryShadowY: CGFloat = 12
  static let cardShadowOpacity: Double = 0.055
  static let cardShadowRadius: CGFloat = 14
  static let cardShadowY: CGFloat = 7
}

enum QaptrMotion {
  static func easeOut(_ duration: Double = 0.2) -> Animation {
    .timingCurve(0.16, 1, 0.3, 1, duration: duration)
  }

  static let press = Animation.easeOut(duration: 0.12)
  static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
  /// Deliberately slower than a spring for whole-surface navigation. The
  /// opacity component in each transition keeps the handoff calm instead of
  /// making two opaque canvases collide during the move.
  static let navigation = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.38)
}
