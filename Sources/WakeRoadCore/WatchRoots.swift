import Foundation

/// Resolves the directory trees to watch for transcript writes into
/// `WatchTarget`s (absolute root + per-root extensions), combining the built-in
/// agents with caller-supplied custom targets or CLI specs.
public enum WatchRoots {
    /// Built-in agent transcript locations as watch targets.
    public static func defaultTargets() -> [WatchTarget] {
        Agent.known.map {
            WatchTarget(name: $0.name, root: $0.root, extensions: [$0.fileExtension])
        }
    }

    /// Resolves the GUI's `custom` entries into watch targets: each is
    /// tilde-expanded and canonicalized, dropped if its directory does not exist
    /// or it has no extensions, and named from its user-entered name (falling
    /// back to the directory name when blank). The built-in agents are not added
    /// here; they are seeded into the custom list on first launch (see
    /// `CustomWatchTargetStore`), so they appear as editable entries.
    public static func resolve(custom: [CustomWatchTarget], log: LogHandler = { _ in })
        -> [WatchTarget]
    {
        custom.compactMap { entry in
            let extensions = entry.extensions
            guard !extensions.isEmpty else {
                log("skipping watch target (no extensions): \(entry.path)")
                return nil
            }
            return makeTarget(
                name: entry.name, rawPath: entry.path, extensions: extensions, log: log)
        }
    }

    /// Combines the default targets with `--watch` specs (CLI). Each spec is
    /// `path` (default extensions) or `path=ext,ext` (see `parseWatchSpec`).
    public static func resolve(cliWatchSpecs specs: [String], log: LogHandler = { _ in })
        -> [WatchTarget]
    {
        resolvedDefaultTargets(log: log) + resolveSpecs(specs, log: log)
    }

    /// The full CLI target list: optionally the built-in agents, then the config
    /// file's targets, then `--watch` specs. `includeDefaults` is true only when
    /// no config file is in play — a config file is authoritative, so it opts
    /// out of the implicit built-in agents (list them explicitly to keep them).
    /// `--watch` specs are always applied, since they are an explicit request.
    public static func resolveCLI(
        configTargets: [CustomWatchTarget],
        watchSpecs: [String],
        includeDefaults: Bool,
        log: LogHandler = { _ in }
    ) -> [WatchTarget] {
        let defaults = includeDefaults ? resolvedDefaultTargets(log: log) : []
        return defaults
            + resolve(custom: configTargets, log: log)
            + resolveSpecs(watchSpecs, log: log)
    }

    private static func resolveSpecs(_ specs: [String], log: LogHandler) -> [WatchTarget] {
        specs.compactMap { spec in
            let (rawPath, extensions) = parseWatchSpec(spec)
            return makeTarget(name: "", rawPath: rawPath, extensions: extensions, log: log)
        }
    }

    private static func resolvedDefaultTargets(log: LogHandler) -> [WatchTarget] {
        defaultTargets().compactMap {
            makeTarget(name: $0.name, rawPath: $0.root, extensions: $0.extensions, log: log)
        }
    }

    /// Tilde-expands and existence-checks `rawPath`, then canonicalizes it so
    /// the root matches the symlink-resolved paths FSEvents reports (e.g. under
    /// /var or /tmp). Returns nil for a non-existent directory. A blank name
    /// falls back to the resolved directory's last component.
    private static func makeTarget(
        name: String, rawPath: String, extensions: Set<String>, log: LogHandler
    ) -> WatchTarget? {
        let expanded = expand(rawPath)
        guard isExistingDirectory(expanded, log: log) else { return nil }
        let root = canonicalize(expanded)
        let resolvedName =
            name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (root as NSString).lastPathComponent : name
        return WatchTarget(name: resolvedName, root: root, extensions: extensions)
    }

    /// Splits a `--watch` spec into a path and extension set. The extension
    /// suffix is only recognized when the text after the last `=` looks like an
    /// extension list (non-empty, contains no path separator), so paths that
    /// themselves contain `=` are treated as plain paths. Absent a valid suffix,
    /// the default transcript extensions apply.
    static func parseWatchSpec(_ spec: String) -> (path: String, extensions: Set<String>) {
        guard let separator = spec.range(of: "=", options: .backwards) else {
            return (spec, Agent.transcriptExtensions)
        }
        let rightSide = String(spec[separator.upperBound...])
        let extensions = WatchTarget.parseExtensions(rightSide)
        guard !extensions.isEmpty, !rightSide.contains("/") else {
            return (spec, Agent.transcriptExtensions)
        }
        return (String(spec[..<separator.lowerBound]), extensions)
    }

    private static func expand(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    /// Resolves symlinks to the canonical path FSEvents reports. Falls back to
    /// the input if the canonical path cannot be determined.
    private static func canonicalize(_ path: String) -> String {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
            ?? path
    }

    private static func isExistingDirectory(_ path: String, log: LogHandler = { _ in }) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            log("skipping watch root (not found): \(abbreviatingHome(path))")
            return false
        }
        return true
    }
}

/// Replaces the home directory prefix with `~` for readable log output.
public func abbreviatingHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path.hasPrefix(home) else { return path }
    return "~" + path.dropFirst(home.count)
}
