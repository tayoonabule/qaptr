import SwiftUI

struct ConsentView: View {
  @Bindable var model: AppModel
  let state: AppModel.Screen

  var body: some View {
    ZStack {
      consentBackdrop
        .opacity(0.35)
      Color.black.opacity(0.06)
      if state == .consentChooseProvider {
        providerSheet
      } else {
        reviewSheet
      }
    }
    .frame(width: 845, height: 737)
    .background(Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var consentBackdrop: some View {
    VStack(spacing: 0) {
      QaptrTitleBar("Qaptr Home")
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          QaptrStatus(text: "Capturing quietly", tone: .success)
          Spacer()
          QaptrButton(title: "Analyze") {}
        }
        VStack(alignment: .leading, spacing: 12) {
          findingCard(
            "Validate a product change before release",
            "Qaptr saw implementation, review feedback, and a build check...")
          findingCard(
            "Compare launch plans and record decisions",
            "A product brief and planning document appeared together...")
        }
      }
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var reviewSheet: some View {
    VStack(alignment: .leading, spacing: 20) {
      sheetHeading(
        "Review before sending",
        "Prepared on your Mac. Nothing has been sent yet."
      )

      VStack(spacing: 0) {
        reviewRow("Sending to", value: "Claude CLI · Claude Sonnet") {
          Button("Change") { model.select(.consentChooseProvider) }
            .buttonStyle(.plain)
            .foregroundStyle(QaptrColor.accent)
        }
        Divider().opacity(0.35)
        reviewRow("What", value: "Redacted text from 16 of 18 captures") { EmptyView() }
        Divider().opacity(0.35)
        reviewRow("Not included", value: "2 captures excluded by your privacy rules · no images") {
          EmptyView()
        }
      }
      .padding(.vertical, 4)

      HStack(spacing: 10) {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: 12))
          .foregroundStyle(QaptrColor.accent)
          .frame(width: 28, height: 28)
          .background(QaptrColor.accent.opacity(0.06), in: Circle())
        Text("Personal details were removed on this Mac. Qaptr asks every time.")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(QaptrColor.accent)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(QaptrColor.accent.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12).strokeBorder(
          QaptrColor.accent.opacity(0.08), lineWidth: 0.5))

      HStack(spacing: 12) {
        Spacer()
        Button("Decline") { model.select(.homeCapturingFindings) }
          .buttonStyle(.plain)
          .font(.system(size: 13))
          .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
          .padding(.horizontal, 16)
          .frame(height: 35)
        QaptrButton(title: "Approve and analyze") { model.select(.homeAnalyzing) }
      }
    }
    .padding(28)
    .frame(width: 520)
    .qaptrGlassSurface(radius: 24)
    .shadow(color: .black.opacity(0.10), radius: 40, y: 16)
    .offset(y: -20)
  }

  private var providerSheet: some View {
    VStack(alignment: .leading, spacing: 20) {
      sheetHeading(
        "How should Qaptr analyze?",
        "Choosing a provider sends nothing. Qaptr asks before every analysis."
      )

      VStack(spacing: 10) {
        providerRow("Claude CLI", detail: "Detected on this Mac")
        providerRow("Codex CLI", detail: "Detected on this Mac")
        VStack(alignment: .leading, spacing: 10) {
          Text("OpenRouter").font(.system(size: 14, weight: .medium))
          HStack(spacing: 8) {
            Text("OpenRouter key")
              .font(.system(size: 13))
              .foregroundStyle(QaptrColor.muted)
              .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
              .padding(.horizontal, 12)
              .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
              .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                  Color.black.opacity(0.08), lineWidth: 0.5))
            QaptrButton(title: "Verify", prominent: false) {}
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 12))
      }

      HStack(spacing: 8) {
        Image(systemName: "key.fill")
        Text("Your key stays in your Mac Keychain.")
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(QaptrColor.accent)
    }
    .padding(28)
    .frame(width: 520)
    .qaptrGlassSurface(radius: 24)
    .shadow(color: .black.opacity(0.10), radius: 40, y: 16)
    .offset(y: -20)
  }

  private func findingCard(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 16, weight: .medium))
      Text(detail).font(.system(size: 13)).foregroundStyle(QaptrColor.muted)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.60), in: RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.03), lineWidth: 0.5))
  }

  private func sheetHeading(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
      Text(subtitle)
        .font(.system(size: 13))
        .foregroundStyle(Color(red: 0.29, green: 0.33, blue: 0.39))
    }
  }

  private func reviewRow<Trailing: View>(
    _ label: String,
    value: String,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .font(.system(size: 13))
        .foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
      Spacer()
      Text(value).font(.system(size: 13, weight: .medium))
      trailing().font(.system(size: 13, weight: .medium))
    }
    .frame(height: 28)
  }

  private func providerRow(_ name: String, detail: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(name).font(.system(size: 14, weight: .medium))
        Text(detail).font(.system(size: 12)).foregroundStyle(QaptrColor.muted)
      }
      Spacer()
      QaptrButton(title: "Use", prominent: false) { model.select(.consentReview) }
    }
    .padding(16)
    .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 12))
  }
}
