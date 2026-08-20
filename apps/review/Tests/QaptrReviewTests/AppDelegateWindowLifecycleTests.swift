import AppKit
@testable import QaptrReview
import XCTest

@MainActor
final class AppDelegateWindowLifecycleTests: XCTestCase {
    func testClosedMainWindowReopensWithTheSameSessionModel() throws {
        let application = NSApplication.shared
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
        let delegate = AppDelegate()
        let originalModel = delegate.model

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let window = try XCTUnwrap(
            application.windows.first { !existingWindows.contains(ObjectIdentifier($0)) }
        )
        XCTAssertTrue(window.isVisible)

        window.performClose(nil)
        XCTAssertFalse(window.isVisible)

        delegate.showMainWindow()
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(delegate.model === originalModel)

        window.close()
    }
}
