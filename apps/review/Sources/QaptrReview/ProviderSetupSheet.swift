import QaptrReviewCore
import SwiftUI

/// Provider choice is deliberately a local configuration action. Selecting a
/// row may verify a CLI or an OpenRouter key, but it never starts an analysis.
/// Analysis still crosses its network boundary only through Approve.
struct ProviderSetupSheet: View {
  @Bindable var model: ReviewAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var key = ""
  @State private var openRouterExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.lg) {
      VStack(alignment: .leading, spacing: QaptrSpace.xs) {
        Text("How should Qaptr analyze?")
          .font(QaptrType.headline(22))
          .foregroundStyle(Color.qaptrInk)
        Text("Choose a provider. Nothing is sent by choosing one.")
          .font(QaptrType.body())
          .foregroundStyle(Color.qaptrInkSoft)
      }

      VStack(spacing: 0) {
        providerRow(.claudeCLI, detected: true)
        providerRow(.codexCLI, detected: true)
        providerRow(.jcodeCLI, detected: false)
        providerRow(.openRouter, detected: false)
      }
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.75), lineWidth: 1) }

      if openRouterExpanded || model.settings.provider == .openRouter {
        openRouterForm
      }

      Text("Choosing a provider sends nothing. Your key stays in your Mac Keychain.")
        .font(QaptrType.caption())
        .foregroundStyle(Color.qaptrInkMuted)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        if model.analysisWaitingForProvider {
          Text("Preparing local review…")
            .font(QaptrType.caption())
            .foregroundStyle(Color.qaptrInkSoft)
        }
        Spacer()
        Button("Done") { dismiss() }
          .buttonStyle(.qaptrOutline)
      }
    }
    .padding(QaptrSpace.xxl)
    .frame(width: 520)
    .background(.regularMaterial)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Choose an analysis provider")
  }

  @ViewBuilder
  private func providerRow(_ provider: ProviderChoice, detected: Bool) -> some View {
    let selected = model.settings.provider == provider
    let presentation = model.providerRowPresentation(for: provider)
    Button {
      if provider == .openRouter {
        openRouterExpanded = true
        model.connectProvider(provider)
      } else {
        model.connectProvider(provider)
      }
    } label: {
      HStack(spacing: QaptrSpace.md) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Color.qaptrAccent : Color.qaptrInkMuted)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: QaptrSpace.xs) {
            Text(provider.displayName)
              .font(QaptrType.title(14)).foregroundStyle(Color.qaptrInk)
            if detected {
              Text("Detected on this Mac")
                .font(QaptrType.caption(11)).foregroundStyle(Color.qaptrSuccess)
            }
          }
          Text(presentation.reason ?? presentation.statusLabel)
            .font(QaptrType.caption()).foregroundStyle(Color.qaptrInkSoft)
        }
        Spacer()
        if selected && provider != .openRouter {
          Text(presentation.statusLabel)
            .font(QaptrType.caption()).foregroundStyle(Color.qaptrAccent)
        } else {
          Text("Use")
            .font(QaptrType.title(13)).foregroundStyle(Color.qaptrAccent)
        }
      }
      .padding(.horizontal, QaptrSpace.md)
      .padding(.vertical, QaptrSpace.md)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(provider.displayName)
    .accessibilityValue(selected ? "Selected, \(presentation.statusLabel)" : presentation.statusLabel)
  }

  private var openRouterForm: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.sm) {
      SecureField("OpenRouter key", text: $key)
        .textFieldStyle(.qaptr)
        .disabled(model.providerConnection == .checking)
      HStack {
        if model.providerConnection == .checking {
          ProgressView("Checking").controlSize(.small)
        } else if model.providerConnection == .connected {
          Label("Connected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.qaptrSuccess)
        } else if case .failed(let failure) = model.providerConnection.kind {
          Text(failure.message).font(QaptrType.caption()).foregroundStyle(Color.qaptrError)
        }
        Spacer()
        Button(model.providerConnection == .connected ? "Connected" : "Verify") {
          model.startOpenRouterConnectionCheck(key)
        }
        .buttonStyle(.qaptrPrimary)
        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.providerConnection == .checking)
      }
    }
    .padding(QaptrSpace.md)
    .background(Color.qaptrPaperMist.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
