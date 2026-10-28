import Foundation
import Testing
@testable import PicseeInfrastructure

private let probeURL = URL(fileURLWithPath: "/Volumes/Photos/2026", isDirectory: true)

private func probeFacts(
    uuid: String? = "volume-a",
    volumeName: String? = "Photos",
    mountedVolumes: [AccessProbeVolume]? = nil,
    resolution: AccessProbeResolution = .resolved(probeURL, stale: false),
    scopeStarted: Bool? = true,
    listing: AccessProbeDirectoryListing? = .succeeded(entryCount: 3),
    isInTrash: Bool = false
) -> AccessProbeFacts {
    AccessProbeFacts(
        volume: AccessProbeVolume(uuid: uuid, url: URL(fileURLWithPath: "/Volumes/Photos"), name: volumeName),
        mountedVolumes: mountedVolumes ?? [AccessProbeVolume(uuid: "volume-a", url: nil, name: "Photos")],
        resolution: resolution,
        scopeStarted: scopeStarted,
        listing: listing,
        isInTrash: isInTrash
    )
}

@Test func accessCauseMatchesVolumesByUUIDOnly() {
    let sameNameOtherVolume = AccessProbeVolume(uuid: "volume-b", url: nil, name: "Photos")
    let result = AccessCauseClassifier.classify(probeFacts(mountedVolumes: [sameNameOtherVolume]))
    #expect(result.cause == .diskNotConnected)
    #expect(!result.isInTrash)
}

@Test func accessCauseRejectsNilUUIDForDiskCase() {
    let result = AccessCauseClassifier.classify(probeFacts(
        uuid: nil,
        mountedVolumes: [],
        resolution: .failed(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
        scopeStarted: nil,
        listing: nil
    ))
    #expect(result.cause == .unknown)
}

@Test func accessCauseMountedVolumeWithFailedResolutionIsNotFound() {
    let result = AccessCauseClassifier.classify(probeFacts(
        resolution: .failed(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
        scopeStarted: nil,
        listing: nil
    ))
    #expect(result.cause == .notFound)
}

@Test(arguments: [
    AccessProbeError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
    AccessProbeError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
    AccessProbeError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
])
func accessCausePermissionRefusalIsAccessExpired(error: AccessProbeError) {
    let result = AccessCauseClassifier.classify(probeFacts(listing: .failed(error)))
    #expect(result.cause == .accessExpired)
}

@Test(arguments: [Int(EPERM), Int(EACCES)])
func accessCauseUnderlyingPermissionRefusalIsAccessExpired(code: Int) {
    let error = AccessProbeError(
        domain: NSCocoaErrorDomain,
        code: NSFileReadUnknownError,
        underlyingErrors: [AccessProbeError(domain: NSPOSIXErrorDomain, code: code)]
    )
    let result = AccessCauseClassifier.classify(probeFacts(listing: .failed(error)))

    #expect(result.cause == .accessExpired)
}

@Test func accessCauseOtherListingFailureIsUnknown() {
    let result = AccessCauseClassifier.classify(probeFacts(
        listing: .failed(AccessProbeError(domain: NSPOSIXErrorDomain, code: Int(EIO)))
    ))
    #expect(result.cause == .unknown)
}

@Test func accessCauseStaleResolvedAndListedBookmarkIsReadable() {
    let result = AccessCauseClassifier.classify(probeFacts(resolution: .resolved(probeURL, stale: true)))
    #expect(result.cause == .readable)
}

@Test func accessCauseTrashIsSeparateAndNeverReadable() {
    let result = AccessCauseClassifier.classify(probeFacts(
        resolution: .resolved(probeURL, stale: true),
        isInTrash: true
    ))
    #expect(result.cause == .unknown)
    #expect(result.isInTrash)
}

@Test func accessCauseDoesNotUseScopeAloneAsReadabilityEvidence() {
    let startedWithoutListing = AccessCauseClassifier.classify(probeFacts(listing: nil))
    let listedWithoutStartedScope = AccessCauseClassifier.classify(probeFacts(scopeStarted: false))
    #expect(startedWithoutListing.cause == .unknown)
    #expect(listedWithoutStartedScope.cause == .readable)
}
