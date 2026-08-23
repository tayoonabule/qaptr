#if DEBUG
import Foundation
import QaptrReviewCore

/// Representative local-only data for exercising the review UI without a
/// running helper, durable store, or provider connection.
enum DevMockData {
    static let enabled = ProcessInfo.processInfo.environment["QAPTR_DEV_MOCK_DATA"] == "1"

    static let snapshot = ReviewSnapshot(
        observations: [
            QaptrObservation(
                id: "mock-observation-1",
                captureID: "mock-capture-1",
                sessionID: "mock-session",
                title: "You compared two launch plans",
                summary: "A product brief and a planning document were open together while you weighed the tradeoffs between a fast beta and a broader launch.",
                confidence: 0.91,
                createdAtMillis: 1_755_295_200_000
            ),
            QaptrObservation(
                id: "mock-observation-2",
                captureID: "mock-capture-2",
                sessionID: "mock-session",
                title: "You were refining the capture experience",
                summary: "The Qaptr settings surface was open while you adjusted spacing, focus treatment, and the window-title exclusion control.",
                confidence: 0.84,
                createdAtMillis: 1_755_291_600_000
            ),
            QaptrObservation(
                id: "mock-observation-3",
                captureID: "mock-capture-3",
                sessionID: "mock-session",
                title: "You reviewed implementation feedback",
                summary: "A code review and terminal session were visible while you validated a small SwiftUI change against the packaged app.",
                confidence: 0.73,
                createdAtMillis: 1_755_288_000_000
            )
        ],
        workflows: [
            WorkflowSummary(
                id: "mock-workflow-1",
                sessionID: "mock-session",
                title: "Polish the Qaptr review workspace",
                goal: "Turn the empty review surface into a calm, scannable record of recent work.",
                evidenceConfidence: 0.88,
                createdAtMillis: 1_755_295_200_000
            )
        ],
        notices: [
            ExclusionNotice(
                id: "mock-notice-1",
                createdAtMillis: 1_755_286_200_000,
                count: 2,
                text: "2 captures were skipped while a protected application was active."
            )
        ],
        workflowCandidates: [
            WorkflowCandidate(
                id: "mock-candidate-1",
                analysisSessionID: "mock-session",
                rank: 1,
                title: "Validate a product change before release",
                rationale: "Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.",
                evidenceStatus: .enoughInformation,
                evidenceConfidence: 0.91,
                evidenceBasis: "8 captures across 42 minutes showed the same implementation-to-verification sequence.",
                evidenceCaptureCount: 8,
                observedStartAtMillis: 1_755_292_680_000,
                observedEndAtMillis: 1_755_295_200_000,
                recommendation: nil,
                createdAtMillis: 1_755_295_200_000,
                revisedAtMillis: 1_755_295_200_000
            ),
            WorkflowCandidate(
                id: "mock-candidate-2",
                analysisSessionID: "mock-session-2",
                rank: 2,
                title: "Compare launch plans and record the decision",
                rationale: "A product brief and planning document appeared together while tradeoffs were reviewed.",
                evidenceStatus: .needsMoreDetail,
                evidenceConfidence: 0.73,
                evidenceBasis: "4 captures show comparison work, but not the final decision or handoff.",
                evidenceCaptureCount: 4,
                observedStartAtMillis: 1_755_291_600_000,
                observedEndAtMillis: 1_755_292_320_000,
                recommendation: WorkflowCaptureRecommendation(intervalSeconds: 15, durationSeconds: 1_800),
                createdAtMillis: 1_755_295_200_000,
                revisedAtMillis: 1_755_295_200_000
            ),
            WorkflowCandidate(
                id: "mock-candidate-3",
                analysisSessionID: "mock-session-3",
                rank: 3,
                title: "Refine a native interface from review feedback",
                rationale: "Qaptr saw the same SwiftUI surface, review notes, and repeated visual adjustments.",
                evidenceStatus: .needsMoreFrequentObservation,
                evidenceConfidence: 0.61,
                evidenceBasis: "3 captures establish the task, but the important edits happened between observations.",
                evidenceCaptureCount: 3,
                observedStartAtMillis: 1_755_288_000_000,
                observedEndAtMillis: 1_755_291_600_000,
                recommendation: WorkflowCaptureRecommendation(intervalSeconds: 10, durationSeconds: 1_200),
                createdAtMillis: 1_755_295_200_000,
                revisedAtMillis: 1_755_295_200_000
            ),
        ]
    )

    static let captureProgress = CaptureProgressSnapshot(
        state: .waiting,
        captureCount: 18,
        lastCaptureAtMillis: 1_755_295_200_000,
        startedAtMillis: 1_755_230_000_000,
        updatedAtMillis: 1_755_295_200_000,
        processID: Int64(ProcessInfo.processInfo.processIdentifier),
        revision: 18,
        selectedDisplayIDs: ["mock-display-main"],
        activeIntervalSeconds: 30
    )

    static let reviewStatus = ReviewStatus(
        store: ReviewStoreStatus(ready: true),
        reviewSession: ReviewSessionStatus(
            state: "ready",
            historyAvailable: true,
            observationCount: snapshot.observations.count,
            workflowCount: snapshot.workflows.count,
            noticeCount: snapshot.notices.count
        ),
        analysis: ReviewAnalysisStatus(state: "ready", provider: "OpenAI", reason: nil)
    )
}
#endif
