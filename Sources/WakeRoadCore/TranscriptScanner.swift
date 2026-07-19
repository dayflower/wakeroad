import Foundation

/// A transcript file write observed during a bootstrap scan.
public struct TranscriptWrite: Sendable {
    public let path: String
    public let date: Date

    public init(path: String, date: Date) {
        self.path = path
        self.date = date
    }
}

/// Filesystem scan used at startup to pick up sessions that were already
/// running before launch. Kept out of `ActivityMonitor` so the monitor stays
/// a pure state machine.
public enum TranscriptScanner {
    /// Returns the most recently modified transcript file (matching
    /// `extensions`) under `roots`, or nil if none exists.
    public static func latestWrite(
        in roots: [String],
        extensions: Set<String> = Agent.transcriptExtensions
    ) -> TranscriptWrite? {
        var latest: TranscriptWrite?
        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }
            for case let fileURL as URL in enumerator {
                guard extensions.contains(fileURL.pathExtension),
                    let date = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate
                else { continue }
                if latest == nil || date > latest!.date {
                    latest = TranscriptWrite(path: fileURL.path, date: date)
                }
            }
        }
        return latest
    }
}
