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
    private var recovery: URL { url.appendingPathExtension("recovered") }
    /// A file that exists but is not a version 1 store.
    private struct Damaged: Error {}
    private struct Contents: Codable {
        var version = 1
        var favorites: [PersonalImageRef] = []
        var recents: [PersonalImageVisit] = []
    }
    public init(url: URL) { self.url = url }

    /// Newest first.
    public func favorites() throws -> [PersonalImageRef] { try load().favorites }
    /// Newest visit first; equal times keep the later visit first.
    public func recents() throws -> [PersonalImageVisit] { try load().recents }
    public func isFavorite(_ item: ItemID) throws -> Bool { try load().favorites.contains { $0.itemID == item } }

    /// Returns whether the item is a favorite afterwards.
    public func toggleFavorite(_ ref: PersonalImageRef) throws -> Bool {
        var contents = try load()
        let removed = contents.favorites.contains(ref)
        contents.favorites.removeAll { $0 == ref }
        if !removed { contents.favorites.insert(ref, at: 0) }
        try save(contents)
        return !removed
    }
    /// A visit older than every kept one falls outside the bound and is not kept.
    public func recordVisit(_ ref: PersonalImageRef, at date: Date) throws {
        var contents = try load()
        contents.recents.removeAll { $0.ref == ref }
        let index = contents.recents.firstIndex { $0.viewedAt <= date } ?? contents.recents.endIndex
        contents.recents.insert(PersonalImageVisit(ref: ref, viewedAt: date), at: index)
        contents.recents = Array(contents.recents.prefix(Self.recentLimit))
        try save(contents)
    }

    /// A read error other than damage (permissions, I/O) is thrown and nothing is written.
    /// A damaged file is kept as evidence and writes go to the recovery file; once the primary
    /// reads again, the recovery file's writes are merged in and the next write retires it.
    private func load() throws -> Contents {
        let primary: Contents?
        do { primary = try read(url) } catch is Damaged {
            storeCorrupt = true
            Logger(subsystem: "io.github.anzchy.picsee", category: "library").error("PersonalImageStore kind=storeCorrupt")
            return try readRecovery() ?? Contents()
        }
        storeCorrupt = false
        guard let recovered = try readRecovery() else { return primary ?? Contents() }
        return Self.merge(recovered, into: primary ?? Contents())
    }
    /// A damaged recovery file holds nothing usable and is replaced by the next write.
    private func readRecovery() throws -> Contents? {
        do { return try read(recovery) } catch is Damaged { return nil }
    }
    private func read(_ path: URL) throws -> Contents? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        guard let contents = try? JSONDecoder().decode(Contents.self, from: data), contents.version == 1 else { throw Damaged() }
        return contents
    }
    /// Recovery favorites first, then the primary's others; each image keeps its newest visit
    /// (recovery first on a tie), ordered by visit time and bounded.
    private static func merge(_ recovered: Contents, into primary: Contents) -> Contents {
        var merged = recovered
        merged.favorites += primary.favorites.filter { !recovered.favorites.contains($0) }
        var kept: [PersonalImageVisit] = []
        for visit in recovered.recents + primary.recents {
            if let index = kept.firstIndex(where: { $0.ref == visit.ref }) {
                if visit.viewedAt > kept[index].viewedAt { kept[index] = visit }
            } else { kept.append(visit) }
        }
        merged.recents = Array(kept.enumerated()
            .sorted { ($0.element.viewedAt, $1.offset) > ($1.element.viewedAt, $0.offset) }
            .map(\.element).prefix(recentLimit))
        return merged
    }
    private func save(_ contents: Contents) throws {
        let fm = FileManager.default
        let destination = storeCorrupt ? recovery : url
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: destination, options: .atomic)
        // The primary now holds the merged recovery writes.
        if !storeCorrupt, fm.fileExists(atPath: recovery.path) { try fm.removeItem(at: recovery) }
    }
}
