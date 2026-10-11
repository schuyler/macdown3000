import XCTest
import AppKit

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
        if let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] {
            app.launchEnvironment["CFFIXED_USER_HOME"] = home
        }
        // Disable state restoration to get consistent initial state
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES",
                               "-AppleLanguages", "(en)"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Helper Methods

    /// Waits for the editor in the frontmost window.
    private func waitForEditor(timeout: TimeInterval = 5) -> XCUIElement? {
        let editor = app.textViews.matching(identifier: "editor-text-view").firstMatch
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

    func testFindFromPreviewOpensRenderedTextSearch() throws {
        let pasteboard = NSPasteboard(name: .find)
        let originalItems = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if !originalItems.isEmpty { pasteboard.writeObjects(originalItems) }
        }
        let window = app.windows.containing(.textView,
            identifier: "editor-text-view").firstMatch
        let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("# Preview target\n\nSearch **rendered text** here.")
        let preview = window.webViews.firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        // The WebView exists before its asynchronous Markdown render finishes.
        // Focus the rendered fixture rather than an arbitrary point in a view
        // whose content can still be replaced while the click is delivered.
        let target = preview.staticTexts.matching(NSPredicate(
            format: "label == %@ OR value == %@", "Preview target", "Preview target"
        )).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10), window.debugDescription)
        target.click()
        app.typeKey("f", modifierFlags: .command)
        let field = app.searchFields["preview-find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("rendered text")
        field.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey("g", modifierFlags: .command)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: field)
        wait(for: [hidden], timeout: 5)
        editor.click()
        XCTAssertTrue((editor.value as? String ?? "").contains("**rendered text**"))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertFalse(app.searchFields["preview-find-field"].isHittable,
                       "Source Find must retain its native editor interface")
    }

    func testPreviewDoubleClickEditingUpdatesSourceAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("PreviewEditing.md")
        let source = "# Preview heading\n\nEditable phrase\n\n[Preserved link](https://example.com)\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES",
                               "-editorStartInPreviewMode", "NO",
                               "-htmlMathJax", "NO",
                               "-AppleLanguages", "(fr)"]
        app.launch()
        app.typeKey("o", modifierFlags: .command)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let window = app.windows["PreviewEditing.md"]
        let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let text = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Editable phrase", "Editable phrase")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), window.debugDescription)
        text.doubleClick()
        let modify = window.webViews.buttons["Modifier le texte"]
        XCTAssertTrue(modify.waitForExistence(timeout: 5))
        modify.click()
        app.typeText("Changed phrase")
        app.typeKey("s", modifierFlags: .command)
        let expected = source.replacingOccurrences(of: "Editable phrase", with: "Changed phrase")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: editor)], timeout: 5)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, source)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Source-backed editable preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let selectable = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Editable phrase", "Editable phrase")).firstMatch
        XCTAssertTrue(selectable.waitForExistence(timeout: 10))
        selectable.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: selectable.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        // aria-pressed exposes these controls as toggles in WebKit accessibility.
        let bold = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Gras")).firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5), window.debugDescription)
        let panelScreenshot = XCTAttachment(screenshot: window.screenshot())
        panelScreenshot.name = "Preview selection formatting panel"
        panelScreenshot.lifetime = .keepAlways
        add(panelScreenshot)
        app.toolbars.groups["text-formatting-group"].buttons.element(boundBy: 0).click()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "**"), object: editor)], timeout: 5)
        XCTAssertTrue((editor.value as? String)?.contains("[Preserved link](https://example.com)") == true)
        let formattedSource = try XCTUnwrap(editor.value as? String)
        let fragments = formattedSource.components(separatedBy: "**")
        XCTAssertEqual(fragments.count, 3)
        guard fragments.count == 3 else { return }
        let rendered = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", fragments[1], fragments[1])).firstMatch
        XCTAssertTrue(rendered.waitForExistence(timeout: 10), window.debugDescription)
        // Heading AX values can be numeric. Evaluating CONTAINS remotely on
        // every AX value throws inside XCTAutomationSupport, aborting the host.
        func assertNoRawDelimiters() {
            for element in window.webViews.staticTexts.allElementsBoundByIndex {
                let value = element.value as? String ?? ""
                XCTAssertFalse(element.label.contains("**") || value.contains("**"))
                XCTAssertFalse(element.label.contains("_") || value.contains("_"))
            }
        }
        assertNoRawDelimiters()
        // Preserve the selection after rendering; do not drag/select again.
        let underline = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Souligné")).firstMatch
        XCTAssertTrue(underline.waitForExistence(timeout: 5), window.debugDescription)
        app.toolbars.groups["text-formatting-group"].buttons.element(boundBy: 2).click()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "_"), object: editor)], timeout: 5)
        XCTAssertFalse((editor.value as? String)?.contains("<u>") == true)
        XCTAssertFalse((editor.value as? String)?.contains("<span") == true)
        assertNoRawDelimiters()
        app.toolbars.groups["text-formatting-group"].buttons.element(boundBy: 1).click()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "*_" + fragments[1] + "_*"), object: editor)], timeout: 5)
        assertNoRawDelimiters()
    }

    func testPreviewMixedSelectionFormattingPreservesSelectionAndNeighbor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("MixedSelection.md")
        let source = "test **mot** selection\n\n[Preserved link](https://example.com)\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        for enabled in [false, true] {
            let window = openPreviewBlockFixture(file, style: "Github2 (dark)", intraWordEmphasis: enabled)
            let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            let plain = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "test ", "test ")).firstMatch
            let styled = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "mot", "mot")).firstMatch
            XCTAssertTrue(plain.waitForExistence(timeout: 10), window.debugDescription)
            XCTAssertTrue(styled.waitForExistence(timeout: 10), window.debugDescription)
            plain.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: styled.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)))
            let bold = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Gras")).firstMatch
            XCTAssertTrue(bold.waitForExistence(timeout: 5), window.debugDescription)
            bold.click()
            let boldSource = "**test mot** selection\n\n[Preserved link](https://example.com)\n"
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", boldSource), object: editor)], timeout: 10)
            let italic = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Italique")).firstMatch
            XCTAssertTrue(italic.waitForExistence(timeout: 5))
            italic.click()
            let combined = "***test mot*** selection\n\n[Preserved link](https://example.com)\n"
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", combined), object: editor)], timeout: 10)
            XCTAssertFalse((editor.value as? String ?? "").contains("<"))
            for element in window.webViews.staticTexts.allElementsBoundByIndex {
                XCTAssertFalse(element.label.contains("**"))
                XCTAssertFalse((element.value as? String ?? "").contains("**"))
            }
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Mixed selection with common bold and italic styles"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.typeKey("s", modifierFlags: .command)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), combined)
            app.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, boldSource)
            app.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, source)
            app.typeKey("s", modifierFlags: .command)
        }
    }


    private func openPreviewBlockFixture(_ file: URL, style: String? = nil, intraWordEmphasis: Bool? = nil) -> XCUIElement {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MPDisableUpdater", "YES",
                               "-editorStartInPreviewMode", "NO", "-htmlMathJax", "NO",
                               "-extensionFencedCode", "YES", "-extensionStrikethough", "YES",
                               "-htmlSyntaxHighlighting", "NO", "-AppleLanguages", "(fr)"]
        if let style { app.launchArguments += ["-htmlStyleName", style] }
        if let intraWordEmphasis { app.launchArguments += ["-extensionIntraEmphasis", intraWordEmphasis ? "YES" : "NO"] }
        app.launch()
        XCTAssertTrue(app.textViews.matching(identifier: "editor-text-view").firstMatch.waitForExistence(timeout: 10))
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Ouvrir"].waitForExistence(timeout: 10), app.debugDescription)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        return app.windows[file.lastPathComponent]
    }

    private func choosePreviewBlock(_ label: String, window: XCUIElement) {
        let menu = window.webViews.popUpButtons["Type de ligne et encadré"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), window.debugDescription)
        XCTAssertTrue(menu.isEnabled)
        menu.click()
        // These are HTML menuitemradio controls, not AppKit menu items.
        let option = window.webViews.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(option.isEnabled)
        XCTAssertTrue(option.isHittable)
        // WebKit exposes menuitemradio as MenuItem, but it has no native
        // NSMenu to traverse. Click its visible position as the user does.
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    func testPreviewCodeSelectionDisablesInlineStylesAndConvertsBackToText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("CodeSelection.md")
        let source = "```text\nCodeword\n```\n\nNeighbor\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let window = openPreviewBlockFixture(file)
        let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let text = window.webViews.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Codeword", "Codeword")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), window.debugDescription)
        text.doubleClick()
        for label in ["Gras", "Italique", "Souligné", "Barré", "Code", "Retirer les styles", "Lien", "Modifier le texte"] {
            let button = window.webViews.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), window.debugDescription)
            XCTAssertFalse(button.isEnabled, "Inline action \(label) must be unavailable inside a code block")
        }
        XCTAssertEqual(editor.value as? String, source)
        choosePreviewBlock("Texte normal", window: window)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (value CONTAINS %@)", "```"), object: editor)], timeout: 10)
        let converted = try XCTUnwrap(editor.value as? String)
        XCTAssertFalse(converted.contains("```"))
        XCTAssertTrue(converted.contains("Neighbor"))
        let bold = window.webViews.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Gras")).firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: bold)], timeout: 10)
        XCTAssertTrue(bold.isEnabled, "Returning to text must restore ordinary formatting capabilities")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, source)
    }

    func testRenderingPreferencesFrenchControlsHaveSeparateFrames() throws {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MPDisableUpdater", "YES", "-AppleLanguages", "(fr)"]
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        let rendering = app.toolbars.buttons["Compilation"]
        XCTAssertTrue(rendering.waitForExistence(timeout: 10), app.debugDescription)
        rendering.click()
        let window = app.windows["Préférences"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "French rendering settings geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        let controls = (window.checkBoxes.allElementsBoundByIndex + window.popUpButtons.allElementsBoundByIndex).filter { $0.isHittable }
        XCTAssertGreaterThan(controls.count, 8)
        for (i, first) in controls.enumerated() {
            for second in controls.dropFirst(i + 1) {
                XCTAssertTrue(first.frame.intersection(second.frame).isEmpty,
                    "Overlapping rendering controls: \(first.label) \(first.frame) / \(second.label) \(second.frame)")
            }
        }
    }

    func testPreviewSingleClickDoesNotFlashSelectionInGithubDark() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = """
        var serial=0;
        document.addEventListener('mousedown',function(event){
          if(!event.target.closest('[data-mp-edit-id]'))return;
          var current=++serial, samples=[],deadline=performance.now()+650;
          function sample(){
            if(current!==serial)return;
            var text=getSelection().toString();
            if(samples.indexOf(text)<0)samples.push(text);
            if(performance.now()<deadline)requestAnimationFrame(sample);
            else document.getElementById('click-probe').textContent='Click samples: '+JSON.stringify(samples)+' count: '+event.detail;
          }
          requestAnimationFrame(sample);
        });
        """
        try script.write(to: directory.appendingPathComponent("click-probe.js"), atomically: true, encoding: .utf8)
        for prefix in ["", "> ", "# "] {
            let file = directory.appendingPathComponent("ClickFlash.md")
            let source = """
            \(prefix)Selectionword neighboring text.

            <div id="click-probe">Awaiting click</div>
            <script src="click-probe.js"></script>
            """
            try source.write(to: file, atomically: true, encoding: .utf8)
            let window = openPreviewBlockFixture(file, style: "Github2 (dark)")
            let text = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Selectionword neighboring text.", "Selectionword neighboring text.")).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10))
            let point = text.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: prefix == "# " ? 0.20 : 0.5))
            point.click()
            let probe = window.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Click samples:", "Click samples:")).firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 5), window.debugDescription)
            XCTAssertEqual(probe.value as? String ?? probe.label, "Click samples: [\"\"] count: 1", prefix)
            point.doubleClick()
            let bold = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Gras")).firstMatch
            XCTAssertTrue(bold.waitForExistence(timeout: 5))
            point.click()
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", "Click samples: [\"\"] count: 1", "Click samples: [\"\"] count: 1"), object: probe)], timeout: 5)
            XCTAssertFalse(bold.exists)
        }
    }

    func testSourceToolbarInlineActionsRetainOnlySelectedWord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("SourceSelection.md")
        let source = "Bonjour test après test\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let window = openPreviewBlockFixture(file, style: "Github2 (dark)")
        let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        for _ in 0..<8 { app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: []) }
        for _ in 0..<4 { app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .shift) }
        let styles = app.toolbars.groups["text-formatting-group"].buttons
        styles.element(boundBy: 0).click()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Bonjour **test** après test\n"), object: editor)], timeout: 5)
        // Toggle without selecting again: neighbouring words must stay untouched.
        styles.element(boundBy: 0).click()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", source), object: editor)], timeout: 5)
        styles.element(boundBy: 0).click()
        styles.element(boundBy: 1).click()
        let formatted = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(formatted.hasPrefix("Bonjour "))
        XCTAssertTrue(formatted.hasSuffix(" après test\n"))
        let word = try XCTUnwrap(formatted.range(of: "test"))
        let expected = formatted.replacingCharacters(in: word, with: "MODIFIED")
        editor.typeText("MODIFIED")
        XCTAssertEqual(editor.value as? String, expected, "Typing must replace only the retained word, not its sentence or delimiters")
    }

    func testBlankPreviewClickDismissesSelectionAndPanel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = """
        document.addEventListener('mouseup', function() {
          setTimeout(function() {
            document.getElementById('blank-click-probe').textContent =
              'After click: ' + JSON.stringify([getSelection().toString(),
                getComputedStyle(document.getElementById('macdown-preview-format')).display]);
          }, 500);
        });
        """
        try script.write(to: directory.appendingPathComponent("blank-click-probe.js"), atomically: true, encoding: .utf8)
        for prefix in ["", "> ", "# "] {
            let file = directory.appendingPathComponent("BlankClick.md")
            let source = """
            \(prefix)Bonjour test

            <div id="blank-click-probe" style="margin-top:300px">Awaiting click</div>
            <script src="blank-click-probe.js"></script>
            """
            try source.write(to: file, atomically: true, encoding: .utf8)
            let window = openPreviewBlockFixture(file, style: "Github2 (dark)")
            let text = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Bonjour test", "Bonjour test")).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), window.debugDescription)
            text.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).doubleClick()
            let bold = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Gras")).firstMatch
            XCTAssertTrue(bold.waitForExistence(timeout: 5))
            // Below the floating panel, still inside the preview's blank page.
            text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 190)).click()
            let probe = window.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "After click:", "After click:")).firstMatch
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR label == %@", "After click: [\"\",\"none\"]", "After click: [\"\",\"none\"]"), object: probe)], timeout: 5)
            XCTAssertFalse(bold.exists, prefix)
            XCTAssertEqual(window.textViews.matching(identifier: "editor-text-view").firstMatch.value as? String, source)
        }
    }

    func testPreviewStationaryPressDoesNotSelectWord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A local script is permitted by the preview CSP. It only observes the
        // real mouse gesture; synthetic DOM events cannot test native selection.
        let probeScript = """
        document.addEventListener('mousedown', function(event) {
          if (!event.target.closest('[data-mp-edit-id]')) return;
          setTimeout(function() {
            document.getElementById('mouse-probe').textContent = 'Held selection: [' + getSelection().toString() + '] click count: ' + event.detail;
          }, 200);
        });
        document.addEventListener('mouseup', function() {
          setTimeout(function() {
            document.getElementById('release-probe').textContent = 'Released selection: [' + getSelection().toString() + ']';
          }, 0);
        });
        """
        try probeScript.write(to: directory.appendingPathComponent("mouse-probe.js"), atomically: true, encoding: .utf8)
        for prefix in ["", "> ", "# "] {
            let file = directory.appendingPathComponent("MouseSelection.md")
            let source = """
            \(prefix)Selectionword neighboring text.

            <div id="mouse-probe">Awaiting press</div>
            <div id="release-probe">Awaiting release</div>
            <script src="mouse-probe.js"></script>
            """
            try source.write(to: file, atomically: true, encoding: .utf8)
            let window = openPreviewBlockFixture(file, style: "Github2 (dark)")
            let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            let text = window.webViews.staticTexts.matching(
                NSPredicate(format: "label == %@ OR value == %@", "Selectionword neighboring text.", "Selectionword neighboring text.")).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), window.debugDescription)
            let start = text.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: prefix == "# " ? 0.20 : 0.5))
            start.press(forDuration: 1)
            let probe = window.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Held selection:", "Held selection:")).firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 5), window.debugDescription)
            XCTAssertEqual(probe.value as? String ?? probe.label, "Held selection: [] click count: 1", prefix)
            start.doubleClick()
            let bold = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Gras")).firstMatch
            XCTAssertTrue(bold.waitForExistence(timeout: 5))
            let released = window.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Released selection:", "Released selection:")).firstMatch
            XCTAssertEqual(released.value as? String ?? released.label, "Released selection: [Selectionword]")
            text.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: prefix == "# " ? 0.20 : 0.5)).press(forDuration: 1)
            XCTAssertEqual(probe.value as? String ?? probe.label, "Held selection: [] click count: 1", prefix)
            XCTAssertFalse(bold.exists, "A stationary press must not reopen the formatting panel")
            start.press(forDuration: 1, thenDragTo: text.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: prefix == "# " ? 0.20 : 0.5)))
            XCTAssertEqual(probe.value as? String ?? probe.label, "Held selection: [] click count: 1", prefix)
            XCTAssertTrue(bold.waitForExistence(timeout: 5), "prefix=\(prefix); release=\(released.value as? String ?? released.label)")
            let releaseText = released.value as? String ?? released.label
            XCTAssertTrue(releaseText.hasPrefix("Released selection: [") && releaseText.hasSuffix("]"))
            let selected = String(releaseText.dropFirst("Released selection: [".count).dropLast())
            XCTAssertFalse(selected.isEmpty)
            XCTAssertLessThan(selected.count, "Selectionword".count, "Drag must select characters, not snap to a whole word")
            XCTAssertTrue("Selectionword".contains(selected))
            XCTAssertEqual(editor.value as? String, source)
            bold.click()
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "**\(selected)**"), object: editor)], timeout: 10)
            app.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, source)
        }
    }

    func testPreviewMultilineQuotePlainWordOpensFormattingPanel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for first in ["Firstword", "**Firstword**"] {
            let file = directory.appendingPathComponent("MultilineQuote.md")
            let source = ">\(first)\n> Secondword\n\nNeighbor\n"
            try source.write(to: file, atomically: true, encoding: .utf8)
            let window = openPreviewBlockFixture(file)
            let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            let text = window.webViews.staticTexts.matching(
                NSPredicate(format: "label == %@ OR value == %@", "Secondword", "Secondword")).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), window.debugDescription)
            text.doubleClick()
            let bold = window.webViews.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Gras")).firstMatch
            XCTAssertTrue(bold.waitForExistence(timeout: 5), window.debugDescription)
            XCTAssertTrue(bold.isEnabled)
            bold.click()
            let expected = ">\(first)\n> **Secondword**\n\nNeighbor\n"
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: editor)], timeout: 10)
            let italic = window.webViews.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Italique")).firstMatch
            XCTAssertTrue(italic.waitForExistence(timeout: 5))
            italic.click()
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "***Secondword***"), object: editor)], timeout: 10)
            XCTAssertFalse((editor.value as? String ?? "").contains("<"))
            app.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, expected)
            app.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, source)
        }
    }

    func testPreviewQuoteToCodeRemovesQuotePrefixAndKeepsNeighbor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("QuoteToCode.md")
        let source = "> Quotedword\n\nNeighbor\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let window = openPreviewBlockFixture(file)
        let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let text = window.webViews.staticTexts.matching(
            NSPredicate(format: "label == %@ OR value == %@", "Quotedword", "Quotedword")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), window.debugDescription)
        text.doubleClick()
        choosePreviewBlock("Code — bloc", window: window)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "```"), object: editor)], timeout: 10)
        let converted = try XCTUnwrap(editor.value as? String)
        XCTAssertFalse(converted.contains(">"), "A converted quote marker must not become code content")
        XCTAssertTrue(converted.contains("Quotedword"))
        XCTAssertTrue(converted.contains("Neighbor"))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, source)
    }

    func testQuickFormattingFollowsExclusiveSelectionAcrossPanes() throws {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MPDisableUpdater", "YES",
                               "-editorStartInPreviewMode", "NO", "-htmlMathJax", "NO",
                               "-AppleLanguages", "(en)"]
        app.launch()
        let editor = try XCTUnwrap(waitForEditor(timeout: 10))
        editor.click()
        editor.typeText("Sourceword.\n\nPreviewword.\n")
        editor.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [.option, .shift])
        let window = app.windows.containing(.textView, identifier: "editor-text-view").firstMatch
        let previewWord = window.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Previewword.", "Previewword.")).firstMatch
        XCTAssertTrue(previewWord.waitForExistence(timeout: 10))
        previewWord.doubleClick()
        let group = window.toolbars.groups["text-formatting-group"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        let bold = group.buttons.element(boundBy: 0)
        bold.click()
        let previewBold = "Sourceword.\n\n**Previewword**.\n"
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", previewBold), object: editor)], timeout: 10)
        editor.click()
        editor.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [.option, .shift])
        let previewPanelBold = window.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Gras")).firstMatch
        XCTAssertFalse(previewPanelBold.isHittable, "Source selection must hide the old preview toolbar")
        bold.click()
        let bothBold = "**Sourceword**.\n\n**Previewword**.\n"
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", bothBold), object: editor)], timeout: 10)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, previewBold)
    }

    func testListToolbarConvertsExistingBlockAndSupportsUndo() throws {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES",
                               "-editorStartInPreviewMode", "NO",
                               "-htmlTaskList", "YES",
                               "-AppleLanguages", "(en)"]
        app.launch()
        let editor = try XCTUnwrap(waitForEditor(timeout: 10))
        editor.click()
        editor.typeText("# Selected\n\nNeighbor.")
        editor.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: .command)
        let conversions = [("Unordered List", "- Selected\n\nNeighbor."),
                           ("Ordered List", "1. Selected\n\nNeighbor."),
                           ("Task List", "- [ ] Selected\n\nNeighbor.")]
        // AppKit exposes icon-only segments as unnamed buttons within the
        // identified group; segment order and localized tooltips have native coverage.
        let group = app.toolbars.groups["list-group"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertEqual(group.buttons.count, conversions.count)
        for (index, conversion) in conversions.enumerated() {
            let (label, expected) = conversion
            let button = group.buttons.element(boundBy: index)
            XCTAssertTrue(button.exists, label)
            button.click()
            XCTAssertEqual(editor.value as? String, expected)
        }
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "1. Selected\n\nNeighbor.")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(editor.value as? String, "- [ ] Selected\n\nNeighbor.")
    }

    func testNormalTextToolbarRemovesCurrentHeadingAndSupportsUndo() throws {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES",
                               "-editorStartInPreviewMode", "NO",
                               "-AppleLanguages", "(fr)"]
        app.launch()
        let editor = try XCTUnwrap(waitForEditor(timeout: 10))
        let normalText = app.toolbars.buttons["Texte normal"]
        XCTAssertTrue(normalText.waitForExistence(timeout: 5))
        for level in 1...3 {
            let source = "Avant\n" + String(repeating: "#", count: level) + " Titre é 日本語\nAprès"
            editor.click()
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(source)
            editor.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: [])
            normalText.click()
            XCTAssertEqual(editor.value as? String, "Avant\nTitre é 日本語\nAprès")
            app.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, source)
            app.typeKey("z", modifierFlags: [.command, .shift])
            XCTAssertEqual(editor.value as? String, "Avant\nTitre é 日本語\nAprès")
        }
        let window = app.windows.containing(.textView, identifier: "editor-text-view").firstMatch
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Texte normal beside heading buttons"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testReaderModeAppliesToEveryNewWindowAndKeepsProgressVisible() throws {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES",
                               "-editorStartInPreviewMode", "YES",
                               "-editorShowReadingProgress", "YES"]
        app.launch()
        for _ in 0..<3 {
            app.typeKey("n", modifierFlags: .command)
            let window = app.windows.firstMatch
            XCTAssertTrue(window.webViews.firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(window.textViews.matching(identifier: "editor-text-view").firstMatch.isHittable)
            let progress = window.staticTexts["reading-progress"]
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            XCTAssertEqual(progress.value as? String, "100%")
        }
    }

    func testReadingPositionUpdatesDuringEditorAndPreviewWheelScrolling() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("ReadingProgress.md")
        try String(repeating: "Reading progress paragraph.\n\n", count: 300)
            .write(to: file, atomically: true, encoding: .utf8)
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-MPDisableUpdater", "YES",
                               "-editorShowReadingProgress", "YES",
                               "-editorSyncScrolling", "NO",
                               "-editorStartInPreviewMode", "NO",
                               "-AppleLanguages", "(en)"]
        app.launch()
        app.typeKey("o", modifierFlags: .command)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let window = app.windows["ReadingProgress.md"]
        let editor = window.textViews.matching(identifier: "editor-text-view").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let progress = window.staticTexts["reading-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        editor.scroll(byDeltaX: 0, deltaY: -100000)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "100%"), object: progress)], timeout: 5)
        // With sync disabled the preview is still at its top. Its wheel event
        // must take ownership of the indicator without requiring a click.
        let preview = window.webViews.firstMatch
        preview.scroll(byDeltaX: 0, deltaY: 1000)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0%"), object: progress)], timeout: 5)
        preview.scroll(byDeltaX: 0, deltaY: -100000)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "100%"), object: progress)], timeout: 5)
    }

    func testReaderSettingsCanBeSelectedThroughPreferences() throws {
        app.typeKey(",", modifierFlags: .command)
        let general = app.toolbars.buttons["General"]
        if general.waitForExistence(timeout: 5) { general.click() }
        let appearance = app.popUpButtons["application-appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.click()
        app.menuItems["Appearance: Dark"].click()
        XCTAssertEqual(appearance.value as? String, "Appearance: Dark")
        let screenshot = XCTAttachment(screenshot: app.windows.containing(.popUpButton,
            identifier: "application-appearance").firstMatch.screenshot())
        screenshot.name = "Reader settings with forced dark appearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let position = app.checkBoxes["reading-progress-setting"]
        XCTAssertTrue(position.exists)
        if (position.value as? NSNumber)?.intValue != 1 { position.click() }
        XCTAssertEqual((position.value as? NSNumber)?.intValue, 1)
        XCTAssertTrue(app.staticTexts.matching(identifier: "reading-progress").firstMatch.waitForExistence(timeout: 5))
        let rendering = app.toolbars.buttons["Rendering"]
        XCTAssertTrue(rendering.exists)
        rendering.click()
        let wrapping = app.checkBoxes["code-wrap-setting"]
        XCTAssertTrue(wrapping.waitForExistence(timeout: 5))
        let initialWrapping = try XCTUnwrap(wrapping.value as? NSNumber).intValue
        let wrapIndicator = wrapping.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        wrapIndicator.click()
        XCTAssertEqual((wrapping.value as? NSNumber)?.intValue, 1 - initialWrapping)
        if initialWrapping == 1 { wrapIndicator.click() }
        XCTAssertEqual((wrapping.value as? NSNumber)?.intValue, 1)
        app.terminate()
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["General"].click()
        XCTAssertEqual(app.popUpButtons["application-appearance"].value as? String, "Appearance: Dark")
        XCTAssertEqual((app.checkBoxes["reading-progress-setting"].value as? NSNumber)?.intValue, 1)
        app.toolbars.buttons["Rendering"].click()
        XCTAssertEqual((app.checkBoxes["code-wrap-setting"].value as? NSNumber)?.intValue, 1)
    }

    /// Smoke test: App launches and shows at least one window.
    func testAppLaunchesWithWindow() throws {
        let firstWindow = app.windows.firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 5), "App should show at least one window after launch")
    }

    /// Smoke test: Editor text view is accessible.
    func testEditorTextViewExists() throws {
        let editor = app.textViews.matching(identifier: "editor-text-view").firstMatch
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
