import SwiftUI

/// The only native Settings routes are allowed to choose between the real
/// Settings surface and the primary setup UI through this policy.
///
/// `onboardingCompleted` is persisted only after the final privacy/capture
/// explanation and explicit Finish action. Reusing it here keeps Cmd+,,
/// SwiftUI's Settings scene, and distributed open-settings requests from
/// bypassing the same consent boundary as the primary UI.
enum SettingsEntryRoute: Equatable {
    case settings
    case primaryUI
}

enum SettingsEntryPolicy {
    static func route(onboardingCompleted: Bool) -> SettingsEntryRoute {
        onboardingCompleted ? .settings : .primaryUI
    }
}

/// The Settings scene can still be requested directly by AppKit or SwiftUI,
/// so it must enforce the gate independently of the command and notification
/// handlers. Before onboarding is complete this is intentionally a blocked
/// state, not a partial Settings surface that could mutate capture behavior.
struct NativeSettingsEntryView: View {
    @Bindable var model: ReviewAppModel
    let redirectToPrimaryUI: () -> Void

    var body: some View {
        switch SettingsEntryPolicy.route(onboardingCompleted: model.onboardingCompleted) {
        case .settings:
            SettingsView(model: model)
        case .primaryUI:
            SettingsBlockedView(redirectToPrimaryUI: redirectToPrimaryUI)
        }
    }
}

private struct SettingsBlockedView: View {
    let redirectToPrimaryUI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Finish setup before opening Settings")
                .font(.title2)
                .fontWeight(.semibold)
            Text(
                "Qaptr keeps capture and privacy controls behind onboarding. Complete the Screen Recording and privacy steps first; no capture or provider request starts from this screen."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button("Return to Qaptr setup", action: redirectToPrimaryUI)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 260, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}
