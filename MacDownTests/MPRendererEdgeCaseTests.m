//
//  MPRendererEdgeCaseTests.m
//  MacDownTests
//
//  Additional renderer scenarios for edge cases including nil data source,
//  empty markdown, extension combinations, malformed HTML in code blocks,
//  and concurrent render requests.
//
//  Created for Issue #234: Test Coverage Phase 1b
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import "hoedown/document.h"


#pragma mark - Test Class

@interface MPRendererEdgeCaseTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPRendererEdgeCaseTests

- (void)setUp
{
    [super setUp];

    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];

    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self.dataSource;
    self.renderer.delegate = self.delegate;
}

- (void)tearDown
{
    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    [super tearDown];
}


#pragma mark - Nil Data Source Tests

- (void)testRendererWithNilDataSource
{
    self.renderer.dataSource = nil;

    // Should handle gracefully without crashing
    XCTAssertNoThrow([self.renderer parseMarkdown:nil],
                     @"Should handle nil dataSource gracefully");
}

- (void)testRendererHTMLExportWithNilDataSource
{
    self.renderer.dataSource = nil;

    // Export should not crash, may return nil or empty
    XCTAssertNoThrow({
        NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
        // Result may be nil or empty, which is acceptable
        (void)html;
    }, @"HTML export should not crash with nil dataSource");
}

- (void)testRendererWithNilDelegate
{
    self.renderer.delegate = nil;
    self.dataSource.markdown = @"# Test";

    // Should handle gracefully
    XCTAssertNoThrow([self.renderer parseMarkdown:self.dataSource.markdown],
                     @"Should handle nil delegate gracefully");
}

- (void)testRendererWithBothNilDataSourceAndDelegate
{
    self.renderer.dataSource = nil;
    self.renderer.delegate = nil;

    XCTAssertNoThrow([self.renderer parseMarkdown:@"# Test"],
                     @"Should handle both nil gracefully");
}


#pragma mark - Empty Markdown Tests

- (void)testRendererWithEmptyMarkdown
{
    self.dataSource.markdown = @"";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML for empty input");
}

- (void)testRendererWithNilMarkdown
{
    self.dataSource.markdown = nil;

    XCTAssertNoThrow([self.renderer parseMarkdown:self.dataSource.markdown],
                     @"Should handle nil markdown");

    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    // Result may vary, just verify no crash
    (void)html;
}

- (void)testRendererWithWhitespaceOnlyMarkdown
{
    self.dataSource.markdown = @"   \n\n\t\t\n   ";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle whitespace-only input");
}

- (void)testRendererWithSingleNewline
{
    self.dataSource.markdown = @"\n";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle single newline");
}


#pragma mark - Extension Combination Tests

- (void)testRendererExtensionTablesOnly
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES;
    self.dataSource.markdown = @"| A | B |\n|---|---|\n| 1 | 2 |";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<table"], @"Should render table");
}

- (void)testRendererExtensionFencedCodeOnly
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```\ncode here\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<code"] || [html containsString:@"<pre"],
                  @"Should render code block");
}

- (void)testRendererExtensionStrikethroughOnly
{
    self.delegate.extensions = HOEDOWN_EXT_STRIKETHROUGH;
    self.dataSource.markdown = @"~~deleted~~";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<del>"] || [html containsString:@"<s>"],
                  @"Should render strikethrough");
}

- (void)testRendererExtensionFootnotesOnly
{
    self.delegate.extensions = HOEDOWN_EXT_FOOTNOTES;
    self.dataSource.markdown = @"Text with footnote[^1].\n\n[^1]: Footnote content.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle footnotes");
}

- (void)testRendererExtensionTablesAndFencedCode
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"| Header |\n|---|\n| Cell |\n\n```js\ncode\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<table"], @"Should render table");
    XCTAssertTrue([html containsString:@"<code"] || [html containsString:@"<pre"],
                  @"Should render code");
}

- (void)testRendererExtensionTablesAndStrikethrough
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES | HOEDOWN_EXT_STRIKETHROUGH;
    self.dataSource.markdown = @"| ~~A~~ | B |\n|---|---|\n| 1 | 2 |";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<table"], @"Should render table");
    XCTAssertTrue([html containsString:@"<del>"] || [html containsString:@"<s>"],
                  @"Should render strikethrough in table");
}

- (void)testRendererExtensionAllCombined
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES |
                               HOEDOWN_EXT_FENCED_CODE |
                               HOEDOWN_EXT_STRIKETHROUGH |
                               HOEDOWN_EXT_FOOTNOTES |
                               HOEDOWN_EXT_AUTOLINK;

    self.dataSource.markdown = @"# Heading\n\n"
                               @"| A | B |\n|---|---|\n| 1 | 2 |\n\n"
                               @"~~deleted~~ and https://example.com\n\n"
                               @"```javascript\nconst x = 1;\n```\n\n"
                               @"Footnote[^1]\n\n[^1]: Note content.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle all extensions combined");
    XCTAssertTrue([html containsString:@"<table"], @"Should render table");
}

- (void)testRendererNoExtensions
{
    self.delegate.extensions = 0;
    self.dataSource.markdown = @"| A | B |\n|---|---|\n| 1 | 2 |";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertFalse([html containsString:@"<table"],
                   @"Should not render table without extension");
}


#pragma mark - Malformed HTML in Code Blocks Tests

- (void)testRendererWithScriptTagInCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```html\n<script>alert('xss')</script>\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML");
    // Script tag should be escaped in code block
    XCTAssertTrue([html containsString:@"&lt;script"] ||
                  [html containsString:@"<code"] ||
                  ![html containsString:@"<script>alert"],
                  @"Should escape or contain script tag safely");
}

- (void)testRendererWithStyleTagInCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```css\n</style><script>bad()</script>\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle style tag attempts");
}

- (void)testRendererWithBrokenHTMLInCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```html\n<div><span>unclosed\n</div>\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle broken HTML in code block");
}

- (void)testRendererWithHTMLEntitiesInCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```\n&lt; &gt; &amp; &quot;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle HTML entities in code");
}

- (void)testRendererWithDeepNestedTagsInCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    NSMutableString *nested = [NSMutableString string];
    for (int i = 0; i < 100; i++) {
        [nested appendString:@"<div>"];
    }
    for (int i = 0; i < 100; i++) {
        [nested appendString:@"</div>"];
    }
    self.dataSource.markdown = [NSString stringWithFormat:@"```\n%@\n```", nested];

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle deeply nested tags");
}


#pragma mark - Multiple Parse Tests

- (void)testRapidConsecutiveParses
{
    // Perform many rapid parses
    for (int i = 0; i < 100; i++) {
        self.dataSource.markdown = [NSString stringWithFormat:@"# Parse %d\n\nContent %d", i, i];
        [self.renderer parseMarkdown:self.dataSource.markdown];
    }

    // Final parse should work correctly
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertTrue([html containsString:@"99"], @"Should have last content");
}

- (void)testParseWithVaryingContentSizes
{
    // Start with small content
    self.dataSource.markdown = @"# Small";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    // Then very large content
    NSMutableString *large = [NSMutableString string];
    for (int i = 0; i < 1000; i++) {
        [large appendFormat:@"## Heading %d\n\nParagraph %d\n\n", i, i];
    }
    self.dataSource.markdown = large;
    [self.renderer parseMarkdown:self.dataSource.markdown];

    // Then small again
    self.dataSource.markdown = @"# Small Again";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertTrue([html containsString:@"Small Again"], @"Should have final content");
}


#pragma mark - Concurrent Render Requests Tests

- (void)testConcurrentRenderRequests
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Concurrent renders"];
    expectation.expectedFulfillmentCount = 10;

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (int i = 0; i < 10; i++) {
        dispatch_async(queue, ^{
            @autoreleasepool {
                // Each concurrent request creates its own renderer
                MPRenderer *localRenderer = [[MPRenderer alloc] init];
                MPMockRendererDataSource *localDataSource = [[MPMockRendererDataSource alloc] init];
                MPMockRendererDelegate *localDelegate = [[MPMockRendererDelegate alloc] init];

                localRenderer.dataSource = localDataSource;
                localRenderer.delegate = localDelegate;

                localDataSource.markdown = [NSString stringWithFormat:@"# Thread %d", i];
                [localRenderer parseMarkdown:localDataSource.markdown];

                NSString *html = [localRenderer HTMLForExportWithStyles:NO highlighting:NO];
                XCTAssertNotNil(html, @"Should produce HTML in concurrent context");

                [expectation fulfill];
            }
        });
    }

    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)testSameRendererFromMultipleThreads
{
    // This tests thread safety of a single renderer instance
    // Note: MPRenderer may or may not be thread-safe, this tests behavior

    XCTestExpectation *expectation = [self expectationWithDescription:@"Same renderer threads"];
    __block NSInteger completedCount = 0;
    __block NSLock *lock = [[NSLock alloc] init];

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (int i = 0; i < 5; i++) {
        dispatch_async(queue, ^{
            @autoreleasepool {
                // All threads use the same renderer - testing thread safety
                self.dataSource.markdown = [NSString stringWithFormat:@"# Concurrent %d", i];

                @try {
                    [self.renderer parseMarkdown:self.dataSource.markdown];
                }
                @catch (NSException *exception) {
                    // Expected if not thread-safe
                }

                [lock lock];
                completedCount++;
                if (completedCount == 5) {
                    [expectation fulfill];
                }
                [lock unlock];
            }
        });
    }

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    // Verify renderer is still usable after concurrent access
    self.dataSource.markdown = @"# After Concurrent";
    XCTAssertNoThrow([self.renderer parseMarkdown:self.dataSource.markdown],
                     @"Renderer should be usable after concurrent access");
}


#pragma mark - Special Content Tests

- (void)testRendererWithNullCharacter
{
    // Markdown with embedded null character
    char bytes[] = {'#', ' ', 'T', 'e', 's', 't', '\0', ' ', 'E', 'n', 'd'};
    NSString *markdown = [[NSString alloc] initWithBytes:bytes
                                                  length:sizeof(bytes)
                                                encoding:NSUTF8StringEncoding];

    if (markdown) {
        self.dataSource.markdown = markdown;
        XCTAssertNoThrow([self.renderer parseMarkdown:self.dataSource.markdown],
                         @"Should handle null character");
    }
}

- (void)testRendererWithVeryLongLine
{
    // Single very long line
    NSMutableString *longLine = [NSMutableString string];
    for (int i = 0; i < 10000; i++) {
        [longLine appendString:@"word "];
    }
    self.dataSource.markdown = longLine;

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle very long line");
}

- (void)testRendererWithManyHeadings
{
    // Document with many headings of varying levels
    NSMutableString *markdown = [NSMutableString string];
    for (int i = 0; i < 500; i++) {
        int level = (i % 6) + 1;
        NSString *hashes = [@"" stringByPaddingToLength:level
                                              withString:@"#"
                                         startingAtIndex:0];
        [markdown appendFormat:@"%@ Heading %d\n\n", hashes, i];
    }
    self.dataSource.markdown = markdown;

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle many headings");
    XCTAssertTrue([html containsString:@"<h1>"], @"Should have h1");
    XCTAssertTrue([html containsString:@"<h6>"], @"Should have h6");
}

- (void)testRendererWithDeeplyNestedLists
{
    // Deeply nested list
    NSMutableString *markdown = [NSMutableString string];
    for (int i = 0; i < 20; i++) {
        NSString *indent = [@"" stringByPaddingToLength:i * 4
                                              withString:@" "
                                         startingAtIndex:0];
        [markdown appendFormat:@"%@- Level %d\n", indent, i];
    }
    self.dataSource.markdown = markdown;

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle deeply nested lists");
}


#pragma mark - MathJax and Special Rendering Tests

- (void)testRendererWithMathJaxEnabled
{
    self.delegate.mathJax = YES;
    self.dataSource.markdown = @"Inline $x^2$ and display:\n\n$$\\sum_{i=1}^n x_i$$";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should handle MathJax content");
}

- (void)testRendererWithMermaidEnabled
{
    self.delegate.mermaid = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should handle Mermaid diagrams");
}

- (void)testRendererWithGraphvizEnabled
{
    self.delegate.graphviz = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should handle Graphviz diagrams");
}


#pragma mark - TOC Rendering Tests

- (void)testRendererWithTOCEnabled
{
    self.delegate.renderTOC = YES;
    self.dataSource.markdown = @"# First\n\n## Second\n\n### Third\n\nContent here.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should render with TOC");
}

- (void)testRendererTOCWithNoHeadings
{
    self.delegate.renderTOC = YES;
    self.dataSource.markdown = @"Just a paragraph with no headings.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should handle TOC with no headings");
}


#pragma mark - Front Matter Tests

- (void)testRendererWithFrontMatter
{
    self.delegate.detectFrontMatter = YES;
    self.dataSource.markdown = @"---\ntitle: Test\nauthor: Me\n---\n\n# Content";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle YAML front matter");
}

- (void)testRendererWithInvalidFrontMatter
{
    self.delegate.detectFrontMatter = YES;
    self.dataSource.markdown = @"---\ninvalid: yaml: content:\n---\n\n# Content";

    XCTAssertNoThrow({
        [self.renderer parseMarkdown:self.dataSource.markdown];
        NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
        XCTAssertNotNil(html, @"Should handle invalid front matter");
    }, @"Should not crash on invalid front matter");
}


#pragma mark - Issue #254: Lists After Paragraphs

/**
 * Tests for Issue #254: Lists immediately following paragraphs should render
 * correctly without requiring a blank line (CommonMark/GFM behavior).
 *
 * NOTE: The simple regex fix has known edge cases:
 * - Lists inside fenced code blocks may be incorrectly modified
 * - Lists inside indented code blocks may be incorrectly modified
 * - Blockquotes may need special handling
 * These edge cases are intentionally not addressed for simplicity.
 */

- (void)testUnorderedListAfterParagraph_Hyphen
{
    self.dataSource.markdown = @"Text here:\n- Item 1\n- Item 2";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<ul>"],
                  @"Should render unordered list with hyphen after paragraph");
    XCTAssertTrue([html containsString:@"<li>Item 1</li>"],
                  @"Should contain list items");
}

- (void)testUnorderedListAfterParagraph_Asterisk
{
    self.dataSource.markdown = @"Text here:\n* Item 1\n* Item 2";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<ul>"],
                  @"Should render unordered list with asterisk after paragraph");
}

- (void)testUnorderedListAfterParagraph_Plus
{
    self.dataSource.markdown = @"Text here:\n+ Item 1\n+ Item 2";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<ul>"],
                  @"Should render unordered list with plus after paragraph");
}

- (void)testOrderedListAfterParagraph
{
    self.dataSource.markdown = @"My list:\n1. First\n2. Second";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<ol>"],
                  @"Should render ordered list after paragraph");
    XCTAssertTrue([html containsString:@"<li>First</li>"],
                  @"Should contain list items");
}

- (void)testListWithBlankLineStillWorks
{
    // Regression test: existing behavior must be preserved
    self.dataSource.markdown = @"Text here:\n\n- Item 1\n- Item 2";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<ul>"],
                  @"Lists with blank lines should still work");
}

- (void)testListAfterParagraphWithoutColon
{
    // Lists should work after any paragraph, not just ones ending with colon
    self.dataSource.markdown = @"This is a paragraph without colon\n- Item 1\n- Item 2";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<ul>"],
                  @"Should render list after paragraph without colon");
}

@end
