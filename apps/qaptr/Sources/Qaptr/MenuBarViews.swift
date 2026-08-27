import AppKit
import SwiftUI

struct NativeMenuBarMenu: View {
  @Bindable var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button(action: {}) {
      Label(menuState.title, systemImage: menuState.systemImage)
    }
    .disabled(true)

    Button(menuState.subtitle, action: {})
      .disabled(true)

    Divider()

    ForEach(menuState.primaryActions) { item in
      Button(item.title) {
        perform(item.action)
      }
    }

    Divider()

    Button("Open Qaptr") {
      model.show(menuState.openScreen)
      openMainWindow()
    }

    Button("Settings…") {
      model.show(.settings)
      openMainWindow()
    }
    .keyboardShortcut(",")

    Divider()

    Button("Quit Qaptr") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }

  private var menuState: MenuState {
    switch model.selectedScreen {
    case .menuBarAttention:
      MenuState(
        title: "Screen Recording was turned off",
        subtitle: "Capture is paused until it’s back",
        systemImage: "exclamationmark.circle.fill",
        primaryActions: [MenuAction(title: "Open System Settings", action: .openSystemSettings)],
        openScreen: .homeAttention
      )
    case .menuBarDetailed:
      MenuState(
        title: "Watching closely · 18m 42s left",
        subtitle: "7 detailed captures so far",
        systemImage: "scope",
        primaryActions: [MenuAction(title: "Stop & review", action: .stopAndReview)],
        openScreen: .homeWatching
      )
    case .menuBarApproval:
      MenuState(
        title: "Ready for your approval",
        subtitle: "Review exactly what will be sent",
        systemImage: "checkmark.circle.fill",
        primaryActions: [MenuAction(title: "Review in Qaptr", action: .review)],
        openScreen: .consentReview
      )
    default:
      MenuState(
        title: "Capturing quietly · 18 today",
        subtitle: "Last capture 2 minutes ago",
        systemImage: "record.circle.fill",
        primaryActions: [
          MenuAction(title: "Analyze now", action: .analyze),
          MenuAction(title: "Pause capture", action: .pause),
        ],
        openScreen: .homeFindings
      )
    }
  }

  private func perform(_ action: MenuAction.Kind) {
    switch action {
    case .analyze:
      model.show(.homeReady)
      openMainWindow()
    case .pause:
      model.capturePaused = true
      model.show(.homePaused)
    case .openSystemSettings:
      guard
        let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
      else { return }
      NSWorkspace.shared.open(url)
    case .stopAndReview:
      model.show(.homeWatchingDone)
      openMainWindow()
    case .review:
      model.show(.consentReview)
      openMainWindow()
    }
  }

  private func openMainWindow() {
    openWindow(id: "main")
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}

struct ToastSpecView: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      toastExample(
        "Nothing was sent.",
        note:
          "After Decline on the consent sheet · bottom-center of the window · dismisses after 3s"
      )
      toastExample(
        "Analysis cancelled. Nothing was sent.",
        note: "After Cancel while analyzing · bottom-center of the window · dismisses after 3s"
      )
      toastExample(
        "Correction saved.",
        note: "After submitting a correction · bottom-center of the window · dismisses after 3s"
      )
    }
    .padding(28)
    .frame(width: 560, height: 360, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: [Color.white.opacity(0.94), QaptrColor.accent.opacity(0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func toastExample(_ text: String, note: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
      Text(note)
        .font(.system(size: 11))
        .foregroundStyle(QaptrColor.muted)
    }
  }
}

private struct MenuState {
  let title: String
  let subtitle: String
  let systemImage: String
  let primaryActions: [MenuAction]
  let openScreen: AppScreen
}

private struct MenuAction: Identifiable {
  enum Kind {
    case analyze
    case pause
    case openSystemSettings
    case stopAndReview
    case review
  }

  let title: String
  let action: Kind
  var id: String { title }
}
