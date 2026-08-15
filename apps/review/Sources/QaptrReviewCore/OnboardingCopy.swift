import Foundation

/// Truthful, testable onboarding copy driven from live settings state (R-D7).
///
/// Every string here is a pure function of already-known local state
/// (the configured interval, the chosen provider, and detected displays). It
/// never claims a network call occurred and never invents a value: a
/// provider-dependent line only appears once a provider has actually been
/// chosen, and the interval line always reflects the person's real current
/// setting rather than a hardcoded default.
public enum OnboardingCopy {
    /// The capture-explanation stage's periodic-capture statement, phrased in
    /// the single interval-slider vocabulary (no pause/sparse/frequency
    /// terms). Always reflects the live configured interval.
    public static func periodicCaptureStatement(intervalSeconds: Int) -> String {
        "Qaptr takes one screenshot every \(CaptureIntervalPolicy.humanized(intervalSeconds))."
    }

    /// The capture-explanation stage's boundary statement: what capture does
    /// not do. Stable regardless of settings, since it describes an
    /// invariant rather than a configured value.
    public static let captureBoundaryStatement =
        "It does not record all the time. It does not read your clipboard or keys."

    /// The privacy-consent stage's local-preparation statement (R-P5, R-P8).
    /// States plainly that redaction happens on this Mac before anything
    /// leaves it.
    public static let localPreparationStatement =
        "Qaptr hides text, faces, and barcodes on this Mac before any content is shared with a provider."

    /// The privacy-consent stage's just-in-time consent statement (KTD10,
    /// AE9). Makes explicit that consent is asked again for every session,
    /// not granted once during onboarding.
    public static let justInTimeConsentStatement =
        "Qaptr asks again, every time, before sending anything to a provider. Choosing a provider here does not send anything yet."

    /// The provider-selection stage's transmission statement. Names the
    /// chosen provider when one is set, so the person sees exactly who will
    /// receive analysis requests; falls back to a provider-agnostic
    /// statement when no provider has been chosen, since naming an
    /// unselected provider would misrepresent the current state.
    public static func providerTransmissionStatement(provider: ProviderChoice?) -> String {
        guard let provider else {
            return "Choosing a provider only saves your choice. Qaptr will not send anything until you separately consent to a review."
        }
        return "\(provider.displayName) will only receive redacted content after you separately consent to a review."
    }
}
