import AppKit
import QaptrReviewCore
import SwiftUI

/// The visual language for the redesigned review surface. These tokens are
/// deliberately local so Settings and ProviderSetupSheet keep their existing
/// compatibility palette.
enum ReviewDesign {
  static let ink = Color.qaptrInk
  static let slate = Color.qaptrSlate
  static let muted = Color.qaptrInkMuted
  static let accent = Color.qaptrAccent
  static let green = Color.qaptrSuccess
  static let orange = Color.qaptrWarning
  static let red = Color.qaptrError
  static let canvasBlue = Color(red: 199 / 255, green: 209 / 255, blue: 230 / 255)
  static let canvasWhite = Color.white
  static var canvas: some View {
    GeometryReader { proxy in
      RadialGradient(
        colors: [canvasBlue, canvasWhite],
        center: UnitPoint(x: 0.5, y: 1.0),
        startRadius: 0,
        endRadius: max(proxy.size.width, proxy.size.height) * 0.72
      )
    }
  }
}

/// Figma's "Liquid Glass - Card" (nodes `27:1056` / `27:1091` / `10:49`) is a
/// stack of ordinary compositing layers, not a platform material. Each
/// overlay below is one Figma fill layer, in the same order, with Figma's own
/// blend-mode enum (`PLUS_LIGHTER` / `PLUS_DARKER`, not the CSS
/// `lighten`/`darken` the dev-mode codegen substitutes for browser
/// compatibility):
///   1. `rgba(255,255,255,0.25)` — `.plusLighter`.
///   2. `rgba(191,191,191,0.08)` — `.plusDarker`.
///   3. `rgba(255,255,255,0.1)` — `.multiply`.
///   4. `0px 0px 0px 0.5px #dbdbdb` — a hairline outer border, not a shadow.
///   5. `inset 0 40px 10px -40px #282828` / `inset 0 -40px 10px -40px
///      #282828` on the top and bottom edges — the vignette that gives the
///      glass its rounded-tube falloff.
///   6. `0px 12px 32px 0px rgba(0,0,0,0.06)` — the card's cast drop shadow.
struct FigmaGlassSurface: View {
  let radius: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(Color.white.opacity(0.25))
      .blendMode(.plusLighter)
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(Color(red: 191 / 255, green: 191 / 255, blue: 191 / 255).opacity(0.08))
          .blendMode(.plusDarker)
      }
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(Color.white.opacity(0.10))
          .blendMode(.multiply)
      }
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Color(red: 219 / 255, green: 219 / 255, blue: 219 / 255), lineWidth: 0.5)
      }
      .overlay {
        VStack(spacing: 0) {
          LinearGradient(
            colors: [Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255).opacity(0.14), .clear],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 40)
          Spacer(minLength: 0)
          LinearGradient(
            colors: [.clear, Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255).opacity(0.14)],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 40)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .allowsHitTesting(false)
      }
      .shadow(color: .black.opacity(0.06), radius: 16, y: 12)
  }
}

struct ReviewGlassCard<Content: View>: View {
  let padding: CGFloat
  @ViewBuilder let content: Content

  init(padding: CGFloat = 24, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background { FigmaGlassSurface(radius: 24) }
  }
}

/// The recommendation block follows the dedicated Figma glass recipe rather
/// than the larger editorial card recipe used elsewhere in the review flow.
struct ReviewSuggestionCard<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(24)
      .background { FigmaGlassSurface(radius: 24) }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}
}

struct ReviewSuggestionPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.white)
      .padding(.horizontal, 24)
      .frame(height: 32)
      .background(
        Color(red: 0.145, green: 0.388, blue: 0.922),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0.0))
      }
      .shadow(color: Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.20), radius: 6, y: 4)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct ReviewEvidenceChip: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(ReviewDesign.slate)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.black.opacity(0.045), in: Capsule())
      .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
  }
}

struct ReviewToastView: View {
  let text: String
  let dismiss: () -> Void

  var body: some View {
    Button(action: dismiss) {
      HStack(spacing: 10) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color.qaptrSuccess)
        Text(text)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(ReviewDesign.ink)
        Spacer(minLength: 4)
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(ReviewDesign.muted)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(minWidth: 220, alignment: .leading)
      .background { FigmaGlassSurface(radius: 14) }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(text)
    .task {
      do {
        try await Task.sleep(nanoseconds: 3_000_000_000)
      } catch {
        return
      }
      dismiss()
    }
  }
}

/// The intentionally short first-run handoff from the screen-recording
/// permission to Home. Optional Accessibility context is offered later by the
/// feed, when the benefit is visible.
struct WelcomeView: View {
  @Bindable var model: ReviewAppModel

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var message: String?

  var body: some View {
    VStack(spacing: 0) {
      QaptrOnboardingTitleBar(title: onboardingTitle)
      ZStack {
        // Figma's Welcome frame (nodes 27:1034 / 27:1069) fills the canvas with
        // a radial gradient: `#C7D1E6` at the bottom-center fading to white at
        // the edges (`gradientTransform` centered at x=422.5,y=737 of an
        // 845×737 frame). This is the same shape as `ReviewDesign.canvas`, so
        // reuse it instead of an unrelated linear gradient.
        ReviewDesign.canvas
          .ignoresSafeArea()

        VStack(spacing: 0) {
          VStack(spacing: 32) {
            QaptrBrandLogo(iconSize: 42, textSize: 28, wordmark: true)
            Text(heroTitle)
              .font(.system(size: 26, weight: .regular))
              .foregroundStyle(Color.qaptrLabelPrimary)
              .multilineTextAlignment(.center)
              .frame(width: 416, height: heroTitleHeight)
          }
          .frame(width: 725, height: heroStackHeight)

          permissionCard
            .padding(.top, 72)
          privacyFooter
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 158)
      }
      .frame(width: 845, height: 706)
    }
    .onAppear {
      refresh()
      advanceIfReady()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { refresh() }
    }
    .task {
      while !Task.isCancelled {
        refresh()
        advanceIfReady()
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
      }
    }
  }

  private var onboardingTitle: String { "Qaptr Setup" }

  private var primaryLabel: String {
    switch model.settings.screenRecordingStatus {
    case .denied: "Open System Settings"
    default: "Allow Screen Recording"
    }
  }

  private var heroTitle: String {
    switch model.settings.screenRecordingStatus {
    case .denied:
      "Uh oh. Our local tools can’t Qaptr much without seeing your screen."
    case .granted:
      "Finally, a way to Qaptr that one task you’ve always wanted to delegate."
    default:
      "You’re so close!!!"
    }
  }

  private var heroTitleHeight: CGFloat {
    model.settings.screenRecordingStatus == .notDetermined ? 32 : 64
  }

  private var heroStackHeight: CGFloat {
    model.settings.screenRecordingStatus == .notDetermined ? 115 : 147
  }

  private var permissionBadge: (label: String, color: Color)? {
    switch model.settings.screenRecordingStatus {
    case .denied: ("Denied", ReviewDesign.red)
    case .granted: nil
    default: ("Waiting...", ReviewDesign.orange)
    }
  }

  private var permissionCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 8) {
        Text("Allow Screen Recording")
          .font(.system(size: 15, weight: .semibold))
          .tracking(-0.3)
          .foregroundStyle(Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255))
        if let permissionBadge {
          Text(permissionBadge.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(permissionBadge.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(permissionBadge.color.opacity(0.1), in: Capsule())
        }
      }
      Text(
        "Screen Recording is the one required permission. QaptrHelper owns capture and reports the live result here."
      )
      .font(.system(size: 13, weight: .regular))
      .foregroundStyle(Color(red: 68 / 255, green: 68 / 255, blue: 68 / 255))
      .fixedSize(horizontal: false, vertical: true)
      Button(action: primaryAction) {
        HStack(spacing: 8) {
          Text(primaryLabel)
            .font(QaptrType.body(13))
          QaptrSVGImage(resourceName: "b453e64d37d7cd6258c15c3274a67f60ee559133")
            .frame(width: 14.4, height: 14.4)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background {
          // Figma's Primary CTA Button (nodes 27:1207 / 27:1214): a flat
          // #2563EB fill, a colored glow drop shadow, and three inset bevel
          // shadows built as clipped edge-highlight overlays because
          // SwiftUI has no native inset-shadow modifier.
          RoundedRectangle(cornerRadius: QaptrRadius.cta, style: .continuous)
            .fill(Color.qaptrCTAAction)
            .overlay {
              RoundedRectangle(cornerRadius: QaptrRadius.cta, style: .continuous)
                .fill(
                  LinearGradient(
                    colors: [Color.white.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
                .frame(height: 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: QaptrRadius.cta, style: .continuous))
                .allowsHitTesting(false)
            }
            .overlay {
              RoundedRectangle(cornerRadius: QaptrRadius.cta, style: .continuous)
                .fill(
                  RadialGradient(
                    colors: [Color.black.opacity(0.3), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 18
                  )
                )
                .clipShape(RoundedRectangle(cornerRadius: QaptrRadius.cta, style: .continuous))
                .allowsHitTesting(false)
            }
            .shadow(color: Color.qaptrCTAAction.opacity(0.2), radius: 6, y: 4)
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .keyboardShortcut(.defaultAction)
    }
    .padding(24)
    .frame(
      width: 580,
      height: model.settings.screenRecordingStatus == .granted ? 148 : 165,
      alignment: .topLeading
    )
    .background { FigmaGlassSurface(radius: QaptrRadius.glass) }
  }

  private var privacyFooter: some View {
    HStack(spacing: 8) {
      // Figma's "Privacy Shield Footer" (nodes 27:1064-1068 / 27:1099-1103)
      // wraps the shield vector in a 22×22 circular frame with a 0.1-opacity
      // black hairline, not a bare SF Symbol.
      QaptrSVGImage(resourceName: "60d3b965b4421c73b8944122e46cb4999a5e2c57")
        .frame(width: 12, height: 12)
        .padding(5)
        .background(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
      Text(
        model.settings.screenRecordingStatus == .denied
          ? "Enable QaptrHelper in Screen Recording, then return to Qaptr."
          : "You can change privacy and capture choices later in Settings."
      )
      .font(.system(size: 12, weight: .regular))
      .foregroundStyle(Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255))
    }
  }

  private func primaryAction() {
    if model.settings.screenRecordingStatus == .denied {
      model.requestScreenRecording()
    } else {
      model.requestScreenRecording()
    }
  }

  private func refresh() {
    model.refreshSettings()
    model.refreshPermissions()
  }

  private func advanceIfReady() {
    guard model.settings.screenRecordingStatus == .granted else { return }
    guard !model.onboardingCompleted else { return }
    if !model.completeOnboarding() {
      if model.settings.availableDisplayIDs.isEmpty {
        message = "Connect a display, then Qaptr will begin quietly."
      } else if !reduceMotion {
        message = "Qaptr is checking the helper before starting capture."
      }
    }
  }
}

struct ReviewStatusStrip: View {
  let progress: CaptureProgressSnapshot
  let helperIsRunning: Bool
  let captureIntent: CaptureControlIntent
  let session: ReviewSessionState
  let detailedCapture: DetailedCaptureState
  let analyze: () -> Void
  let pause: () -> Void
  let resume: () -> Void
  let cancel: () -> Void
  let retry: () -> Void
  let requestPermission: () -> Void
  let restart: () -> Void
  let stopDetailed: () -> Void
  let openSettings: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 14) {
      Circle()
        .fill(statusColor)
        .frame(width: 6, height: 6)
        .shadow(color: statusColor.opacity(0.35), radius: 5)

      VStack(alignment: .leading, spacing: 1) {
        Text(statusTitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(ReviewDesign.ink)
        if displayState == .working {
          Text(statusDetail)
            .font(.system(size: 12))
            .foregroundStyle(ReviewDesign.muted)
        }
      }

      Spacer(minLength: 12)
      action
    }
    .padding(.horizontal, 40)
    .frame(height: 60)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.white.opacity(0.75))
        .frame(height: 1)
    }
    .onHover { isHovering = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(statusTitle)
    .accessibilityValue(statusDetail)
  }

  @ViewBuilder
  private var action: some View {
    switch displayState {
    case .capturing:
      HStack(spacing: 10) {
        Button("Analyze", action: analyze)
          .buttonStyle(.borderedProminent)
          .tint(ReviewDesign.accent)
          .disabled((progress.captureCount ?? 0) == 0)
        Button("Pause", action: pause)
          .buttonStyle(.plain)
          .foregroundStyle(ReviewDesign.muted)
          .opacity(isHovering ? 1 : 0.65)
      }
    case .paused:
      Button("Resume", action: resume)
        .buttonStyle(.borderedProminent)
        .tint(ReviewDesign.accent)
    case .permission:
      Button("Open System Settings", action: requestPermission)
        .buttonStyle(.borderedProminent)
        .tint(ReviewDesign.accent)
    case .helper:
      Button("Restart capture", action: restart)
        .buttonStyle(.borderedProminent)
        .tint(ReviewDesign.accent)
    case .noDisplays:
      EmptyView()
    case .providerFailed:
      Button("Try again", action: retry)
        .buttonStyle(.borderedProminent)
        .tint(ReviewDesign.accent)
    case .working:
      Button("Cancel", action: cancel)
        .buttonStyle(.plain)
        .foregroundStyle(ReviewDesign.muted)
    case .approval:
      EmptyView()
    case .watching:
      Button("Stop & review", action: stopDetailed)
        .buttonStyle(.borderedProminent)
        .tint(ReviewDesign.accent)
    }
  }

  private enum DisplayState {
    case capturing, paused, permission, helper, noDisplays, providerFailed, working, approval,
      watching
  }

  private var displayState: DisplayState {
    if detailedCapture.lifecycle == .capturing { return .watching }
    switch session.phase {
    case .ingesting, .preparing, .analyzing: return .working
    case .readyForConsent: return .approval
    case .failed: return .providerFailed
    default: break
    }
    if captureIntent == .paused || progress.state == .paused || progress.state == .stopped {
      return .paused
    }
    switch progress.state {
    case .permissionRequired: return .permission
    case .noDisplays: return .noDisplays
    case .error, .unknown: return .helper
    case .starting, .waiting, .capturing:
      return helperIsRunning ? .capturing : .helper
    case .paused, .stopped: return .paused
    }
  }

  private var captureCountLabel: String {
    guard let count = progress.captureCount else { return "Waiting for the capture helper" }
    return "\(count) today"
  }

  private var statusTitle: String {
    switch displayState {
    case .capturing: "Capturing quietly · \(captureCountLabel)"
    case .paused: "Capture paused"
    case .permission: "Screen Recording was turned off"
    case .helper: "Capture stopped in the background"
    case .noDisplays: "No display connected"
    case .providerFailed: "The last analysis couldn’t finish"
    case .working: "Analyzing on this Mac…"
    case .approval: "Analysis is ready for your approval"
    case .watching: "Watching closely · detailed capture active"
    }
  }

  private var statusDetail: String {
    switch displayState {
    case .capturing: "Qaptr is keeping a quiet local record."
    case .paused: "Resume whenever you want Qaptr to notice more."
    case .permission: "Screen Recording is required to continue capturing."
    case .helper: progress.failureReason ?? "Restart the helper to resume local capture."
    case .noDisplays: "Connect a display and capture will resume on its own."
    case .providerFailed: "Your captures stayed local. Try the review again when ready."
    case .working: workingDetail
    case .approval: "Review the privacy-safe summary before anything leaves this Mac."
    case .watching: "Qaptr is collecting more detail for a finding."
    }
  }

  private var workingDetail: String {
    switch session.phase {
    case .ingesting: "Reading captures"
    case .preparing: "Redacting private content"
    case .analyzing: "The selected provider is reviewing approved text"
    default: "Preparing your review"
    }
  }

  private var statusColor: Color {
    switch displayState {
    case .capturing: ReviewDesign.green
    case .paused, .watching: ReviewDesign.accent
    case .permission, .helper, .noDisplays, .providerFailed: ReviewDesign.orange
    case .working, .approval: ReviewDesign.accent
    }
  }
}

struct ReviewFindingRow: View {
  let finding: ReviewFinding
  let open: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          Text(finding.title)
            .font(QaptrType.title(16))
            .foregroundStyle(ReviewDesign.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(finding.summary)
            .font(QaptrType.body(13))
            .foregroundStyle(ReviewDesign.slate)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
          ReviewEvidenceChip(text: "📷  \(finding.evidenceText)")
          if finding.incomplete {
            Text("Continue capturing to complete →")
              .font(QaptrType.caption(12))
              .foregroundStyle(ReviewDesign.accent)
          }
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        hovering ? ReviewDesign.accent.opacity(0.08) : Color.white.opacity(0.16),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel(finding.accessibilityLabel)
    .accessibilityHint("Open finding details")
  }
}

enum ReviewFindingKind {
  case workflow
  case observation
}

struct ReviewFinding: Identifiable {
  let id: String
  let kind: ReviewFindingKind
  let title: String
  let summary: String
  let evidenceText: String
  let incomplete: Bool
  let candidate: WorkflowCandidate?
  let observation: QaptrObservation?

  var accessibilityLabel: String {
    "\(title), \(evidenceText)"
  }
}

struct FindingDetailView: View {
  let finding: ReviewFinding
  let saved: Bool
  let save: () -> Void
  let captureMoreDetail: () -> Void
  let back: () -> Void

  @State private var correction = ""
  @State private var correctionMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        Button(action: back) {
          Label("All findings", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReviewDesign.muted)

        VStack(alignment: .leading, spacing: 12) {
          if let candidate = finding.candidate {
            Text(String(format: "%02d", candidate.rank))
              .font(.system(size: 12, weight: .semibold, design: .monospaced))
              .foregroundStyle(ReviewDesign.accent)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(ReviewDesign.accent.opacity(0.10), in: Capsule())
          }
          Text(finding.title)
            .font(.system(size: 32, weight: .regular, design: .serif))
            .foregroundStyle(ReviewDesign.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(finding.summary)
            .font(.system(size: 16))
            .foregroundStyle(ReviewDesign.slate)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            ReviewEvidenceChip(text: finding.evidenceText)
            if saved { savedPill }
          }
        }

        Divider()

        if let candidate = finding.candidate {
          candidateDetail(candidate)
        } else if let observation = finding.observation {
          observationDetail(observation)
        }
      }
      .frame(maxWidth: 900, alignment: .leading)
      .padding(.horizontal, 54)
      .padding(.top, 30)
      .padding(.bottom, 54)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if finding.candidate != nil {
          Button(saved ? "Saved ✓" : "Save workflow", action: save)
            .buttonStyle(.borderedProminent)
            .tint(saved ? ReviewDesign.green : ReviewDesign.accent)
        }
      }
    }
  }

  @ViewBuilder
  private func candidateDetail(_ candidate: WorkflowCandidate) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      ReviewGlassCard {
        VStack(alignment: .leading, spacing: 10) {
          Label(
            candidate.evidenceStatus.reviewTitle,
            systemImage: candidate.evidenceStatus.reviewSymbolName
          )
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(candidate.evidenceStatus.reviewColor)
          Text(candidate.evidenceBasis)
            .font(.system(size: 15))
            .foregroundStyle(ReviewDesign.slate)
            .lineSpacing(3)
          HStack(spacing: 16) {
            detailMetadata("Evidence", value: "\(candidate.evidenceCaptureCount) captures")
            if let observedSpan = candidate.observedSpanLabel {
              detailMetadata("Observed", value: observedSpan)
            }
          }
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Why Qaptr suggested this")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(ReviewDesign.ink)
        Text(candidate.rationale)
          .font(.system(size: 15))
          .foregroundStyle(ReviewDesign.slate)
          .lineSpacing(3)
      }

      if let recommendation = candidate.recommendation {
        ReviewSuggestionCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Capture more detail")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(Color(red: 0.294, green: 0.333, blue: 0.388))
            Text("The broad pattern is visible, but Qaptr missed an important decision or handoff.")
              .font(.system(size: 15))
              .foregroundStyle(Color(red: 0.294, green: 0.333, blue: 0.388))
              .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
              Button("Capture more detail", action: captureMoreDetail)
                .buttonStyle(ReviewSuggestionPrimaryButtonStyle())
              Button("Keep it as is", action: back)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.294, green: 0.333, blue: 0.388))
            }
            .padding(.top, 4)
            Text(
              "Watch every \(recommendation.intervalSeconds) seconds for \(recommendation.reviewDurationLabel)."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ReviewDesign.accent)
          }
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("What did Qaptr misunderstand?")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(ReviewDesign.ink)
        TextField("Tell Qaptr what to correct…", text: $correction)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("Submit correction") {
            correctionMessage =
              correction.isEmpty
              ? "Add a correction before saving."
              : "Corrections are not connected to this review yet."
          }
          .buttonStyle(.bordered)
          .disabled(correction.isEmpty)
          if let correctionMessage {
            Text(correctionMessage)
              .font(.system(size: 12))
              .foregroundStyle(ReviewDesign.muted)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func observationDetail(_ observation: QaptrObservation) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      ReviewGlassCard {
        VStack(alignment: .leading, spacing: 12) {
          Text("What Qaptr noticed")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ReviewDesign.ink)
          Text(observation.summary)
            .font(.system(size: 15))
            .foregroundStyle(ReviewDesign.slate)
            .lineSpacing(3)
          HStack(spacing: 16) {
            detailMetadata("Confidence", value: observation.confidenceBand.label)
            detailMetadata("Created", value: observation.createdAtLabel)
          }
          if let captureID = observation.captureID {
            detailMetadata("Capture", value: captureID)
          }
          detailMetadata("Session", value: observation.sessionID)
        }
      }
      Text("This explanation contains no source screenshots or provider payload.")
        .font(.system(size: 13))
        .foregroundStyle(ReviewDesign.muted)
    }
  }

  private func detailMetadata(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(ReviewDesign.muted)
      Text(value)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(ReviewDesign.slate)
    }
  }

  private var savedPill: some View {
    Label("Saved to workflows", systemImage: "checkmark")
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(ReviewDesign.green)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(ReviewDesign.green.opacity(0.12), in: Capsule())
  }
}

extension WorkflowEvidenceStatus {
  fileprivate var reviewTitle: String {
    switch self {
    case .enoughInformation: "Enough information"
    case .needsMoreDetail: "Needs more detail"
    case .needsMoreFrequentObservation: "Needs more frequent observation"
    }
  }

  fileprivate var reviewSymbolName: String {
    switch self {
    case .enoughInformation: "checkmark.circle.fill"
    case .needsMoreDetail: "viewfinder.circle"
    case .needsMoreFrequentObservation: "timer.circle"
    }
  }

  fileprivate var reviewColor: Color {
    switch self {
    case .enoughInformation: ReviewDesign.green
    case .needsMoreDetail: ReviewDesign.orange
    case .needsMoreFrequentObservation: ReviewDesign.accent
    }
  }
}

extension WorkflowCaptureRecommendation {
  fileprivate var reviewDurationLabel: String {
    durationSeconds < 60 ? "\(durationSeconds) seconds" : "\(durationSeconds / 60) minutes"
  }
}

private extension WorkflowCandidate {
  var observedSpanLabel: String? {
    guard let start = observedStartAtMillis, let end = observedEndAtMillis else { return nil }
    let minutes = max(0, Int((end - start) / 60_000))
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}

private extension QaptrObservation {
  var createdAtLabel: String {
    Date(timeIntervalSince1970: Double(createdAtMillis) / 1_000)
      .formatted(date: .long, time: .shortened)
  }
}
