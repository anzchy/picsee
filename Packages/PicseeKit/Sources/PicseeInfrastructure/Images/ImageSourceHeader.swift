import Foundation
import ImageIO
import PicseeCore

struct ImageSourceHeader: Sendable {
    let width: Int
    let height: Int
    let revision: FileRevision
    static func read(_ request: ImageDecodeRequest, budget: Int) throws -> ImageSourceHeader {
        guard request.fileURL.isFileURL, request.maximumPixelSize > 0 else { throw ImageDecodeError.invalidRequest }
        // A header-only PNG may be too incomplete for ImageIO properties. Inspect
        // its fixed IHDR fields first, without reading the payload or allocating pixels.
        let file = try? FileHandle(forReadingFrom: request.fileURL)
        let prefix = try? file?.read(upToCount: 24)
        try? file?.close()
        if let data = prefix, data.count == 24,
           Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
           Array(data[12..<16]) == [73, 72, 68, 82] {
            let width = data[16..<20].reduce(0) { ($0 << 8) | Int($1) }
            let height = data[20..<24].reduce(0) { ($0 << 8) | Int($1) }
            _ = try DecodeBudget.sourceCost(width: width, height: height, budget: budget)
        }
        guard let source = CGImageSourceCreateWithURL(request.fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ImageDecodeError.unreadableImage }
        _ = try DecodeBudget.sourceCost(width: width, height: height, budget: budget)
        let attributes = try FileManager.default.attributesOfItem(atPath: request.fileURL.path)
        guard let size = attributes[.size] as? NSNumber else { throw ImageDecodeError.unreadableImage }
        return ImageSourceHeader(width: width, height: height,
            revision: FileRevision(byteCount: size.intValue,
                                   modificationDate: attributes[.modificationDate] as? Date))
    }
}
