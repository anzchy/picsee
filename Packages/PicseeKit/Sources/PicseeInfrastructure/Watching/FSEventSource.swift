import CoreServices
import Foundation
import PicseeCore

/// FSEvents adapter. The stream conformance arrives with WI-6; the flag mapping is pure and tested directly.
public struct FSEventSource: Sendable {
    public static let latency: Double = 0.05
    public init() {}
    static let dropFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged)
    static func hint(path: String, flags: FSEventStreamEventFlags) -> FolderChangeHint {
        flags & dropFlags != 0 ? .mustRescan : .changed(URL(fileURLWithPath: path))
    }
}
