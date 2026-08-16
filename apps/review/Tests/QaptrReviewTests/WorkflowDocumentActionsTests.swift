import XCTest
@testable import QaptrReview
@testable import QaptrReviewCore

/// Direct tests for `MarkdownExportVariant`'s wire encoding and filename
/// derivation, and for `ReviewAppModel`'s honest failure behavior when no
/// bridge is available (the deterministic state in this test environment,
/// matching how `ReviewAppModel` behaves whenever the native bridge cannot
/// be loaded or bootstrapped).
final class WorkflowDocumentActionsTests: XCTestCase {

    // MARK: - MarkdownExportVariant

    func testWireValueMatchesTheRustBridgeStrings() {
        XCTAssertEqual(MarkdownExportVariant.automation.wireValue, "automation")
        XCTAssertEqual(MarkdownExportVariant.handoff.wireValue, "handoff")
        XCTAssertEqual(MarkdownExportVariant.onboarding.wireValue, "onboarding")
        XCTAssertEqual(MarkdownExportVariant.sop.wireValue, "sop")
    }

    func testSuggestedFileNameSanitizesSlashesAndAlwaysEndsInMd() {
        let name = MarkdownExportVariant.sop.suggestedFileName(workflowTitle: "Review/Draft Plan")
        XCTAssertEqual(name, "Review-Draft Plan-sop.md")
        XCTAssertTrue(name.hasSuffix(".md"))
    }

    func testSuggestedFileNameFallsBackForAnEmptyTitleRatherThanProducingABareExtension() {
        let name = MarkdownExportVariant.handoff.suggestedFileName(workflowTitle: "   ")
        XCTAssertEqual(name, "workflow-handoff.md")
    }

    // MARK: - DocumentActionError

    func testDocumentActionErrorDescriptionIsTheSuppliedMessage() {
        let error = DocumentActionError("Qaptr is not ready yet.")
        XCTAssertEqual(error.description, "Qaptr is not ready yet.")
        XCTAssertEqual(String(describing: error), "Qaptr is not ready yet.")
    }

    // MARK: - ReviewAppModel honest failure without a bridge

    /// In this unit-test process, `ReviewAppModel`'s real `ReviewBridge` init
    /// cannot bootstrap (no packaged dylib, no writable Application Support
    /// bootstrap path configured for the test sandbox), so `bridge` is
    /// deterministically `nil` -- the same state a person would see if Qaptr
    /// could not load its native bridge. Both document actions must report
    /// that honestly rather than silently succeeding or crashing.
    @MainActor
    func testGenerateWorkflowFailsHonestlyWithoutALiveBridge() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        let model = ReviewAppModel(preferences: preferences)

        let result = model.generateWorkflow(fromObservationID: "observation-1")

        switch result {
        case .success:
            XCTFail("generateWorkflow must not report success without a live bridge")
        case .failure(let error):
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    @MainActor
    func testExportWorkflowFailsHonestlyWithoutALiveBridge() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        let model = ReviewAppModel(preferences: preferences)

        let error = model.exportWorkflow(
            workflowID: "workflow-1",
            variant: .sop,
            destination: URL(fileURLWithPath: "/tmp/does-not-matter.md")
        )

        XCTAssertNotNil(error)
    }
}
