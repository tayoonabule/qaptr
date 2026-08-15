import QaptrReviewCore
import SwiftUI

// Hallmark: Control Plane layout. A persistent category rail keeps one deliberate editor in focus.

/// The control surface for the small number of choices that affect Qaptr.
///
/// Redesigned around compact bordered product cards and the mono meta voice.
/// `showsOpenRouterKeyNotice` is a static, directly
/// testable decision function -- its signature is a preserved contract
/// (`SettingsViewOpenRouterReadinessTests`) and must not change shape.
struct SettingsView: View {
  @Bindable var model: ReviewAppModel
  let showObservations: () -> Void
  @State private var newExcludedWindowTitle = ""
  @State private var showsProviderSetup = false
  @State private var showsApplicationPicker = false
  @State private var installedApplications: [InstalledApplication] = []
  @State private var selectedCategory: SettingsCategory = .capture

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: QaptrSpace.lg) {
        header

        HStack(alignment: .top, spacing: QaptrSpace.xl) {
          categoryRail
            .frame(width: 176, alignment: .leading)

          focusedEditor
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(QaptrSpace.xl)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(Color.qaptrSurface)
    .onAppear { model.refreshSettings() }
    .task {
      if installedApplications.isEmpty {
        installedApplications = ApplicationCatalog.load()
      }
    }
    .sheet(isPresented: $showsProviderSetup, onDismiss: model.dismissProviderSetup) {
      ProviderSetupSheet(model: model)
    }
    .sheet(isPresented: $showsApplicationPicker) {
      ApplicationPickerSheet(
        applications: installedApplications,
        selectedNames: Set(model.settings.excludedApplications),
        choose: model.addExcludedApplication
      )
    }
  }

  private enum SettingsCategory: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case analysis = "Analysis"
    case privacy = "Privacy"
    case neverCapture = "Never Capture"

    var id: Self { self }

    var detail: String {
      switch self {
      case .capture: "Rhythm and local history"
      case .analysis: "Provider and readiness"
      case .privacy: "Permissions and launch"
      case .neverCapture: "Apps and window titles"
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: QaptrSpace.lg) {
      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        Text("QAPTR / CONTROL PLANE")
          .font(QaptrType.meta())
          .tracking(1.2)
          .foregroundStyle(Color.qaptrInkMuted)
        Text("Settings")
          .font(QaptrType.display())
          .foregroundStyle(Color.qaptrInk)
        Text("Adjust one system at a time. Changes apply to Qaptr immediately.")
          .font(QaptrType.body())
          .foregroundStyle(Color.qaptrInkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: QaptrSpace.lg)
      Button("Observations", action: showObservations)
        .buttonStyle(.qaptrOutline)
    }
    .padding(.bottom, QaptrSpace.md)
  }

  private var categoryRail: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.xs) {
      Text("INDEX")
        .font(QaptrType.meta(10.5))
        .tracking(1)
        .foregroundStyle(Color.qaptrInkMuted)
        .padding(.bottom, QaptrSpace.xs)

      ForEach(SettingsCategory.allCases) { category in
        Button {
          selectedCategory = category
        } label: {
          VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
            Text(category.rawValue.uppercased())
              .font(QaptrType.meta(10.5))
              .tracking(0.85)
            Text(category.detail)
              .font(QaptrType.caption(10.5))
              .fixedSize(horizontal: false, vertical: true)
          }
          .foregroundStyle(selectedCategory == category ? Color.qaptrInk : Color.qaptrInkSoft)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, QaptrSpace.sm)
          .padding(.vertical, QaptrSpace.xs)
          .background(
            selectedCategory == category ? Color.qaptrAccentTint : Color.clear,
            in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
          )
          .overlay(alignment: .leading) {
            if selectedCategory == category {
              Capsule()
                .fill(Color.qaptrAccent)
                .frame(width: 3)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
        .accessibilityLabel(category.rawValue)
        .accessibilityValue(selectedCategory == category ? "Selected" : "Not selected")
      }
    }
    .padding(.trailing, QaptrSpace.xl)
    .overlay(alignment: .trailing) {
      Rectangle().fill(Color.qaptrHairline).frame(width: 1)
    }
  }

  @ViewBuilder
  private var focusedEditor: some View {
    switch selectedCategory {
    case .capture:
      captureSection
    case .analysis:
      analysisSection
    case .privacy:
      privacySection
    case .neverCapture:
      exclusionsSection
    }
  }

  private var captureSection: some View {
    SettingsSection(
      title: "Capture", detail: "Choose Qaptr's local capture rhythm and expiry window."
    ) {
      VStack(alignment: .leading, spacing: QaptrSpace.md) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
            Text("Capture rhythm")
              .font(QaptrType.title())
              .foregroundStyle(Color.qaptrInk)
            Text("How often Qaptr takes a screenshot")
              .font(QaptrType.caption())
              .foregroundStyle(Color.qaptrInkSoft)
          }
          Spacer()
          Picker("Capture rhythm", selection: captureIntervalBinding) {
            ForEach(CaptureIntervalPreset.allCases, id: \.self) { preset in
              Text("\(preset.displayName) · \(preset.detail)")
                .tag(preset.seconds)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
        Text(
          "Choose a pace from every 5 seconds to every 30 minutes. Nothing is shown in this screen."
        )
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkSoft.opacity(0.8))
      }

      HStack(spacing: QaptrSpace.sm) {
        SettingsMetric(
          value: "\(model.settings.availableDisplayIDs.count)", label: "Displays ready")
        SettingsMetric(
          value: CaptureIntervalPolicy.humanized(model.captureIntervalSeconds),
          label: "Current rhythm")
      }

      VStack(alignment: .leading, spacing: QaptrSpace.md) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
            Text("Keep captures for")
              .font(QaptrType.title())
              .foregroundStyle(Color.qaptrInk)
            Text("Local history expires after this window")
              .font(QaptrType.caption())
              .foregroundStyle(Color.qaptrInkSoft)
          }
          Spacer()
          Picker("Keep captures for", selection: cacheLifetimeBinding) {
            ForEach(CacheLifetime.allCases, id: \.self) { lifetime in
              Text(lifetime.displayName)
                .tag(lifetime)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }
    }
  }

  private var analysisSection: some View {
    SettingsSection(
      title: "Analysis", detail: "Choose an analysis provider, or leave Qaptr in capture-only mode."
    ) {
      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        Text("Connect a provider")
          .font(QaptrType.title(13))
          .foregroundStyle(Color.qaptrInk)
        Text("Qaptr checks a key before it says connected.")
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkSoft)
      }
      VStack(spacing: 0) {
        ForEach(Array(ProviderChoice.allCases.enumerated()), id: \.element) { index, provider in
          providerRow(provider)
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
      if showsOpenRouterKeyNotice {
        OpenRouterKeyReadinessNotice(action: { showsProviderSetup = true })
      }
    }
  }

  private func providerRow(_ provider: ProviderChoice) -> some View {
    let selected = model.settings.provider == provider
    return Button {
      // `connectProvider` only requests the setup sheet itself when
      // OpenRouter is selected and still needs a key.
      model.connectProvider(provider)
      if model.providerSetupRequest == .openRouter { showsProviderSetup = true }
    } label: {
      HStack(spacing: QaptrSpace.md) {
        VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
          Text(provider.displayName)
            .font(QaptrType.body(14.5))
            .foregroundStyle(Color.qaptrInk)
          Text(provider == .openRouter ? "API key" : "Command-line connection")
            .font(QaptrType.caption(11))
            .foregroundStyle(Color.qaptrInkMuted)
        }
        Spacer(minLength: QaptrSpace.sm)
        if selected {
          Text(model.providerConnection.title.uppercased())
            .font(QaptrType.meta(9.5))
            .tracking(0.55)
            .foregroundStyle(
              model.providerConnection == .connected ? Color.qaptrSuccess : Color.qaptrAccentStrong
            )
            .padding(.horizontal, QaptrSpace.sm)
            .padding(.vertical, QaptrSpace.xs)
            .background(Color.qaptrSurface, in: Capsule())
        }
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(selected ? Color.qaptrAccent : Color.qaptrBorderStrong)
      }
      .padding(.horizontal, QaptrSpace.md)
      .padding(.vertical, QaptrSpace.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(selected ? Color.qaptrAccentTint : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityLabel(provider.displayName)
    .accessibilityValue(selected ? model.providerConnection.title : "Not selected")
    .overlay(alignment: .leading) {
      if selected {
        Rectangle()
          .fill(Color.qaptrAccent)
          .frame(width: 3)
      }
    }
    .contextMenu {
      if provider == .openRouter && selected && showsOpenRouterChangeKeyAction {
        Button("Change key") {
          model.openProviderSetup()
          showsProviderSetup = true
        }
      }
    }
  }

  /// True only for OpenRouter once a key exists (saved or verified), so
  /// there is always an explicit, accessible way to open the setup sheet
  /// again without that action being implied by merely re-selecting the
  /// already-selected provider.
  private var showsOpenRouterChangeKeyAction: Bool {
    Self.showsOpenRouterChangeKeyAction(
      provider: model.settings.provider, connection: model.providerConnection)
  }

  /// Pure decision logic behind `showsOpenRouterChangeKeyAction`, directly
  /// testable without a full `ReviewAppModel`.
  static func showsOpenRouterChangeKeyAction(
    provider: ProviderChoice?, connection: ProviderConnectionState
  ) -> Bool {
    guard provider == .openRouter else { return false }
    switch connection.kind {
    case .configured, .connected, .checking, .failed:
      return true
    case .notConnected, .needsKey:
      return false
    }
  }

  /// True only when the selected provider is OpenRouter and Qaptr has
  /// determined, from local settings and Keychain state alone, that no key
  /// has been saved yet. This is a bounded model-only readiness read: it
  /// never triggers a network request and never claims the key or any
  /// model catalog has been validated.
  private var showsOpenRouterKeyNotice: Bool {
    Self.showsOpenRouterKeyNotice(
      provider: model.settings.provider, connection: model.providerConnection)
  }

  /// Pure decision logic behind `showsOpenRouterKeyNotice`, exposed as an
  /// internal static function so it is directly testable without standing
  /// up a full `ReviewAppModel` or rendering a view.
  static func showsOpenRouterKeyNotice(
    provider: ProviderChoice?, connection: ProviderConnectionState
  ) -> Bool {
    provider == .openRouter && connection.kind == .needsKey
  }

  private var privacySection: some View {
    SettingsSection(
      title: "Privacy", detail: "Review the permissions Qaptr uses and how it starts."
    ) {
      PermissionControlRow(
        title: "Screen Recording", detail: "Lets Qaptr take small screenshots now and then.",
        status: model.settings.screenRecordingStatus, request: model.requestScreenRecording)
      PermissionControlRow(
        title: "Accessibility context",
        detail: "Lets Qaptr read app and window names. You can skip this.",
        status: model.settings.accessibilityContextStatus,
        request: model.requestAccessibilityContext)
      QaptrToggle(title: "Start Qaptr at login", isOn: loginItemBinding)
    }
  }

  private var exclusionsSection: some View {
    SettingsSection(
      title: "Never Capture", detail: "Create hard boundaries for applications and window titles."
    ) {
      ApplicationExclusionEditor(
        entries: model.settings.excludedApplications, add: model.addExcludedApplication,
        remove: model.removeExcludedApplication, choose: { showsApplicationPicker = true })
      ExclusionEditor(
        title: "Window titles", entries: model.settings.excludedWindowTitles,
        newValue: $newExcludedWindowTitle, placeholder: "Window name",
        add: model.addExcludedWindowTitle, remove: model.removeExcludedWindowTitle)
    }
  }

  private var cacheLifetimeBinding: Binding<CacheLifetime> {
    Binding(
      get: { model.settings.cacheLifetime },
      set: { model.setCacheLifetime($0) }
    )
  }

  private var captureIntervalBinding: Binding<Int> {
    Binding(
      get: { model.captureIntervalSeconds },
      set: { model.setCaptureIntervalSeconds($0) }
    )
  }

  private var loginItemBinding: Binding<Bool> {
    Binding(
      get: { model.settings.loginItemEnabled },
      set: { model.setLoginItemEnabled($0) }
    )
  }
}

/// A bordered settings card with a compact eyebrow and direct controls.
private struct SettingsSection<Content: View>: View {
  let title: String
  let detail: String
  @ViewBuilder let content: Content

  init(title: String, detail: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.detail = detail
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        Text(title.uppercased())
          .font(QaptrType.meta(10.5))
          .tracking(1.0)
          .foregroundStyle(Color.qaptrAccentStrong)
        Text(title)
          .font(QaptrType.display(28))
          .foregroundStyle(Color.qaptrInk)
        Text(detail)
          .font(QaptrType.body(13))
          .foregroundStyle(Color.qaptrInkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(alignment: .leading, spacing: QaptrSpace.lg) {
        content
      }
    }
    .padding(QaptrSpace.xxl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: QaptrRadius.card, style: .continuous)
        .strokeBorder(Color.qaptrHairline, lineWidth: 1)
    }
  }
}

private struct SettingsMetric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
      Text(value)
        .font(QaptrType.headline(18))
        .foregroundStyle(Color.qaptrInk)
      Text(label.uppercased())
        .font(QaptrType.meta(9.5))
        .tracking(0.7)
        .foregroundStyle(Color.qaptrInkMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(QaptrSpace.md)
    .background(
      Color.qaptrPaperMist,
      in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous))
  }
}

/// A single, concise status/recovery row shown only when OpenRouter is the
/// selected provider and no key has been saved. It reads solely from
/// `ProviderConnectionState`, derived from Keychain presence, never from a
/// network call.
private struct OpenRouterKeyReadinessNotice: View {
  let action: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: QaptrSpace.md) {
      Text("OpenRouter needs a key before Qaptr can use it.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkSoft)
      Spacer(minLength: QaptrSpace.md)
      Button("Add key", action: action)
        .buttonStyle(.qaptrOutline)
    }
    .padding(.top, QaptrSpace.xs)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("OpenRouter needs a key before Qaptr can use it.")
  }
}

private struct PermissionControlRow: View {
  let title: String
  let detail: String
  let status: PermissionStatus
  let request: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: QaptrSpace.lg) {
      VStack(alignment: .leading, spacing: QaptrSpace.xxs + 1) {
        Text(title)
          .font(QaptrType.title())
          .foregroundStyle(Color.qaptrInk)
        Text(detail)
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkSoft)
      }
      Spacer(minLength: QaptrSpace.md)
      VStack(alignment: .trailing, spacing: QaptrSpace.xs) {
        Text(status.label)
          .font(QaptrType.caption())
          .foregroundStyle(
            status == .granted ? Color.qaptrInkSoft : Color.qaptrInkSoft.opacity(0.65))
        if status != .granted {
          Button("Request", action: request)
            .buttonStyle(.qaptrOutline)
        }
      }
    }
  }
}

/// A minimal switch drawn from the shared token set, replacing AppKit's
/// stock `Toggle` so its color and motion match every other control.
private struct QaptrToggle: View {
  let title: String
  var detail: String? = nil
  @Binding var isOn: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      if reduceMotion {
        isOn.toggle()
      } else {
        withAnimation(QaptrMotion.easeOut(0.2)) {
          isOn.toggle()
        }
      }
    } label: {
      HStack(alignment: .center, spacing: QaptrSpace.md) {
        Capsule()
          .fill(isOn ? Color.qaptrAccent : Color.qaptrHairline)
          .frame(width: 30, height: 17)
          .overlay(alignment: isOn ? .trailing : .leading) {
            Circle()
              .fill(Color.qaptrSurface)
              .frame(width: 13, height: 13)
              .padding(2)
          }
        VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
          Text(title)
            .font(QaptrType.title())
            .foregroundStyle(Color.qaptrInk)
          if let detail {
            Text(detail)
              .font(QaptrType.caption())
              .foregroundStyle(Color.qaptrInkSoft)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .buttonStyle(.tactile)
    .accessibilityLabel(title)
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

private struct ApplicationExclusionEditor: View {
  let entries: [String]
  let add: (String) -> Void
  let remove: (String) -> Void
  let choose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.md) {
      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        Text("Applications")
          .font(QaptrType.title(13))
          .foregroundStyle(Color.qaptrInk)
        Text("Choose apps from your Mac. Qaptr will never capture them.")
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkSoft)
      }

      if entries.isEmpty {
        Text("No applications excluded")
          .font(QaptrType.caption())
          .foregroundStyle(Color.qaptrInkMuted)
      } else {
        ForEach(entries, id: \.self) { entry in
          HStack(spacing: QaptrSpace.sm) {
            Circle()
              .fill(Color.qaptrWarning)
              .frame(width: 7, height: 7)
            Text(entry)
              .font(QaptrType.body())
              .foregroundStyle(Color.qaptrInk)
            Spacer()
            Button("Remove") { remove(entry) }
              .buttonStyle(.qaptrQuiet)
          }
        }
      }

      Button {
        choose()
      } label: {
        Label("Choose an application", systemImage: "plus")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.qaptrOutline)
    }
  }
}

private struct ApplicationPickerSheet: View {
  let applications: [InstalledApplication]
  let choose: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var selectedNames: Set<String>

  init(
    applications: [InstalledApplication], selectedNames: Set<String>,
    choose: @escaping (String) -> Void
  ) {
    self.applications = applications
    self.choose = choose
    _selectedNames = State(initialValue: selectedNames)
  }

  private var filteredApplications: [InstalledApplication] {
    guard !search.isEmpty else { return applications }
    return applications.filter { $0.name.localizedCaseInsensitiveContains(search) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
          Text("Never capture")
            .font(QaptrType.meta())
            .tracking(1.1)
            .foregroundStyle(Color.qaptrInkMuted)
          Text("Choose an application")
            .font(QaptrType.display(24))
            .foregroundStyle(Color.qaptrInk)
          Text("Select an app from the list. You can change this later.")
            .font(QaptrType.body())
            .foregroundStyle(Color.qaptrInkSoft)
        }
        Spacer()
        Button("Done") { dismiss() }
          .buttonStyle(.qaptrOutline)
      }

      TextField("Search applications", text: $search)
        .textFieldStyle(.qaptr)

      List(filteredApplications) { application in
        Button {
          if !selectedNames.contains(application.name) {
            choose(application.name)
            selectedNames.insert(application.name)
          }
        } label: {
          HStack(spacing: QaptrSpace.md) {
            Image(nsImage: application.icon)
              .resizable()
              .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
              Text(application.name)
                .font(QaptrType.title(13))
                .foregroundStyle(Color.qaptrInk)
              Text(application.url.deletingPathExtension().path)
                .font(QaptrType.meta(9))
                .foregroundStyle(Color.qaptrInkMuted)
                .lineLimit(1)
            }
            Spacer()
            if selectedNames.contains(application.name) {
              Label("Excluded", systemImage: "checkmark")
                .font(QaptrType.caption())
                .foregroundStyle(Color.qaptrAccentStrong)
            }
          }
          .padding(.vertical, QaptrSpace.xs)
        }
        .buttonStyle(.plain)
        .disabled(selectedNames.contains(application.name))
      }
      .listStyle(.inset)
    }
    .padding(QaptrSpace.xxl)
    .frame(width: 560, height: 560)
    .background(Color.qaptrSurface)
  }
}

private struct ExclusionEditor: View {
  let title: String
  let entries: [String]
  @Binding var newValue: String
  let placeholder: String
  let add: (String) -> Void
  let remove: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.md) {
      Text(title)
        .font(QaptrType.title(13))
        .foregroundStyle(Color.qaptrInk)

      ForEach(entries, id: \.self) { entry in
        HStack {
          Text(entry)
            .font(QaptrType.body())
            .foregroundStyle(Color.qaptrInk)
          Spacer()
          Button("Remove") { remove(entry) }
            .buttonStyle(.qaptrQuiet)
        }
        .padding(.vertical, QaptrSpace.xxs)
      }

      HStack(spacing: QaptrSpace.md) {
        TextField(placeholder, text: $newValue)
          .textFieldStyle(.qaptr)
          .accessibilityLabel(title)
          .onSubmit(addEntry)
        Button("Add", action: addEntry)
          .buttonStyle(.qaptrOutline)
          .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private func addEntry() {
    add(newValue)
    newValue = ""
  }
}
