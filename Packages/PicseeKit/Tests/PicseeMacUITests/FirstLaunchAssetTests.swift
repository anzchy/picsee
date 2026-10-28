import AppKit
import CryptoKit
import Testing
@testable import PicseeMacUI

@Test @MainActor func p316B4BundledSamplesMatchPinnedBytes() throws {
    let expected = [
        "alley": "3168c66cbe2b8615d4a2d59f2872f41601265bb2309c0f3d1e8db32628f19001",
        "lakeside": "ef934fd0f43fa7e7d1cc3e0629a60f3d120ca4fdd7455aaf5652463d7f4cc9c6",
        "temple": "9b126270484f8782b26c8913163f521567f07324b3764bec078bab1ffb80fa8a",
        "hillside": "955348ffdc1ce2b0cdd757971a4159277457d0158a109a6d7b83f3aac4ffb8f4",
        "lakehouse": "ca9b44fc2170ea0ac07e3aee6182e9dbf8757200197dc57e1ad464f1c4b48593",
        "gate": "b8e7a6dffa9ecdce9943b13c20380692ad12b18e43d72aca484088bd3315f325"
    ]
    var total = 0
    for (name, hash) in expected {
        let url = try #require(FirstLaunchView.sampleURL(name: name))
        let data = try Data(contentsOf: url)
        total += data.count
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash)
    }
    #expect(total == 353_257)
}

@Test @MainActor func p316B4DecodeFailureLeavesNoEmptyPhotoFrame() async throws {
    _ = NSApplication.shared
    let invalid = URL(fileURLWithPath: "/picsee-b4-missing-photo.jpg")
    let view = FirstLaunchView(frame: NSRect(x: 0, y: 0, width: 960, height: 640),
                               openButton: ViewerStateButton(frame: .zero), sampleURLs: ["alley": invalid])
    view.layoutSubtreeIfNeeded()
    let alley = try #require(view.subviews.first { $0.accessibilityIdentifier() == "first-launch.print.alley" })
    #expect(alley.layer?.sublayers?.allSatisfy(\.isHidden) == true)
    for _ in 0..<100 where !view.sampleLoadCompleted {
        try await Task.sleep(for: .milliseconds(10))
    }
    view.layoutSubtreeIfNeeded()
    #expect(view.sampleLoadCompleted)
    #expect(alley.isHidden)
    #expect((alley as? NSImageView)?.image == nil)
}


@Test func p316B4CatalogContainsApprovedEnglishAndChineseCopy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
    let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: Any])
    let approved = [
        ("Drop a photo folder here", "把照片文件夹拖到这里"),
        ("Release to open", "松开即可打开"),
        ("Choose Folder…", "选择文件夹…"),
        ("or press ⌘O", "或按 ⌘O"),
        ("Folder", "文件夹"),
        ("One or more images", "单张或多张图片"),
        ("Common image formats", "常见图片格式")
    ]
    for (english, chinese) in approved {
        let entry = try #require(strings[english] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        func value(_ language: String) -> String? {
            let item = localizations[language] as? [String: Any]
            let unit = item?["stringUnit"] as? [String: Any]
            return unit?["value"] as? String
        }
        #expect(value("en") == english)
        #expect(value("zh-Hans") == chinese)
    }
}
