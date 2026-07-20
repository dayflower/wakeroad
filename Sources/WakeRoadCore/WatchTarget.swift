import Foundation

/// A resolved directory tree to watch: an absolute, existing root plus the set
/// of file extensions whose writes count as activity there. Built-in agents and
/// user-defined custom targets both reduce to this uniform shape downstream, so
/// the watcher, scanner, and display lookups only deal with `WatchTarget`.
public struct WatchTarget: Sendable, Equatable {
    /// Human-readable name shown in the status line.
    public let name: String
    /// Absolute path to an existing directory.
    public let root: String
    /// Extensions (without dot, lower-cased) that trigger activity under `root`.
    public let extensions: Set<String>

    public init(name: String, root: String, extensions: Set<String>) {
        self.name = name
        self.root = root
        self.extensions = extensions
    }

    /// The target whose root contains `path`, if any. When roots are nested the
    /// most specific (longest) root wins, so a custom target inside a built-in
    /// root resolves to the custom target.
    public static func matching(path: String, in targets: [WatchTarget]) -> WatchTarget? {
        targets
            .sorted { $0.root.count > $1.root.count }
            .first { path.hasPrefix($0.root + "/") }
    }

    /// Parses a comma-separated extension string into a normalized set:
    /// trimmed, lower-cased, de-duplicated, with empty entries dropped. Shared
    /// by the settings UI (`CustomWatchTarget`) and the CLI's `--watch` syntax
    /// so both accept extensions the same way.
    public static func parseExtensions(_ raw: String) -> Set<String> {
        Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
    }
}
