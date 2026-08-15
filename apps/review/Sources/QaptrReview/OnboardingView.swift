import QaptrReviewCore
import SwiftUI

/// A short, truthful setup flow for capture, privacy, and provider preference.
///
/// Every stage is driven purely by `OnboardingStage`/`OnboardingCopy` --
/// forward-only, one-time, and the provider connection sheet only ever
/// appears from the final `providerSelection` stage onward, never before.
/// This preserves KTD10's just-in-time consent boundary: no provider is
/// ever contacted before the person has read every earlier stage.
struct OnboardingView: View {
    @Bindable var model: ReviewAppModel
    @State private var stage: OnboardingStage = .permissions
    @State private var direction: StageDirection = .forward
    @State private var showsProviderSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.md) {
                Text("QAPTR")
                    .font(QaptrType.meta())
                    .tracking(1.2)
                    .foregroundStyle(Color.qaptrInk)
                Spacer(minLength: QaptrSpace.md)
                Text("STEP \(stage.rawValue + 1) OF \(OnboardingStage.allCases.count)")
                    .font(QaptrType.meta(10.5))
                    .tracking(1.0)
                    .foregroundStyle(Color.qaptrInkMuted)
            }
            progressIndicator
                .padding(.top, QaptrSpace.md)

            if reduceMotion {
                stageCard
                    .padding(.top, QaptrSpace.xl)
            } else {
                stageCard
                .id(stage)
                .transition(stageTransition)
                .padding(.top, QaptrSpace.xl)
            }

            Spacer(minLength: QaptrSpace.xxl)

            HStack {
                if let previous = stage.previous {
                    Button("Back") {
                        go(to: previous, direction: .backward)
                    }
                    .buttonStyle(.qaptrQuiet)
                }
                Spacer()
                Button(stage == .privacyConsent ? "Finish" : "Continue", action: advance)
                    .buttonStyle(.qaptrPrimary)
                    .disabled(
                        stage == .privacyConsent
                            && (model.loadError != nil || !model.isOnboardingCompletionEligible)
                    )
            }
        }
        .padding(QaptrSpace.xl)
        .frame(maxWidth: 600, alignment: .leading)
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
            .font(QaptrType.display(30))
            .foregroundStyle(Color.qaptrInk)
    }

    private var stageCard: some View {
        QaptrCard(padding: QaptrSpace.xl) {
            VStack(alignment: .leading, spacing: QaptrSpace.lg) {
                stageHeader
                content
            }
        }
    }

    /// A row of hairline segments, one per stage, filled with the accent as
    /// the person advances. Replaces the previous build's opacity-only
    /// primary-color capsules with the same three-tier language used
    /// elsewhere (accent / ink / hairline).
    private var progressIndicator: some View {
        HStack(spacing: QaptrSpace.xs) {
            ForEach(OnboardingStage.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(fill(for: candidate))
                    .frame(height: candidate == stage ? 3 : 2)
                    .animation(reduceMotion ? nil : QaptrMotion.easeOut(0.18), value: stage)
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
            AnyShapeStyle(Color.qaptrInkSoft)
        } else {
            AnyShapeStyle(Color.qaptrHairline)
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
                detail: PermissionRationale.screenRecording,
                status: model.settings.screenRecordingStatus,
                actionTitle: "Allow",
                action: model.requestScreenRecording
            )
            Divider().overlay(Color.qaptrHairline).padding(.vertical, QaptrSpace.md)
            PermissionRow(
                title: "App and window names",
                detail: PermissionRationale.accessibilityContext,
                status: model.settings.accessibilityContextStatus,
                actionTitle: "Allow",
                action: model.requestAccessibilityContext
            )
        }
    }

    private var displaysStage: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            Text("Qaptr can use all of your screens.")
                .font(QaptrType.title())
                .foregroundStyle(Color.qaptrInk)
            Text("You can choose fewer screens later in Settings.")
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
            Text("\(model.settings.availableDisplayIDs.count) screens available")
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
                .padding(.top, QaptrSpace.xs)
        }
        .accessibilityElement(children: .combine)
    }

    private var captureExplanationStage: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            Text(OnboardingCopy.periodicCaptureStatement(intervalSeconds: model.settings.intervalSeconds))
                .font(QaptrType.title())
                .foregroundStyle(Color.qaptrInk)
            Text(OnboardingCopy.captureBoundaryStatement)
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private var providerSelectionStage: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.md) {
            Text("Choose an analysis tool, or leave this empty for capture-only mode.")
                .font(QaptrType.title())
                .foregroundStyle(Color.qaptrInk)
            Text(OnboardingCopy.providerTransmissionStatement(provider: model.settings.provider))
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
            OnboardingProviderChoiceList(selection: model.settings.provider) { provider in
                model.connectProvider(provider)
                if provider == .openRouter {
                    showsProviderSetup = true
                }
            }
            .padding(.top, QaptrSpace.xxs)
        }
    }

    private var privacyConsentStage: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            Text("Your screenshots stay on this Mac until you approve a review.")
                .font(QaptrType.title())
                .foregroundStyle(Color.qaptrInk)
            Text(OnboardingCopy.localPreparationStatement)
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
            Text(OnboardingCopy.justInTimeConsentStatement)
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
            if model.loadError != nil {
                Text("Setup could not finish. Try again after reopening Qaptr.")
                    .font(QaptrType.title(13))
                    .foregroundStyle(Color.qaptrError)
                    .padding(.top, QaptrSpace.xs)
                    .accessibilityLabel("Setup error: setup could not finish. Try again after reopening Qaptr.")
            }
        }
        .accessibilityElement(children: .combine)
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
            withAnimation(QaptrMotion.easeOut(0.18)) {
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
        VStack(alignment: .leading, spacing: QaptrSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.md) {
                Text(title)
                    .font(QaptrType.title(14.5))
                    .foregroundStyle(Color.qaptrInk)
                Spacer(minLength: QaptrSpace.sm)
                Text(status.label)
                    .font(QaptrType.meta(10.5))
                    .foregroundStyle(status == .granted ? Color.qaptrAccent : Color.qaptrInkSoft)
            }
            Text(detail)
                .font(QaptrType.caption())
                .foregroundStyle(Color.qaptrInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if status != .granted {
                Button(actionTitle, action: action)
                    .buttonStyle(.qaptrOutline)
            }
        }
        .padding(.vertical, QaptrSpace.sm)
        .accessibilityElement(children: .contain)
    }
}

/// Onboarding's own provider list, distinct from the Settings list, since it
/// carries no "not selected" affordance -- leaving a provider unset here is
/// a legitimate capture-only choice, not an omission to correct.
private struct OnboardingProviderChoiceList: View {
    let selection: ProviderChoice?
    let select: (ProviderChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
            ForEach(ProviderChoice.allCases, id: \.self) { provider in
                Button {
                    select(provider)
                } label: {
                    HStack(spacing: QaptrSpace.sm) {
                        Circle()
                            .strokeBorder(selection == provider ? Color.qaptrAccent : Color.qaptrBorderStrong, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                            .overlay {
                                if selection == provider {
                                    Circle().fill(Color.qaptrAccent).frame(width: 8, height: 8)
                                }
                            }
                        Text(provider.displayName)
                            .font(QaptrType.body(14))
                            .foregroundStyle(Color.qaptrInk)
                        Spacer()
                    }
                    .padding(.horizontal, QaptrSpace.sm)
                    .padding(.vertical, QaptrSpace.sm)
                    .background(
                        selection == provider ? Color.qaptrAccentTint : Color.clear,
                        in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactile)
                .accessibilityAddTraits(selection == provider ? .isSelected : [])
                .accessibilityLabel(provider.displayName)
                .accessibilityValue(selection == provider ? "Selected" : "Not selected")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider")
    }
}
