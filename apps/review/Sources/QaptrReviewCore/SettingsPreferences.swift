import Foundation

/// A minimal, injectable key-value store so preferences logic is unit
/// testable without touching real `UserDefaults`.
public protocol PreferenceStore: Sendable {
    func string(forKey key: String) -> String?
    func stringArray(forKey key: String) -> [String]?
    func bool(forKey key: String) -> Bool
    func set(_ value: String?, forKey key: String)
    func set(_ value: [String], forKey key: String)
    func set(_ value: Bool, forKey key: String)
}

extension UserDefaults: PreferenceStore {
    public func set(_ value: String?, forKey key: String) {
        setValue(value, forKey: key)
    }

    public func set(_ value: [String], forKey key: String) {
        setValue(value, forKey: key)
    }
}

/// An in-memory preference store used by tests and previews.
public final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var strings: [String: String] = [:]
    private var arrays: [String: [String]] = [:]
    private var bools: [String: Bool] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return strings[key]
    }

    public func stringArray(forKey key: String) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        return arrays[key]
    }

    public func bool(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return bools[key] ?? false
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        strings[key] = value
    }

    public func set(_ value: [String], forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        arrays[key] = value
    }

    public func set(_ value: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        bools[key] = value
    }
}

/// Persists the small settings surface's user-editable preferences.
///
/// This intentionally persists only what a person actually configures here:
/// cache lifetime, provider choice, an optional explicit model override, and
/// the two exclusion lists. Permission and login-item status are always read
/// live through the bridge rather than cached, so settings can never show a
/// stale granted state. The person's requested login-item choice is retained
/// separately so a future app upgrade cannot silently undo an explicit opt-out.
public struct SettingsPreferences: Sendable {
    private let store: PreferenceStore

    private enum Key {
        static let cacheLifetime = "com.qaptr.review.settings.cacheLifetime"
        static let provider = "com.qaptr.review.settings.provider"
        static let explicitModelOverride = "com.qaptr.review.settings.explicitModelOverride"
        static let excludedApplications = "com.qaptr.review.settings.excludedApplications"
        static let excludedWindowTitles = "com.qaptr.review.settings.excludedWindowTitles"
        static let onboardingCompleted = "com.qaptr.review.onboarding.completed"
        static let loginItemEnabledPreference = "com.qaptr.review.settings.loginItemEnabledPreference"
    }

    public init(store: PreferenceStore) {
        self.store = store
    }

    public var cacheLifetime: CacheLifetime {
        get {
            store.string(forKey: Key.cacheLifetime).flatMap(CacheLifetime.init(rawValue:)) ?? .oneDay
        }
        nonmutating set {
            store.set(newValue.rawValue, forKey: Key.cacheLifetime)
        }
    }

    public var provider: ProviderChoice? {
        get {
            store.string(forKey: Key.provider).flatMap(ProviderChoice.init(rawValue:))
        }
        nonmutating set {
            store.set(newValue?.rawValue, forKey: Key.provider)
        }
    }

    /// The person's requested model identifier, if any.
    ///
    /// This is intentionally independent of `provider` and of policy/default
    /// resolution. The value is non-secret configuration only: validation and
    /// resolution happen later, immediately before a consented request.
    public var explicitModelOverride: String? {
        get { store.string(forKey: Key.explicitModelOverride) }
        nonmutating set {
            let normalized = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            store.set(normalized?.isEmpty == false ? normalized : nil, forKey: Key.explicitModelOverride)
        }
    }

    public var excludedApplications: [String] {
        get { store.stringArray(forKey: Key.excludedApplications) ?? [] }
        nonmutating set { store.set(newValue, forKey: Key.excludedApplications) }
    }

    public var excludedWindowTitles: [String] {
        get { store.stringArray(forKey: Key.excludedWindowTitles) ?? [] }
        nonmutating set { store.set(newValue, forKey: Key.excludedWindowTitles) }
    }

    /// Whether onboarding has already completed. Used to avoid nagging.
    public var onboardingCompleted: Bool {
        get { store.bool(forKey: Key.onboardingCompleted) }
        nonmutating set { store.set(newValue, forKey: Key.onboardingCompleted) }
    }

    /// The person's explicit start-at-login choice, when they have made one.
    /// `nil` preserves the legacy first-upgrade behavior for existing installs.
    public var loginItemEnabledPreference: Bool? {
        get {
            switch store.string(forKey: Key.loginItemEnabledPreference) {
            case "enabled": true
            case "disabled": false
            default: nil
            }
        }
        nonmutating set {
            store.set(newValue.map { $0 ? "enabled" : "disabled" }, forKey: Key.loginItemEnabledPreference)
        }
    }

    /// Adds a normalized entry to the excluded-application list.
    public func addExcludedApplication(_ raw: String) {
        guard let entry = ExclusionEntry.normalized(raw) else { return }
        var current = excludedApplications
        guard !current.contains(entry) else { return }
        current.append(entry)
        excludedApplications = current
    }

    /// Adds a normalized entry to the excluded-window-title list.
    public func addExcludedWindowTitle(_ raw: String) {
        guard let entry = ExclusionEntry.normalized(raw) else { return }
        var current = excludedWindowTitles
        guard !current.contains(entry) else { return }
        current.append(entry)
        excludedWindowTitles = current
    }

    /// Removes an entry from the excluded-application list.
    public func removeExcludedApplication(_ entry: String) {
        excludedApplications = excludedApplications.filter { $0 != entry }
    }

    /// Removes an entry from the excluded-window-title list.
    public func removeExcludedWindowTitle(_ entry: String) {
        excludedWindowTitles = excludedWindowTitles.filter { $0 != entry }
    }
}
