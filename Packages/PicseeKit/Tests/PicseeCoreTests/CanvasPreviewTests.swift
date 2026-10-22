import Foundation
import Testing
import PicseeCore

@Test func previewAlwaysPrecedesViewportDetailAndNeverExceeds512() {
    #expect(CanvasDecodePolicy.previewMaximumPixelSize == 512)
    #expect(CanvasDecodePolicy.maximumPixelSize(source: CGSize(width: 8000, height: 6000), viewport: CGSize(width: 1920, height: 1080), zoom: 0.18) == 1920)
    #expect(CanvasDecodePolicy.maximumPixelSize(source: CGSize(width: 8000, height: 6000), viewport: CGSize(width: 1920, height: 1080), zoom: 1) == 8000)
}
