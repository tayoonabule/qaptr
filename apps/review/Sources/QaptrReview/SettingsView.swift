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
                    Text(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))
                        .font(QaptrType.headline(20))
                        .foregroundStyle(Color.qaptrAccentStrong)
                }
                CadenceGrid(
                    selection: model.captureIntervalSeconds,
                    select: model.setCaptureIntervalSeconds
                )
                .accessibilityLabel("Capture rhythm")
                Text("Choose a pace from every 5 seconds to every 30 minutes. Nothing is shown in this screen.")
                    .font(QaptrType.caption())
                    .foregroundStyle(Color.qaptrInkSoft.opacity(0.8))
            }

            HStack(spacing: QaptrSpace.sm) {
                SettingsMetric(value: "\(model.settings.availableDisplayIDs.count)", label: "Displays ready")
                SettingsMetric(value: CaptureIntervalPolicy.humanized(model.captureIntervalSeconds), label: "Current rhythm")
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
                    Text(model.settings.cacheLifetime.displayName)
                        .font(QaptrType.body(13))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.qaptrInkSoft)
                }
                RetentionGrid(selection: cacheLifetimeBinding)
            }
            .padding(.top, QaptrSpace.sm)
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
        .background(Color.qaptrPaperMist, in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous))
    }
}

/// A small set of deliberate choices is easier to scan than a long continuous control.
/// Each tile also shows a tiny rhythm mark, so the control communicates the
/// difference between a quick capture pace and a long working block.
private struct CadenceGrid: View {
    let selection: Int
    let select: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: QaptrSpace.sm), GridItem(.flexible(), spacing: QaptrSpace.sm), GridItem(.flexible(), spacing: QaptrSpace.sm)], spacing: QaptrSpace.sm) {
            ForEach(CaptureIntervalPreset.allCases, id: \.self) { preset in
                let isSelected = selection == preset.seconds
                Button {
                    guard !isSelected else { return }
                    if reduceMotion {
                        select(preset.seconds)
                    } else {
                        withAnimation(QaptrMotion.easeOut(0.18)) {
                            select(preset.seconds)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: QaptrSpace.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(preset.displayName)
                                .font(QaptrType.title(14))
                                .fontWeight(isSelected ? .semibold : .medium)
                            Spacer(minLength: QaptrSpace.xs)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { index in
                                Capsule()
                                    .fill(index < cadenceBars(for: preset) ? (isSelected ? Color.qaptrAccent : Color.qaptrInkMuted) : Color.qaptrHairline)
                                    .frame(height: 4)
                            }
                        }
                        Text(preset.detail)
                            .font(QaptrType.caption(10.5))
                            .foregroundStyle(isSelected ? Color.qaptrAccentStrong : Color.qaptrInkSoft)
                    }
                    .foregroundStyle(isSelected ? Color.qaptrAccentStrong : Color.qaptrInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(QaptrSpace.md)
                    .background(isSelected ? Color.qaptrAccentTint : Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
                            .strokeBorder(isSelected ? Color.qaptrAccent : Color.qaptrHairline, lineWidth: isSelected ? 1.5 : 1)
                    }
                }
                .buttonStyle(.tactile)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel("Capture every \(CaptureIntervalPolicy.humanized(preset.seconds))")
                .accessibilityValue(isSelected ? "Selected, \(preset.detail)" : preset.detail)
            }
        }
    }

    private func cadenceBars(for preset: CaptureIntervalPreset) -> Int {
        switch preset {
        case .fiveSeconds, .fifteenSeconds: 5
        case .thirtySeconds, .oneMinute: 4
        case .twoMinutes, .fiveMinutes: 3
        case .tenMinutes, .fifteenMinutes: 2
        case .thirtyMinutes: 1
        }
    }
}

private struct RetentionGrid: View {
    @Binding var selection: CacheLifetime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: QaptrSpace.sm), GridItem(.flexible(), spacing: QaptrSpace.sm), GridItem(.flexible(), spacing: QaptrSpace.sm)], spacing: QaptrSpace.sm) {
            ForEach(CacheLifetime.allCases, id: \.self) { lifetime in
                let isSelected = selection == lifetime
                Button {
                    guard !isSelected else { return }
                    if reduceMotion {
                        selection = lifetime
                    } else {
                        withAnimation(QaptrMotion.easeOut(0.18)) {
                            selection = lifetime
                        }
                    }
                } label: {
                    HStack(spacing: QaptrSpace.sm) {
                        Circle()
                            .fill(isSelected ? Color.qaptrAccent : Color.qaptrHairline)
                            .frame(width: 9, height: 9)
                        Text(lifetime.displayName)
                            .font(QaptrType.title(13))
                            .fontWeight(isSelected ? .semibold : .regular)
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(isSelected ? Color.qaptrAccentStrong : Color.qaptrInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, QaptrSpace.md)
                    .padding(.vertical, QaptrSpace.md)
                    .background(isSelected ? Color.qaptrAccentTint : Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
                            .strokeBorder(isSelected ? Color.qaptrAccent : Color.qaptrHairline, lineWidth: isSelected ? 1.5 : 1)
                    }
                }
                .buttonStyle(.tactile)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel("Keep captures for \(lifetime.displayName)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
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
