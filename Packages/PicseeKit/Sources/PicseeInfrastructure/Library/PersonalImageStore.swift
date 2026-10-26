import Foundation
import PicseeCore
import os

/// Favorites and recently viewed images, kept apart from Open Recent's folders (recent-folders.json).
/// Stores references only; access always comes from the Access Root's own bookmark.
public actor PersonalImageStore {
    /// Recently viewed keeps the newest visits; favorites are unbounded.
    public static let recentLimit = 50
    public private(set) var storeCorrupt = false
    private let url: URL
    private struct Contents: Codable {
        var version = 1
        var favorites: [PersonalImageRef] = []
        var recents: [PersonalImageVisit] = []
    }
    public init(url: URL) { self.url = url }

    /// Newest first.
    public func favorites() throws -> [PersonalImageRef] { load().favorites }
    /// Newest visit first; equal times keep the later visit first.
    public func recents() throws -> [PersonalImageVisit] { load().recents }
    public func isFavorite(_ item: ItemID) throws -> Bool { load().favorites.contains { $0.itemID == item } }

    /// Returns whether the item is a favorite afterwards.
    public func toggleFavorite(_ ref: PersonalImageRef) throws -> Bool {
        var contents = load()
        let removed = contents.favorites.contains(ref)
        contents.favorites.removeAll { $0 == ref }
        if !removed { contents.favorites.insert(ref, at: 0) }
        try save(contents)
        return !removed
    }
    /// A visit older than every kept one falls outside the bound and is not kept.
    public func recordVisit(_ ref: PersonalImageRef, at date: Date) throws {
        var contents = load()
        contents.recents.removeAll { $0.ref == ref }
        let index = contents.recents.firstIndex { $0.viewedAt <= date } ?? contents.recents.endIndex
        contents.recents.insert(PersonalImageVisit(ref: ref, viewedAt: date), at: index)
        contents.recents = Array(contents.recents.prefix(Self.recentLimit))
        try save(contents)
    }

    private func load() -> Contents {
        do {
            let contents = try read(url)
            storeCorrupt = false
            return contents
        } catch {
            // Keep the damaged file as evidence; later writes go to the recovery file.
            storeCorrupt = true
            Logger(subsystem: "io.github.anzchy.picsee", category: "library").error("PersonalImageStore kind=storeCorrupt")
            return (try? read(url.appendingPathExtension("recovered"))) ?? Contents()
        }
    }
    private func read(_ path: URL) throws -> Contents {
        guard FileManager.default.fileExists(atPath: path.path) else { return Contents() }
        let contents = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: path))
        guard contents.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return contents
    }
    private func save(_ contents: Contents) throws {
        let destination = storeCorrupt ? url.appendingPathExtension("recovered") : url
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: destination, options: .atomic)
    }
}
