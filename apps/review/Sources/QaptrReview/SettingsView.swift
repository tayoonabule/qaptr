import QaptrReviewCore
import SwiftUI

/// The capture status copy is kept separate from the settings layout so the
/// recovery contract remains directly unit-testable.
enum CaptureSettingsAction: Equatable {
  case pause
  case resume
  case restart
  case openPrivacy
}

struct CaptureSettingsPresentation: Equatable {
  let title: String
  let detail: String
  let action: CaptureSettingsAction?
  let actionLabel: String?

  static func present(
    intent: CaptureControlIntent,
    progress: CaptureProgressSnapshot,
    helperIsRunning: Bool,
    helperProcessExists: Bool
  ) -> Self {
    if intent == .paused {
      return Self(
        title: "Capture paused",
        detail: "No new ticks will start until you resume.",
        action: .resume,
        actionLabel: "Resume"
      )
    }

    switch progress.state {
    case .permissionRequired:
      return Self(
        title: "Screen Recording required",
        detail: progress.failureReason ?? "Grant Screen Recording permission to continue.",
        action: .openPrivacy,
        actionLabel: "Review privacy"
      )
    case .noDisplays:
      return Self(
        title: "No display available",
        detail: progress.failureReason ?? "Connect a display before Qaptr can capture.",
        action: nil,
        actionLabel: nil
      )
    case .error, .stopped, .unknown:
      return Self(
        title: "Capture needs attention",
        detail: progress.actionableReason ?? "The background helper is not running.",
        action: .restart,
        actionLabel: "Try again"
      )
    case .paused where helperProcessExists:
      return Self(
        title: "Capture resuming",
        detail: "The helper is applying your request.",
        action: .pause,
        actionLabel: "Pause"
      )
    case .starting where helperProcessExists:
      return Self(
        title: "Capture starting",
        detail: "The helper is preparing the first capture tick.",
        action: .pause,
        actionLabel: "Pause"
      )
    case .waiting where helperIsRunning, .capturing where helperIsRunning:
      return Self(
        title: "Capture running",
        detail: "The helper owns capture timing in the background.",
        action: .pause,
        actionLabel: "Pause"
      )
    case .starting, .waiting, .capturing, .paused:
      return Self(
        title: "Capture needs attention",
        detail: "The background helper is not responding.",
        action: .restart,
        actionLabel: "Try again"
      )
    }
  }
}

/// Compact native settings. Each section has one job: capture cadence and
/// retention, detailed-session controls, provider readiness, privacy/recovery
/// controls, and exclusions.
struct SettingsView: View {
  @Bindable var model: ReviewAppModel
  @AppStorage("com.qaptr.review.settings.detailedSessionDuration")
  private var detailedSessionDurationRaw = DetailedSessionDuration.oneHour.rawValue
  @State private var showsProviderSetup = false
  @State private var excludedApplication = ""
  @State private var excludedWindowTitle = ""
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Form {
      captureSection
      detailedSessionSection
      privacySection
      providerSection
      exclusionsSection
    }
    .formStyle(.grouped)
    .frame(maxWidth: 620)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.clear)
    .navigationTitle("Settings")
    .onAppear { model.refreshSettings() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshSettings() }
    }
    .sheet(isPresented: $showsProviderSetup, onDismiss: model.dismissProviderSetup) {
      ProviderSetupSheet(model: model)
    }
    .accessibilityElement(children: .contain)
  }

  private var captureSection: some View {
    let presentation = CaptureSettingsPresentation.present(
      intent: model.captureControlIntent,
      progress: model.captureProgress,
      helperIsRunning: model.captureHelperIsRunning,
      helperProcessExists: model.captureHelperProcessExists
    )

    return Section {
      LabeledContent {
        if let action = presentation.action, let actionLabel = presentation.actionLabel {
          Button(actionLabel) {
            switch action {
            case .pause: model.pauseCapture()
            case .resume: model.resumeCapture()
            case .restart: model.restartCaptureHelper()
            case .openPrivacy: model.requestScreenRecording()
            }
          }
          .buttonStyle(.bordered)
          .keyboardShortcut(.defaultAction)
        }
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(presentation.title)
            .font(.headline)
          Text(presentation.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let restartError = model.captureRestartError {
        recoveryLine(restartError)
      }

      Picker("Capture cadence", selection: captureIntervalBinding) {
        ForEach(CaptureIntervalPreset.allCases, id: \.self) { preset in
          Text("Every \(preset.displayName)")
            .tag(preset.seconds)
        }
      }
      .accessibilityValue(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))

      Picker("Keep local captures for", selection: cacheLifetimeBinding) {
        ForEach(CacheLifetime.allCases, id: \.self) { lifetime in
          Text(lifetime.displayName).tag(lifetime)
        }
      }

      LabeledContent("Displays available") {
        Text("\(model.settings.availableDisplayIDs.count)")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("Capture")
    } footer: {
      Text(
        "Cadence changes are written to the helper's scalar control file. Screenshots remain local until an explicit analysis consent."
      )
    }
  }

  private var detailedSessionSection: some View {
    Section {
      Picker("Detailed session duration", selection: detailedDurationBinding) {
        ForEach(DetailedSessionDuration.allCases, id: \.self) { duration in
          Text(duration.displayName).tag(duration)
        }
      }
      .accessibilityHint("Controls how long the helper captures more frequently")

      if model.detailedCaptureState.lifecycle == .capturing {
        Button("Stop detailed capture") {
          model.stopDetailedCapture()
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button("Capture more detail now") {
          model.startDetailedCapture()
        }
        .buttonStyle(.borderedProminent)
      }

      if case .helperUnavailable? = model.detailedCaptureState.outcome {
        recoveryLine("QaptrHelper is not available. Start the helper, then try again.")
      }
    } header: {
      Text("Detailed capture")
    } footer: {
      Text(
        "The lightweight helper changes cadence locally. Stop it here or from the menu bar; stopping opens the capture summary."
      )
    }
  }

  private var privacySection: some View {
    Section {
      PermissionControlRow(
        title: "Screen Recording",
        status: model.settings.screenRecordingStatus,
        action: model.requestScreenRecording
      )
      PermissionControlRow(
        title: "App and window names (optional)",
        status: model.settings.accessibilityContextStatus,
        action: model.requestAccessibilityContext
      )

      Toggle("Open Qaptr at login", isOn: loginItemBinding)
        .accessibilityHint("Starts the lightweight capture helper, not an analysis provider")
    } header: {
      Text("Privacy and access")
    } footer: {
      Text(
        "Screen Recording is required for capture. App and window names are optional context. Provider consent is requested separately for each analysis session."
      )
    }
  }

  private var providerSection: some View {
    Section {
      ForEach(ProviderChoice.allCases, id: \.self) { provider in
        let selected = model.settings.provider == provider
        let presentation = model.providerRowPresentation(for: provider)
        Button {
          model.connectProvider(provider)
          if model.providerSetupRequest == .openRouter { showsProviderSetup = true }
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(provider.displayName)
                .foregroundStyle(.primary)
              Text(presentation.reason ?? presentation.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(selected ? Color.accentColor : .secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(
          selected ? "Selected, \(presentation.statusLabel)" : presentation.statusLabel
        )
        .contextMenu {
          if provider == .openRouter && selected && showsOpenRouterChangeKeyAction {
            Button("Change key") {
              model.openProviderSetup()
              showsProviderSetup = true
            }
          }
        }
      }
    } header: {
      Text("Analysis provider")
    } footer: {
      Text(
        "Choosing a provider does not send captures. Qaptr asks for consent before every analysis session."
      )
    }
  }

  private var exclusionsSection: some View {
    Section {
      TextField("Application name", text: $excludedApplication)
        .onSubmit(addExcludedApplication)
      if !model.settings.excludedApplications.isEmpty {
        ForEach(model.settings.excludedApplications, id: \.self) { entry in
          exclusionRow(entry) { model.removeExcludedApplication(entry) }
        }
      }

      TextField("Window title", text: $excludedWindowTitle)
        .onSubmit(addExcludedWindowTitle)
      if !model.settings.excludedWindowTitles.isEmpty {
        ForEach(model.settings.excludedWindowTitles, id: \.self) { entry in
          exclusionRow(entry) { model.removeExcludedWindowTitle(entry) }
        }
      }
    } header: {
      Text("Never capture")
    } footer: {
      Text("Excluded applications and window titles are filtered before capture is retained.")
    }
  }

  private func exclusionRow(_ value: String, remove: @escaping () -> Void) -> some View {
    HStack {
      Text(value)
      Spacer()
      Button("Remove", action: remove)
        .buttonStyle(.borderless)
    }
    .accessibilityElement(children: .combine)
  }

  private func addExcludedApplication() {
    model.addExcludedApplication(excludedApplication)
    excludedApplication = ""
  }

  private func addExcludedWindowTitle() {
    model.addExcludedWindowTitle(excludedWindowTitle)
    excludedWindowTitle = ""
  }

  private var captureIntervalBinding: Binding<Int> {
    Binding(
      get: { model.captureIntervalSeconds },
      set: { model.setCaptureIntervalSeconds($0) }
    )
  }

  private var cacheLifetimeBinding: Binding<CacheLifetime> {
    Binding(
      get: { model.settings.cacheLifetime },
      set: { model.setCacheLifetime($0) }
    )
  }

  private var detailedDurationBinding: Binding<DetailedSessionDuration> {
    Binding(
      get: { DetailedSessionDuration(rawValue: detailedSessionDurationRaw) ?? .oneHour },
      set: { detailedSessionDurationRaw = $0.rawValue }
    )
  }

  private var loginItemBinding: Binding<Bool> {
    Binding(
      get: { model.settings.loginItemEnabled },
      set: { model.setLoginItemEnabled($0) }
    )
  }

  private var showsOpenRouterChangeKeyAction: Bool {
    Self.showsOpenRouterChangeKeyAction(
      provider: model.settings.provider,
      connection: model.providerConnection
    )
  }

  /// True only for OpenRouter after a key has been configured or checked.
  static func showsOpenRouterChangeKeyAction(
    provider: ProviderChoice?, connection: ProviderConnectionState
  ) -> Bool {
    guard provider == .openRouter else { return false }
    switch connection.kind {
    case .configured, .connected, .checking, .failed: return true
    case .notConnected, .needsKey: return false
    }
  }

  /// True only when OpenRouter is selected and the local key is known to be
  /// absent. This never performs a network request.
  static func showsOpenRouterKeyNotice(
    provider: ProviderChoice?, connection: ProviderConnectionState
  ) -> Bool {
    provider == .openRouter && connection.kind == .needsKey
  }

  private func recoveryLine(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle")
      .font(.caption)
      .foregroundStyle(Color.qaptrError)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(text)
  }

  private struct PermissionControlRow: View {
    let title: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
      LabeledContent {
        if status != .granted {
          Button(status == .denied ? "Open System Settings" : "Request", action: action)
            .buttonStyle(.bordered)
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          Text(status.label)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .contain)
    }
  }
}
