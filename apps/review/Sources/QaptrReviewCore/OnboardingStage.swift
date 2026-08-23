import Foundation

/// One step in the first-run permission sequence.
///
/// Capture starts from the final action in this sequence. Provider setup is
/// deliberately not part of onboarding: it belongs to the later, explicit
/// analysis flow and must not delay local capture.
public enum OnboardingStage: Int, CaseIterable, Equatable, Sendable {
  case screenRecording = 0
  case accessibilityContext = 1

  public var next: OnboardingStage? {
    OnboardingStage(rawValue: rawValue + 1)
  }

  /// The stage before this one, or `nil` for the first stage.
  ///
  /// Onboarding's "forward-only, runs once" guarantee (R-D7) governs
  /// whether onboarding can be *re-entered* after completion, not whether
  /// a user mid-flow can step back to re-read an earlier stage. `previous`
  /// only supports in-flow review; it is never used to reset
  /// `SettingsPreferences.onboardingCompleted` or to re-trigger a provider
  /// request, so it does not weaken KTD10's just-in-time consent boundary.
  public var previous: OnboardingStage? {
    OnboardingStage(rawValue: rawValue - 1)
  }

  public var title: String {
    switch self {
    case .screenRecording: "Screen Recording"
    case .accessibilityContext: "Optional context"
    }
  }
}

/// User-facing choices for the future detailed-capture session.
///
/// The review app can persist this preference locally, but it must not claim
/// that a detailed session is active until the helper acknowledges a real
/// command. The current transport is intentionally unavailable, so the
/// settings surface renders that limitation explicitly.
public enum DetailedSessionDuration: String, CaseIterable, Equatable, Sendable {
  case thirtyMinutes
  case oneHour
  case twoHours

  public var seconds: Int {
    switch self {
    case .thirtyMinutes: 30 * 60
    case .oneHour: 60 * 60
    case .twoHours: 2 * 60 * 60
    }
  }

  public var displayName: String {
    switch self {
    case .thirtyMinutes: "30 minutes"
    case .oneHour: "1 hour"
    case .twoHours: "2 hours"
    }
  }
}

/// The plain-language rationale shown for each requested permission.
///
/// Screen Recording is explained as required; Accessibility context is
/// explained as optional and separate, matching AE9's requirement that
/// optional context permissions are explained apart from the required one.
public enum PermissionRationale {
  public static let screenRecording =
    "Qaptr needs Screen Recording to take an occasional, downscaled screenshot every few minutes. It never records continuously and never uploads a screenshot until you choose to review it."
  public static let accessibilityContext =
    "Optional: Qaptr can also read the frontmost window's title to describe what you were doing more precisely. This is separate from Screen Recording and you can skip it."
}
