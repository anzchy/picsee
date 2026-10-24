import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PicseeCore
import SQLite3
import UniformTypeIdentifiers

/// Re-creatable small renders only. Actor isolation serializes SQLite and payload operations;
/// the actor never inherits MainActor from its caller.
public actor ThumbnailDiskCache: ThumbnailCaching {
    public static let maximumSourceBytes = 32 * 1024 * 1024
    public static let maximumPayloadBytes = 8 * 1024 * 1024
    public static let maximumPixelEdge = 1024
    private static let cacheVersion = 2
    private static let encoderVersion = 2
    private let directory: URL
    private let afterPayloadWrite: (@Sendable () throws -> Void)?
    private var didSweepOrphans = false

    public init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Picsee/Thumbnails", isDirectory: true)) {
        self.directory = directory
        self.afterPayloadWrite = nil
    }

    init(directory: URL, afterPayloadWrite: @escaping @Sendable () throws -> Void) {
        self.directory = directory
        self.afterPayloadWrite = afterPayloadWrite
    }

    public func prepare(_ request: ImageDecodeRequest) async throws -> ThumbnailCacheTicket? {
        try Task.checkCancellation()
        guard let render = request.renderKey,
              render.itemID.stableEncoding.hasPrefix("id1:root:"),
              render.policy == .orientedSDR, render.frameIndex == 0,
              render.maximumPixelSize == request.maximumPixelSize,
              render.isPreview == request.isPreview,
              request.maximumPixelSize > 0,
              request.maximumPixelSize <= Self.maximumPixelEdge,
              request.fileURL.isFileURL else { return nil }
        let digest = try? fingerprint(request.fileURL, expected: render.revision)
        try Task.checkCancellation()
        guard let digest, let key = DurableThumbnailKey(renderKey: render, sourceSHA256: digest,
                                                       encoderVersion: Self.encoderVersion) else { return nil }
        return ThumbnailCacheTicket(request: request, key: key, sourceSHA256: digest)
    }

    public func load(_ ticket: ThumbnailCacheTicket) async throws -> DecodedImage? {
        try Task.checkCancellation()
        guard let render = ticket.request.renderKey,
              let expectedKey = DurableThumbnailKey(renderKey: render, sourceSHA256: ticket.sourceSHA256,
                                                    encoderVersion: Self.encoderVersion),
              expectedKey == ticket.key,
              try fingerprint(ticket.request.fileURL, expected: render.revision) == ticket.sourceSHA256 else { return nil }
        sweepOrphansIfNeeded()
        guard let row = readRow(ticket), row.byteCount > 0, row.byteCount <= Self.maximumPayloadBytes,
              row.payloadPath == ticket.key.filename + ".png" else {
            removeDamagedEntry(ticket)
            return nil
        }
        let payload = directory.appendingPathComponent(row.payloadPath)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: payload.path)[.size] as? NSNumber)?.intValue,
              size == row.byteCount, size <= Self.maximumPayloadBytes,
              let data = try? Data(contentsOf: payload), data.count == row.byteCount,
              digest(data) == row.payloadSHA256,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              (CGImageSourceGetType(source) as String?) == UTType.png.identifier,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0,
              image.width <= ticket.request.maximumPixelSize,
              image.height <= ticket.request.maximumPixelSize else {
            removeDamagedEntry(ticket)
            return nil
        }
        try Task.checkCancellation()
        guard try fingerprint(ticket.request.fileURL, expected: render.revision) == ticket.sourceSHA256 else { return nil }
        try Task.checkCancellation()
        return DecodedImage(image: image,
            sourcePixelSize: CGSize(width: row.sourceWidth, height: row.sourceHeight),
            revision: render.revision, itemID: render.itemID)
    }

    public func store(_ image: DecodedImage, for ticket: ThumbnailCacheTicket) async throws {
        try Task.checkCancellation()
        guard let render = ticket.request.renderKey,
              let expectedKey = DurableThumbnailKey(renderKey: render, sourceSHA256: ticket.sourceSHA256,
                                                    encoderVersion: Self.encoderVersion),
              expectedKey == ticket.key,
              image.image.width > 0, image.image.height > 0,
              image.image.bitsPerComponent == 8,
              image.image.width <= ticket.request.maximumPixelSize,
              image.image.height <= ticket.request.maximumPixelSize,
              image.sourcePixelSize.width > 0, image.sourcePixelSize.height > 0,
              image.sourcePixelSize.width.isFinite, image.sourcePixelSize.height.isFinite,
              image.sourcePixelSize.width <= Double(Int32.max),
              image.sourcePixelSize.height <= Double(Int32.max) else { return }
        guard image.itemID == render.itemID, image.revision == render.revision else {
            throw ImageLoadError(.sourceChanged, itemID: render.itemID, revision: image.revision)
        }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image.image, nil) // No original EXIF/GPS metadata.
        guard CGImageDestinationFinalize(destination) else { return }
        let payload = bytes as Data
        guard payload.count > 0, payload.count <= Self.maximumPayloadBytes else { return }
        // Re-read after decode and encoding. Metadata alone cannot prove same-inode writes.
        guard try sourceMatches(ticket, render: render) else {
            throw ImageLoadError(.sourceChanged, itemID: render.itemID, revision: render.revision)
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = ticket.key.filename + ".png"
        let url = directory.appendingPathComponent(path)
        try payload.write(to: url, options: .atomic)
        try afterPayloadWrite?()
        // Catch a source mutation during payload publication before indexing the bytes.
        let unchanged: Bool
        do { unchanged = try sourceMatches(ticket, render: render) }
        catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        guard unchanged else {
            try? FileManager.default.removeItem(at: url)
            throw ImageLoadError(.sourceChanged, itemID: render.itemID, revision: render.revision)
        }
        try Task.checkCancellation()
        try writeRow(ticket, payloadPath: path, payloadBytes: payload.count,
                     payloadSHA256: digest(payload), sourceWidth: Int(image.sourcePixelSize.width),
                     sourceHeight: Int(image.sourcePixelSize.height))
    }

    private func sourceMatches(_ ticket: ThumbnailCacheTicket, render: RenderKey) throws -> Bool {
        do {
            return try fingerprint(ticket.request.fileURL, expected: render.revision) == ticket.sourceSHA256
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImageLoadError(.sourceChanged, itemID: render.itemID, revision: render.revision)
        }
    }

    private func fingerprint(_ url: URL, expected: FileRevision) throws -> String? {
        try Task.checkCancellation()
        let before = try FileRevisionReader.read(url)
        guard before == expected, before.byteCount >= 0,
              before.byteCount <= Self.maximumSourceBytes else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha = SHA256()
        var count = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            count += chunk.count
            guard count <= Self.maximumSourceBytes else { return nil }
            sha.update(data: chunk)
        }
        try Task.checkCancellation()
        let after = try FileRevisionReader.read(url)
        guard count == before.byteCount, after == before else { return nil }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func rowChecksum(key: String, item: String, source: String, path: String,
                             byteCount: Int, payloadSHA256: String, width: Int, height: Int) -> String {
        let fields = ["row1", key, item, source, path, String(byteCount), payloadSHA256,
                      String(Self.cacheVersion), String(width), String(height)]
        return digest(Data(fields.joined(separator: "|").utf8))
    }

    private struct Row {
        let payloadPath: String
        let byteCount: Int
        let payloadSHA256: String
        let sourceWidth: Int
        let sourceHeight: Int
    }
    private var databaseURL: URL { directory.appendingPathComponent("index.sqlite3") }
    private func removeDamagedEntry(_ ticket: ThumbnailCacheTicket) {
        // The path comes from the key, never from a possibly damaged SQLite row.
        var writable: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &writable,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db = writable else {
            if let writable { sqlite3_close(writable) }
            return
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM thumbnails WHERE key=?", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(ticket.key.filename, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(ticket.key.filename + ".png"))
    }

    private func sweepOrphansIfNeeded() {
        guard !didSweepOrphans, let db = openDatabase(create: false) else { return }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM thumbnails", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        var referenced = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = sqlite3_column_text(statement, 0) { referenced.insert(String(cString: path)) }
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(".png") && name.count == 68 && !referenced.contains(name) {
            let hex = name.dropLast(4)
            guard hex.allSatisfy({ $0.isHexDigit }) else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        didSweepOrphans = true
    }
    private func openDatabase(create: Bool) -> OpaquePointer? {
        if !create && !FileManager.default.fileExists(atPath: databaseURL.path) { return nil }
        var db: OpaquePointer?
        let flags = (create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        return db
    }
    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }
    private func readRow(_ ticket: ThumbnailCacheTicket) -> Row? {
        guard let db = openDatabase(create: false) else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT payload, byte_count, payload_sha256, source_width, source_height, item_id, source_sha256, row_sha256 FROM thumbnails WHERE key=? AND cache_version=2"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(ticket.key.filename, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let path = sqlite3_column_text(statement, 0),
              let sha = sqlite3_column_text(statement, 2),
              let item = sqlite3_column_text(statement, 5),
              let source = sqlite3_column_text(statement, 6),
              let rowSHA = sqlite3_column_text(statement, 7),
              String(cString: item) == ticket.request.renderKey?.itemID.stableEncoding,
              String(cString: source) == ticket.sourceSHA256 else { return nil }
        let width = Int(sqlite3_column_int(statement, 3)), height = Int(sqlite3_column_int(statement, 4))
        let byteCount = Int(sqlite3_column_int(statement, 1))
        guard width > 0, height > 0,
              String(cString: rowSHA) == rowChecksum(key: ticket.key.filename, item: String(cString: item),
                source: String(cString: source), path: String(cString: path), byteCount: byteCount,
                payloadSHA256: String(cString: sha), width: width, height: height) else { return nil }
        return Row(payloadPath: String(cString: path), byteCount: byteCount,
                   payloadSHA256: String(cString: sha), sourceWidth: width, sourceHeight: height)
    }
    private func writeRow(_ ticket: ThumbnailCacheTicket, payloadPath: String, payloadBytes: Int,
                          payloadSHA256: String, sourceWidth: Int, sourceHeight: Int) throws {
        guard let db = openDatabase(create: true) else { throw ThumbnailStoreError.database }
        defer { sqlite3_close(db) }
        let schema = "CREATE TABLE IF NOT EXISTS thumbnails (key TEXT PRIMARY KEY, item_id TEXT NOT NULL, source_sha256 TEXT NOT NULL, payload TEXT NOT NULL, byte_count INTEGER NOT NULL, payload_sha256 TEXT NOT NULL, last_access REAL NOT NULL, cache_version INTEGER NOT NULL, source_width INTEGER NOT NULL, source_height INTEGER NOT NULL, row_sha256 TEXT)"
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw ThumbnailStoreError.database }
        // Older re-creatable indexes lack this column. Their version-1 rows remain misses.
        _ = sqlite3_exec(db, "ALTER TABLE thumbnails ADD COLUMN row_sha256 TEXT", nil, nil, nil)
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO thumbnails (key,item_id,source_sha256,payload,byte_count,payload_sha256,last_access,cache_version,source_width,source_height,row_sha256) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ThumbnailStoreError.database }
        defer { sqlite3_finalize(statement) }
        bind(ticket.key.filename, to: statement, at: 1)
        bind(ticket.request.renderKey!.itemID.stableEncoding, to: statement, at: 2)
        bind(ticket.sourceSHA256, to: statement, at: 3)
        bind(payloadPath, to: statement, at: 4)
        sqlite3_bind_int(statement, 5, Int32(payloadBytes))
        bind(payloadSHA256, to: statement, at: 6)
        sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970)
        sqlite3_bind_int(statement, 8, Int32(Self.cacheVersion))
        sqlite3_bind_int(statement, 9, Int32(sourceWidth))
        sqlite3_bind_int(statement, 10, Int32(sourceHeight))
        bind(rowChecksum(key: ticket.key.filename, item: ticket.request.renderKey!.itemID.stableEncoding,
            source: ticket.sourceSHA256, path: payloadPath, byteCount: payloadBytes,
            payloadSHA256: payloadSHA256, width: sourceWidth, height: sourceHeight), to: statement, at: 11)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ThumbnailStoreError.database }
    }
}

private enum ThumbnailStoreError: Error { case database }
