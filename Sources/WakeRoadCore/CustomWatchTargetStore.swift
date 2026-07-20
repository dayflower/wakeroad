import Foundation

/// Loads and saves the user's custom watch targets in `UserDefaults` as a
/// JSON-encoded blob, migrating the legacy `extraWatchRoots` string array on
/// first load. Takes a `UserDefaults` so tests can inject a scratch suite.
public enum CustomWatchTargetStore {
    static let key = "customWatchTargets"
    static let legacyExtraWatchRootsKey = "extraWatchRoots"

    public static func load(from defaults: UserDefaults = .standard) -> [CustomWatchTarget] {
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([CustomWatchTarget].self, from: data)
        {
            return decoded
        }
        // First launch: seed the built-in agents so they appear as editable
        // entries, plus any migrated legacy `extraWatchRoots`. Persisting the
        // result means later launches take the decode path above, so user edits
        // and deletions (including removing a seeded agent) stick.
        let seeded = seedDefaults() + legacyMigratedTargets(defaults: defaults)
        save(seeded, to: defaults)
        defaults.removeObject(forKey: legacyExtraWatchRootsKey)
        return seeded
    }

    public static func save(_ targets: [CustomWatchTarget], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults.set(data, forKey: key)
    }

    /// Built-in agents as editable seed entries, using tilde paths for
    /// readability (resolved later by `WatchRoots`).
    private static func seedDefaults() -> [CustomWatchTarget] {
        Agent.known.map { agent in
            CustomWatchTarget(
                name: agent.name,
                path: "~/" + agent.homeRelativeRoot,
                extensionsRaw: agent.fileExtension
            )
        }
    }

    /// Converts a pre-existing `extraWatchRoots` array into custom targets.
    /// Legacy roots were always filtered by `Agent.transcriptExtensions`, so
    /// migrated entries carry those extensions to preserve behavior exactly.
    private static func legacyMigratedTargets(defaults: UserDefaults) -> [CustomWatchTarget] {
        guard let legacy = defaults.stringArray(forKey: legacyExtraWatchRootsKey), !legacy.isEmpty
        else { return [] }

        let extensionsRaw = Agent.transcriptExtensions.sorted().joined(separator: ", ")
        return legacy.map { path in
            CustomWatchTarget(
                name: (path as NSString).lastPathComponent,
                path: path,
                extensionsRaw: extensionsRaw
            )
        }
    }
}
