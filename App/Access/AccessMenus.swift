import AppKit
import PicseeCore

@MainActor final class RecentFolderMenuTarget: NSObject {
    var onOpen: ((RecentFolder) -> Void)?
    @objc func open(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? RecentFolder else { return }
        onOpen?(folder)
    }
}

@MainActor final class AccessNavigationMenuTarget: NSObject, NSMenuItemValidation {
    static let shared = AccessNavigationMenuTarget()
    @objc func invoke(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = CommandID(rawValue: raw) else { return }
        (NSApp.keyWindow?.windowController as? CanvasWindowController)?.route(id, from: .menu)
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        (NSApp.keyWindow?.windowController as? CanvasWindowController)?.canNavigate ?? false
    }
}
