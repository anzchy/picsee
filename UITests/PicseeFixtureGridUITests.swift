import XCTest

final class PicseeFixtureGridUITests: XCTestCase {
    @MainActor
    func testContainerFixtureOpensThreeImageGrid() throws {
        let app = XCUIApplication(bundleIdentifier: "io.github.anzchy.picsee")
        let names = ["landscape-3x2.png", "portrait-2x3.png", "orientation-1.tiff"]
        for (index, name) in names.enumerated() {
            let resource = name as NSString
            let url = try XCTUnwrap(Bundle(for: Self.self).url(
                forResource: resource.deletingPathExtension,
                withExtension: resource.pathExtension))
            app.launchEnvironment["PICSEE_UI_FIXTURE_\(index)"] = try Data(contentsOf: url).base64EncodedString()
        }
        app.launchArguments += ["-PicseeUITestFixture", UUID().uuidString]
        app.launch()

        let collection = app.descendants(matching: .any).matching(identifier: "grid.collection").firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20))
        let cells = collection.descendants(matching: .any).matching(identifier: "grid.cell")
        let deadline = Date().addingTimeInterval(30)
        while cells.count != 3 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let count = cells.count
        XCTAssertEqual(count, 3)
    }
}
