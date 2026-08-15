import QaptrReviewCore
import SwiftUI

/// The intentionally small settings surface (R-D6): cadence/profile status,
/// displays, cache duration, provider, and privacy/permission status, plus
/// application/window exclusions. Nothing else appears here.
struct SettingsView: View {
    @Bindable var model: ReviewAppModel
    @State private var newExcludedApplication = ""
    @State private var newExcludedWindowTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))

                section("Capture") {
                    LabeledContent("Cadence") {
                        Text(model.settings.cadence.isDetailed ? "Detailed" : "Sparse")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Displays") {
                        Text("\(model.settings.availableDisplayIDs.count) available")
                            .foregroundStyle(.secondary)
                    }
                }

                section("Cache duration") {
                    Picker("Cache duration", selection: cacheLifetimeBinding) {
                        ForEach(CacheLifetime.allCases, id: \.self) { lifetime in
                            Text(lifetime.displayName).tag(lifetime)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                section("Provider") {
                    Picker("Provider", selection: providerBinding) {
                        Text("Not selected").tag(ProviderChoice?.none)
                        ForEach(ProviderChoice.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(ProviderChoice?.some(provider))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                section("Privacy and permissions") {
                    permissionRow(
                        title: "Screen Recording",
                        status: model.settings.screenRecordingStatus,
                        request: model.requestScreenRecording
                    )
                    permissionRow(
                        title: "Accessibility context (optional)",
                        status: model.settings.accessibilityContextStatus,
                        request: model.requestAccessibilityContext
                    )
                    Toggle("Start Qaptr at login", isOn: loginItemBinding)
                }

                section("Excluded applications") {
                    exclusionEditor(
                        entries: model.settings.excludedApplications,
                        newValue: $newExcludedApplication,
                        placeholder: "Application name",
                        add: model.addExcludedApplication,
                        remove: model.removeExcludedApplication
                    )
                }

                section("Excluded window titles") {
                    exclusionEditor(
                        entries: model.settings.excludedWindowTitles,
                        newValue: $newExcludedWindowTitle,
                        placeholder: "Window title",
                        add: model.addExcludedWindowTitle,
                        remove: model.removeExcludedWindowTitle
                    )
                }
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.qaptrSurface)
        .onAppear { model.refreshSettings() }
    }

    private var cacheLifetimeBinding: Binding<CacheLifetime> {
        Binding(
            get: { model.settings.cacheLifetime },
            set: { model.setCacheLifetime($0) }
        )
    }

    private var providerBinding: Binding<ProviderChoice?> {
        Binding(
            get: { model.settings.provider },
            set: { newValue in
                if let newValue {
                    model.setProvider(newValue)
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

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, status: PermissionStatus, request: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(status.label)
                .foregroundStyle(.secondary)
            if status != .granted {
                Button("Request", action: request)
                    .buttonStyle(.tactile)
                    .foregroundStyle(.primary)
                    .underline()
            }
        }
    }

    @ViewBuilder
    private func exclusionEditor(
        entries: [String],
        newValue: Binding<String>,
        placeholder: String,
        add: @escaping (String) -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries, id: \.self) { entry in
                HStack {
                    Text(entry)
                    Spacer()
                    Button("Remove") { remove(entry) }
                        .buttonStyle(.tactile)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField(placeholder, text: newValue)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    add(newValue.wrappedValue)
                    newValue.wrappedValue = ""
                }
                .buttonStyle(.tactile)
                .foregroundStyle(.primary)
                .underline()
            }
        }
    }
}
