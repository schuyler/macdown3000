import XCTest

/// UI acceptance smoke tests for MacDown 3000.
///
/// This is intentionally a small, deterministic core that exercises the
/// app launch path, the editor, and the preview pane through XCUITest.
/// It complements (not replaces) the unit test suite.
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

    // MARK: - Helper Methods

    /// Waits for the editor in the frontmost window.
    private func waitForEditor(timeout: TimeInterval = 5) -> XCUIElement? {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: timeout) else {
            return nil
        }
        return editor
    }

    // MARK: - Smoke Tests

    /// Smoke test: App launches and shows at least one window.
    func testAppLaunchesWithWindow() throws {
        let firstWindow = app.windows.firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 5), "App should show at least one window after launch")
    }

    /// Smoke test: Editor text view is accessible.
    func testEditorTextViewExists() throws {
        let editor = app.textViews["editor-text-view"]
        let editorExists = editor.waitForExistence(timeout: 5)
        XCTAssertTrue(editorExists, "Editor text view should exist with accessibility identifier 'editor-text-view'")
    }

    /// Test: Can type text in the editor.
    func testCanTypeInEditor() throws {
        guard let editor = waitForEditor() else {
            XCTFail("Editor not found")
            return
        }

        editor.click()
        let testText = "# Hello World"
        editor.typeText(testText)

        let editorValue = editor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains("Hello World"), "Editor should contain typed text")
    }

    /// Test: Preview pane exists after typing markdown content.
    func testPreviewPaneExists() throws {
        guard let editor = waitForEditor() else {
            XCTFail("Editor not found")
            return
        }

        editor.click()
        editor.typeText("# Hello World")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "Preview pane web view should exist")
    }
}
