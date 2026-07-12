import Foundation

/// Resolves the directory trees to watch for transcript writes.
public enum WatchRoots {
    /// Default transcript locations of Claude Code and Codex.
    public static func defaultRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home + "/.claude/projects",
            home + "/.codex/sessions",
        ]
    }

    /// Combines the default roots with `extra` (tilde-expanded) and drops
    /// entries that are not existing directories, logging each skip.
    public static func resolve(extra: [String] = [], log: LogHandler = { _ in }) -> [String] {
        let roots = defaultRoots() + extra.map { NSString(string: $0).expandingTildeInPath }
        let fileManager = FileManager.default
        return roots.filter { root in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: root, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue else {
                log("skipping watch root (not found): \(abbreviatingHome(root))")
                return false
            }
            return true
        }
    }
}

/// Replaces the home directory prefix with `~` for readable log output.
public func abbreviatingHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path.hasPrefix(home) else { return path }
    return "~" + path.dropFirst(home.count)
}
