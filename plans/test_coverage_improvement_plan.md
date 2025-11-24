# Test Coverage Improvement Plan for MacDown

**Document Version:** 1.0
**Date:** 2025-11-18
**Status:** Proposed

## Executive Summary

MacDown currently has minimal test coverage (~7% test-to-code ratio) focused primarily on low-level utility functions. This plan outlines a pragmatic, CI-friendly testing strategy to improve coverage of critical functionality without introducing flaky or hard-to-maintain tests.

**Key Recommendations:**
- Focus on **markdown rendering tests** (highest ROI)
- Add **document model logic tests** (core business logic)
- Implement **export/conversion tests** (critical features)
- Keep UI tests minimal and focused on smoke testing only
- All recommended tests are compatible with GitHub Actions macOS runners

## Current State Assessment

### What We Have (7 test files, ~822 lines)

| Test File | Coverage Area | Quality | Lines |
|-----------|--------------|---------|-------|
| MPUtilityTests.m | JS/ObjC bridge | Good | ~34 |
| MPStringLookupTests.m | String parsing | Excellent | ~188 |
| MPPreferencesTests.m | Preferences | Minimal | ~49 |
| MPHTMLTabularizeTests.m | HTML generation | Good | ~58 |
| MPColorTests.m | Color parsing | Good | ~39 |
| MPAssetTests.m | Asset handling | Good | ~122 |
| MPDocumentIOTests.m | File I/O, document state | Good | ~340 |

### What We're Missing (Critical Gaps)

**Zero Coverage:**
- Application controller logic
- Export functionality
- Plugin system
- Most extension categories
- All UI components

**Partial Coverage:**
- Markdown rendering engine (MPRenderer.m) - 18 golden file tests + 3 regression tests added (Issue #89, Issue #81)
- Document management (MPDocument.m) - File I/O and state management covered (Issue #90)

**Test Infrastructure:**
- ✅ XCTest framework configured
- ✅ GitHub Actions CI pipeline (test.yml)
- ✅ Runs on macOS-14, macOS-15, and macOS-15-intel (Intel-specific testing)
- ✅ Runtime launch tests (detects hang-on-launch issues)
- ✅ Code coverage reporting configured
- ❌ No integration tests
- ❌ Minimal UI testing

## CI-Friendly Testing Strategy

### Why This Matters

GitHub Actions macOS runners are:
- **Available:** macOS-14 with Xcode pre-installed
- **Fast enough:** For unit and integration tests
- **Reliable:** For deterministic tests
- **Limited:** By compute time (billable)

### What Works Well in CI

✅ **Unit tests** - Fast, deterministic
✅ **Rendering tests** - Input → Output validation
✅ **Logic tests** - Business rules without UI
✅ **File I/O tests** - Filesystem operations
✅ **Integration tests** - Component interactions
✅ **Basic UI tests** - Critical path smoke tests

### What to Avoid

❌ Complex UI automation (flaky, slow)
❌ Visual regression testing (inconsistent)
❌ Performance benchmarks (variable results)
❌ Tests requiring human interaction

## Priority Roadmap

### Phase 1: Core Rendering (HIGH PRIORITY)

**Goal:** Test the heart of MacDown - markdown to HTML conversion

**Status:** ✅ **PARTIALLY IMPLEMENTED** (Issue #89, Issue #81)
- ✅ `MPMarkdownRenderingTests.m` - 18 golden file tests for core markdown syntax (Issue #89)
- ✅ `MPMarkdownRenderingTests.m` - 3 regression tests for known hoedown bugs (Issue #81)
- ⏳ `MPSyntaxHighlightingTests.m` - Code block highlighting (planned)
- ⏳ `MPMathJaxRenderingTests.m` - Math formula rendering (planned)

**Actual Impact (MPMarkdownRenderingTests.m):**
- Tests added: 18 golden file test cases (Issue #89) + 3 regression tests (Issue #81)
- Fixtures created: 18 input/output pairs for core syntax + 6 files (3 pairs) for regression tests
- Coverage: TBD (measure after implementation)
- Maintenance: Low (golden file approach)

**Code Modifications Made:**
- Modified `MPCreateHTMLRenderer` in `MPRenderer.m` to accept `tocLevel` parameter
- Prevents unwanted header ID generation when table of contents is disabled
- Ensures tests can control rendering behavior for consistent output

**Example Tests:**
```objective-c
- (void)testHeaderRendering
- (void)testListRendering
- (void)testCodeBlockRendering
- (void)testTableRendering
- (void)testInlineFormattingBold
- (void)testInlineFormattingItalic
- (void)testInlineFormattingCode
- (void)testLinkRendering
- (void)testImageRendering
- (void)testBlockquoteRendering
- (void)testHorizontalRuleRendering
- (void)testGitHubFlavoredMarkdown
- (void)testNestedListRendering
- (void)testMalformedMarkdownHandling
- (void)testSpecialCharacterEscaping
- (void)testUnicodeSupport
```

### Phase 2: Document Logic (HIGH PRIORITY) - PARTIALLY COMPLETED

**Goal:** Test document state management without UI

**Test Files:**
- `MPDocumentIOTests.m` - ✅ COMPLETED (12 tests, file I/O, document state, autosave)
- Additional tests needed for complete document lifecycle coverage

**Estimated Impact:**
- Coverage: +3-5%
- Bug prevention: High
- Maintenance: Low
- CI time: +20-30 seconds

**Example Tests:**
```objective-c
// Document Creation & Loading
- (void)testDocumentInitialization
- (void)testLoadMarkdownFile
- (void)testLoadWithDifferentEncodings
- (void)testLoadEmptyFile
- (void)testLoadLargeFile

// Document State
- (void)testDirtyFlagOnEdit
- (void)testDirtyFlagAfterSave
- (void)testUndoRedoTracking
- (void)testDocumentModificationDate

// Document Saving
- (void)testSaveToFile
- (void)testSaveWithEncoding
- (void)testAutosaveNaming
- (void)testSaveConflictHandling

// Text Operations
- (void)testTextReplacement
- (void)testTextInsertion
- (void)testTextDeletion
```

### Phase 3: Export Functionality (MEDIUM PRIORITY)

**Goal:** Verify HTML/PDF export works correctly

**New Test Files:**
- `MPExportTests.m` - Export operations
- `MPHTMLGenerationTests.m` - Complete HTML document generation

**Estimated Impact:**
- Coverage: +2-4%
- Bug prevention: Medium-High
- Maintenance: Low
- CI time: +30-45 seconds

**Example Tests:**
```objective-c
// HTML Export
- (void)testHTMLExportBasic
- (void)testHTMLExportWithCSS
- (void)testHTMLExportWithJavaScript
- (void)testHTMLExportEmbeddedAssets
- (void)testHTMLExportLinkedAssets
- (void)testHTMLExportWithSyntaxHighlighting
- (void)testHTMLExportWithMathJax

// PDF Export
- (void)testPDFGenerationBasic
- (void)testPDFGenerationWithImages
- (void)testPDFGenerationWithStyles

// Export Options
- (void)testExportOptionsApplied
- (void)testExportFileNaming
- (void)testExportPathHandling
```

### Phase 4: Expanded Utility Tests (MEDIUM PRIORITY)

**Goal:** Complete coverage of utility classes

**Extended Test Files:**
- Expand `MPPreferencesTests.m`
- Add `MPAssetLoadingTests.m`
- Add `MPFileIOTests.m`

**Estimated Impact:**
- Coverage: +2-3%
- Bug prevention: Medium
- Maintenance: Low
- CI time: +15-20 seconds

**Example Tests:**
```objective-c
// Preferences
- (void)testThemePreference
- (void)testEditorFontPreference
- (void)testMarkdownExtensionsPreference
- (void)testPreferenceDefaults
- (void)testPreferenceMigrationWithTimeout  // ✅ Issue #169 - timeout protection added

// File I/O
- (void)testFileEncodingDetection
- (void)testUTF8FileLoading
- (void)testUTF16FileLoading
- (void)testBinaryFileRejection
- (void)testFilePermissionHandling
```

### Phase 5: Integration Tests (MEDIUM PRIORITY)

**Goal:** Test component interactions

**New Test Files:**
- `MPRendererIntegrationTests.m` - Renderer + Preferences + Assets
- `MPDocumentIntegrationTests.m` - Document + Renderer + Export

**Estimated Impact:**
- Coverage: +2-3%
- Bug prevention: Medium
- Maintenance: Medium
- CI time: +30-45 seconds

**Example Tests:**
```objective-c
// Renderer Integration
- (void)testRendererRespectsPreferences
- (void)testRendererLoadsCustomCSS
- (void)testRendererInjectsPrismAssets
- (void)testRendererHandlesMathJaxPreference

// Document Integration
- (void)testDocumentRenderingPipeline
- (void)testDocumentWithAssetReferences
- (void)testDocumentExportWithAllOptions
```

### Phase 6: Smoke Test UI (LOW PRIORITY)

**Goal:** Minimal critical path validation

**New Test Files:**
- `MPSmokeTests.m` - Basic UI flows (XCUITest)

**Estimated Impact:**
- Coverage: +1%
- Bug prevention: Medium
- Maintenance: High
- CI time: +60-120 seconds

**Example Tests (limit to 3-5):**
```objective-c
- (void)testLaunchAndQuit
- (void)testOpenFileAndRender
- (void)testTypingUpdatesPreview
```

**Note:** Only add if Phases 1-5 complete successfully

## Detailed Test Specifications

### MPMarkdownRenderingTests.m

**Status:** ✅ **IMPLEMENTED** (Issue #89, Issue #81)

**Purpose:** Comprehensive validation of markdown→HTML conversion using golden file testing

**Implementation Approach:**
- **Golden file pattern:** Each test compares rendered output against expected HTML
- **Fixtures:** 18 test cases in `MacDownTests/Fixtures/` directory
- **Naming:** `test-name.md` → `test-name.html` pairs
- **Coverage:** Headers, lists, code blocks, emphasis, links, blockquotes, etc.
- **Regression tests:** 3 tests documenting known hoedown parser bugs (Issue #81)

**Example Test Cases Implemented:**

1. ✅ **Headers** - `atx-headers.md` tests H1-H6 rendering
2. ✅ **Emphasis** - `emphasis.md` tests bold, italic, strikethrough
3. ✅ **Lists** - `unordered-list.md`, `ordered-list.md`, `nested-lists.md`
4. ✅ **Code Blocks** - `code-blocks.md`, `fenced-code.md`
5. ✅ **Links** - `links.md` tests inline and reference-style links
6. ✅ **Blockquotes** - `blockquote.md` tests quote rendering
7. ✅ **Horizontal Rules** - `horizontal-rule.md`
8. ✅ **Tables** - `table.md` tests GFM table syntax
9. ✅ **Inline Code** - `inline-code.md`
10. ✅ **Images** - `images.md`
11. ✅ **Autolinks** - `autolinks.md`
12. ✅ **HTML Blocks** - `html-blocks.md`
13. ✅ **Setext Headers** - `setext-headers.md`
14. ✅ **Special Characters** - `backslash-escapes.md`
15. ✅ **Line Breaks** - `hard-line-breaks.md`
16. ✅ **Mixed Content** - `mixed-content.md`
17. ✅ **Paragraphs** - `paragraphs.md`
18. ✅ **Table of Contents** - `toc.md` (with renderer modification for tocLevel parameter)

**Regression Tests (Issue #81):**

Three regression tests document known hoedown parser limitations that will be fixed in parser modernization (#77):

1. ✅ **Issue #34** - `regression-issue34.md/.html` - Lists after colons (requires blank lines)
2. ✅ **Issue #36** - `regression-issue36.md/.html` - Code blocks without blank lines
3. ✅ **Issue #37** - `regression-issue37.md/.html` - Square brackets in code blocks (is_ref() false positive)

These tests capture the current broken behavior to prevent regressions and validate fixes when the parser is modernized.

### MPDocumentIOTests.m - ✅ IMPLEMENTED

**Purpose:** Test document file I/O and state management without UI

**Status:** Completed with 12 test cases covering:
- API-level I/O operations (readFromData, dataOfType, writableTypes)
- Document state management (isDocumentEdited, markdown property, autosave)
- File operations (writeToURL with newline handling, read-only detection, save panel preparation)

**Implementation Reference:** See `/home/user/macdown3000/MacDownTests/MPDocumentIOTests.m`

**Future Expansion Opportunities:**
- Additional document lifecycle edge cases
- More complex file encoding scenarios
- Document versioning and conflict handling

### MPExportTests.m

**Purpose:** Validate export functionality

**Critical Test Cases:**

1. **HTML Export Structure**
   ```objective-c
   - (void)testHTMLExportStructure {
       self.document.text = @"# Title\n\nParagraph.";

       NSString *html = [self.document exportedHTML];

       XCTAssertTrue([html containsString:@"<!DOCTYPE html>"]);
       XCTAssertTrue([html containsString:@"<html>"]);
       XCTAssertTrue([html containsString:@"<head>"]);
       XCTAssertTrue([html containsString:@"<body>"]);
   }
   ```

2. **Asset Embedding**
   ```objective-c
   - (void)testHTMLExportWithEmbeddedCSS {
       // Test that CSS is embedded when option selected
       self.document.exportOptions = MPAssetEmbedded;
       NSString *html = [self.document exportedHTML];

       XCTAssertTrue([html containsString:@"<style>"]);
       XCTAssertFalse([html containsString:@"<link rel=\"stylesheet\""]);
   }
   ```

## Implementation Guidelines

### Test File Organization

```
MacDownTests/
├── MPMarkdownRenderingTests.m ✅ (implemented - Issue #89, Issue #81)
├── Rendering/ (planned)
│   ├── MPSyntaxHighlightingTests.m
│   └── MPMathJaxRenderingTests.m
├── Document/
│   ├── MPDocumentIOTests.m (✅ implemented - Issue #90 - file I/O and state)
│   └── MPExportTests.m (planned)
├── Utilities/ (existing)
│   ├── MPUtilityTests.m
│   ├── MPStringLookupTests.m
│   ├── MPColorTests.m
│   ├── MPPreferencesTests.m
│   ├── MPAssetTests.m
│   └── MPFileIOTests.m (new - planned)
├── Integration/ (planned)
│   ├── MPRendererIntegrationTests.m
│   └── MPDocumentIntegrationTests.m
├── UI/ (planned)
│   └── MPSmokeTests.m (XCUITest)
└── Fixtures/ ✅ (implemented - Issue #89, Issue #81)
    ├── atx-headers.md / .html
    ├── emphasis.md / .html
    ├── unordered-list.md / .html
    ├── ordered-list.md / .html
    ├── nested-lists.md / .html
    ├── code-blocks.md / .html
    ├── fenced-code.md / .html
    ├── links.md / .html
    ├── blockquote.md / .html
    ├── horizontal-rule.md / .html
    ├── table.md / .html
    ├── inline-code.md / .html
    ├── images.md / .html
    ├── autolinks.md / .html
    ├── html-blocks.md / .html
    ├── setext-headers.md / .html
    ├── backslash-escapes.md / .html
    ├── hard-line-breaks.md / .html
    ├── mixed-content.md / .html
    ├── paragraphs.md / .html
    ├── toc.md / .html
    ├── regression-issue34.md / .html  ✅ (Issue #81)
    ├── regression-issue36.md / .html  ✅ (Issue #81)
    └── regression-issue37.md / .html  ✅ (Issue #81)
```

### Testing Best Practices

1. **Isolation:** Each test should be independent
2. **Cleanup:** Use setUp/tearDown for test fixtures
3. **Assertions:** Clear, specific assertion messages
4. **Coverage:** One test per behavior, not per method
5. **Performance:** Keep tests fast (<100ms each)
6. **Determinism:** No randomness, no network calls
7. **Readability:** Test names describe what they test

### Code Coverage Reporting

**Current implementation** (configured in `.github/workflows/test.yml`):

- Tests run with `-enableCodeCoverage YES` flag
- Coverage reports generated using `xcrun xccov` in both JSON and text formats
- Coverage percentage extracted using Python script
- Reports uploaded as workflow artifacts with 30-day retention
- Coverage summary automatically posted to PR comments
- Robust error handling for when tests fail or coverage data is unavailable
- Uses only free GitHub Actions features (no third-party services)

### Continuous Integration Updates

**Current `.github/workflows/test.yml` includes:**

- ✅ Code coverage reporting (configured)
- ✅ PR comments with coverage summaries (configured)
- ✅ Coverage artifacts uploaded for review (configured)

**Future enhancements to consider:**

1. **Coverage threshold enforcement**
   - Fail if coverage drops below X%

2. **Performance monitoring**
   - Track test execution time trends

## Success Metrics

### Coverage Targets

| Phase | Target Coverage | Estimated Tests | Time Investment |
|-------|----------------|-----------------|-----------------|
| Phase 1 | 15-20% | 30-40 tests | 2-3 days |
| Phase 2 | 25-30% | 50-60 tests | 3-4 days |
| Phase 3 | 30-35% | 65-75 tests | 2-3 days |
| Phase 4 | 35-40% | 80-95 tests | 2-3 days |
| Phase 5 | 40-45% | 95-110 tests | 2-3 days |
| Phase 6 | 45-50% | 100-115 tests | 1-2 days |

### Quality Indicators

- ✅ All tests pass in CI
- ✅ Test suite runs in <5 minutes
- ⏳ Zero flaky tests (100% consistent results) - to be verified
- ✅ Code coverage visible in PRs (configured)
- ⏳ New features require tests (policy) - to be established

### Long-term Goals

1. **Minimum 40% code coverage** for core features
2. **100% coverage** for critical rendering logic
3. **Zero regressions** in tested functionality
4. **Fast feedback** (<5 min CI run)
5. **Developer confidence** to refactor safely

## Maintenance Strategy

### Ongoing Responsibilities

1. **Add tests with new features** - Make it policy
2. **Update tests when specs change** - Keep in sync
3. **Review coverage reports** - Identify gaps
4. **Prune redundant tests** - Keep suite lean
5. **Monitor CI performance** - Keep builds fast

### Red Flags to Watch

- Tests taking >10 minutes in CI
- Flaky tests (intermittent failures)
- Coverage decreasing over time
- Tests skipped/disabled
- Untested bug fixes

## Appendix: Test Fixtures

### Sample Test Files

**tests/Resources/TestFixtures/comprehensive.md**
```markdown
# Comprehensive Test Document

## Headers
### H3
#### H4

## Lists
- Unordered item
- Another item
  - Nested item

1. Ordered item
2. Second item

## Code
Inline `code` here.

```javascript
function test() {
    return true;
}
```

## Tables
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |

## Formatting
**bold** *italic* ~~strikethrough~~

## Links
[Link](https://example.com)

## Images
![Alt text](image.png)

## Blockquotes
> Quote here
> Multiple lines

## Math
$E = mc^2$

## Horizontal Rule
---
```

### Edge Case Files

**tests/Resources/TestFixtures/edge_cases.md**
```markdown
# Edge Cases

## Empty code block
```

```

## Unclosed formatting
**unclosed bold
*unclosed italic

## Special characters
< > & " '

## Unicode
日本語 🎉 Émojis

## Very long line
[very long line with many characters that might cause wrapping or performance issues...]
```

## References

- XCTest Documentation: https://developer.apple.com/documentation/xctest
- GitHub Actions for macOS: https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners
- Hoedown Library (MacDown's renderer): https://github.com/hoedown/hoedown
- Code Coverage in Xcode: https://developer.apple.com/documentation/xcode/code-coverage

---

**Next Steps:**
1. Review and approve this plan
2. Create test fixtures
3. Implement Phase 1 (rendering tests)
4. ✅ Set up code coverage reporting (completed)
5. Iterate through remaining phases
