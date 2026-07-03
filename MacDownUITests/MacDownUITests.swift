import XCTest

/// UI acceptance tests for MacDown 3000.
///
/// These tests verify core user-facing functionality through XCUITest,
/// complementing the unit test suite with end-to-end validation.
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

    /// Small delay to allow UI to settle after keyboard commands.
    private func waitForUIToSettle() {
        // Using RunLoop for more reliable timing in XCUITest
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    }

    // MARK: - App Launch Tests

    /// Smoke test: App launches and shows a window.
    func testAppLaunchesWithWindow() throws {
        XCTAssertGreaterThan(app.windows.count, 0, "App should have at least one window after launch")
        let firstWindow = app.windows.firstMatch
        XCTAssertTrue(firstWindow.exists, "First window should exist")
    }

    /// Smoke test: Editor text view is accessible.
    func testEditorTextViewExists() throws {
        let editor = app.textViews["editor-text-view"]
        let editorExists = editor.waitForExistence(timeout: 5)
        XCTAssertTrue(editorExists, "Editor text view should exist with accessibility identifier 'editor-text-view'")
    }

    // MARK: - Editor Interaction Tests

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

    /// Test: Can select all text using keyboard shortcut.
    func testSelectAllText() throws {
        guard let editor = waitForEditor() else {
            XCTFail("Editor not found")
            return
        }

        // Type some text
        editor.click()
        editor.typeText("Test content")
        waitForUIToSettle()

        // Select all with Cmd+A
        editor.typeKey("a", modifierFlags: .command)
        waitForUIToSettle()

        // Type replacement text
        editor.typeText("Replaced")
        waitForUIToSettle()

        let editorValue = (editor.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(editorValue, "Replaced", "Select All should select all text for replacement")
    }

    /// Test: Undo works after typing.
    func testUndoAfterTyping() throws {
        guard let editor = waitForEditor() else {
            XCTFail("Editor not found")
            return
        }

        editor.click()
        editor.typeText("First")
        waitForUIToSettle()

        // Clear and type new content
        editor.typeKey("a", modifierFlags: .command)
        waitForUIToSettle()
        editor.typeText("Second")
        waitForUIToSettle()

        // Undo with Cmd+Z - should restore "First"
        editor.typeKey("z", modifierFlags: .command)
        waitForUIToSettle()

        let editorValue = editor.value as? String ?? ""
        // After undo, either "First" is restored or "Second" is removed
        let undoWorked = editorValue.contains("First") || !editorValue.contains("Second")
        XCTAssertTrue(undoWorked, "Undo should revert the last change")
    }

    // MARK: - Menu Tests

    /// Test: File > New menu item creates a new window.
    func testFileNewCreatesWindow() throws {
        let initialWindowCount = app.windows.count

        // Use keyboard shortcut for New (Cmd+N)
        app.typeKey("n", modifierFlags: .command)

        // Wait for new window to appear
        let newWindowAppeared = app.windows.element(boundBy: initialWindowCount).waitForExistence(timeout: 5)
        XCTAssertTrue(newWindowAppeared, "File > New should create a new window")
    }

    /// Test: Can close a window with Cmd+W.
    func testCloseWindow() throws {
        // First create a new window so we have something to close
        app.typeKey("n", modifierFlags: .command)

        // Wait for the new window
        let secondWindow = app.windows.element(boundBy: 1)
        guard secondWindow.waitForExistence(timeout: 5) else {
            XCTFail("New window did not appear")
            return
        }

        let windowCountAfterNew = app.windows.count

        // Close the frontmost window
        app.typeKey("w", modifierFlags: .command)
        waitForUIToSettle()

        // Handle potential "Don't Save" dialog
        let dontSaveButton = app.buttons["Don't Save"]
        if dontSaveButton.waitForExistence(timeout: 1) {
            dontSaveButton.click()
            waitForUIToSettle()
        }

        XCTAssertLessThan(app.windows.count, windowCountAfterNew, "Cmd+W should close a window")
    }

    // MARK: - Preferences Tests

    /// Test: Can open preferences window.
    func testOpenPreferences() throws {
        // Open preferences with Cmd+,
        app.typeKey(",", modifierFlags: .command)

        // Wait for any preferences-like window to appear
        // MASPreferences may use different window identifiers
        let prefsAppeared = app.windows.element(boundBy: 1).waitForExistence(timeout: 5)
        XCTAssertTrue(prefsAppeared, "Preferences window should open with Cmd+,")
    }

    /// Test: Preferences window has a toolbar.
    func testPreferencesHasToolbar() throws {
        app.typeKey(",", modifierFlags: .command)

        // Wait for preferences window (second window after main document)
        let preferencesWindow = app.windows.element(boundBy: 1)
        guard preferencesWindow.waitForExistence(timeout: 5) else {
            XCTFail("Preferences window not found")
            return
        }

        // Check for toolbar
        let toolbar = preferencesWindow.toolbars.firstMatch
        XCTAssertTrue(toolbar.exists, "Preferences should have a toolbar")

        // Verify toolbar has buttons (preference panes)
        let toolbarButtonCount = toolbar.buttons.count
        XCTAssertGreaterThan(toolbarButtonCount, 0, "Preferences toolbar should have buttons")
    }

    // MARK: - Document State Tests

    /// Test: New document starts with editor accessible.
    func testNewDocumentHasEditor() throws {
        // Create a new document
        app.typeKey("n", modifierFlags: .command)

        // Wait for new window
        let newWindow = app.windows.element(boundBy: 1)
        guard newWindow.waitForExistence(timeout: 5) else {
            XCTFail("New window did not appear")
            return
        }

        // Find editor in the new window
        let editor = newWindow.textViews["editor-text-view"]
        let editorExists = editor.waitForExistence(timeout: 5)
        XCTAssertTrue(editorExists, "New document should have an accessible editor")
    }
}
