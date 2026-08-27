import XCTest
import QaptrReviewCore
@testable import QaptrReview

@MainActor
final class ReviewWorkspaceStateTests: XCTestCase {
    func testLoadingAndLoadFailureAreExplicitAndOrdered() {
        XCTAssertEqual(ReviewWorkspaceState.resolve(input(hasLoaded: false)), .loading)
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(loadError: "store failed")),
            .loadFailure("store failed")
        )
    }

    func testConsentAndWorkingStatesFollowTheSessionLifecycle() {
        let consent = ReviewConsentSummary(
            provider: "Jcode",
            resolvedModel: nil,
            modelLabel: "Default",
            payloadKind: "text",
            captureCount: 4,
            imageCount: 0,
            exclusionCount: 1
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(session: session(phase: .readyForConsent, consent: consent))),
            .consentNeeded(consent)
        )

        let candidates = [candidate(rank: 1)]
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(candidates: candidates, session: session(phase: .preparing))
            ),
            .working(.preparing, previousCandidates: candidates)
        )
    }

    func testEachAnalysisPhaseRoutesToTheExpectedWorkspaceState() {
        let candidates = [candidate(rank: 1)]

        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(session: session(phase: .ingesting))),
            .working(.ingesting, previousCandidates: [])
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(candidates: candidates, session: session(phase: .analyzing))
            ),
            .working(.analyzing, previousCandidates: candidates)
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(session: session(phase: .completed))),
            .insufficientEvidence(
                "Analysis completed without a supported workflow candidate result."
            )
        )
    }

    func testConsentWithoutSummaryRoutesToAnExplicitLoadFailure() {
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(session: session(phase: .readyForConsent))
            ),
            .loadFailure(
                "Analysis is waiting for approval, but its consent summary is unavailable."
            )
        )
    }

    func testAnalysisFailureUsesAnalysisErrorThenSessionErrorThenFallback() {
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(
                    analysisError: "provider timed out",
                    session: session(phase: .failed, error: "session failed")
                )
            ),
            .loadFailure("provider timed out")
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(session: session(phase: .failed, error: "session failed"))
            ),
            .loadFailure("session failed")
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(session: session(phase: .failed))),
            .loadFailure("Analysis could not finish.")
        )
    }

    func testTypedCandidatesWinOverLegacyObservationCounts() {
        let candidates = [candidate(rank: 2), candidate(rank: 1)]

        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(observationCount: 12, candidates: candidates)),
            .candidatesReady(candidates)
        )
    }

    func testEmptyCaptureProviderAndUnavailableAnalysisStatesStayDistinct() {
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(captureCount: 0)),
            .noCaptures
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(captureCount: nil)),
            .captureUnavailable
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(hasProvider: false)),
            .providerSetupNeeded
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(providerConnected: false)),
            .providerSetupNeeded
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(analysisAvailability: "unavailable", analysisReason: "driver missing")
            ),
            .analysisUnavailable("driver missing")
        )
    }

    func testCompletedObservationOnlyResultDoesNotInventCandidates() {
        let completed = session(
            phase: .completed,
            observationsWritten: 3,
            outcome: "provider_completed"
        )

        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(session: completed)),
            .evidenceWithoutCandidates(3)
        )
    }

    func testNoEligiblePayloadAndCancellationHaveHonestRecoveryStates() {
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(
                input(session: session(phase: .completed, outcome: "no_eligible_payload"))
            ),
            .insufficientEvidence("No privacy-safe capture content was eligible for this analysis.")
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(session: session(phase: .cancelled))),
            .cancelled
        )
    }

    func testReadyAndEvidenceOnlyRoutesAreDistinct() {
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input()),
            .readyToAnalyze
        )
        XCTAssertEqual(
            ReviewWorkspaceState.resolve(input(observationCount: 2)),
            .evidenceWithoutCandidates(2)
        )
    }

    func testProbeNamesCoverEveryRenderedWorkspaceRoute() {
        let states: [ReviewWorkspaceState] = [
            .loading,
            .loadFailure("failed"),
            .noCaptures,
            .captureUnavailable,
            .analysisUnavailable("unavailable"),
            .providerSetupNeeded,
            .readyToAnalyze,
            .working(.analyzing, previousCandidates: []),
            .consentNeeded(consentSummary()),
            .candidatesReady([candidate(rank: 1)]),
            .insufficientEvidence("insufficient"),
            .evidenceWithoutCandidates(1),
            .cancelled,
        ]
        let expected = [
            "loading", "error", "no-captures", "capture-unavailable",
            "analysis-unavailable", "provider-setup", "ready", "analyzing",
            "consent", "candidates", "insufficient-evidence", "evidence-only",
            "cancelled",
        ]

        XCTAssertEqual(states.map(\.probeName), expected)
        XCTAssertEqual(Set(states.map(\.probeName)).count, states.count)
    }

    func testUnavailableCapabilitiesNeverClaimMutationSucceeded() {
        XCTAssertTrue(CandidateCapabilityPresentation.correctionUnavailable.contains("unchanged"))
        XCTAssertTrue(CandidateCapabilityPresentation.correctionUnavailable.contains("not connected"))
        XCTAssertTrue(CandidateCapabilityPresentation.detailedCaptureUnavailable.contains("no capture setting has changed"))
    }

    private func input(
        hasLoaded: Bool = true,
        loadError: String? = nil,
        analysisError: String? = nil,
        captureCount: Int? = 8,
        observationCount: Int = 0,
        candidates: [WorkflowCandidate] = [],
        analysisAvailability: String? = "ready",
        analysisReason: String? = nil,
        hasProvider: Bool = true,
        providerConnected: Bool = true,
        session: ReviewSessionState = .idle
    ) -> ReviewWorkspaceInput {
        ReviewWorkspaceInput(
            hasLoaded: hasLoaded,
            loadError: loadError,
            analysisError: analysisError,
            captureCount: captureCount,
            observationCount: observationCount,
            candidates: candidates,
            analysisAvailability: analysisAvailability,
            analysisUnavailableReason: analysisReason,
            hasProvider: hasProvider,
            providerConnected: providerConnected,
            session: session
        )
    }

    private func candidate(rank: Int) -> WorkflowCandidate {
        WorkflowCandidate(
            id: "candidate-\(rank)",
            analysisSessionID: "session",
            rank: rank,
            title: "Candidate \(rank)",
            rationale: "A grounded explanation",
            evidenceStatus: .needsMoreDetail,
            evidenceConfidence: 0.7,
            evidenceBasis: "Four captures",
            evidenceCaptureCount: 4,
            observedStartAtMillis: nil,
            observedEndAtMillis: nil,
            recommendation: nil,
            createdAtMillis: 1,
            revisedAtMillis: 1
        )
    }

    private func consentSummary() -> ReviewConsentSummary {
        ReviewConsentSummary(
            provider: "Jcode",
            resolvedModel: nil,
            modelLabel: "Default",
            payloadKind: "text",
            captureCount: 4,
            imageCount: 0,
            exclusionCount: 1
        )
    }

    private func session(
        phase: ReviewSessionPhase,
        consent: ReviewConsentSummary? = nil,
        observationsWritten: Int = 0,
        outcome: String? = nil,
        error: String? = nil
    ) -> ReviewSessionState {
        ReviewSessionState(
            sessionID: "session",
            phase: phase,
            capturesSeen: 4,
            preparedCaptures: 3,
            imageCount: 0,
            exclusionCount: 1,
            observationsWritten: observationsWritten,
            consentSummary: consent,
            result: nil,
            outcome: outcome,
            error: error,
            resultProvider: nil,
            resultModelLabel: nil,
            allowedOperations: ["state", "start", "retry", "cancel"]
        )
    }
}
