import SwiftUI

/// Native Settings cannot bypass first-run capture consent. AppKit, SwiftUI,
/// and distributed open-settings requests all arrive through this policy.
enum SettingsEntryRoute: Equatable {
  case settings
  case primaryUI
}

enum SettingsEntryPolicy {
  static func route(onboardingCompleted: Bool) -> SettingsEntryRoute {
    onboardingCompleted ? .settings : .primaryUI
  }
}

struct NativeSettingsEntryView: View {
  @Bindable var model: ReviewAppModel
  let redirectToPrimaryUI: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      switch SettingsEntryPolicy.route(onboardingCompleted: model.onboardingCompleted) {
      case .settings:
        SettingsView(model: model)
      case .primaryUI:
        SettingsBlockedView(redirectToPrimaryUI: redirectToPrimaryUI)
      }
    }
    .transaction { transaction in
      if reduceMotion { transaction.animation = nil }
    }
  }
}

private struct SettingsBlockedView: View {
  let redirectToPrimaryUI: () -> Void
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Finish setup first", systemImage: "lock.shield")
        .font(.headline)
        .foregroundStyle(.secondary)

      Text("Settings is available after capture setup")
        .font(.title2)
        .fontWeight(.semibold)

      Text(
        "Qaptr keeps capture and privacy controls behind the same sequential permission flow. Complete Screen Recording setup first. No capture or provider request starts from this screen."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Button("Return to Qaptr setup", action: redirectToPrimaryUI)
        .keyboardShortcut(.defaultAction)
        .focused($isFocused)
        .buttonStyle(.borderedProminent)
        .onAppear { isFocused = true }
    }
    .padding(32)
    .frame(minWidth: 480, minHeight: 280, alignment: .topLeading)
    .accessibilityElement(children: .contain)
  }
}
