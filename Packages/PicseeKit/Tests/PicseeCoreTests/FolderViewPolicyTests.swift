import Foundation
import Testing
import PicseeCore

private let viewPolicyRoot = ItemIdentityRoot(id: AccessRootID(), url: URL(fileURLWithPath: "/view-policy"))
private let viewPolicyVersion = SnapshotVersion(rootID: viewPolicyRoot.id, folder: viewPolicyRoot.url, generation: 1)

private func viewPolicyEntry(_ path: String, modified: Date? = nil, size: Int64? = nil) -> FolderEntry {
    FolderEntry(url: viewPolicyRoot.url.appendingPathComponent(path), root: viewPolicyRoot,
        modificationDate: modified, fileSize: size)
}

private func viewPolicyNames(_ entries: [FolderEntry], conditions: FolderViewConditions) -> [String] {
    FolderSnapshot(version: viewPolicyVersion, entries: entries, isComplete: true)
        .applying(conditions).entries.map(\.relativePath)
}

@Test func folderViewPolicySortsEveryKeyWithDeterministicTiesAndMissingLast() {
    let early = Date(timeIntervalSince1970: 10), late = Date(timeIntervalSince1970: 20)
    let entries = [
        viewPolicyEntry("z/img2.JPG", modified: late, size: 20),
        viewPolicyEntry("img10.png", modified: nil, size: nil),
        viewPolicyEntry("a/img2.jpg", modified: early, size: 10),
        viewPolicyEntry("img3", modified: early, size: 10),
    ]

    #expect(viewPolicyNames(entries, conditions: .init()) == ["a/img2.jpg", "z/img2.JPG", "img3", "img10.png"])
    #expect(viewPolicyNames(entries, conditions: .init(direction: .descending)) == ["img10.png", "img3", "a/img2.jpg", "z/img2.JPG"])
    #expect(viewPolicyNames(entries, conditions: .init(sort: .modificationDate)) == ["a/img2.jpg", "img3", "z/img2.JPG", "img10.png"])
    #expect(viewPolicyNames(entries, conditions: .init(sort: .modificationDate, direction: .descending)) == ["z/img2.JPG", "a/img2.jpg", "img3", "img10.png"])
    #expect(viewPolicyNames(entries, conditions: .init(sort: .size)) == ["a/img2.jpg", "img3", "z/img2.JPG", "img10.png"])
    #expect(viewPolicyNames(entries, conditions: .init(sort: .size, direction: .descending)) == ["z/img2.JPG", "a/img2.jpg", "img3", "img10.png"])
    #expect(viewPolicyNames(entries, conditions: .init(sort: .type)) == ["img3", "a/img2.jpg", "z/img2.JPG", "img10.png"])
    #expect(viewPolicyNames(entries, conditions: .init(sort: .type, direction: .descending)) == ["img10.png", "a/img2.jpg", "z/img2.JPG", "img3"])
    #expect(entries.map(\.normalizedExtension) == ["jpg", "png", "jpg", ""])
}

@Test func folderViewPolicyFiltersNormalizedExtensionsWithoutMutatingSource() {
    let entries = [viewPolicyEntry("img2.PNG"), viewPolicyEntry("img1.JpG"), viewPolicyEntry("README")]
    let source = FolderSnapshot(version: viewPolicyVersion, entries: entries, isComplete: false)
    let conditions = FolderViewConditions(selectedExtensions: ["PNG"])
    #expect(conditions.selectedExtensions == ["png"])
    let filtered = source.applying(conditions)
    #expect(filtered.entries.map(\.relativePath) == ["img2.PNG"])
    #expect(filtered.navigationEntries == filtered.entries)
    #expect(filtered.navigationIndex(for: entries[0].itemID) == 0)
    #expect(filtered.navigationIndex(for: entries[1].itemID) == nil)
    #expect(!filtered.isComplete && filtered.version == source.version)
    #expect(source.entries.count == 3 && source.navigationEntries.count == 3)
    #expect(source.applying(.init()).entries == source.entries)
    #expect(source.applying(.init(selectedExtensions: [])).entries.isEmpty)
    var directlyMutated = FolderViewConditions()
    directlyMutated.selectedExtensions = ["JPG"]
    #expect(source.applying(directlyMutated).entries.map(\.relativePath) == ["img1.JpG"])
}

@Test func folderViewPolicyMissingMetadataTiesUseNaturalNameThenPath() {
    let entries = [viewPolicyEntry("z/img2.png"), viewPolicyEntry("img10.png"), viewPolicyEntry("a/img2.png")]
    for key in [FolderSortKey.modificationDate, .size] {
        for direction in [FolderSortDirection.ascending, .descending] {
            #expect(viewPolicyNames(entries, conditions: .init(sort: key, direction: direction)) == [
                "a/img2.png", "z/img2.png", "img10.png"])
        }
    }
}
