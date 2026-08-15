import Foundation

/// One step in the truthful, non-nagging onboarding sequence (R-D7).
///
/// Onboarding only ever advances forward and only ever runs once per
/// installation, tracked by `SettingsPreferences.onboardingCompleted`. It
/// never re-appears after completion, and it never requests a provider before
/// the final consent step, matching KTD10's just-in-time consent boundary.
public enum OnboardingStage: Int, CaseIterable, Equatable, Sendable {
    case permissions = 0
    case displays = 1
    case captureExplanation = 2
    case providerSelection = 3
    case privacyConsent = 4

    public var next: OnboardingStage? {
        OnboardingStage(rawValue: rawValue + 1)
    }

    public var title: String {
        switch self {
        case .permissions: "Screen Recording"
        case .displays: "Displays"
        case .captureExplanation: "How capture works"
        case .providerSelection: "Choose a provider"
        case .privacyConsent: "Privacy"
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
