import Foundation
import PicseeCore

public actor RecentFolderStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [RecentFolder] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([RecentFolder].self, from: Data(contentsOf: url)) }
        catch { throw FileAccessError.corruptStore }
    }
    public func add(_ folder: RecentFolder) throws {
        let old = try load().filter { $0.rootID != folder.rootID && $0.url.standardizedFileURL.path != folder.url.standardizedFileURL.path }
        let recent = Array(([folder] + old).prefix(10))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(recent).write(to: url, options: .atomic)
    }
}
