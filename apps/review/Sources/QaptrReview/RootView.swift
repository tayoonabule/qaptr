import QaptrReviewCore
import SwiftUI

/// The top-level window content: the Observation Sheet by default, with a
/// small toolbar-driven switch to Settings. Reduced-motion is respected by
/// disabling the section-switch transition.
struct ContentView: View {
    @Bindable var model: ReviewAppModel
    @State private var showsSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if showsSettings {
                SettingsView(model: model, showObservations: toggleSurface)
            } else {
                ObservationSheetView(model: model, showSettings: toggleSurface)
            }
        }
    }

    private func toggleSurface() {
        if reduceMotion {
            showsSettings.toggle()
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showsSettings.toggle()
            }
        }
    }
}

/// The root view: onboarding until completed, then the main content.
struct RootView: View {
    @Bindable var model: ReviewAppModel

    var body: some View {
        Group {
            if model.onboardingCompleted {
                ContentView(model: model)
            } else {
                OnboardingView(model: model)
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}
