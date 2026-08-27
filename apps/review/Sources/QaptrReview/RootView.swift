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
        ZStack(alignment: .top) {
            ReviewDesign.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                QaptrTitleBar(title: navigation.surface == .settings ? "Settings" : "Home")
                if navigation.surface == .settings {
                    settingsSurface
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    WorkflowSuggestionsView(
                        model: model,
                        openSettings: { setSurface(.settings) }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .frame(width: 845, height: 737)
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
        ZStack(alignment: .topLeading) {
            SettingsView(model: model)
            Button { setSurface(.review) } label: {
                Label("Home", systemImage: "chevron.left")
            }
            .font(QaptrType.body(13))
            .foregroundStyle(Color.qaptrFigmaMuted)
            .buttonStyle(.plain)
            .padding(.leading, 40)
            .padding(.top, 18)
            .accessibilityLabel("Return to Home")
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
                WelcomeView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
    }
}
