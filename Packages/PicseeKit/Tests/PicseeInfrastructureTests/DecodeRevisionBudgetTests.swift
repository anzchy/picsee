import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

private struct ReplacingDecoder: ImageDecoding {
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        // Deterministically replace the file after the pipeline's admission header
        // was read, but before the real decoder reads its own header.
        try Data(contentsOf: fixture("coordinate-grid.png")).write(to: request.fileURL)
        return try ImageIODecoder().decode(request)
    }
}
@Test func changedSourceCannotOutgrowItsAdmittedReservation() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(contentsOf: fixture("alpha-gradient.png")).write(to: file)
    let pipeline = ImageIOPipeline(decoder: ReplacingDecoder())
    await #expect(throws: ImageDecodeError.budgetExceeded) {
        try await pipeline.image(for: ImageDecodeRequest(fileURL: file, maximumPixelSize: 128))
    }
}
