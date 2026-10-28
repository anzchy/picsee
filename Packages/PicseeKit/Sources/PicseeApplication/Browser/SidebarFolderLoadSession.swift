import Foundation
import PicseeCore

@MainActor public final class SidebarFolderLoadSession {
    private let browser: SidebarFolderBrowser
    private var task: Task<Void, Never>?
    public init(browser: SidebarFolderBrowser) { self.browser = browser }
    public func start(folder: URL, rootID: AccessRootID,
        onRows: @escaping @MainActor ([URL], URL?) -> Void,
        onCount: @escaping @MainActor (URL, Int) -> Void) {
        task?.cancel()
        let browser = self.browser
        task = Task(priority: .utility) {
            do {
                let children = try await browser.children(in: folder, rootID: rootID)
                let parent = try? await browser.parent(in: folder, rootID: rootID)
                try Task.checkCancellation()
                onRows(children, parent ?? nil)
                for child in children {
                    try Task.checkCancellation()
                    if let count = try? await browser.imageCount(in: child, rootID: rootID) {
                        try Task.checkCancellation()
                        onCount(child, count)
                    }
                }
            } catch { /* Failed listing or counting leaves unknown data blank. */ }
        }
    }
    public func cancel() { task?.cancel(); task = nil }
    deinit { task?.cancel() }
}
