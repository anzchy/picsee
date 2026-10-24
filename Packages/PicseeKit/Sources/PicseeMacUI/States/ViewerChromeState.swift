import Foundation
import PicseeApplication

extension ViewerChromeOverlay {
    /// Refresh the label from the load identity, which is retired on cancellation.
    public func refresh(session: ViewerSession) {
        let position = session.folderScan?.completedImageCount.map {
            String(format: String(localized: "Images: %lld"), Int64($0))
        }
        refresh(filename: session.imageLoader.fileURL?.lastPathComponent, position: position)
    }
}
