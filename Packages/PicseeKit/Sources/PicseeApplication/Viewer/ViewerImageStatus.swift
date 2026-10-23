import PicseeCore

public enum ViewerImageFailure: Equatable, Sendable {
    case corruptImage, unsupportedFormat, resourceLimit, sourceChanged, access
}

/// The single presentation state consumed by native state surfaces.
public enum ViewerImageStatus: Equatable, Sendable {
    case empty, loading(String), showing, detailLimited, failed(ViewerImageFailure, String)

    public init(phase: ViewerImagePhase, fileName: String, failure: (any Error)?) {
        switch phase {
        case .idle: self = .empty
        case .opening: self = .loading(fileName)
        case .refining, .settled: self = .showing
        case .detailLimited: self = .detailLimited
        case .failed:
            let kind: ViewerImageFailure
            switch (failure as? ImageLoadError)?.kind {
            case .corruptImage: kind = .corruptImage
            case .unsupportedFormat: kind = .unsupportedFormat
            case .resourceLimit: kind = .resourceLimit
            case .sourceChanged: kind = .sourceChanged
            case .cancelled: self = .empty; return
            case nil: kind = .access
            }
            self = .failed(kind, fileName)
        }
    }
}

extension ViewerSession {
    public var imageStatus: ViewerImageStatus {
        ViewerImageStatus(phase: imageLoader.phase,
            fileName: imageLoader.fileURL?.lastPathComponent ?? "", failure: imageLoader.failure)
    }
}
