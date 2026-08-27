import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel

  var body: some View {
    ZStack(alignment: .bottom) {
      QaptrCanvas()

      routedScreen
        .frame(width: 845, height: 737)
        .clipped()

      if let toast = model.toast {
        QToast(text: toast) { model.toast = nil }
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }

    }
    .animation(.snappy(duration: 0.28), value: model.screen)
    .animation(.easeOut(duration: 0.18), value: model.toast)
    .ignoresSafeArea()
  }

  @ViewBuilder
  private var routedScreen: some View {
    switch model.screen {
    case .setupPermission, .setupWaiting, .setupDenied:
      OnboardingView(model: model, state: model.screen)
    case .homeEmpty, .homeFindings, .homePaused, .homeAttention, .homeAnalyzing,
      .homeReady, .homeQuietResult, .homeContextNudge, .homeWatching, .homeWatchingDone:
      HomeView(model: model, state: model.screen)
    case .consentReview, .providerChoice:
      ConsentView(model: model, state: model.screen)
    case .settings, .settingsNeverCapture:
      SettingsView(model: model, state: model.screen)
    case .findingComplete, .findingIncomplete, .findingCorrection, .findingSaved:
      FindingDetailView(model: model, state: model.screen)
    case .menuCapturing:
      HomeView(model: model, state: .homeFindings)
    case .menuAttention:
      HomeView(model: model, state: .homeAttention)
    case .menuDetailed:
      HomeView(model: model, state: .homeWatching)
    case .menuApproval:
      ConsentView(model: model, state: .consentReview)
    case .toastSpec:
      ToastSpecView(model: model)
    }
  }
}
