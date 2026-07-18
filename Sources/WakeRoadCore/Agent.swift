import Foundation

/// A supported AI coding agent: where it writes transcripts and how to
/// recognize them. Supporting a new agent only requires adding an entry to
/// `known`; watch roots, file filters, and display names all derive from it.
public struct Agent: Sendable {
    public let name: String
    /// Transcript directory relative to the home directory.
    public let homeRelativeRoot: String
    /// Extension (without dot) of transcript files.
    public let fileExtension: String

    public init(name: String, homeRelativeRoot: String, fileExtension: String) {
        self.name = name
        self.homeRelativeRoot = homeRelativeRoot
        self.fileExtension = fileExtension
    }

    /// Absolute transcript directory for the current user.
    public var root: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/" + homeRelativeRoot
    }

    public static let known: [Agent] = [
        Agent(name: "Claude Code", homeRelativeRoot: ".claude/projects", fileExtension: "jsonl"),
        Agent(name: "Codex", homeRelativeRoot: ".codex/sessions", fileExtension: "jsonl"),
    ]

    /// Extensions (without dot) any known agent uses for transcripts.
    /// Also applied to extra watch roots.
    public static var transcriptExtensions: Set<String> {
        Set(known.map(\.fileExtension))
    }

    /// The known agent whose transcript directory contains `path`, if any.
    public static func agent(forTranscriptPath path: String) -> Agent? {
        known.first { path.hasPrefix($0.root + "/") }
    }
}
