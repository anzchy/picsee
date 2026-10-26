import Foundation
import PicseeApplication
import PicseeCore
import PicseeInfrastructure

struct WindowInspectorReader: InspectorMetadataReading {
    let services: Task<AccessServices, Error>
    func read(_ url: URL, access: AccessRequest) async throws -> InspectorMetadata {
        let files = try await services.value.files
        return try await ImageIOInspectorMetadataReader(access: files).read(url, access: access)
    }
}
