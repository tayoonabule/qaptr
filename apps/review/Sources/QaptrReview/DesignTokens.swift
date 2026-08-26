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
  static let qaptrInkSoft = Color(nsColor: QaptrHex.steel)
  static let qaptrInkMuted = Color(nsColor: QaptrHex.fog)
  static let qaptrSlate = Color(nsColor: QaptrHex.slate)
  static let qaptrHairline = Color(nsColor: QaptrHex.ash)
  static let qaptrBorderStrong = Color(nsColor: QaptrHex.smoke)
  static let qaptrInputBorder = Color(nsColor: QaptrHex.midnightInk)
  static let qaptrAccent = Color(nsColor: QaptrHex.electricBlue)
  static let qaptrAccentStrong = Color(nsColor: QaptrHex.deepSapphire)
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
  static let qaptrWarning = Color(nsColor: QaptrHex.tangerine)
  static let qaptrLavender = Color(nsColor: QaptrHex.lavender)
  static let qaptrError = Color(nsColor: QaptrHex.error)

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
  static let feature: CGFloat = 16
  static let input: CGFloat = 6
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
}

enum QaptrControlMetrics {
  static let height: CGFloat = 44
}

/// A crisp system sans display voice with a system sans body voice. The native
/// app should feel precise and editorial, not soft or toy-like.
enum QaptrType {
  /// Distinct editorial display role. New York is a native macOS serif and
  /// safely falls back to the platform system serif when unavailable.
  static func editorial(_ size: CGFloat = 30) -> Font {
    .system(size: size, weight: .regular, design: .serif)
  }

  static func display(_ size: CGFloat = 30) -> Font {
    editorial(size)
  }

  static func headline(_ size: CGFloat = 20) -> Font {
    .system(size: size, weight: .medium, design: .default)
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
  static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
  /// Deliberately slower than a spring for whole-surface navigation. The
  /// opacity component in each transition keeps the handoff calm instead of
  /// making two opaque canvases collide during the move.
  static let navigation = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.38)
}

/// A quiet animated macOS glass backdrop. The color movement is intentionally
/// slow and low contrast so it gives the window depth without becoming a
/// decorative distraction.
struct QaptrGlassBackdrop<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewBuilder let content: Content
  @State private var isSettled = false

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      Color.qaptrGlassCanvas.ignoresSafeArea()

      Circle()
        .fill(Color.qaptrAccent.opacity(0.16))
        .frame(width: 420, height: 420)
        .blur(radius: 90)
        .offset(x: isSettled ? 260 : 170, y: isSettled ? -240 : -180)

      Circle()
        .fill(Color.qaptrTeal.opacity(0.12))
        .frame(width: 360, height: 360)
        .blur(radius: 100)
        .offset(x: isSettled ? -280 : -210, y: isSettled ? 250 : 190)

      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()

      content
    }
    .task {
      guard !reduceMotion else { return }
      withAnimation(QaptrMotion.spring.repeatForever(autoreverses: true)) {
        isSettled = true
      }
    }
  }
}

/// A reusable floating glass panel. It carries the depth, edge highlight, and
/// shadow language that makes the utility feel native instead of like a flat
/// document pasted into an AppKit window.
struct QaptrGlassPanel<Content: View>: View {
  let padding: CGFloat
  @ViewBuilder let content: Content

  init(padding: CGFloat = QaptrSpace.xl, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: QaptrRadius.feature, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: QaptrRadius.feature, style: .continuous)
          .strokeBorder(
            LinearGradient(
              colors: [Color.white.opacity(0.82), Color.qaptrHairline.opacity(0.55)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      }
      .shadow(color: Color.black.opacity(0.10), radius: 28, y: 14)
  }
}

/// A compact glass treatment for sheets and popover-sized utility surfaces.
/// Unlike `QaptrGlassPanel`, this keeps the radius and padding small enough for
/// secondary flows while retaining the same edge highlight as the main app.
struct QaptrSecondarySurface<Content: View>: View {
  let padding: CGFloat
  @ViewBuilder let content: Content

  init(padding: CGFloat = QaptrSpace.xl, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(
            LinearGradient(
              colors: [Color.white.opacity(0.88), Color.qaptrHairline.opacity(0.62)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      }
      .shadow(color: Color.black.opacity(0.12), radius: 24, y: 12)
  }
}

/// A real product card surface with a translucent material base and one
/// restrained highlight. Existing callers keep the same API while inheriting
/// the new visual language.
struct QaptrCard<Content: View>: View {
  let padding: CGFloat
  @ViewBuilder let content: Content

  init(padding: CGFloat = QaptrSpace.xl, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background(
        .thinMaterial, in: RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
          .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.055), radius: 14, y: 7)
  }
}
