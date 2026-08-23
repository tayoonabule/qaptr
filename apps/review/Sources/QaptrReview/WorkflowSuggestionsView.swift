import AppKit
import QaptrReviewCore
import SwiftUI

// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V5

private enum EvidenceLensSpace {
    static let compact: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let section: CGFloat = 36
    static let page: CGFloat = 48
}

private enum EvidenceLensColor {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let selected = Color.accentColor.opacity(0.08)
    static let enough = Color(nsColor: .systemGreen)
    static let moreDetail = Color(nsColor: .systemOrange)
    static let moreFrequent = Color(nsColor: .systemBlue)
    static let attention = Color(nsColor: .systemRed)
}

/// The mutually exclusive primary bodies of the returning review canvas.
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
        if !input.hasLoaded {
            return .loading
        }
        if let loadError = input.loadError {
            return .loadFailure(loadError)
        }

        switch input.session.phase {
        case .readyForConsent:
            if let summary = input.session.consentSummary {
                return .consentNeeded(summary)
            }
            return .loadFailure("Analysis is waiting for approval, but its consent summary is unavailable.")
        case .ingesting, .preparing, .analyzing:
            return .working(input.session.phase, previousCandidates: input.candidates)
        case .failed:
            return .loadFailure(input.analysisError ?? input.session.error ?? "Analysis could not finish.")
        case .cancelled:
            return .cancelled
        case .idle, .completed:
            break
        }

        if !input.candidates.isEmpty {
            return .candidatesReady(input.candidates)
        }

        if input.session.phase == .completed {
            if input.session.outcome == "no_eligible_payload" {
                return .insufficientEvidence("No privacy-safe capture content was eligible for this analysis.")
            }
            if input.session.outcome == "consent_declined" {
                return .insufficientEvidence("The request stayed local because provider consent was declined.")
            }
            if input.session.observationsWritten > 0 {
                return .evidenceWithoutCandidates(input.session.observationsWritten)
            }
            return .insufficientEvidence("Analysis completed without a supported workflow candidate result.")
        }

        guard let captureCount = input.captureCount else {
            return .captureUnavailable
        }
        if captureCount == 0 {
            return .noCaptures
        }

        if let analysisState = input.analysisAvailability,
           analysisState == "unavailable" {
            return .analysisUnavailable(input.analysisUnavailableReason ?? "Workflow analysis is unavailable in this build.")
        }

        if !input.hasProvider || !input.providerConnected {
            return .providerSetupNeeded
        }

        if input.observationCount > 0 {
            return .evidenceWithoutCandidates(input.observationCount)
        }
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
    static let correctionUnavailable = "Correction is not connected to the review-session boundary in this build. Qaptr will keep the saved explanation unchanged rather than pretending a local edit revised the analysis."
    static let detailedCaptureUnavailable = "Detailed capture is not connected in this build, so no capture setting has changed."
}

/// Adapts the existing privacy-safe app model into the new single-canvas review
/// surface. Provider calls still start only through `ReviewAppModel` and its
/// explicit consent sheet.
struct WorkflowSuggestionsView: View {
    @Bindable var model: ReviewAppModel
    let openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedCandidateID: String?

    var body: some View {
        ReviewWorkspaceContent(
            state: workspaceState,
            captureStatus: captureStatus,
            lastCaptureAtMillis: model.captureProgress.lastCaptureAtMillis,
            workflows: model.snapshot.workflows,
            selectedCandidateID: $selectedCandidateID,
            openSettings: openSettings,
            analyze: model.startAnalysis,
            retry: retry,
            cancel: model.cancelAnalysis,
            refresh: model.refresh
        )
        .sheet(isPresented: consentPresented) {
            if let summary = model.analysisSessionState.consentSummary {
                WorkflowConsentSheet(model: model, summary: summary)
                    .interactiveDismissDisabled()
            }
        }
        .onAppear { model.refresh() }
        .onChange(of: workspaceState.probeName, initial: true) { _, _ in
            recordReviewContentStateIfRequested(workspaceState.probeName)
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
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

    private var captureStatus: CaptureStatusPresentation {
        CaptureStatusPresentation.present(
            intent: model.captureControlIntent,
            helperIsRunning: model.captureHelperIsRunning
        )
    }

    private var consentPresented: Binding<Bool> {
        Binding(
            get: { model.analysisSessionState.phase == .readyForConsent },
            set: { _ in }
        )
    }

    private func retry() {
        if model.analysisSessionState.allowedOperations.contains("retry") {
            model.retryAnalysis()
        } else {
            model.startAnalysis()
        }
    }
}

private struct ReviewWorkspaceContent: View {
    let state: ReviewWorkspaceState
    let captureStatus: CaptureStatusPresentation
    let lastCaptureAtMillis: Int64?
    let workflows: [WorkflowSummary]
    @Binding var selectedCandidateID: String?
    let openSettings: () -> Void
    let analyze: () -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let refresh: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            EvidenceLensColor.canvas.ignoresSafeArea()

            if let selectedCandidate {
                WorkflowUnderstandingView(
                    candidate: selectedCandidate,
                    workflow: workflows.first { $0.sessionID == selectedCandidate.analysisSessionID },
                    back: clearSelection
                )
                .transition(contentTransition)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: EvidenceLensSpace.section) {
                        statusBar
                        workspaceBody
                    }
                    .padding(.horizontal, EvidenceLensSpace.page)
                    .padding(.top, 30)
                    .padding(.bottom, EvidenceLensSpace.page)
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .transition(contentTransition)
            }
        }
    }

    private var selectedCandidate: WorkflowCandidate? {
        guard let selectedCandidateID else { return nil }
        switch state {
        case let .candidatesReady(candidates), let .working(_, candidates):
            return candidates.first { $0.id == selectedCandidateID }
        default:
            return nil
        }
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }

    private var statusBar: some View {
        HStack(spacing: EvidenceLensSpace.medium) {
            HStack(spacing: EvidenceLensSpace.compact) {
                Circle()
                    .fill(captureStatusColor)
                    .frame(width: 7, height: 7)
                Text(captureStatus.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(captureStatus.accessibilityLabel)

            if let lastCaptureAtMillis {
                Text("Last capture \(Date(timeIntervalSince1970: Double(lastCaptureAtMillis) / 1_000), style: .relative)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: openSettings) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Open Settings")
            .accessibilityValue("Open Settings")
            .accessibilityRepresentation {
                Button("Open Settings", action: openSettings)
            }
            .help("Settings")
        }
    }

    @ViewBuilder
    private var workspaceBody: some View {
        switch state {
        case .loading:
            StateMessageView(
                symbol: "clock.arrow.circlepath",
                title: "Reading your local history",
                detail: "Qaptr is checking saved, privacy-safe results on this Mac."
            ) {
                ProgressView().controlSize(.small)
            }
        case let .loadFailure(message):
            StateMessageView(
                symbol: "exclamationmark.triangle",
                title: "Qaptr could not load this review",
                detail: message,
                symbolColor: EvidenceLensColor.attention
            ) {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        case .noCaptures:
            StateMessageView(
                symbol: "viewfinder",
                title: "Workflow suggestions need a little history",
                detail: "No screenshots have been captured yet. Qaptr will keep this screen quiet until the helper reports real capture history."
            ) {
                Button("Check again", action: refresh)
                    .buttonStyle(.bordered)
            }
        case .captureUnavailable:
            StateMessageView(
                symbol: "rectangle.dashed.badge.record",
                title: "Capture status is unavailable",
                detail: "Qaptr cannot confirm that the helper is reporting. Review capture settings before relying on new evidence."
            ) {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
        case let .analysisUnavailable(reason):
            StateMessageView(
                symbol: "bolt.slash",
                title: "Workflow analysis is unavailable",
                detail: reason
            ) {
                Button("Check again", action: refresh)
                    .buttonStyle(.bordered)
            }
        case .providerSetupNeeded:
            StateMessageView(
                symbol: "point.3.connected.trianglepath.dotted",
                title: "Connect an analysis tool when you are ready",
                detail: "Your captures remain local. Qaptr will prepare privacy-safe context first and ask again before anything is sent."
            ) {
                Button("Open Provider Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
        case .readyToAnalyze:
            StateMessageView(
                symbol: "scope",
                title: "Find repeatable work in your recent captures",
                detail: "Qaptr will prepare local evidence, then request one-time consent before contacting the connected provider."
            ) {
                Button("Review recent work", action: analyze)
                    .buttonStyle(.borderedProminent)
            }
        case let .working(phase, previousCandidates):
            WorkingStateView(phase: phase, candidates: previousCandidates, cancel: cancel, select: select)
        case .consentNeeded:
            StateMessageView(
                symbol: "hand.raised",
                title: "Your approval is needed",
                detail: "Review the scalar consent summary before Qaptr contacts the selected provider."
            ) {
                ProgressView().controlSize(.small)
            }
        case let .candidatesReady(candidates):
            CandidateListView(candidates: candidates, select: select)
        case let .insufficientEvidence(reason):
            StateMessageView(
                symbol: "text.magnifyingglass",
                title: "Qaptr does not have enough evidence yet",
                detail: reason
            ) {
                Button("Review again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        case let .evidenceWithoutCandidates(count):
            StateMessageView(
                symbol: "list.bullet.clipboard",
                title: "Evidence is saved, but no workflow candidates are ready",
                detail: "Qaptr has \(count) evidence record\(count == 1 ? "" : "s"). This build has not returned the typed candidate result this screen requires, so it will not invent suggestions from those records."
            ) {
                Button("Analyze recent work", action: analyze)
                    .buttonStyle(.borderedProminent)
            }
        case .cancelled:
            StateMessageView(
                symbol: "xmark.circle",
                title: "Analysis stopped before completion",
                detail: "Existing saved results remain unchanged. You can start a new review when you are ready."
            ) {
                Button("Start again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var captureStatusColor: Color {
        switch captureStatus {
        case .live: EvidenceLensColor.enough
        case .paused: EvidenceLensColor.moreDetail
        case .needsAttention: EvidenceLensColor.attention
        }
    }

    private func select(_ candidate: WorkflowCandidate) {
        if reduceMotion {
            selectedCandidateID = candidate.id
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                selectedCandidateID = candidate.id
            }
        }
    }

    private func clearSelection() {
        if reduceMotion {
            selectedCandidateID = nil
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedCandidateID = nil
            }
        }
    }
}

private struct CandidateListView: View {
    let candidates: [WorkflowCandidate]
    let select: (WorkflowCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EvidenceLensSpace.large) {
            VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                Text("Work worth understanding")
                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                Text("These are evidence-backed possibilities, not finished claims. Start with the one that would be most useful to understand.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 660, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    WorkflowCandidateRow(candidate: candidate, emphasized: index == 0) {
                        select(candidate)
                    }
                    if index < candidates.count - 1 {
                        Divider()
                    }
                }
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

private struct WorkingStateView: View {
    let phase: ReviewSessionPhase
    let candidates: [WorkflowCandidate]
    let cancel: () -> Void
    let select: (WorkflowCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EvidenceLensSpace.section) {
            HStack(alignment: .top, spacing: EvidenceLensSpace.large) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: EvidenceLensSpace.compact) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, EvidenceLensSpace.medium)

            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: EvidenceLensSpace.medium) {
                    Text("Previous candidates remain available while Qaptr reviews newer evidence.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            WorkflowCandidateRow(candidate: candidate, emphasized: false) {
                                select(candidate)
                            }
                            if index < candidates.count - 1 { Divider() }
                        }
                    }
                    .overlay(alignment: .top) { Divider() }
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    private var title: String {
        switch phase {
        case .ingesting: "Reading committed capture records"
        case .preparing: "Preparing privacy-safe evidence"
        case .analyzing: "Looking for repeatable work"
        default: "Reviewing recent work"
        }
    }

    private var detail: String {
        switch phase {
        case .ingesting: "Only committed local capture records are included."
        case .preparing: "Exclusions and redaction happen on this Mac before consent."
        case .analyzing: "Qaptr is waiting for a bounded, typed result from the approved provider."
        default: "Qaptr is following the explicit review-session lifecycle."
        }
    }
}

private struct WorkflowCandidateRow: View {
    let candidate: WorkflowCandidate
    let emphasized: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: EvidenceLensSpace.large) {
                Text(String(format: "%02d", candidate.rank))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                    Text(candidate.title)
                        .font(.system(size: emphasized ? 22 : 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.rationale)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    EvidenceStatusLine(candidate: candidate)
                }

                Spacer(minLength: EvidenceLensSpace.large)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, EvidenceLensSpace.medium)
            .padding(.vertical, emphasized ? 28 : 20)
            .background(hovering ? EvidenceLensColor.selected : .clear)
            .accessibilityHidden(true)

            Button(accessibilityTitle, action: select)
                .buttonStyle(.plain)
                .foregroundStyle(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel(accessibilityTitle)
                .accessibilityValue(accessibilityTitle)
                .accessibilityHint("Open the workflow explanation and evidence")
        }
        .onHover { hovering = $0 }
    }

    private var accessibilityTitle: String {
        "Candidate \(candidate.rank), \(candidate.title), \(candidate.evidenceStatus.accessibilityLabel), \(candidate.evidenceCaptureCount) captures"
    }
}

private struct EvidenceStatusLine: View {
    let candidate: WorkflowCandidate

    var body: some View {
        HStack(spacing: EvidenceLensSpace.small) {
            Image(systemName: candidate.evidenceStatus.symbolName)
                .foregroundStyle(candidate.evidenceStatus.color)
            Text(candidate.evidenceStatus.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(candidate.evidenceCaptureCount) capture\(candidate.evidenceCaptureCount == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkflowUnderstandingView: View {
    let candidate: WorkflowCandidate
    let workflow: WorkflowSummary?
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EvidenceLensSpace.section) {
                Button(action: back) {
                    Label("All candidates", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Return to workflow candidates")

                VStack(alignment: .leading, spacing: EvidenceLensSpace.medium) {
                    Text(candidate.title)
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.rationale)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: 720, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(alignment: .top, spacing: EvidenceLensSpace.page) {
                    VStack(alignment: .leading, spacing: EvidenceLensSpace.section) {
                        explanationSection
                        correctionSection
                        automationSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    evidenceRail
                        .frame(width: 260, alignment: .leading)
                }
            }
            .padding(.horizontal, EvidenceLensSpace.page)
            .padding(.top, 30)
            .padding(.bottom, EvidenceLensSpace.page)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(EvidenceLensColor.canvas)
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
            Text("Why Qaptr suggested this")
                .font(.system(size: 16, weight: .semibold))
            Text(candidate.evidenceBasis)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
            Text("What did Qaptr misunderstand?")
                .font(.system(size: 16, weight: .semibold))
            Text(CandidateCapabilityPresentation.correctionUnavailable)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, EvidenceLensSpace.medium)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var automationSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                if let workflow {
                    Text(workflow.goal)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("Canonical workflow available")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Automation-ready output stays unavailable until Qaptr has produced a grounded canonical workflow.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, EvidenceLensSpace.small)
        } label: {
            Text("Automation-ready layer")
                .font(.system(size: 14, weight: .medium))
        }
    }

    private var evidenceRail: some View {
        VStack(alignment: .leading, spacing: EvidenceLensSpace.large) {
            VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                Label(candidate.evidenceStatus.title, systemImage: candidate.evidenceStatus.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(candidate.evidenceStatus.color)
                Text(candidate.evidenceStatus.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                EvidenceFact(label: "CAPTURES", value: "\(candidate.evidenceCaptureCount)")
                EvidenceFact(label: "CONFIDENCE", value: candidate.confidenceBand.label)
                if let span = candidate.observedSpanLabel {
                    EvidenceFact(label: "OBSERVED", value: span)
                }
            }

            if let recommendation = candidate.recommendation {
                VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                    Text("More evidence")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Recommended: every \(recommendation.intervalSeconds) seconds for \(recommendation.durationLabel).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CandidateCapabilityPresentation.detailedCaptureUnavailable)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, EvidenceLensSpace.medium)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .padding(.leading, EvidenceLensSpace.large)
        .overlay(alignment: .leading) { Divider() }
    }
}

private struct EvidenceFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

private struct WorkflowConsentSheet: View {
    @Bindable var model: ReviewAppModel
    let summary: ReviewConsentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: EvidenceLensSpace.large) {
            VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                Text("Approve this analysis request")
                    .font(.system(size: 24, weight: .semibold))
                Text("Review the boundary before Qaptr contacts \(summary.provider). Nothing is sent unless you approve.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                consentRow("Provider", summary.provider)
                consentRow("Model", summary.modelLabel)
                consentRow("Prepared captures", "\(summary.captureCount)")
                consentRow("Excluded locally", "\(summary.exclusionCount)")
                consentRow("Screenshot files", summary.imageCount == 0 ? "None" : "\(summary.imageCount)")
                consentRow("Payload", payloadLabel)
            }
            .padding(.vertical, EvidenceLensSpace.medium)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            Text(privacyExplanation)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.analysisError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(EvidenceLensColor.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Keep local") {
                    model.decideAnalysisConsent(granted: false)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Approve request") {
                    model.decideAnalysisConsent(granted: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 520, alignment: .leading)
        .background(EvidenceLensColor.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analysis consent for \(summary.provider)")
    }

    private var payloadLabel: String {
        if summary.payloadKind == "text", summary.imageCount == 0 {
            return "Privacy-filtered text"
        }
        return summary.payloadKind
    }

    private var privacyExplanation: String {
        if summary.imageCount == 0 {
            return "Screenshot files stay on this Mac. The provider receives prepared text from the approved captures."
        }
        return "This request includes \(summary.imageCount) image\(summary.imageCount == 1 ? "" : "s") plus prepared context."
    }

    private func consentRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

private struct StateMessageView<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var symbolColor: Color = .accentColor
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: EvidenceLensSpace.large) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: EvidenceLensSpace.medium) {
                VStack(alignment: .leading, spacing: EvidenceLensSpace.small) {
                    Text(title)
                        .font(.system(size: 30, weight: .regular, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: 650, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions()
            }
        }
        .padding(.vertical, EvidenceLensSpace.page)
    }
}

private extension WorkflowEvidenceStatus {
    var title: String {
        switch self {
        case .enoughInformation: "Enough information"
        case .needsMoreDetail: "Needs more detail"
        case .needsMoreFrequentObservation: "Needs more frequent observation"
        }
    }

    var detail: String {
        switch self {
        case .enoughInformation: "The current evidence supports a human-readable workflow explanation."
        case .needsMoreDetail: "The broad pattern is visible, but an important decision or handoff is missing."
        case .needsMoreFrequentObservation: "The task is visible, but the interval missed important intermediate steps."
        }
    }

    var accessibilityLabel: String { title }

    var symbolName: String {
        switch self {
        case .enoughInformation: "checkmark.circle.fill"
        case .needsMoreDetail: "viewfinder.circle"
        case .needsMoreFrequentObservation: "timer.circle"
        }
    }

    var color: Color {
        switch self {
        case .enoughInformation: EvidenceLensColor.enough
        case .needsMoreDetail: EvidenceLensColor.moreDetail
        case .needsMoreFrequentObservation: EvidenceLensColor.moreFrequent
        }
    }
}

private extension WorkflowCandidate {
    var observedSpanLabel: String? {
        guard let start = observedStartAtMillis,
              let end = observedEndAtMillis,
              end >= start
        else { return nil }
        let seconds = (end - start) / 1_000
        if seconds < 60 { return "Less than a minute" }
        if seconds < 3_600 { return "\(seconds / 60) min" }
        let hours = Double(seconds) / 3_600
        return hours < 10 ? String(format: "%.1f hr", hours) : "\(Int(hours)) hr"
    }
}

private extension WorkflowCaptureRecommendation {
    var durationLabel: String {
        if durationSeconds < 60 { return "\(durationSeconds) seconds" }
        if durationSeconds < 3_600 { return "\(durationSeconds / 60) minutes" }
        let hours = durationSeconds / 3_600
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
}

private func recordReviewContentStateIfRequested(_ probeName: String) {
    guard let path = ProcessInfo.processInfo.environment["QAPTR_REVIEW_CONTENT_FILE"] else {
        return
    }
    try? "\(probeName)\n".write(
        to: URL(fileURLWithPath: path),
        atomically: true,
        encoding: .utf8
    )
}

#if DEBUG
private enum WorkflowSuggestionsPreviewData {
    static let candidates = DevMockData.snapshot.rankedWorkflowCandidates
}

#Preview("Candidates") {
    ReviewWorkspaceContent(
        state: .candidatesReady(WorkflowSuggestionsPreviewData.candidates),
        captureStatus: .live,
        lastCaptureAtMillis: 1_755_295_200_000,
        workflows: DevMockData.snapshot.workflows,
        selectedCandidateID: .constant(nil),
        openSettings: {}, analyze: {}, retry: {}, cancel: {}, refresh: {}
    )
    .frame(width: 1040, height: 720)
}

#Preview("Loading") {
    ReviewWorkspaceContent(
        state: .loading,
        captureStatus: .live,
        lastCaptureAtMillis: nil,
        workflows: [],
        selectedCandidateID: .constant(nil),
        openSettings: {}, analyze: {}, retry: {}, cancel: {}, refresh: {}
    )
    .frame(width: 900, height: 620)
}

#Preview("No captures") {
    ReviewWorkspaceContent(
        state: .noCaptures,
        captureStatus: .needsAttention,
        lastCaptureAtMillis: nil,
        workflows: [],
        selectedCandidateID: .constant(nil),
        openSettings: {}, analyze: {}, retry: {}, cancel: {}, refresh: {}
    )
    .frame(width: 900, height: 620)
}

#Preview("Error") {
    ReviewWorkspaceContent(
        state: .loadFailure("The durable history store could not be opened."),
        captureStatus: .paused,
        lastCaptureAtMillis: nil,
        workflows: [],
        selectedCandidateID: .constant(nil),
        openSettings: {}, analyze: {}, retry: {}, cancel: {}, refresh: {}
    )
    .frame(width: 900, height: 620)
}
#endif
