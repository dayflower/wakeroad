import Foundation
import WakeRoadCore

/// Maps monitor status to the strings shown in the menu bar, keeping
/// presentation concerns out of `AppController`.
enum StatusPresentation {
    static func iconName(status: MonitorStatus, hasStartupError: Bool) -> String {
        if hasStartupError { return "exclamationmark.triangle" }
        if status.isSuspended { return "pause.circle" }
        return status.isActive ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    static func statusLine(for status: MonitorStatus) -> String {
        if status.isSuspended { return "⏸ Paused" }
        return status.isActive ? "● Active — inhibiting sleep" : "○ Idle"
    }

    static func lastTriggerLine(for status: MonitorStatus, targets: [WatchTarget]) -> String? {
        guard let trigger = status.lastTrigger else { return nil }
        var line = "last: " + targetName(for: trigger, in: targets)
        if let date = status.lastActivity {
            line += " (" + timeFormatter.string(from: date) + ")"
        }
        return line
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Maps a write path to the name of the watch target that contains it;
    /// falls back to the containing directory name when no target matches.
    private static func targetName(for path: String, in targets: [WatchTarget]) -> String {
        if let target = WatchTarget.matching(path: path, in: targets) { return target.name }
        let directory = (abbreviatingHome(path) as NSString).deletingLastPathComponent
        return directory.isEmpty ? path : directory
    }
}
