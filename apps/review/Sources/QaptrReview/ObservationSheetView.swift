import QaptrReviewCore
import SwiftUI

/// The primary surface: a small, honest list of recent observations.
///
/// Deliberately not a dashboard. There is no grid, no card chrome, no
/// decorative icon per row — a plain vertical list of title, summary, and an
/// honest confidence line, closer to a note than a control panel (R-D3).
struct ObservationSheetView: View {
    @Bindable var model: ReviewAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the entrance animation for `observationList` has already
    /// played. The staggered fade-and-rise is tied to this view's own
    /// `onAppear` rather than to `snapshot` changes: `.onAppear { model.refresh() }`
    /// can fire a re-render with identical data (e.g. window refocus), and
    /// keying the animation off "did the snapshot change" would replay the
    /// stagger on every routine refresh. Tying it to "has this view instance
    /// appeared before" plays the entrance once per appearance of the sheet,
    /// which reads as a genuine first-render effect without re-animating on
    /// every background poll.
    @State private var hasPlayedEntrance = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let loadError = model.loadError {
                    ErrorStateView(message: loadError)
                } else if model.snapshot.observations.isEmpty {
                    EmptyStateView()
                } else {
                    observationList
                }

                if !model.snapshot.notices.isEmpty {
                    NoticesView(notices: model.snapshot.notices)
                }
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            model.refresh()
            hasPlayedEntrance = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Qaptr")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(model.snapshot.observations.isEmpty ? "No observations yet" : "What Qaptr noticed")
                .font(.system(size: 28, weight: .semibold, design: .default))
        }
    }

    private var observationList: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(model.snapshot.recentObservations.enumerated()), id: \.element.id) { index, observation in
                ObservationRow(
                    observation: observation,
                    entranceDelay: reduceMotion || hasPlayedEntrance ? nil : Double(index) * 0.04
                )
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
    /// Stagger delay in seconds for this row's entrance, or `nil` to skip the
    /// entrance animation entirely (reduced motion, or the sheet has already
    /// played its entrance once).
    let entranceDelay: Double?

    @State private var hasAppeared = false

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
        .opacity(entranceOpacity)
        .offset(y: entranceOffset)
        .onAppear {
            guard let entranceDelay else {
                hasAppeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.24).delay(entranceDelay)) {
                hasAppeared = true
            }
        }
    }

    private var entranceOpacity: Double {
        entranceDelay == nil || hasAppeared ? 1 : 0
    }

    private var entranceOffset: Double {
        entranceDelay == nil || hasAppeared ? 0 : 4
    }
}

/// The Granola-level empty state: quiet, no illustration, no call to action
/// that would suggest launching anything.
private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr hasn't analyzed a session yet.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text("Observations appear here after Qaptr reviews your recent captures.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A plain, deliberate failure state with no icon and no styling flourish.
private struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr couldn't load recent observations.")
                .font(.system(size: 15, weight: .medium))
            Text(message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
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
