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
      if style == .native && !reduceTransparency {
        shape
          .fill(.clear)
          .glassEffect(.regular, in: shape)
          .overlay { shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 0.7) }
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
      .fill(opaque ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
      .glassEffect(opaque ? .identity : .clear, in: shape)
      .overlay {
        if !opaque {
          shape
            .fill(QaptrColor.figmaGlassLight)
            .blendMode(.lighten)
        }
      }
      .overlay {
        if !opaque {
          shape
            .fill(QaptrColor.figmaGlassDark)
            .blendMode(.darken)
        }
      }
      .overlay {
        if !opaque {
          shape
            .fill(QaptrColor.figmaGlassMultiply)
            .blendMode(.multiply)
        }
      }
      .overlay {
        shape.strokeBorder(QaptrColor.figmaGlassBorder.opacity(0.9), lineWidth: 0.5)
      }
      .overlay {
        shape
          .strokeBorder(
            LinearGradient(
              stops: [
                .init(color: .white.opacity(0.92), location: 0),
                .init(color: .white.opacity(0.28), location: 0.48),
                .init(color: QaptrColor.ink.opacity(0.14), location: 1),
              ],
              startPoint: .top,
              endPoint: .bottom
            ),
            lineWidth: 1
          )
      }
      .overlay {
        RadialGradient(
          colors: [.white.opacity(0.26), .white.opacity(0.07), .clear],
          center: UnitPoint(x: 0.18, y: -0.08),
          startRadius: 0,
          endRadius: 260
        )
        .blendMode(.screen)
        .clipShape(shape)
      }
      .overlay {
        VStack(spacing: 0) {
          LinearGradient(
            colors: [QaptrColor.ink.opacity(0.08), .clear],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 16)
          Spacer(minLength: 0)
          LinearGradient(
            colors: [.clear, QaptrColor.ink.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 18)
        }
        .clipShape(shape)
      }
      .shadow(color: .black.opacity(0.095), radius: 16, y: 12)
      .shadow(color: .black.opacity(0.035), radius: 2, y: 1)
      .shadow(color: .white.opacity(0.42), radius: 1, y: -1)
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
