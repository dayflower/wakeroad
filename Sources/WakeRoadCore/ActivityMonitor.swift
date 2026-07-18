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

    private let inhibitor: SleepInhibiting
    private let queue: DispatchQueue
    private let log: LogHandler
    private let now: @Sendable () -> Date
    private var state: State = .idle
    private var suspended = false
    private var lastActivity: Date = .distantPast
    private var lastTrigger: String?
    private var timer: DispatchSourceTimer?

    public init(
        timeout: TimeInterval,
        inhibitor: SleepInhibiting,
        queue: DispatchQueue,
        log: @escaping LogHandler = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.timeout = timeout
        self.inhibitor = inhibitor
        self.queue = queue
        self.log = log
        self.now = now
    }

    /// Seeds the monitor with the result of a pre-launch scan (see
    /// `TranscriptScanner.latestWrite(in:)`) and starts in the active state if
    /// the write happened within the timeout window, so sessions already
    /// running before launch are picked up.
    public func bootstrap(latestWrite: TranscriptWrite?) {
        guard let latestWrite, now().timeIntervalSince(latestWrite.date) <= timeout else { return }
        lastActivity = latestWrite.date
        becomeActive(trigger: latestWrite.path)
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
        lastActivity = now()
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
            becomeIdle(reason: "released sleep assertion (paused)")
        } else {
            notifyStatus()
        }
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
            becomeIdle(reason: "released sleep assertion (shutting down)")
        }
    }

    /// Internal (not private) so tests can drive the idle check directly
    /// instead of waiting for the timer.
    func checkIdle() {
        guard state == .active else { return }
        let elapsed = now().timeIntervalSince(lastActivity)
        guard elapsed > timeout else { return }
        becomeIdle(reason: "idle (no writes for \(Int(elapsed))s)")
    }

    private func becomeIdle(reason: String) {
        inhibitor.release()
        state = .idle
        log(reason)
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
