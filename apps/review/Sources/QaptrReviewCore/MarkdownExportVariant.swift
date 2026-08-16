import Foundation

/// A concise, user-facing failure reason for a document action (workflow
/// generation or export). This is never a raw Rust error or a stack trace:
/// callers already reduce the underlying `ReviewBridgeError` to one plain
/// sentence before constructing this.
public struct DocumentActionError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// The four canonical Markdown export variants, matching
/// `qaptr_workflow::MarkdownExportVariant` and the wire strings accepted by
/// `qaptr_workflow_export_json`'s bounded request.
public enum MarkdownExportVariant: String, CaseIterable, Equatable, Sendable {
    case automation
    case handoff
    case onboarding
    case sop

    /// The exact lowercase string this bridge's JSON v1 request expects.
    public var wireValue: String { rawValue }

    /// A short, human-facing name for export pickers.
    public var displayName: String {
        switch self {
        case .automation: "Automation"
        case .handoff: "Handoff"
        case .onboarding: "Onboarding"
        case .sop: "Standard Operating Procedure"
        }
    }

    /// The suggested filename for a save panel, always ending in `.md`.
    public func suggestedFileName(workflowTitle: String) -> String {
        let base = workflowTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let safeBase = base.isEmpty ? "workflow" : base
        return "\(safeBase)-\(rawValue).md"
    }
}
