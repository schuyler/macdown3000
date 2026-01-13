//
//  MPMarkdownRenderingTests.m
//  MacDown 3000
//
//  Created for Issue #58 (expanded from original Issue #89)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <hoedown/document.h>
#import "MPRendererTestHelpers.h"
#import "hoedown_html_patch.h"

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
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = 0;

    [self verifyGoldenFile:@"code-fenced"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testCodeLanguages
{
    // Test fenced code blocks with language tags
    // MacDown adds Prism CSS classes like "language-python"
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

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
    int extFlags = HOEDOWN_EXT_TABLES;
    int rendFlags = 0;

    [self verifyGoldenFile:@"tables"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testTaskLists
{
    // Task lists are MacDown's custom rendering feature
    int extFlags = 0;
    int rendFlags = HOEDOWN_HTML_USE_TASK_LIST;

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
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
    self.dataSource.markdown = @"- [ ] Task one\n- [x] Task two";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""],
                  @"First checkbox should have index 0");
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""],
                  @"Second checkbox should have index 1");
}

/**
 * Test that multiple checkboxes get sequential indices.
 * Related to GitHub issue #269.
 */
- (void)testMultipleCheckboxesHaveSequentialIndices
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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

- (void)testStrikethrough
{
    // Strikethrough requires the STRIKETHROUGH extension
    int extFlags = HOEDOWN_EXT_STRIKETHROUGH;
    int rendFlags = 0;

    [self verifyGoldenFile:@"strikethrough"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testAutolinks
{
    // Autolinks require the AUTOLINK extension
    int extFlags = HOEDOWN_EXT_AUTOLINK;
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
    int extFlags = HOEDOWN_EXT_TABLES |
                   HOEDOWN_EXT_FENCED_CODE |
                   HOEDOWN_EXT_AUTOLINK |
                   HOEDOWN_EXT_STRIKETHROUGH;
    int rendFlags = HOEDOWN_HTML_USE_TASK_LIST;

    [self verifyGoldenFile:@"mixed-complex"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

- (void)testEdgeCases
{
    // Test edge cases like empty input, special characters, etc.
    int extFlags = HOEDOWN_EXT_TABLES |
                   HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = 0;

    [self verifyGoldenFile:@"edge-cases"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

#pragma mark - Regression Tests for Known Hoedown Limitations

/**
 * Regression test for Issue #34: Lists after colons
 *
 * NOTE: This issue is NOT currently fixed. Hoedown requires blank lines
 * before lists that follow paragraphs. This test documents the current
 * (non-ideal) behavior. Will be resolved by parser modernization (#77).
 *
 * Current behavior: Lists immediately following text with colons render
 * as paragraph text instead of proper <ul> or <ol> elements.
 *
 * Related: Issue #34, PR #70 (reverted)
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
 * FIXED: The markdown preprocessor now inserts blank lines before fenced
 * code blocks that immediately follow text, ensuring Hoedown recognizes
 * them correctly.
 *
 * Related: Issue #36
 */
- (void)testRegressionIssue36_CodeBlocksWithoutBlankLines
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = 0;

    [self verifyGoldenFile:@"regression-issue36"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Regression test for Issue #37: Square brackets in code blocks
 *
 * FIXED: The markdown preprocessor inserts a zero-width space between
 * ] and : inside fenced code blocks, preventing Hoedown's is_ref() from
 * matching these patterns as reference links.
 *
 * Related: Issue #37
 */
- (void)testRegressionIssue37_SquareBracketsInCode
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    [self verifyGoldenFile:@"regression-issue37"
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
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
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
    int extFlags = HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_TABLES;
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
    int extFlags = HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_TABLES;
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

@end
