import Foundation
import Testing

#if DEBUG
@MainActor
struct AccessProbeLaunchTests {
    @Test func runsOnlyWithExplicitLaunchArgument() {
        var runCount = 0
        let normal = AccessProbeRunner.runIfRequested(arguments: ["Picsee"], runProbe: {
            runCount += 1
        }, terminate: {})
        let similar = AccessProbeRunner.runIfRequested(
            arguments: ["Picsee", "-PicseeAccessProbeExtra"],
            runProbe: { runCount += 1 },
            terminate: {}
        )
        let requested = AccessProbeRunner.runIfRequested(
            arguments: ["Picsee", "-PicseeAccessProbe"],
            runProbe: { runCount += 1 },
            terminate: {}
        )

        #expect(!normal)
        #expect(!similar)
        #expect(requested)
        #expect(runCount == 1)
    }

    @Test func probeLaunchTerminatesWithoutConstructingProductAccessServices() {
        var terminated = false
        let constructsProductAccessServices: Bool
        if AccessProbeRunner.runIfRequested(
            arguments: ["Picsee", "-PicseeAccessProbe"],
            runProbe: {},
            terminate: { terminated = true }
        ) {
            constructsProductAccessServices = false
        } else {
            constructsProductAccessServices = true
        }

        #expect(terminated)
        #expect(!constructsProductAccessServices)
    }

    @Test func storesBothBookmarkKindsAndWritesJSONLOnEveryRun() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let folder = root.appendingPathComponent("Photos", isDirectory: true)
        let container = root.appendingPathComponent("Probe", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var selectionCount = 0

        let firstOutput = try AccessProbeRunner.run(containerURL: container) {
            selectionCount += 1
            return [folder]
        }
        let secondOutput = try AccessProbeRunner.run(containerURL: container) {
            selectionCount += 1
            return []
        }

        #expect(selectionCount == 1)
        #expect(firstOutput == secondOutput)
        #expect(fileManager.fileExists(atPath: container.appendingPathComponent("bookmarks.json").path))
        for output in [firstOutput, secondOutput] {
            let lines = try String(contentsOf: output, encoding: .utf8)
                .split(separator: "\n")
            #expect(lines.count == 2)
            let objects = try lines.map { line in
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
            #expect(Set(objects.compactMap { $0?["bookmarkKind"] as? String }) == Set(["plain", "enriched"]))
            #expect(objects.allSatisfy { $0?["report"] is [String: Any] })
        }
    }
}
#endif
