import Foundation
import PicseeCore

public enum ViewerInputNotice: Equatable, Sendable { case unsupported(String), rejected }
@MainActor public protocol ViewerInputHost: AnyObject {
    func openInputImage(_ url: URL, accessRequest: AccessRequest?)
    func showInputNotice(_ notice: ViewerInputNotice)
    func promptForInputFolder(_ folder: URL)
}
public enum ViewerInputProbeResult: Equatable, Sendable { case open(AccessRequest), unsupported, discarded }
public struct ViewerInputAdmission: Sendable {
    private let access: any AccessLeasing
    private let pipeline: any ImagePipeline
    private let maximumPixelSize: Int
    private let rootCovering: @Sendable (URL) async -> AccessRootID?
    public init(access: any AccessLeasing, pipeline: any ImagePipeline, maximumPixelSize: Int,
                rootCovering: @escaping @Sendable (URL) async -> AccessRootID?) {
        self.access = access; self.pipeline = pipeline; self.maximumPixelSize = maximumPixelSize
        self.rootCovering = rootCovering
    }
    @MainActor public func probe(_ url: URL, operation: AccessOperation) async -> ViewerInputProbeResult {
        do {
            let root = try await operation.wait { await rootCovering(url) }
            let request: AccessRequest = root.map { .root($0, file: url) } ?? .fileGrant(url)
            do {
                _ = try await operation.wait {
                    try await access.withLease(request) { lease in
                        try await pipeline.request(for: url, maximumPixelSize: maximumPixelSize,
                            identityRoot: lease.rootID.map { ItemIdentityRoot(id: $0, url: lease.url) })
                    }
                }
            } catch {
                try operation.check()
                if (error as? ImageLoadError)?.kind == .unsupportedFormat { return .unsupported }
            }
            return .open(request)
        } catch {
            return .discarded
        }
    }
}

extension ViewerSession {
    public func openInput(_ urls: [URL], operation: AccessOperation, admission: ViewerInputAdmission,
                          host: any ViewerInputHost) async {
        guard operation.isCurrent else { return }
        let input = ViewerInput.classify(urls)
        if case .single(let url) = input {
            let result = await admission.probe(url, operation: operation)
            guard operation.isCurrent else { return }
            if case .open(let request) = result { host.openInputImage(url, accessRequest: request) }
            else if result == .unsupported { host.showInputNotice(.unsupported(url.lastPathComponent)) }
        } else if case .rejected = input { host.showInputNotice(.rejected) }
    }
}
