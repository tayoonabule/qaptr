import SwiftUI

/// A small sheet to connect (or disconnect) OpenRouter with a pasted key.
///
/// Every string is model-driven: the connection state comes only from
/// `ProviderConnectionState`, never a guessed or optimistic label. Checking
/// a key never happens until the person explicitly presses Connect.
struct ProviderSetupSheet: View {
  @Bindable var model: ReviewAppModel
  @State private var key = ""
  @FocusState private var keyFocused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      VStack(alignment: .leading, spacing: QaptrSpace.lg) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
            Text("Provider")
              .font(QaptrType.meta(10.5))
              .foregroundStyle(Color.qaptrInkMuted)
            Text("Connect OpenRouter")
              .font(QaptrType.headline(18))
              .foregroundStyle(Color.qaptrInk)
            Text("Use your own key for workflow analysis.")
              .font(QaptrType.caption())
              .foregroundStyle(Color.qaptrInkSoft)
          }
          Spacer()
          Button("Disconnect") { model.disconnectProvider() }
            .buttonStyle(.qaptrQuiet)
        }

        Text(
          "Your key stays in your Mac Keychain. Checking it sends no screenshots, notes, or capture content."
        )
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkSoft)

        SecureField("OpenRouter key", text: $key)
          .textFieldStyle(.qaptr)
          .focusEffectDisabled()
          .focused($keyFocused)
          .disabled(model.providerConnection == .checking)
          .accessibilityLabel("OpenRouter key")

        if case .failed(let failure) = model.providerConnection.kind {
          Text(failure.message)
            .font(QaptrType.caption())
            .foregroundStyle(Color.qaptrError)
            .padding(QaptrSpace.sm)
            .background(
              Color.qaptrError.opacity(0.08),
              in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
            )
            .accessibilityLabel("Connection failed: \(failure.message)")
        }

        if model.providerConnection == .configured {
          Text(model.providerConnection.detail)
            .font(QaptrType.caption())
            .foregroundStyle(Color.qaptrInkSoft)
            .accessibilityLabel("Connection status: \(model.providerConnection.detail)")
        }

        HStack {
          if model.providerConnection == .checking {
            ProgressView("Checking")
              .controlSize(.small)
              .tint(Color.qaptrAccent)
          } else if model.providerConnection == .connected {
            HStack(spacing: QaptrSpace.xs) {
              Circle().fill(Color.qaptrAccent).frame(width: 6, height: 6)
              Text("OpenRouter is connected")
                .font(QaptrType.title(13))
                .foregroundStyle(Color.qaptrInk)
            }
          }
          Spacer()
          Button(model.providerConnection == .connected ? "Connected" : "Verify connection") {
            model.startOpenRouterConnectionCheck(key)
          }
          .buttonStyle(.qaptrPrimary)
          .disabled(
            key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || model.providerConnection == .checking)
        }

        Divider().overlay(Color.qaptrHairline)

        HStack {
          Spacer()
          Button("Done") { dismiss() }
            .buttonStyle(.qaptrOutline)
        }
      }
    }
    .padding(28)
    .background { FigmaGlassSurface(radius: QaptrRadius.feature) }
    .frame(width: 460)
  }
}
