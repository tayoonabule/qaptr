import QaptrReviewCore
import SwiftUI

/// A short, truthful setup flow for capture, privacy, and provider preference.
struct OnboardingView: View {
    @Bindable var model: ReviewAppModel
    @State private var stage: OnboardingStage = .permissions
    @State private var direction: StageDirection = .forward
    @State private var showsProviderSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                progressIndicator
                Spacer(minLength: 12)
                Text("Step \(stage.rawValue + 1) of \(OnboardingStage.allCases.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            if reduceMotion {
                stageHeader
                content.padding(.top, 16)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    stageHeader
                    content
                }
                .id(stage)
                .transition(stageTransition)
            }

            Spacer(minLength: 28)

            HStack {
                if let previous = stage.previous {
                    QuietButton(title: "Back") {
                        go(to: previous, direction: .backward)
                    }
                }
                Spacer()
                PrimaryActionButton(
                    title: stage == .privacyConsent ? "Finish" : "Continue",
                    action: advance
                )
                .disabled(stage == .privacyConsent && model.loadError != nil)
            }
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.qaptrSurface)
        .sheet(isPresented: $showsProviderSetup, onDismiss: model.dismissProviderSetup) {
            ProviderSetupSheet(model: model)
        }
    }

    private enum StageDirection {
        case forward
        case backward
    }

    private var stageTransition: AnyTransition {
        switch direction {
        case .forward:
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
        case .backward:
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            )
        }
    }

    private var stageHeader: some View {
        Text(stage.title)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.primary)
    }

    private var progressIndicator: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStage.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(fill(for: candidate))
                    .frame(height: candidate == stage ? 3 : 2)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: stage)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stage.rawValue + 1) of \(OnboardingStage.allCases.count)")
    }

    private func fill(for candidate: OnboardingStage) -> AnyShapeStyle {
        if candidate == stage {
            AnyShapeStyle(Color.qaptrAccent)
        } else if candidate.rawValue < stage.rawValue {
            AnyShapeStyle(Color.primary.opacity(0.65))
        } else {
            AnyShapeStyle(Color.primary.opacity(0.12))
        }
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
        VStack(alignment: .leading, spacing: 0) {
            PermissionRow(
                title: "Screen Recording",
                detail: "Qaptr needs this to take small screenshots from time to time.",
                status: model.settings.screenRecordingStatus,
                actionTitle: "Allow",
                action: model.requestScreenRecording
            )
            Divider()
                .padding(.vertical, 4)
            PermissionRow(
                title: "App and window names",
                detail: "Optional. This helps Qaptr describe what you were doing. You can skip it.",
                status: model.settings.accessibilityContextStatus,
                actionTitle: "Allow",
                action: model.requestAccessibilityContext
            )
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private var displaysStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr can use all of your screens.")
                .font(.system(size: 14, weight: .medium))
            Text("You can choose fewer screens later in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("\(model.settings.availableDisplayIDs.count) screens available")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var captureExplanationStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr takes one screenshot every \(CaptureIntervalPolicy.humanized(model.settings.intervalSeconds)).")
                .font(.system(size: 14, weight: .medium))
            Text("It does not record all the time. It does not read your clipboard or keys.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var providerSelectionStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an analysis tool, or leave this empty for capture-only mode.")
                .font(.system(size: 14, weight: .medium))
            Text("This saves your choice. Qaptr will not send anything just because you choose it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            ProviderChoiceList(selection: model.settings.provider) { provider in
                model.connectProvider(provider)
                if provider == .openRouter {
                    showsProviderSetup = true
                }
            }
                .padding(.top, 2)
        }
    }

    private var privacyConsentStage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your screenshots stay on this Mac until you approve a review.")
                .font(.system(size: 14, weight: .medium))
            Text("Qaptr hides text, faces, and barcodes before approved content is shared with a provider.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if model.loadError != nil {
                Text("Setup could not finish. Try again after reopening Qaptr.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    private func advance() {
        if let next = stage.next {
            go(to: next, direction: .forward)
        } else {
            guard model.loadError == nil else { return }
            model.completeOnboarding()
        }
    }

    private func go(to next: OnboardingStage, direction newDirection: StageDirection) {
        direction = newDirection
        if reduceMotion {
            stage = next
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                stage = next
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                Text(status.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(status == .granted ? .green : .secondary)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status != .granted {
                ActionButton(title: actionTitle, action: action)
            }
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }
}

private struct ProviderChoiceList: View {
    let selection: ProviderChoice?
    let select: (ProviderChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ProviderChoice.allCases, id: \.self) { provider in
                ProviderRow(provider: provider, isSelected: provider == selection) {
                    select(provider)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ProviderRow: View {
    let provider: ProviderChoice
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Text(isSelected ? "Selected" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.qaptrAccent)
                    .frame(width: 52, alignment: .leading)
                Text(provider.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.qaptrAccent.opacity(0.09) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(provider.displayName), \(isSelected ? "selected" : "not selected")")
    }
}
