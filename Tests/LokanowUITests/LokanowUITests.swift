import XCTest
final class LokanowUITests: XCTestCase {
    func testWelcomeAndSettings() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Open Xcode Project Folder"].waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.secureTextFields["API token"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save & Test Connection"].exists)
    }
}
