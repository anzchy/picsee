import Foundation
import PicseeCore

public struct BookmarkStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [AccessRootRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([AccessRootRecord].self, from: Data(contentsOf: url)) }
        catch { throw FileAccessError.corruptStore }
    }
    public func save(_ roots: [AccessRootRecord]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(roots).write(to: url, options: .atomic)
    }
}
