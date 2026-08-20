import AppKit
import QaptrReviewCore
import SwiftUI
import UniformTypeIdentifiers

// Hallmark · studied-DNA: Micro live-site · work plane: row ledger · no stacked dashboard cards

/// The primary surface: a small, honest list of recent observations.
struct ObservationSheetView: View {
    @Bindable var model: ReviewAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedObservation: QaptrObservation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                AnalysisControlView(model: model)
                    .padding(.top, QaptrSpace.lg)

                if model.loadError != nil {
                    ErrorStateView(retry: model.refresh)
                        .padding(.top, QaptrSpace.xl)
                } else {
                    if model.snapshot.observations.isEmpty {
                        EmptyStateView(
                            progress: model.captureProgress,
                            notices: model.snapshot.notices,
                            analysisStatus: model.reviewStatus?.analysis
                        )
                            .padding(.top, QaptrSpace.lg)
                    } else {
                        observationList
                            .padding(.top, QaptrSpace.lg)
                    }
                }

                if !model.snapshot.notices.isEmpty {
                    NoticesView(notices: model.snapshot.notices)
                        .padding(.top, QaptrSpace.xl)
                }
            }
            .padding(.horizontal, QaptrSpace.xxxl)
            .padding(.vertical, QaptrSpace.xxl)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.qaptrSurface)
        .sheet(item: $selectedObservation) { observation in
            ObservationDetailView(model: model, observation: observation)
        }
        .sheet(isPresented: analysisConsentPresented) {
            if let summary = model.analysisSessionState.consentSummary {
                AnalysisConsentView(model: model, summary: summary)
                    .interactiveDismissDisabled()
            }
        }
        .onAppear { model.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                model.refresh()
            }
        }
    }

    private var header: some View {
        Text(headerTitle)
            .font(QaptrType.editorial(38))
            .foregroundStyle(Color.qaptrInk)
    }

    private var headerTitle: String {
        if model.loadError != nil {
            return "Review setup"
        }
        return model.snapshot.observations.isEmpty ? "Review" : "What Qaptr found"
    }

    private var analysisConsentPresented: Binding<Bool> {
        Binding(
            get: { model.analysisSessionState.phase == .readyForConsent },
            set: { _ in }
        )
    }

    private var observationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.snapshot.recentObservations.enumerated()), id: \.element.id) { index, observation in
                ObservationRow(
                    observation: observation,
                    index: index,
                    reduceMotion: reduceMotion,
                    select: { selectedObservation = observation }
                )
                .padding(.horizontal, QaptrSpace.xl)
                .padding(.vertical, QaptrSpace.xxl)
                if index < model.snapshot.recentObservations.count - 1 {
                    Divider().overlay(Color.qaptrHairline)
                }
            }
        }
        .overlay {
            Rectangle().strokeBorder(Color.qaptrHairline, lineWidth: 1)
        }
    }
}

private struct AnalysisControlView: View {
    @Bindable var model: ReviewAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.md) {
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text(title)
                        .font(QaptrType.title(15))
                        .foregroundStyle(Color.qaptrInk)
                    Text(detail)
                        .font(QaptrType.caption())
                        .foregroundStyle(Color.qaptrInkSoft)
                }
                Spacer(minLength: QaptrSpace.lg)
                action
            }

            if let error = model.analysisError {
                Text(error)
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrError)
            }

            if model.analysisSessionState.phase.isActivelyWorking {
                AnalysisProgressView(
                    state: model.analysisSessionState,
                    providerName: model.settings.provider?.displayName
                )
                .padding(.top, QaptrSpace.xxs)
            }
        }
        .padding(.horizontal, QaptrSpace.lg)
        .padding(.vertical, QaptrSpace.md)
        .overlay {
            RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
                .strokeBorder(Color.qaptrHairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch model.analysisSessionState.phase {
        case .ingesting, .preparing, .analyzing:
            HStack(spacing: QaptrSpace.sm) {
                ProgressView().controlSize(.small)
                Button("Cancel", action: model.cancelAnalysis)
                    .buttonStyle(.qaptrQuiet)
            }
        case .readyForConsent:
            Text("CONSENT REQUIRED")
                .font(QaptrType.meta(10))
                .tracking(0.7)
                .foregroundStyle(Color.qaptrTeal)
        case .failed, .cancelled:
            Button("Try again", action: model.retryAnalysis)
                .buttonStyle(.qaptrOutline)
        case .idle, .completed:
            Button(model.analysisSessionState.phase == .completed ? "Analyze again" : "Analyze captures") {
                model.startAnalysis()
            }
            .buttonStyle(.qaptrOutline)
            .disabled(!model.analysisCanStart)
        }
    }

    private var title: String {
        switch model.analysisSessionState.phase {
        case .idle: "Turn captures into observations"
        case .ingesting: "Finding screenshots in your local vault"
        case .preparing: "Protecting screenshots on this Mac"
        case .readyForConsent: "Ready for your approval"
        case .analyzing:
            if let provider = model.settings.provider {
                "\(provider.displayName) is reviewing approved text"
            } else {
                "Reviewing approved text"
            }
        case .completed:
            if model.analysisSessionState.outcome == "consent_declined" {
                "Nothing was sent"
            } else if model.analysisSessionState.outcome == "no_eligible_payload" {
                "No eligible screenshots"
            } else if model.analysisSessionState.observationsWritten == 1 {
                "Added 1 observation"
            } else {
                "Added \(model.analysisSessionState.observationsWritten) observations"
            }
        case .failed: "Analysis needs attention"
        case .cancelled: "Analysis cancelled"
        }
    }

    private var detail: String {
        let state = model.analysisSessionState
        switch state.phase {
        case .idle:
            guard let provider = model.settings.provider else {
                return "Choose and connect a local CLI provider in Settings first."
            }
            if provider == .openRouter {
                return "Native review analysis currently supports Claude, Codex, and Jcode CLI."
            }
            if model.providerConnection != .connected {
                return "Reconnect \(provider.displayName) in Settings before analyzing."
            }
            let count = model.captureProgress.captureCount ?? 0
            return "\(count) screenshot\(count == 1 ? "" : "s") available. Preparation stays on this Mac."
        case .ingesting:
            return "Qaptr is opening committed captures. Nothing has left this Mac."
        case .preparing:
            return "OCR is extracting text while privacy rules remove sensitive content before approval."
        case .readyForConsent:
            return "Review exactly what will be sent before the provider is invoked."
        case .analyzing:
            return "Only the privacy-filtered text you approved is with the selected provider. Screenshot files remain local."
        case .completed:
            if state.outcome == "consent_declined" {
                return "Nothing was sent. Prepared context stayed local."
            }
            return "The observation list has been refreshed from durable history."
        case .failed:
            return failureDetail(state.error)
        case .cancelled:
            return "No partial observation batch was saved."
        }
    }

    private func failureDetail(_ error: String?) -> String {
        switch error {
        case "no_committed_bundles": "No captured screenshots are ready yet."
        case "provider_unavailable", "provider_failed":
            "The selected CLI could not complete analysis. Reconnect it in Settings and try again."
        case "local_review_failed": "Local preparation could not complete. Try again."
        default: "Try again, or check the selected provider in Settings."
        }
    }
}

private extension ReviewSessionPhase {
    var isActivelyWorking: Bool {
        self == .ingesting || self == .preparing || self == .analyzing
    }
}

private struct AnalysisProgressView: View {
    let state: ReviewSessionState
    let providerName: String?

    private let stages = AnalysisProgressStage.allCases

    var body: some View {
        HStack(alignment: .top, spacing: QaptrSpace.md) {
            ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    HStack(spacing: QaptrSpace.xs) {
                        ZStack {
                            Circle()
                                .fill(stage.fill(for: state.phase))
                                .frame(width: 18, height: 18)
                            if stage.isComplete(for: state.phase) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.qaptrSuccess)
                            } else {
                                Text("\(index + 1)")
                                    .font(QaptrType.meta(8.5))
                                    .foregroundStyle(stage.isCurrent(for: state.phase) ? Color.qaptrAccentStrong : Color.qaptrInkMuted)
                            }
                        }
                        Text(stage.title)
                            .font(QaptrType.title(11.5))
                            .foregroundStyle(stage.isUpcoming(for: state.phase) ? Color.qaptrInkMuted : Color.qaptrInk)
                    }
                    Text(stage.detail(state: state, providerName: providerName))
                        .font(QaptrType.caption(10.5))
                        .foregroundStyle(Color.qaptrInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, QaptrSpace.sm)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.qaptrHairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analysis progress")
    }
}

private enum AnalysisProgressStage: Int, CaseIterable {
    case collect
    case protect
    case analyze

    var title: String {
        switch self {
        case .collect: "Find captures"
        case .protect: "Protect locally"
        case .analyze: "Create observations"
        }
    }

    func detail(state: ReviewSessionState, providerName: String?) -> String {
        switch self {
        case .collect:
            return state.capturesSeen > 0
                ? "\(state.capturesSeen) found"
                : "Reading the local vault"
        case .protect:
            if state.preparedCaptures > 0 {
                return "\(state.preparedCaptures) ready · \(state.exclusionCount) kept out"
            }
            return "OCR and privacy checks"
        case .analyze:
            return state.phase == .analyzing
                ? "Approved text with \(providerName ?? "provider")"
                : "Waits for your approval"
        }
    }

    func isComplete(for phase: ReviewSessionPhase) -> Bool {
        rawValue < currentIndex(for: phase)
    }

    func isCurrent(for phase: ReviewSessionPhase) -> Bool {
        rawValue == currentIndex(for: phase)
    }

    func isUpcoming(for phase: ReviewSessionPhase) -> Bool {
        rawValue > currentIndex(for: phase)
    }

    func fill(for phase: ReviewSessionPhase) -> Color {
        if isComplete(for: phase) { return Color.qaptrSoftMint }
        if isCurrent(for: phase) { return Color.qaptrAccentTintStrong }
        return Color.qaptrPaperMist
    }

    private func currentIndex(for phase: ReviewSessionPhase) -> Int {
        switch phase {
        case .ingesting: 0
        case .preparing: 1
        case .analyzing: 2
        default: 0
        }
    }
}

private struct AnalysisConsentView: View {
    @Bindable var model: ReviewAppModel
    let summary: ReviewConsentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.xl) {
            VStack(alignment: .leading, spacing: QaptrSpace.xs) {
                Text("Send prepared text?")
                    .font(QaptrType.editorial(30))
                    .foregroundStyle(Color.qaptrInk)
                Text("Review the exact boundary before Qaptr contacts \(summary.provider). Nothing is sent unless you approve.")
                    .font(QaptrType.body())
                    .foregroundStyle(Color.qaptrInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: QaptrSpace.md) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.qaptrSuccess)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text(AnalysisConsentPresentation.privacyTitle(summary))
                        .font(QaptrType.title(13))
                        .foregroundStyle(Color.qaptrInk)
                    Text(AnalysisConsentPresentation.privacyExplanation(summary))
                        .font(QaptrType.caption())
                        .foregroundStyle(Color.qaptrInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(QaptrSpace.md)
            .background(
                Color.qaptrSoftMint.opacity(0.72),
                in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
            )

            VStack(alignment: .leading, spacing: QaptrSpace.sm) {
                consentRow("Provider", summary.provider)
                consentRow("Model", summary.modelLabel)
                consentRow("Sent to provider", AnalysisConsentPresentation.payloadLabel(summary))
                consentRow("Source captures", "\(summary.captureCount) prepared locally")
                consentRow("Screenshot files", summary.imageCount == 0 ? "None sent" : "\(summary.imageCount) sent")
                consentRow("Excluded locally", "\(summary.exclusionCount)")
            }

            if let error = model.analysisError {
                Text(error)
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrError)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Analysis consent failed: \(error)")
            }

            HStack(spacing: QaptrSpace.sm) {
                Button("Keep local") { model.decideAnalysisConsent(granted: false) }
                    .buttonStyle(.qaptrOutline)
                Button("Send text to \(summary.provider)") { model.decideAnalysisConsent(granted: true) }
                    .buttonStyle(.qaptrPrimary)
            }
        }
        .padding(QaptrSpace.xxl)
        .frame(width: 540, alignment: .leading)
        .background(Color.qaptrSurface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analysis consent for \(summary.provider)")
    }

    private func consentRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(QaptrType.meta(10.5))
                .foregroundStyle(Color.qaptrInkMuted)
            Spacer()
            Text(value)
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInk)
        }
    }
}

enum AnalysisConsentPresentation {
    static func privacyTitle(_ summary: ReviewConsentSummary) -> String {
        if summary.imageCount == 0 {
            return "Screenshot files stay on this Mac"
        }
        return "Screenshot files are included in this request"
    }

    static func payloadLabel(_ summary: ReviewConsentSummary) -> String {
        if summary.payloadKind == "text", summary.imageCount == 0 {
            return "Privacy-filtered OCR text"
        }
        return summary.payloadKind
    }

    static func privacyExplanation(_ summary: ReviewConsentSummary) -> String {
        if summary.imageCount == 0 {
            return "Qaptr extracted and privacy-filtered text from \(summary.captureCount) capture\(summary.captureCount == 1 ? "" : "s"). The provider receives that text, not the images."
        }
        return "This request includes \(summary.imageCount) image\(summary.imageCount == 1 ? "" : "s") and prepared context from \(summary.captureCount) capture\(summary.captureCount == 1 ? "" : "s")."
    }
}

/// One observation row: title, plain summary, and an honest confidence line.
///
/// Selecting a row opens only its already-durable scalar detail. It never opens
/// a vault bundle, invokes a provider, launches a tool, or executes anything.
private struct ObservationRow: View {
    let observation: QaptrObservation
    let index: Int
    let reduceMotion: Bool
    let select: () -> Void

    /// Whether this row has finished (or skipped) its entrance. Seeded once
    /// per row *identity* via the initializer below, not recomputed from a
    /// parent-level flag on every render.
    ///
    /// `@State`'s initial value is evaluated exactly once per SwiftUI
    /// identity (here, `observation.id` via `ForEach`), so seeding
    /// `hasAppeared` from `reduceMotion` in `init` gives every row that
    /// appears for the first time an honest, un-interruptible entrance,
    /// while a row whose identity SwiftUI already knows about (an unrelated
    /// re-render) keeps its already-settled state and does not replay.
    @State private var hasAppeared: Bool

    init(observation: QaptrObservation, index: Int, reduceMotion: Bool, select: @escaping () -> Void) {
        self.observation = observation
        self.index = index
        self.reduceMotion = reduceMotion
        self.select = select
        _hasAppeared = State(initialValue: reduceMotion)
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: QaptrSpace.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(observation.title)
                        .font(QaptrType.title(15))
                        .foregroundStyle(Color.qaptrInk)
                    Spacer(minLength: QaptrSpace.md)
                    ConfidenceTag(band: observation.confidenceBand)
                }
                Text(observation.summary)
                    .font(QaptrType.body())
                    .foregroundStyle(Color.qaptrInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 4)
        .onAppear {
            guard !reduceMotion, !hasAppeared else { return }
            withAnimation(QaptrMotion.easeOut(0.24).delay(Double(index) * 0.04)) {
                hasAppeared = true
            }
        }
    }
}

/// A quiet, mono-set confidence label. Never rounds an honest low score up.
private struct ConfidenceTag: View {
    let band: ConfidenceBand

    var body: some View {
        Text(band.label)
            .font(QaptrType.meta(10.5))
            .foregroundStyle(band == .high ? Color.qaptrSuccess : Color.qaptrInkSoft)
            .padding(.horizontal, QaptrSpace.sm)
            .padding(.vertical, QaptrSpace.xxs)
            .background(band == .high ? Color.qaptrSoftMint : Color.qaptrPaperMist, in: Capsule())
    }
}

/// Read-only provenance and confidence for one durable observation, plus the
/// two scalar-driven detail actions: generating the canonical workflow and
/// exporting one of its four Markdown variants. Both actions read and write
/// only durable `qaptr-store` records through `ReviewBridge`; neither opens
/// the source vault bundle, invokes a provider, or launches anything.
private struct ObservationDetailView: View {
    @Bindable var model: ReviewAppModel
    let observation: QaptrObservation
    @Environment(\.dismiss) private var dismiss
    @State private var generatedWorkflow: WorkflowSummary?
    @State private var actionMessage: String?
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.xl) {
            HStack(alignment: .top) {
                Text(observation.title)
                    .font(QaptrType.headline(22))
                    .foregroundStyle(Color.qaptrInk)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.qaptrQuiet)
            }

            Text(observation.summary)
                .font(QaptrType.body(14.5))
                .foregroundStyle(Color.qaptrInkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.qaptrHairline)

            VStack(alignment: .leading, spacing: QaptrSpace.sm) {
                detailLine("Confidence", observation.confidenceBand.label)
                detailLine("Session", observation.sessionID)
                detailLine("Capture", observation.captureID ?? "Source capture expired")
                detailLine(
                    "Created",
                    Date(timeIntervalSince1970: Double(observation.createdAtMillis) / 1_000)
                        .formatted(date: .abbreviated, time: .standard)
                )
            }

            Divider().overlay(Color.qaptrHairline)

            workflowActions

            Text("This view contains only durable scalar history. It does not open or export the original screenshot.")
                .font(QaptrType.caption())
                .foregroundStyle(Color.qaptrInkSoft)
        }
        .padding(QaptrSpace.xxxl)
        .frame(width: 480, alignment: .leading)
        .background(Color.qaptrSurface)
    }

    @ViewBuilder
    private var workflowActions: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            Text("Workflow")
                .font(QaptrType.title(13))
                .foregroundStyle(Color.qaptrInk)

            if let workflow = generatedWorkflow ?? existingWorkflow {
                Text(workflow.title)
                    .font(QaptrType.body(13))
                    .foregroundStyle(Color.qaptrInkSoft)
                HStack(spacing: QaptrSpace.sm) {
                    Button("Regenerate", action: generateWorkflow)
                        .buttonStyle(.qaptrOutline)
                        .disabled(isGenerating)
                    Menu("Export") {
                        ForEach(MarkdownExportVariant.allCases, id: \.self) { variant in
                            Button(variant.displayName) { exportWorkflow(workflow, variant: variant) }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.qaptrOutline)
                }
            } else {
                Button("Generate workflow", action: generateWorkflow)
                    .buttonStyle(.qaptrOutline)
                    .disabled(isGenerating)
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(actionMessage)
            }
        }
    }

    /// A workflow already present in durable history for this observation's
    /// session, so a person who reopens detail after generating once still
    /// sees the Export action rather than being asked to regenerate.
    private var existingWorkflow: WorkflowSummary? {
        model.snapshot.workflows.first { $0.sessionID == observation.sessionID }
    }

    private func generateWorkflow() {
        isGenerating = true
        actionMessage = nil
        let result = model.generateWorkflow(fromObservationID: observation.id)
        isGenerating = false
        switch result {
        case .success(let workflow):
            generatedWorkflow = workflow
            actionMessage = nil
        case .failure(let error):
            actionMessage = error.message
        }
    }

    private func exportWorkflow(_ workflow: WorkflowSummary, variant: MarkdownExportVariant) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = variant.suggestedFileName(workflowTitle: workflow.title)
        panel.allowedContentTypes = [.text]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if let error = model.exportWorkflow(workflowID: workflow.id, variant: variant, destination: destination) {
            actionMessage = error
        } else {
            actionMessage = "Saved \(variant.displayName) to \(destination.lastPathComponent)."
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.md) {
            Text(label)
                .font(QaptrType.meta(10.5))
                .foregroundStyle(Color.qaptrInkSoft)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInk)
                .textSelection(.enabled)
        }
    }
}


/// Honest empty states covering checklist 4.1 row 135: no captures yet, every
/// capture excluded during local privacy preparation (no safely prepared
/// captures), captures waiting for analysis, and analysis unavailable.
/// Each branch is driven only by already-known scalar state -- capture
/// count/status and the durable exclusion notices -- never by a guess.
struct EmptyStateView: View {
    let progress: CaptureProgressSnapshot
    let notices: [ExclusionNotice]
    let analysisStatus: ReviewAnalysisStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            Text(title)
                .font(QaptrType.body(14))
                .foregroundStyle(Color.qaptrInkSoft)
            Text(detail)
                .font(QaptrType.caption())
                .foregroundStyle(Color.qaptrInkSoft.opacity(0.75))
        }
    }

    private var title: String {
        Self.title(
            captureCount: progress.captureCount,
            notices: notices,
            analysisState: analysisStatus?.state
        )
    }
    private var detail: String {
        Self.detail(
            captureCount: progress.captureCount,
            statusLabel: progress.statusLabel,
            notices: notices,
            analysisState: analysisStatus?.state
        )
    }

    /// Whether every prepared capture was excluded rather than simply
    /// producing no observation worth reporting. This is only ever true when
    /// captures actually exist and at least one exclusion notice is present,
    /// so it never claims exclusion before any capture has happened.
    private nonisolated static func allCapturesExcluded(captureCount: Int?, notices: [ExclusionNotice]) -> Bool {
        guard let count = captureCount, count > 0 else { return false }
        return !notices.isEmpty
    }

    /// Pure decision logic behind the empty-state title, directly testable
    /// without a full `CaptureProgressSnapshot`.
    nonisolated static func title(
        captureCount: Int?, notices: [ExclusionNotice], analysisState: String? = nil
    ) -> String {
        switch captureCount {
        case .some(0):
            "No screenshots have been captured yet."
        case .some where allCapturesExcluded(captureCount: captureCount, notices: notices):
            "Every recent screenshot was excluded before analysis."
        case .some(let count) where count > 0 && analysisState == "unavailable":
            "\(count) screenshot\(count == 1 ? "" : "s") captured. Analysis is unavailable."
        case .some(let count) where count > 0:
            "\(count) screenshot\(count == 1 ? " is" : "s are") waiting for analysis."
        default:
            "No observations yet."
        }
    }

    /// Pure decision logic behind the empty-state detail line, directly
    /// testable without a full `CaptureProgressSnapshot`.
    nonisolated static func detail(
        captureCount: Int?, statusLabel: String, notices: [ExclusionNotice], analysisState: String? = nil
    ) -> String {
        switch captureCount {
        case .some(0):
            "\(statusLabel). Notes show up here after Qaptr checks a screenshot."
        case .some where allCapturesExcluded(captureCount: captureCount, notices: notices):
            "Local privacy preparation could not safely include any recent capture. See the notice below for the reason."
        case .some where captureCount ?? 0 > 0 && analysisState == "unavailable":
            "This build can capture screenshots, but it cannot turn them into observations yet."
        case .some where captureCount ?? 0 > 0:
            "Qaptr has not produced an observation yet."
        default:
            "Qaptr is still getting ready."
        }
    }
}

/// A plain, deliberate failure state with no icon and no styling flourish.
private struct ErrorStateView: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.md) {
            Text("Qaptr is not ready yet.")
                .font(QaptrType.title(15))
                .foregroundStyle(Color.qaptrInk)
            Text("Check that Qaptr is open, then try again.")
                .font(QaptrType.body())
                .foregroundStyle(Color.qaptrInkSoft)
            HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.md) {
                Button("Try again", action: retry)
                    .buttonStyle(.qaptrOutline)
                Text("If this keeps happening, open Settings to check your setup.")
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft.opacity(0.75))
            }
        }
    }
}

/// Quiet, count-only exclusion notices (R-P7). No capture content, ever.
private struct NoticesView: View {
    let notices: [ExclusionNotice]

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.xs) {
            ForEach(notices) { notice in
                Text(notice.text)
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft.opacity(0.75))
            }
        }
    }
}
