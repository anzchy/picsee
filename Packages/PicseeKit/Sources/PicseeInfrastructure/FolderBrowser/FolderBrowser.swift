import Foundation
import PicseeCore
import UniformTypeIdentifiers

public actor FolderBrowser: FolderScanning {
    // Provisional after WI-0's first-64 probe; later P2 device validation calibrates these.
    public static let firstBatchSize = 64
    public static let batchSize = 256
    public init() {}
    public func scan(in folder: URL, root: ItemIdentityRoot,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws {
        try Task.checkCancellation()
        guard AccessBoundary.contains(folder, in: root.url) else { throw FileAccessError.outsideRoot }
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in enumerationError = error; return false }) else { throw FileAccessError.invalidFolder }
        var batch: [FolderEntry] = []
        var limit = Self.firstBatchSize
        while let file = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            // Resolve/check before metadata lookup; outward links are never inspected here.
            guard AccessBoundary.contains(file, in: root.url) else { continue }
            let values = try file.resolvingSymlinksInPath().resourceValues(forKeys: [
                .isRegularFileKey, .contentTypeKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true, values.contentType?.conforms(to: .image) == true else { continue }
            batch.append(FolderEntry(url: file, root: root, modificationDate: values.contentModificationDate,
                fileSize: values.fileSize.map(Int64.init)))
            if batch.count == limit {
                try await emit(batch)
                try Task.checkCancellation()
                batch.removeAll(keepingCapacity: true)
                limit = Self.batchSize
            }
        }
        try Task.checkCancellation()
        if let enumerationError { throw enumerationError }
        if !batch.isEmpty {
            try await emit(batch)
            try Task.checkCancellation()
        }
    }
}
