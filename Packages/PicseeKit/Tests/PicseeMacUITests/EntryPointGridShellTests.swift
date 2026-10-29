import AppKit
import Testing
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@Test @MainActor func issue215GridComingSoonEntriesAreVisibleDisabledAndUnfocusable() {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 652),
                              preferencesStore: InMemoryDisplayPreferencesStore())
    shell.layoutSubtreeIfNeeded()
    let entries: [(EntryPoint, NSButton)] = [
        (.favorites, shell.favoritesButton),
        (.recents, shell.recentsButton),
        (.footerInfo, shell.infoButton),
        (.footerDisplay, shell.displayButton),
    ]

    for (entry, button) in entries {
        #expect(entry.state == .comingSoon)
        #expect(button.superview != nil)
        #expect(!button.isHidden)
        #expect(!button.isEnabled)
        #expect(!button.acceptsFirstResponder)
        #expect(!button.canBecomeKeyView)
        #expect(button.action == nil)
        #expect(button.keyEquivalent.isEmpty)
        #expect(button.title.contains("Coming Soon"))
        #expect(button.accessibilityLabel()?.contains("Coming Soon") == true)
    }
}
