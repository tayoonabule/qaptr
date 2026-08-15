import QaptrReviewCore
import SwiftUI

/// The control surface for the small number of choices that actually affect
/// Qaptr. It deliberately uses selection rails and radio rows instead of
/// AppKit's generic popup controls, so every option stays visible and every
/// state change has a clear, tactile response.
struct SettingsView: View {
    @Bindable var model: ReviewAppModel
    let showObservations: () -> Void
    @State private var newExcludedApplication = ""
    @State private var newExcludedWindowTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                AppHeader(
                    title: "Settings",
                    detail: "Choose what Qaptr can use and what it must leave alone.",
                    actionTitle: "Observations",
                    action: showObservations
                )

                captureSection
                analysisSection
                privacySection
                exclusionsSection
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.qaptrSurface)
        .onAppear { model.refreshSettings() }
    }

    private var captureSection: some View {
        SettingsSection(title: "Capture") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Capture interval")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: captureIntervalBinding,
                    in: Double(CaptureIntervalPolicy.minimumSeconds)...Double(CaptureIntervalPolicy.maximumSeconds),
                    step: Double(CaptureIntervalPolicy.stepSeconds)
                )
                .accessibilityLabel("Capture interval")
                .accessibilityValue(CaptureIntervalPolicy.humanized(model.captureIntervalSeconds))
                Text("Qaptr uses this time for the next screenshot. No picture is shown here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            SettingsFact(label: "Displays", value: "\(model.settings.availableDisplayIDs.count) available")

            VStack(alignment: .leading, spacing: 10) {
                Text("Keep captures for")
                    .font(.system(size: 14, weight: .medium))
                ChoiceRail(
                    values: CacheLifetime.allCases,
                    selection: cacheLifetimeBinding,
                    label: \.displayName
                )
            }
            .padding(.top, 6)
        }
    }

    private var analysisSection: some View {
        SettingsSection(title: "Analysis") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a provider")
                    .font(.system(size: 14, weight: .medium))
                Text("This only saves your choice. Qaptr will not contact it from this page.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            SettingsProviderChoiceList(selection: providerBinding, includesNoSelection: true)
        }
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
            QaptrToggle(
                title: "Start Qaptr at login",
                isOn: loginItemBinding
            )
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

    private var providerBinding: Binding<ProviderChoice?> {
        Binding(
            get: { model.settings.provider },
            set: { newValue in
                if let newValue {
                    model.setProvider(newValue)
                } else {
                    model.clearProvider()
                }
            }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { model.settings.loginItemEnabled },
            set: { model.setLoginItemEnabled($0) }
        )
    }
}

struct AppHeader: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 18)
            ActionButton(title: actionTitle, action: action)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(Color.qaptrRule)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 14) {
                content
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
                .font(.system(size: 15, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChoiceRail<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button {
                    guard selection != value else { return }
                    if reduceMotion {
                        selection = value
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selection = value
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(label(value))
                            .font(.system(size: 13, weight: selection == value ? .semibold : .regular))
                            .foregroundStyle(selection == value ? Color.primary : .secondary)
                        Capsule()
                            .fill(selection == value ? Color.qaptrAccent : .clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactile)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsProviderChoiceList: View {
    @Binding var selection: ProviderChoice?
    let includesNoSelection: Bool

    init(selection: Binding<ProviderChoice?>, includesNoSelection: Bool = false) {
        _selection = selection
        self.includesNoSelection = includesNoSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if includesNoSelection {
                ProviderChoiceRow(
                    title: "Not selected",
                    isSelected: selection == nil,
                    select: { selection = nil }
                )
            }
            ForEach(ProviderChoice.allCases, id: \.self) { provider in
                ProviderChoiceRow(
                    title: provider.displayName,
                    isSelected: selection == provider,
                    select: { selection = provider }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider")
    }
}

private struct ProviderChoiceRow: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.qaptrAccent : Color.primary.opacity(0.24), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.qaptrAccent)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isSelected ? 1 : 0.001)
                        .opacity(isSelected ? 1 : 0)
                }
                .animation(
                    reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.3, dampingFraction: 0.62),
                    value: isSelected
                )
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.qaptrControlFill.opacity(isHovering ? 1 : 0))
            )
        }
        .buttonStyle(.tactile)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct PermissionControlRow: View {
    let title: String
    let detail: String
    let status: PermissionStatus
    let request: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(status.label)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(status == .granted ? .secondary : .tertiary)
                if status != .granted {
                    ActionButton(title: "Request", action: request)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.qaptrAccent : Color.qaptrControlFill)
                    .frame(width: 24, height: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isOn ? Color.qaptrAccent : Color.primary.opacity(0.16), lineWidth: 1)
                    }
                    .overlay {
                        if isOn {
                            Circle()
                                .fill(Color.qaptrSurface)
                                .frame(width: 8, height: 8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))

            ForEach(entries, id: \.self) { entry in
                HStack {
                    Text(entry)
                        .font(.system(size: 14))
                    Spacer()
                    ActionButton(title: "Remove") { remove(entry) }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                TextField(placeholder, text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title)
                    .onSubmit(addEntry)
                ActionButton(title: "Add", action: addEntry)
                    .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addEntry() {
        add(newValue)
        newValue = ""
    }
}

struct ActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovering ? Color.qaptrAccent : Color.secondary)
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isHovering ? Color.qaptrAccent : Color.primary.opacity(0.32))
                        .frame(height: 1)
                }
        }
        .buttonStyle(.tactile)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.qaptrSurface)
                .padding(.horizontal, 17)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovering ? Color.qaptrAccent : Color.primary)
                )
        }
        .buttonStyle(.tactile)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}

struct QuietButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.qaptrControlFill.opacity(isHovering ? 1 : 0.55))
                )
        }
        .buttonStyle(.tactile)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}
