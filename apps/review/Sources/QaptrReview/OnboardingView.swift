import QaptrReviewCore
import SwiftUI

// Hallmark: Setup Desk layout. A compact orientation band, persistent stage map, and one focused work canvas.

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
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      setupBand
        .padding(.bottom, QaptrSpace.lg)

      HStack(alignment: .top, spacing: QaptrSpace.xl) {
        setupMap
          .frame(width: 220, alignment: .leading)

        VStack(alignment: .leading, spacing: 0) {
          if reduceMotion {
            stageCanvas
          } else {
            stageCanvas
              .id(stage)
              .transition(stageTransition)
          }

          workspaceFooter
            .padding(.top, QaptrSpace.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .padding(QaptrSpace.xxl)
    .frame(maxWidth: 900, alignment: .leading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.qaptrSurface)
    .sheet(isPresented: $showsProviderSetup, onDismiss: model.dismissProviderSetup) {
      ProviderSetupSheet(model: model)
    }
    .onAppear {
      model.refreshSettings()
      model.refreshCaptureProgress()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.refreshSettings()
        model.refreshCaptureProgress()
      }
    }
    .task {
      while !Task.isCancelled {
        model.refreshPermissions()
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
      }
    }
  }

  private var setupBand: some View {
    HStack(alignment: .center, spacing: QaptrSpace.lg) {
      QaptrBrandLogo(iconSize: 27, textSize: 23)

      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        Text("QAPTR / SETUP DESK")
          .font(QaptrType.meta())
          .tracking(1.15)
        Text("Set your capture boundary")
          .font(QaptrType.title(18))
      }
      Spacer(minLength: QaptrSpace.md)
      Text("ONE-TIME SETUP")
        .font(QaptrType.meta(10.5))
        .tracking(0.9)
    }
    .foregroundStyle(Color.qaptrInk)
    .padding(.horizontal, QaptrSpace.xl)
    .padding(.vertical, QaptrSpace.lg)
    .background(
      LinearGradient(
        colors: [Color.qaptrAccentTint, Color.qaptrPaperMist],
        startPoint: .leading,
        endPoint: .trailing
      ),
      in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
    )
    .accessibilityElement(children: .combine)
  }

  private var setupMap: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.sm) {
      Text("SETUP MAP")
        .font(QaptrType.meta(10.5))
        .tracking(1)
        .foregroundStyle(Color.qaptrInkMuted)

      ForEach(OnboardingStage.allCases, id: \.self) { candidate in
        Button {
          go(to: candidate, direction: candidate.rawValue >= stage.rawValue ? .forward : .backward)
        } label: {
          HStack(alignment: .center, spacing: QaptrSpace.sm) {
            ZStack {
              Circle()
                .fill(mapMarker(for: candidate))
                .frame(width: 20, height: 20)
              if candidate.rawValue < stage.rawValue {
                Image(systemName: "checkmark")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundStyle(Color.qaptrSurface)
              } else {
                Text("\(candidate.rawValue + 1)")
                  .font(QaptrType.meta(9.5))
                  .foregroundStyle(candidate == stage ? Color.qaptrSurface : Color.qaptrInkSoft)
              }
            }
            Text(candidate.title)
              .font(candidate == stage ? QaptrType.headline(13) : QaptrType.title(13))
              .foregroundStyle(candidate == stage ? Color.qaptrInk : Color.qaptrInkSoft)
          }
          .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.title), \(mapAccessibilityValue(for: candidate))")
      }
    }
    .padding(.trailing, QaptrSpace.xl)
  }

  private var stageCanvas: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      HStack(alignment: .firstTextBaseline) {
        Text("STEP \(stage.rawValue + 1) / \(OnboardingStage.allCases.count)")
          .font(QaptrType.meta(10.5))
          .tracking(1)
          .foregroundStyle(Color.qaptrAccentStrong)
        Spacer()
        progressIndicator
          .frame(width: 104)
      }
      stageHeader
      content
    }
    .padding(QaptrSpace.xxl)
    .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
    .background(
      Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
        .strokeBorder(Color.qaptrHairline, lineWidth: 1)
    }
  }

  private var workspaceFooter: some View {
    HStack(alignment: .center, spacing: QaptrSpace.md) {
      if let previous = stage.previous {
        Button("Back") {
          go(to: previous, direction: .backward)
        }
        .buttonStyle(.qaptrQuiet)
      }

      Text(
        stage == .privacyConsent
          ? "Review the boundary, then complete setup."
          : "You can revisit every choice in Settings."
      )
      .font(QaptrType.caption())
      .foregroundStyle(Color.qaptrInkSoft)
      .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: QaptrSpace.md)

      Button(stage == .privacyConsent ? "Finish" : "Continue", action: advance)
        .buttonStyle(.qaptrPrimary)
        .disabled(
          stage == .privacyConsent
            && (model.loadError != nil || !model.isOnboardingCompletionEligible)
        )
    }
  }

  private func mapMarker(for candidate: OnboardingStage) -> Color {
    if candidate == stage { return .qaptrAccent }
    if candidate.rawValue < stage.rawValue { return .qaptrInkSoft }
    return .qaptrPaperMist
  }

  private func mapAccessibilityValue(for candidate: OnboardingStage) -> String {
    if candidate == stage { return "current step" }
    if candidate.rawValue < stage.rawValue { return "completed" }
    return "available"
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
        actionTitle: model.settings.screenRecordingStatus == .denied
          ? "Open System Settings" : "Allow",
        action: model.requestScreenRecording
      )
      Divider().overlay(Color.qaptrHairline).padding(.vertical, QaptrSpace.md)
      PermissionRow(
        title: "App and window names",
        detail: PermissionRationale.accessibilityContext,
        status: model.settings.accessibilityContextStatus,
        actionTitle: model.settings.accessibilityContextStatus == .denied
          ? "Open System Settings" : "Allow",
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
      Text(
        "\(model.settings.availableDisplayIDs.count) screen\(model.settings.availableDisplayIDs.count == 1 ? "" : "s") available"
      )
      .font(QaptrType.body(13))
      .foregroundStyle(Color.qaptrInkSoft)
      .padding(.top, QaptrSpace.xs)
      if let capturingText = liveCaptureDisplaysText {
        Text(capturingText)
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkSoft.opacity(0.85))
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// A truthful, live line about which screens the background helper is
  /// actually capturing right now, distinct from the system's merely
  /// *available* display count above. Returns `nil` before the helper has
  /// ever reported a status, so this never invents a running-capture claim.
  private var liveCaptureDisplaysText: String? {
    Self.liveCaptureDisplaysText(
      helperIsRunning: model.captureProgress.helperIsRunning,
      selectedDisplayIDs: model.captureProgress.selectedDisplayIDs
    )
  }

  /// Pure decision logic behind `liveCaptureDisplaysText`, directly testable
  /// without a full `ReviewAppModel`.
  nonisolated static func liveCaptureDisplaysText(
    helperIsRunning: Bool, selectedDisplayIDs: [String]
  ) -> String? {
    guard helperIsRunning else { return nil }
    guard !selectedDisplayIDs.isEmpty else {
      return "Capture is running but has not reported a selected screen yet."
    }
    return
      "Currently capturing \(selectedDisplayIDs.count) screen\(selectedDisplayIDs.count == 1 ? "" : "s")."
  }

  private var captureExplanationStage: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.sm) {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("Qaptr takes one screenshot every ")
        Menu {
          ForEach(CaptureIntervalPreset.allCases, id: \.self) { preset in
            Button {
              model.setCaptureIntervalSeconds(preset.seconds)
            } label: {
              HStack {
                Text(preset.displayName)
                if preset.seconds == model.settings.intervalSeconds {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          HStack(spacing: QaptrSpace.xxs) {
            Text(CaptureIntervalPolicy.humanized(model.settings.intervalSeconds))
            Image(systemName: "chevron.down")
              .font(.system(size: 9, weight: .bold))
          }
          .foregroundStyle(Color.qaptrAccentStrong)
          .padding(.horizontal, QaptrSpace.xs)
          .padding(.vertical, QaptrSpace.xxs)
          .background(
            Color.qaptrAccentTint,
            in: RoundedRectangle(cornerRadius: QaptrRadius.input, style: .continuous)
          )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        Text(". We'll let you change the frequency.")
      }
      .font(QaptrType.title())
      .foregroundStyle(Color.qaptrInk)
      .fixedSize(horizontal: false, vertical: true)
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
        Text("Setup could not finish: \(model.loadError ?? "unknown setup error").")
          .font(QaptrType.title(13))
          .foregroundStyle(Color.qaptrError)
          .padding(.top, QaptrSpace.xs)
          .accessibilityLabel(
            "Setup error: \(model.loadError ?? "unknown setup error")")
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
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(ProviderChoice.allCases.enumerated()), id: \.element) { index, provider in
        Button {
          select(provider)
        } label: {
          HStack(spacing: QaptrSpace.sm) {
            Circle()
              .strokeBorder(
                selection == provider ? Color.qaptrAccent : Color.qaptrBorderStrong, lineWidth: 1.5
              )
              .frame(width: 16, height: 16)
              .overlay {
                if selection == provider {
                  Circle().fill(Color.qaptrAccent).frame(width: 8, height: 8)
                }
              }
            Text(provider.displayName)
              .font(QaptrType.body(14))
              .foregroundStyle(Color.qaptrInk)
            Spacer(minLength: QaptrSpace.sm)
            Image(systemName: selection == provider ? "checkmark.circle.fill" : "circle")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(selection == provider ? Color.qaptrAccent : Color.qaptrBorderStrong)
          }
          .padding(.horizontal, QaptrSpace.sm)
          .padding(.vertical, QaptrSpace.sm)
          .background(
            selection == provider ? Color.qaptrAccentTint : Color.clear,
            in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == provider ? .isSelected : [])
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(selection == provider ? "Selected" : "Not selected")
        if index < ProviderChoice.allCases.count - 1 {
          Divider().overlay(Color.qaptrHairline)
        }
      }
    }
    .background(
      Color.qaptrPaperMist.opacity(0.55),
      in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
        .strokeBorder(Color.qaptrHairline, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Provider")
  }
}
