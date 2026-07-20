import ArgumentParser
import Foundation
import WakeRoadCore

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

@Sendable func log(_ message: String) {
    print("[\(logDateFormatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

@main
struct WakeRoad: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wakeroad",
        abstract: "Keep macOS awake while files are being written under directories you watch.",
        discussion: """
            Holds an IOKit power assertion while matching files are written under \
            the watched directory trees. With no config file it watches Claude \
            Code and Codex transcripts (*.jsonl) by default; a config file \
            (--config, or ~/.config/wakeroad/config.json) replaces those \
            defaults, and --watch adds trees on top.
            """,
        subcommands: [Run.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Watch file writes under the given directories and inhibit sleep while active."
    )

    @Option(help: "Seconds without writes before the machine may sleep again.")
    var timeout: Int = 300

    @Flag(help: "Also prevent the display from sleeping.")
    var display = false

    @Option(
        help: ArgumentHelp(
            """
            Additional directory tree to watch (repeatable). Append \
            "=ext,ext" to watch specific extensions, e.g. ~/proj=md,log; \
            without it, transcript extensions (jsonl) are used.
            """,
            valueName: "path[=ext,ext]"
        ))
    var watch: [String] = []

    @Option(
        help: ArgumentHelp(
            """
            JSON config file listing watch targets, added to the built-in \
            agents and any --watch flags. Defaults to \
            ~/.config/wakeroad/config.json when present.
            """,
            valueName: "path"
        ))
    var config: String?

    @Flag(help: "Log every matching file event.")
    var verbose = false

    func validate() throws {
        guard timeout > 0 else {
            throw ValidationError("--timeout must be greater than 0.")
        }
    }

    /// Default config path, used only when `--config` is not given (its absence
    /// is then not an error).
    private static let defaultConfigPath = "~/.config/wakeroad/config.json"

    func run() throws {
        let fileConfig: CLIConfig?
        do {
            let path = config ?? Self.defaultConfigPath
            fileConfig = try CLIConfig.load(path: path, required: config != nil)
        } catch {
            throw ValidationError("\(error)")
        }

        // A config file is authoritative: when one is present the built-in
        // agents are no longer added by default (list them in the file to keep
        // watching them). With no config file, they are the sensible default.
        let targets = WatchRoots.resolveCLI(
            configTargets: fileConfig?.customWatchTargets ?? [],
            watchSpecs: watch,
            includeDefaults: fileConfig == nil,
            log: log
        )
        guard !targets.isEmpty else {
            throw ValidationError("None of the watch roots exist; nothing to watch.")
        }

        let onFileEvent: ((String) -> Void)? =
            verbose
            ? { path in log("write: \(abbreviatingHome(path))") }
            : nil
        let session = WakeRoadSession(
            configuration: .init(
                targets: targets,
                timeout: TimeInterval(timeout),
                kind: display ? .display : .system,
                log: log,
                onFileEvent: onFileEvent
            ))

        for target in targets {
            let extensions = target.extensions.sorted().joined(separator: ", ")
            log("watching \(abbreviatingHome(target.root)) [\(extensions)]")
        }
        log("idle timeout: \(timeout)s, assertion: \(display ? "system+display" : "system") sleep")

        try session.start()

        let shutdown = {
            session.stop()
            WakeRoad.exit()
        }
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler(handler: shutdown)
        sigintSource.resume()
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler(handler: shutdown)
        sigtermSource.resume()

        withExtendedLifetime((session, sigintSource, sigtermSource)) {
            dispatchMain()
        }
    }
}
