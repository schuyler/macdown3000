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

        // Type some text with unique marker
        editor.click()
        editor.typeText("ORIGINAL_CONTENT")
        waitForUIToSettle()

        // Select all with Cmd+A
        editor.typeKey("a", modifierFlags: .command)
        waitForUIToSettle()

        // Type replacement text
        editor.typeText("REPLACED")
        waitForUIToSettle()

        let editorValue = editor.value as? String ?? ""
        // Verify the original content was replaced
        XCTAssertTrue(editorValue.contains("REPLACED"), "Replacement text should be present")
        XCTAssertFalse(editorValue.contains("ORIGINAL_CONTENT"), "Original content should be replaced")
    }

    /// Test: Undo works after typing.
    func testUndoAfterTyping() throws {
        guard let editor = waitForEditor() else {
            XCTFail("Editor not found")
            return
        }

        editor.click()

        // Type some text
        editor.typeText("TEST_CONTENT")
        waitForUIToSettle()

        // Verify text is present
        var editorValue = editor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains("TEST_CONTENT"), "Text should be typed")

        // Undo with Cmd+Z - should remove or partially revert the typed text
        editor.typeKey("z", modifierFlags: .command)
        waitForUIToSettle()

        editorValue = editor.value as? String ?? ""
        // After undo, the text should be different (either empty or partially reverted)
        // macOS may undo the entire text or just part of it depending on undo grouping
        let undoHadEffect = !editorValue.contains("TEST_CONTENT") || editorValue.count < "TEST_CONTENT".count
        XCTAssertTrue(undoHadEffect, "Undo should have some effect on the content")
    }

    // MARK: - Menu Tests

    /// Test: File > New menu item creates a new window.
    func testFileNewCreatesWindow() throws {
        let initialWindowCount = app.windows.count

        // Use keyboard shortcut for New (Cmd+N)
        app.typeKey("n", modifierFlags: .command)

        // Wait for window count to increase using predicate
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", initialWindowCount),
            object: app.windows
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "File > New should create a new window")
    }

    /// Test: Can close a window with Cmd+W.
    func testCloseWindow() throws {
        let initialWindowCount = app.windows.count

        // First create a new window so we have something to close
        app.typeKey("n", modifierFlags: .command)
        waitForUIToSettle()

        // Wait for window count to increase
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", initialWindowCount),
            object: app.windows
        )
        let newWindowAppeared = XCTWaiter.wait(for: [expectation], timeout: 5)
        guard newWindowAppeared == .completed else {
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

        // Wait for window count to decrease
        let closeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < %d", windowCountAfterNew),
            object: app.windows
        )
        let windowClosed = XCTWaiter.wait(for: [closeExpectation], timeout: 5)
        XCTAssertEqual(windowClosed, .completed, "Cmd+W should close a window")
    }

    // MARK: - Preferences Tests

    /// Test: Can open preferences window.
    func testOpenPreferences() throws {
        let initialWindowCount = app.windows.count

        // Open preferences with Cmd+,
        app.typeKey(",", modifierFlags: .command)
        waitForUIToSettle()

        // Verify a new window appeared
        XCTAssertGreaterThan(app.windows.count, initialWindowCount, "Preferences window should open with Cmd+,")
    }

    /// Test: Preferences window has a toolbar.
    func testPreferencesHasToolbar() throws {
        let initialWindowCount = app.windows.count

        app.typeKey(",", modifierFlags: .command)
        waitForUIToSettle()

        // Wait for a new window to appear
        guard app.windows.count > initialWindowCount else {
            XCTFail("Preferences window not found")
            return
        }

        // Find the newest window (preferences)
        let preferencesWindow = app.windows.element(boundBy: initialWindowCount)
        guard preferencesWindow.waitForExistence(timeout: 5) else {
            XCTFail("Preferences window did not appear")
            return
        }

        // Check for toolbar - MASPreferences windows have toolbars
        let toolbar = preferencesWindow.toolbars.firstMatch
        // Toolbar may take a moment to be accessible
        let toolbarExists = toolbar.waitForExistence(timeout: 2)
        XCTAssertTrue(toolbarExists, "Preferences should have a toolbar")
    }

    // MARK: - Document State Tests

    /// Test: New document starts with editor accessible.
    func testNewDocumentHasEditor() throws {
        let initialWindowCount = app.windows.count

        // Create a new document
        app.typeKey("n", modifierFlags: .command)
        waitForUIToSettle()

        // Wait for window count to increase
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", initialWindowCount),
            object: app.windows
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        guard result == .completed else {
            XCTFail("New window did not appear")
            return
        }

        // Find the newest window (the one we just created)
        let newWindow = app.windows.element(boundBy: initialWindowCount)

        // Find editor in the new window
        let editor = newWindow.textViews["editor-text-view"]
        let editorExists = editor.waitForExistence(timeout: 5)
        XCTAssertTrue(editorExists, "New document should have an accessible editor")
    }
}
