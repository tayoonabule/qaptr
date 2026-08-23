import Foundation

/// Resolves filesystem locations used before the helper application starts.
public enum HelperRuntimePaths {
    /// Returns an explicit non-empty lock override, or the canonical per-user
    /// Application Support path. `URL(fileURLWithPath: "")` resolves to the
    /// current working directory, so the empty environment value must be
    /// rejected before constructing a URL.
    public static func lockURL(
        environment: [String: String],
        homeDirectory: URL
    ) -> URL {
        if let override = environment["QAPTR_HELPER_LOCK_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return homeDirectory
            .appendingPathComponent("Library/Application Support/Qaptr", isDirectory: true)
            .appendingPathComponent("helper.lock")
    }

    /// Resolves the exact review app that encloses the packaged login-item
    /// helper. This intentionally does not ask LaunchServices for an arbitrary
    /// bundle-ID match, which could reopen an obsolete Qaptr copy after an
    /// upgrade.
    public static func reviewApplicationURL(
        environment: [String: String],
        helperBundleURL: URL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> URL? {
        if let override = environment["QAPTR_REVIEW_APP_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            return fileExists(url.path) ? url : nil
        }

        let enclosingReview = helperBundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard ["Qaptr.app", "QaptrReview.app"].contains(enclosingReview.lastPathComponent),
              fileExists(enclosingReview.path) else {
            return nil
        }
        return enclosingReview
    }
}
