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
        static let extraWatchRoots = "extraWatchRoots"
    }

    @Published private(set) var status = MonitorStatus()
    @Published private(set) var launchAtLogin = false
    @Published private(set) var startupError: String?

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
            let expected = Agent.known.map { "~/" + $0.homeRelativeRoot }.joined(separator: " or ")
            startupError = "No watch roots found (expected \(expected))"
            return
        }

        let session = WakeRoadSession(
            configuration: .init(
                roots: roots,
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
