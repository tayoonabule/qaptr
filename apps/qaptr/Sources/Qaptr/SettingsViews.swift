import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel
  let state: AppModel.Screen

  var body: some View {
    ZStack {
      settingsPage
        .opacity(state == .settingsNeverCapture ? 0.55 : 1)

      if state == .settingsNeverCapture {
        Color.black.opacity(0.06)
        neverCaptureSheet
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
      }
    }
    .frame(width: 845, height: 737)
    .background(Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var settingsPage: some View {
    VStack(spacing: 0) {
      QTitleBar("Qaptr Settings")

      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 12) {
          QaptrBrand(compact: true)
            .frame(width: 84, alignment: .leading)
          Text("Settings")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(QaptrColor.muted)
        }

        settingsSection("Capture") {
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              QaptrStatus(text: "Capture on", tone: .success)
                .fontWeight(.bold)
              Spacer()
              compactButton("Pause") {}
            }
            Divider().opacity(0.45)
            settingsRow("Capture cadence") { compactPicker("Every 30 seconds  ⌄") }
            settingsRow("Keep captures") { compactPicker("1 day  ⌄") }
            Text("Screenshots stay on this Mac until you approve an analysis.")
              .font(.system(size: 12))
              .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.55))
          }
        }

        settingsSection("Privacy") {
          VStack(alignment: .leading, spacing: 16) {
            settingsRow("Screen Recording", weight: .medium) {
              statusPill("Granted", color: Color(red: 0.10, green: 0.50, blue: 0.30))
            }
            settingsRow("App and window names", weight: .medium) {
              statusPill("Not yet requested", color: Color(red: 1, green: 0.55, blue: 0.16))
            }
            Divider().opacity(0.45)
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("Never capture").font(.system(size: 14, weight: .medium))
                Text("1Password, Keychain Access · 2 window titles")
                  .font(.system(size: 12))
                  .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.55))
              }
              Spacer()
              Button("Edit") { model.select(.settingsNeverCapture) }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(QaptrColor.accent)
            }
          }
        }

        settingsSection("Analysis") {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Claude CLI").font(.system(size: 14, weight: .medium))
              Text("Ready · asks before every analysis")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.55))
            }
            Spacer()
            Button("Change") { model.select(.consentChooseProvider) }
              .buttonStyle(.plain)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(QaptrColor.accent)
          }
        }
      }
      .padding(.horizontal, 52)
      .padding(.vertical, 32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var neverCaptureSheet: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Never capture")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
        Text("Captures are skipped while any of these is on screen.")
          .font(.system(size: 13))
          .foregroundStyle(Color(red: 0.29, green: 0.33, blue: 0.39))
      }

      HStack(spacing: 8) {
        Text("App or window title…")
          .font(.system(size: 13))
          .foregroundStyle(QaptrColor.muted)
          .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
          .padding(.horizontal, 12)
          .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 8))
          .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
              Color.black.opacity(0.08), lineWidth: 0.5))
        QaptrButton(title: "Add", prominent: false) {}
      }

      VStack(spacing: 0) {
        neverCaptureRow("1Password", kind: "App")
        Divider().opacity(0.4)
        neverCaptureRow("Keychain Access", kind: "App")
        Divider().opacity(0.4)
        neverCaptureRow("Private notes", kind: "Window title")
        Divider().opacity(0.4)
        neverCaptureRow("Personal finance", kind: "Window title")
      }
      .padding(.horizontal, 14)
      .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))

      HStack {
        Spacer()
        QaptrButton(title: "Done") { model.select(.settings) }
      }
    }
    .padding(28)
    .frame(width: 520)
    .qaptrGlassSurface(radius: 24)
    .shadow(color: .black.opacity(0.10), radius: 40, y: 16)
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.system(size: 14, weight: .medium))
      content()
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qaptrGlassSurface(radius: 16)
        .shadow(color: .black.opacity(0.06), radius: 32, y: 12)
    }
  }

  private func settingsRow<Trailing: View>(
    _ title: String,
    weight: Font.Weight = .regular,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack {
      Text(title)
        .font(.system(size: 14, weight: weight))
        .foregroundStyle(Color(red: 0.29, green: 0.33, blue: 0.39))
      Spacer()
      trailing()
    }
  }

  private func compactPicker(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13))
      .padding(.horizontal, 12)
      .frame(height: 28)
      .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 7))
      .overlay(
        RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
  }

  private func compactButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(.plain)
      .font(.system(size: 13, weight: .medium))
      .padding(.horizontal, 14)
      .frame(height: 28)
      .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
  }

  private func statusPill(_ title: String, color: Color) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(color.opacity(0.12), in: Capsule())
  }

  private func neverCaptureRow(_ title: String, kind: String) -> some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .medium))
      Spacer()
      Text(kind).font(.system(size: 12)).foregroundStyle(QaptrColor.muted)
      Button("✕") {}
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(QaptrColor.muted)
        .accessibilityLabel("Remove \(title)")
    }
    .frame(height: 42)
  }

}
