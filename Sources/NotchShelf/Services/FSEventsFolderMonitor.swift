import CoreServices
import Foundation
import OSLog

public enum FolderMonitorError: Error {
    case streamCreationFailed
    case streamStartFailed
}

public final class FSEventsFolderMonitor: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable () -> Void

    private final class ContextBox {
        weak var monitor: FSEventsFolderMonitor?

        init(monitor: FSEventsFolderMonitor) {
            self.monitor = monitor
        }
    }

    private let queue = DispatchQueue(label: "com.capturearc.capture-folder-monitor")
    private let queueIdentityKey = DispatchSpecificKey<UInt8>()
    private let lifecycleLock = NSLock()
    private let handlerLock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CaptureArc",
        category: "CaptureMonitor"
    )
    private var stream: FSEventStreamRef?
    private var changeHandler: ChangeHandler?

    public init() {
        queue.setSpecific(key: queueIdentityKey, value: 1)
    }

    deinit {
        stop()
    }

    public func start(
        monitoring folderURL: URL,
        latency: CFTimeInterval = 0.35,
        onChange: @escaping ChangeHandler
    ) throws {
        try start(
            monitoring: [folderURL],
            latency: latency,
            onChange: onChange
        )
    }

    public func start(
        monitoring folderURLs: [URL],
        latency: CFTimeInterval = 0.35,
        onChange: @escaping ChangeHandler
    ) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        stopLocked()
        setChangeHandler(onChange)

        let paths = Array(Set(folderURLs.map {
            $0.standardizedFileURL.path
        })).sorted()
        guard !paths.isEmpty else {
            setChangeHandler(nil)
            throw FolderMonitorError.streamCreationFailed
        }

        let contextBox = ContextBox(monitor: self)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(contextBox).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<ContextBox>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<ContextBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, contextInfo, eventCount, _, _, _ in
                guard let contextInfo else { return }
                let contextBox = Unmanaged<ContextBox>
                    .fromOpaque(contextInfo)
                    .takeUnretainedValue()
                contextBox.monitor?.handleEvents(count: eventCount)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            setChangeHandler(nil)
            throw FolderMonitorError.streamCreationFailed
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)

        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            setChangeHandler(nil)
            throw FolderMonitorError.streamStartFailed
        }

        logger.info(
            "Capture folder monitoring started for \(paths.count, privacy: .public) source(s)"
        )
    }

    public func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        setChangeHandler(nil)
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        if DispatchQueue.getSpecific(key: queueIdentityKey) == nil {
            queue.sync {}
        }
        FSEventStreamRelease(stream)
        self.stream = nil
        logger.info("Capture folder monitoring stopped")
    }

    private func handleEvents(count: Int) {
        logger.debug("Filesystem changes received: \(count, privacy: .public)")
        handlerLock.lock()
        let handler = changeHandler
        handlerLock.unlock()
        handler?()
    }

    private func setChangeHandler(_ handler: ChangeHandler?) {
        handlerLock.lock()
        changeHandler = handler
        handlerLock.unlock()
    }
}
