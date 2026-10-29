import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

/// A watched refresh or a recents reload repeats the same page-22 request; keyboard focus must stay on its control.
@Test @MainActor func page22RepeatedRequestKeepsFocusedControl() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 1280, height: 772),
                              preferencesStore: InMemoryDisplayPreferencesStore())
    window.contentView?.addSubview(shell)
    let folder = URL(fileURLWithPath: "/focus/A")
    shell.showFolderTree(current: GridSidebarFolder(url: folder), parent: nil,
                         children: ["x", "y"].map { GridSidebarFolder(url: folder.appendingPathComponent($0)) })
    let now = Date(timeIntervalSince1970: 1_615_809_600)
    let recent = RecentFolder(rootID: AccessRootID(), url: URL(fileURLWithPath: "/focus/R"), displayName: "R",
                              openedAt: now.addingTimeInterval(-86_400))
    shell.setEmptyFolderState(true, recents: [recent], now: now)
    let tile = try #require(shell.emptyFolderView.tiles.last)
    #expect(window.makeFirstResponder(tile))
    shell.setEmptyFolderState(true, recents: [recent], now: now)
    shell.showFolderTree(current: GridSidebarFolder(url: folder), parent: nil,
                         children: ["x", "y"].map { GridSidebarFolder(url: folder.appendingPathComponent($0)) })
    #expect(shell.emptyFolderView.tiles.last === tile)
    #expect(window.firstResponder === tile)
    shell.showFolderTree(current: GridSidebarFolder(url: folder), parent: nil,
                         children: ["x", "y", "z"].map { GridSidebarFolder(url: folder.appendingPathComponent($0)) })
    #expect(shell.emptyFolderView.tiles.map { $0.url.lastPathComponent } == ["x", "y", "z"])
}
