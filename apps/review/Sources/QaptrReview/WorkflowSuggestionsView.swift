import AppKit
import QaptrReviewCore
import SwiftUI

/// The returning review states retained as a pure adapter for the existing
/// session model and unit tests. The redesigned surface renders these as a
/// status strip, feed content, or a transient consent sheet.
enum ReviewWorkspaceState: Equatable {
  case loading
  case loadFailure(String)
  case noCaptures
  case captureUnavailable
  case analysisUnavailable(String)
  case providerSetupNeeded
  case readyToAnalyze
  case working(ReviewSessionPhase, previousCandidates: [WorkflowCandidate])
  case consentNeeded(ReviewConsentSummary)
  case candidatesReady([WorkflowCandidate])
  case insufficientEvidence(String)
  case evidenceWithoutCandidates(Int)
  case cancelled

  var probeName: String {
    switch self {
    case .loading: "loading"
    case .loadFailure: "error"
    case .noCaptures: "no-captures"
    case .captureUnavailable: "capture-unavailable"
    case .analysisUnavailable: "analysis-unavailable"
    case .providerSetupNeeded: "provider-setup"
    case .readyToAnalyze: "ready"
    case .working: "analyzing"
    case .consentNeeded: "consent"
    case .candidatesReady: "candidates"
    case .insufficientEvidence: "insufficient-evidence"
    case .evidenceWithoutCandidates: "evidence-only"
    case .cancelled: "cancelled"
    }
  }

  static func resolve(_ input: ReviewWorkspaceInput) -> ReviewWorkspaceState {
    if !input.hasLoaded { return .loading }
    if let loadError = input.loadError { return .loadFailure(loadError) }
    switch input.session.phase {
    case .readyForConsent:
      if let summary = input.session.consentSummary { return .consentNeeded(summary) }
      return .loadFailure(
        "Analysis is waiting for approval, but its consent summary is unavailable.")
    case .ingesting, .preparing, .analyzing:
      return .working(input.session.phase, previousCandidates: input.candidates)
    case .failed:
      return .loadFailure(
        input.analysisError ?? input.session.error ?? "Analysis could not finish.")
    case .cancelled: return .cancelled
    case .idle, .completed: break
    }
    if !input.candidates.isEmpty { return .candidatesReady(input.candidates) }
    if input.session.phase == .completed {
      if input.session.outcome == "no_eligible_payload" {
        return .insufficientEvidence(
          "No privacy-safe capture content was eligible for this analysis.")
      }
      if input.session.outcome == "consent_declined" {
        return .insufficientEvidence(
          "The request stayed local because provider consent was declined.")
      }
      if input.session.observationsWritten > 0 {
        return .evidenceWithoutCandidates(input.session.observationsWritten)
      }
      return .insufficientEvidence(
        "Analysis completed without a supported workflow candidate result.")
    }
    guard let captureCount = input.captureCount else { return .captureUnavailable }
    if captureCount == 0 { return .noCaptures }
    if input.analysisAvailability == "unavailable" {
      return .analysisUnavailable(
        input.analysisUnavailableReason ?? "Workflow analysis is unavailable in this build.")
    }
    if !input.hasProvider || !input.providerConnected { return .providerSetupNeeded }
    if input.observationCount > 0 { return .evidenceWithoutCandidates(input.observationCount) }
    return .readyToAnalyze
  }
}

struct ReviewWorkspaceInput: Equatable {
  let hasLoaded: Bool
  let loadError: String?
  let analysisError: String?
  let captureCount: Int?
  let observationCount: Int
  let candidates: [WorkflowCandidate]
  let analysisAvailability: String?
  let analysisUnavailableReason: String?
  let hasProvider: Bool
  let providerConnected: Bool
  let session: ReviewSessionState
}

enum CandidateCapabilityPresentation {
  static let correctionUnavailable =
    "Correction is not connected to the review-session boundary in this build. Qaptr will keep the saved explanation unchanged rather than pretending a local edit revised the analysis."
  static let detailedCaptureUnavailable =
    "Detailed capture is not connected in this build, so no capture setting has changed."
}

struct WorkflowSuggestionsView: View {
  @Bindable var model: ReviewAppModel
  let openSettings: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var toast: String?
  @State private var dismissedContextNudge = false
  @State private var dismissedQuietResult = false
  @State private var dismissedDoneWatching = false

  var body: some View {
    ZStack(alignment: .bottom) {
      ReviewDesign.canvas.ignoresSafeArea()
      if model.reviewHasLoaded {
        HomeReviewView(
          model: model,
          state: workspaceState,
          openSettings: openSettings,
          cancel: cancelAnalysis,
          showToast: { toast = $0 },
          contextNudgeDismissed: dismissedContextNudge,
          dismissContextNudge: { dismissedContextNudge = true },
          quietResultDismissed: dismissedQuietResult,
          dismissQuietResult: { dismissedQuietResult = true },
          doneWatchingDismissed: dismissedDoneWatching,
          dismissDoneWatching: { dismissedDoneWatching = true }
        )
      } else {
        ReviewLoadingView()
      }
      if let toast {
        ReviewToastView(text: toast) { self.toast = nil }
          .padding(.bottom, 24)
      }
    }
    .sheet(isPresented: consentPresented) {
      if let summary = model.analysisSessionState.consentSummary {
        ConsentReviewView(
          model: model,
          summary: summary,
          declined: { toast = "Nothing was sent." }
        )
        .interactiveDismissDisabled()
      }
    }
    .onAppear { model.refresh() }
    .onChange(of: workspaceState.probeName, initial: true) { _, value in
      recordReviewContentStateIfRequested(value)
    }
    .task {
      while !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
        model.refresh()
      }
    }
  }

  private var workspaceState: ReviewWorkspaceState {
    ReviewWorkspaceState.resolve(
      ReviewWorkspaceInput(
        hasLoaded: model.reviewHasLoaded,
        loadError: model.loadError,
        analysisError: model.analysisError,
        captureCount: model.captureProgress.captureCount,
        observationCount: model.snapshot.observations.count,
        candidates: model.workflowCandidates,
        analysisAvailability: model.reviewStatus?.analysis.state,
        analysisUnavailableReason: model.reviewStatus?.analysis.reason,
        hasProvider: model.settings.provider != nil,
        providerConnected: model.providerConnection == .connected,
        session: model.analysisSessionState
      )
    )
  }

  private var consentPresented: Binding<Bool> {
    Binding(get: { model.analysisSessionState.phase == .readyForConsent }, set: { _ in })
  }

  private func cancelAnalysis() {
    model.cancelAnalysis()
    toast = "Analysis cancelled. Nothing was sent."
  }
}

private struct HomeReviewView: View {
  @Bindable var model: ReviewAppModel
  let state: ReviewWorkspaceState
  let openSettings: () -> Void
  let cancel: () -> Void
  let showToast: (String) -> Void
  let contextNudgeDismissed: Bool
  let dismissContextNudge: () -> Void
  let quietResultDismissed: Bool
  let dismissQuietResult: () -> Void
  let doneWatchingDismissed: Bool
  let dismissDoneWatching: () -> Void

  @State private var path: [String] = []
  @State private var savedIDs: Set<String> = []

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        homeToolbar
        ReviewStatusStrip(
          progress: model.captureProgress,
          helperIsRunning: model.captureHelperIsRunning,
          captureIntent: model.captureControlIntent,
          session: model.analysisSessionState,
          detailedCapture: model.detailedCaptureState,
          analyze: model.startAnalysis,
          pause: model.pauseCapture,
          resume: model.resumeCapture,
          cancel: cancel,
          retry: retry,
          requestPermission: model.requestScreenRecording,
          restart: model.restartCaptureHelper,
          stopDetailed: model.stopDetailedCapture,
          openSettings: openSettings
        )
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            banners
            feed
          }
          .frame(width: 765, alignment: .leading)
          .padding(.top, 22)
          .padding(.bottom, 36)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .navigationDestination(for: String.self) { id in
        if let finding = findings.first(where: { $0.id == id }) {
          FindingDetailView(
            finding: finding,
            saved: savedIDs.contains(id)
              || model.snapshot.workflows.contains {
                $0.sessionID == finding.candidate?.analysisSessionID
              },
            save: { save(finding) },
            captureMoreDetail: { captureMoreDetail(finding) },
            back: { path.removeLast() }
          )
        }
      }
    }
  }

  private var homeToolbar: some View {
    HStack(spacing: 0) {
      QaptrBrandLogo(iconSize: 22, textSize: 18)
      Rectangle()
        .fill(Color.black.opacity(0.10))
        .frame(width: 1, height: 20)
        .padding(.horizontal, 18)
      Text("Home")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(ReviewDesign.ink)
      Spacer()
      Text("LOCAL REVIEW")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(ReviewDesign.muted)
      Button(action: openSettings) {
        Image(systemName: "gearshape")
          .font(.system(size: 14, weight: .medium))
          .frame(width: 30, height: 30)
      }
      .buttonStyle(.plain)
      .foregroundStyle(ReviewDesign.slate)
      .contentShape(Rectangle())
      .accessibilityLabel("Open Settings")
      .padding(.leading, 12)
    }
    .padding(.horizontal, 40)
    .frame(height: 60)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.white.opacity(0.75))
        .frame(height: 1)
    }
  }

  @ViewBuilder
  private var banners: some View {
    if !quietResultDismissed
      && (state.probeName == "insufficient-evidence" || state.probeName == "evidence-only")
    {
      ReviewGlassCard(padding: 18) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "sparkles")
            .foregroundStyle(ReviewDesign.accent)
          VStack(alignment: .leading, spacing: 5) {
            Text("No new patterns stood out this time.")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(ReviewDesign.ink)
            if model.analysisSessionState.observationsWritten > 0 {
              Text(
                "Qaptr saved \(model.analysisSessionState.observationsWritten) observations below."
              )
              .font(.system(size: 13))
              .foregroundStyle(ReviewDesign.slate)
            }
            if let notice = model.snapshot.notices.first {
              Text(notice.text)
                .font(.system(size: 13))
                .foregroundStyle(ReviewDesign.slate)
            }
          }
          Spacer()
          Button("Dismiss", action: dismissQuietResult)
            .buttonStyle(.plain)
            .foregroundStyle(ReviewDesign.muted)
        }
      }
    }
    if !doneWatchingDismissed && model.detailedCaptureState.outcome == .stopped {
      ReviewGlassCard(padding: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("Done watching ✓")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(ReviewDesign.ink)
            Text("Qaptr finished collecting detailed captures.")
              .font(.system(size: 13))
              .foregroundStyle(ReviewDesign.slate)
          }
          Spacer()
          Button("Analyze them", action: model.startAnalysis)
            .buttonStyle(.borderedProminent)
            .tint(ReviewDesign.accent)
          Button("Dismiss", action: dismissDoneWatching)
            .buttonStyle(.plain)
            .foregroundStyle(ReviewDesign.muted)
        }
      }
    }
    if !contextNudgeDismissed && !findings.isEmpty
      && model.settings.accessibilityContextStatus == .notDetermined
    {
      ReviewGlassCard(padding: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Findings get sharper with app and window names.")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(ReviewDesign.ink)
            Text("Optional. Capture doesn’t depend on it.")
              .font(.system(size: 13))
              .foregroundStyle(ReviewDesign.slate)
          }
          Spacer()
          Button("Allow", action: model.requestAccessibilityContext)
            .buttonStyle(.borderedProminent)
            .tint(ReviewDesign.accent)
          Button("Not now", action: dismissContextNudge)
            .buttonStyle(.plain)
            .foregroundStyle(ReviewDesign.muted)
        }
      }
    }
  }

  @ViewBuilder
  private var feed: some View {
    if case .loadFailure(let message) = state {
      ReviewRecoveryView(
        title: "Qaptr could not load this review", detail: message, actionTitle: "Try again",
        action: model.refresh)
    } else if case .analysisUnavailable(let message) = state {
      ReviewRecoveryView(
        title: "Workflow analysis is unavailable", detail: message, actionTitle: "Check again",
        action: model.refresh)
    } else if case .providerSetupNeeded = state {
      ReviewRecoveryView(
        title: "Connect an analysis tool when you are ready",
        detail: "Your captures remain local. Provider setup happens before analysis.",
        actionTitle: "Open Provider Settings", action: openSettings)
    } else if findings.isEmpty {
      EmptyFindingsView(
        captureCount: model.captureProgress.captureCount, analyze: model.startAnalysis)
    } else {
      VStack(alignment: .leading, spacing: 14) {
        Text("From your last analysis")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(ReviewDesign.muted)
        VStack(spacing: 16) {
          ForEach(findings.filter { $0.kind == .workflow }) { finding in
            ReviewFindingRow(finding: finding) { path.append(finding.id) }
          }
        }
        if findings.contains(where: { $0.kind == .observation }) {
          Text("Earlier")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ReviewDesign.muted)
            .padding(.top, 8)
          VStack(spacing: 16) {
            ForEach(findings.filter { $0.kind == .observation }) { finding in
              ReviewFindingRow(finding: finding) { path.append(finding.id) }
            }
          }
        }
      }
    }
  }

  private var findings: [ReviewFinding] {
    model.workflowCandidates.map { candidate in
      ReviewFinding(
        id: candidate.id, kind: .workflow, title: candidate.title, summary: candidate.rationale,
        evidenceText: "\(candidate.evidenceCaptureCount) captures",
        incomplete: candidate.recommendation != nil, candidate: candidate, observation: nil)
    }
      + model.snapshot.recentObservations.map { observation in
        ReviewFinding(
          id: observation.id, kind: .observation, title: observation.title,
          summary: observation.summary,
          evidenceText: "Observed · \(observation.confidenceBand.label)", incomplete: false,
          candidate: nil, observation: observation)
      }
  }

  private func retry() {
    model.analysisSessionState.allowedOperations.contains("retry")
      ? model.retryAnalysis() : model.startAnalysis()
  }

  private func save(_ finding: ReviewFinding) {
    guard let candidate = finding.candidate,
      let observation = model.snapshot.observations.first(where: {
        $0.sessionID == candidate.analysisSessionID
      })
    else {
      showToast("This workflow cannot be saved until its source observation is available.")
      return
    }
    switch model.generateWorkflow(fromObservationID: observation.id) {
    case .success:
      savedIDs.insert(finding.id)
      showToast("Workflow saved.")
    case .failure(let error):
      showToast(error.localizedDescription)
    }
  }

  private func captureMoreDetail(_ finding: ReviewFinding) {
    model.startDetailedCapture()
    if model.detailedCaptureState.lifecycle == .capturing {
      path.removeLast()
    } else {
      showToast(CandidateCapabilityPresentation.detailedCaptureUnavailable)
    }
  }
}

private struct EmptyFindingsView: View {
  let captureCount: Int?
  let analyze: () -> Void

  var body: some View {
    ReviewGlassCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Nothing to review yet.")
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(ReviewDesign.ink)
        if let captureCount, captureCount > 0 {
          Text(
            "Qaptr has been capturing quietly. Review the latest \(captureCount) captures when you’re ready."
          )
          .font(.system(size: 15))
          .foregroundStyle(ReviewDesign.slate)
          Button("Analyze \(captureCount) captures", action: analyze)
            .buttonStyle(.borderedProminent)
            .tint(ReviewDesign.accent)
            .padding(.top, 8)
        } else {
          Text(
            "Qaptr is capturing quietly. Work for a stretch, then analyze to see what it noticed."
          )
          .font(.system(size: 15))
          .foregroundStyle(ReviewDesign.slate)
        }
      }
    }
  }
}

private struct ReviewLoadingView: View {
  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("Reading your local history")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(ReviewDesign.ink)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ReviewRecoveryView: View {
  let title: String
  let detail: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    ReviewGlassCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.system(size: 22, weight: .regular))
          .foregroundStyle(ReviewDesign.ink)
        Text(detail)
          .font(.system(size: 14))
          .foregroundStyle(ReviewDesign.slate)
          .fixedSize(horizontal: false, vertical: true)
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .tint(ReviewDesign.accent)
      }
    }
  }
}

private struct ConsentReviewView: View {
  @Bindable var model: ReviewAppModel
  let summary: ReviewConsentSummary
  let declined: () -> Void
  @State private var approving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("Approve before anything leaves this Mac")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(ReviewDesign.ink)
      Text("Qaptr asks every time. Review exactly what will be sent, to whom, before approving.")
        .font(.system(size: 14))
        .foregroundStyle(ReviewDesign.slate)
      VStack(spacing: 0) {
        consentRow("Sending to", "\(summary.provider) · \(summary.modelLabel)")
        consentRow(
          "What", "Redacted text from \(summary.preparedCount) of \(summary.captureCount) captures")
        consentRow(
          "Not included",
          "\(summary.exclusionCount) captures excluded by your privacy rules · no images")
      }
      .padding(.vertical, 10)
      .overlay(alignment: .top) { Divider() }
      .overlay(alignment: .bottom) { Divider() }
      Text(
        "Personal details like emails and phone numbers were removed on this Mac. Qaptr asks every time."
      )
      .font(.system(size: 13))
      .foregroundStyle(ReviewDesign.muted)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Cancel") {
          model.decideAnalysisConsent(granted: false)
          declined()
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReviewDesign.muted)
        Spacer()
        Button(approving ? "Starting…" : "Approve & analyze") {
          approving = true
          model.decideAnalysisConsent(granted: true)
        }
        .buttonStyle(.borderedProminent)
        .tint(ReviewDesign.accent)
        .disabled(approving)
      }
    }
    .padding(30)
    .frame(width: 560)
  }

  private func consentRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ReviewDesign.muted)
      Spacer()
      Text(value)
        .font(.system(size: 13))
        .foregroundStyle(ReviewDesign.ink)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 10)
  }
}

extension ReviewConsentSummary {
  fileprivate var preparedCount: Int { max(0, captureCount - exclusionCount) }
}

extension WorkflowEvidenceStatus {
  fileprivate var title: String {
    switch self {
    case .enoughInformation: "Enough information"
    case .needsMoreDetail: "Needs more detail"
    case .needsMoreFrequentObservation: "Needs more frequent observation"
    }
  }

  fileprivate var symbolName: String {
    switch self {
    case .enoughInformation: "checkmark.circle.fill"
    case .needsMoreDetail: "viewfinder.circle"
    case .needsMoreFrequentObservation: "timer.circle"
    }
  }

  fileprivate var color: Color {
    switch self {
    case .enoughInformation: ReviewDesign.green
    case .needsMoreDetail: ReviewDesign.orange
    case .needsMoreFrequentObservation: ReviewDesign.accent
    }
  }
}

extension WorkflowCaptureRecommendation {
  fileprivate var durationLabel: String {
    if durationSeconds < 60 { return "\(durationSeconds) seconds" }
    return "\(durationSeconds / 60) minutes"
  }
}

private func recordReviewContentStateIfRequested(_ probeName: String) {
  guard let path = ProcessInfo.processInfo.environment["QAPTR_REVIEW_CONTENT_FILE"] else { return }
  try? "\(probeName)\n".write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
}
