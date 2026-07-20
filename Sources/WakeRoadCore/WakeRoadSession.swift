import Foundation

/// Owns the queue, inhibitor, monitor, and watcher as a single unit so entry
/// points (CLI and GUI) only create a session and call its methods. The
/// "all monitor/inhibitor access happens on the session queue" threading rule
/// is enforced here instead of leaking to callers.
public final class WakeRoadSession: @unchecked Sendable {
    public struct Configuration {
        /// Watch targets: roots plus per-root extensions (see `WatchRoots`).
        public var targets: [WatchTarget]
        /// Seconds without writes before the assertion is released.
        public var timeout: TimeInterval
        /// Which kind of sleep to inhibit while active.
        public var kind: SleepInhibitor.Kind
        public var log: LogHandler
        /// Called on the session queue for every matching file write, before
        /// the monitor processes it. Used by the CLI's verbose logging.
        public var onFileEvent: ((String) -> Void)?

        public init(
            targets: [WatchTarget],
            timeout: TimeInterval,
            kind: SleepInhibitor.Kind,
            log: @escaping LogHandler = { _ in },
            onFileEvent: ((String) -> Void)? = nil
        ) {
            self.targets = targets
            self.timeout = timeout
            self.kind = kind
            self.log = log
            self.onFileEvent = onFileEvent
        }
    }

    /// Called on the session queue whenever the monitor status changes.
    /// Set before `start()`; the receiver hops to its own actor/queue.
    public var onStatusChange: ((MonitorStatus) -> Void)? {
        get { monitor.onStatusChange }
        set { monitor.onStatusChange = newValue }
    }

    private var targets: [WatchTarget]
    private let queue: DispatchQueue
    private let inhibitor: SleepInhibitor
    private let monitor: ActivityMonitor
    private let onFileEvent: ((String) -> Void)?
    private var watcher: FileActivityWatcher

    public init(configuration: Configuration) {
        let queue = DispatchQueue(label: "com.github.dayflower.wakeroad.session")
        let inhibitor = SleepInhibitor(kind: configuration.kind, log: configuration.log)
        let monitor = ActivityMonitor(
            timeout: configuration.timeout,
            inhibitor: inhibitor,
            queue: queue,
            log: configuration.log
        )
        let onFileEvent = configuration.onFileEvent
        self.targets = configuration.targets
        self.queue = queue
        self.inhibitor = inhibitor
        self.monitor = monitor
        self.onFileEvent = onFileEvent
        self.watcher = FileActivityWatcher(targets: configuration.targets, queue: queue) { path in
            onFileEvent?(path)
            monitor.recordActivity(path: path)
        }
    }

    /// Seeds the monitor from a pre-launch transcript scan, starts the idle
    /// timer, and starts the file watcher. If the watcher fails to start the
    /// monitor is rolled back and the error is rethrown.
    public func start() throws {
        monitor.bootstrap(latestWrite: TranscriptScanner.latestWrite(in: targets))
        monitor.start()
        do {
            try watcher.start()
        } catch {
            queue.sync { monitor.stop() }
            throw error
        }
    }

    /// Replaces the set of watch targets at runtime by swapping in a fresh
    /// watcher, leaving the monitor and inhibitor untouched so a currently held
    /// sleep assertion and the active/idle state survive. A target added while
    /// something is already writing to it is only picked up on its next write;
    /// the reconfiguration does not re-scan for pre-existing activity.
    public func reconfigure(targets: [WatchTarget]) throws {
        let onFileEvent = self.onFileEvent
        let monitor = self.monitor
        let newWatcher = FileActivityWatcher(targets: targets, queue: queue) { path in
            onFileEvent?(path)
            monitor.recordActivity(path: path)
        }
        try newWatcher.start()
        queue.sync { self.watcher.stop() }
        self.watcher = newWatcher
        self.targets = targets
    }

    /// Stops the watcher and monitor, releasing any held assertion.
    /// Synchronous: safe to call right before process exit.
    public func stop() {
        queue.sync {
            watcher.stop()
            monitor.stop()
        }
    }

    /// Changes the idle timeout; takes effect at the next idle check.
    public func setTimeout(_ seconds: TimeInterval) {
        queue.async { self.monitor.timeout = seconds }
    }

    /// Switches the assertion kind, re-acquiring it if currently held.
    public func setKind(_ kind: SleepInhibitor.Kind) {
        queue.async { self.inhibitor.setKind(kind) }
    }

    /// Releases the assertion and ignores events until `resume()`.
    public func suspend() {
        queue.async { self.monitor.suspend() }
    }

    /// Re-enables event handling; the assertion is re-acquired on the next write.
    public func resume() {
        queue.async { self.monitor.resume() }
    }
}
