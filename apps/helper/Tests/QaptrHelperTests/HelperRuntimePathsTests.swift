import Foundation
import XCTest
@testable import QaptrHelperCore

final class HelperRuntimePathsTests: XCTestCase {
    func testReviewApplicationResolvesFromPackagedLoginItemLayout() {
        let helper = URL(
            fileURLWithPath:
                "/Applications/Qaptr.app/Contents/Applications/QaptrReview.app/Contents/Library/LoginItems/QaptrHelper.app",
            isDirectory: true
        )
        let expected = URL(
            fileURLWithPath: "/Applications/Qaptr.app/Contents/Applications/QaptrReview.app",
            isDirectory: true
        )

        let resolved = HelperRuntimePaths.reviewApplicationURL(
            environment: [:],
            helperBundleURL: helper,
            fileExists: { $0 == expected.path }
        )

        XCTAssertEqual(resolved, expected)
    }

    func testReviewApplicationHonorsAnExistingExplicitOverride() {
        let expected = URL(fileURLWithPath: "/Test/QaptrReview.app", isDirectory: true)
        let resolved = HelperRuntimePaths.reviewApplicationURL(
            environment: ["QAPTR_REVIEW_APP_PATH": expected.path],
            helperBundleURL: URL(fileURLWithPath: "/Standalone/QaptrHelper.app", isDirectory: true),
            fileExists: { $0 == expected.path }
        )
        XCTAssertEqual(resolved, expected)
    }

    func testReviewApplicationRejectsStandaloneOrMissingBundles() {
        XCTAssertNil(
            HelperRuntimePaths.reviewApplicationURL(
                environment: [:],
                helperBundleURL: URL(fileURLWithPath: "/Standalone/QaptrHelper.app", isDirectory: true),
                fileExists: { _ in false }
            )
        )
    }
}
