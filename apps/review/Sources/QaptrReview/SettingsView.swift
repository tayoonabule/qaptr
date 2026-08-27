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

private struct FigmaSettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(QaptrType.title(14))
        .foregroundStyle(Color.qaptrFigmaText)
      VStack(alignment: .leading, spacing: 16) {
        content
      }
      .padding(20)
      .frame(width: 741, alignment: .leading)
      .background { FigmaGlassSurface(radius: QaptrRadius.feature) }
    }
  }
}

private struct FigmaSettingsPicker<SelectionValue: Hashable, Content: View>: View {
  let label: String
  @Binding var selection: SelectionValue
  @ViewBuilder let content: Content

  init(label: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
    self.label = label
    self._selection = selection
    self.content = content()
  }

  var body: some View {
    HStack {
      Text(label).font(QaptrType.body(14)).foregroundStyle(Color.qaptrFigmaBody)
      Spacer()
      Picker(label, selection: $selection) { content }
        .labelsHidden()
        .pickerStyle(.menu)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 26)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.08), lineWidth: 1) }
    }
  }
}

private struct FigmaPermissionRow: View {
  let title: String
  let status: PermissionStatus
  let action: () -> Void

  var body: some View {
    HStack {
      Text(title).font(QaptrType.body(14)).foregroundStyle(Color.qaptrFigmaText)
      Spacer()
      if status == .granted {
        Text(status.label)
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrSuccess)
          .padding(.horizontal, 10).padding(.vertical, 3)
          .background(Color.qaptrSuccess.opacity(0.12), in: Capsule())
      } else {
        Button(status.label, action: action)
          .font(QaptrType.caption())
          .foregroundStyle(status == .denied ? Color.qaptrError : Color.qaptrWarning)
          .padding(.horizontal, 10).padding(.vertical, 3)
          .background((status == .denied ? Color.qaptrError : Color.qaptrWarning).opacity(0.12), in: Capsule())
          .buttonStyle(.plain)
      }
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
  @State private var showsExclusions = false
  @State private var excludedApplication = ""
  @State private var excludedWindowTitle = ""
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 12) {
          QaptrBrandLogo(iconSize: 22, textSize: 20, wordmark: true)
            .frame(width: 84, height: 30)
            .clipped()
          Text("Settings")
            .font(QaptrType.body(13))
            .foregroundStyle(Color.qaptrFigmaBody)
        }
        captureFigmaSection
        privacyFigmaSection
        analysisFigmaSection
      }
      .padding(.horizontal, 52)
      .padding(.vertical, 32)
      .frame(width: 845, alignment: .leading)
    }
    .background(ReviewDesign.canvas)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear { model.refreshSettings() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshSettings() }
    }
    .sheet(isPresented: $showsProviderSetup, onDismiss: model.dismissProviderSetup) {
      ProviderSetupSheet(model: model)
    }
    .sheet(isPresented: $showsExclusions) { exclusionsEditor }
    .accessibilityElement(children: .contain)
  }

  private var captureFigmaSection: some View {
    FigmaSettingsSection(title: "Capture") {
      let presentation = CaptureSettingsPresentation.present(
        intent: model.captureControlIntent,
        progress: model.captureProgress,
        helperIsRunning: model.captureHelperIsRunning,
        helperProcessExists: model.captureHelperProcessExists
      )
      HStack {
        HStack(spacing: 8) {
          Circle().fill(model.captureHelperIsRunning ? Color.qaptrSuccess : Color.qaptrWarning)
            .frame(width: 8, height: 8)
          Text(CaptureStatusPresentation.present(intent: model.captureControlIntent, helperIsRunning: model.captureHelperIsRunning).label)
            .font(QaptrType.body(14))
            .foregroundStyle(Color.qaptrFigmaText)
        }
        Spacer()
        if let action = presentation.action, let label = presentation.actionLabel {
          Button(label) { perform(action) }
            .buttonStyle(.qaptrOutline)
        }
      }
      Divider().overlay(Color.qaptrFigmaHairline)
      FigmaSettingsPicker(label: "Capture cadence", selection: captureIntervalBinding) {
        ForEach(CaptureIntervalPreset.allCases, id: \.self) { preset in
          Text("Every \(preset.displayName)").tag(preset.seconds)
        }
      }
      FigmaSettingsPicker(label: "Keep captures", selection: cacheLifetimeBinding) {
        ForEach(CacheLifetime.allCases, id: \.self) { lifetime in
          Text(lifetime.displayName).tag(lifetime)
        }
      }
      Text("Screenshots stay on this Mac until you approve an analysis.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrFigmaMuted)
    }
  }

  private var privacyFigmaSection: some View {
    FigmaSettingsSection(title: "Privacy") {
      FigmaPermissionRow(title: "Screen Recording", status: model.settings.screenRecordingStatus, action: model.requestScreenRecording)
      FigmaPermissionRow(title: "App and window names", status: model.settings.accessibilityContextStatus, action: model.requestAccessibilityContext)
      Divider().overlay(Color.qaptrFigmaHairline)
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Never capture").font(QaptrType.body(14)).foregroundStyle(Color.qaptrFigmaText)
          Text(exclusionSummary).font(QaptrType.caption()).foregroundStyle(Color.qaptrFigmaMuted)
        }
        Spacer()
        Button("Edit") { showsExclusions = true }
          .buttonStyle(.plain)
          .foregroundStyle(Color.qaptrFigmaAction)
      }
    }
  }

  private var analysisFigmaSection: some View {
    FigmaSettingsSection(title: "Analysis") {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(model.settings.provider?.displayName ?? "No provider selected")
            .font(QaptrType.body(14)).foregroundStyle(Color.qaptrFigmaText)
          Text(model.settings.provider == nil ? "Choose a provider when you are ready" : "Ready · asks before every analysis")
            .font(QaptrType.caption()).foregroundStyle(Color.qaptrFigmaMuted)
        }
        Spacer()
        Button("Change") {
          model.openProviderSetup()
          showsProviderSetup = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.qaptrFigmaAction)
      }
    }
  }

  private var exclusionSummary: String {
    let apps = model.settings.excludedApplications
    let windows = model.settings.excludedWindowTitles
    if apps.isEmpty && windows.isEmpty { return "No applications or window titles" }
    let appText = apps.prefix(2).joined(separator: ", ")
    let windowText = windows.isEmpty ? "" : " · \(windows.count) window titles"
    return appText.isEmpty ? "\(windows.count) window titles" : appText + windowText
  }

  private var exclusionsEditor: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Never capture").font(QaptrType.headline(22))
      Text("Captures are skipped while any of these is on screen.")
        .font(QaptrType.body(13)).foregroundStyle(Color.qaptrFigmaBody)
      HStack {
        TextField("App or window title…", text: $excludedApplication)
        Button("Add") { addExcludedApplication() }.buttonStyle(.qaptrOutline)
      }
      ForEach(model.settings.excludedApplications, id: \.self) { entry in exclusionRow(entry) { model.removeExcludedApplication(entry) } }
      ForEach(model.settings.excludedWindowTitles, id: \.self) { entry in exclusionRow(entry) { model.removeExcludedWindowTitle(entry) } }
      HStack { Spacer(); Button("Done") { showsExclusions = false }.buttonStyle(.qaptrPrimary) }
    }
    .padding(28)
    .frame(width: 520)
  }

  private func perform(_ action: CaptureSettingsAction) {
    switch action {
    case .pause: model.pauseCapture()
    case .resume: model.resumeCapture()
    case .restart: model.restartCaptureHelper()
    case .openPrivacy: model.requestScreenRecording()
    }
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
          .buttonStyle(.qaptrOutline)
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
        .buttonStyle(.qaptrPrimary)
      } else {
        Button("Capture more detail now") {
          model.startDetailedCapture()
        }
        .buttonStyle(.qaptrPrimary)
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
      Text("Keep sensitive apps and windows out of Qaptr before anything is retained.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkSoft)
        .fixedSize(horizontal: false, vertical: true)
      TextField("Application name", text: $excludedApplication)
        .textFieldStyle(.qaptr)
        .onSubmit(addExcludedApplication)
      if !model.settings.excludedApplications.isEmpty {
        ForEach(model.settings.excludedApplications, id: \.self) { entry in
          exclusionRow(entry) { model.removeExcludedApplication(entry) }
        }
      }

      TextField("Window title", text: $excludedWindowTitle)
        .textFieldStyle(.qaptr)
        .onSubmit(addExcludedWindowTitle)
      if !model.settings.excludedWindowTitles.isEmpty {
        ForEach(model.settings.excludedWindowTitles, id: \.self) { entry in
          exclusionRow(entry) { model.removeExcludedWindowTitle(entry) }
        }
      }
    } header: {
      Label("Never capture", systemImage: "eye.slash")
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
            .buttonStyle(.qaptrOutline)
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
