import AppKit
import XCTest

final class PicseeFixtureGridUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.anzchy.picsee").isEmpty else {
            throw XCTSkip("another Picsee is running; refusing to launch over it")
        }
    }

    @MainActor
    func testContainerFixtureOpensThreeImageGrid() throws {
        // The UI target's TEST_TARGET_NAME binds this to the product built for this test run.
        let app = XCUIApplication()
        let fixtureName = UUID().uuidString
        let names = ["landscape-3x2.png", "portrait-2x3.png", "orientation-1.tiff"]
        for (index, name) in names.enumerated() {
            let resource = name as NSString
            let url = try XCTUnwrap(Bundle(for: Self.self).url(
                forResource: resource.deletingPathExtension,
                withExtension: resource.pathExtension))
            app.launchEnvironment["PICSEE_UI_FIXTURE_\(index)"] = try Data(contentsOf: url).base64EncodedString()
        }
        app.launchArguments += ["-PicseeUITestFixture", fixtureName]
        app.launch()
        addTeardownBlock {
            app.terminate()
            // Fallback if App termination did not run its test-only cleanup hook.
            let runFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/io.github.anzchy.picsee/Data/Library/Application Support/Picsee/UITestFixtures", isDirectory: true)
                .appendingPathComponent(fixtureName, isDirectory: true)
            if FileManager.default.fileExists(atPath: runFolder.path) {
                try? FileManager.default.removeItem(at: runFolder)
            }
        }

        let folderMarker = app.descendants(matching: .any).matching(identifier: "grid.sidebar.folder").firstMatch
        let fixtureMarker = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", fixtureName), object: folderMarker)
        XCTAssertEqual(XCTWaiter.wait(for: [fixtureMarker], timeout: 20), .completed,
            "The build under test did not open its fixture; check the UI test compile flag and target application")

        let collection = app.descendants(matching: .any).matching(identifier: "grid.collection").firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20))
        let cells = collection.descendants(matching: .any).matching(identifier: "grid.cell")
        XCTAssertTrue(cells.element(boundBy: 2).waitForExistence(timeout: 30))
        let count = cells.count
        XCTAssertEqual(count, 3)
    }
}
