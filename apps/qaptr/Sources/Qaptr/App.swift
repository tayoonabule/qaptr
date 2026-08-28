import AppKit
import SwiftUI

@main
struct QaptrApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    Window("Qaptr", id: "main") {
      RootView(model: model)
        .frame(width: AppModel.windowSize.width, height: AppModel.windowSize.height)
        .offset(y: -32)
        .frame(
          width: AppModel.windowSize.width,
          height: AppModel.windowSize.height - 32,
          alignment: .top
        )
        .background(WindowConfigurator())
        .containerBackground(.clear, for: .window)
    }
    .defaultSize(width: AppModel.windowSize.width, height: AppModel.windowSize.height - 32)
    .windowStyle(.hiddenTitleBar)
    .windowToolbarStyle(.unified(showsTitle: false))
    .defaultLaunchBehavior(.suppressed)
    .commands {
      CommandMenu("Preview") {
        ForEach(AppScreen.allCases) { screen in
          Button(screen.title) { model.show(screen) }
        }
      }
    }

    MenuBarExtra {
      NativeMenuBarMenu(model: model)
    } label: {
      Image(systemName: model.menuBarSymbolName)
        .accessibilityLabel("Qaptr")
    }
    .menuBarExtraStyle(.menu)
  }
}

private struct WindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { configure(view.window) }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { configure(nsView.window) }
  }

  private func configure(_ window: NSWindow?) {
    guard let window else { return }
    let size = AppModel.windowSize
    window.title = "Qaptr"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none
    window.toolbarStyle = .unified
    window.styleMask.insert(.fullSizeContentView)
    window.isOpaque = true
    window.backgroundColor = .white
    window.minSize = size
    window.maxSize = size
    if window.frame.size != size {
      window.setFrame(
        NSRect(origin: window.frame.origin, size: size),
        display: true
      )
    }
  }
}
