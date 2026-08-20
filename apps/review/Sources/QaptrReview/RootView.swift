import QaptrReviewCore
import Observation
import SwiftUI

// Hallmark · studied-DNA: Micro live-site · persistent rail + ledger work plane

enum ReviewSurface: Equatable {
  case review
  case settings
}

@MainActor
@Observable
final class ReviewNavigation {
  var surface: ReviewSurface = .review
}

/// The post-onboarding product shell. Navigation is persistent and quiet: the
/// left rail stays put while Review and Settings share one warm work plane.
struct ContentView: View {
  @Bindable var model: ReviewAppModel
  @Bindable var navigation: ReviewNavigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 0) {
      rail
        .frame(width: 208)
        .overlay(alignment: .trailing) {
          Rectangle()
            .fill(Color.qaptrHairline)
            .frame(width: 1)
            .ignoresSafeArea(.container, edges: .top)
        }
      ZStack {
        if navigation.surface == .settings {
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
    .task {
      while !Task.isCancelled {
        model.refreshCaptureProgress()
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
      }
    }
  }

  private var rail: some View {
    ZStack(alignment: .topLeading) {
      // The rail owns the titlebar-facing background so the surface remains
      // continuous when the window uses full-size content.
      Color.qaptrPaperMist.opacity(0.42)
        .ignoresSafeArea(.container, edges: .top)

      VStack(alignment: .leading, spacing: QaptrSpace.xxl) {
        VStack(alignment: .leading, spacing: QaptrSpace.xs) {
          HStack(spacing: QaptrSpace.xs) {
            QaptrBrandLogo(iconSize: 20, textSize: 17)
          }
          Text("REVIEW / MAC")
            .font(QaptrType.meta(9.5))
            .tracking(0.8)
            .foregroundStyle(Color.qaptrInkMuted)
        }

        VStack(alignment: .leading, spacing: QaptrSpace.xxs) {
          railButton("Review", systemImage: "list.bullet.rectangle", selected: navigation.surface == .review) {
            setSurface(.review)
          }
          railButton("Settings", systemImage: "slider.horizontal.3", selected: navigation.surface == .settings) {
            setSurface(.settings)
          }
        }

        Spacer()

        VStack(alignment: .leading, spacing: QaptrSpace.xs) {
          CaptureSignalBar(status: captureStatus)
          Text(captureStatus.label)
            .font(QaptrType.meta(9))
            .tracking(0.7)
            .foregroundStyle(captureStatus.isActive ? Color.qaptrTeal : Color.qaptrInkMuted)
        }
      }
      .padding(.horizontal, QaptrSpace.lg)
      .padding(.vertical, QaptrSpace.xl)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
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
        .contentShape(RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous))
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var captureStatus: CaptureStatusPresentation {
    CaptureStatusPresentation.present(
      intent: model.captureControlIntent,
      helperIsRunning: model.captureHelperIsRunning
    )
  }

  private func setSurface(_ surface: ReviewSurface) {
    if reduceMotion {
      navigation.surface = surface
    } else {
      withAnimation(QaptrMotion.easeOut(0.22)) {
        navigation.surface = surface
      }
    }
  }
}

enum CaptureStatusPresentation: Equatable {
  case live
  case paused
  case needsAttention

  static func present(
    intent: CaptureControlIntent,
    helperIsRunning: Bool
  ) -> CaptureStatusPresentation {
    if intent == .paused { return .paused }
    return helperIsRunning ? .live : .needsAttention
  }

  var label: String {
    switch self {
    case .live: "CAPTURE LIVE"
    case .paused: "CAPTURE PAUSED"
    case .needsAttention: "CAPTURE NEEDS ATTENTION"
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .live: "Capture live"
    case .paused: "Capture paused"
    case .needsAttention: "Capture needs attention"
    }
  }

  var isActive: Bool { self == .live }
}

struct CaptureSignalBar: View {
  let status: CaptureStatusPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isActive: Bool { status.isActive }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
      let cycle =
        context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6
      let breathing = isActive && !reduceMotion ? 1 + (sin(cycle * .pi * 2) * 0.07) : 1
      let shimmer = isActive && !reduceMotion ? cycle : 0

      Capsule()
        .fill(Color.qaptrSignalGradient)
        .frame(height: 4)
        .scaleEffect(y: breathing, anchor: .center)
        .opacity(isActive ? 1 : 0.5)
        .overlay {
          GeometryReader { proxy in
            Capsule()
              .fill(
                LinearGradient(
                  colors: [.clear, Color.white.opacity(isActive ? 0.65 : 0), .clear],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: proxy.size.width * 0.38)
              .offset(x: ((shimmer * 1.65) - 0.38) * proxy.size.width)
          }
          .clipShape(Capsule())
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
    .frame(height: 8)
    .accessibilityLabel(status.accessibilityLabel)
  }
}

/// The root view: onboarding until completed, then the main content.
struct RootView: View {
  @Bindable var model: ReviewAppModel
  @Bindable var navigation: ReviewNavigation

  var body: some View {
    Group {
      if model.onboardingCompleted {
        ContentView(model: model, navigation: navigation)
      } else {
        OnboardingView(model: model)
      }
    }
    .frame(minWidth: 960, minHeight: 640)
  }
}
