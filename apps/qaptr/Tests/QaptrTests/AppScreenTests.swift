import Testing
@testable import Qaptr

@Test func figmaStateInventoryIsComplete() {
  #expect(AppScreen.allCases.count == 26)
  #expect(Set(AppScreen.allCases.map(\.title)).count == 26)
}

@Test func exportedSurfaceFamiliesAreRepresented() {
  let screens = Set(AppScreen.allCases)
  #expect(screens.contains(.setupPermission))
  #expect(screens.contains(.homeFindings))
  #expect(screens.contains(.consentReview))
  #expect(screens.contains(.settingsNeverCapture))
  #expect(screens.contains(.findingCorrection))
  #expect(screens.contains(.menuApproval))
  #expect(screens.contains(.toastSpec))
}
