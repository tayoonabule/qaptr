import QaptrReviewCore
import SwiftUI

/// The primary surface: a small, honest list of recent observations.
struct ObservationSheetView: View {
    @Bindable var model: ReviewAppModel
    let showSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedObservation: QaptrObservation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.reviewStatus != nil || model.reviewStatusError != nil {
                    QaptrCard(padding: QaptrSpace.lg) {
                        reviewStatusSummary
                    }
                    .padding(.top, QaptrSpace.md)
                }

                if model.loadError != nil {
                    ErrorStateView(retry: model.refresh)
                        .padding(.top, QaptrSpace.lg)
                } else {
                    captureProgress
                        .padding(.top, QaptrSpace.lg)
                    if model.snapshot.observations.isEmpty {
                        EmptyStateView(progress: model.captureProgress)
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
            .padding(QaptrSpace.lg)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.qaptrSurface)
        .sheet(item: $selectedObservation) { observation in
            ObservationDetailView(observation: observation)
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
        HStack(alignment: .top, spacing: QaptrSpace.lg) {
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
                    .font(QaptrType.display())
                    .foregroundStyle(Color.qaptrInk)
            }
            Spacer(minLength: QaptrSpace.lg)
            Button("Settings", action: showSettings)
                .buttonStyle(.qaptrOutline)
        }
        .padding(QaptrSpace.lg)
        .background(Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.feature, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: QaptrRadius.feature, style: .continuous)
                .strokeBorder(Color.qaptrHairline, lineWidth: 1)
        }
    }

    private var headerTitle: String {
        if model.loadError != nil {
            return "Review setup"
        }
        return model.snapshot.observations.isEmpty ? "Nothing here yet" : "What Qaptr found"
    }

    private var captureProgress: some View {
        QaptrCard {
            VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.xxl) {
                VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                    Text("Screenshots captured")
                        .font(QaptrType.meta())
                        .foregroundStyle(Color.qaptrInkSoft)
                    Text(model.captureProgress.captureCount.map(String.init) ?? "Not available")
                        .font(QaptrType.headline(21))
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
        }
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
        VStack(alignment: .leading, spacing: QaptrSpace.md) {
            ForEach(Array(model.snapshot.recentObservations.enumerated()), id: \.element.id) { index, observation in
                QaptrCard(padding: QaptrSpace.lg) {
                    ObservationRow(
                        observation: observation,
                        index: index,
                        reduceMotion: reduceMotion,
                        select: { selectedObservation = observation }
                    )
                }
            }
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

/// Read-only provenance and confidence for one durable observation.
private struct ObservationDetailView: View {
    let observation: QaptrObservation
    @Environment(\.dismiss) private var dismiss

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

            Text("This view contains only durable scalar history. It does not open or export the original screenshot.")
                .font(QaptrType.caption())
                .foregroundStyle(Color.qaptrInkSoft)
        }
        .padding(QaptrSpace.xxl)
        .frame(width: 480, alignment: .leading)
        .background(Color.qaptrSurface)
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

/// A quiet empty state: no illustration, no call to action that would
/// suggest launching anything.
private struct EmptyStateView: View {
    let progress: CaptureProgressSnapshot

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
        switch progress.captureCount {
        case .some(0):
            "No screenshots have been captured yet."
        case .some(let count) where count > 0:
            "\(count) screenshot\(count == 1 ? " is" : "s are") ready. Nothing new was found."
        default:
            "No observations yet."
        }
    }

    private var detail: String {
        switch progress.captureCount {
        case .some(0):
            "\(progress.statusLabel). Notes show up here after Qaptr checks a screenshot."
        case .some where progress.captureCount ?? 0 > 0:
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
