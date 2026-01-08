# Test Coverage Improvement: Technical Design

## Overview

MacDown has excellent unit test coverage for markdown rendering (golden file tests), utilities, and rendering logic. However, significant gaps exist in UI integration, WebView behavior, file operations, and user workflows.

This document analyzes the gaps and proposes technical approaches to fill them through:
1. Enhanced unit tests for currently untested areas (no GUI required)
2. Integration tests with minimal refactoring  
3. Targeted XCUITests for critical user workflows
4. CI/CD automation

## Current State Analysis

### What We Test Well ✓

**Rendering Engine** (MPMarkdownRenderingTests, MPMathJaxRenderingTests, MPRendererEdgeCaseTests):
- Markdown → HTML conversion with golden files
- Known Hoedown bugs (#34, #36, #37) documented
- MathJax syntax preservation
- Syntax highlighting CSS classes
- HTML export structure
- Renderer edge cases: nil handling, concurrent rendering, extension combinations (Issue #234)

**Utilities**:
- String operations (MPStringLookupTests)
- Asset loading (MPAssetTests)
- Color conversion (MPColorTests)
- Preferences persistence (MPPreferencesTests)
- Syntax highlighter properties (HGMarkdownHighlighterTests - Issue #234)

**Document Lifecycle** (MPDocumentIOTests, MPDocumentLifecycleTests):
- File I/O and state management
- Document dirty flags, revert behavior, encoding detection (Issue #234)

**Notifications** (MPNotificationTests):
- NSNotificationCenter observer patterns, preference change notifications (Issue #234)

**Export** (MPHTMLExportTests, MPImageExportTests):
- HTML export workflows
- Image export with base64, linked images, alt text preservation (Issue #234)

**Edge Cases**:
- Unicode handling
- Malformed markdown
- Large documents (10K lines)

### Critical Gaps

**1. WebView Integration** (Biggest Gap)
- Preview rendering (HTML output vs. actual display)
- MathJax browser execution
- Prism syntax highlighting in WebView
- JavaScript errors in preview
- Scroll position restoration

**2. Document Lifecycle** (Partially Addressed)
- ✅ Basic lifecycle tests added (Issue #234)
- Window controller initialization
- `markdown` property getter/setter (returns nil in headless tests)
- Multiple simultaneous documents
- Document restoration

**3. Scroll Synchronization** (Issue #39, Issue #258)
- Logic tested ✓ (including bidirectional scroll sync)
- Integration not tested: actual scrolling, WebView coordination, image loading

**4. File Operations** (Partially Addressed)
- ✅ Image export tests added (Issue #234)
- Missing: disk full, permission errors, file conflicts, iCloud/network drives
- Missing: export writes actual files verification, PDF generation
- Missing: autosave failure recovery

**5. User Interactions**
- Zero tests for: menu actions, toolbar, keyboard shortcuts, preferences UI
- Missing: interactive task lists, link clicks in preview

**6. Error Handling**
- Limited coverage for graceful degradation
- Missing: WebView crash recovery, render timeouts

## Proposed Solution

### Phase 1: Enhanced Unit Tests (2-3 weeks) - PARTIALLY IMPLEMENTED

**No GUI required. Can run in CI headless.**

**Status:** Issue #234 implemented notification tests, document lifecycle tests, renderer edge case tests, syntax highlighter tests, and image export tests. Additional Phase 1 work outlined below remains to be completed.

#### 1.1 File Operations Integration Tests

**New Test Suite: MPFileOperationsTests**

```objc
// Test real filesystem operations
- testExportHTMLWritesActualFile
- testExportWithDiskFullError
- testExportWithPermissionError
- testExportOverwritesExistingFile
- testExportWithInvalidFilename
- testSaveWithFileConflict
- testAutosaveFailureRecovery
- testOpenFileDeletedDuringEdit
```

**Approach:**
- Use temporary directories for each test
- Simulate disk full (write to small disk image)
- Test error propagation and user messaging
- Verify file contents match expected output

#### 1.2 Export Workflow Tests

**Extend MPHTMLExportTests:**

```objc
- testExportHTMLCreateValidFile
- testExportedHTMLOpenableInBrowser  // Validate syntax
- testExportPDFCreatesFile
- testCopyAsHTMLToClipboard
- testExportWithEmbeddedImages
- testExportWithLinkedImages
```

**Approach:**
- Actually write to temp directory
- Parse exported HTML with NSXMLParser to validate
- Use NSTask to invoke browser/PDF validator
- Test clipboard operations

#### 1.3 Preferences Integration Tests

**New Test Suite: MPPreferencesIntegrationTests**

```objc
- testThemeChangeNotification
- testFontSizeChangeNotification
- testSyntaxHighlightingToggle
- testInvalidPreferenceValueFallback
- testPreferencesResetToDefault
```

**Approach:**
- Post NSNotification manually
- Mock MPPreferences observers
- Verify MPRenderer responds to changes
- Test edge cases (nil values, corrupted prefs)

#### 1.4 MPRenderer State Tests

**Extend MPRendererTestHelpers:**

```objc
- testRendererDelegateMethodsCalled
- testRendererDataSourceIntegration
- testRenderCancellation
- testConcurrentRenderRequests
- testRenderTimeout
```

**Approach:**
- Use existing mock infrastructure
- Add verification of method call sequences
- Test async behavior with expectations

#### 1.5 Error Handling Tests

**New Test Suite: MPErrorHandlingTests**

```objc
- testMalformedUTF8Recovery
- testRenderFailureGracefulDegradation
- testJavaScriptErrorHandling
- testMemoryPressureHandling
- testInvalidImageURLs
```

### Phase 2: Refactoring for Testability

**Minimal code changes to enable better testing.**

#### 2.1 Extract Testable Logic from View Controllers

**Problem:** MPDocument methods return early when `editor` outlet is nil.

**Solution:** Extract business logic to testable classes.

```objc
// New class: MPScrollSyncEngine
@interface MPScrollSyncEngine : NSObject
- (NSArray<NSNumber *> *)detectHeaderLocationsInMarkdown:(NSString *)markdown;
- (CGFloat)calculateScrollPositionForEditorOffset:(CGFloat)offset
                                   editorLocations:(NSArray<NSNumber *> *)editorLocs
                                  webViewLocations:(NSArray<NSNumber *> *)webViewLocs;
@end

// MPDocument uses it:
@property (strong) MPScrollSyncEngine *scrollSyncEngine;
```

**Tests:**
```objc
- testHeaderDetectionInMarkdown
- testScrollPositionCalculation
- testScrollSyncWithImages
- testScrollSyncEdgeCases
```

#### 2.2 Document Protocol for Testing

```objc
@protocol MPDocumentInterface
@property (copy) NSString *markdown;
@property (readonly) BOOL isLoading;
- (void)updateHeaderLocations;
@end

@interface MPDocument : NSDocument <MPDocumentInterface>
```

**Enables:**
- Mock documents for integration tests
- Testing multi-document scenarios
- Avoiding outlet nil issues

#### 2.3 Preference Observation Protocol

```objc
@protocol MPPreferenceObserver
- (void)preferenceDidChange:(NSString *)key value:(id)value;
@end
```

**Benefits:**
- Test preference changes without UI
- Verify components respond correctly
- Simulate preference corruption

### Phase 3: XCUITest Implementation

**Targeted UI tests for critical workflows.**

#### 3.1 XCUITest Target Setup

**New Target:** MacDownUITests

**Dependencies:**
```ruby
# Gemfile for CI
gem 'xcpretty'
gem 'fastlane'  # Optional but recommended
```

**Configuration:**
- Test target with host application
- Accessibility identifiers added to key UI elements
- Test data fixtures (sample markdown files)

#### 3.2 Critical Path Tests (8-10 tests max)

**File:** BasicWorkflowUITests.swift

```swift
class BasicWorkflowUITests: XCTestCase {
    func testCreateEditExportWorkflow() {
        // New doc → type markdown → preview updates → export
    }
    
    func testFileOpenSaveWorkflow() {
        // Open file → modify → save → verify disk
    }
    
    func testPreviewUpdatesInRealTime() {
        // Type in editor → preview renders (Issue #58)
    }
}
```

**File:** ScrollSyncUITests.swift

```swift
class ScrollSyncUITests: XCTestCase {
    func testScrollEditorUpdatesPreview() {
        // Issue #39: Scroll editor → preview follows
    }
    
    func testScrollSyncWithImages() {
        // Long doc with images → scroll stays synced
    }
    
    func testScrollPositionRestoration() {
        // Scroll → close → reopen → position restored
    }
}
```

**File:** ExportUITests.swift

```swift
class ExportUITests: XCTestCase {
    func testExportHTML() {
        // Menu → Export → file created
    }
    
    func testCopyAsHTML() {
        // Menu → Copy as HTML → clipboard has HTML
    }
}
```

**File:** PreferencesUITests.swift

```swift
class PreferencesUITests: XCTestCase {
    func testThemeChange() {
        // Prefs → change theme → preview updates
    }
    
    func testSyntaxHighlightingToggle() {
        // Prefs → toggle highlighting → preview changes
    }
}
```

#### 3.3 Page Object Pattern

**File:** MacDownPageObjects.swift

```swift
class EditorPage {
    let app: XCUIApplication
    var textView: XCUIElement { app.textViews["markdown-editor"] }
    
    func typeMarkdown(_ text: String) {
        textView.click()
        textView.typeText(text)
    }
}

class PreviewPage {
    let app: XCUIApplication
    var webView: XCUIElement { app.webViews["preview-pane"] }
    
    func waitForRender() {
        webView.waitForExistence(timeout: 2)
    }
    
    func containsText(_ text: String) -> Bool {
        return webView.staticTexts[text].exists
    }
}
```

**Benefits:**
- Reusable test components
- Maintainable tests
- Clear test structure

#### 3.4 Test Data Management

**Fixtures:**
```
MacDownUITests/
  Fixtures/
    simple.md
    with-images.md
    long-document.md
    math-equations.md
```

**Helper:**
```swift
class TestDataHelper {
    static func loadFixture(_ name: String) -> String {
        // Load test markdown files
    }
    
    static func createTempFile(content: String) -> URL {
        // Create temp file for open tests
    }
}
```

### Phase 4: CI/CD Integration

#### 4.1 GitHub Actions Configuration

**File:** .github/workflows/tests.yml

```yaml
name: Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  unit-tests:
    name: Unit Tests
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      
      - name: Run unit tests
        run: |
          xcodebuild test \
            -project MacDown.xcodeproj \
            -scheme MacDown \
            -destination 'platform=macOS' \
            -only-testing:MacDownTests \
            -enableCodeCoverage YES
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  ui-tests:
    name: UI Tests
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      
      - name: Run UI tests
        run: |
          xcodebuild test \
            -project MacDown.xcodeproj \
            -scheme MacDown \
            -destination 'platform=macOS' \
            -only-testing:MacDownUITests
```

#### 4.2 Test Reporting

**Tools:**
- xcpretty for readable output
- Code coverage uploaded to Codecov
- Test failure annotations in PR
- Slack/email notifications (optional)

## Success Criteria

**Test Coverage:**
- File operations tested with real filesystem
- Export workflows verified end-to-end
- Scroll sync integration validated
- WebView rendering behavior tested
- UI workflows covered for critical paths

**Test Quality:**
- Unit tests run in <2 minutes
- UI tests complete in <10 minutes
- Test flakiness <5%
- Clear failure messages for debugging

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| XCUITest flakiness | High | Use `waitForExistence()`, generous timeouts, retry logic |
| Refactoring breaks existing code | High | Incremental changes, feature flags, regression testing |
| Tests take too long | Medium | Run in parallel, split test suites, optimize fixtures |
| WebView testing unreliable | High | Mock WebView for unit tests, minimal UI tests |

## Alternatives Considered

### Alternative 1: Only Unit Tests
**Pros:** Fast execution, deterministic, easy to maintain  
**Cons:** Can't catch UI regressions, WebView issues, integration problems  
**Decision:** Rejected - gaps too significant for UI-heavy application

### Alternative 2: Full XCUITest Coverage
**Pros:** Complete UI coverage, catches all integration issues  
**Cons:** Slow execution, high maintenance, flaky tests, difficult to debug  
**Decision:** Rejected - diminishing returns, most issues catchable with unit tests

### Alternative 3: Hybrid Approach (Chosen)
**Pros:** Fast feedback from unit tests, targeted UI coverage for critical paths, best signal-to-noise ratio  
**Cons:** More complex test architecture, requires discipline to avoid over-testing  
**Decision:** Accepted - balances coverage breadth with test suite maintainability

## References

- Issue #39: Preview pane scroll position on long documents
- Issue #58: Test coverage improvements
- Issue #77: Parser modernization (depends on good tests)
- Issue #143: Horizontal rule detection
- Issue #144: Sort logic edge cases

## Appendix: Quick Wins

**Can implement immediately (1-2 days each):**

1. **Export file verification**
```objc
- (void)testExportHTMLCreatesValidFile {
    NSString *markdown = @"# Test\n\nContent";
    NSURL *tempURL = [self temporaryFileURL];
    
    BOOL success = [self.document exportHTMLToURL:tempURL error:nil];
    XCTAssertTrue(success);
    
    NSString *html = [NSString stringWithContentsOfURL:tempURL ...];
    XCTAssertTrue([html containsString:@"<h1>Test</h1>"]);
}
```

2. **Scroll sync math tests**
```objc
- (void)testScrollPositionCalculation {
    NSArray *editorLocs = @[@100, @200, @300];
    NSArray *previewLocs = @[@50, @150, @250];
    
    CGFloat result = [MPScrollSyncEngine 
        calculateScrollPositionForOffset:150
        editorLocations:editorLocs
        previewLocations:previewLocs];
    
    XCTAssertEqualWithAccuracy(result, 100, 1.0);
}
```

3. **Clipboard operations**
```objc
- (void)testCopyAsHTML {
    self.document.markdown = @"# Test";
    [self.document copyAsHTML:nil];
    
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *html = [pb stringForType:NSPasteboardTypeHTML];
    XCTAssertNotNil(html);
    XCTAssertTrue([html containsString:@"<h1>"]);
}
```

---

**End of Document**