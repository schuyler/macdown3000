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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES"]
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

    func testUntitledDocumentSurvivesNormalQuitAndRelaunch() throws {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "NO",
                               "-NSQuitAlwaysKeepsWindows", "YES",
                               "-editorAutoSave", "YES",
                               "-MPDisableUpdater", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        let documentWindow = app.windows.containing(.textView,
            identifier: "editor-text-view").firstMatch
        let editor = documentWindow.textViews.matching(
            identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "")
        let marker = "Draft recovery " + UUID().uuidString
        editor.click()
        editor.typeText(marker)
        XCTAssertTrue((editor.value as? String ?? "").contains(marker))
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15),
                      "Normal quit must preserve the draft without a save panel")
        app.launch()
        let recovered = app.textViews.matching(identifier: "editor-text-view")
            .matching(NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(recovered.waitForExistence(timeout: 15),
                      "The never-saved document must retain its exact contents")
        // Explicitly close this fixture rather than leave it for later UI tests.
        recovered.click()
        recovered.typeKey("a", modifierFlags: .command)
        recovered.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        app.typeKey("w", modifierFlags: .command)
    }

    func testSavedDocumentSurvivesNormalQuitWithUnsavedEdits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                               withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("existing.md")
        let marker = "Existing recovery " + UUID().uuidString
        try "Saved baseline".write(to: file, atomically: true, encoding: .utf8)
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "NO",
                               "-NSQuitAlwaysKeepsWindows", "YES",
                               "-editorAutoSave", "YES",
                               "-MPDisableUpdater", "YES"]
        app.launch()
        app.typeKey("o", modifierFlags: .command)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let editor = app.textViews.matching(identifier: "editor-text-view").matching(
            NSPredicate(format: "value CONTAINS %@", "Saved baseline")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(marker)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
        app.launch()
        let restored = app.textViews.matching(identifier: "editor-text-view").matching(
            NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 15))
    }

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
