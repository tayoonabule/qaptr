import AppKit
import SwiftUI

/// The shared website wordmark, backed by the same aperture-outline SVG used
/// by the public site rather than a platform-specific substitute.
struct QaptrBrandLogo: View {
  var iconSize: CGFloat = 28
  var textSize: CGFloat = 24

  var body: some View {
    HStack(spacing: 8) {
      if let image = NSImage(data: QaptrReviewLogoResources.aperture) {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: iconSize, height: iconSize)
      }

      Text("Qaptr")
        .font(.system(size: textSize, weight: .medium, design: .default))
        .tracking(-textSize * 0.02)
        .foregroundStyle(Color.qaptrInk)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Qaptr")
  }
}

private enum QaptrReviewLogoResources {
  static let aperture: Data = {
    guard let url = Bundle.main.url(forResource: "QaptrAperture", withExtension: "svg")
      ?? Bundle.module.url(forResource: "QaptrAperture", withExtension: "svg"),
      let data = try? Data(contentsOf: url)
    else {
      return Data()
    }
    return data
  }()
}
