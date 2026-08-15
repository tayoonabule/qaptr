import QaptrReviewCore
import SwiftUI

// Hallmark · studied-DNA: Micro live-site · persistent rail + ledger work plane

/// The post-onboarding product shell. Navigation is persistent and quiet: the
/// left rail stays put while Review and Settings share one warm work plane.
struct ContentView: View {
  @Bindable var model: ReviewAppModel
  @State private var showsSettings = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 0) {
      rail
        .frame(width: 208)
      Rectangle()
        .fill(Color.qaptrHairline)
        .frame(width: 1)
      ZStack {
        if showsSettings {
          SettingsView(model: model)
            .transition(.opacity)
        } else {
          ObservationSheetView(model: model)
            .transition(.opacity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color.qaptrSurface)
  }

  private var rail: some View {
    VStack(alignment: .leading, spacing: QaptrSpace.xxl) {
      VStack(alignment: .leading, spacing: QaptrSpace.xs) {
        HStack(spacing: QaptrSpace.xs) {
          Circle()
            .fill(Color.qaptrAccent)
            .frame(width: 7, height: 7)
          Text("QAPTR")
            .font(QaptrType.meta(12))
            .tracking(1.2)
            .foregroundStyle(Color.qaptrInk)
        }
        Text("REVIEW / MAC")
          .font(QaptrType.meta(9.5))
          .tracking(0.8)
          .foregroundStyle(Color.qaptrInkMuted)
      }

      VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
        railButton("Review", systemImage: "list.bullet.rectangle", selected: !showsSettings) {
          setSurface(false)
        }
        railButton("Settings", systemImage: "slider.horizontal.3", selected: showsSettings) {
          setSurface(true)
        }
      }

      Spacer()

      VStack(alignment: .leading, spacing: QaptrSpace.xs) {
        Capsule()
          .fill(Color.qaptrSignalGradient)
          .frame(height: 4)
        Text(model.captureProgress.helperIsRunning ? "CAPTURE LIVE" : "CAPTURE PAUSED")
          .font(QaptrType.meta(9))
          .tracking(0.7)
          .foregroundStyle(
            model.captureProgress.helperIsRunning ? Color.qaptrTeal : Color.qaptrInkMuted)
      }
    }
    .padding(.horizontal, QaptrSpace.lg)
    .padding(.vertical, QaptrSpace.xl)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(Color.qaptrPaperMist.opacity(0.42))
  }

  private func railButton(
    _ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(QaptrType.body(12.5))
        .foregroundStyle(selected ? Color.qaptrInk : Color.qaptrInkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, QaptrSpace.sm)
        .padding(.vertical, QaptrSpace.sm)
        .background(
          selected ? Color.qaptrAccentTint : Color.clear,
          in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
        )
        .overlay(alignment: .leading) {
          if selected {
            Capsule()
              .fill(Color.qaptrAccent)
              .frame(width: 3)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func setSurface(_ settings: Bool) {
    if reduceMotion {
      showsSettings = settings
    } else {
      withAnimation(QaptrMotion.easeOut(0.22)) {
        showsSettings = settings
      }
    }
  }
}

/// The root view: onboarding until completed, then the main content.
struct RootView: View {
  @Bindable var model: ReviewAppModel

  var body: some View {
    Group {
      if model.onboardingCompleted {
        ContentView(model: model)
      } else {
        OnboardingView(model: model)
      }
    }
    .frame(minWidth: 960, minHeight: 640)
  }
}
