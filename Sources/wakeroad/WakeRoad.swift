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
        abstract: "Prevent macOS sleep while AI coding agents are working.",
        discussion: """
            Watches Claude Code and Codex transcript files (*.jsonl) and holds \
            an IOKit power assertion while they are being written to.
            """,
        subcommands: [Run.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Watch transcript writes and inhibit sleep while agents are active."
    )

    @Option(help: "Seconds without writes before the machine may sleep again.")
    var timeout: Int = 300

    @Flag(help: "Also prevent the display from sleeping.")
    var display = false

    @Option(help: ArgumentHelp(
        "Additional directory tree to watch (repeatable).",
        valueName: "path"
    ))
    var watch: [String] = []

    @Flag(help: "Log every matching file event.")
    var verbose = false

    func validate() throws {
        guard timeout > 0 else {
            throw ValidationError("--timeout must be greater than 0.")
        }
    }

    func run() throws {
        let watchRoots = WatchRoots.resolve(extra: watch, log: log)
        guard !watchRoots.isEmpty else {
            throw ValidationError("None of the watch roots exist; nothing to watch.")
        }

        let onFileEvent: ((String) -> Void)? = verbose
            ? { path in log("write: \(abbreviatingHome(path))") }
            : nil
        let session = WakeRoadSession(configuration: .init(
            roots: watchRoots,
            timeout: TimeInterval(timeout),
            kind: display ? .display : .system,
            log: log,
            onFileEvent: onFileEvent
        ))

        for root in watchRoots {
            log("watching \(abbreviatingHome(root))")
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
