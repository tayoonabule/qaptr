import SwiftUI

enum QaptrColor {
  static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
  static let ink = Color(red: 35 / 255, green: 35 / 255, blue: 35 / 255)
  static let secondaryInk = Color(red: 68 / 255, green: 68 / 255, blue: 68 / 255)
  static let muted = Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255)
  static let success = Color(red: 31 / 255, green: 153 / 255, blue: 85 / 255)
  static let warning = Color(red: 214 / 255, green: 139 / 255, blue: 25 / 255)
  static let danger = Color(red: 208 / 255, green: 56 / 255, blue: 56 / 255)

  static let figmaGlassLight = Color.white.opacity(0.25)
  static let figmaGlassDark = Color(white: 191 / 255).opacity(0.08)
  static let figmaGlassMultiply = Color.white.opacity(0.10)
  static let figmaGlassBorder = Color(white: 219 / 255)
}

enum QaptrSpacing {
  static let xSmall: CGFloat = 4
  static let small: CGFloat = 8
  static let medium: CGFloat = 16
  static let large: CGFloat = 24
  static let xLarge: CGFloat = 32
}

enum QaptrRadius {
  static let button: CGFloat = 12
  static let chip: CGFloat = 100
  static let card: CGFloat = 24
}

enum QaptrType {
  static let title = Font.system(size: 26, weight: .regular)
  static let heading = Font.system(size: 15, weight: .semibold)
  static let body = Font.system(size: 13, weight: .regular)
  static let caption = Font.system(size: 11, weight: .medium)
}

enum QaptrMotion {
  static func animation(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.14)
  }
}

struct QaptrCanvas: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.white
        RadialGradient(
          colors: [Color(red: 0.78, green: 0.82, blue: 0.90), .white],
          center: UnitPoint(x: 0.5, y: 1.03),
          startRadius: 0,
          endRadius: max(proxy.size.width, proxy.size.height) * 0.72
        )
      }
    }
    .ignoresSafeArea()
  }
}
