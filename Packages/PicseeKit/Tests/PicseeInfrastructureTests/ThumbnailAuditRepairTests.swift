import Foundation
import SQLite3
import Testing
import PicseeCore
@testable import PicseeInfrastructure

@Test func p304AuditMalformedEvictionRowCannotDeleteOutsideCache() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cacheDirectory = folder.appendingPathComponent("cache")
    let outside = folder.appendingPathComponent("original.png")
    let sentinel = Data("original must survive malformed cache index".utf8)
    try sentinel.write(to: outside)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let seed = ThumbnailDiskCache(directory: cacheDirectory)
    var tickets: [ThumbnailCacheTicket] = []
    var images: [DecodedImage] = []
    for index in 0..<2 {
        let file = folder.appendingPathComponent("image-\(index).tiff")
        try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
        let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
        tickets.append(try #require(try await seed.prepare(request)))
        images.append(try await pipeline.image(for: request))
    }
    try await seed.store(images[0], for: tickets[0])
    let payload = cacheDirectory.appendingPathComponent(tickets[0].key.filename + ".png")
    let payloadBytes = try Data(contentsOf: payload).count
    let index = cacheDirectory.appendingPathComponent("index.sqlite3")
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(index.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    let sql = "INSERT INTO thumbnails (key,item_id,source_sha256,payload,byte_count,payload_sha256,last_access,cache_version,source_width,source_height,row_sha256) VALUES ('../original','bad','bad','../original.png',\(3 * payloadBytes),'bad',0,2,1,1,'bad')"
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    let limited = ThumbnailDiskCache(directory: cacheDirectory,
                                     highWaterBytes: 4 * payloadBytes, lowWaterBytes: 2 * payloadBytes)
    try await limited.store(images[1], for: tickets[1])
    let outsideSurvived = (try? Data(contentsOf: outside)) == sentinel
    #expect(outsideSurvived)
    #expect(try await limited.load(tickets[0]).map { _ in true } == true)
    #expect(try await limited.load(tickets[1]).map { _ in true } == true)
    var check: OpaquePointer?
    #expect(sqlite3_open_v2(index.path, &check, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { if let check { sqlite3_close(check) } }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(check, "SELECT count(*) FROM thumbnails WHERE key='../original'", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 0)
}
