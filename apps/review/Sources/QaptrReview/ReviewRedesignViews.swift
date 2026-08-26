import AppKit
import QaptrReviewCore
import SwiftUI

/// The visual language for the redesigned review surface. These tokens are
/// deliberately local so Settings and ProviderSetupSheet keep their existing
/// compatibility palette.
enum ReviewDesign {
  static let ink = Color(red: 0x11 / 255.0, green: 0x18 / 255.0, blue: 0x26 / 255.0)
  static let slate = Color(red: 0x4B / 255.0, green: 0x55 / 255.0, blue: 0x63 / 255.0)
  static let muted = Color(red: 0x64 / 255.0, green: 0x74 / 255.0, blue: 0x8B / 255.0)
  static let accent = Color(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0)
  static let green = Color(red: 0x35 / 255.0, green: 0xC7 / 255.0, blue: 0x5A / 255.0)
  static let orange = Color.orange
  static let red = Color.red
  static let canvas = RadialGradient(
    colors: [Color.white, Color(red: 0.91, green: 0.94, blue: 0.97)],
    center: UnitPoint(x: 0.78, y: 0.82),
    startRadius: 80,
    endRadius: 720
  )
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
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.07), radius: 28, y: 12)
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
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(Color.white.opacity(0.25))
          .blendMode(.plusLighter)
          .allowsHitTesting(false)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(Color(red: 0.859, green: 0.859, blue: 0.859), lineWidth: 0.5)
      }
      .overlay {
        VStack(spacing: 0) {
          LinearGradient(
            colors: [.clear, .black.opacity(0.10)], startPoint: .top, endPoint: .bottom
          )
          .frame(height: 12)
          Spacer()
          LinearGradient(
            colors: [.black.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom
          )
          .frame(height: 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .opacity(0.35)
        .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .shadow(color: .black.opacity(0.06), radius: 16, y: 12)
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
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    QaptrGlassBackdrop {
      HStack(spacing: 24) {
        Image(systemName: model.settings.screenRecordingStatus == .denied
          ? "exclamationmark.shield.fill" : "rectangle.dashed.and.paperclip")
          .font(.system(size: 28, weight: .medium))
          .foregroundStyle(model.settings.screenRecordingStatus == .denied
            ? ReviewDesign.orange : ReviewDesign.accent)
          .frame(width: 48)

        VStack(alignment: .leading, spacing: 5) {
          Text(model.settings.screenRecordingStatus == .denied
            ? "Screen Recording is off" : "Allow Screen Recording")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(ReviewDesign.ink)
          Text(model.settings.screenRecordingStatus == .denied
            ? "Enable QaptrHelper in Screen Recording, then return to Qaptr."
            : "Screen Recording is the one required permission. QaptrHelper owns capture and reports the live result here.")
            .font(.system(size: 13))
            .foregroundStyle(ReviewDesign.slate)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          if let message {
            Text(message)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(ReviewDesign.orange)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        Button(primaryLabel, action: primaryAction)
          .buttonStyle(.borderedProminent)
          .tint(ReviewDesign.accent)
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 28)
      .frame(width: 580, height: 160)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.12), radius: 26, y: 12)
    }
    .frame(width: 845, height: 706)
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

  private var primaryLabel: String {
    switch model.settings.screenRecordingStatus {
    case .denied: "Open System Settings"
    default: "Allow Screen Recording"
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
    ReviewGlassCard(padding: 18) {
      HStack(spacing: 14) {
        Circle()
          .fill(statusColor)
          .frame(width: 9, height: 9)
          .shadow(color: statusColor.opacity(0.35), radius: 5)

        VStack(alignment: .leading, spacing: 3) {
          Text(statusTitle)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ReviewDesign.ink)
          Text(statusDetail)
            .font(.system(size: 12))
            .foregroundStyle(ReviewDesign.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 12)
        action
      }
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
      HStack(alignment: .top, spacing: 16) {
        Image(systemName: finding.kind == .workflow ? "sparkles" : "text.quote")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(finding.kind == .workflow ? ReviewDesign.accent : ReviewDesign.muted)
          .frame(width: 24, height: 24)
          .background(
            (finding.kind == .workflow ? ReviewDesign.accent : ReviewDesign.muted).opacity(0.10),
            in: Circle()
          )

        VStack(alignment: .leading, spacing: 7) {
          Text(finding.title)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(ReviewDesign.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(finding.summary)
            .font(.system(size: 13))
            .foregroundStyle(ReviewDesign.slate)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            ReviewEvidenceChip(text: finding.evidenceText)
            if finding.incomplete {
              Text("Qaptr can finish this picture →")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ReviewDesign.accent)
            }
          }
        }

        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(ReviewDesign.muted)
          .padding(.top, 5)
      }
      .padding(.vertical, 18)
      .padding(.horizontal, 18)
      .background(
        hovering ? ReviewDesign.accent.opacity(0.06) : .clear,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        TextField("Optional correction", text: $correction)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("Save correction") {
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
      Text("What Qaptr noticed")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(ReviewDesign.ink)
      Text(observation.summary)
        .font(.system(size: 15))
        .foregroundStyle(ReviewDesign.slate)
        .lineSpacing(3)
      Text("This observation is a record, not a workflow recommendation.")
        .font(.system(size: 13))
        .foregroundStyle(ReviewDesign.muted)
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

/// Home's single adaptive canvas. The view deliberately derives every visible
/// state from the shared model so the status strip and menu-bar surfaces cannot
/// drift apart.
struct RedesignedHomeView: View {
  @Bindable var model: ReviewAppModel
  let openSettings: () -> Void

  @State private var selectedFinding: ReviewFinding?

  var body: some View {
    ZStack {
      ReviewDesign.canvas.ignoresSafeArea()

      if let selectedFinding {
        FindingDetailView(
          finding: selectedFinding,
          saved: false,
          save: {},
          captureMoreDetail: model.startDetailedCapture,
          back: { self.selectedFinding = nil }
        )
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            HStack {
              QaptrBrandLogo(iconSize: 22, textSize: 18)
              Spacer()
              Button(action: openSettings) {
                Image(systemName: "gearshape")
              }
              .buttonStyle(.plain)
              .foregroundStyle(ReviewDesign.muted)
              .accessibilityLabel("Open Settings")
            }

            ReviewStatusStrip(
              progress: model.captureProgress,
              helperIsRunning: model.captureHelperIsRunning,
              captureIntent: model.captureControlIntent,
              session: model.analysisSessionState,
              detailedCapture: model.detailedCaptureState,
              analyze: model.startAnalysis,
              pause: model.pauseCapture,
              resume: model.resumeCapture,
              cancel: model.cancelAnalysis,
              retry: model.retryAnalysis,
              requestPermission: model.requestScreenRecording,
              restart: model.restartCaptureHelper,
              stopDetailed: model.stopDetailedCapture,
              openSettings: openSettings
            )

            feed
          }
          .frame(maxWidth: 760, alignment: .leading)
          .padding(.horizontal, 42)
          .padding(.top, 28)
          .padding(.bottom, 48)
          .frame(maxWidth: .infinity)
        }
      }
    }
    .onAppear { model.refresh() }
  }

  @ViewBuilder
  private var feed: some View {
    let findings =
      model.workflowCandidates.map { candidate in
        ReviewFinding(
          id: candidate.id,
          kind: .workflow,
          title: candidate.title,
          summary: candidate.rationale,
          evidenceText: "\(candidate.evidenceCaptureCount) captures",
          incomplete: candidate.recommendation != nil,
          candidate: candidate,
          observation: nil
        )
      }
      + model.snapshot.observations.map { observation in
        ReviewFinding(
          id: observation.id,
          kind: .observation,
          title: observation.title,
          summary: observation.summary,
          evidenceText: "Observation",
          incomplete: false,
          candidate: nil,
          observation: observation
        )
      }

    VStack(alignment: .leading, spacing: 18) {
      Text("Findings")
        .font(.system(size: 26, weight: .regular, design: .serif))
        .foregroundStyle(ReviewDesign.ink)

      if findings.isEmpty {
        ReviewGlassCard {
          VStack(alignment: .leading, spacing: 10) {
            Text("Nothing to review yet.")
              .font(.system(size: 22, weight: .regular))
              .foregroundStyle(ReviewDesign.ink)
            Text(
              (model.captureProgress.captureCount ?? 0) > 0
                ? "Qaptr has captures ready. Analyze them when you want to see what it noticed."
                : "Qaptr is capturing quietly. Work for a stretch, then analyze to see what it noticed."
            )
            .font(.system(size: 15))
            .foregroundStyle(ReviewDesign.slate)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        VStack(spacing: 2) {
          ForEach(findings) { finding in
            ReviewFindingRow(finding: finding) {
              selectedFinding = finding
            }
          }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      }
    }
  }
}
