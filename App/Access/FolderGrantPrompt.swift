import AppKit

@MainActor enum FolderGrantPrompt {
    static func request(folder: URL, window: NSWindow, mismatch: Bool = false,
                        selected: @escaping (URL) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: mismatch ? "Folder Does Not Contain This Image" : "Browsing Needs Folder Access")
        alert.informativeText = String(format: String(localized: "To browse images in “%@”, grant access to its folder."), folder.lastPathComponent)
        alert.addButton(withTitle: String(localized: "Grant Folder…"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let panel = NSOpenPanel()
            panel.title = String(localized: "Grant Folder Access")
            panel.prompt = String(localized: "Grant Folder")
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                // Completion can run while the panel is still attached. Let AppKit
                // finish ending it before the caller can present a mismatch sheet.
                panel.orderOut(nil)
                DispatchQueue.main.async { selected(url) }
            }
        }
    }
}
