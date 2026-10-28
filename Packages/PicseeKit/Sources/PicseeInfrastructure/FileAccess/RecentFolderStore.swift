import Foundation
import PicseeCore
import os

public actor RecentFolderStore {
    public private(set) var storeCorrupt = false
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [RecentFolder] {
        do {
            let recent = try read(url)
            storeCorrupt = false
            return recent
        } catch is StoredSchema.UnsupportedVersion {
            storeCorrupt = false
            return []
        } catch {
            storeCorrupt = true
            Logger(subsystem: "io.github.anzchy.picsee", category: "access").error("RecentStore kind=storeCorrupt")
            return (try? read(url.appendingPathExtension("recovered"))) ?? []
        }
    }
    private func read(_ path: URL) throws -> [RecentFolder] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        switch try StoredSchema.decodeItems(Data(contentsOf: path), as: RecentFolder.self) {
        case .current(let recent): return recent
        case .unsupported:
            StoredSchema.logUnsupportedOnce(at: path, category: "access")
            throw StoredSchema.UnsupportedVersion()
        }
    }
    public func add(_ folder: RecentFolder) throws {
        let old = try load().filter { $0.rootID != folder.rootID && $0.url.standardizedFileURL.path != folder.url.standardizedFileURL.path }
        let recent = Array(([folder] + old).prefix(10))
        let destination = storeCorrupt ? url.appendingPathExtension("recovered") : url
        try StoredSchema.refuseUnsupportedWrite(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StoredSchema.encodeItems(recent).write(to: destination, options: .atomic)
    }
}
