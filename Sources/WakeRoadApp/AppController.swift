import AppKit
import Combine
import Foundation
import WakeRoadCore
import os

private let coreLogger = Logger(subsystem: "com.github.dayflower.wakeroad", category: "core")
private let appLogger = Logger(subsystem: "com.github.dayflower.wakeroad", category: "app")

/// Bridges WakeRoadCore to the SwiftUI menu: wires up the watcher/monitor on
/// launch, republishes monitor status on the main actor, and pushes setting
/// changes back onto the monitor queue.
@MainActor
final class AppController: ObservableObject {
    private enum DefaultsKey {
        static let timeoutMinutes = "idleTimeoutMinutes"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let extraWatchRoots = "extraWatchRoots"
    }

    @Published private(set) var status = MonitorStatus()
    @Published private(set) var isPaused = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var startupError: String?

    @Published var timeoutMinutes: Int {
        didSet {
            guard timeoutMinutes != oldValue else { return }
            UserDefaults.standard.set(timeoutMinutes, forKey: DefaultsKey.timeoutMinutes)
            let seconds = TimeInterval(timeoutMinutes * 60)
            if let monitor {
                queue.async { monitor.timeout = seconds }
            }
        }
    }

    @Published var keepDisplayAwake: Bool {
        didSet {
            guard keepDisplayAwake != oldValue else { return }
            UserDefaults.standard.set(keepDisplayAwake, forKey: DefaultsKey.keepDisplayAwake)
            let kind: SleepInhibitor.Kind = keepDisplayAwake ? .display : .system
            if let inhibitor {
                queue.async { inhibitor.setKind(kind) }
            }
        }
    }

    private let queue = DispatchQueue(label: "com.github.dayflower.wakeroad.app")
    private var inhibitor: SleepInhibitor?
    private var monitor: ActivityMonitor?
    private var watcher: FileActivityWatcher?
    private var terminationObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [DefaultsKey.timeoutMinutes: 5])
        timeoutMinutes = defaults.integer(forKey: DefaultsKey.timeoutMinutes)
        keepDisplayAwake = defaults.bool(forKey: DefaultsKey.keepDisplayAwake)
        launchAtLogin = LaunchAtLogin.isEnabled

        start()

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue; assumeIsolated instead of a Task
            // because the process exits right after the handlers return.
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }
    }

    private func start() {
        // Default (notice) level so events show up in `log show` without
        // enabling info-level persistence.
        let log: LogHandler = { message in
            coreLogger.log("\(message, privacy: .public)")
        }

        let extra = UserDefaults.standard.stringArray(forKey: DefaultsKey.extraWatchRoots) ?? []
        let roots = WatchRoots.resolve(extra: extra, log: log)
        guard !roots.isEmpty else {
            startupError = "No watch roots found (expected ~/.claude/projects or ~/.codex/sessions)"
            return
        }

        let inhibitor = SleepInhibitor(kind: keepDisplayAwake ? .display : .system, log: log)
        let monitor = ActivityMonitor(
            timeout: TimeInterval(timeoutMinutes * 60),
            inhibitor: inhibitor,
            queue: queue,
            log: log
        )
        monitor.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
        let watcher = FileActivityWatcher(roots: roots, queue: queue) { path in
            monitor.recordActivity(path: path)
        }

        monitor.bootstrap(roots: roots)
        monitor.start()
        do {
            try watcher.start()
        } catch {
            queue.sync { monitor.stop() }
            startupError = "Failed to start file watcher: \(error)"
            return
        }

        self.inhibitor = inhibitor
        self.monitor = monitor
        self.watcher = watcher
    }

    func togglePause() {
        guard let monitor else { return }
        isPaused.toggle()
        let paused = isPaused
        queue.async {
            if paused {
                monitor.suspend()
            } else {
                monitor.resume()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLogin = enabled
        } catch {
            appLogger.error(
                "failed to update launch at login: \(error.localizedDescription, privacy: .public)"
            )
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func shutdown() {
        guard let monitor, let watcher else { return }
        queue.sync {
            watcher.stop()
            monitor.stop()
        }
        self.monitor = nil
        self.watcher = nil
    }

    // MARK: - Presentation

    var iconName: String {
        if startupError != nil { return "exclamationmark.triangle" }
        if isPaused { return "pause.circle" }
        return status.isActive ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    var statusLine: String {
        if isPaused { return "⏸ Paused" }
        return status.isActive ? "● Active — inhibiting sleep" : "○ Idle"
    }

    var lastTriggerLine: String? {
        guard let trigger = status.lastTrigger else { return nil }
        var line = "last: " + Self.compactPath(trigger)
        if let date = status.lastActivity {
            line += " (" + Self.timeFormatter.string(from: date) + ")"
        }
        return line
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Shortens long transcript paths for menu display, e.g.
    /// `~/.claude/projects/…/session.jsonl`.
    private static func compactPath(_ path: String) -> String {
        let abbreviated = abbreviatingHome(path)
        let parts = abbreviated.split(separator: "/")
        guard parts.count > 4, let last = parts.last else { return abbreviated }
        return parts.prefix(3).joined(separator: "/") + "/…/" + last
    }
}
