import QaptrReviewCore
import SwiftUI

/// The primary surface: a small, honest list of recent observations.
///
/// Deliberately not a dashboard. There is no grid, no card chrome, no
/// decorative icon per row — a plain vertical list of title, summary, and an
/// honest confidence line, closer to a note than a control panel (R-D3).
struct ObservationSheetView: View {
    @Bindable var model: ReviewAppModel
    let showSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

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
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.qaptrSurface)
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
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Qaptr")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(headerTitle)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
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
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
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
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
            Text("No screenshot yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var observationList: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(model.snapshot.recentObservations.enumerated()), id: \.element.id) { index, observation in
                ObservationRow(observation: observation, index: index, reduceMotion: reduceMotion)
                Divider()
            }
        }
    }
}

/// One observation row: title, plain summary, and an honest confidence line.
///
/// No affordance here executes anything. Selecting an observation is reserved
/// for a future "Qaptr in more detail" action (U18/U17), which this unit does
/// not implement; the row is read-only in U20.
private struct ObservationRow: View {
    let observation: QaptrObservation
    let index: Int
    let reduceMotion: Bool

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

    init(observation: QaptrObservation, index: Int, reduceMotion: Bool) {
        self.observation = observation
        self.index = index
        self.reduceMotion = reduceMotion
        _hasAppeared = State(initialValue: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(observation.title)
                .font(.system(size: 17, weight: .semibold))
            Text(observation.summary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(observation.confidenceBand.label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
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
