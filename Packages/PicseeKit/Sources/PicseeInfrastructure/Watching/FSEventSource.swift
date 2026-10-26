import CoreServices
import Foundation
import PicseeCore

/// FSEvents adapter: file-level events since now, delivered on the stream's own serial queue until `stop()` returns.
public struct FSEventSource: FolderEventSource {
    public static let latency: Double = 0.05
    public init() {}
    static let dropFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged)
    static func hint(path: String, flags: FSEventStreamEventFlags) -> FolderChangeHint {
        flags & dropFlags != 0 ? .mustRescan : .changed(URL(fileURLWithPath: path))
    }

    /// `ref` and `stopped` are touched only on `queue`; the FSEvents context retains this object until the stream is released.
    private final class Stream: FolderEventStream, @unchecked Sendable {
        let queue = DispatchQueue(label: "picsee.fsevents"), key = DispatchSpecificKey<Void>()
        let onHints: @Sendable ([FolderChangeHint]) -> Void
        var ref: FSEventStreamRef?, stopped = false
        init(_ onHints: @escaping @Sendable ([FolderChangeHint]) -> Void) {
            self.onHints = onHints; queue.setSpecific(key: key, value: ())
        }
        /// Off the queue, tears down synchronously behind any in-flight callback; inside a callback, later callbacks are dropped.
        func stop() {
            if DispatchQueue.getSpecific(key: key) != nil { stopped = true; queue.async { self.teardown() } }
            else { queue.sync { stopped = true; teardown() } }
        }
        private func teardown() {
            guard let ref else { return }
            self.ref = nil
            FSEventStreamStop(ref); FSEventStreamInvalidate(ref); FSEventStreamRelease(ref)
        }
    }

    public func start(watching url: URL, onHints: @escaping @Sendable ([FolderChangeHint]) -> Void) -> any FolderEventStream {
        let stream = Stream(onHints)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(stream).toOpaque(),
            retain: { info in info.map { _ = Unmanaged<Stream>.fromOpaque($0).retain(); return $0 } },
            release: { info in info.map { Unmanaged<Stream>.fromOpaque($0).release() } }, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let stream = Unmanaged<Stream>.fromOpaque(info).takeUnretainedValue()
            guard !stream.stopped else { return }
            let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            stream.onHints((0..<count).map { FSEventSource.hint(path: String(cString: cPaths[$0]), flags: flags[$0]) })
        }
        // A stream that failed to create is never started; its stop() finds no ref.
        guard let ref = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return stream }
        stream.queue.sync { stream.ref = ref; FSEventStreamSetDispatchQueue(ref, stream.queue); FSEventStreamStart(ref) }
        return stream
    }
}

/// Production WatchScheduling: monotonic uptime milliseconds; actions run on a global queue.
public struct DispatchWatchScheduler: WatchScheduling {
    private struct Item: WatchCancellable, @unchecked Sendable { let item: DispatchWorkItem; func cancel() { item.cancel() } }
    public init() {}
    public var nowMilliseconds: Int { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }
    public func schedule(afterMilliseconds: Int, _ action: @escaping @Sendable () -> Void) -> any WatchCancellable {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(afterMilliseconds), execute: item)
        return Item(item: item)
    }
}
