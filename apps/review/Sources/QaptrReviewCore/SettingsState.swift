import Foundation

/// The identity of a supported analysis provider.
///
/// Qaptr never invents a fifth provider here: the four names mirror the
/// release-gating set decided by the plan (R-PR4). This type is presentation
/// vocabulary only; it does not select or invoke an adapter.
public enum ProviderChoice: String, CaseIterable, Equatable, Sendable {
    case openRouter = "openrouter"
    case claudeCLI = "claude-cli"
    case codexCLI = "codex"
    case jcodeCLI = "jcode"

    public var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .claudeCLI: "Claude CLI"
        case .codexCLI: "Codex CLI"
        case .jcodeCLI: "Jcode CLI"
        }
    }
}

/// The capture cadence profile shown in settings.
///
/// Settings only ever displays the current mode; starting or stopping
/// detailed capture is the Observation Sheet's "Qaptr in more detail" action
/// (U18), not a settings toggle, so a person cannot silently leave detailed
/// capture running from a control they forgot about.
public enum CaptureCadence: Equatable, Sendable {
    case sparse
    case detailed(endsAtMillis: Int64)

    public var isDetailed: Bool {
        if case .detailed = self { return true }
        return false
    }
}

/// The person's chosen cache lifetime for ephemeral capture bundles (R-P2).
public enum CacheLifetime: String, CaseIterable, Equatable, Sendable {
    case sixHours
    case oneDay
    case threeDays
    case sevenDays

    public var seconds: UInt64 {
        switch self {
        case .sixHours: 6 * 3_600
        case .oneDay: 24 * 3_600
        case .threeDays: 3 * 24 * 3_600
        case .sevenDays: 7 * 24 * 3_600
        }
    }

    public var displayName: String {
        switch self {
        case .sixHours: "6 hours"
        case .oneDay: "1 day"
        case .threeDays: "3 days"
        case .sevenDays: "7 days"
        }
    }
}

/// Read-only permission state shown in settings and onboarding.
///
/// This mirrors `qaptr_domain::ports::PermissionState` exactly so a status
/// glance can never silently invent a fourth state.
public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case unavailable

    public init(bridgeCode: Int32) {
        switch bridgeCode {
        case 1: self = .granted
        case 0: self = .denied
        case -1: self = .notDetermined
        default: self = .unavailable
        }
    }

    public var label: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Denied"
        case .notDetermined: "Not yet requested"
        case .unavailable: "Unavailable"
        }
    }
}

/// The full, small settings surface (R-D6): cadence, displays, cache
/// duration, provider, and privacy/permission status, and nothing else.
public struct SettingsState: Equatable, Sendable {
    public var cadence: CaptureCadence
    public var selectedDisplayIDs: Set<String>
    public var availableDisplayIDs: [String]
    public var cacheLifetime: CacheLifetime
    public var provider: ProviderChoice?
    public var screenRecordingStatus: PermissionStatus
    public var accessibilityContextStatus: PermissionStatus
    public var loginItemEnabled: Bool
    public var excludedApplications: [String]
    public var excludedWindowTitles: [String]

    public init(
        cadence: CaptureCadence,
        selectedDisplayIDs: Set<String>,
        availableDisplayIDs: [String],
        cacheLifetime: CacheLifetime,
        provider: ProviderChoice?,
        screenRecordingStatus: PermissionStatus,
        accessibilityContextStatus: PermissionStatus,
        loginItemEnabled: Bool,
        excludedApplications: [String],
        excludedWindowTitles: [String]
    ) {
        self.cadence = cadence
        self.selectedDisplayIDs = selectedDisplayIDs
        self.availableDisplayIDs = availableDisplayIDs
        self.cacheLifetime = cacheLifetime
        self.provider = provider
        self.screenRecordingStatus = screenRecordingStatus
        self.accessibilityContextStatus = accessibilityContextStatus
        self.loginItemEnabled = loginItemEnabled
        self.excludedApplications = excludedApplications
        self.excludedWindowTitles = excludedWindowTitles
    }

    /// A conservative default state used before any preference is loaded.
    public static let placeholder = SettingsState(
        cadence: .sparse,
        selectedDisplayIDs: [],
        availableDisplayIDs: [],
        cacheLifetime: .oneDay,
        provider: nil,
        screenRecordingStatus: .notDetermined,
        accessibilityContextStatus: .notDetermined,
        loginItemEnabled: false,
        excludedApplications: [],
        excludedWindowTitles: []
    )
}

/// Validates and normalizes one exclusion entry before it is persisted.
///
/// Rejects empty and whitespace-only entries so settings cannot silently
/// store a rule that would never match anything.
public enum ExclusionEntry {
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
