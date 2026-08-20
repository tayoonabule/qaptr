import Foundation
import QaptrReviewCore

/// The narrow app-model seam over one native review session.
protocol AnalysisSessionControlling: Sendable {
    func state() throws -> ReviewSessionState
    func start(sessionID: String) throws -> ReviewSessionState
    func decideConsent(granted: Bool) throws -> ReviewSessionState
    func cancel() throws -> ReviewSessionState
    func retry() throws -> ReviewSessionState
}

struct NativeAnalysisSessionController: AnalysisSessionControlling {
    let session: ReviewSession

    func state() throws -> ReviewSessionState { try session.state() }
    func start(sessionID: String) throws -> ReviewSessionState { try session.start(sessionID: sessionID) }
    func decideConsent(granted: Bool) throws -> ReviewSessionState {
        try session.decideConsent(granted: granted)
    }
    func cancel() throws -> ReviewSessionState { try session.cancel() }
    func retry() throws -> ReviewSessionState { try session.retry() }
}

typealias AnalysisSessionFactory = @Sendable (String) throws -> any AnalysisSessionControlling
