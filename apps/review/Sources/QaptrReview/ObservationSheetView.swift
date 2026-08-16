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

                if model.loadError != nil {
                    ErrorStateView(retry: model.refresh)
                        .padding(.top, QaptrSpace.xl)
                } else {
                    statusLedger
                        .padding(.top, QaptrSpace.xl)
                    if model.snapshot.observations.isEmpty {
                        EmptyStateView(progress: model.captureProgress, notices: model.snapshot.notices)
                            .padding(.top, QaptrSpace.xl)
                    } else {
                        Text("RECENT OBSERVATIONS")
                            .font(QaptrType.meta(10.5))
                            .tracking(1)
                            .foregroundStyle(Color.qaptrInkMuted)
                            .padding(.top, QaptrSpace.xl)
                            .padding(.bottom, QaptrSpace.sm)
                        observationList
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
        VStack(alignment: .leading, spacing: QaptrSpace.md) {
            CaptureSignalBar(isActive: model.captureProgress.helperIsRunning)
            VStack(alignment: .leading, spacing: QaptrSpace.xs) {
                HStack(spacing: QaptrSpace.xs) {
                    Circle()
                        .fill(model.captureProgress.helperIsRunning ? Color.qaptrLive : Color.qaptrInkSoft.opacity(0.35))
                        .frame(width: 6, height: 6)
                    Text("QAPTR")
                        .font(QaptrType.meta())
                        .tracking(1.2)
                        .foregroundStyle(Color.qaptrInkSoft)
                }
                Text(headerTitle)
                    .font(QaptrType.editorial(38))
                    .foregroundStyle(Color.qaptrInk)
                Text("A readable record of what happened on this Mac.")
                    .font(QaptrType.body(14))
                    .foregroundStyle(Color.qaptrInkSoft)
            }
        }
        .padding(.bottom, QaptrSpace.lg)
    }

    private var statusLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            captureProgress
            if model.reviewStatus != nil || model.reviewStatusError != nil {
                ledgerRule
                reviewStatusSummary
                    .padding(.bottom, QaptrSpace.md)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.qaptrHairline).frame(height: 1)
        }
    }

    private func ledgerHeading(_ title: String) -> some View {
        Text(title)
            .font(QaptrType.meta(10))
            .tracking(1.1)
            .foregroundStyle(Color.qaptrInkMuted)
            .padding(.vertical, QaptrSpace.sm)
    }

    private var ledgerRule: some View {
        Divider().overlay(Color.qaptrHairline)
    }

    private var headerTitle: String {
        if model.loadError != nil {
            return "Review setup"
        }
        return model.snapshot.observations.isEmpty ? "Nothing here yet" : "What Qaptr found"
    }

    private var captureProgress: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            Text("Capture")
                .font(QaptrType.title(16))
                .foregroundStyle(Color.qaptrInk)
            HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.xxl) {
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text("Screenshots captured")
                        .font(QaptrType.meta())
                        .foregroundStyle(Color.qaptrInkSoft)
                    Text(model.captureProgress.captureCount.map(String.init) ?? "Not available")
                        .font(QaptrType.display(28))
                        .foregroundStyle(Color.qaptrInk)
                }
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text("Capture state")
                        .font(QaptrType.meta())
                        .foregroundStyle(Color.qaptrInkSoft)
                        Text(model.captureProgress.statusLabel)
                            .font(QaptrType.body())
                            .foregroundStyle(model.captureProgress.helperIsRunning ? Color.qaptrInk : Color.qaptrInkSoft)
                            .padding(.horizontal, QaptrSpace.sm)
                            .padding(.vertical, QaptrSpace.xxs)
                            .background(
                            model.captureProgress.helperIsRunning ? Color.qaptrAccentTint : Color.qaptrPaperMist,
                            in: Capsule()
                        )
                }
            }
            if let lastCaptureDate = model.captureProgress.lastCaptureDate {
                Text("Last capture \(lastCaptureDate, format: .dateTime.hour().minute().second())")
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft)
            } else {
                Text("No screenshot yet")
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft)
            }
            Text(captureConfigurationSummary)
                .font(QaptrType.caption())
                .foregroundStyle(Color.qaptrInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, QaptrSpace.md)
    }

    private var captureConfigurationSummary: String {
        let displays = model.captureProgress.selectedDisplayIDs
        let displaySummary = displays.isEmpty
            ? "No displays selected"
            : "\(displays.count) selected display\(displays.count == 1 ? "" : "s")"
        let interval = model.captureProgress.activeIntervalSeconds ?? model.captureIntervalSeconds
        return "\(displaySummary) · Every \(interval) seconds"
    }

    @ViewBuilder
    private var reviewStatusSummary: some View {
        if let status = model.reviewStatus {
            VStack(alignment: .leading, spacing: QaptrSpace.md) {
                Text("History")
                    .font(QaptrType.title(16))
                    .foregroundStyle(Color.qaptrInk)
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text("Durable history")
                        .font(QaptrType.title())
                        .foregroundStyle(Color.qaptrInk)
                    Text(historySummary(status.reviewSession))
                        .font(QaptrType.body(13))
                        .foregroundStyle(Color.qaptrInkSoft)
                }
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text("Live analysis unavailable")
                        .font(QaptrType.title())
                        .foregroundStyle(Color.qaptrInk)
                    Text(status.analysis.reason ?? "Live provider analysis is not available here.")
                        .font(QaptrType.body(13))
                        .foregroundStyle(Color.qaptrInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
                .accessibilityElement(children: .combine)
        } else if model.reviewStatusError != nil {
            Text("History status unavailable. Saved observations may still be shown.")
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func historySummary(_ session: ReviewSessionStatus) -> String {
        guard session.historyAvailable else { return "No saved observations yet." }
        let count = session.observationCount
        return "\(count) saved observation\(count == 1 ? "" : "s") available."
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
/// captures), captures prepared but nothing worth reporting, and the
/// existing analysis-unavailable state already shown by `reviewStatusSummary`.
/// Each branch is driven only by already-known scalar state -- capture
/// count/status and the durable exclusion notices -- never by a guess.
struct EmptyStateView: View {
    let progress: CaptureProgressSnapshot
    let notices: [ExclusionNotice]

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

    private var title: String { Self.title(captureCount: progress.captureCount, notices: notices) }
    private var detail: String {
        Self.detail(captureCount: progress.captureCount, statusLabel: progress.statusLabel, notices: notices)
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
    nonisolated static func title(captureCount: Int?, notices: [ExclusionNotice]) -> String {
        switch captureCount {
        case .some(0):
            "No screenshots have been captured yet."
        case .some where allCapturesExcluded(captureCount: captureCount, notices: notices):
            "Every recent screenshot was excluded before analysis."
        case .some(let count) where count > 0:
            "\(count) screenshot\(count == 1 ? " is" : "s are") ready. Nothing new was found."
        default:
            "No observations yet."
        }
    }

    /// Pure decision logic behind the empty-state detail line, directly
    /// testable without a full `CaptureProgressSnapshot`.
    nonisolated static func detail(captureCount: Int?, statusLabel: String, notices: [ExclusionNotice]) -> String {
        switch captureCount {
        case .some(0):
            "\(statusLabel). Notes show up here after Qaptr checks a screenshot."
        case .some where allCapturesExcluded(captureCount: captureCount, notices: notices):
            "Local privacy preparation could not safely include any recent capture. See the notice below for the reason."
        case .some where captureCount ?? 0 > 0:
            "Qaptr did not find a note to show."
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
