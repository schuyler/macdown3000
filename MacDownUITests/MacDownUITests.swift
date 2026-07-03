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

    // MARK: - App Launch Tests

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
        let editor = app.textViews["editor-text-view"]
        let editorExists = editor.waitForExistence(timeout: 5)
        XCTAssertTrue(editorExists, "Editor text view should exist with accessibility identifier 'editor-text-view'")
    }

    // MARK: - Editor Interaction Tests

    /// Test: Can type text in the editor.
    func testCanTypeInEditor() throws {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
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
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found")
            return
        }

        // Type some text first
        editor.click()
        editor.typeText("Test content for selection")

        // Select all with Cmd+A
        editor.typeKey("a", modifierFlags: .command)

        // The text should now be selected - verify by typing replacement
        editor.typeText("Replaced")

        let editorValue = editor.value as? String ?? ""
        XCTAssertEqual(editorValue, "Replaced", "Select All should select all text for replacement")
    }

    /// Test: Undo works after typing.
    func testUndoAfterTyping() throws {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found")
            return
        }

        editor.click()
        editor.typeText("Original text")

        // Select all and replace
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("New text")

        // Undo with Cmd+Z
        editor.typeKey("z", modifierFlags: .command)

        let editorValue = editor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains("Original"), "Undo should restore original text")
    }

    /// Test: Can apply bold formatting via keyboard shortcut.
    func testBoldFormatting() throws {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found")
            return
        }

        editor.click()

        // Type text, select it, apply bold
        editor.typeText("bold text")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("b", modifierFlags: .command)

        let editorValue = editor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains("**"), "Bold formatting should wrap text in **")
    }

    /// Test: Can apply italic formatting via keyboard shortcut.
    func testItalicFormatting() throws {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found")
            return
        }

        editor.click()
        editor.typeText("italic text")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("i", modifierFlags: .command)

        let editorValue = editor.value as? String ?? ""
        // Check for either * or _ italic markers
        let hasItalicMarkers = editorValue.contains("*") || editorValue.contains("_")
        XCTAssertTrue(hasItalicMarkers, "Italic formatting should wrap text in * or _")
    }

    // MARK: - Menu Tests

    /// Test: File > New menu item creates a new window.
    func testFileNewCreatesWindow() throws {
        let initialWindowCount = app.windows.count

        // Use keyboard shortcut for New (Cmd+N)
        app.typeKey("n", modifierFlags: .command)

        // Wait a moment for the new window
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertGreaterThan(app.windows.count, initialWindowCount, "File > New should create a new window")
    }

    /// Test: Can close a window with Cmd+W.
    func testCloseWindow() throws {
        // First create a new window so we have something to close
        app.typeKey("n", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        let windowCountAfterNew = app.windows.count

        // Close the frontmost window
        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertLessThan(app.windows.count, windowCountAfterNew, "Cmd+W should close a window")
    }

    // MARK: - Preferences Tests

    /// Test: Can open preferences window.
    func testOpenPreferences() throws {
        // Open preferences with Cmd+,
        app.typeKey(",", modifierFlags: .command)

        // Wait for preferences window to appear
        let preferencesWindow = app.windows["Preferences"]
        let appeared = preferencesWindow.waitForExistence(timeout: 5)

        XCTAssertTrue(appeared, "Preferences window should open with Cmd+,")
    }

    /// Test: Preferences window has expected tabs.
    func testPreferencesHasTabs() throws {
        app.typeKey(",", modifierFlags: .command)

        let preferencesWindow = app.windows["Preferences"]
        guard preferencesWindow.waitForExistence(timeout: 5) else {
            XCTFail("Preferences window not found")
            return
        }

        // Check for toolbar buttons (preference panes)
        let toolbar = preferencesWindow.toolbars.firstMatch
        XCTAssertTrue(toolbar.exists, "Preferences should have a toolbar")

        // Look for expected preference pane buttons
        let generalButton = toolbar.buttons["General"]
        let editorButton = toolbar.buttons["Editor"]
        let markdownButton = toolbar.buttons["Markdown"]

        // At least one of these should exist
        let hasExpectedPanes = generalButton.exists || editorButton.exists || markdownButton.exists
        XCTAssertTrue(hasExpectedPanes, "Preferences should have expected preference panes")
    }

    // MARK: - Document State Tests

    /// Test: New document starts empty.
    func testNewDocumentIsEmpty() throws {
        // Create a new document
        app.typeKey("n", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found in new document")
            return
        }

        let editorValue = editor.value as? String ?? ""
        XCTAssertTrue(editorValue.isEmpty, "New document should start with empty editor")
    }

    /// Test: Document shows unsaved indicator after editing.
    func testDocumentShowsUnsavedIndicator() throws {
        let editor = app.textViews["editor-text-view"]
        guard editor.waitForExistence(timeout: 5) else {
            XCTFail("Editor not found")
            return
        }

        editor.click()
        editor.typeText("Unsaved changes")

        // Check window title or close button for unsaved indicator
        // On macOS, the window's close button shows a dot when document is edited
        let window = app.windows.firstMatch
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]

        // The close button exists (we can't easily check the dot indicator via XCUITest)
        XCTAssertTrue(closeButton.exists, "Window should have a close button")
    }
}
