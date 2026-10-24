import Foundation
import PicseeCore
import UniformTypeIdentifiers

public actor FolderBrowser: FolderScanning {
    // Provisional after WI-0's first-64 probe; later P2 device validation calibrates these.
    public static let firstBatchSize = 64
    public static let batchSize = 256
    public init() {}
    public func scan(in folder: URL, root: ItemIdentityRoot, options: FolderScanOptions,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws {
        try Task.checkCancellation()
        guard AccessBoundary.contains(folder, in: root.url) else { throw FileAccessError.outsideRoot }
        var batch: [FolderEntry] = []
        var limit = Self.firstBatchSize
        var admittedImages = 0
        var visitedEntries = 0
        var directories: [(url: URL, depth: Int)] = [(folder, 0)]
        var seenDirectories: Set<URL> = [folder.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL]
        var seenImages: Set<ItemID> = []
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            guard AccessBoundary.contains(directory.url, in: root.url) else { continue }
            var enumerationError: (any Error)?
            guard let enumerator = FileManager.default.enumerator(at: directory.url, includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in enumerationError = error; return false }) else { throw FileAccessError.invalidFolder }
            while let file = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if visitedEntries >= options.maxVisitedEntries {
                    if !batch.isEmpty { try await emit(batch); try Task.checkCancellation(); batch.removeAll() }
                    throw FolderScanLimitError.entryLimit(limit: options.maxVisitedEntries, admittedImages: admittedImages)
                }
                visitedEntries += 1
                // Canonical boundary comes before resource lookup, including aliases and symlinks.
                guard AccessBoundary.contains(file, in: root.url) else { continue }
                let target = file.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
                let values = try target.resourceValues(forKeys: [
                    .isRegularFileKey, .isDirectoryKey, .isPackageKey, .contentTypeKey,
                    .contentModificationDateKey, .fileSizeKey])
                if options.recursive, values.isDirectory == true, values.isPackage != true {
                    guard !seenDirectories.contains(target) else { continue }
                    let nextDepth = directory.depth + 1
                    if nextDepth > options.maxDepth {
                        if !batch.isEmpty { try await emit(batch); try Task.checkCancellation(); batch.removeAll() }
                        throw FolderScanLimitError.depthLimit(limit: options.maxDepth, admittedImages: admittedImages)
                    }
                    _ = seenDirectories.insert(target)
                    directories.append((file, nextDepth))
                    continue
                }
                guard values.isRegularFile == true, values.contentType?.conforms(to: .image) == true else { continue }
                let entry = FolderEntry(url: file, root: root, modificationDate: values.contentModificationDate,
                    fileSize: values.fileSize.map(Int64.init))
                if options.recursive && !seenImages.insert(entry.itemID).inserted { continue }
                batch.append(entry)
                admittedImages += 1
                if batch.count == limit {
                    try await emit(batch)
                    try Task.checkCancellation()
                    batch.removeAll(keepingCapacity: true)
                    limit = Self.batchSize
                }
            }
            try Task.checkCancellation()
            if let enumerationError { throw enumerationError }
        }
        if !batch.isEmpty { try await emit(batch); try Task.checkCancellation() }
    }
}
