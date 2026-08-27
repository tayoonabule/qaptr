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
            .foregroundStyle(Color.qaptrFigmaText)
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

/// Figma's custom in-content title bar (node `16:5594`, 845×32): a
/// `rgba(255,255,255,0.6)` bar with a `rgba(0,0,0,0.05)` bottom hairline,
/// 8pt window-control inset, and a 14×14 `logo-mini` + 13pt Satoshi-Medium
/// title 8pt to its right. AppKit still owns the real traffic lights (this
/// view never draws its own), so only the title label and hairline are
/// rendered here; the transparent titlebar host places this content over
/// the native controls at the same 8pt inset Figma specifies.
struct QaptrTitleBar: View {
  let title: String

  var body: some View {
    HStack(spacing: 8) {
      QaptrTitleMark(size: 14)
      Text(title)
        .font(QaptrFont.custom(13, weight: .medium))
        .foregroundStyle(Color.qaptrLabelPrimary)
    }
    // 8pt top/bottom padding centers the 14pt content in the 32pt bar. The
    // 84pt leading inset in Figma is `8 (controls inset) + 60 (traffic
    // light cluster width) + 16 (gap)`; AppKit's real traffic lights
    // already occupy that space, so only the remaining leading gap is
    // added here.
    .padding(.leading, 84)
    .padding(.vertical, 8)
    .frame(height: 32, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.qaptrFigmaTitlebar)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.qaptrFigmaHairline).frame(height: 1)
    }
  }
}

/// The onboarding title bar (Figma node `27:1035`, 845×31): no logo mark,
/// a bold SF Pro title, and no background fill (unlike the post-onboarding
/// `QaptrTitleBar`, which adds the `rgba(255,255,255,0.6)` wash and the
/// 14×14 logo-mini). Kept separate rather than parameterizing one view
/// because the two frames differ in font, height, and whether a logo mark
/// is present at all, not just in copy.
struct QaptrOnboardingTitleBar: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(Color.qaptrLabelPrimary)
      .padding(.leading, 84)
      .frame(height: 31, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .bottom) {
        Rectangle().fill(Color.qaptrFigmaHairline).frame(height: 1)
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
