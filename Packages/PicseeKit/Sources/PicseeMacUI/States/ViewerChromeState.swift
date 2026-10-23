import PicseeApplication

extension ViewerChromeOverlay {
    /// Refresh the label from the load identity, which is retired on cancellation.
    public func refresh(session: ViewerSession) {
        refresh(filename: session.imageLoader.fileURL?.lastPathComponent)
    }
}
