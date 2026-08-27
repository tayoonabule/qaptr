import QaptrReviewCore

// The old observation-sheet and two-step onboarding SwiftUI hierarchies were
// replaced by WorkflowSuggestionsView, FindingDetailView, and WelcomeView. Keep
// only the pure presentation decisions that still have direct contract tests.

enum ReviewContentState: Equatable {
  case error
  case empty
  case observations

  static func resolve(hasLoadError: Bool, observationCount: Int) -> ReviewContentState {
    if hasLoadError { return .error }
    return observationCount == 0 ? .empty : .observations
  }

  var headerTitle: String {
    switch self {
    case .error: return "Review setup"
    case .empty: return "Review"
    case .observations: return "What Qaptr found"
    }
  }

  var probeName: String {
    switch self {
    case .error: return "error"
    case .empty: return "empty"
    case .observations: return "observations"
    }
  }
}

enum AnalysisConsentPresentation {
  static func privacyTitle(_ summary: ReviewConsentSummary) -> String {
    if summary.imageCount == 0 {
      return "Screenshot files stay on this Mac"
    }
    return "Screenshot files are included in this request"
  }

  static func payloadLabel(_ summary: ReviewConsentSummary) -> String {
    if summary.payloadKind == "text", summary.imageCount == 0 {
      return "Privacy-filtered OCR text"
    }
    return summary.payloadKind
  }

  static func privacyExplanation(_ summary: ReviewConsentSummary) -> String {
    if summary.imageCount == 0 {
      return
        "Qaptr extracted and privacy-filtered text from \(summary.captureCount) capture\(summary.captureCount == 1 ? "" : "s"). The provider receives that text, not the images."
    }
    return
      "This request includes \(summary.imageCount) image\(summary.imageCount == 1 ? "" : "s") and prepared context from \(summary.captureCount) capture\(summary.captureCount == 1 ? "" : "s")."
  }
}

enum EmptyStateView {
  private static func allCapturesExcluded(
    captureCount: Int?, notices: [ExclusionNotice]
  ) -> Bool {
    guard let count = captureCount, count > 0 else { return false }
    return !notices.isEmpty
  }

  static func title(
    captureCount: Int?, notices: [ExclusionNotice], analysisState: String? = nil
  ) -> String {
    switch captureCount {
    case .some(0):
      "No screenshots have been captured yet."
    case .some where allCapturesExcluded(captureCount: captureCount, notices: notices):
      "Every recent screenshot was excluded before analysis."
    case .some(let count) where count > 0 && analysisState == "unavailable":
      "\(count) screenshot\(count == 1 ? "" : "s") captured. Analysis is unavailable."
    case .some(let count) where count > 0:
      "\(count) screenshot\(count == 1 ? " is" : "s are") waiting for analysis."
    default:
      "No observations yet."
    }
  }

  static func detail(
    captureCount: Int?, statusLabel: String, notices: [ExclusionNotice],
    analysisState: String? = nil
  ) -> String {
    switch captureCount {
    case .some(0):
      "\(statusLabel). Notes show up here after Qaptr checks a screenshot."
    case .some where allCapturesExcluded(captureCount: captureCount, notices: notices):
      "Local privacy preparation could not safely include any recent capture. See the notice below for the reason."
    case .some where captureCount ?? 0 > 0 && analysisState == "unavailable":
      "This build can capture screenshots, but it cannot turn them into observations yet."
    case .some where captureCount ?? 0 > 0:
      "Qaptr has not produced an observation yet."
    default:
      "Qaptr is still getting ready."
    }
  }
}

enum OnboardingView {
  static func liveCaptureDisplaysText(
    helperIsRunning: Bool, selectedDisplayIDs: [String]
  ) -> String? {
    guard helperIsRunning else { return nil }
    guard !selectedDisplayIDs.isEmpty else {
      return "Capture is running but has not reported a selected screen yet."
    }
    return
      "Currently capturing \(selectedDisplayIDs.count) screen\(selectedDisplayIDs.count == 1 ? "" : "s")."
  }
}
