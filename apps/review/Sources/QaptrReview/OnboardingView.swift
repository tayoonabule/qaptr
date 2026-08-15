import QaptrReviewCore
import SwiftUI

/// Truthful, non-nagging onboarding across five stages (R-D7, AE9).
///
/// Runs once per installation (`SettingsPreferences.onboardingCompleted`) and
/// never requests a provider before the final privacy-consent stage.
struct OnboardingView: View {
    @Bindable var model: ReviewAppModel
    @State private var stage: OnboardingStage = .permissions

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(stage.title)
                .font(.system(size: 26, weight: .semibold))

            content

            HStack {
                Spacer()
                Button(stage == .privacyConsent ? "Finish" : "Continue") {
                    advance()
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 4)
                .underline()
            }
        }
        .padding(40)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .permissions:
            permissionsStage
        case .displays:
            displaysStage
        case .captureExplanation:
            captureExplanationStage
        case .providerSelection:
            providerSelectionStage
        case .privacyConsent:
            privacyConsentStage
        }
    }

    private var permissionsStage: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(PermissionRationale.screenRecording)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(model.settings.screenRecordingStatus.label)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if model.settings.screenRecordingStatus != .granted {
                        Button("Grant Screen Recording") { model.requestScreenRecording() }
                            .buttonStyle(.plain)
                            .underline()
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(PermissionRationale.accessibilityContext)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(model.settings.accessibilityContextStatus.label)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if model.settings.accessibilityContextStatus != .granted {
                        Button("Grant (optional)") { model.requestAccessibilityContext() }
                            .buttonStyle(.plain)
                            .underline()
                    }
                }
            }
        }
    }

    private var displaysStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr will capture from all currently attached displays by default. You can narrow this to specific displays later in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("\(model.settings.availableDisplayIDs.count) display(s) detected")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var captureExplanationStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By default, Qaptr takes one downscaled screenshot every ten minutes and a point-in-time snapshot of the active app, window title, and reduced browser host.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("It never records continuously, and it never reads your clipboard or keystrokes.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var providerSelectionStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose which AI provider prepares your observations. You can change this later in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Picker("Provider", selection: providerBinding) {
                Text("Not selected").tag(ProviderChoice?.none)
                ForEach(ProviderChoice.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(ProviderChoice?.some(provider))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var privacyConsentStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr redacts recognized text, faces, and barcodes locally before anything reaches your chosen provider. It only sends data after you explicitly approve each analysis session.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("No provider request happens until you say so.")
                .font(.system(size: 14, weight: .medium))
        }
    }

    private var providerBinding: Binding<ProviderChoice?> {
        Binding(
            get: { model.settings.provider },
            set: { newValue in
                if let newValue {
                    model.setProvider(newValue)
                }
            }
        )
    }

    private func advance() {
        if let next = stage.next {
            stage = next
        } else {
            model.completeOnboarding()
        }
    }
}
