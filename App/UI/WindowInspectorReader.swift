import Foundation
import os
import PicseeApplication
import PicseeCore
import PicseeInfrastructure

struct WindowInspectorReader: InspectorMetadataReading {
    let services: Task<AccessServices, Error>
    func read(_ url: URL, access: AccessRequest) async throws -> InspectorMetadata {
        do {
            let services = try await services.value
            let files = services.files
            let request: AccessRequest
            if case .fileGrant = access, let root = await files.rootCovering(url) {
                request = .root(root, file: url)
            } else {
                request = access
            }
            let context: AccessMonitor.ReadContext?
            if case .root(let id, _) = request { context = try await services.monitor.readContext(for: id) }
            else { context = nil }
            do {
                try Task.checkCancellation()
                try context?.permit.check()
                let metadata = try await ImageIOInspectorMetadataReader(access: files).read(url, access: request)
                try context?.permit.check()
                return metadata
            } catch {
                if let context, !Task.isCancelled, !(error is CancellationError), case .root(let id, _) = request {
                    await services.monitor.reportReadFailure(id, from: context.stamp)
                }
                throw error
            }
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
