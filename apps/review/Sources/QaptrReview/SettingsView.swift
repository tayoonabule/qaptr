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
      return Self(title: "Capture paused", detail: "No new ticks will start until you resume.", action: .resume, actionLabel: "Resume")
    }
    switch progress.state {
    case .permissionRequired:
      return Self(title: "Screen Recording required", detail: progress.failureReason ?? "Grant Screen Recording permission to continue.", action: .openPrivacy, actionLabel: "Review privacy")
    case .noDisplays:
      return Self(title: "No display available", detail: progress.failureReason ?? "Connect a display before Qaptr can capture.", action: nil, actionLabel: nil)
    case .error, .stopped, .unknown:
      return Self(title: "Capture needs attention", detail: progress.actionableReason ?? "The background helper is not running.", action: .restart, actionLabel: "Try again")
    case .paused where helperProcessExists:
      return Self(title: "Capture resuming", detail: "The helper is applying your request.", action: .pause, actionLabel: "Pause")
    case .starting where helperProcessExists:
      return Self(title: "Capture starting", detail: "The helper is preparing the first capture tick.", action: .pause, actionLabel: "Pause")
    case .waiting where helperIsRunning, .capturing where helperIsRunning:
      return Self(title: "Capture running", detail: "The helper owns capture timing in the background.", action: .pause, actionLabel: "Pause")
    case .starting, .waiting, .capturing, .paused:
      return Self(title: "Capture needs attention", detail: "The background helper is not responding.", action: .restart, actionLabel: "Try again")
    }
  }
}

/// Qaptr v2 settings. Configuration is grouped around the three things a
/// person can set: capture, privacy, and the provider used at approval time.
struct SettingsView: View {
  @Bindable var model: ReviewAppModel
  @State private var showsProviderSetup = false
  @State private var showsNeverCapture = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: QaptrSpace.lg) {
        settingsHeader
        captureSection
        privacySection
        analysisSection
      }
      .frame(maxWidth: 620, alignment: .leading)
      .padding(.horizontal, QaptrSpace.xxl)
      .padding(.vertical, QaptrSpace.xl)
      .frame(maxWidth: .infinity)
    }
    .background(Color.clear)
    .onAppear { model.refreshSettings() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshSettings() }
    }
    .sheet(isPresented: $showsProviderSetup) {
      ProviderSetupSheet(model: model)
    }
    .sheet(isPresented: $showsNeverCapture) {
      NeverCaptureSheet(model: model)
    }
    .accessibilityElement(children: .contain)
  }

  private var settingsHeader: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.xs) {
      Text("Settings")
        .font(QaptrType.editorial(34))
        .foregroundStyle(Color.qaptrInk)
      Text("Set the quiet defaults. Qaptr keeps capture local and asks before every analysis.")
        .font(QaptrType.body(14))
        .foregroundStyle(Color.qaptrInkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var captureSection: some View {
    settingsCard("Capture", systemImage: "record.circle") {
      Toggle(isOn: captureEnabledBinding) {
        settingLabel("Capture", "Mirrors pause and resume in the menu bar")
      }
      .toggleStyle(.switch)

      Divider().overlay(Color.qaptrHairline)

      Picker("Cadence", selection: captureIntervalBinding) {
        ForEach(CaptureIntervalPreset.allCases, id: \.self) { preset in
          Text("Every \(preset.displayName)").tag(preset.seconds)
        }
      }
      .accessibilityValue(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))

      Picker("Keep captures", selection: cacheLifetimeBinding) {
        ForEach(CacheLifetime.allCases, id: \.self) { lifetime in
          Text(lifetime.displayName).tag(lifetime)
        }
      }

      if let restartError = model.captureRestartError {
        Label(restartError, systemImage: "exclamationmark.triangle")
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrError)
      }

      Text("Screenshots stay on this Mac until you approve an analysis.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var privacySection: some View {
    settingsCard("Privacy", systemImage: "lock.shield") {
      permissionRow("Screen Recording", status: model.settings.screenRecordingStatus, action: model.requestScreenRecording)
      permissionRow("App and window names", status: model.settings.accessibilityContextStatus, action: model.requestAccessibilityContext)

      Divider().overlay(Color.qaptrHairline)

      Button { showsNeverCapture = true } label: {
        HStack(spacing: QaptrSpace.md) {
          Image(systemName: "eye.slash")
            .foregroundStyle(Color.qaptrAccent)
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 3) {
            Text("Never capture")
              .font(QaptrType.title(14))
              .foregroundStyle(Color.qaptrInk)
            Text(exclusionSummary)
              .font(QaptrType.caption())
              .foregroundStyle(Color.qaptrInkSoft)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          Text("Edit")
            .font(QaptrType.title(13))
            .foregroundStyle(Color.qaptrAccent)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Text("Rules are applied before a capture is retained or prepared for analysis.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var analysisSection: some View {
    settingsCard("Analysis", systemImage: "sparkles") {
      Button {
        model.connectProvider(model.settings.provider ?? .claudeCLI)
        showsProviderSetup = true
      } label: {
        HStack(spacing: QaptrSpace.md) {
          Image(systemName: "network")
            .foregroundStyle(Color.qaptrAccent)
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 3) {
            Text(model.settings.provider?.displayName ?? "Choose a provider")
              .font(QaptrType.title(14))
              .foregroundStyle(Color.qaptrInk)
            Text(providerDetail)
              .font(QaptrType.caption())
              .foregroundStyle(Color.qaptrInkSoft)
          }
          Spacer()
          Text("Change")
            .font(QaptrType.title(13))
            .foregroundStyle(Color.qaptrAccent)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Text("Choosing a provider sends nothing. Qaptr asks before every analysis.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var captureEnabledBinding: Binding<Bool> {
    Binding(
      get: { model.captureControlIntent == .running },
      set: { $0 ? model.resumeCapture() : model.pauseCapture() }
    )
  }

  private var captureIntervalBinding: Binding<Int> {
    Binding(get: { model.captureIntervalSeconds }, set: { model.setCaptureIntervalSeconds($0) })
  }

  private var cacheLifetimeBinding: Binding<CacheLifetime> {
    Binding(get: { model.settings.cacheLifetime }, set: { model.setCacheLifetime($0) })
  }

  private var exclusionSummary: String {
    let count = model.settings.excludedApplications.count + model.settings.excludedWindowTitles.count
    return count == 0
      ? "Nothing excluded. Add an app or window title to keep it out of every capture."
      : "\(count) rule\(count == 1 ? "" : "s") active"
  }

  private var providerDetail: String {
    guard let provider = model.settings.provider else { return "No provider selected" }
    let presentation = model.providerRowPresentation(for: provider)
    return presentation.reason ?? presentation.statusLabel
  }

  /// Compatibility predicates retained for the provider-state tests and for
  /// callers that need to decide whether to show a key recovery affordance.
  static func showsOpenRouterChangeKeyAction(
    provider: ProviderChoice?, connection: ProviderConnectionState
  ) -> Bool {
    guard provider == .openRouter else { return false }
    switch connection.kind {
    case .configured, .connected, .checking, .failed: return true
    case .notConnected, .needsKey: return false
    }
  }

  static func showsOpenRouterKeyNotice(
    provider: ProviderChoice?, connection: ProviderConnectionState
  ) -> Bool {
    provider == .openRouter && connection.kind == .needsKey
  }

  @ViewBuilder
  private func settingsCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: QaptrSpace.md) {
      Label(title, systemImage: systemImage)
        .font(QaptrType.title(14))
        .foregroundStyle(Color.qaptrInkMuted)
      content()
    }
    .padding(QaptrSpace.xl)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.8), lineWidth: 1) }
    .shadow(color: Color.black.opacity(0.06), radius: 18, y: 9)
  }

  private func settingLabel(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(QaptrType.title(14)).foregroundStyle(Color.qaptrInk)
      Text(detail).font(QaptrType.caption()).foregroundStyle(Color.qaptrInkSoft)
    }
  }

  @ViewBuilder
  private func permissionRow(_ title: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
    HStack(spacing: QaptrSpace.md) {
      Image(systemName: status == .granted ? "checkmark.shield" : "shield")
        .foregroundStyle(status == .granted ? Color.qaptrSuccess : Color.qaptrWarning)
        .frame(width: 22)
      Text(title).font(QaptrType.body(14)).foregroundStyle(Color.qaptrInk)
      Spacer()
      Text(status.label)
        .font(QaptrType.caption(12))
        .foregroundStyle(status == .granted ? Color.qaptrSuccess : Color.qaptrWarning)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background((status == .granted ? Color.qaptrSuccess : Color.qaptrWarning).opacity(0.12), in: Capsule())
      if status != .granted {
        Button(status == .denied ? "Open" : "Allow", action: action)
          .buttonStyle(.qaptrQuiet)
      }
    }
  }
}

struct NeverCaptureSheet: View {
  @Bindable var model: ReviewAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var entry = ""
  @State private var entryKind: EntryKind = .app

  private enum EntryKind: String, CaseIterable {
    case app = "App"
    case windowTitle = "Window title"
  }

  private var rows: [(String, String)] {
    model.settings.excludedApplications.map { ("App", $0) } +
      model.settings.excludedWindowTitles.map { ("Window title", $0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      VStack(alignment: .leading, spacing: QaptrSpace.xs) {
        Text("Never capture")
          .font(QaptrType.headline(22)).foregroundStyle(Color.qaptrInk)
        Text("Keep sensitive apps and windows out of every capture.")
          .font(QaptrType.body()).foregroundStyle(Color.qaptrInkSoft)
      }

      HStack(spacing: QaptrSpace.sm) {
        Picker("Rule type", selection: $entryKind) {
          ForEach(EntryKind.allCases, id: \.self) { kind in
            Text(kind.rawValue).tag(kind)
          }
        }
        .labelsHidden()
        TextField("App or window title…", text: $entry)
          .textFieldStyle(.qaptr)
          .onSubmit(add)
        Button("Add", action: add)
          .buttonStyle(.qaptrPrimary)
          .disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      if rows.isEmpty {
        Text("Nothing excluded. Add an app or a window title to keep it out of every capture.")
          .font(QaptrType.caption()).foregroundStyle(Color.qaptrInkMuted)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack {
              Text(row.0).font(QaptrType.caption()).foregroundStyle(Color.qaptrInkMuted).frame(width: 90, alignment: .leading)
              Text(row.1).font(QaptrType.body()).foregroundStyle(Color.qaptrInk)
              Spacer()
              Button("Remove") { remove(row.0, row.1) }.buttonStyle(.qaptrQuiet)
            }
            .padding(.vertical, QaptrSpace.sm)
            Divider().overlay(Color.qaptrHairline)
          }
        }
      }

      HStack {
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(.qaptrPrimary)
      }
    }
    .padding(QaptrSpace.xxl)
    .frame(width: 520)
    .background(.regularMaterial)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Never capture settings")
  }

  private func add() {
    let normalized = entry.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    if entryKind == .app {
      model.addExcludedApplication(normalized)
    } else {
      model.addExcludedWindowTitle(normalized)
    }
    entry = ""
  }

  private func remove(_ type: String, _ value: String) {
    if type == "App" { model.removeExcludedApplication(value) }
    else { model.removeExcludedWindowTitle(value) }
  }
}
