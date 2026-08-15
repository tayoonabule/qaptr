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
            VStack(alignment: .leading, spacing: 24) {
                header

                reviewStatusSummary

                if model.loadError != nil {
                    ErrorStateView(retry: model.refresh)
                } else {
                    captureProgress
                    if model.snapshot.observations.isEmpty {
                        EmptyStateView(progress: model.captureProgress)
                    } else {
                        observationList
                    }
                }

                if !model.snapshot.notices.isEmpty {
                    NoticesView(notices: model.snapshot.notices)
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Qaptr")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(headerTitle)
                    .font(.system(size: 26, weight: .bold))
            }
            Spacer(minLength: 18)
            ActionButton(title: "Settings", action: showSettings)
        }
    }

    private var headerTitle: String {
        if model.loadError != nil {
            return "Review setup"
        }
        return model.snapshot.observations.isEmpty ? "Nothing here yet" : "What Qaptr found"
    }

    private var captureProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Screenshots captured")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.captureProgress.captureCount.map(String.init) ?? "Not available")
                        .font(.system(size: 22, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capture state")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.captureProgress.statusLabel)
                        .font(.system(size: 13))
                }
            }
            if let lastCaptureDate = model.captureProgress.lastCaptureDate {
                Text("Last capture \(lastCaptureDate, format: .dateTime.hour().minute().second())")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
            Text("No screenshot yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private var reviewStatusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = model.reviewStatus {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Durable history")
                        .font(.system(size: 13, weight: .semibold))
                    Text(historySummary(status.reviewSession))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Live analysis unavailable")
                        .font(.system(size: 13, weight: .semibold))
                    Text(status.analysis.reason ?? "Live provider analysis is not available here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if model.reviewStatusError != nil {
                Text("History status unavailable. Saved observations may still be shown.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func historySummary(_ session: ReviewSessionStatus) -> String {
        guard session.historyAvailable else { return "No saved observations yet." }
        let count = session.observationCount
        return "\(count) saved observation\(count == 1 ? "" : "s") available."
    }

    private var observationList: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(model.snapshot.recentObservations.enumerated()), id: \.element.id) { index, observation in
                ObservationRow(
                    observation: observation,
                    index: index,
                    reduceMotion: reduceMotion,
                    select: { selectedObservation = observation }
                )
                Divider()
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
    /// An earlier version gated the stagger on a shared `hasPlayedEntrance`
    /// flag flipped in the sheet's own `.onAppear`. Because
    /// `ReviewAppModel.refresh()` is synchronous, that flip landed in the
    /// same render pass as the data load, so by the time `observationList`
    /// first rendered with real rows the flag was already `true` and no row
    /// ever animated on a genuine app launch. `@State`'s initial value is
    /// evaluated exactly once per SwiftUI identity (here, `observation.id`
    /// via `ForEach`), so seeding `hasAppeared` from `reduceMotion` in
    /// `init` gives every row that appears for the first time an honest,
    /// un-interruptible entrance, while a row whose identity SwiftUI already
    /// knows about (an unrelated re-render, e.g. a settings-driven refresh)
    /// keeps its already-settled state and does not replay or snap.
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
            VStack(alignment: .leading, spacing: 6) {
                Text(observation.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(observation.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Confidence: \(observation.confidenceBand.label)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 4)
        .onAppear {
            guard !reduceMotion, !hasAppeared else { return }
            withAnimation(.easeOut(duration: 0.24).delay(Double(index) * 0.04)) {
                hasAppeared = true
            }
        }
    }
}

/// Read-only provenance and confidence for one durable observation.
private struct ObservationDetailView: View {
    let observation: QaptrObservation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text(observation.title)
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                QuietButton(title: "Close") { dismiss() }
            }

            Text(observation.summary)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
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
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 520, alignment: .leading)
        .background(Color.qaptrSurface)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }
}

/// The Granola-level empty state: quiet, no illustration, no call to action
/// that would suggest launching anything.
private struct EmptyStateView: View {
    let progress: CaptureProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Qaptr is not ready yet.")
                .font(.system(size: 16, weight: .medium))
            Text("Check that Qaptr is open, then try again.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ActionButton(title: "Try again", action: retry)
                Text("If this keeps happening, open Settings to check your setup.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Quiet, count-only exclusion notices (R-P7). No capture content, ever.
private struct NoticesView: View {
    let notices: [ExclusionNotice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notices) { notice in
                Text(notice.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 8)
    }
}
