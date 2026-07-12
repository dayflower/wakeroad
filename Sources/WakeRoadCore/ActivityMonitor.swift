import Foundation

/// Snapshot of the monitor state, delivered via `ActivityMonitor.onStatusChange`.
public struct MonitorStatus: Sendable {
    public var isActive: Bool
    public var lastActivity: Date?
    public var lastTrigger: String?

    public init(isActive: Bool = false, lastActivity: Date? = nil, lastTrigger: String? = nil) {
        self.isActive = isActive
        self.lastActivity = lastActivity
        self.lastTrigger = lastTrigger
    }
}

/// State machine that turns file-write events into sleep-assertion
/// acquire/release transitions. All methods and property mutations must
/// happen on `queue` (or before the watcher/timer start delivering events);
/// `@unchecked Sendable` so a reference can be handed to that queue.
public final class ActivityMonitor: @unchecked Sendable {
    private enum State {
        case idle
        case active
    }

    /// May be changed while running; takes effect at the next idle check.
    public var timeout: TimeInterval
    /// Called on `queue` whenever the status changes. The receiver is
    /// responsible for hopping to its own actor/queue.
    public var onStatusChange: ((MonitorStatus) -> Void)?

    private let inhibitor: SleepInhibitor
    private let queue: DispatchQueue
    private let log: LogHandler
    private var state: State = .idle
    private var suspended = false
    private var lastActivity: Date = .distantPast
    private var lastTrigger: String?
    private var timer: DispatchSourceTimer?

    public init(
        timeout: TimeInterval,
        inhibitor: SleepInhibitor,
        queue: DispatchQueue,
        log: @escaping LogHandler = { _ in }
    ) {
        self.timeout = timeout
        self.inhibitor = inhibitor
        self.queue = queue
        self.log = log
    }

    /// Scans the watch roots for the most recently modified `.jsonl` file and
    /// starts in the active state if it was written within the timeout window,
    /// so sessions already running before launch are picked up.
    public func bootstrap(roots: [String]) {
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

    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.checkIdle()
        }
        timer.resume()
        self.timer = timer
    }

    public func recordActivity(path: String) {
        guard !suspended else { return }
        lastActivity = Date()
        if state == .idle {
            becomeActive(trigger: path)
        } else {
            lastTrigger = path
            notifyStatus()
        }
    }

    /// Releases the assertion and ignores events until `resume()`.
    /// The watcher keeps running; suspension is purely a monitor-side gate.
    public func suspend() {
        guard !suspended else { return }
        suspended = true
        if state == .active {
            inhibitor.release()
            state = .idle
            log("released sleep assertion (paused)")
        }
        notifyStatus()
    }

    /// Re-enables event handling. The assertion is re-acquired on the next
    /// write event, not immediately.
    public func resume() {
        guard suspended else { return }
        suspended = false
        log("resumed")
        notifyStatus()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        if state == .active {
            inhibitor.release()
            state = .idle
            log("released sleep assertion (shutting down)")
            notifyStatus()
        }
    }

    private func checkIdle() {
        guard state == .active else { return }
        let elapsed = Date().timeIntervalSince(lastActivity)
        guard elapsed > timeout else { return }
        inhibitor.release()
        state = .idle
        log("idle (no writes for \(Int(elapsed))s)")
        notifyStatus()
    }

    private func becomeActive(trigger: String) {
        guard inhibitor.acquire() else { return }
        state = .active
        lastTrigger = trigger
        log("active (trigger: \(abbreviatingHome(trigger)))")
        notifyStatus()
    }

    private func notifyStatus() {
        onStatusChange?(MonitorStatus(
            isActive: state == .active,
            lastActivity: lastActivity == .distantPast ? nil : lastActivity,
            lastTrigger: lastTrigger
        ))
    }
}
