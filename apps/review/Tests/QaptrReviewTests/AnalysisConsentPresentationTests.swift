import QaptrReviewCore
import XCTest
@testable import QaptrReview

final class AnalysisConsentPresentationTests: XCTestCase {
    func testTextOnlyBoundaryNamesOCRTextAndSaysImagesStayLocal() {
        let summary = ReviewConsentSummary(
            provider: "jcode",
            resolvedModel: nil,
            modelLabel: "Provider default",
            payloadKind: "text",
            captureCount: 41,
            imageCount: 0,
            exclusionCount: 0
        )

        XCTAssertEqual(AnalysisConsentPresentation.payloadLabel(summary), "Privacy-filtered OCR text")
        XCTAssertEqual(
            AnalysisConsentPresentation.privacyExplanation(summary),
            "Qaptr extracted and privacy-filtered text from 41 captures. The provider receives that text, not the images."
        )
    }

    func testFutureImagePayloadIsReportedHonestly() {
        let summary = ReviewConsentSummary(
            provider: "provider",
            resolvedModel: "model",
            modelLabel: "Model",
            payloadKind: "multimodal",
            captureCount: 1,
            imageCount: 1,
            exclusionCount: 0
        )

        XCTAssertEqual(AnalysisConsentPresentation.payloadLabel(summary), "multimodal")
        XCTAssertEqual(
            AnalysisConsentPresentation.privacyExplanation(summary),
            "This request includes 1 image and prepared context from 1 capture."
        )
    }
}
