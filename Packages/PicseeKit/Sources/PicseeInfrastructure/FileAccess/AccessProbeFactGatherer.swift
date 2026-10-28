import Dispatch
import Foundation
import PicseeCore

public struct AccessProbeReport: Codable, Equatable, Sendable {
    public let volume: AccessProbeVolume
    public let volumePropertiesError: AccessProbeError?
    public let mountedVolumes: [AccessProbeVolume]
    public let resolution: AccessProbeResolution
    public let scopeStarted: Bool?
    public let listing: AccessProbeDirectoryListing?
    public let isInTrash: Bool
    public let latencyMilliseconds: Double
    public let classification: AccessProbeClassification

    public init(
        volume: AccessProbeVolume,
        volumePropertiesError: AccessProbeError?,
        mountedVolumes: [AccessProbeVolume],
        resolution: AccessProbeResolution,
        scopeStarted: Bool?,
        listing: AccessProbeDirectoryListing?,
        isInTrash: Bool,
        latencyMilliseconds: Double,
        classification: AccessProbeClassification
    ) {
        self.volume = volume
        self.volumePropertiesError = volumePropertiesError
        self.mountedVolumes = mountedVolumes
        self.resolution = resolution
        self.scopeStarted = scopeStarted
        self.listing = listing
        self.isInTrash = isInTrash
        self.latencyMilliseconds = latencyMilliseconds
        self.classification = classification
    }
}

public protocol AccessProbeBookmarkCoding: Sendable {
    func makeBookmark(for url: URL, includingResourceValuesForKeys keys: Set<URLResourceKey>?) throws -> Data
    func volumeProperties(in data: Data) -> AccessProbeVolume
    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> AccessProbeResolution
}

public struct AccessProbeFactGatherer: Sendable {
    private static let volumeKeys: [URLResourceKey] = [.volumeUUIDStringKey, .volumeURLKey, .volumeNameKey]
    private let bookmarks: any AccessProbeBookmarkCoding
    private let scope: any SecurityScope
    private let mountedVolumesProvider: @Sendable () -> [AccessProbeVolume]
    private let lister: @Sendable (URL) throws -> Int
    private let trashCheck: @Sendable (URL) -> Bool

    public init() {
        bookmarks = SystemAccessProbeBookmarkCoding()
        scope = SystemSecurityScope()
        mountedVolumesProvider = { Self.mountedVolumes() }
        lister = { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil).count }
        trashCheck = { FileAccess.isTrashed($0) }
    }

    init(
        bookmarks: any AccessProbeBookmarkCoding,
        scope: any SecurityScope,
        mountedVolumes: @escaping @Sendable () -> [AccessProbeVolume],
        lister: @escaping @Sendable (URL) throws -> Int,
        isInTrash: @escaping @Sendable (URL) -> Bool
    ) {
        self.bookmarks = bookmarks
        self.scope = scope
        mountedVolumesProvider = mountedVolumes
        self.lister = lister
        trashCheck = isInTrash
    }

    public func makeBookmark(for url: URL, storingVolumeProperties: Bool) throws -> Data {
        try bookmarks.makeBookmark(
            for: url,
            includingResourceValuesForKeys: storingVolumeProperties ? Set(Self.volumeKeys) : nil
        )
    }

    public func gather(bookmarkData: Data) -> AccessProbeReport {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let volume = bookmarks.volumeProperties(in: bookmarkData)
        let volumePropertiesError: AccessProbeError? = nil
        let mountedVolumes = mountedVolumesProvider()
        let resolution: AccessProbeResolution
        var scopeStarted: Bool?
        var listing: AccessProbeDirectoryListing?
        var isInTrash = false
        do {
            let resolved = try bookmarks.resolve(
                bookmarkData,
                options: [.withSecurityScope, .withoutMounting, .withoutUI]
            )
            resolution = resolved
            if let url = resolved.url {
                isInTrash = trashCheck(url)
                let started = scope.start(url)
                scopeStarted = started
                do {
                    defer { if started { scope.stop(url) } }
                    do {
                        listing = .succeeded(entryCount: try lister(url))
                    } catch {
                        listing = .failed(AccessProbeError(error))
                    }
                }
            }
        } catch {
            resolution = .failed(AccessProbeError(error))
        }

        let facts = AccessProbeFacts(
            volume: volume,
            mountedVolumes: mountedVolumes,
            resolution: resolution,
            scopeStarted: scopeStarted,
            listing: listing,
            isInTrash: isInTrash
        )
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return AccessProbeReport(
            volume: volume,
            volumePropertiesError: volumePropertiesError,
            mountedVolumes: mountedVolumes,
            resolution: resolution,
            scopeStarted: scopeStarted,
            listing: listing,
            isInTrash: isInTrash,
            latencyMilliseconds: Double(elapsed) / 1_000_000,
            classification: AccessCauseClassifier.classify(facts)
        )
    }

    private static func mountedVolumes() -> [AccessProbeVolume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: volumeKeys,
            options: []
        ) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(volumeKeys))
            return AccessProbeVolume(
                uuid: values?.volumeUUIDString,
                url: values?.volume ?? url,
                name: values?.volumeName
            )
        }
    }
}

private struct SystemAccessProbeBookmarkCoding: AccessProbeBookmarkCoding {
    func makeBookmark(for url: URL, includingResourceValuesForKeys keys: Set<URLResourceKey>?) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: keys, relativeTo: nil)
    }

    func volumeProperties(in data: Data) -> AccessProbeVolume {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeURLKey, .volumeNameKey]
        let values = URL.resourceValues(forKeys: keys, fromBookmarkData: data)
        return AccessProbeVolume(
            uuid: values?.volumeUUIDString,
            url: values?.volume,
            name: values?.volumeName
        )
    }

    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> AccessProbeResolution {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return .resolved(url, stale: stale)
    }
}

private extension AccessProbeError {
    init(_ error: Error) {
        let nsError = error as NSError
        var underlyingErrors: [AccessProbeError] = []
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        while let error = underlying {
            underlyingErrors.append(AccessProbeError(domain: error.domain, code: error.code))
            underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.init(domain: nsError.domain, code: nsError.code, underlyingErrors: underlyingErrors)
    }
}
