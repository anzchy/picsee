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
    enum IntegrityDecision: Equatable { case healthy, confirmedCorrupt, unconfirmedFailure }
    static func integrityDecision(prepareCode: Int32, firstStepCode: Int32?, diagnostic: String?) -> IntegrityDecision {
        if isCorruptSQLite(prepareCode) { return .confirmedCorrupt }
        guard prepareCode == SQLITE_OK, let firstStepCode else { return .unconfirmedFailure }
        if isCorruptSQLite(firstStepCode) { return .confirmedCorrupt }
        guard firstStepCode == SQLITE_ROW, let diagnostic else { return .unconfirmedFailure }
        return diagnostic == "ok" ? .healthy : .confirmedCorrupt
    }
    static func isMissingRemovalError(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileNoSuchFile.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
    }
    public static let maximumSourceBytes = 32 * 1024 * 1024
    public static let maximumPayloadBytes = 8 * 1024 * 1024
    public static let maximumPixelEdge = 1024
    private static let cacheVersion = 2
    private static let encoderVersion = 2
    private let directory: URL
    private let highWaterBytes: Int
    private let lowWaterBytes: Int
    private let afterPayloadWrite: (@Sendable () throws -> Void)?
    private let afterReadLeaseAcquired: (@Sendable () async -> Void)?
    private let afterOrphanSnapshot: (@Sendable () async -> Void)?
    private var didSweepOrphans = false

    public init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Picsee/Thumbnails", isDirectory: true)) {
        self.directory = directory
        self.highWaterBytes = 512 * 1024 * 1024
        self.lowWaterBytes = 384 * 1024 * 1024
        self.afterPayloadWrite = nil
        self.afterReadLeaseAcquired = nil
        self.afterOrphanSnapshot = nil
    }

    init(directory: URL, afterPayloadWrite: @escaping @Sendable () throws -> Void) {
        self.directory = directory
        self.highWaterBytes = 512 * 1024 * 1024
        self.lowWaterBytes = 384 * 1024 * 1024
        self.afterPayloadWrite = afterPayloadWrite
        self.afterReadLeaseAcquired = nil
        self.afterOrphanSnapshot = nil
    }

    init(directory: URL, highWaterBytes: Int, lowWaterBytes: Int) {
        self.directory = directory
        self.highWaterBytes = highWaterBytes
        self.lowWaterBytes = lowWaterBytes
        self.afterPayloadWrite = nil
        self.afterReadLeaseAcquired = nil
        self.afterOrphanSnapshot = nil
    }

    init(directory: URL, afterReadLeaseAcquired: @escaping @Sendable () async -> Void) {
        self.directory = directory
        self.highWaterBytes = 512 * 1024 * 1024
        self.lowWaterBytes = 384 * 1024 * 1024
        self.afterPayloadWrite = nil
        self.afterReadLeaseAcquired = afterReadLeaseAcquired
        self.afterOrphanSnapshot = nil
    }

    init(directory: URL, afterOrphanSnapshot: @escaping @Sendable () async -> Void) {
        self.directory = directory
        self.highWaterBytes = 512 * 1024 * 1024
        self.lowWaterBytes = 384 * 1024 * 1024
        self.afterPayloadWrite = nil
        self.afterReadLeaseAcquired = nil
        self.afterOrphanSnapshot = afterOrphanSnapshot
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
        await sweepOrphansIfNeeded()
        guard let row = readRow(ticket), row.byteCount > 0, row.byteCount <= Self.maximumPayloadBytes,
              row.payloadPath == ticket.key.filename + ".png" else {
            removeDamagedEntry(ticket)
            return nil
        }
        let payload = directory.appendingPathComponent(row.payloadPath)
        guard PayloadLeaseRegistry.shared.acquire(payload.path) else { return nil }
        var leaseHeld = true
        defer { if leaseHeld { PayloadLeaseRegistry.shared.release(payload.path) } }
        await afterReadLeaseAcquired?()
        try Task.checkCancellation()
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: ticket.request.maximumPixelSize,
        ]
        guard let size = (try? FileManager.default.attributesOfItem(atPath: payload.path)[.size] as? NSNumber)?.intValue,
              size == row.byteCount, size <= Self.maximumPayloadBytes,
              let data = try? Data(contentsOf: payload), data.count == row.byteCount,
              digest(data) == row.payloadSHA256,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              (CGImageSourceGetType(source) as String?) == UTType.png.identifier,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary),
              image.width > 0, image.height > 0,
              image.width <= ticket.request.maximumPixelSize,
              image.height <= ticket.request.maximumPixelSize else {
            PayloadLeaseRegistry.shared.release(payload.path)
            leaseHeld = false
            removeDamagedEntry(ticket)
            return nil
        }
        try Task.checkCancellation()
        guard try fingerprint(ticket.request.fileURL, expected: render.revision) == ticket.sourceSHA256 else { return nil }
        try Task.checkCancellation()
        touch(ticket.key.filename)
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
        guard let payload = Self.removingPNGMetadata(from: bytes as Data),
              payload.count > 0, payload.count <= Self.maximumPayloadBytes else { return }
        // Re-read after decode and encoding. Metadata alone cannot prove same-inode writes.
        guard try sourceMatches(ticket, render: render) else {
            throw ImageLoadError(.sourceChanged, itemID: render.itemID, revision: render.revision)
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = ticket.key.filename + ".png"
        guard let url = payloadURL(forKey: ticket.key.filename) else { return }
        guard PayloadLeaseRegistry.shared.acquireWrite(url.path) else { return }
        defer { PayloadLeaseRegistry.shared.releaseWrite(url.path) }
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
        try withIndexLock {
            try repairCorruptIndexIfNeeded()
            try writeRow(ticket, payloadPath: path, payloadBytes: payload.count,
                         payloadSHA256: digest(payload), sourceWidth: Int(image.sourcePixelSize.width),
                         sourceHeight: Int(image.sourcePixelSize.height))
        }
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

    private static func removingPNGMetadata(from data: Data) -> Data? {
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard data.starts(with: signature) else { return nil }
        let metadataChunks: Set<String> = ["eXIf", "tEXt", "zTXt", "iTXt"]
        var result = signature, offset = 8
        while offset + 12 <= data.count {
            let length = data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let end = offset + 12 + Int(length)
            guard end <= data.count else { return nil }
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if !metadataChunks.contains(type) { result.append(data[offset..<end]) }
            offset = end
        }
        return offset == data.count ? result : nil
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
    private func withIndexLock<T>(_ body: () throws -> T) rethrows -> T {
        try CacheIndexLocks.shared.withLock(for: directory, body)
    }
    private func payloadURL(forKey key: String) -> URL? {
        let bytes = key.utf8
        guard bytes.count == 64,
              bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        let root = directory.standardizedFileURL
        let payload = root.appendingPathComponent(key + ".png").standardizedFileURL
        guard payload.deletingLastPathComponent() == root else { return nil }
        return payload
    }

    private func deleteIndexRow(_ key: String, using db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM thumbnails WHERE key=?", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    private func repairCorruptIndexIfNeeded() throws {
        let index = databaseURL.path
        guard FileManager.default.fileExists(atPath: index),
              (try? FileManager.default.attributesOfItem(atPath: index)[.type] as? FileAttributeType) == .typeRegular else { return }
        let decision = try { () throws -> IntegrityDecision in
            var db: OpaquePointer?
            let opened = sqlite3_open_v2(index, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
            defer { if let db { sqlite3_close(db) } }
            guard opened == SQLITE_OK else { throw ThumbnailStoreError.database }
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            let result = prepared == SQLITE_OK ? sqlite3_step(statement) : nil
            var diagnostic: String?
            if result == SQLITE_ROW, let status = sqlite3_column_text(statement, 0) {
                diagnostic = String(cString: status)
            }
            let decision = Self.integrityDecision(prepareCode: prepared, firstStepCode: result, diagnostic: diagnostic)
            guard decision != .unconfirmedFailure else { throw ThumbnailStoreError.database }
            return decision
        }()
        guard decision == .confirmedCorrupt else { return }
        try FileManager.default.removeItem(atPath: index)
        didSweepOrphans = false
    }
    private static func isCorruptSQLite(_ code: Int32) -> Bool {
        let primary = code & 0xff
        return primary == SQLITE_CORRUPT || primary == SQLITE_NOTADB
    }
    private func removeDamagedEntry(_ ticket: ThumbnailCacheTicket) {
        withIndexLock { removeDamagedEntryLocked(ticket) }
    }
    private func removeDamagedEntryLocked(_ ticket: ThumbnailCacheTicket) {
        // The path comes from the key, never from a possibly damaged SQLite row.
        guard let path = payloadURL(forKey: ticket.key.filename)?.path else { return }
        guard PayloadLeaseRegistry.shared.beginDeletion(path) else { return }
        defer { PayloadLeaseRegistry.shared.endDeletion(path) }
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
        try? FileManager.default.removeItem(atPath: path)
    }

    private func referencedPayloads() -> Set<String>? {
        guard let db = openDatabase(create: false) else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM thumbnails", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var referenced = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = sqlite3_column_text(statement, 0) { referenced.insert(String(cString: path)) }
        }
        return referenced
    }
    private func sweepOrphansIfNeeded() async {
        guard !didSweepOrphans, let referenced = withIndexLock({ referencedPayloads() }) else { return }
        await afterOrphanSnapshot?()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        var deferred = false
        for name in names where name.hasSuffix(".png") && name.count == 68 && !referenced.contains(name) {
            guard let payload = payloadURL(forKey: String(name.dropLast(4))) else { continue }
            if !withIndexLock({ removeOrphanIfUnindexed(payload) }) { deferred = true }
        }
        didSweepOrphans = !deferred
    }
    private func removeOrphanIfUnindexed(_ payload: URL) -> Bool {
        guard PayloadLeaseRegistry.shared.beginDeletion(payload.path) else { return false }
        defer { PayloadLeaseRegistry.shared.endDeletion(payload.path) }
        guard let db = openDatabase(create: false) else { return false }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM thumbnails WHERE payload=? LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(payload.lastPathComponent, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        guard result == SQLITE_DONE else { return false }
        do { try FileManager.default.removeItem(at: payload) }
        catch { return false }
        return true
    }

    private func touch(_ key: String) {
        withIndexLock { touchLocked(key) }
    }
    private func touchLocked(_ key: String) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "UPDATE thumbnails SET last_access=(SELECT MAX(last_access)+1 FROM thumbnails) WHERE key=?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1)
        _ = sqlite3_step(statement)
    }

    private func evictIfNeeded(using db: OpaquePointer) {
        guard highWaterBytes > 0, lowWaterBytes >= 0, lowWaterBytes <= highWaterBytes else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT key,payload,byte_count FROM thumbnails ORDER BY last_access ASC,key ASC",
            -1, &statement, nil) == SQLITE_OK else { return }
        var rows: [(key: String, path: String, bytes: Int64)] = []
        var total: Int64 = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = sqlite3_column_text(statement, 0),
                  let path = sqlite3_column_text(statement, 1) else { continue }
            let bytes = max(0, sqlite3_column_int64(statement, 2))
            let (sum, overflow) = total.addingReportingOverflow(bytes)
            total = overflow ? Int64.max : sum
            rows.append((String(cString: key), String(cString: path), bytes))
        }
        sqlite3_finalize(statement)
        guard total > highWaterBytes else { return }
        for row in rows where total > lowWaterBytes {
            guard let payload = payloadURL(forKey: row.key), row.path == payload.lastPathComponent else {
                // An index row cannot authorize deletion of a filesystem path.
                if deleteIndexRow(row.key, using: db) { total -= row.bytes }
                continue
            }
            guard PayloadLeaseRegistry.shared.beginDeletion(payload.path) else { continue }
            defer { PayloadLeaseRegistry.shared.endDeletion(payload.path) }
            do { try FileManager.default.removeItem(at: payload) }
            catch {
                guard Self.isMissingRemovalError(error as NSError) else { continue }
            }
            total -= row.bytes
            _ = deleteIndexRow(row.key, using: db)
        }
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
        withIndexLock { readRowLocked(ticket) }
    }
    private func readRowLocked(_ ticket: ThumbnailCacheTicket) -> Row? {
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
        let sql = "INSERT OR REPLACE INTO thumbnails (key,item_id,source_sha256,payload,byte_count,payload_sha256,last_access,cache_version,source_width,source_height,row_sha256) VALUES (?,?,?,?,?, ?, (SELECT COALESCE(MAX(last_access),0)+1 FROM thumbnails), ?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ThumbnailStoreError.database }
        defer { sqlite3_finalize(statement) }
        guard let renderKey = ticket.request.renderKey else { throw ThumbnailStoreError.database }
        bind(ticket.key.filename, to: statement, at: 1)
        bind(renderKey.itemID.stableEncoding, to: statement, at: 2)
        bind(ticket.sourceSHA256, to: statement, at: 3)
        bind(payloadPath, to: statement, at: 4)
        sqlite3_bind_int(statement, 5, Int32(payloadBytes))
        bind(payloadSHA256, to: statement, at: 6)
        sqlite3_bind_int(statement, 7, Int32(Self.cacheVersion))
        sqlite3_bind_int(statement, 8, Int32(sourceWidth))
        sqlite3_bind_int(statement, 9, Int32(sourceHeight))
        bind(rowChecksum(key: ticket.key.filename, item: renderKey.itemID.stableEncoding,
            source: ticket.sourceSHA256, path: payloadPath, byteCount: payloadBytes,
            payloadSHA256: payloadSHA256, width: sourceWidth, height: sourceHeight), to: statement, at: 10)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ThumbnailStoreError.database }
        sqlite3_finalize(statement)
        statement = nil
        evictIfNeeded(using: db)
    }
}

private enum ThumbnailStoreError: Error { case database }

/// Every app-owned SQLite connection for one cache directory uses this lock.
private final class CacheIndexLocks: @unchecked Sendable {
    static let shared = CacheIndexLocks()
    private let mapLock = NSLock()
    private var locks: [String: NSRecursiveLock] = [:]

    func withLock<T>(for directory: URL, _ body: () throws -> T) rethrows -> T {
        let key = directory.standardizedFileURL.path
        mapLock.lock()
        let lock: NSRecursiveLock
        if let existing = locks[key] { lock = existing }
        else {
            lock = NSRecursiveLock()
            locks[key] = lock
        }
        mapLock.unlock()
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// Coordinates actors in this process that use the same cache directory.
private final class PayloadLeaseRegistry: @unchecked Sendable {
    static let shared = PayloadLeaseRegistry()
    private let lock = NSLock()
    // Positive values count readers; -1 is the sole writer.
    private var claims: [String: Int] = [:]
    private var deleting = Set<String>()

    func acquire(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !deleting.contains(key), claims[key, default: 0] >= 0 else { return false }
        claims[key, default: 0] += 1
        return true
    }

    func release(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        // Every release follows a successful acquire; fail fast on an unbalanced lease.
        let count = claims[key]!
        precondition(count > 0)
        if count == 1 { claims.removeValue(forKey: key) }
        else { claims[key] = count - 1 }
    }

    func acquireWrite(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        guard claims[key] == nil, !deleting.contains(key) else { return false }
        claims[key] = -1
        return true
    }

    func releaseWrite(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        precondition(claims[key] == -1)
        claims.removeValue(forKey: key)
    }

    func beginDeletion(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        guard claims[key] == nil, !deleting.contains(key) else { return false }
        deleting.insert(key)
        return true
    }

    func endDeletion(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        deleting.remove(URL(fileURLWithPath: path).standardizedFileURL.path)
    }
}
