import Foundation
import Testing
import PicseeCore
@testable import PicseeInfrastructure

@Test func bitDepthReservationCoversRealSixteenBitPixels() throws {
    let item = ItemID.ephemeral(UUID())
    let request = ImageDecodeRequest(fileURL: fixture("gradient-16bit.png"), maximumPixelSize: 256)
    let header = try ImageSourceHeader.read(request, budget: 1_000_000, itemID: item)
    let image = try ImageIODecoder().decode(request)
    let reserved = try DecodeBudget.sourceCost(width: 256, height: 128, budget: 1_000_000, bytesPerPixel: header.bytesPerPixel)
    #expect(DecodeBudget.bytesPerPixel(depth: 16, components: 3, hasAlpha: false, isFloat: false) == 8)
    #expect(DecodeBudget.bytesPerPixel(depth: 32, components: 3, hasAlpha: true, isFloat: true) == 16)
    #expect(reserved >= image.image.bytesPerRow * image.image.height)
    #expect(throws: ImageDecodeError.budgetExceeded) {
        try DecodeBudget.sourceCost(width: 256, height: 128, budget: 200_000, bytesPerPixel: 8)
    }
    let eight = ImageDecodeRequest(fileURL: fixture("alpha-gradient.png"), maximumPixelSize: 256)
    let eightHeader = try ImageSourceHeader.read(eight, budget: 1_000_000, itemID: item)
    #expect(eightHeader.bytesPerPixel == 4)
    #expect(try DecodeBudget.sourceCost(width: 256, height: 128, budget: 1_000_000, bytesPerPixel: eightHeader.bytesPerPixel) == 131_072)
}
