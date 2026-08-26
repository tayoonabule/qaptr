import QaptrReviewCore
import SwiftUI

/// First-run setup is intentionally a short permission handoff, not a product
/// tour. The required Screen Recording permission is first, optional context
/// follows, and the final action starts capture through the existing model
/// lifecycle boundary.
struct OnboardingView: View {
  @Bindable var model: ReviewAppModel
  @State private var stage: OnboardingStage = .screenRecording
  @State private var completionMessage: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    QaptrGlassBackdrop {
      QaptrGlassPanel(padding: QaptrSpace.xl) {
        VStack(alignment: .leading, spacing: 0) {
          header
            .padding(.bottom, QaptrSpace.xl)

          progress
            .padding(.bottom, QaptrSpace.xl)

          if reduceMotion {
            stageContent
          } else {
            stageContent
              .id(stage)
              .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
          }

          Spacer(minLength: QaptrSpace.lg)

          footer
        }
      }
      .frame(maxWidth: 760, maxHeight: 680)
      .padding(QaptrSpace.xl)
    }
    .onAppear {
      model.refreshSettings()
      model.refreshPermissions()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.refreshSettings()
        model.refreshPermissions()
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

  private var header: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.sm) {
      HStack(alignment: .center, spacing: QaptrSpace.sm) {
        QaptrBrandLogo(iconSize: 24, textSize: 20)
        Spacer()
        Text("FIRST RUN")
          .font(QaptrType.meta(10))
          .tracking(0.9)
          .foregroundStyle(Color.qaptrInkMuted)
      }

      Text(OnboardingCopy.welcomeTitle)
        .font(QaptrType.display(34))
        .foregroundStyle(Color.qaptrInk)
        .fixedSize(horizontal: false, vertical: true)

      Text(OnboardingCopy.welcomeStatement)
        .font(QaptrType.body(14))
        .foregroundStyle(Color.qaptrInkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  private var progress: some View {
    HStack(spacing: QaptrSpace.xs) {
      ForEach(OnboardingStage.allCases, id: \.self) { candidate in
        Capsule()
          .fill(candidate.rawValue <= stage.rawValue ? Color.qaptrAccent : Color.qaptrHairline)
          .frame(height: candidate == stage ? 4 : 2)
          .animation(reduceMotion ? nil : QaptrMotion.easeOut(0.18), value: stage)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Setup step \(stage.rawValue + 1) of \(OnboardingStage.allCases.count)")
  }

  @ViewBuilder
  private var stageContent: some View {
    switch stage {
    case .screenRecording:
      permissionStep(
        title: "Allow Screen Recording",
        statement: OnboardingCopy.screenRecordingStep,
        rationale: PermissionRationale.screenRecording,
        status: model.settings.screenRecordingStatus,
        action: model.requestScreenRecording,
        actionLabel: model.settings.screenRecordingStatus == .denied
          ? "Open System Settings" : "Allow Screen Recording"
      )
    case .accessibilityContext:
      accessibilityStep
    }
  }

  private func permissionStep(
    title: String,
    statement: String,
    rationale: String,
    status: PermissionStatus,
    action: @escaping () -> Void,
    actionLabel: String
  ) -> some View {
    VStack(alignment: .leading, spacing: QaptrSpace.md) {
      Text("STEP \(stage.rawValue + 1) / \(OnboardingStage.allCases.count)")
        .font(QaptrType.meta(10.5))
        .tracking(0.9)
        .foregroundStyle(Color.qaptrAccentStrong)

      Text(title)
        .font(QaptrType.headline(24))
        .foregroundStyle(Color.qaptrInk)

      Text(statement)
        .font(QaptrType.body(14))
        .foregroundStyle(Color.qaptrInkSoft)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: QaptrSpace.sm) {
        HStack(spacing: QaptrSpace.sm) {
          Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(status == .granted ? Color.qaptrSuccess : Color.qaptrWarning)
          Text(status.label)
            .font(QaptrType.title(13))
            .foregroundStyle(Color.qaptrInk)
        }
        Text(rationale)
          .font(QaptrType.caption(12.5))
          .foregroundStyle(Color.qaptrInkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(QaptrSpace.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
          .strokeBorder(Color.white.opacity(0.58), lineWidth: 1)
      }
      .accessibilityElement(children: .combine)

      if status == .unavailable {
        recoveryMessage(OnboardingCopy.unavailablePermissionRecovery)
      }

      if status == .granted {
        Text(OnboardingCopy.captureBeginsAfterPermission)
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkSoft)
      }

      HStack(spacing: QaptrSpace.md) {
        if status == .granted {
          Button("Continue") {
            move(to: .accessibilityContext)
          }
          .buttonStyle(.qaptrPrimary)
          .keyboardShortcut(.defaultAction)
        } else {
          Button(actionLabel, action: action)
            .buttonStyle(.qaptrPrimary)
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var accessibilityStep: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      Text("STEP 2 / 2")
        .font(QaptrType.meta(10.5))
        .tracking(0.9)
        .foregroundStyle(Color.qaptrAccentStrong)

      Text("Add optional context")
        .font(QaptrType.headline(24))
        .foregroundStyle(Color.qaptrInk)

      Text(OnboardingCopy.accessibilityStep)
        .font(QaptrType.body(14))
        .foregroundStyle(Color.qaptrInkSoft)
        .fixedSize(horizontal: false, vertical: true)

      permissionStatusRow(
        title: "App and window names",
        status: model.settings.accessibilityContextStatus
      )

      if model.settings.availableDisplayIDs.isEmpty {
        recoveryMessage("Connect at least one display before capture can begin.")
      } else if let completionMessage {
        recoveryMessage(completionMessage)
      }

      HStack(spacing: QaptrSpace.md) {
        Button("Allow optional context") {
          model.requestAccessibilityContext()
        }
        .buttonStyle(.qaptrOutline)
        .disabled(model.settings.accessibilityContextStatus == .granted)

        Button("Start capture") {
          finishOnboarding()
        }
        .buttonStyle(.qaptrPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(!canFinish)
      }

      Button("Start without optional context") {
        finishOnboarding()
      }
      .buttonStyle(.qaptrQuiet)
      .keyboardShortcut(.cancelAction)
      .disabled(!canFinish)
    }
    .accessibilityElement(children: .contain)
  }

  private func permissionStatusRow(title: String, status: PermissionStatus) -> some View {
    HStack(spacing: QaptrSpace.sm) {
      Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle.dashed")
        .foregroundStyle(status == .granted ? Color.qaptrSuccess : Color.qaptrWarning)
      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        Text(title)
          .font(QaptrType.title(13))
          .foregroundStyle(Color.qaptrInk)
        Text(status.label)
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkSoft)
      }
      Spacer()
    }
    .padding(QaptrSpace.lg)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
        .strokeBorder(Color.white.opacity(0.58), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  private var footer: some View {
    HStack(alignment: .center, spacing: QaptrSpace.md) {
      Image(systemName: "lock.shield")
        .foregroundStyle(Color.qaptrAccentStrong)
      Text("You can change privacy and capture choices later in Settings.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkSoft)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .accessibilityElement(children: .combine)
  }

  private var canFinish: Bool {
    model.settings.screenRecordingStatus == .granted
      && !model.settings.availableDisplayIDs.isEmpty
  }

  private func finishOnboarding() {
    guard canFinish else {
      completionMessage =
        "Screen Recording must be granted and at least one display must be available before capture can begin."
      return
    }
    guard model.completeOnboarding() else {
      completionMessage =
        "Qaptr could not finish setup yet. Check the live permission and helper status, then try again."
      return
    }
  }

  private func move(to next: OnboardingStage) {
    if reduceMotion {
      stage = next
    } else {
      withAnimation(QaptrMotion.easeOut(0.18)) {
        stage = next
      }
    }
  }

  private func recoveryMessage(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle")
      .font(QaptrType.caption())
      .foregroundStyle(Color.qaptrError)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(text)
  }

  /// Pure decision logic retained for the onboarding live-display test seam.
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
}
