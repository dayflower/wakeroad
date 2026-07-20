import Foundation

/// A user-defined watch target as entered in the settings UI and persisted to
/// disk. Holds raw, unvalidated text (`~`-relative paths, comma-separated
/// extensions) so it round-trips through editing and storage; `WatchRoots`
/// resolves it into a `WatchTarget` (tilde-expanded, existence-checked).
public struct CustomWatchTarget: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Raw path as typed, e.g. "~/some/project".
    public var path: String
    /// Raw comma-separated extensions as typed, e.g. "jsonl, log".
    public var extensionsRaw: String

    public init(id: UUID = UUID(), name: String, path: String, extensionsRaw: String) {
        self.id = id
        self.name = name
        self.path = path
        self.extensionsRaw = extensionsRaw
    }

    /// Parsed, normalized extension set (see `WatchTarget.parseExtensions`).
    public var extensions: Set<String> {
        WatchTarget.parseExtensions(extensionsRaw)
    }
}
