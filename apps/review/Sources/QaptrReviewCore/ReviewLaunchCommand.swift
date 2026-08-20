/// A command the helper can hand to the review app *at launch time*.
///
/// The helper's status-menu items reach the review app through
/// `DistributedNotificationCenter`, which only works when a listener is
/// already registered. On a cold launch the helper posts its notification as
/// soon as `NSWorkspace.openApplication` reports success, which can happen
/// before the review app has installed its observers, so the command was
/// silently dropped and the app opened on its default surface instead of the
/// requested one.
///
/// Passing the same intent as a launch argument closes that race
/// deterministically: `NSWorkspace.OpenConfiguration.arguments` is delivered
/// only when a new instance is actually spawned, which is exactly the case the
/// notification cannot cover. When the app is already running the arguments are
/// ignored and the notification path still applies, so the two mechanisms are
/// complementary rather than redundant.
public enum ReviewLaunchCommand: String, Equatable, CaseIterable, Sendable {
    case showObservations = "show-observations"
    case openSettings = "open-settings"

    /// The flag the helper uses to pass a command to a newly launched instance.
    public static let argumentFlag = "--qaptr-command"

    /// Renders the launch arguments that request this command.
    public var launchArguments: [String] {
        [Self.argumentFlag, rawValue]
    }

    /// Extracts a command from a process argument list.
    ///
    /// Both `--qaptr-command <value>` and `--qaptr-command=<value>` are
    /// accepted so the contract does not depend on how a caller happens to
    /// serialize the pair. Unknown or missing values yield `nil`, which leaves
    /// the app on its normal default surface rather than failing to launch.
    public static func parse(arguments: [String]) -> ReviewLaunchCommand? {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == argumentFlag {
                guard let value = iterator.next() else { return nil }
                return ReviewLaunchCommand(rawValue: value)
            }
            let inlinePrefix = "\(argumentFlag)="
            if argument.hasPrefix(inlinePrefix) {
                return ReviewLaunchCommand(rawValue: String(argument.dropFirst(inlinePrefix.count)))
            }
        }
        return nil
    }
}
