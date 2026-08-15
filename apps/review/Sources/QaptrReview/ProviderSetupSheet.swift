import SwiftUI

struct ProviderSetupSheet: View {
    @Bindable var model: ReviewAppModel
    @State private var key = ""
    @FocusState private var keyFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect OpenRouter")
                        .font(.system(size: 20, weight: .bold))
                    Text("Paste your key to check the connection.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") { model.disconnectProvider() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("Your key stays in your Mac Keychain. This check sends no screenshots or notes.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SecureField("OpenRouter key", text: $key)
                .textFieldStyle(.roundedBorder)
                .focused($keyFocused)
                .disabled(model.providerConnection == .checking)

            if case .failed(let failure) = model.providerConnection.kind {
                Text(failure.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                if model.providerConnection == .checking {
                    ProgressView("Checking")
                        .controlSize(.small)
                } else if model.providerConnection == .connected {
                    Label("OpenRouter is connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(model.providerConnection == .connected ? "Connected" : "Connect") {
                    model.startOpenRouterConnectionCheck(key)
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.providerConnection == .checking)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { keyFocused = true }
    }
}
