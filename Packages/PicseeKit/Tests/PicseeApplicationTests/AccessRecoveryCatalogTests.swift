import Foundation
import Testing

private struct RecoveryCatalog: Decodable {
    struct Record: Decodable {
        struct Translation: Decodable {
            struct Unit: Decodable { let value: String }
            let stringUnit: Unit?
        }
        let localizations: [String: Translation]?
    }
    let strings: [String: Record]
    func value(_ key: String, language: String) -> String? {
        strings[key]?.localizations?[language]?.stringUnit?.value
    }
}

private func recoveryCatalog() throws -> RecoveryCatalog {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
    return try JSONDecoder().decode(RecoveryCatalog.self, from: data)
}

@Test func p201RecoveryCatalogCopyMatchesBothLanguagesExactly() throws {
    let catalog = try recoveryCatalog()
    let copy = [
        ("Can’t Access This Folder", "无法访问这个文件夹"),
        ("Access may have expired. Choose “%@” again.", "访问权限可能已失效，请重新选择“%@”。"),
        ("Choose Folder Again…", "重新选择文件夹…"),
        ("Choose Another Folder…", "选择其他文件夹…"),
        ("Reconnect Folder", "重新连接文件夹"),
        ("Cancel", "取消")
    ]
    for (english, chinese) in copy {
        #expect(catalog.value(english, language: "en") == english)
        #expect(catalog.value(english, language: "zh-Hans") == chinese)
    }
}

@Test(arguments: ["en", "zh-Hans"], ["Holiday 2026", "100% Photos"])
func p201RecoveryCatalogFormatsFolderNameWithoutInterpretingItsPercent(language: String, name: String) throws {
    let catalog = try recoveryCatalog()
    let format = try #require(catalog.value("Access may have expired. Choose “%@” again.", language: language))
    #expect(format.components(separatedBy: "%@").count - 1 == 1)
    let expected = language == "en"
        ? "Access may have expired. Choose “\(name)” again."
        : "访问权限可能已失效，请重新选择“\(name)”。"
    #expect(String(format: format, name) == expected)
}
