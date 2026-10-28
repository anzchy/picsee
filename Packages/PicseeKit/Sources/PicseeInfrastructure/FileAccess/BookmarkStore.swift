import Foundation
import PicseeCore

public struct BookmarkStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [AccessRootRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            switch try StoredSchema.decodeItems(Data(contentsOf: url), as: AccessRootRecord.self) {
            case .current(let roots): return roots
            case .unsupported:
                StoredSchema.logUnsupportedOnce(at: url, category: "access")
                return []
            }
        }
        catch { throw FileAccessError.corruptStore }
    }
    public func save(_ roots: [AccessRootRecord]) throws {
        try StoredSchema.refuseUnsupportedWrite(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StoredSchema.encodeItems(roots).write(to: url, options: .atomic)
    }
}
