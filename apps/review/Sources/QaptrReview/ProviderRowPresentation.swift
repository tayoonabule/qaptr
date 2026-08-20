import Foundation
import QaptrReviewCore

/// The bounded, truthful presentation for one provider row: a status label,
/// a short concise reason, and at most one next action. This is a pure
/// function of already-known state (settings provider choice, the
/// Keychain-backed OpenRouter connection state, and the bounded path-only CLI
/// readiness snapshot), so rendering never triggers a provider process or
/// claims a readiness check occurred when one has not.
struct ProviderRowPresentation: Equatable, Sendable {
    /// A short, uppercase-friendly status word or phrase.
    let statusLabel: String
    /// A single concise reason shown only when the row is not simply "ready
    /// and selected". `nil` means no explanation is needed.
    let reason: String?
    /// The one next action a person can take, if any. `nil` when the row is
    /// either already usable or has no in-app recovery action available.
    let nextAction: ProviderRowAction?

    init(statusLabel: String, reason: String?, nextAction: ProviderRowAction?) {
        self.statusLabel = statusLabel
        self.reason = reason
        self.nextAction = nextAction
    }
}

/// The bounded set of next actions a provider row may offer. Each row shows
/// at most one of these, never more.
enum ProviderRowAction: Equatable, Sendable {
    case addKey
    case changeKey
}

/// Derives one truthful provider-row presentation from local state only.
///
/// OpenRouter's presentation is derived from the Keychain-backed
/// `ProviderConnectionState` (already network-verified when `.connected`).
/// The three CLI providers are derived from the bounded, path-only
/// `ProviderReadiness` snapshot: a detected executable is explicitly never
/// claimed usable, matching `qaptr_provider_readiness_json`'s own invariant.
enum ProviderRowPresenter {
    static func present(
        provider: ProviderChoice,
        connection: ProviderConnectionState,
        cliReadiness: ProviderReadiness?
    ) -> ProviderRowPresentation {
        switch provider {
        case .openRouter:
            return presentOpenRouter(connection: connection)
        case .claudeCLI, .codexCLI, .jcodeCLI:
            return connection == .notConnected
                ? presentCliInstallation(readiness: cliReadiness)
                : presentCliConnection(connection)
        }
    }

    private static func presentOpenRouter(connection: ProviderConnectionState) -> ProviderRowPresentation {
        switch connection.kind {
        case .notConnected:
            return ProviderRowPresentation(statusLabel: "Not connected", reason: nil, nextAction: nil)
        case .needsKey:
            return ProviderRowPresentation(
                statusLabel: "Add a key",
                reason: "OpenRouter needs a key before Qaptr can use it.",
                nextAction: .addKey
            )
        case .configured:
            return ProviderRowPresentation(
                statusLabel: "Key saved",
                reason: "A key is saved but not yet verified with OpenRouter.",
                nextAction: .changeKey
            )
        case .checking:
            return ProviderRowPresentation(statusLabel: "Checking", reason: nil, nextAction: .changeKey)
        case .connected:
            return ProviderRowPresentation(statusLabel: "Connected", reason: nil, nextAction: .changeKey)
        case .failed(let failure):
            return ProviderRowPresentation(statusLabel: "Try again", reason: failure.message, nextAction: .changeKey)
        }
    }

    private static func presentCliConnection(
        _ connection: ProviderConnectionState
    ) -> ProviderRowPresentation {
        switch connection.kind {
        case .checking:
            return ProviderRowPresentation(statusLabel: "Checking", reason: nil, nextAction: nil)
        case .connected:
            return ProviderRowPresentation(statusLabel: "Connected", reason: nil, nextAction: nil)
        case .failed(let failure):
            return ProviderRowPresentation(statusLabel: "Error", reason: failure.message, nextAction: nil)
        case .notConnected, .needsKey, .configured:
            return ProviderRowPresentation(statusLabel: "Installed", reason: nil, nextAction: nil)
        }
    }

    private static func presentCliInstallation(readiness: ProviderReadiness?) -> ProviderRowPresentation {
        guard let readiness else {
            return ProviderRowPresentation(
                statusLabel: "Not checked",
                reason: "Qaptr could not check this CLI yet.",
                nextAction: nil
            )
        }
        switch readiness.state {
        case .detected:
            // Detection only proves an executable exists at a known path. It
            // never proves authentication, so this row must never claim the
            // provider is ready to use.
            return ProviderRowPresentation(
                statusLabel: "Installed",
                reason: nil,
                nextAction: nil
            )
        case .notInstalled:
            return ProviderRowPresentation(
                statusLabel: "Not installed",
                reason: "Install this CLI on your Mac to use it.",
                nextAction: nil
            )
        case .unavailable:
            return ProviderRowPresentation(
                statusLabel: "Unavailable",
                reason: "Qaptr could not check for this CLI right now.",
                nextAction: nil
            )
        }
    }
}
