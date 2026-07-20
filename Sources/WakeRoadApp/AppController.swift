import AppKit
import Combine
import Foundation
import WakeRoadCore
import os

private let coreLogger = Logger(subsystem: "com.github.dayflower.wakeroad", category: "core")
private let appLogger = Logger(subsystem: "com.github.dayflower.wakeroad", category: "app")

/// Bridges WakeRoadCore to the SwiftUI menu: starts a `WakeRoadSession` on
/// launch, republishes monitor status on the main actor, and forwards setting
/// changes to the session.
@MainActor
final class AppController: ObservableObject {
    private enum DefaultsKey {
        static let timeoutMinutes = "idleTimeoutMinutes"
        static let keepDisplayAwake = "keepDisplayAwake"
    }

    @Published private(set) var status = MonitorStatus()
    @Published private(set) var launchAtLogin = false
    @Published private(set) var startupError: String?
    /// User-defined watch targets; edited by the settings window.
    @Published private(set) var customWatchTargets: [CustomWatchTarget]
    /// Currently active resolved targets, used for status-line name lookup.
    @Published private(set) var resolvedTargets: [WatchTarget] = []

    @Published var timeoutMinutes: Int {
        didSet {
            guard timeoutMinutes != oldValue else { return }
            UserDefaults.standard.set(timeoutMinutes, forKey: DefaultsKey.timeoutMinutes)
            session?.setTimeout(timeoutSeconds)
        }
    }

    @Published var keepDisplayAwake: Bool {
        didSet {
            guard keepDisplayAwake != oldValue else { return }
            UserDefaults.standard.set(keepDisplayAwake, forKey: DefaultsKey.keepDisplayAwake)
            session?.setKind(keepDisplayAwake ? .display : .system)
        }
    }

    var isPaused: Bool { status.isSuspended }

    private var session: WakeRoadSession?
    private var terminationObserver: NSObjectProtocol?

    private var timeoutSeconds: TimeInterval { TimeInterval(timeoutMinutes * 60) }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [DefaultsKey.timeoutMinutes: 5])
        timeoutMinutes = defaults.integer(forKey: DefaultsKey.timeoutMinutes)
        keepDisplayAwake = defaults.bool(forKey: DefaultsKey.keepDisplayAwake)
        customWatchTargets = CustomWatchTargetStore.load()
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

    // Default (notice) level so events show up in `log show` without
    // enabling info-level persistence.
    private let log: LogHandler = { message in
        coreLogger.log("\(message, privacy: .public)")
    }

    private func noWatchRootsError() -> String {
        let expected = Agent.known.map { "~/" + $0.homeRelativeRoot }.joined(separator: " or ")
        return "No watch roots found (expected \(expected))"
    }

    private func start() {
        resolvedTargets = WatchRoots.resolve(custom: customWatchTargets, log: log)
        guard !resolvedTargets.isEmpty else {
            startupError = noWatchRootsError()
            return
        }

        let session = WakeRoadSession(
            configuration: .init(
                targets: resolvedTargets,
                timeout: timeoutSeconds,
                kind: keepDisplayAwake ? .display : .system,
                log: log
            ))
        session.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
        do {
            try session.start()
        } catch {
            startupError = "Failed to start file watcher: \(error)"
            return
        }
        self.session = session
    }

    /// Persists edited custom targets and reconfigures the running watcher so
    /// changes take effect without a restart.
    func updateCustomWatchTargets(_ targets: [CustomWatchTarget]) {
        guard targets != customWatchTargets else { return }
        customWatchTargets = targets
        CustomWatchTargetStore.save(targets)
        reconfigureWatchTargets()
    }

    private func reconfigureWatchTargets() {
        resolvedTargets = WatchRoots.resolve(custom: customWatchTargets, log: log)
        guard !resolvedTargets.isEmpty else {
            startupError = noWatchRootsError()
            return
        }
        // Start a session lazily if launch failed with no roots; otherwise swap
        // the watcher in place, preserving any held sleep assertion.
        guard let session else {
            start()
            return
        }
        do {
            try session.reconfigure(targets: resolvedTargets)
            startupError = nil
        } catch {
            startupError = "Failed to update file watcher: \(error)"
        }
    }

    func togglePause() {
        guard let session else { return }
        if status.isSuspended {
            session.resume()
        } else {
            session.suspend()
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
        session?.stop()
        session = nil
    }
}
