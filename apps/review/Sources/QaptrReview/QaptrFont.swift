import CoreText
import Foundation
import SwiftUI

enum QaptrFont {
  static let familyName = "Satoshi Variable"

  static func register() {
    guard let url = Bundle.module.url(forResource: "Satoshi-Variable", withExtension: "ttf") else {
      return
    }
    var error: Unmanaged<CFError>?
    _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
  }

  static func custom(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .custom(familyName, size: size).weight(weight)
  }
}
