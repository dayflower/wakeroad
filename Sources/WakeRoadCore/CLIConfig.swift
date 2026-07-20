import Foundation

/// The CLI's optional JSON config file: a list of watch targets read from disk
/// instead of (or in addition to) repeated `--watch` flags. Kept separate from
/// the GUI's `UserDefaults` storage — the two do not share state.
///
/// Example:
/// ```json
/// {
///   "watchTargets": [
///     { "name": "Notes", "path": "~/notes", "extensions": ["md", "txt"] }
///   ]
/// }
/// ```
public struct CLIConfig: Codable, Equatable {
    public struct Target: Codable, Equatable {
        /// Optional display name; falls back to the directory name when absent.
        public var name: String?
        /// Directory tree to watch (`~` allowed).
        public var path: String
        /// File extensions (without dot) whose writes count as activity.
        public var extensions: [String]

        public init(name: String? = nil, path: String, extensions: [String]) {
            self.name = name
            self.path = path
            self.extensions = extensions
        }
    }

    public var watchTargets: [Target]

    public init(watchTargets: [Target]) {
        self.watchTargets = watchTargets
    }

    /// The file's targets as `CustomWatchTarget`s so they flow through the same
    /// `WatchRoots` resolution and extension normalization as the GUI's targets.
    public var customWatchTargets: [CustomWatchTarget] {
        watchTargets.map {
            CustomWatchTarget(
                name: $0.name ?? "",
                path: $0.path,
                extensionsRaw: $0.extensions.joined(separator: ",")
            )
        }
    }

    public enum LoadError: Error, CustomStringConvertible {
        case notFound(String)
        case malformed(String, underlying: Error)

        public var description: String {
            switch self {
            case .notFound(let path):
                return "config file not found: \(path)"
            case .malformed(let path, let underlying):
                return "could not parse config file \(path): \(underlying)"
            }
        }
    }

    /// Loads and decodes the config at `path` (tilde-expanded). Returns nil when
    /// the file is absent and `required` is false; throws `LoadError.notFound`
    /// when it is absent and required, or `LoadError.malformed` on a decode
    /// failure.
    public static func load(path: String, required: Bool) throws -> CLIConfig? {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            if required { throw LoadError.notFound(path) }
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: expanded))
            return try JSONDecoder().decode(CLIConfig.self, from: data)
        } catch {
            throw LoadError.malformed(path, underlying: error)
        }
    }
}
