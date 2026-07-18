//
//  MPMarkdownRenderingTests.m
//  MacDown 3000
//
//  Created for Issue #58 (expanded from original Issue #89)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <cmark-gfm/mdmark.h>
#import "MPRendererTestHelpers.h"

// Uncomment to regenerate golden files
// #define REGENERATE_GOLDEN_FILES


#pragma mark - Test Class

@interface MPMarkdownRenderingTests : XCTestCase
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPMarkdownRenderingTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];

    // Create mock data source and delegate
    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];

    // Create renderer and wire it up
    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self.dataSource;
    self.renderer.delegate = self.delegate;
}

- (void)tearDown
{
    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    self.bundle = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

/**
 * Load a fixture file from the MacDownTests/Fixtures/ subdirectory.
 */
- (NSString *)loadFixture:(NSString *)name withExtension:(NSString *)ext
{
    NSURL *url = [self.bundle URLForResource:name
                               withExtension:ext
                                subdirectory:@"Fixtures"];
    if (!url) {
        return nil;
    }

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    if (error) {
        NSLog(@"Error loading fixture %@.%@: %@", name, ext, error);
        return nil;
    }

    return content;
}

/**
 * Render markdown through MPRenderer (MacDown's actual rendering code).
 * This calls parseMarkdown directly for synchronous testing.
 */
- (NSString *)renderMarkdown:(NSString *)markdown
              withExtensions:(int)extFlags
               rendererFlags:(int)rendFlags
{
    // Configure the delegate with the desired flags
    self.delegate.extensions = extFlags;
    self.renderer.rendererFlags = rendFlags;

    // Set the markdown content in the data source
    self.dataSource.markdown = markdown;

    // Parse the markdown synchronously (for testing)
    [self.renderer parseMarkdown:markdown];

    // Return the rendered HTML
    return [self.renderer currentHtml];
}

/**
 * Verify rendering against a golden file.
 * Loads <name>.md, renders it, and compares with <name>.html.
 * If REGENERATE_GOLDEN_FILES is defined, writes the output instead of comparing.
 */
- (void)verifyGoldenFile:(NSString *)name
          withExtensions:(int)extFlags
           rendererFlags:(int)rendFlags
{
    // Load input markdown
    NSString *input = [self loadFixture:name withExtension:@"md"];
    XCTAssertNotNil(input, @"Failed to load input fixture: %@.md", name);

    // Render the markdown
    NSString *actual = [self renderMarkdown:input
                             withExtensions:extFlags
                              rendererFlags:rendFlags];
    XCTAssertNotNil(actual, @"Rendering produced nil output for: %@", name);

#ifdef REGENERATE_GOLDEN_FILES
    // Regenerate mode: write the output to the golden file
    NSString *fixturePath = [[self.bundle resourcePath]
                             stringByAppendingPathComponent:@"Fixtures"];
    NSString *goldenPath = [fixturePath stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"%@.html", name]];

    NSError *error = nil;
    [actual writeToFile:goldenPath
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&error];

    if (error) {
        XCTFail(@"Failed to write golden file %@.html: %@", name, error);
    } else {
        NSLog(@"Regenerated golden file: %@.html", name);
    }
#else
    // Normal mode: compare with expected output
    NSString *expected = [self loadFixture:name withExtension:@"html"];
    XCTAssertNotNil(expected, @"Failed to load expected fixture: %@.html", name);

    XCTAssertEqualObjects(actual, expected,
                          @"Rendered output doesn't match golden file: %@", name);
#endif
}

/**
 * Extract every match of a regular expression's first capture group from a
 * string, in order of appearance. Used by the duplicate-heading dedup tests
 * to compare heading ids against TOC hrefs in document order (issue #503).
 */
- (NSArray<NSString *> *)matchesForPattern:(NSString *)pattern inString:(NSString *)string
{
    NSError *error = nil;
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern
                                                    options:0
                                                      error:&error];
    XCTAssertNil(error, @"Invalid regex pattern: %@", pattern);

    NSMutableArray<NSString *> *results = [NSMutableArray array];
    [regex enumerateMatchesInString:string
                             options:0
                               range:NSMakeRange(0, string.length)
                          usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        if (match.numberOfRanges > 1) {
            [results addObject:[string substringWithRange:[match rangeAtIndex:1]]];
        }
    }];
    return results;
}

#pragma mark - Basic Markdown Tests

- (void)testBasicHeaders
{
    int extFlags = 0;  // No extensions needed for basic headers
    int rendFlags = 0;

    [self verifyGoldenFile:@"basic"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testEmphasis
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"emphasis"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testLinks
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"links"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testImages
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"images"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - Code Block Tests

- (void)testCodeInline
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"code-inline"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testCodeFenced
{
    // Fenced code blocks require the FENCED_CODE extension
    int extFlags = 0 /* fenced code: core CommonMark */;
    int rendFlags = 0;

    [self verifyGoldenFile:@"code-fenced"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testCodeLanguages
{
    // Test fenced code blocks with language tags
    // MacDown adds Prism CSS classes like "language-python"
    int extFlags = 0 /* fenced code: core CommonMark */;
    int rendFlags = MDMARK_HTML_BLOCKCODE_INFORMATION;

    [self verifyGoldenFile:@"code-languages"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - List Tests

- (void)testListsUnordered
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"lists-unordered"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testListsOrdered
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"lists-ordered"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testListsNested
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"lists-nested"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - GFM Tests

- (void)testTables
{
    // Tables require the TABLES extension
    int extFlags = MDMARK_EXT_TABLES;
    int rendFlags = 0;

    [self verifyGoldenFile:@"tables"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testTaskLists
{
    // Task lists are MacDown's custom rendering feature
    int extFlags = 0;
    int rendFlags = MDMARK_HTML_USE_TASK_LIST;

    [self verifyGoldenFile:@"task-lists"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - Interactive Checkbox Tests (Issue #269)

/**
 * Test that checkboxes include data-checkbox-index attributes for interactivity.
 * Related to GitHub issue #269.
 */
- (void)testCheckboxHasDataIndex
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [ ] Task one\n- [x] Task two";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"First checkbox should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"Second checkbox should have index 1");
}

- (void)testUppercaseCheckedCheckboxHasDataIndex
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [X] Done";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"<input type=\"checkbox\" checked data-checkbox-index=\"0\">"],
                  @"Uppercase checked task-list markers should render as checked checkboxes");
}

/**
 * Test that multiple checkboxes get sequential indices.
 * Related to GitHub issue #269.
 */
- (void)testMultipleCheckboxesHaveSequentialIndices
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [ ] First\n- [x] Second\n- [ ] Third\n- [x] Fourth";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"First checkbox should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"Second checkbox should have index 1");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"2\""],
                  @"Third checkbox should have index 2");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"3\""],
                  @"Fourth checkbox should have index 3");
}

/**
 * Test that nested checkboxes maintain correct sequential indices.
 * Related to GitHub issue #269.
 */
- (void)testNestedCheckboxesHaveCorrectIndices
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [ ] Parent\n  - [x] Child 1\n  - [ ] Child 2\n- [x] Another parent";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    // Indices should be sequential regardless of nesting
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"Parent checkbox should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"First child checkbox should have index 1");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"2\""],
                  @"Second child checkbox should have index 2");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"3\""],
                  @"Another parent checkbox should have index 3");
}

/**
 * Test that regular list items don't get checkbox indices.
 * Related to GitHub issue #269.
 */
- (void)testMixedListsOnlyTaskItemsGetIndices
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- Regular item\n- [ ] Task item\n- Another regular\n- [x] Another task";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    // Only task items should have indices (0 and 1)
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"First task item should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"Second task item should have index 1");
    // Should not have index 2 (only 2 checkboxes)
    XCTAssertFalse([html containsString:@"data-checkbox-index=\"2\""],
                   @"Should only have indices 0 and 1 for the two checkboxes");
}

/**
 * Test that numbered task lists get checkbox indices.
 * Related to GitHub issue #269.
 */
- (void)testNumberedTaskListsGetIndices
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"1. [ ] First task\n2. [x] Second task\n3. [ ] Third task";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"First numbered task should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"Second numbered task should have index 1");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"2\""],
                  @"Third numbered task should have index 2");
}

/**
 * Test that an uppercase [X] checkbox renders as a checked checkbox, matching
 * the GFM spec. Related to GitHub issue #369.
 */
- (void)testUppercaseCheckboxRendersChecked
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [X] Capital X task";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"task-list-item"],
                  @"Uppercase [X] should render as a task-list item, not plain text");
    XCTAssertTrue([html containsString:@"checked"],
                  @"Uppercase [X] should render as a checked checkbox");
    XCTAssertFalse([html containsString:@"[X]"],
                   @"Uppercase [X] should not appear as literal text");
}

/**
 * Test that [x] and [X] share a single sequential index space, so the rendered
 * data-checkbox-index values stay aligned with the editor-side toggle logic.
 * Related to GitHub issue #369.
 */
- (void)testMixedCaseCheckboxesShareIndexSpace
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = MDMARK_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [ ] Lower unchecked\n- [X] Capital checked\n- [x] Lower checked";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"First checkbox should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"Uppercase [X] checkbox should take the next sequential index 1");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"2\""],
                  @"Third checkbox should have index 2");
}

- (void)testStrikethrough
{
    // Strikethrough requires the STRIKETHROUGH extension
    int extFlags = MDMARK_EXT_STRIKETHROUGH;
    int rendFlags = 0;

    [self verifyGoldenFile:@"strikethrough"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testAutolinks
{
    // Autolinks require the AUTOLINK extension
    int extFlags = MDMARK_EXT_AUTOLINK;
    int rendFlags = 0;

    [self verifyGoldenFile:@"autolinks"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - Other Tests

- (void)testBlockquotes
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"blockquotes"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testHorizontalRules
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"horizontal-rules"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testMixedComplex
{
    // Complex document with multiple GFM features enabled
    int extFlags = MDMARK_EXT_TABLES |
                   0 /* fenced code: core CommonMark */ |
                   MDMARK_EXT_AUTOLINK |
                   MDMARK_EXT_STRIKETHROUGH;
    int rendFlags = MDMARK_HTML_USE_TASK_LIST;

    [self verifyGoldenFile:@"mixed-complex"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testEdgeCases
{
    // Test edge cases like empty input, special characters, etc.
    int extFlags = MDMARK_EXT_TABLES |
                   0 /* fenced code: core CommonMark */;
    int rendFlags = 0;

    [self verifyGoldenFile:@"edge-cases"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - Regression Tests for Historical Parser Limitations

/**
 * Regression test for Issue #34: Lists after colons
 *
 * FIXED by the cmark-gfm migration (#77): lists immediately following a
 * paragraph now render as proper <ul>/<ol> elements per CommonMark, with
 * no preprocessor workaround needed.
 *
 * Related: Issue #34, PR #70 (reverted), Issue #77
 */
- (void)testRegressionIssue34_ListsAfterColons
{
    int extFlags = 0;
    int rendFlags = 0;

    // This currently produces broken output (lists don't render correctly)
    // The golden file documents the current behavior, not the desired behavior
    [self verifyGoldenFile:@"regression-issue34"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Regression test for Issue #36: Code blocks without blank lines
 *
 * FIXED: cmark-gfm recognizes fenced code blocks that immediately follow
 * text without any preprocessing (the hoedown-era blank-line insertion
 * workaround was removed in #77).
 *
 * Related: Issue #36, Issue #77
 */
- (void)testRegressionIssue36_CodeBlocksWithoutBlankLines
{
    int extFlags = 0 /* fenced code: core CommonMark */;
    int rendFlags = 0;

    [self verifyGoldenFile:@"regression-issue36"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Regression test for Issue #37: Square brackets in code blocks
 *
 * FIXED: cmark-gfm never scans fenced code block content for reference
 * links, so "]:" sequences render literally (the hoedown-era zero-width
 * space injection workaround was removed in #77).
 *
 * Related: Issue #37, Issue #77
 */
- (void)testRegressionIssue37_SquareBracketsInCode
{
    int extFlags = 0 /* fenced code: core CommonMark */;
    int rendFlags = MDMARK_HTML_BLOCKCODE_INFORMATION;

    [self verifyGoldenFile:@"regression-issue37"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Regression test for Issue #25: Adjacent shortcut links
 *
 * FIXED: cmark-gfm parses adjacent shortcut-style links correctly with no
 * preprocessing (the hoedown-era [text] -> [text][] rewrite was removed
 * in #77).
 *
 * Related: Issue #25, Issue #77
 */
- (void)testRegressionIssue25_AdjacentShortcutLinks
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"regression-issue25"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - Edge Case Tests

/**
 * Test that nil input is handled gracefully without crashing.
 */
- (void)testNilInput
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *html = [self renderMarkdown:nil
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    // Should return empty string or nil, but not crash
    XCTAssertTrue(html == nil || [html length] == 0,
                  @"Nil input should produce empty output");
}

/**
 * Test that empty string input is handled correctly.
 */
- (void)testEmptyInput
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *html = [self renderMarkdown:@""
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    // Should return empty string, not crash
    XCTAssertNotNil(html, @"Empty input should produce non-nil output");
    XCTAssertTrue([html length] == 0,
                  @"Empty input should produce empty output");
}

/**
 * Test that whitespace-only input is handled correctly.
 */
- (void)testWhitespaceOnlyInput
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *html = [self renderMarkdown:@"   \n\n   \t\t\n"
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    XCTAssertNotNil(html, @"Whitespace input should produce non-nil output");
    // Whitespace may be preserved or collapsed, but should not crash
}

/**
 * Test comprehensive unicode support with golden file.
 */
- (void)testUnicodeComprehensive
{
    int extFlags = 0 /* fenced code: core CommonMark */;
    int rendFlags = 0;

    [self verifyGoldenFile:@"unicode"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Test that malformed markdown doesn't crash the renderer.
 */
- (void)testMalformedMarkdown
{
    int extFlags = 0 /* fenced code: core CommonMark */ | MDMARK_EXT_TABLES;
    int rendFlags = 0;

    // Unclosed code block
    NSString *markdown1 = @"# Header\n```python\ncode without closing fence";
    NSString *html1 = [self renderMarkdown:markdown1
                            withExtensions:extFlags
                             rendererFlags:rendFlags];
    XCTAssertNotNil(html1, @"Unclosed code block should not crash");

    // Malformed table
    NSString *markdown2 = @"| Header |\n| No separator\n| Cell |";
    NSString *html2 = [self renderMarkdown:markdown2
                            withExtensions:extFlags
                             rendererFlags:rendFlags];
    XCTAssertNotNil(html2, @"Malformed table should not crash");

    // Unclosed emphasis
    NSString *markdown3 = @"**Bold without closing";
    NSString *html3 = [self renderMarkdown:markdown3
                            withExtensions:extFlags
                             rendererFlags:rendFlags];
    XCTAssertNotNil(html3, @"Unclosed emphasis should not crash");
}

/**
 * Test very large document performance.
 * This is a basic sanity check to ensure large inputs don't cause issues.
 */
- (void)testVeryLargeDocument
{
    int extFlags = 0 /* fenced code: core CommonMark */ | MDMARK_EXT_TABLES;
    int rendFlags = 0;

    // Generate a large markdown document (10,000 lines)
    NSMutableString *largeMarkdown = [NSMutableString string];
    for (int i = 0; i < 10000; i++) {
        [largeMarkdown appendFormat:@"Line %d with some text\n", i];
    }

    NSDate *start = [NSDate date];
    NSString *html = [self renderMarkdown:largeMarkdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];

    XCTAssertNotNil(html, @"Large document should render successfully");
    XCTAssertTrue(elapsed < 10.0,
                  @"Large document should render in reasonable time (<%f seconds)", elapsed);
}


#pragma mark - CRLF Line Ending Tests (Issue #382)

/**
 * Basic heading and paragraph with Windows CRLF line endings should render
 * identically to the same content with Unix LF endings.
 */
- (void)testHeadingAndParagraphWithCRLFLineEndings
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *lfMarkdown   = @"# Heading\n\nParagraph text.\n";
    NSString *crlfMarkdown = @"# Heading\r\n\r\nParagraph text.\r\n";

    NSString *lfHtml   = [self renderMarkdown:lfMarkdown
                               withExtensions:extFlags
                                rendererFlags:rendFlags];
    NSString *crlfHtml = [self renderMarkdown:crlfMarkdown
                               withExtensions:extFlags
                                rendererFlags:rendFlags];

    XCTAssertNotNil(crlfHtml, @"CRLF content should produce non-nil HTML");
    XCTAssertTrue([crlfHtml containsString:@"<h1 "],
                  @"CRLF heading should render as an <h1> element");
    XCTAssertTrue([crlfHtml containsString:@"Heading"],
                  @"CRLF heading text should appear in output");
    XCTAssertTrue([crlfHtml containsString:@"<p>"],
                  @"CRLF paragraph should render as <p>");
    XCTAssertEqualObjects(lfHtml, crlfHtml,
                          @"CRLF and LF content should produce identical HTML");
}

/**
 * List immediately after a paragraph (Issue #254, now native CommonMark
 * behavior in cmark-gfm). CRLF input must render identically to LF after
 * MPPreprocessMarkdown's line-ending normalization.
 */
- (void)testListAfterParagraphWithCRLFLineEndings
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *lfMarkdown   = @"Paragraph\n- List item\n";
    NSString *crlfMarkdown = @"Paragraph\r\n- List item\r\n";

    NSString *lfHtml   = [self renderMarkdown:lfMarkdown
                               withExtensions:extFlags
                                rendererFlags:rendFlags];
    NSString *crlfHtml = [self renderMarkdown:crlfMarkdown
                               withExtensions:extFlags
                                rendererFlags:rendFlags];

    XCTAssertTrue([crlfHtml containsString:@"<ul>"],
                  @"CRLF list after paragraph should render as <ul>");
    XCTAssertTrue([crlfHtml containsString:@"List item"],
                  @"CRLF list item text should appear in output");
    XCTAssertEqualObjects(lfHtml, crlfHtml,
                          @"CRLF and LF list-after-paragraph should produce identical HTML");
}

/**
 * Fenced code block immediately after text (Issue #36, now parsed natively
 * by cmark-gfm). CRLF input must render identically to LF after
 * MPPreprocessMarkdown's line-ending normalization.
 */
- (void)testFencedCodeAfterTextWithCRLFLineEndings
{
    int extFlags = 0 /* fenced code: core CommonMark */;
    int rendFlags = 0;

    NSString *lfMarkdown   = @"Text\n```\ncode\n```\n";
    NSString *crlfMarkdown = @"Text\r\n```\r\ncode\r\n```\r\n";

    NSString *lfHtml   = [self renderMarkdown:lfMarkdown
                               withExtensions:extFlags
                                rendererFlags:rendFlags];
    NSString *crlfHtml = [self renderMarkdown:crlfMarkdown
                               withExtensions:extFlags
                                rendererFlags:rendFlags];

    XCTAssertTrue([crlfHtml containsString:@"<code"],
                  @"CRLF fenced code block should render as <code>");
    XCTAssertTrue([crlfHtml containsString:@"code"],
                  @"CRLF fenced code content should appear in output");
    XCTAssertEqualObjects(lfHtml, crlfHtml,
                          @"CRLF and LF fenced-code-after-text should produce identical HTML");
}


#pragma mark - Heading Anchor ID Tests

// Headings should always receive a text-derived id attribute so that
// CommonMark/GFM-style anchor links like [text](#section) navigate to
// the corresponding heading in the preview.

- (void)testHeadingHasSlugBasedAnchorId
{
    NSString *html = [self renderMarkdown:@"## Foo Bar"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"foo-bar\""],
                  @"Heading should have a slug-based id derived from its text. Got: %@", html);
}

- (void)testHeadingAnchorIdPreservesUTF8
{
    NSString *html = [self renderMarkdown:@"## Introducción"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"introducción\""],
                  @"Heading id should preserve UTF-8 multi-byte characters. Got: %@", html);
}

- (void)testHeadingAnchorIdStripsPunctuation
{
    NSString *html = [self renderMarkdown:@"# Hello, World!"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"hello-world\""],
                  @"Heading id should drop ASCII punctuation. Got: %@", html);
}

- (void)testHeadingAnchorIdEmittedWithoutTOCPreference
{
    // Regression guard: ids must be emitted regardless of the
    // "Detect TOC token" preference state.
    self.delegate.renderTOC = NO;
    NSString *html = [self renderMarkdown:@"### Some Section"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"some-section\""],
                  @"Heading id must be emitted independent of TOC preference. Got: %@", html);
}

// Rendered heading content always escapes special characters to HTML entities
// (&amp; / &lt; / &gt; ...), so the slug must skip &...; sequences the same way
// it already skips <...> tags. Otherwise literal letters leak into the id and
// anchor links like [text](#qa) silently fail to navigate.

- (void)testHeadingAnchorIdSkipsAmpEntity
{
    // "Q&A" renders as "Q&amp;A"; the slug must be "qa", not "qampa".
    NSString *html = [self renderMarkdown:@"## Q&A"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"qa\""],
                  @"Heading id must skip the &amp; entity. Got: %@", html);
}

- (void)testHeadingAnchorIdSkipsLtGtEntity
{
    // "A < B" renders as "A &lt; B"; the entity is skipped like GitHub drops
    // the raw "<", but (matching GitHub's no-collapse behavior) the two
    // spaces surrounding it each become their own hyphen: "a--b", not "a-b"
    // or "a-lt-b".
    NSString *html = [self renderMarkdown:@"## A < B"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"a--b\""],
                  @"Heading id must skip the &lt; entity. Got: %@", html);
}

- (void)testHeadingAnchorIdSkipsMultipleEntities
{
    // "Tips & Tricks" renders as "Tips &amp; Tricks"; the entity is skipped
    // like GitHub drops the raw "&", but (matching GitHub's no-collapse
    // behavior) the two spaces surrounding it each become their own hyphen:
    // "tips--tricks", not "tips-tricks" or "tips-amp-tricks".
    NSString *html = [self renderMarkdown:@"## Tips & Tricks"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"tips--tricks\""],
                  @"Heading id must skip every HTML entity. Got: %@", html);
}

// Duplicate headings now dedup with github-slugger "-N" suffixes: the first
// occurrence keeps the base slug, and each subsequent occurrence gets the
// next available "-N" suffix (issue #503). "## C" and "## C++" both slugify
// to "c"; the second becomes "c-1", not a second "id=\"c\"".

- (void)testDuplicateHeadingsGetDedupedIds
{
    NSString *html = [self renderMarkdown:@"## C\n\n## C++\n"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"c\""],
                  @"First heading should have id=\"c\". Got: %@", html);
    XCTAssertTrue([html containsString:@"id=\"c-1\""],
                  @"Second heading (also slugifying to \"c\") should dedup to id=\"c-1\". Got: %@", html);

    NSUInteger firstC = [html rangeOfString:@"id=\"c\""].location;
    NSUInteger secondC = [html rangeOfString:@"id=\"c-1\""].location;
    XCTAssertNotEqual(firstC, NSNotFound);
    XCTAssertNotEqual(secondC, NSNotFound);
    XCTAssertLessThan(firstC, secondC,
                      @"id=\"c\" must appear before id=\"c-1\" in document order. Got: %@", html);
}

// Because this PR changes both the heading id and the TOC href, lock in the
// navigation guarantee: the TOC href must equal the heading id for the same
// heading text.

- (void)testTOCHrefMatchesHeadingId
{
    self.delegate.renderTOC = YES;
    NSString *html = [self renderMarkdown:@"[TOC]\n\n## Foo Bar"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"href=\"#foo-bar\""],
                  @"TOC entry must link to the heading slug. Got: %@", html);
    XCTAssertTrue([html containsString:@"id=\"foo-bar\""],
                  @"Heading must carry the matching id. Got: %@", html);
}

// Extends testTOCHrefMatchesHeadingId to duplicated headings (issue #503,
// requirements §2.5 / §4.2a): every TOC href must exactly equal the
// corresponding heading's id, in document order, including dedup suffixes.
// All headings are levels <=6 (the real-app case; kMPRendererTOCLevel is
// hardcoded to 6 in MPRenderer.m so every heading here is TOC-eligible).

- (void)testTOCHrefMatchesHeadingIdForDuplicateHeadings
{
    self.delegate.renderTOC = YES;
    NSString *markdown = @"[TOC]\n\n"
                          @"## Overview\n\n"
                          @"## Overview\n\n"
                          @"### Details\n\n"
                          @"## Overview\n\n"
                          @"### Details\n";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:0
                            rendererFlags:0];

    NSArray<NSString *> *headingIds =
        [self matchesForPattern:@"<h[1-6][^>]*\\bid=\"([^\"]+)\"" inString:html];
    NSArray<NSString *> *tocHrefs =
        [self matchesForPattern:@"href=\"#([^\"]+)\"" inString:html];

    NSArray<NSString *> *expectedIds = @[@"overview", @"overview-1", @"details",
                                          @"overview-2", @"details-1"];
    XCTAssertEqualObjects(headingIds, expectedIds,
                          @"Heading ids should dedup in document order. Got: %@", html);
    XCTAssertEqualObjects(tocHrefs, expectedIds,
                          @"TOC hrefs must exactly match heading ids, including dedup "
                          @"suffixes, in document order. Got: %@", html);
}

// Canonical github-slugger dedup sequence (issue #503, requirements §2.1):
// occurrences map keyed by generated slug; "Hello, Hello, Hello, World,
// Hello" must yield "hello, hello-1, hello-2, world, hello-3".

- (void)testDuplicateHeadingsDedupIdSequence
{
    NSString *markdown = @"## Hello\n\n## Hello\n\n## Hello\n\n## World\n\n## Hello\n";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:0
                            rendererFlags:0];

    NSArray<NSString *> *expectedIds = @[@"hello", @"hello-1", @"hello-2", @"world", @"hello-3"];
    NSUInteger searchLocation = 0;
    for (NSString *expectedId in expectedIds) {
        NSString *needle = [NSString stringWithFormat:@"id=\"%@\"", expectedId];
        NSRange range = [html rangeOfString:needle
                                     options:0
                                       range:NSMakeRange(searchLocation, html.length - searchLocation)];
        XCTAssertNotEqual(range.location, NSNotFound,
                          @"Expected to find %@ starting at or after location %lu. Got: %@",
                          needle, (unsigned long)searchLocation, html);
        if (range.location == NSNotFound) {
            break;
        }
        searchLocation = range.location + range.length;
    }
}

// While-loop edge case (requirements §3.2): a literal heading text that
// collides with an already-generated suffixed slug must still get its own
// unique suffix, not reuse "-1". "Hello, Hello 1, Hello" -> the third
// heading's base slug "hello" is taken, so it tries "hello-1" -- but that
// literal slug was already produced by the second heading's own text
// ("Hello 1" -> "hello-1") -- so it must advance to "hello-2".

- (void)testDuplicateHeadingsDedupWhileLoopHandlesSlugCollision
{
    NSString *markdown = @"## Hello\n\n## Hello 1\n\n## Hello\n";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:0
                            rendererFlags:0];

    NSArray<NSString *> *expectedIds = @[@"hello", @"hello-1", @"hello-2"];
    NSUInteger searchLocation = 0;
    for (NSString *expectedId in expectedIds) {
        NSString *needle = [NSString stringWithFormat:@"id=\"%@\"", expectedId];
        NSRange range = [html rangeOfString:needle
                                     options:0
                                       range:NSMakeRange(searchLocation, html.length - searchLocation)];
        XCTAssertNotEqual(range.location, NSNotFound,
                          @"Expected to find %@ starting at or after location %lu (the third "
                          @"heading must NOT collapse back to \"hello-1\"). Got: %@",
                          needle, (unsigned long)searchLocation, html);
        if (range.location == NSNotFound) {
            break;
        }
        searchLocation = range.location + range.length;
    }
}

// Empty/"section" fallback dedup (requirements §2.3): the fallback
// substitution to "section" must happen BEFORE dedup, so repeated
// punctuation-only headings dedup as "section, section-1, section-2, ...".

- (void)testEmptyHeadingsDedupWithSectionFallback
{
    NSString *markdown = @"## ¡¿?!\n\n## ¡¿?!\n\n## ¡¿?!\n";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:0
                            rendererFlags:0];

    NSArray<NSString *> *expectedIds = @[@"section", @"section-1", @"section-2"];
    NSUInteger searchLocation = 0;
    for (NSString *expectedId in expectedIds) {
        NSString *needle = [NSString stringWithFormat:@"id=\"%@\"", expectedId];
        NSRange range = [html rangeOfString:needle
                                     options:0
                                       range:NSMakeRange(searchLocation, html.length - searchLocation)];
        XCTAssertNotEqual(range.location, NSNotFound,
                          @"Expected %@ in document order. Got: %@", needle, html);
        if (range.location == NSNotFound) {
            break;
        }
        searchLocation = range.location + range.length;
    }
}

// The literal-slug path (a heading whose text already slugifies to
// "section") and the empty/punctuation-only fallback path (which also
// produces the base slug "section") must share the same dedup namespace
// (requirements §2.3): the fallback occurrence has to be treated as a
// duplicate of the literal one, not slugified independently.
- (void)testSectionFallbackSharesDedupNamespaceWithLiteralHeading
{
    NSString *markdown = @"## Section\n\n## ¡¿?!\n";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:0
                            rendererFlags:0];

    NSArray<NSString *> *expectedIds = @[@"section", @"section-1"];
    NSUInteger searchLocation = 0;
    for (NSString *expectedId in expectedIds) {
        NSString *needle = [NSString stringWithFormat:@"id=\"%@\"", expectedId];
        NSRange range = [html rangeOfString:needle
                                     options:0
                                       range:NSMakeRange(searchLocation, html.length - searchLocation)];
        XCTAssertNotEqual(range.location, NSNotFound,
                          @"Expected %@ in document order. Got: %@", needle, html);
        if (range.location == NSNotFound) {
            break;
        }
        searchLocation = range.location + range.length;
    }
}

// Per-render stability (requirements §2.4): dedup state must reset at the
// start of each render, so repeated renders of the same duplicated-heading
// document are byte-stable (guards against a global/static counter that
// keeps accumulating across renders).

- (void)testDuplicateHeadingDedupIsStableAcrossRenders
{
    NSString *markdown = @"## Hello\n\n## Hello\n\n## Hello\n";
    NSString *first = [self renderMarkdown:markdown withExtensions:0 rendererFlags:0];
    NSString *second = [self renderMarkdown:markdown withExtensions:0 rendererFlags:0];
    XCTAssertEqualObjects(first, second,
                          @"Repeated renders of the same duplicated-heading document must "
                          @"produce identical output (dedup state must reset per render).");
}

// Deep-heading desync guard (requirements §2.2 / §4.2b), exercised directly
// via the C API. In the shipped app kMPRendererTOCLevel is hardcoded to 6
// and Markdown headings never exceed level 6, so the TOC pass's
// "level > toc_level" skip branch is unreachable through the normal
// MPRenderer path (see testTOCHrefMatchesHeadingIdForDuplicateHeadings for
// that primary, reachable guarantee). This test exercises the branch
// directly: a level-3 duplicate is skipped from the TOC list (toc_level=2)
// but must still consume a dedup suffix, so the second level-2 "Foo"
// heading must get id="foo-2" in the HTML pass, and the TOC pass's href for
// that same heading must also be "#foo-2" (not "#foo-1", which is what you
// get if the skipped deep heading isn't counted).

- (void)testTOCHrefMatchesIdWhenDeeperDuplicateConsumesSuffix
{
    NSString *markdown = @"## Foo\n\n### Foo\n\n## Foo\n";
    NSData *markdownData = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = (const char *)markdownData.bytes;
    size_t length = markdownData.length;

    mdmark_options options = {0};

    char *renderedHtml = mdmark_render_html(bytes, length, &options);
    XCTAssertTrue(renderedHtml != NULL, @"mdmark_render_html returned NULL");
    NSString *html = [NSString stringWithUTF8String:renderedHtml];
    free(renderedHtml);

    char *renderedToc = mdmark_render_toc(bytes, length, &options, /*toc_level=*/2);
    XCTAssertTrue(renderedToc != NULL, @"mdmark_render_toc returned NULL");
    NSString *toc = [NSString stringWithUTF8String:renderedToc];
    free(renderedToc);

    NSArray<NSString *> *headingIds =
        [self matchesForPattern:@"<h[1-6][^>]*\\bid=\"([^\"]+)\"" inString:html];
    NSArray<NSString *> *tocHrefs =
        [self matchesForPattern:@"href=\"#([^\"]+)\"" inString:toc];

    XCTAssertEqualObjects(headingIds, (@[@"foo", @"foo-1", @"foo-2"]),
                          @"HTML pass must dedup every heading in document order "
                          @"regardless of level. Got: %@", html);
    XCTAssertEqualObjects(tocHrefs, (@[@"foo", @"foo-2"]),
                          @"TOC pass (toc_level=2) must skip the level-3 duplicate from "
                          @"the list but still advance the dedup counter for it, so the "
                          @"second level-2 heading's href must be \"foo-2\" (matching its "
                          @"actual HTML id), not \"foo-1\". Got TOC: %@ / HTML: %@", toc, html);
}

// GitHub-slugger parity (github-slugger semantics). Unicode punctuation and
// symbols (em/en dashes, curly quotes, ellipsis, the Latin-1 ¡-¿ block, etc.)
// are dropped rather than passed through raw, Latin-1 uppercase letters are
// lowercased, and each space/tab maps to exactly one hyphen without
// collapsing runs. Context: #471.

- (void)testHeadingAnchorIdDropsEmDash
{
    NSString *html = [self renderMarkdown:@"## Pregunta 5 — Cobro de AWS Lambda"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"pregunta-5--cobro-de-aws-lambda\""],
                  @"Em dash must be dropped, not passed through raw. Got: %@", html);
}

- (void)testHeadingAnchorIdLowercasesLatin1Uppercase
{
    NSString *html = [self renderMarkdown:@"## Índice"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"índice\""],
                  @"Latin-1 uppercase letters must be lowercased. Got: %@", html);
}

- (void)testHeadingAnchorIdDropsInvertedQuestionMark
{
    NSString *html = [self renderMarkdown:@"## ¿Qué es AWS?"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"qué-es-aws\""],
                  @"Inverted question mark and trailing '?' must be dropped. Got: %@", html);
}

- (void)testHeadingAnchorIdDropsEnDashBetweenWords
{
    NSString *html = [self renderMarkdown:@"## Conexión on-premises–AWS"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"conexión-on-premisesaws\""],
                  @"En dash between words must be dropped with no hyphen left behind. Got: %@", html);
}

- (void)testHeadingAnchorIdDoesNotCollapseHyphenRuns
{
    NSString *html = [self renderMarkdown:@"## Foo --- Bar"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"foo-----bar\""],
                  @"Consecutive spaces/hyphens must not collapse. Got: %@", html);
}

- (void)testHeadingAnchorIdKeepsUnchangedForOrdinaryUnicode
{
    NSString *html = [self renderMarkdown:@"## Introducción"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"introducción\""],
                  @"Ordinary accented letters must pass through unchanged. Got: %@", html);
}

// Sanity check against a real-world heading (verbatim, not modified) from the
// AWS certification study notes that originally surfaced this mismatch with
// GitHub's slug algorithm.

- (void)testHeadingAnchorIdMatchesGitHubForRealWorldHeading
{
    NSString *html = [self renderMarkdown:@"### Pregunta 16 — Conexión privada y consistente on-premises–AWS"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"pregunta-16--conexión-privada-y-consistente-on-premisesaws\""],
                  @"Heading id must match GitHub's slug for real-world content. Got: %@", html);
}

- (void)testHeadingAnchorIdFallsBackToSectionForPunctuationOnlyHeading
{
    NSString *html = [self renderMarkdown:@"## ¡¿?!"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"section\""],
                  @"A punctuation-only heading must fall back to the 'section' id. Got: %@", html);
}

#pragma mark - Empty Heading Crash Regression (#479)

// Hoedown treated a lone setext underline ('-' or '=') with no preceding
// text as a heading with empty content, which crashed its slug buffer
// (#479). cmark-gfm parses these inputs differently — '-' is an empty
// bullet list item and '=' is a literal paragraph — so no empty heading is
// ever produced. These inputs still render through the real parse path to
// pin the new behavior and guard against crashes.

- (void)testLoneHyphenHeadingDoesNotCrash
{
    // cmark-gfm: a lone '-' is an empty bullet list item, not an empty
    // setext heading needing a fallback id (issue #77)
    NSString *html = [self renderMarkdown:@"-"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"<ul>"] &&
                  [html containsString:@"<li></li>"],
                  @"A lone '-' must render as an empty list item without "
                  @"crashing. Got: %@", html);
}

- (void)testLoneEqualsHeadingDoesNotCrash
{
    // cmark-gfm: a lone '=' is a literal paragraph, not an empty setext
    // heading needing a fallback id (issue #77)
    NSString *html = [self renderMarkdown:@"="
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"<p>=</p>"],
                  @"A lone '=' must render as a literal paragraph without "
                  @"crashing. Got: %@", html);
}

- (void)testReportedHyphenCrashInputRenders
{
    // Exact document from the issue: it ends in a lone '-' after a blank
    // line. cmark-gfm: the trailing '-' renders as an empty list item, not
    // an empty heading with a fallback id (issue #77)
    NSString *html = [self renderMarkdown:@"_ - _ - _ -\n-\n\n-"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertNotNil(html,
                  @"Reported crash input must render to a non-nil string.");
    XCTAssertTrue([html containsString:@"<li></li>"],
                  @"The trailing lone '-' must render as an empty list item. "
                  @"Got: %@", html);
}

- (void)testEmptyHeadingWithTOCDoesNotCrash
{
    // The TOC rendering pass parses the same document a second time and
    // must also survive this input.
    self.delegate.renderTOC = YES;
    NSString *html = [self renderMarkdown:@"[TOC]\n\n-"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertNotNil(html,
                  @"Lone '-' with TOC enabled must render without crashing.");
}

@end
