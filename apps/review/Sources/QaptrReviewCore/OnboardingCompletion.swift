import Foundation

/// Pure, explicit inputs describing whether the required local setup
/// decisions needed before onboarding can complete have actually been made
/// (checklist 5.1).
///
/// Every field states a concretely observed fact rather than a default or
/// optimistic assumption (R-D7, KTD10): `false`/`.notDetermined` always means
/// "not yet confirmed", never "probably fine". Callers are expected to derive
/// these from their own live state (e.g. a translated provider-connection
/// status) rather than from this type inventing a value.
public struct OnboardingCompletionInputs: Equatable, Sendable {
    /// Whether at least one display has actually been selected for capture.
    public var hasSelectedDisplay: Bool

    /// The live (not cached) Screen Recording permission status.
    public var screenRecordingStatus: PermissionStatus

    /// Whether a provider has been chosen **and** confirmed usable, not
    /// merely selected. A provider that still needs a key, is mid-check, or
    /// has failed connection is not usable, even though `SettingsPreferences`
    /// already stores a `ProviderChoice` for it.
    public var hasUsableProvider: Bool

    public init(
        hasSelectedDisplay: Bool,
        screenRecordingStatus: PermissionStatus,
        hasUsableProvider: Bool
    ) {
        self.hasSelectedDisplay = hasSelectedDisplay
        self.screenRecordingStatus = screenRecordingStatus
        self.hasUsableProvider = hasUsableProvider
    }
}

/// The reason onboarding completion is currently withheld.
///
/// This is intentionally closed and checked in a stable order, so a caller
/// can show exactly one actionable reason instead of a vague failure.
public enum OnboardingCompletionBlocker: Equatable, Sendable {
    case displayNotSelected
    case screenRecordingNotGranted
    case providerNotUsable
}

/// Pure completion-eligibility policy for checklist 5.1: onboarding may only
/// be marked complete once every required local setup decision has actually
/// been made. It never assumes success and never completes onboarding as a
/// side effect; it only answers whether completion is currently eligible.
public enum OnboardingCompletionPolicy {
    /// The first unmet requirement, in a stable, checked order, or `nil`
    /// when every requirement is met and completion is eligible.
    public static func blocker(for inputs: OnboardingCompletionInputs) -> OnboardingCompletionBlocker? {
        guard inputs.hasSelectedDisplay else { return .displayNotSelected }
        guard inputs.screenRecordingStatus == .granted else { return .screenRecordingNotGranted }
        guard inputs.hasUsableProvider else { return .providerNotUsable }
        return nil
    }

    /// Whether `inputs` satisfies every required local setup decision.
    public static func isEligible(_ inputs: OnboardingCompletionInputs) -> Bool {
        blocker(for: inputs) == nil
    }
}

extension SettingsPreferences {
    /// Marks onboarding complete only when `inputs` satisfies every required
    /// local setup decision (checklist 5.1). Returns whether completion was
    /// recorded; a `false` result means at least one requirement is still
    /// unmet and `onboardingCompleted` is left untouched, so a caller can
    /// never accidentally durably persist an ineligible completion.
    ///
    /// This guard does not itself re-derive `inputs`: it trusts the caller to
    /// supply live, explicitly observed state rather than assumed defaults.
    @discardableResult
    public func completeOnboardingIfEligible(_ inputs: OnboardingCompletionInputs) -> Bool {
        guard OnboardingCompletionPolicy.isEligible(inputs) else { return false }
        onboardingCompleted = true
        return true
    }
}
