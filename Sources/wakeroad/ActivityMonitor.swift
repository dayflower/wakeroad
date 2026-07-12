import Foundation

/// State machine that turns file-write events into sleep-assertion
/// acquire/release transitions. All methods must be called on `queue`
/// (or before the watcher/timer start delivering events).
final class ActivityMonitor {
    private enum State {
        case idle
        case active
    }

    private let timeout: TimeInterval
    private let inhibitor: SleepInhibitor
    private let queue: DispatchQueue
    private var state: State = .idle
    private var lastActivity: Date = .distantPast
    private var timer: DispatchSourceTimer?

    init(timeout: TimeInterval, inhibitor: SleepInhibitor, queue: DispatchQueue) {
        self.timeout = timeout
        self.inhibitor = inhibitor
        self.queue = queue
    }

    /// Scans the watch roots for the most recently modified `.jsonl` file and
    /// starts in the active state if it was written within the timeout window,
    /// so sessions already running before launch are picked up.
    func bootstrap(roots: [String]) {
        var latest: (path: String, date: Date)?
        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl",
                      let date = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                          .contentModificationDate
                else { continue }
                if latest == nil || date > latest!.date {
                    latest = (fileURL.path, date)
                }
            }
        }

        guard let latest, Date().timeIntervalSince(latest.date) <= timeout else { return }
        lastActivity = latest.date
        becomeActive(trigger: latest.path)
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.checkIdle()
        }
        timer.resume()
        self.timer = timer
    }

    func recordActivity(path: String) {
        lastActivity = Date()
        if state == .idle {
            becomeActive(trigger: path)
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if state == .active {
            inhibitor.release()
            state = .idle
            log("released sleep assertion (shutting down)")
        }
    }

    private func checkIdle() {
        guard state == .active else { return }
        let elapsed = Date().timeIntervalSince(lastActivity)
        guard elapsed > timeout else { return }
        inhibitor.release()
        state = .idle
        log("idle (no writes for \(Int(elapsed))s)")
    }

    private func becomeActive(trigger: String) {
        guard inhibitor.acquire() else { return }
        state = .active
        log("active (trigger: \(abbreviatingHome(trigger)))")
    }
}

/// Replaces the home directory prefix with `~` for readable log output.
func abbreviatingHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path.hasPrefix(home) else { return path }
    return "~" + path.dropFirst(home.count)
}
