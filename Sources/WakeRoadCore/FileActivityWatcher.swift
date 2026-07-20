import CoreServices
import Foundation

/// Watches the roots of `targets` with a single FSEventStream and reports
/// writes to files whose extension matches the target containing them. Events
/// are delivered on the queue passed to `init`.
public final class FileActivityWatcher {
    /// FSEvents coalescing latency: writes within this window arrive as one batch.
    private static let eventLatency: CFTimeInterval = 1.5

    public enum WatcherError: Error, CustomStringConvertible {
        case streamCreationFailed
        case streamStartFailed

        public var description: String {
            switch self {
            case .streamCreationFailed: return "failed to create FSEventStream"
            case .streamStartFailed: return "failed to start FSEventStream"
            }
        }
    }

    private let targets: [WatchTarget]
    private let roots: [String]
    private let queue: DispatchQueue
    private let onEvent: (String) -> Void
    private var stream: FSEventStreamRef?

    public init(
        targets: [WatchTarget],
        queue: DispatchQueue,
        onEvent: @escaping (String) -> Void
    ) {
        self.targets = targets
        self.roots = targets.map(\.root)
        self.queue = queue
        self.onEvent = onEvent
    }

    /// Whether `path` is a write we should report: its extension matches the
    /// extension set of the target whose root contains it.
    private func matches(_ path: String) -> Bool {
        guard let target = WatchTarget.matching(path: path, in: targets) else { return false }
        return target.extensions.contains((path as NSString).pathExtension.lowercased())
    }

    public func start() throws {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes makes eventPaths a CFArray of CFString.
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            for index in 0..<numEvents {
                guard let path = paths[index] as? String, watcher.matches(path)
                else { continue }
                watcher.onEvent(path)
            }
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                roots as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.eventLatency,
                flags
            )
        else {
            throw WatcherError.streamCreationFailed
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw WatcherError.streamStartFailed
        }
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
