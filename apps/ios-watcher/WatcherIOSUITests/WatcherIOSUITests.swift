import XCTest

@MainActor
final class WatcherIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsPrimaryTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.tabBars.buttons["Threads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }
}
