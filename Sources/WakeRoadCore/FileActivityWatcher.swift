import CoreServices
import Foundation

/// Watches directory trees with a single FSEventStream and reports writes to
/// files matching `fileExtensions`. Events are delivered on the queue passed
/// to `init`.
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

    private let roots: [String]
    private let fileExtensions: Set<String>
    private let queue: DispatchQueue
    private let onEvent: (String) -> Void
    private var stream: FSEventStreamRef?

    public init(
        roots: [String],
        fileExtensions: Set<String> = Agent.transcriptExtensions,
        queue: DispatchQueue,
        onEvent: @escaping (String) -> Void
    ) {
        self.roots = roots
        self.fileExtensions = fileExtensions
        self.queue = queue
        self.onEvent = onEvent
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
                guard let path = paths[index] as? String,
                    watcher.fileExtensions.contains((path as NSString).pathExtension)
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
