import QaptrReviewCore
import SwiftUI

/// The control surface for the small number of choices that affect Qaptr.
///
/// Redesigned around compact bordered product cards and the mono meta voice.
/// `showsOpenRouterKeyNotice` is a static, directly
/// testable decision function -- its signature is a preserved contract
/// (`SettingsViewOpenRouterReadinessTests`) and must not change shape.
struct SettingsView: View {
    @Bindable var model: ReviewAppModel
    let showObservations: () -> Void
    @State private var newExcludedApplication = ""
    @State private var newExcludedWindowTitle = ""
    @State private var showsProviderSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, QaptrSpace.md)

                captureSection
                sectionDivider
                analysisSection
                sectionDivider
                privacySection
                sectionDivider
                exclusionsSection
            }
            .padding(QaptrSpace.lg)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.qaptrSurface)
        .onAppear { model.refreshSettings() }
        .sheet(isPresented: $showsProviderSetup, onDismiss: model.dismissProviderSetup) {
            ProviderSetupSheet(model: model)
        }
    }

    private var sectionDivider: some View {
        Divider().overlay(Color.qaptrHairline).padding(.vertical, QaptrSpace.xl)
    }

    private var header: some View {
        QaptrCard(padding: QaptrSpace.xl) {
            HStack(alignment: .top, spacing: QaptrSpace.lg) {
                VStack(alignment: .leading, spacing: QaptrSpace.xs) {
                Text("QAPTR")
                    .font(QaptrType.meta())
                    .tracking(1.2)
                    .foregroundStyle(Color.qaptrInkSoft)
                    Text("Settings")
                        .font(QaptrType.display())
                    .foregroundStyle(Color.qaptrInk)
                    Text("Choose what Qaptr can use and what it must leave alone.")
                        .font(QaptrType.body())
                        .foregroundStyle(Color.qaptrInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: QaptrSpace.lg)
                Button("Observations", action: showObservations)
                    .buttonStyle(.qaptrOutline)
            }
        }
    }

    private var captureSection: some View {
        SettingsSection(title: "Capture") {
            VStack(alignment: .leading, spacing: QaptrSpace.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Capture interval")
                        .font(QaptrType.title())
                        .foregroundStyle(Color.qaptrInk)
                    Spacer()
                    Text(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))
                        .font(QaptrType.body(13))
                        .foregroundStyle(Color.qaptrInkSoft)
                }
                Slider(
                    value: captureIntervalBinding,
                    in: Double(CaptureIntervalPolicy.minimumSeconds)...Double(CaptureIntervalPolicy.maximumSeconds),
                    step: Double(CaptureIntervalPolicy.stepSeconds)
                )
                .tint(Color.qaptrAccent)
                .accessibilityLabel("Capture interval")
                .accessibilityValue(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))
                Text("Qaptr uses this time for the next screenshot. No picture is shown here.")
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft.opacity(0.8))
            }
            SettingsFact(label: "Displays", value: "\(model.settings.availableDisplayIDs.count) available")

            VStack(alignment: .leading, spacing: QaptrSpace.md) {
                Text("Keep captures for")
                    .font(QaptrType.title(13))
                    .foregroundStyle(Color.qaptrInk)
                ChoiceRail(
                    values: CacheLifetime.allCases,
                    selection: cacheLifetimeBinding,
                    label: \.displayName
                )
            }
            .padding(.top, QaptrSpace.xs)
        }
    }

    private var analysisSection: some View {
        SettingsSection(title: "Analysis") {
            VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
                Text("Connect a provider")
                    .font(QaptrType.title(13))
                    .foregroundStyle(Color.qaptrInk)
                Text("Qaptr checks a key before it says connected.")
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft)
            }
            ForEach(ProviderChoice.allCases, id: \.self) { provider in
                Button {
                    model.connectProvider(provider)
                    if provider == .openRouter { showsProviderSetup = true }
                } label: {
                    HStack {
                        Text(provider.displayName)
                            .font(QaptrType.body(14.5))
                            .foregroundStyle(Color.qaptrInk)
                        Spacer()
                        if model.settings.provider == provider {
                            Text(model.providerConnection.title)
                                .font(QaptrType.meta(10.5))
                                .foregroundStyle(Color.qaptrAccent)
                        }
                    }
                    .padding(.horizontal, QaptrSpace.sm)
                    .padding(.vertical, QaptrSpace.sm)
                    .background(
                        model.settings.provider == provider ? Color.qaptrAccentTint : Color.clear,
                        in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactile)
                .accessibilityAddTraits(model.settings.provider == provider ? .isSelected : [])
                .accessibilityLabel(provider.displayName)
                .accessibilityValue(
                    model.settings.provider == provider
                        ? model.providerConnection.title
                        : "Not selected"
                )
            }
            if showsOpenRouterKeyNotice {
                OpenRouterKeyReadinessNotice(action: { showsProviderSetup = true })
            }
        }
    }

    /// True only when the selected provider is OpenRouter and Qaptr has
    /// determined, from local settings and Keychain state alone, that no key
    /// has been saved yet. This is a bounded model-only readiness read: it
    /// never triggers a network request and never claims the key or any
    /// model catalog has been validated.
    private var showsOpenRouterKeyNotice: Bool {
        Self.showsOpenRouterKeyNotice(provider: model.settings.provider, connection: model.providerConnection)
    }

    /// Pure decision logic behind `showsOpenRouterKeyNotice`, exposed as an
    /// internal static function so it is directly testable without standing
    /// up a full `ReviewAppModel` or rendering a view.
    static func showsOpenRouterKeyNotice(provider: ProviderChoice?, connection: ProviderConnectionState) -> Bool {
        provider == .openRouter && connection.kind == .needsKey
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            PermissionControlRow(
                title: "Screen Recording",
                detail: "Lets Qaptr take small screenshots now and then.",
                status: model.settings.screenRecordingStatus,
                request: model.requestScreenRecording
            )
            PermissionControlRow(
                title: "Accessibility context",
                detail: "Lets Qaptr read app and window names. You can skip this.",
                status: model.settings.accessibilityContextStatus,
                request: model.requestAccessibilityContext
            )
            QaptrToggle(title: "Start Qaptr at login", isOn: loginItemBinding)
        }
    }

    private var exclusionsSection: some View {
        SettingsSection(title: "Never capture") {
            ExclusionEditor(
                title: "Applications",
                entries: model.settings.excludedApplications,
                newValue: $newExcludedApplication,
                placeholder: "App name",
                add: model.addExcludedApplication,
                remove: model.removeExcludedApplication
            )
            ExclusionEditor(
                title: "Window titles",
                entries: model.settings.excludedWindowTitles,
                newValue: $newExcludedWindowTitle,
                placeholder: "Window name",
                add: model.addExcludedWindowTitle,
                remove: model.removeExcludedWindowTitle
            )
        }
    }

    private var cacheLifetimeBinding: Binding<CacheLifetime> {
        Binding(
            get: { model.settings.cacheLifetime },
            set: { model.setCacheLifetime($0) }
        )
    }

    private var captureIntervalBinding: Binding<Double> {
        Binding(
            get: { Double(model.captureIntervalSeconds) },
            set: { model.setCaptureIntervalSeconds(Int($0.rounded())) }
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
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        QaptrCard {
            VStack(alignment: .leading, spacing: QaptrSpace.lg) {
                Text(title.uppercased())
                    .font(QaptrType.meta(10.5))
                    .tracking(1.0)
                    .foregroundStyle(Color.qaptrInkMuted)
                VStack(alignment: .leading, spacing: QaptrSpace.lg) {
                    content
                }
            }
        }
    }
}

private struct SettingsFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(QaptrType.title())
                .foregroundStyle(Color.qaptrInk)
            Spacer()
            Text(value)
                .font(QaptrType.body(13))
                .foregroundStyle(Color.qaptrInkSoft)
        }
    }
}

/// A tabbed rail of choices marked by an accent underline, matching the
/// website's own segmented-choice pattern rather than a macOS pill control.
private struct ChoiceRail<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: QaptrSpace.xs) {
            ForEach(values, id: \.self) { value in
                Button {
                    guard selection != value else { return }
                    if reduceMotion {
                        selection = value
                    } else {
                        withAnimation(QaptrMotion.easeOut(0.22)) {
                            selection = value
                        }
                    }
                } label: {
                    VStack(spacing: QaptrSpace.xs) {
                        Text(label(value))
                            .font(QaptrType.body(13))
                            .fontWeight(selection == value ? .semibold : .regular)
                            .foregroundStyle(selection == value ? Color.qaptrInk : Color.qaptrInkSoft)
                        Rectangle()
                            .fill(selection == value ? Color.qaptrAccent : .clear)
                            .frame(height: 1.5)
                    }
                    .padding(.horizontal, QaptrSpace.sm)
                    .padding(.vertical, QaptrSpace.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactile)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
                .accessibilityLabel(label(value))
                .accessibilityValue(selection == value ? "Selected" : "Not selected")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
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
                    .foregroundStyle(status == .granted ? Color.qaptrInkSoft : Color.qaptrInkSoft.opacity(0.65))
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
