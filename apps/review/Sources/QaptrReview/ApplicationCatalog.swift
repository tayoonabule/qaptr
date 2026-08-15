import AppKit
import Foundation

/// A small, local catalog of apps the person can choose for a never-capture rule.
/// It reads bundle metadata only. It does not launch or inspect the applications.
struct InstalledApplication: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum ApplicationCatalog {
    static func load() -> [InstalledApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var applications: [String: InstalledApplication] = [:]
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in children where url.pathExtension == "app" {
                add(url, to: &applications)
            }
        }

        for running in NSWorkspace.shared.runningApplications {
            if let url = running.bundleURL, url.pathExtension == "app" {
                add(url, to: &applications)
            }
        }

        return applications.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func add(_ url: URL, to applications: inout [String: InstalledApplication]) {
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let id = bundle?.bundleIdentifier ?? url.path
        applications[id] = InstalledApplication(id: id, name: name, url: url)
    }
}
