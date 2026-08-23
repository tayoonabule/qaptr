import AppKit
import QaptrReviewCore
import Observation
import SwiftUI

// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V5

/// The retained AppKit window still accepts review and settings commands, but
/// the primary app no longer uses persistent in-window navigation.
enum ReviewSurface: Equatable {
    case review
    case settings

    var probeName: String {
        switch self {
        case .review: "review"
        case .settings: "settings"
        }
    }
}

@MainActor
@Observable
final class ReviewNavigation {
    var surface: ReviewSurface = .review
}

/// The post-onboarding shell. Review is one adaptive canvas. Settings remains a
/// policy-checked destination for existing helper and menu commands, without
/// becoming a permanent rail beside the user's work.
struct ContentView: View {
    @Bindable var model: ReviewAppModel
    @Bindable var navigation: ReviewNavigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        QaptrGlassBackdrop {
            ZStack {
                if navigation.surface == .settings {
                    settingsSurface
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    WorkflowSuggestionsView(
                        model: model,
                        openSettings: { setSurface(.settings) }
                    )
                    // Review leaves toward the leading edge when Settings is
                    // opened. Settings uses the opposite edge, so the two
                    // surfaces do not appear to chase each other rightward.
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            while !Task.isCancelled {
                model.refreshCaptureProgress()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private var settingsSurface: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    setSurface(.review)
                } label: {
                    Label("Review", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Return to Review")

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            QaptrGlassPanel(padding: 0) {
                SettingsView(model: model)
            }
            .padding(.horizontal, QaptrSpace.xxl)
            .padding(.vertical, QaptrSpace.lg)
        }
    }

    private func setSurface(_ surface: ReviewSurface) {
        if reduceMotion {
            navigation.surface = surface
        } else {
            withAnimation(QaptrMotion.navigation) {
                navigation.surface = surface
            }
        }
    }
}

enum CaptureStatusPresentation: Equatable {
    case live
    case paused
    case needsAttention

    static func present(
        intent: CaptureControlIntent,
        helperIsRunning: Bool
    ) -> CaptureStatusPresentation {
        if intent == .paused { return .paused }
        return helperIsRunning ? .live : .needsAttention
    }

    var label: String {
        switch self {
        case .live: "Capture on"
        case .paused: "Capture paused"
        case .needsAttention: "Capture needs attention"
        }
    }

    var accessibilityLabel: String { label }

    var isActive: Bool { self == .live }
}

/// The root view keeps the existing privacy/onboarding gate intact.
struct RootView: View {
    @Bindable var model: ReviewAppModel
    @Bindable var navigation: ReviewNavigation

    var body: some View {
        Group {
            if model.onboardingCompleted {
                ContentView(model: model, navigation: navigation)
            } else {
                OnboardingView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
    }
}
