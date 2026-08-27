import AppKit
import SwiftUI

/// Shared Qaptr brand mark. The full wordmark is used on spacious surfaces;
/// compact chrome uses the aperture mark plus a text label to match the Figma
/// title-bar geometry.
struct QaptrBrandLogo: View {
  var iconSize: CGFloat = 28
  var textSize: CGFloat = 24
  var wordmark: Bool = false

  var body: some View {
    Group {
      if wordmark, let image = NSImage(data: QaptrReviewLogoResources.wordmark) {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: 140, height: 51)
      } else {
        HStack(spacing: 8) {
          if let image = NSImage(data: QaptrReviewLogoResources.aperture) {
            Image(nsImage: image)
              .resizable()
              .interpolation(.high)
              .scaledToFit()
              .frame(width: iconSize, height: iconSize)
          }
          Text("Qaptr")
            .font(QaptrFont.custom(textSize, weight: .medium))
            .tracking(-textSize * 0.02)
            .foregroundStyle(Color.qaptrInk)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Qaptr")
  }
}

/// The compact "logo-mini" mark used in Figma's custom title bar (nodes
/// `16:5600` / `29:...`), 14×14 by default. Distinct from `QaptrBrandLogo`,
/// which always pairs the icon with the literal word "Qaptr" and cannot
/// carry a per-surface title like "Qaptr Home" or "Qaptr Settings".
struct QaptrTitleMark: View {
  var size: CGFloat = 14

  var body: some View {
    if let image = NSImage(data: QaptrReviewLogoResources.aperture) {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .frame(width: size, height: size)
    }
  }
}

private enum QaptrReviewLogoResources {
  static let aperture: Data = load("QaptrAperture")
  static let wordmark: Data = load("qaptr_logo")

  private static func load(_ name: String) -> Data {
    guard
      let url = Bundle.main.url(forResource: name, withExtension: "svg")
        ?? Bundle.module.url(forResource: name, withExtension: "svg"),
      let data = try? Data(contentsOf: url)
    else {
      return Data()
    }
    return data
  }
}

/// Renders an exported Figma SVG without rebuilding its path geometry in
/// SwiftUI. This keeps vector boundaries authoritative and lets package
/// resources remain the single source of truth for small brand icons.
struct QaptrSVGImage: View {
  let resourceName: String

  var body: some View {
    if let image = NSImage(data: resourceData) {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
    }
  }

  private var resourceData: Data {
    guard let url = Bundle.module.url(forResource: resourceName, withExtension: "svg") else {
      return Data()
    }
    return (try? Data(contentsOf: url)) ?? Data()
  }
}
