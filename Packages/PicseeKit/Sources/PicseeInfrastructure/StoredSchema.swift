import Foundation
import os

enum StoredSchema {
    static let current = 1
    struct UnsupportedVersion: Error {}
    enum Items<Value> {
        case current([Value])
        case unsupported
    }
    private struct Header: Decodable { let schemaVersion: Int? }
    private struct Envelope<Value: Codable>: Codable {
        let schemaVersion: Int
        let items: [Value]
    }

    static func decodeItems<Value: Codable>(_ data: Data, as type: Value.Type) throws -> Items<Value> {
        let decoder = JSONDecoder()
        if let header = try? decoder.decode(Header.self, from: data), let version = header.schemaVersion {
            if version != current { return .unsupported }
            return .current(try decoder.decode(Envelope<Value>.self, from: data).items)
        }
        return .current(try decoder.decode([Value].self, from: data))
    }

    static func encodeItems<Value: Codable>(_ items: [Value]) throws -> Data {
        try JSONEncoder().encode(Envelope(schemaVersion: current, items: items))
    }

    /// Recheck the destination immediately before each atomic replacement. Callers serialize their
    /// own writes; a separate process changing the file between this check and rename remains a race.
    static func refuseUnsupportedWrite(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        if let header = try? JSONDecoder().decode(Header.self, from: data),
           let version = header.schemaVersion, version != current { throw UnsupportedVersion() }
    }

    private static let logState = LogState()
    static func logUnsupportedOnce(at url: URL, category: String) {
        let key = category + ":" + url.standardizedFileURL.path
        let first = logState.lock.withLock { logState.paths.insert(key).inserted }
        if first {
            Logger(subsystem: "io.github.anzchy.picsee", category: category)
                .error("StoredSchema kind=unsupportedVersion")
        }
    }

    private final class LogState: @unchecked Sendable {
        let lock = NSLock()
        var paths: Set<String> = []
    }
}
