import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

private let personalStoreRoot = ItemIdentityRoot(id: AccessRootID(), url: URL(fileURLWithPath: "/pictures-personal"))
private func personalRef(_ name: String, fileNumber: UInt64? = 1, root: ItemIdentityRoot = personalStoreRoot) -> PersonalImageRef {
    PersonalImageRef(fileURL: root.url.appendingPathComponent(name), root: root, fileNumber: fileNumber)!
}
private func personalStoreDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}
private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + seconds) }

@Test func personalImageStoreRecentsBoundOrderUnique() async throws {
    let base = personalStoreDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    for seed in UInt64(1)...20 {
        var rng = SplitMix64(seed: seed)
        let store = PersonalImageStore(url: base.appendingPathComponent("\(seed).json"))
        let refs = (0..<Int.random(in: 1...80, using: &rng)).map { personalRef("r\($0).jpg") }
        var oracle: [PersonalImageRef] = []
        for step in 0..<Int.random(in: 0...120, using: &rng) {
            let ref = refs.randomElement(using: &rng)!
            try await store.recordVisit(ref, at: at(Double(step)))
            oracle.removeAll { $0 == ref }; oracle.insert(ref, at: 0)
        }
        let recents = try await store.recents()
        #expect(recents.count == min(PersonalImageStore.recentLimit, oracle.count), "seed \(seed)")
        #expect(recents.map(\.ref) == Array(oracle.prefix(50)), "seed \(seed)")
        #expect(zip(recents, recents.dropFirst()).allSatisfy { $0.viewedAt >= $1.viewedAt }, "seed \(seed)")
        #expect(Set(recents.map(\.ref)).count == recents.count, "seed \(seed)")
    }
    #expect(PersonalImageStore.recentLimit == 50)
}

@Test func personalImageStoreRecentsOrderByVisitTime() async throws {
    let base = personalStoreDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let (a, b) = (personalRef("a.jpg"), personalRef("b.jpg"))
    let older = PersonalImageStore(url: base.appendingPathComponent("older.json"))
    try await older.recordVisit(a, at: at(3)); try await older.recordVisit(b, at: at(1))
    #expect(try await older.recents().map(\.ref) == [a, b])
    let tie = PersonalImageStore(url: base.appendingPathComponent("tie.json"))
    try await tie.recordVisit(a, at: at(4)); try await tie.recordVisit(b, at: at(4))
    #expect(try await tie.recents().map(\.ref) == [b, a])
    let back = PersonalImageStore(url: base.appendingPathComponent("back.json"))
    try await back.recordVisit(a, at: at(5)); try await back.recordVisit(b, at: at(6)); try await back.recordVisit(a, at: at(2))
    #expect(try await back.recents() == [PersonalImageVisit(ref: b, viewedAt: at(6)), PersonalImageVisit(ref: a, viewedAt: at(2))])
    #expect(try await back.recents().map(\.viewedAt) == [at(6), at(2)])
}

@Test func personalImageStoreRecentsBoundaries() async throws {
    let base = personalStoreDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = PersonalImageStore(url: base.appendingPathComponent("p.json"))
    #expect(try await store.recents().isEmpty)
    #expect(try await store.favorites().isEmpty)
    let refs = (0...50).map { personalRef("v\($0).jpg") }
    for (index, ref) in refs.prefix(50).enumerated() { try await store.recordVisit(ref, at: at(100 + Double(index))) }
    let full = try await store.recents()
    #expect(full.count == 50 && full.last?.ref == refs[0] && full.first?.ref == refs[49])
    try await store.recordVisit(refs[50], at: at(1))
    #expect(try await store.recents() == full)
    #expect(try await !store.recents().contains { $0.ref == refs[50] })
    try await store.recordVisit(refs[50], at: at(200))
    let shifted = try await store.recents()
    #expect(shifted.count == 50 && shifted.first?.ref == refs[50] && !shifted.contains { $0.ref == refs[0] })
}

@Test func personalImageStoreRevisitMovesToFrontAndRefreshesFingerprint() async throws {
    let base = personalStoreDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = PersonalImageStore(url: base.appendingPathComponent("p.json"))
    try await store.recordVisit(personalRef("a.jpg", fileNumber: 1), at: at(1))
    try await store.recordVisit(personalRef("b.jpg"), at: at(2))
    try await store.recordVisit(personalRef("a.jpg", fileNumber: 9), at: at(3))
    let recents = try await store.recents()
    #expect(recents.map(\.ref) == [personalRef("a.jpg"), personalRef("b.jpg")])
    #expect(recents.first?.viewedAt == at(3) && recents.first?.ref.fileNumber == 9)
}

@Test func personalImageStoreToggleFavoriteInvolution() async throws {
    let base = personalStoreDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = PersonalImageStore(url: base.appendingPathComponent("p.json"))
    let (a, b, c) = (personalRef("a.jpg"), personalRef("b.jpg"), personalRef("c.jpg"))
    #expect(try await store.toggleFavorite(a)); #expect(try await store.toggleFavorite(b))
    #expect(try await store.favorites() == [b, a])
    #expect(try await store.toggleFavorite(c))
    #expect(try await store.isFavorite(c.itemID))
    #expect(try await !store.toggleFavorite(personalRef("c.jpg", fileNumber: 42)))
    #expect(try await !store.isFavorite(c.itemID))
    #expect(try await store.favorites() == [b, a])
    #expect(try await !store.toggleFavorite(a)); #expect(try await !store.isFavorite(a.itemID))
    #expect(try await store.toggleFavorite(a)); #expect(try await store.isFavorite(a.itemID))
    #expect(try await store.favorites() == [a, b])
    try await store.recordVisit(c, at: at(1))
    #expect(try await !store.isFavorite(c.itemID))
    let otherRoot = ItemIdentityRoot(id: AccessRootID(), url: personalStoreRoot.url)
    #expect(try await store.toggleFavorite(personalRef("a.jpg", root: otherRoot)))
    #expect(try await store.favorites().count == 3)
    let many = PersonalImageStore(url: base.appendingPathComponent("many.json"))
    let refs = (0..<60).map { personalRef("f\($0).jpg") }
    for ref in refs { #expect(try await many.toggleFavorite(ref)) }
    #expect(try await many.favorites() == refs.reversed())
}

@Test func personalImageStoreRelaunchRoundTrip() async throws {
    let base = personalStoreDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let path = base.appendingPathComponent("support/personal-images.json")
    let store = PersonalImageStore(url: path)
    for name in ["x.jpg", "y.jpg", "z.jpg"] { _ = try await store.toggleFavorite(personalRef(name, fileNumber: 5)) }
    let times = [0.25, 1.125, 2.5, 3.0625, 4.75]
    for (index, time) in times.enumerated() {
        try await store.recordVisit(personalRef("v\(index).jpg", fileNumber: index == 2 ? nil : UInt64(index)), at: at(time))
    }
    let favorites = try await store.favorites(), recents = try await store.recents()
    let relaunched = PersonalImageStore(url: path)
    #expect(try await relaunched.favorites() == favorites)
    #expect(try await relaunched.favorites().map(\.fileNumber) == [5, 5, 5])
    let reread = try await relaunched.recents()
    #expect(reread == recents)
    #expect(reread.map(\.viewedAt) == times.reversed().map(at))
    #expect(reread.map(\.ref.fileNumber) == [4, 3, nil, 1, 0])
    #expect(await !relaunched.storeCorrupt)
}

@Test func personalImageStoreCorruptRecoversToSidecar() async throws {
    let fm = FileManager.default
    for bytes in [Data("{nope".utf8), Data(#"{"version":99,"favorites":[],"recents":[]}"#.utf8)] {
        let base = personalStoreDirectory()
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let path = base.appendingPathComponent("personal-images.json")
        let recovery = path.appendingPathExtension("recovered")
        try bytes.write(to: path)
        let store = PersonalImageStore(url: path)
        #expect(try await store.favorites().isEmpty)
        #expect(try await store.recents().isEmpty)
        #expect(await store.storeCorrupt)
        let (a, b) = (personalRef("a.jpg"), personalRef("b.jpg"))
        #expect(try await store.toggleFavorite(a))
        try await store.recordVisit(b, at: at(1))
        #expect(try Data(contentsOf: path) == bytes)
        #expect(fm.fileExists(atPath: recovery.path))
        let relaunched = PersonalImageStore(url: path)
        #expect(try await relaunched.favorites() == [a])
        #expect(try await relaunched.recents().map(\.ref) == [b])
        #expect(await relaunched.storeCorrupt)
        #expect(try await relaunched.toggleFavorite(b))
        #expect(try Data(contentsOf: path) == bytes)
        #expect(try await PersonalImageStore(url: path).favorites() == [b, a])
        try Data("broken recovery".utf8).write(to: recovery)
        let both = PersonalImageStore(url: path)
        #expect(try await both.favorites().isEmpty)
        #expect(try await both.toggleFavorite(a))
        #expect(try await PersonalImageStore(url: path).favorites() == [a])
        #expect(try Data(contentsOf: path) == bytes)
    }
}

@Test func personalImageStoreLeavesRecentFoldersUntouched() async throws {
    let fm = FileManager.default
    let base = personalStoreDirectory()
    defer { try? fm.removeItem(at: base) }
    let folders = RecentFolderStore(url: base.appendingPathComponent("recent-folders.json"))
    let first = RecentFolder(rootID: personalStoreRoot.id, url: personalStoreRoot.url, displayName: "pictures")
    let second = RecentFolder(rootID: AccessRootID(), url: base, displayName: "other")
    try await folders.add(first); try await folders.add(second)
    let before = try Data(contentsOf: base.appendingPathComponent("recent-folders.json"))
    let listed = try await folders.load()
    let store = PersonalImageStore(url: base.appendingPathComponent("personal-images.json"))
    _ = try await store.toggleFavorite(personalRef("a.jpg")); _ = try await store.toggleFavorite(personalRef("a.jpg"))
    for index in 0..<60 { try await store.recordVisit(personalRef("v\(index).jpg"), at: at(Double(index))) }
    try Data("{nope".utf8).write(to: base.appendingPathComponent("personal-images.json"))
    _ = try await PersonalImageStore(url: base.appendingPathComponent("personal-images.json")).toggleFavorite(personalRef("b.jpg"))
    #expect(try Data(contentsOf: base.appendingPathComponent("recent-folders.json")) == before)
    #expect(try await RecentFolderStore(url: base.appendingPathComponent("recent-folders.json")).load() == listed)
    #expect(try await store.recents().allSatisfy { $0.ref.rootID == personalStoreRoot.id && $0.ref.relativePath.hasSuffix(".jpg") })
}

@Test func personalImageStoreFileHoldsRefsOnly() async throws {
    let fm = FileManager.default
    let base = personalStoreDirectory()
    defer { try? fm.removeItem(at: base) }
    let path = base.appendingPathComponent("personal-images.json")
    let store = PersonalImageStore(url: path)
    _ = try await store.toggleFavorite(personalRef("a.jpg")); _ = try await store.toggleFavorite(personalRef("sub/b.jpg"))
    try await store.recordVisit(personalRef("c.jpg"), at: at(1)); try await store.recordVisit(personalRef("d.jpg", fileNumber: nil), at: at(2))
    try #require(fm.fileExists(atPath: path.path), "the store wrote its file")
    let data = try Data(contentsOf: path)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["version", "favorites", "recents"])
    #expect(object["version"] as? Int == 1)
    let favorites = try #require(object["favorites"] as? [[String: Any]])
    let recents = try #require(object["recents"] as? [[String: Any]])
    #expect(favorites.allSatisfy { Set($0.keys).isSubset(of: ["rootID", "relativePath", "fileNumber"]) })
    #expect(recents.allSatisfy { Set($0.keys) == ["ref", "viewedAt"] })
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains(personalStoreRoot.url.path) && !text.contains("/Users") && !text.contains("/private"))
    #expect(data.count < 2048)
}
