import ArgumentParser
import Foundation

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

func log(_ message: String) {
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var roots = [
            home + "/.claude/projects",
            home + "/.codex/sessions",
        ]
        roots += watch.map { NSString(string: $0).expandingTildeInPath }

        let fileManager = FileManager.default
        let watchRoots = roots.filter { root in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: root, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue else {
                log("skipping watch root (not found): \(abbreviatingHome(root))")
                return false
            }
            return true
        }
        guard !watchRoots.isEmpty else {
            throw ValidationError("None of the watch roots exist; nothing to watch.")
        }

        let queue = DispatchQueue(label: "com.github.dayflower.wakeroad")
        let inhibitor = SleepInhibitor(kind: display ? .display : .system)
        let monitor = ActivityMonitor(
            timeout: TimeInterval(timeout),
            inhibitor: inhibitor,
            queue: queue
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
