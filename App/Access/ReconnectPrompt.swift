import AppKit

/// Untested native sheets/panels; recovery decisions are package-tested.
@MainActor enum ReconnectPrompt {
    enum Selection { case reconnect(URL), anotherFolder(URL) }

    static func request(displayName: String, lastKnownFolder: URL, window: NSWindow,
                        isCurrent: @escaping @MainActor () -> Bool,
                        selected: @escaping @MainActor (Selection) -> Void) {
        guard window.attachedSheet == nil, isCurrent() else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Can’t Access This Folder")
        alert.informativeText = String(format: String(localized: "Access may have expired. Choose “%@” again."), displayName)
        alert.addButton(withTitle: String(localized: "Choose Folder Again…"))
        alert.addButton(withTitle: String(localized: "Choose Another Folder…"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in
            alert.window.orderOut(nil)
            guard isCurrent(), response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            let another = response == .alertSecondButtonReturn
            DispatchQueue.main.async {
                guard isCurrent(), window.attachedSheet == nil else { return }
                let panel = NSOpenPanel()
                panel.title = String(localized: another ? "Grant Folder Access" : "Reconnect Folder")
                panel.prompt = String(localized: another ? "Grant Folder" : "Choose Folder Again…")
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                // The powerbox owns fallback for a missing directory; no unleased stat.
                panel.directoryURL = lastKnownFolder.deletingLastPathComponent()
                panel.beginSheetModal(for: window) { response in
                    panel.orderOut(nil)
                    guard response == .OK, let url = panel.url, isCurrent() else { return }
                    DispatchQueue.main.async {
                        guard isCurrent() else { return }
                        selected(another ? .anotherFolder(url) : .reconnect(url))
                    }
                }
            }
        }
    }
}
