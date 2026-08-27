import SwiftUI

struct HomeView: View {
  @Bindable var model: AppModel
  let state: AppScreen

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      toolbar
      content
    }
    .frame(width: 845, height: 737)
    .background(Color.clear)
  }

  private var titleBar: some View {
    HStack(spacing: 8) {
      QaptrBrand(compact: true)
        .scaleEffect(0.58, anchor: .leading)
        .frame(width: 14, height: 14, alignment: .leading)
      Text("Qaptr Home")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(QaptrColor.ink.opacity(0.85))
      Spacer()
      Button {
        model.screen = .settings
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 12, weight: .medium))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .foregroundStyle(QaptrColor.muted)
      .accessibilityLabel("Settings")
    }
    .padding(.leading, 92)
    .padding(.trailing, 10)
    .frame(height: 32)
    .background(Color.white.opacity(0.60))
    .overlay(alignment: .bottom) { Divider().opacity(0.35) }
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      statusIndicator
      VStack(alignment: .leading, spacing: state == .homeAnalyzing ? 2 : 0) {
        Text(toolbarTitle)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(QaptrColor.ink)
        if state == .homeAnalyzing {
          Text("Redacting private content")
            .font(.system(size: 12))
            .foregroundStyle(QaptrColor.muted)
        }
      }
      Spacer()
      toolbarButton
    }
    .padding(.horizontal, 40)
    .frame(height: state == .homeAnalyzing ? 72 : 60)
    .qaptrGlassSurface(radius: 0)
  }

  @ViewBuilder
  private var statusIndicator: some View {
    if state == .homeAnalyzing {
      ProgressView().controlSize(.small).frame(width: 16, height: 16)
    } else {
      ZStack {
        Circle().stroke(statusColor.opacity(0.18), lineWidth: 3).frame(width: 18, height: 18)
        Circle().fill(statusColor).frame(width: 6, height: 6)
      }
    }
  }

  private var toolbarTitle: String {
    switch state {
    case .homeEmpty: "Capturing quietly · 0 today"
    case .homePaused: "Capture paused"
    case .homeAttention: "Capture stopped in the background"
    case .homeAnalyzing: "Analyzing on this Mac..."
    case .homeWatching: "Watching closely · 23m left · 7 captures"
    case .homeWatchingDone: "Capturing quietly · 25 today"
    default: "Capturing quietly · 18 today"
    }
  }

  private var statusColor: Color {
    switch state {
    case .homePaused: QaptrColor.warning
    case .homeAttention: QaptrColor.danger
    case .homeWatching: QaptrColor.accent
    default: Color(red: 0.06, green: 0.73, blue: 0.51)
    }
  }

  @ViewBuilder
  private var toolbarButton: some View {
    let title: String = switch state {
    case .homePaused: "Resume"
    case .homeAttention: "Restart capture"
    case .homeAnalyzing: "Cancel"
    case .homeWatching: "Stop & review"
    default: "Analyze"
    }
    Button(title) {
      switch state {
      case .homePaused, .homeAttention, .homeAnalyzing:
        model.screen = .homeFindings
      case .homeWatching:
        model.screen = .homeWatchingDone
      default:
        model.screen = .consentReview
      }
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.roundedRectangle(radius: 6))
    .controlSize(.small)
    .tint(state == .homeAttention ? QaptrColor.danger : QaptrColor.accent)
  }

  @ViewBuilder
  private var content: some View {
    switch state {
    case .homeEmpty:
      emptyState(actionTitle: nil)
    case .homeReady:
      emptyState(actionTitle: "Analyze 18 captures")
    case .homeQuietResult:
      bannerFeed(
        icon: "sparkles",
        title: "No new patterns stood out this time",
        detail: nil,
        action: "Watch more closely for 30 minutes",
        actionScreen: .homeWatching,
        contextStyle: false
      )
    case .homeContextNudge:
      bannerFeed(
        icon: "rectangle.on.rectangle",
        title: "Findings get sharper with app and window names.",
        detail: "Optional - capture doesn't depend on it.",
        action: "Allow",
        actionScreen: .settings,
        contextStyle: true
      )
    case .homeWatchingDone:
      watchingDoneFeed
    default:
      findingsFeed(topInset: 18)
    }
  }

  private func emptyState(actionTitle: String?) -> some View {
    VStack(spacing: 24) {
      Spacer()
      ZStack {
        Circle().fill(QaptrColor.accent.opacity(0.10)).frame(width: 80, height: 80)
        Image(systemName: "shield.checkered")
          .font(.system(size: 36, weight: .light))
          .foregroundStyle(QaptrColor.accent)
      }
      VStack(spacing: 12) {
        Text("Nothing to review yet")
          .font(.system(size: 28, weight: .bold))
        Text("Qaptr is capturing quietly.  Work for a stretch, then analyze to see what it noticed.")
          .font(.system(size: 16))
          .foregroundStyle(QaptrColor.secondaryInk)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .frame(width: 520)
        if let actionTitle {
          Button(actionTitle) { model.screen = .consentReview }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .padding(.top, 4)
        }
      }
      Spacer()
    }
    .frame(width: 765)
    .padding(.horizontal, 40)
    .padding(.bottom, 40)
  }

  private func bannerFeed(
    icon: String,
    title: String,
    detail: String?,
    action: String,
    actionScreen: AppScreen,
    contextStyle: Bool
  ) -> some View {
    VStack(spacing: contextStyle ? 16 : 24) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(QaptrColor.accent)
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 15, weight: .semibold))
          if let detail {
            Text(detail).font(.system(size: 12)).foregroundStyle(QaptrColor.muted)
          }
        }
        Spacer()
        Button(action) { model.screen = actionScreen }
          .buttonStyle(.bordered)
          .buttonBorderShape(.roundedRectangle(radius: 8))
          .tint(QaptrColor.accent)
      }
      .padding(.horizontal, 24)
      .frame(height: contextStyle ? 76 : 84)
      .qaptrGlassSurface(radius: 16)

      if contextStyle {
        compactAnalysisFeed
      } else {
        earlierOnlyFeed
      }
    }
    .frame(width: 765, alignment: .top)
    .padding(.horizontal, 40)
    .padding(.top, 24)
    .padding(.bottom, 32)
  }

  private var watchingDoneFeed: some View {
    VStack(spacing: 24) {
      HStack(spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(QaptrColor.success)
        VStack(alignment: .leading, spacing: 3) {
          Text("Done watching ✓").font(.system(size: 15, weight: .semibold))
          Text("Qaptr collected 7 detailed captures of the launch-plan comparison.")
            .font(.system(size: 12)).foregroundStyle(QaptrColor.muted)
        }
        Spacer()
        Button("Analyze them") { model.screen = .consentReview }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.roundedRectangle(radius: 8))
        Button { model.screen = .homeFindings } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
      }
      .padding(.horizontal, 24)
      .frame(height: 71)
      .qaptrGlassSurface(radius: 16)

      findingsFeedBody
    }
    .frame(width: 765, alignment: .top)
    .padding(.horizontal, 40)
    .padding(.top, 18)
    .padding(.bottom, 40)
  }

  private func findingsFeed(topInset: CGFloat) -> some View {
    findingsFeedBody
      .frame(width: 765, alignment: .top)
      .padding(.horizontal, 40)
      .padding(.top, topInset)
      .padding(.bottom, 40)
  }

  private var findingsFeedBody: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 16) {
        sectionTitle("Today")
        findingCard(
          title: "Validate a product change before release",
          detail: "Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.",
          evidence: "📷 8 captures · 42 min",
          height: 164
        )
        findingCard(
          title: "Compare launch plans and record the decision",
          detail: "A product brief and planning document appeared together while tradeoffs were reviewed.",
          evidence: "📷 4 captures · 26 min",
          height: 144,
          footer: "Continue capturing to complete →"
        )
      }
      VStack(alignment: .leading, spacing: 16) {
        sectionTitle("Earlier")
        earlierCard
      }
    }
  }

  private var compactAnalysisFeed: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("From your last analysis")
      findingCard(
        title: "Validate a product change before release",
        detail: "Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.",
        evidence: "📷 8 captures · 42 min",
        height: 128,
        compact: true
      )
      findingCard(
        title: "Compare launch plans and record the decision",
        detail: "A product brief and planning document appeared together while tradeoffs were reviewed.",
        evidence: "📷 4 captures · 26 min",
        height: 128,
        footer: "Continue capturing to complete →",
        compact: true
      )
    }
  }

  private var earlierOnlyFeed: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Earlier")
      earlierCard.frame(height: 146)
    }
  }

  private var earlierCard: some View {
    findingCard(
      title: "You reviewed implementation feedback",
      detail: "A code review and terminal session were visible while you validated a small SwiftUI change against the packaged app.",
      evidence: "📷 3 captures · 18 min",
      height: 164
    )
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(QaptrColor.secondaryInk)
      .frame(height: 19)
  }

  private func findingCard(
    title: String,
    detail: String,
    evidence: String,
    height: CGFloat,
    footer: String? = nil,
    compact: Bool = false
  ) -> some View {
    Button {
      model.screen = .findingComplete
    } label: {
      VStack(alignment: .leading, spacing: compact ? 4 : 8) {
        Text(title)
          .font(.system(size: compact ? 17 : 22, weight: .regular))
          .foregroundStyle(QaptrColor.ink)
          .lineLimit(1)
        Text(detail)
          .font(.system(size: compact ? 13 : 15))
          .foregroundStyle(QaptrColor.secondaryInk)
          .lineLimit(compact ? 1 : 2)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack {
          Text(evidence)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: compact ? 22 : 28)
            .background(Color.black.opacity(0.045), in: Capsule())
          Spacer()
          if let footer {
            Text(footer)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(QaptrColor.accent)
          }
        }
      }
      .padding(24)
      .frame(width: 765, height: height, alignment: .topLeading)
      .contentShape(Rectangle())
      .qaptrGlassSurface(radius: 24)
    }
    .buttonStyle(.plain)
  }
}
