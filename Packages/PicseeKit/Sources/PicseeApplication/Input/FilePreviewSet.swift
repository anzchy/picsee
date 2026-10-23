import Foundation

/// Members are a frozen input snapshot; later file revisions do not change the path list.
public struct FilePreviewSet: Sendable {
    public let members: [URL]
    public private(set) var index = 0
    public init(files: [URL]) { members = files }
    public var current: URL? { members.indices.contains(index) ? members[index] : nil }
    public func canMove(forward: Bool) -> Bool { members.indices.contains(index + (forward ? 1 : -1)) }
    @discardableResult public mutating func move(forward: Bool) -> URL? {
        guard canMove(forward: forward) else { return nil }
        index += forward ? 1 : -1
        return members[index]
    }
}

extension ViewerSession {
    public func endFilePreviewSet() { filePreviewSet = nil }
    func moveInputFile(forward: Bool) {
        guard let url = filePreviewSet?.move(forward: forward) else { return }
        (host as? any ViewerInputHost)?.openInputImage(url, accessRequest: nil)
    }
}
