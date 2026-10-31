import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

private let i315Samples = ["alley", "lakeside", "hillside", "gate", "temple", "lakehouse"]
private let i315Missing = URL(fileURLWithPath: "/picsee-i315-missing.jpg")

@MainActor private func i315Launch(_ urls: [String: URL]?) async -> FirstLaunchView {
    _ = NSApplication.shared
    let view = FirstLaunchView(frame: NSRect(x: 0, y: 0, width: 960, height: 640),
                               openButton: ViewerStateButton(frame: .zero), sampleURLs: urls)
    view.pinAccessibility()
    await waitForSamples(view)
    return view
}

@Test @MainActor func i315WallReplacesPrintsAndStack() throws {
    let scene = StatesScene(width: 960)
    defer { scene.window.close() }
    scene.state.display(.empty)
    scene.state.layoutSubtreeIfNeeded()
    let home = try launch(in: scene)
    #expect(scene.state.textLines == ["Drop a photo folder here", "or press ⌘O", "Folder", "One or more images", "Common image formats"])
    #expect(scene.state.buttons.map(\.title) == ["Choose Folder…"])
    let ids = wallTestIdentifiers(in: scene.state)
    #expect(!ids.contains("first-launch.stack"), "stack still composed")
    #expect(ids.filter { $0.hasPrefix("first-launch.print") }.isEmpty, "edge prints still composed")
    let wall = try #require(wallView(home), "first-launch.wall missing")
    #expect(wall.isDescendant(of: home))
    let names = wall.layer?.sublayers?.compactMap(\.name) ?? []
    #expect(names.contains("first-launch.wall.tiles"))
    #expect(names.contains("first-launch.wall.scrim"))
}

@Test @MainActor func i315WallTilesUseOnlyBundledSamplesWithDistinctNeighbours() async throws {
    let pinned = try PinnedDesign.page("first-launch")
    let count = try pinned.childCount(tag: "img", inClass: "tiles")
    #expect(count > 0 && count % 6 == 0)
    #expect(FirstLaunchLayout.sampleNames == i315Samples)
    let names = FirstLaunchLayout.sampleNames
    func key(_ tile: FirstLaunchLayout.Tile) -> String { "\(tile.row),\(tile.column),\(tile.sample)" }
    let reference = FirstLaunchLayout.wall(in: NSSize(width: 960, height: 640)).tiles.map(key)
    let sizes = [NSSize(width: 960, height: 640)] +
        generatedSizes(seed: 0x315, count: 100, width: 360...3200, height: 480...2000)
    for size in sizes {
        let tiles = FirstLaunchLayout.wall(in: size).tiles
        #expect(tiles.count == count, "seed 0x315 size \(size)")
        var grid: [String: String] = [:]
        for tile in tiles {
            #expect(names.contains(tile.sample), "seed 0x315 size \(size) tile \(key(tile))")
            #expect(names.isEmpty || tile.sample == names[(tile.column + 2 * tile.row) % names.count],
                    "seed 0x315 size \(size) tile \(key(tile))")
            #expect(grid.updateValue(tile.sample, forKey: "\(tile.row),\(tile.column)") == nil, "duplicate cell \(key(tile))")
        }
        for tile in tiles {
            for (dr, dc) in [(0, 1), (1, 0)] {
                if let neighbour = grid["\(tile.row + dr),\(tile.column + dc)"] {
                    #expect(neighbour != tile.sample, "seed 0x315 size \(size) neighbours at \(key(tile)) +\(dr),\(dc)")
                }
            }
        }
        for name in names {
            #expect(tiles.filter { $0.sample == name }.count == count / names.count, "seed 0x315 size \(size) \(name)")
        }
        #expect(tiles.map(key) == reference, "seed 0x315 size \(size) assignment depends on size")
    }

    let scene = StatesScene()
    defer { scene.window.close() }
    let home = try launch(in: scene)
    #expect(home.sampleLoadCompleted == false, "init waited for decode")
    await waitForSamples(home)
    #expect(home.sampleLoadCompleted)
    let containers = tileContainers(home)
    #expect(containers.count == count)
    #expect(containers.map(\.name) == FirstLaunchLayout.wall(in: NSSize(width: 960, height: 640)).tiles.map { $0.sample as String? })
    for container in containers {
        let name = try #require(container.name)
        let url = try #require(FirstLaunchView.sampleURL(name: name))
        let source = try #require(sourcePixels(url))
        #expect(!container.isHidden, "\(name) hidden")
        let image = try #require(cgImage(imageLayer(container)), "\(name) has no decoded contents")
        #expect(max(image.width, image.height) == expectedDecodedMaxSide(url), "\(name) decoded size")
        #expect((image.width > image.height) == source.landscape, "\(name) orientation")
    }
}

@Test @MainActor func i315WallHidesOnlyFailedSampleTiles() async throws {
    for failing in ["gate", "alley"] {
        var urls: [String: URL] = [:]
        for name in i315Samples { urls[name] = name == failing ? i315Missing : FirstLaunchView.sampleURL(name: name) }
        let view = await i315Launch(urls)
        #expect(view.sampleLoadCompleted)
        let containers = tileContainers(view)
        #expect(containers.count == 60, "failing \(failing)")
        let hidden = containers.filter(\.isHidden)
        #expect(Set(hidden.compactMap(\.name)) == [failing], "failing \(failing)")
        #expect(hidden.count == 10, "failing \(failing)")
        #expect(hidden.allSatisfy { imageLayer($0)?.contents == nil }, "failing \(failing)")
        for container in containers where !container.isHidden {
            #expect(container.name != failing)
            #expect(cgImage(imageLayer(container)) != nil, "failing \(failing): \(container.name ?? "?") empty")
        }
    }
}

@Test @MainActor func i315WallShowsNoTilesWhenEverySampleFails() async throws {
    let reference = await i315Launch(nil)
    let expectedFrames = reference.semanticViews.map(\.frame)
    let allMissing = Dictionary(uniqueKeysWithValues: i315Samples.map { ($0, i315Missing) })
    for urls in [allMissing, [:]] {
        let view = await i315Launch(urls)
        #expect(view.sampleLoadCompleted, "\(urls.count) urls")
        let containers = tileContainers(view)
        #expect(containers.count == 60, "\(urls.count) urls")
        #expect(containers.allSatisfy { $0.isHidden }, "\(urls.count) urls")
        #expect(containers.allSatisfy { imageLayer($0)?.contents == nil }, "\(urls.count) urls")
        #expect(wallView(view) != nil)
        #expect(wallLayer("first-launch.wall.tiles", in: view) != nil)
        #expect(wallLayer("first-launch.wall.scrim", in: view) != nil)
        #expect(view.semanticViews.map(\.frame) == expectedFrames, "\(urls.count) urls")
    }
}
