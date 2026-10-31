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

// MARK: - WI-2 wall geometry and tile styling (pinned page 21)

@MainActor private func i315Scene(_ size: NSSize = NSSize(width: 960, height: 640)) throws -> (StatesScene, FirstLaunchView) {
    let scene = StatesScene(width: 960)
    scene.state.display(.empty)
    try resize(scene, to: size)
    return (scene, try launch(in: scene))
}

private func i315Close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat) -> Bool { abs(a - b) <= tolerance }
private func i315Close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat) -> Bool {
    i315Close(a.x, b.x, tolerance) && i315Close(a.y, b.y, tolerance)
}
private func i315Close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat) -> Bool {
    i315Close(a.minX, b.minX, tolerance) && i315Close(a.minY, b.minY, tolerance)
        && i315Close(a.width, b.width, tolerance) && i315Close(a.height, b.height, tolerance)
}
private func i315Close(_ a: PinnedDesign.Color, _ b: PinnedDesign.Color, rgb: Double = 1.5 / 255, alpha: Double = 0.01) -> Bool {
    abs(a.red - b.red) <= rgb && abs(a.green - b.green) <= rgb && abs(a.blue - b.blue) <= rgb && abs(a.alpha - b.alpha) <= alpha
}

@Test @MainActor func i315WallFrameFillsContentBelowTitleBar() throws {
    let pinned = try PinnedDesign.page("first-launch")
    for size in [NSSize(width: 960, height: 640), NSSize(width: 800, height: 680), NSSize(width: 1440, height: 900)] {
        let (scene, home) = try i315Scene(size)
        defer { scene.window.close() }
        let titleBar = try pinned.length(":root", "--title-bar-height", viewport: size.width)
        let wall = try #require(wallView(home))
        #expect(home.bounds.size == size, "\(size)")
        #expect(i315Close(wall.convert(wall.bounds, to: home),
                          NSRect(x: 0, y: 0, width: size.width, height: size.height - titleBar), 0.001), "\(size) wall \(wall.frame)")
        #expect(wall.layer?.masksToBounds == true, "\(size)")
        let scrim = try #require(wallLayer("first-launch.wall.scrim", in: home))
        #expect(i315Close(scrim.frame, wall.bounds, 0.001), "\(size) scrim \(scrim.frame)")
    }
}

@Test func i315WallLayoutGeometryLawHoldsAcrossSizes() throws {
    let pinned = try PinnedDesign.page("first-launch")
    let selector = ".wall .tiles"
    let columns = try pinned.gridColumns(selector)
    let offset = CGFloat(try pinned.translateY(".wall .tiles>:nth-child(2n)"))
    let count = try pinned.childCount(tag: "img", inClass: "tiles")
    let seed: UInt64 = 0x3150
    let sizes = generatedSizes(seed: seed, count: 200, width: 360...3200, height: 480...2000)
        + [NSSize(width: 360, height: 680), NSSize(width: 800, height: 680)]
    let tolerance: CGFloat = 0.001
    var columnWidths: [(width: CGFloat, column: CGFloat, row: CGFloat)] = []
    for size in sizes {
        let w = Double(size.width), h = Double(size.height)
        func css(_ property: String, base: Double) throws -> CGFloat {
            CGFloat(try pinned.lengthValue(pinned.raw(selector, property, viewport: w), viewport: w, percentageBase: base))
        }
        let left = try css("left", base: w), right = try css("right", base: w)
        let top = try css("top", base: h), height = try css("height", base: h)
        let rowHeight = try css("grid-auto-rows", base: h), gap = try css("gap", base: w)
        let layout = FirstLaunchLayout.wall(in: size)
        let box = layout.box
        let context = "seed 0x3150 size \(size)"
        #expect(i315Close(box.width, size.width - left - right, tolerance), "\(context) box \(box)")
        #expect(i315Close(box.height, height, tolerance), "\(context) box \(box)")
        #expect(i315Close(box.midX, left + box.width / 2, tolerance), "\(context) box \(box)")
        #expect(i315Close(box.midX, size.width / 2, tolerance), "\(context) box \(box)")
        #expect(i315Close(box.midY, size.height - (top + height / 2), tolerance), "\(context) box \(box)")
        #expect(i315Close(box.midY, size.height / 2, tolerance), "\(context) box \(box)")
        #expect(layout.tiles.count == count, "\(context)")
        let columnWidth = (box.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
        var grid: [String: NSRect] = [:]
        for (index, tile) in layout.tiles.enumerated() {
            #expect(tile.row == index / columns && tile.column == index % columns, "\(context) tile \(index) not row-major")
            #expect(i315Close(tile.frame.width, columnWidth, tolerance) && i315Close(tile.frame.height, rowHeight, tolerance),
                    "\(context) tile \(tile.row),\(tile.column) size \(tile.frame.size)")
            grid["\(tile.row),\(tile.column)"] = tile.frame
        }
        for tile in layout.tiles {
            let frame = tile.frame, cell = "\(context) tile \(tile.row),\(tile.column)"
            if tile.column == 0 { #expect(i315Close(frame.minX, 0, tolerance), "\(cell)") }
            if tile.column == columns - 1 { #expect(i315Close(frame.maxX, box.width, tolerance), "\(cell)") }
            if let next = grid["\(tile.row),\(tile.column + 1)"] {
                #expect(i315Close(next.minX - frame.maxX, gap, tolerance), "\(cell) row gap")
            }
            if let lower = grid["\(tile.row + 1),\(tile.column)"] {
                #expect(i315Close(frame.minY - lower.maxY, gap, tolerance), "\(cell) column gap")
            }
            if tile.column % 2 == 1, let neighbour = grid["\(tile.row),\(tile.column - 1)"] {
                #expect(i315Close(frame.minY, neighbour.minY - offset, tolerance), "\(cell) odd column offset")
            }
            if tile.row == 0, tile.column % 2 == 0 { #expect(i315Close(frame.maxY, box.height, tolerance), "\(cell)") }
        }
        if let first = layout.tiles.first { columnWidths.append((size.width, first.frame.width, first.frame.height)) }
    }
    let sorted = columnWidths.sorted { $0.width < $1.width }
    for (lower, upper) in zip(sorted, sorted.dropFirst()) where lower.width < upper.width {
        #expect(upper.column > lower.column, "seed 0x3150 column width not increasing \(lower.width) → \(upper.width)")
        #expect(i315Close(upper.row, lower.row, tolerance), "seed 0x3150 row height varies \(lower.width) → \(upper.width)")
    }
}

@Test @MainActor func i315RenderedWallTilesFollowLayoutTiltAndOffset() throws {
    let pinned = try PinnedDesign.page("first-launch")
    let tilt = CGFloat(-(try pinned.rotationDegrees(".wall .tiles")))
    let offset = CGFloat(try pinned.translateY(".wall .tiles>:nth-child(2n)"))
    for size in [NSSize(width: 960, height: 640), NSSize(width: 800, height: 680)] {
        let (scene, home) = try i315Scene(size)
        defer { scene.window.close() }
        let wall = try #require(wallView(home))
        let wallLayerRoot = try #require(wall.layer)
        let tiles = try #require(wallLayer("first-launch.wall.tiles", in: home))
        let layout = FirstLaunchLayout.wall(in: wall.bounds.size)
        let c = CGPoint(x: wall.bounds.midX, y: wall.bounds.midY)
        let (w, h) = (layout.box.width, layout.box.height)
        #expect(i315Close(tiles.bounds.width, w, 0.5) && i315Close(tiles.bounds.height, h, 0.5), "\(size) \(tiles.bounds)")
        #expect(i315Close(tiles.position, c, 0.5), "\(size) position \(tiles.position)")
        let containers = tileContainers(home)
        #expect(containers.count == layout.tiles.count, "\(size)")
        for (container, tile) in zip(containers, layout.tiles) {
            #expect(i315Close(container.frame, tile.frame, 0.5), "\(size) tile \(tile.row),\(tile.column) \(container.frame)")
        }
        let centre = tiles.convert(CGPoint(x: tiles.bounds.midX, y: tiles.bounds.midY), to: wallLayerRoot)
        #expect(i315Close(centre, c, 0.5), "\(size) box centre \(centre)")
        let corner = tiles.convert(CGPoint(x: tiles.bounds.minX, y: tiles.bounds.maxY), to: wallLayerRoot)
        let cornerOffset = rotated(CGVector(dx: -w / 2, dy: h / 2), degrees: tilt)
        #expect(i315Close(corner, CGPoint(x: c.x + cornerOffset.dx, y: c.y + cornerOffset.dy), 0.5), "\(size) top-left \(corner)")
        let t = tiles.affineTransform()
        #expect(i315Close(atan2(t.b, t.a) * 180 / .pi, tilt, 0.01), "\(size) tilt \(atan2(t.b, t.a) * 180 / .pi)")
        let rightEdge = tiles.convert(CGPoint(x: tiles.bounds.maxX, y: tiles.bounds.midY), to: wallLayerRoot)
        let leftEdge = tiles.convert(CGPoint(x: tiles.bounds.minX, y: tiles.bounds.midY), to: wallLayerRoot)
        #expect(rightEdge.y > leftEdge.y, "\(size) right side not raised")
        guard containers.count > 1 else { continue }
        func centreInWall(_ layer: CALayer) -> CGPoint {
            tiles.convert(CGPoint(x: layer.frame.midX, y: layer.frame.midY), to: wallLayerRoot)
        }
        let first = centreInWall(containers[0]), second = centreInWall(containers[1])
        let step = rotated(CGVector(dx: layout.tiles[0].frame.width + FirstLaunchLayout.gap, dy: -offset), degrees: tilt)
        #expect(i315Close(CGPoint(x: second.x - first.x, y: second.y - first.y), CGPoint(x: step.dx, y: step.dy), 0.5),
                "\(size) odd column step \(second.x - first.x),\(second.y - first.y)")
    }
}

@Test @MainActor func i315WallRelayoutsOnResize() throws {
    let (scene, home) = try i315Scene()
    defer { scene.window.close() }
    var boxes: [NSRect] = []
    for size in [NSSize(width: 960, height: 640), NSSize(width: 1440, height: 900), NSSize(width: 800, height: 680)] {
        try resize(scene, to: size)
        let wall = try #require(wallView(home))
        let wallLayerRoot = try #require(wall.layer)
        let tiles = try #require(wallLayer("first-launch.wall.tiles", in: home))
        let layout = FirstLaunchLayout.wall(in: wall.bounds.size)
        boxes.append(layout.box)
        #expect(i315Close(tiles.bounds.width, layout.box.width, 0.5) && i315Close(tiles.bounds.height, layout.box.height, 0.5),
                "\(size) \(tiles.bounds)")
        let centre = tiles.convert(CGPoint(x: tiles.bounds.midX, y: tiles.bounds.midY), to: wallLayerRoot)
        #expect(i315Close(centre, CGPoint(x: wall.bounds.midX, y: wall.bounds.midY), 0.5), "\(size) centre \(centre)")
        let containers = tileContainers(home)
        #expect(containers.count == layout.tiles.count, "\(size)")
        for (container, tile) in zip(containers, layout.tiles) {
            let cell = "\(size) tile \(tile.row),\(tile.column)"
            #expect(i315Close(container.frame, tile.frame, 0.5), "\(cell) \(container.frame)")
            #expect(container.shadowPath.map { i315Close($0.boundingBox, container.bounds, 0.5) } == true, "\(cell) shadowPath")
            #expect(imageLayer(container).map { i315Close($0.frame, container.bounds, 0.5) } == true, "\(cell) image frame")
        }
    }
    #expect(boxes.count == 3 && boxes[1].width != boxes[0].width, "stale geometry would pass: \(boxes)")
}

@Test @MainActor func i315DecodedContentsSurviveResizeAndThemeChange() async throws {
    for failing in [nil, "gate"] as [String?] {
        var urls: [String: URL]?
        if let failing {
            urls = [:]
            for name in i315Samples { urls?[name] = name == failing ? i315Missing : FirstLaunchView.sampleURL(name: name) }
        }
        let view = await i315Launch(urls)
        #expect(view.sampleLoadCompleted, "failing \(failing ?? "none")")
        let before = tileContainers(view).map { ($0.name, $0.isHidden, cgImage(imageLayer($0))) }
        #expect(before.count == 60)
        let steps: [(String, () -> Void)] = [
            ("1440×900", { view.frame = NSRect(x: 0, y: 0, width: 1440, height: 900) }),
            ("darkAqua", { view.appearance = NSAppearance(named: .darkAqua) }),
            ("800×680", { view.frame = NSRect(x: 0, y: 0, width: 800, height: 680) }),
            ("aqua", { view.appearance = NSAppearance(named: .aqua) })
        ]
        for (label, apply) in steps {
            apply()
            view.layoutSubtreeIfNeeded()
            let context = "failing \(failing ?? "none") after \(label)"
            let containers = tileContainers(view)
            #expect(containers.map(\.name) == before.map(\.0), "\(context)")
            #expect(containers.map(\.isHidden) == before.map(\.1), "\(context)")
            let hidden = containers.filter(\.isHidden)
            if let failing {
                #expect(Set(hidden.compactMap(\.name)) == [failing] && hidden.count == 10, "\(context)")
            } else {
                #expect(hidden.isEmpty, "\(context)")
            }
            for (container, record) in zip(containers, before) {
                if container.isHidden {
                    #expect(imageLayer(container)?.contents == nil, "\(context) \(record.0 ?? "?")")
                } else {
                    let current = cgImage(imageLayer(container))
                    #expect(current != nil && current === record.2, "\(context) \(record.0 ?? "?") contents replaced")
                }
            }
        }
    }
}

@Test @MainActor func i315WallOpacityFollowsThemeToken() throws {
    let light = try PinnedDesign.page("first-launch")
    let dark = try PinnedDesign.page("first-launch", appearance: "dark")
    let (scene, home) = try i315Scene()
    defer { scene.window.close() }
    let wall = try #require(wallView(home))
    for (appearance, page) in [(NSAppearance.Name.aqua, light), (.darkAqua, dark), (.aqua, light)] {
        home.appearance = NSAppearance(named: appearance)
        home.layoutSubtreeIfNeeded()
        let expected = try #require(Double(page.raw(".wall .tiles", "opacity", viewport: 960)))
        let tiles = try #require(wallLayer("first-launch.wall.tiles", in: home))
        #expect(abs(Double(tiles.opacity) - expected) < 0.001, "\(appearance.rawValue) tiles opacity \(tiles.opacity)")
        #expect(wall.alphaValue == 1, "\(appearance.rawValue)")
    }
}

@Test @MainActor func i315OnlyTilesLayerCarriesWallOpacity() async throws {
    let light = try PinnedDesign.page("first-launch")
    let dark = try PinnedDesign.page("first-launch", appearance: "dark")
    let (scene, home) = try i315Scene()
    defer { scene.window.close() }
    await waitForSamples(home)
    #expect(home.sampleLoadCompleted)
    let wall = try #require(wallView(home))
    for (appearance, page) in [(NSAppearance.Name.aqua, light), (.darkAqua, dark)] {
        home.appearance = NSAppearance(named: appearance)
        home.layoutSubtreeIfNeeded()
        let expected = try #require(Double(page.raw(".wall .tiles", "opacity", viewport: 960)))
        let tiles = try #require(wallLayer("first-launch.wall.tiles", in: home))
        let scrim = try #require(wallLayer("first-launch.wall.scrim", in: home))
        let wallOpacity = try #require(wall.layer?.opacity)
        #expect(scrim.opacity == 1 && !scrim.isHidden, "\(appearance.rawValue) scrim")
        #expect(wallOpacity == 1 && wall.alphaValue == 1, "\(appearance.rawValue) wall")
        let containers = tileContainers(home)
        #expect(containers.count == 60)
        for container in containers {
            let image = try #require(imageLayer(container))
            let cell = "\(appearance.rawValue) \(container.name ?? "?")"
            #expect(container.opacity == 1 && !container.isHidden, "\(cell)")
            #expect(image.opacity == 1, "\(cell)")
            let product = Double(image.opacity * container.opacity * tiles.opacity * wallOpacity) * Double(wall.alphaValue)
            #expect(abs(product - expected) < 0.001, "\(cell) opacity product \(product)")
        }
    }
}

@Test @MainActor func i315WallTileRadiusRingAndShadowFollowThemeShadowSoft() throws {
    let light = try PinnedDesign.page("first-launch")
    let dark = try PinnedDesign.page("first-launch", appearance: "dark")
    let (scene, home) = try i315Scene()
    defer { scene.window.close() }
    for (appearance, page) in [(NSAppearance.Name.aqua, light), (.darkAqua, dark)] {
        home.appearance = NSAppearance(named: appearance)
        home.layoutSubtreeIfNeeded()
        let layers = try page.boxShadowLayers(":root", "--shadow-soft", viewport: 960)
        try #require(layers.count == 2)
        let radius = CGFloat(try page.length(":root", "--radius-control", viewport: 960))
        #expect(try page.raw(".wall img", "object-fit", viewport: 960) == "cover")
        let containers = tileContainers(home)
        #expect(containers.count == 60)
        for container in containers {
            let image = try #require(imageLayer(container))
            let cell = "\(appearance.rawValue) \(container.name ?? "?")"
            #expect(image.cornerRadius == radius && image.masksToBounds, "\(cell) radius \(image.cornerRadius)")
            #expect(image.contentsGravity == .resizeAspectFill, "\(cell)")
            #expect(abs(Double(image.borderWidth) - layers[0].spread) < 0.001, "\(cell) ring width \(image.borderWidth)")
            let ring = try srgb(image.borderColor)
            #expect(i315Close(ring, layers[0].color), "\(cell) ring \(ring) vs \(layers[0].color)")
            #expect(Double(container.shadowOffset.width) == layers[1].x && Double(container.shadowOffset.height) == -layers[1].y,
                    "\(cell) shadow offset \(container.shadowOffset)")
            #expect(abs(Double(container.shadowRadius) - layers[1].blur / 2) < 0.001, "\(cell) shadow radius \(container.shadowRadius)")
            let shadow = try srgb(container.shadowColor)
            #expect(i315Close(PinnedDesign.Color(red: shadow.red, green: shadow.green, blue: shadow.blue, alpha: 0),
                              PinnedDesign.Color(red: layers[1].color.red, green: layers[1].color.green,
                                                 blue: layers[1].color.blue, alpha: 0)),
                    "\(cell) shadow rgb \(shadow) vs \(layers[1].color)")
            #expect(abs(shadow.alpha * Double(container.shadowOpacity) - layers[1].color.alpha) < 0.01,
                    "\(cell) shadow alpha \(shadow.alpha) × \(container.shadowOpacity)")
            #expect(container.shadowPath.map { i315Close($0.boundingBox, container.bounds, 0.5) } == true, "\(cell) shadowPath")
        }
    }
}

// MARK: - WI-3 drop outline inset and centre placement (pinned page 21)

@Test @MainActor func i315DropOutlineInsetsContentByPinnedInset() throws {
    let pinned = try PinnedDesign.page("first-launch")
    for size in [NSSize(width: 960, height: 640), NSSize(width: 800, height: 680), NSSize(width: 1440, height: 900)] {
        let (scene, home) = try i315Scene(size)
        defer { scene.window.close() }
        let titleBar = CGFloat(try pinned.length(":root", "--title-bar-height", viewport: size.width))
        let inset = CGFloat(try pinned.length(".drop-outline", "inset", viewport: size.width))
        let radius = CGFloat(try pinned.length(".drop-outline", "border-radius", viewport: size.width))
        let border = try pinned.border(".drop-outline")
        let drop = try #require(wallTestView("first-launch.drop", in: home))
        let frame = drop.convert(drop.bounds, to: home)
        let expected = NSRect(x: 0, y: 0, width: size.width, height: size.height - titleBar).insetBy(dx: inset, dy: inset)
        #expect(i315Close(frame, expected, 0.001), "\(size) drop \(frame) vs \(expected)")
        #expect(drop.layer?.cornerRadius == radius, "\(size) radius \(String(describing: drop.layer?.cornerRadius))")
        let outline = try #require(drop.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        #expect(Double(outline.lineWidth) == border.width, "\(size) line \(outline.lineWidth)")
        #expect(border.style == "dashed" && outline.lineDashPattern?.isEmpty == false, "\(size) dash")
        let half = outline.lineWidth / 2
        let path = try #require(outline.path)
        #expect(i315Close(path.boundingBoxOfPath, drop.bounds.insetBy(dx: half, dy: half), 0.001),
                "\(size) outline path \(path.boundingBoxOfPath)")
        let corner = path.boundingBoxOfPath
        #expect(!path.contains(CGPoint(x: corner.minX + 0.5, y: corner.minY + 0.5))
                && path.contains(CGPoint(x: corner.minX + radius, y: corner.minY + radius)),
                "\(size) outline path corner radius not \(radius)")
    }
}

@Test @MainActor func i315CentreGroupCentresOnContentMidpoint() throws {
    let pinned = try PinnedDesign.page("first-launch")
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let b4 = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let gap = CGFloat(try b4.length(".centre", "gap", viewport: 960))
    let seed: UInt64 = 0x3153
    let sizes = generatedSizes(seed: seed, count: 40, width: 800...2400, height: 680...1600) + [NSSize(width: 960, height: 640)]
    let scene = StatesScene(width: 960)
    defer { scene.window.close() }
    scene.state.display(.empty)
    for size in sizes {
        try resize(scene, to: size)
        let home = try launch(in: scene)
        let context = "seed 0x3153 size \(size)"
        let titleBar = CGFloat(try pinned.length(":root", "--title-bar-height", viewport: size.width))
        let views = centreViews(home)
        try #require(views.count == 7, "\(context)")
        let group = views.map { $0.convert($0.bounds, to: home) }.reduce(views[0].convert(views[0].bounds, to: home)) { $0.union($1) }
        let drop = try #require(wallTestView("first-launch.drop", in: home))
        let dropFrame = drop.convert(drop.bounds, to: home)
        #expect(i315Close(group.midY, dropFrame.midY, 0.5), "\(context) group \(group) drop \(dropFrame)")
        #expect(i315Close(group.midY, (size.height - titleBar) / 2, 0.5), "\(context) group midY \(group.midY)")
        #expect(i315Close(group.midX, size.width / 2, 0.5), "\(context) group midX \(group.midX)")
        let heading = try #require(wallTestView("first-launch.heading", in: home))
        let button = try #require(wallTestView("state.open", in: home))
        let chip = try #require(wallTestView("first-launch.chip.images", in: home))
        #expect(i315Close(heading.frame.minY - button.frame.maxY, gap, 1), "\(context) heading→button")
        #expect(i315Close(button.frame.minY - chip.frame.maxY, gap, 1), "\(context) button→chips")
        #expect(heading.frame.height == 24 && button.frame.height == 30 && chip.frame.height == 20,
                "\(context) heights \(heading.frame.height) \(button.frame.height) \(chip.frame.height)")
    }
}
