import Foundation
import Testing
import PicseeCore
@testable import PicseeInfrastructure

@Test func statesHeaderWithoutIENDIsRejectedDeterministically() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("missing-iend.png")
    // Complete 1×1 RGBA IHDR with its valid CRC; no IEND chunk follows it.
    let header: [UInt8] = [137,80,78,71,13,10,26,10, 0,0,0,13, 73,72,68,82,
        0,0,0,1, 0,0,0,1, 8,6,0,0,0, 31,21,196,137]
    try Data(header).write(to: file)
    #expect(throws: ImageDecodeError.unreadableImage) {
        try ImageSourceHeader.read(ImageDecodeRequest(fileURL: file, maximumPixelSize: 1),
            budget: 1_000_000, itemID: .ephemeral(UUID()))
    }
}
