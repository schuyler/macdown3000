import XCTest

/// Feasibility spike for XCUITest infrastructure.
///
/// This minimal test verifies that:
/// 1. The app can be launched via XCUITest
/// 2. A window appears
/// 3. The editor text view can be found by accessibility identifier
///
/// If this test passes reliably across all macOS CI versions, we can
/// proceed with more comprehensive UI tests.
final class MacDownUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Disable state restoration to get consistent initial state
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    /// Smoke test: App launches and shows a window.
    func testAppLaunchesWithWindow() throws {
        // Verify at least one window exists
        XCTAssertGreaterThan(app.windows.count, 0, "App should have at least one window after launch")

        // Verify the window is visible
        let firstWindow = app.windows.firstMatch
        XCTAssertTrue(firstWindow.exists, "First window should exist")
    }

    /// Smoke test: Editor text view is accessible.
    func testEditorTextViewExists() throws {
        // Find the editor by accessibility identifier
        let editor = app.textViews["editor-text-view"]

        // Wait for the editor to appear (up to 5 seconds)
        let editorExists = editor.waitForExistence(timeout: 5)
        XCTAssertTrue(editorExists, "Editor text view should exist with accessibility identifier 'editor-text-view'")
    }

    /// Smoke test: Can type in the editor.
    func testCanTypeInEditor() throws {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found")
            return
        }

        // Click to focus
        editor.click()

        // Type some text
        let testText = "# Hello World"
        editor.typeText(testText)

        // Verify text was entered (basic check - editor value contains our text)
        // Note: This may need adjustment based on how XCUITest reads NSTextView content
        let editorValue = editor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains("Hello World"), "Editor should contain typed text")
    }
}
