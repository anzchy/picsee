import Foundation
import os
import PicseeApplication
import PicseeCore
import PicseeInfrastructure

struct WindowInspectorReader: InspectorMetadataReading {
    let services: Task<AccessServices, Error>
    func read(_ url: URL, access: AccessRequest) async throws -> InspectorMetadata {
        do {
            let files = try await services.value.files
            let request: AccessRequest
            if case .fileGrant = access, let root = await files.rootCovering(url) {
                request = .root(root, file: url)
            } else {
                request = access
            }
            try Task.checkCancellation()
            return try await ImageIOInspectorMetadataReader(access: files).read(url, access: request)
        } catch {
            if !Task.isCancelled {
                let outcome = (error as? InspectorReadError) == .noPermission ? "no-permission" : "unreadable"
                Logger(subsystem: "io.github.anzchy.picsee", category: "inspector")
                    .notice("Metadata read outcome=\(outcome, privacy: .public)")
            }
            throw error
        }
    }
}
