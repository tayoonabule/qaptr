import QaptrReviewCore
import SwiftUI

/// The top-level window content: the Observation Sheet by default, with a
/// toolbar-driven switch to Settings. The two surfaces crossfade on the
/// shared `QaptrMotion.easeOut` curve rather than sliding or springing, so
/// switching surfaces reads as the same one continuous motion language used
/// everywhere else in the app.
struct ContentView: View {
    @Bindable var model: ReviewAppModel
    @State private var showsSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showsSettings {
                SettingsView(model: model, showObservations: toggleSurface)
                    .transition(.opacity)
            } else {
                ObservationSheetView(model: model, showSettings: toggleSurface)
                    .transition(.opacity)
            }
        }
    }

    private func toggleSurface() {
        if reduceMotion {
            showsSettings.toggle()
        } else {
            withAnimation(QaptrMotion.easeOut(0.22)) {
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
