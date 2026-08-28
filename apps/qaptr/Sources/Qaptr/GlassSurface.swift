import SwiftUI

enum GlassSurfaceStyle: Equatable, Sendable {
  case automatic
  case native
  case layeredFallback
}

struct GlassSurface: View {
  let radius: CGFloat
  var style: GlassSurfaceStyle = .automatic

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

    Group {
      if style != .layeredFallback && !reduceTransparency {
        shape
          .fill(.clear)
          .glassEffect(
            .clear.tint(Color(red: 0.82, green: 0.88, blue: 0.98).opacity(0.10)),
            in: shape
          )
          .overlay { ExportedGlassLayers(shape: shape) }
      } else {
        LayeredGlassFallback(radius: radius, opaque: reduceTransparency)
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

private struct LayeredGlassFallback: View {
  let radius: CGFloat
  let opaque: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

    shape
      .fill(opaque ? Color(nsColor: .windowBackgroundColor) : Color.white.opacity(0.16))
      .overlay { ExportedGlassLayers(shape: shape, includeFills: !opaque) }
  }
}

private struct ExportedGlassLayers: View {
  let shape: RoundedRectangle
  var includeFills = true

  var body: some View {
    shape
      .fill(
        includeFills
          ? Color(red: 0.88, green: 0.92, blue: 0.98).opacity(0.18)
          : Color.clear
      )
      .overlay {
        if includeFills {
          shape
            .fill(QaptrColor.figmaGlassLight)
            .blendMode(.lighten)
        }
      }
      .overlay {
        if includeFills {
          shape
            .fill(QaptrColor.figmaGlassDark)
            .blendMode(.darken)
        }
      }
      .overlay {
        if includeFills {
          shape
            .fill(QaptrColor.figmaGlassMultiply)
            .blendMode(.multiply)
        }
      }
      .overlay {
        shape.strokeBorder(
          LinearGradient(
            colors: [.white.opacity(0.90), .white.opacity(0.34), QaptrColor.ink.opacity(0.13)],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 0.75
        )
      }
      .shadow(color: Color(red: 0.20, green: 0.26, blue: 0.36).opacity(0.10), radius: 14, y: 9)
      .shadow(color: .white.opacity(0.36), radius: 1, y: -1)
  }
}

extension View {
  func qaptrGlassSurface(
    radius: CGFloat = QaptrRadius.card,
    style: GlassSurfaceStyle = .automatic
  ) -> some View {
    background { GlassSurface(radius: radius, style: style) }
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}
