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

        let queue = DispatchQueue(label: "com.github.dayflower.wakeroad")
        let inhibitor = SleepInhibitor(kind: display ? .display : .system, log: log)
        let monitor = ActivityMonitor(
            timeout: TimeInterval(timeout),
            inhibitor: inhibitor,
            queue: queue,
            log: log
        )

        let verbose = self.verbose
        let watcher = FileActivityWatcher(roots: watchRoots, queue: queue) { path in
            if verbose {
                log("write: \(abbreviatingHome(path))")
            }
            monitor.recordActivity(path: path)
        }

        for root in watchRoots {
            log("watching \(abbreviatingHome(root))")
        }
        log("idle timeout: \(timeout)s, assertion: \(display ? "system+display" : "system") sleep")

        monitor.bootstrap(roots: watchRoots)
        monitor.start()
        try watcher.start()

        let shutdown = {
            queue.sync {
                watcher.stop()
                monitor.stop()
            }
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

        withExtendedLifetime((watcher, monitor, sigintSource, sigtermSource)) {
            dispatchMain()
        }
    }
}
