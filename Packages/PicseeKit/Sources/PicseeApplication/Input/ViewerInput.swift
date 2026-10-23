import Foundation
import UniformTypeIdentifiers

/// Keeps original grant URLs while comparing canonical paths for duplicate input.
public enum ViewerInput: Equatable, Sendable {
    case single(URL), files([URL]), folder(URL), rejected([URL])

    public static func classify(_ urls: [URL]) -> ViewerInput {
        let unique = uniqueFiles(urls)
        let images = unique.filter { !$0.hasDirectoryPath && isImage($0) }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        if images.count == 1 { return .single(images[0]) }
        if images.count > 1 { return .files(images) }
        let folders = unique.filter(\.hasDirectoryPath)
        return folders.count == 1 ? .folder(folders[0]) : .rejected(unique)
    }
    public static func excludedCount(in urls: [URL]) -> Int {
        uniqueFiles(urls).filter { !$0.hasDirectoryPath && !isImage($0) }.count
    }
    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }
    private static func uniqueFiles(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter {
            $0.isFileURL && seen.insert($0.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path).inserted
        }
    }
}
