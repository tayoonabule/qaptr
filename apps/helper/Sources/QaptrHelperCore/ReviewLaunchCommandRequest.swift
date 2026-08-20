import Foundation

/// The helper's side of the review app's launch-command contract.
///
/// The status-menu commands normally reach a running review app through
/// `DistributedNotificationCenter`. That mechanism has no delivery guarantee
/// for a process that does not yet exist: on a cold launch the helper posts as
/// soon as `NSWorkspace.openApplication` reports success, which can precede the
/// review app registering its observers, so the command is dropped and the app
/// opens on its default surface instead of the requested one.
///
/// Launch arguments close that gap, because macOS delivers them only when a new
/// instance is actually spawned — precisely the case the notification misses.
/// The raw values here must stay in sync with `ReviewLaunchCommand` in
/// `QaptrReviewCore`; the two apps ship as separate SwiftPM packages, so this is
/// duplicated deliberately rather than shared through a common dependency, and
/// `HelperReviewCommandContractTests` pins the wire format on this side.
public enum ReviewLaunchCommandRequest: String, Equatable, CaseIterable, Sendable {
    case showObservations = "show-observations"
    case openSettings = "open-settings"

    /// The flag understood by the review app's argument parser.
    public static let argumentFlag = "--qaptr-command"

    /// The arguments to hand to `NSWorkspace.OpenConfiguration`.
    public var launchArguments: [String] {
        [Self.argumentFlag, rawValue]
    }

    /// Maps the helper's boolean menu intent onto the shared command.
    public static func forSettingsRequest(_ requestSettings: Bool) -> ReviewLaunchCommandRequest {
        requestSettings ? .openSettings : .showObservations
    }
}
