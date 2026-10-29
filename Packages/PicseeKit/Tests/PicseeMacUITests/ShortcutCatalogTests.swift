import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@MainActor func issue219Menu() -> NSMenu {
    let main = NSMenu(title: "Picsee")
    func submenu(_ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
        return menu
    }
    func add(_ title: String, _ key: String, to menu: NSMenu, modifiers: NSEvent.ModifierFlags = [.command]) {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
    }
    let app = submenu("Picsee")
    add("Settings…", ",", to: app)
    add("Hide Picsee", "h", to: app)
    add("Hide Others", "h", to: app, modifiers: [.option, .command])
    add("Quit Picsee", "q", to: app)
    let file = submenu("File")
    add("Open…", "o", to: file)
    add("Close", "w", to: file)
    let edit = submenu("Edit")
    add("Undo", "z", to: edit)
    add("Redo", "z", to: edit, modifiers: [.command, .shift])
    let view = submenu("View")
    add("Search current folder", "f", to: view)
    add("Hide sidebar", "s", to: view, modifiers: [.control, .command])
    add("Enter Full Screen", "f", to: view, modifiers: [.control, .command])
    let window = submenu("Window")
    add("Minimize", "m", to: window)
    return main
}

private let issue219ExpectedRows: [(String, [String], [String], [String], [String])] = [
    ("files", ["command:open"], ["⌘", "O"], ["Open…"], ["打开…"]),
    ("files", ["menu:Settings…"], ["⌘", ","], ["Settings…"], ["设置…"]),
    ("files", ["menu:Close"], ["⌘", "W"], ["Close Window"], ["关闭窗口"]),
    ("files", ["menu:Minimize"], ["⌘", "M"], ["Minimize"], ["最小化"]),
    ("files", ["menu:Hide Picsee"], ["⌘", "H"], ["Hide picsee"], ["隐藏 picsee"]),
    ("files", ["menu:Hide Others"], ["⌥", "⌘", "H"], ["Hide Others"], ["隐藏其他"]),
    ("files", ["menu:Quit Picsee"], ["⌘", "Q"], ["Quit picsee"], ["退出 picsee"]),
    ("grid", ["key:grid-arrows"], ["←", "→", "↑", "↓"], ["Move Current Item"], ["移动当前项"]),
    ("grid", ["command:preview"], ["Space"], ["Preview Current Item"], ["用大图查看当前项"]),
    ("grid", ["command:enter"], ["Return"], ["Open Current Item"], ["打开当前项"]),
    ("grid", ["menu:Search current folder"], ["⌘", "F"], ["Search Current Folder"], ["搜索当前文件夹"]),
    ("grid", ["menu:Hide sidebar"], ["⌃", "⌘", "S"], ["Show / Hide Sidebar"], ["显示 / 隐藏侧栏"]),
    ("viewer", ["command:previous", "command:next"], ["←", "→"], ["Previous / Next Image"], ["上一张 / 下一张"]),
    ("viewer", ["command:escape"], ["Esc"], ["Return to Grid"], ["回到网格"]),
    ("viewer", ["command:fit"], ["0"], ["Fit Window"], ["适应窗口"]),
    ("viewer", ["command:actualPixels"], ["1"], ["Actual Pixels"], ["实际像素"]),
    ("viewer", ["command:zoomIn", "command:zoomOut"], ["+", "−"], ["Zoom In / Out"], ["放大 / 缩小"]),
    ("viewer", ["key:viewer-tab"], ["Tab"], ["Recall Tools"], ["唤回工具"]),
    ("viewer", ["command:inspector"], ["⌘", "I"], ["Image Information"], ["图片信息"]),
    ("viewer", ["menu:Enter Full Screen"], ["⌃", "⌘", "F"], ["Enter / Exit Full Screen"], ["进入 / 退出全屏"]),
]

@MainActor private func issue219Flatten(_ catalog: ShortcutCatalog) -> [(String, [String], [String], String)] {
    catalog.cards.flatMap { card in
        card.rows.map { (card.id.rawValue, $0.sources.map(\.id), $0.keycaps, $0.name) }
    }
}

@Test @MainActor func issue219ShortcutCatalogMatchesLiveSourcesAndKeycaps() throws {
    let catalog = ShortcutCatalog(menu: issue219Menu(), language: .english)
    let actual = issue219Flatten(catalog)
    #expect(actual.count == issue219ExpectedRows.count)
    for (row, expected) in zip(actual, issue219ExpectedRows) {
        #expect(row.0 == expected.0)
        #expect(row.1 == expected.1)
        #expect(row.2 == expected.2)
        #expect(row.3 == expected.3[0])
    }
    #expect(catalog.cards.map(\.title) == ["Files & Windows", "Grid", "Image Viewer"])
    #expect(catalog.cards.map(\.when) == ["Anytime", "While Browsing a Folder", "While Viewing One Image"])
}

@Test @MainActor func issue219ShortcutCatalogUsesSimplifiedChinese() {
    let catalog = ShortcutCatalog(menu: issue219Menu(), language: .simplifiedChinese)
    let actual = issue219Flatten(catalog)
    #expect(actual.count == issue219ExpectedRows.count)
    for (row, expected) in zip(actual, issue219ExpectedRows) {
        #expect(row.3 == expected.4[0])
    }
    #expect(catalog.cards.map(\.title) == ["文件与窗口", "网格", "大图"])
    #expect(catalog.cards.map(\.when) == ["任何时候", "浏览文件夹时", "查看一张图片时"])
}

@Test @MainActor func issue219ShortcutCatalogFollowsImplementedFlagAndMenuAvailability() throws {
    let menu = issue219Menu()
    let settings = try #require(menu.items.first { $0.title == "Picsee" }?.submenu?.items.first { $0.title == "Settings…" })
    settings.keyEquivalent = ""
    let catalog = ShortcutCatalog(menu: menu, implementedCommands: Set(CommandID.allCases).subtracting([.fit, .inspector]), language: .english)
    let sources = issue219Flatten(catalog).flatMap(\.1)
    #expect(!sources.contains("command:fit"))
    #expect(!sources.contains("command:inspector"))
    #expect(!sources.contains("menu:Settings…"))
    #expect(sources.contains("command:open"))
    #expect(sources.contains("menu:Search current folder"))
    #expect(sources.filter { $0 == "command:open" }.count == 1)
    #expect(sources.contains("menu:Undo") == false)
    #expect(sources.contains("menu:Redo") == false)
}
