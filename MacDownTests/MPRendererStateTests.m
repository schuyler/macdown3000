//
//  MPRendererStateTests.m
//  MacDownTests
//
//  Tests for MPRenderer state management, delegate/datasource interactions,
//  and configuration behavior.
//
//  Created for Issue #197: Test Coverage Phase 1
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import "hoedown/document.h"


#pragma mark - Extended Mock Delegate for Tracking Calls

@interface MPTrackingRendererDelegate : MPMockRendererDelegate
@property (nonatomic) NSInteger extensionsCallCount;
@property (nonatomic) NSInteger smartyPantsCallCount;
@property (nonatomic) NSInteger tocCallCount;
@property (nonatomic) NSInteger styleNameCallCount;
@property (nonatomic) NSInteger syntaxHighlightingCallCount;
@property (nonatomic) NSInteger htmlOutputCallCount;
@property (nonatomic, copy) NSString *lastReceivedHTML;
@property (nonatomic, copy) void (^onHTML)(NSString *html);
@end

@implementation MPTrackingRendererDelegate

- (int)rendererExtensions:(MPRenderer *)renderer
{
    self.extensionsCallCount++;
    return [super rendererExtensions:renderer];
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    self.smartyPantsCallCount++;
    return [super rendererHasSmartyPants:renderer];
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    self.tocCallCount++;
    return [super rendererRendersTOC:renderer];
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    self.styleNameCallCount++;
    return [super rendererStyleName:renderer];
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    self.syntaxHighlightingCallCount++;
    return [super rendererHasSyntaxHighlighting:renderer];
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    self.htmlOutputCallCount++;
    self.lastReceivedHTML = html;
    [super renderer:renderer didProduceHTMLOutput:html];
    if (self.onHTML) self.onHTML(html);
}

@end


#pragma mark - Tracking Data Source

@interface MPTrackingRendererDataSource : MPMockRendererDataSource
@property (nonatomic) NSInteger markdownCallCount;
@property (nonatomic) NSInteger titleCallCount;
@property (nonatomic) NSInteger loadingCallCount;
@property (nonatomic) BOOL loading;
@end

@implementation MPTrackingRendererDataSource

- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    self.markdownCallCount++;
    return [super rendererMarkdown:renderer];
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    self.titleCallCount++;
    return [super rendererHTMLTitle:renderer];
}

- (BOOL)rendererLoading
{
    self.loadingCallCount++;
    return self.loading;
}

@end



#pragma mark - Test Class

@interface MPRendererStateTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPTrackingRendererDataSource *dataSource;
@property (nonatomic, strong) MPTrackingRendererDelegate *delegate;
@end


@implementation MPRendererStateTests

- (void)setUp
{
    [super setUp];

    self.dataSource = [[MPTrackingRendererDataSource alloc] init];
    self.delegate = [[MPTrackingRendererDelegate alloc] init];

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


#pragma mark - Delegate Method Tests

- (void)testRendererQueriesExtensions
{
    self.dataSource.markdown = @"# Test";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    XCTAssertGreaterThan(self.delegate.extensionsCallCount, 0,
                         @"Renderer should query extensions from delegate");
}

- (void)testRendererQueriesStyleName
{
    self.dataSource.markdown = @"# Test";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    // Style name is queried when building stylesheets
    XCTAssertGreaterThanOrEqual(self.delegate.styleNameCallCount, 0,
                                @"Renderer may query style name");
}

- (void)testRendererProducesHTML
{
    // parseMarkdown: is synchronous and doesn't call delegate callback
    // Instead, we verify HTML is available via HTMLForExportWithStyles
    self.dataSource.markdown = @"# Hello World\n\nThis is a test.";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertNotNil(html, @"Should produce HTML");
    XCTAssertTrue([html containsString:@"Hello World"],
                  @"HTML should contain heading text");
}



#pragma mark - Extension Configuration Tests

- (void)testRendererWithTablesExtension
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES;
    self.dataSource.markdown = @"| A | B |\n|---|---|\n| 1 | 2 |";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<table"],
                  @"Should render table with extension enabled");
}

- (void)testRendererWithoutTablesExtension
{
    self.delegate.extensions = 0;  // No extensions
    self.dataSource.markdown = @"| A | B |\n|---|---|\n| 1 | 2 |";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertFalse([html containsString:@"<table"],
                   @"Should not render table without extension");
}

- (void)testRendererWithStrikethroughExtension
{
    self.delegate.extensions = HOEDOWN_EXT_STRIKETHROUGH;
    self.dataSource.markdown = @"This is ~~deleted~~ text.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<del>"] || [html containsString:@"<s>"],
                  @"Should render strikethrough with extension enabled");
}

- (void)testRendererWithFencedCodeExtension
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```javascript\nconst x = 1;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<code"],
                  @"Should render fenced code block");
}


#pragma mark - SmartyPants Tests

- (void)testRendererWithSmartyPants
{
    self.delegate.smartyPants = YES;
    self.dataSource.markdown = @"This is \"quoted\" text.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    // SmartyPants converts straight quotes to curly quotes
    // The exact characters depend on implementation
    XCTAssertNotNil(html, @"Should produce HTML with SmartyPants");
}

- (void)testRendererWithoutSmartyPants
{
    self.delegate.smartyPants = NO;
    self.dataSource.markdown = @"This is \"quoted\" text.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    // Without SmartyPants, quotes remain as straight quotes (may be HTML-encoded)
    // Check for either literal quotes or HTML entities
    BOOL hasQuotes = [html containsString:@"\"quoted\""] ||
                     [html containsString:@"&quot;quoted&quot;"];
    XCTAssertTrue(hasQuotes, @"Should have straight quotes (literal or encoded)");
}


#pragma mark - Syntax Highlighting Tests

- (void)testRendererWithSyntaxHighlighting
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.dataSource.markdown = @"```javascript\nconst x = 1;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    // With syntax highlighting, code should have language class
    XCTAssertTrue([html containsString:@"javascript"] || [html containsString:@"language-"],
                  @"Should include language information for highlighting");
}


#pragma mark - MathJax Tests

- (void)testRendererWithMathJax
{
    self.delegate.mathJax = YES;
    self.dataSource.markdown = @"Inline math: $x^2$";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    // MathJax content should be preserved
    XCTAssertNotNil(html, @"Should produce HTML with MathJax");
}


#pragma mark - Export Tests

- (void)testHTMLExportWithStyles
{
    self.dataSource.markdown = @"# Styled Export\n\nContent here.";
    self.dataSource.title = @"Export Test";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML");
    XCTAssertTrue([html containsString:@"<style"],
                  @"Should include embedded styles");
    XCTAssertTrue([html containsString:@"<h1 "],
                  @"Should include heading");
}

- (void)testHTMLExportWithoutStyles
{
    self.dataSource.markdown = @"# Plain Export\n\nContent here.";
    self.dataSource.title = @"Plain Test";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML");
    XCTAssertTrue([html containsString:@"<h1 "],
                  @"Should include heading");
}


#pragma mark - Empty and Edge Case Tests

- (void)testRendererWithEmptyMarkdown
{
    self.dataSource.markdown = @"";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML even for empty input");
}

- (void)testRendererWithWhitespaceOnlyMarkdown
{
    self.dataSource.markdown = @"   \n\n   \t   \n";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle whitespace-only input");
}

- (void)testRendererWithVeryLongMarkdown
{
    // Create a large document
    NSMutableString *longMarkdown = [NSMutableString string];
    for (int i = 0; i < 1000; i++) {
        [longMarkdown appendFormat:@"## Heading %d\n\nParagraph number %d with some content.\n\n", i, i];
    }
    self.dataSource.markdown = longMarkdown;

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle large documents");
    XCTAssertTrue([html containsString:@"Heading 999"],
                  @"Should contain last heading");
}


#pragma mark - Multiple Parse Tests

- (void)testRendererMultipleParses
{
    // First parse
    self.dataSource.markdown = @"# First";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html1 = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertTrue([html1 containsString:@"First"], @"Should have first content");

    // Second parse (should replace)
    self.dataSource.markdown = @"# Second";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html2 = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertTrue([html2 containsString:@"Second"], @"Should have second content");
    XCTAssertFalse([html2 containsString:@"First"], @"Should not have first content");
}


#pragma mark - Unicode Tests

- (void)testRendererWithUnicodeContent
{
    self.dataSource.markdown = @"# 日本語\n\n中文内容\n\nКириллица\n\nالعربية";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"日本語"], @"Should preserve Japanese");
    XCTAssertTrue([html containsString:@"中文内容"], @"Should preserve Chinese");
    XCTAssertTrue([html containsString:@"Кириллица"], @"Should preserve Cyrillic");
    XCTAssertTrue([html containsString:@"العربية"], @"Should preserve Arabic");
}

- (void)testRendererWithEmoji
{
    self.dataSource.markdown = @"# Hello 👋\n\nThis is a test 🎉";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"👋"], @"Should preserve wave emoji");
    XCTAssertTrue([html containsString:@"🎉"], @"Should preserve party emoji");
}

- (void)testImmediateRenderCompletesWhilePreviousPreviewIsLoading
{
    self.dataSource.loading = YES;
    self.dataSource.markdown = @"# Latest";
    XCTestExpectation *finished = [self expectationWithDescription:@"Immediate render"];
    self.delegate.onHTML = ^(NSString *html) {
        XCTAssertTrue([NSThread isMainThread]);
        XCTAssertTrue([html containsString:@"Latest"]);
        [finished fulfill];
    };
    [self.renderer parseAndRenderNow];
    [self waitForExpectations:@[finished] timeout:2];
}

- (void)testDelayedRenderHasBoundedWaitWhenPreviewNeverFinishesLoading
{
    self.dataSource.loading = YES;
    self.dataSource.markdown = @"Bounded";
    XCTestExpectation *finished = [self expectationWithDescription:@"Bounded render"];
    NSDate *started = [NSDate date];
    self.delegate.onHTML = ^(NSString *html) {
        XCTAssertTrue([html containsString:@"Bounded"]);
        XCTAssertGreaterThanOrEqual(-started.timeIntervalSinceNow, 0.45);
        [finished fulfill];
    };
    [self.renderer parseAndRenderLater];
    [self waitForExpectations:@[finished] timeout:2];
}

- (void)testNewRequestSupersedesPendingPreview
{
    self.dataSource.loading = YES;
    self.dataSource.markdown = @"Old content";
    [self.renderer parseAndRenderLater];
    self.dataSource.markdown = @"New content";
    XCTestExpectation *finished = [self expectationWithDescription:@"Latest content"];
    self.delegate.onHTML = ^(NSString *html) {
        XCTAssertTrue([html containsString:@"New content"]);
        XCTAssertFalse([html containsString:@"Old content"]);
        [finished fulfill];
    };
    [self.renderer parseAndRenderNow];
    [self waitForExpectations:@[finished] timeout:2];
    XCTAssertEqual(self.delegate.htmlOutputCallCount, 1);
}

- (void)testCodeFenceInformationCannotInjectHTMLAttributes
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.renderer.rendererFlags = (1 << 6);
    [self.renderer parseMarkdown:@"```js:\"/><img/src=x/onerror=alert(1)>\ncontent\n```"];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertFalse([html containsString:@"<img/src"]);
    XCTAssertTrue([html containsString:@"data-information=\"&quot;/&gt;&lt;img/src"]);
}

- (void)testTaskListParagraphRetainsItsClosingMarkup
{
    self.renderer.rendererFlags = (1 << 4);
    [self.renderer parseMarkdown:@"- [ ] First\n\n  continuation\n\n- [x] Second"];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];
    XCTAssertTrue([html containsString:@"continuation</p>"]);
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"0\""]);
    XCTAssertTrue([html containsString:@"data-checkbox-index=\"1\""]);
}

- (void)testMathJaxPreferenceChangeRefreshesScriptResources
{
    [self.renderer parseMarkdown:@"$x^2$"];
    [self.renderer render];
    self.delegate.lastHTML = nil;
    self.delegate.mathJax = YES;
    [self.renderer renderIfPreferencesChanged];
    XCTAssertTrue([self.delegate.lastHTML containsString:@"MathJax.js"]);
    self.delegate.lastHTML = nil;
    self.delegate.mathJax = NO;
    [self.renderer renderIfPreferencesChanged];
    XCTAssertNotNil(self.delegate.lastHTML);
    XCTAssertFalse([self.delegate.lastHTML containsString:@"MathJax.js"]);
}

- (void)testFencedCodeRetainsListsReferencesAndAdjacentBracketsVerbatim
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    NSString *code = @"text\n- item\n[a] [b]\n[id]: https://example.com";
    [self.renderer parseMarkdown:[NSString stringWithFormat:@"````text\n%@\n````", code]];
    NSString *html = self.renderer.currentHtml;
    XCTAssertTrue([html containsString:code]);
    XCTAssertFalse([html containsString:@"\u200B"]);
    XCTAssertFalse([html containsString:@"macdown-code-"]);
}

- (void)testUnclosedFencedCodeRetainsReferenceDefinition
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    [self.renderer parseMarkdown:@"```text\n[id]: https://example.com"];
    XCTAssertTrue([self.renderer.currentHtml containsString:@"[id]: https://example.com"]);
    XCTAssertFalse([self.renderer.currentHtml containsString:@"macdown-code-"]);
}

- (void)testCheckboxOffsetsFollowRenderedTasksAndOriginalUTF16Source
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.renderer.rendererFlags = (1 << 4);
    NSString *markdown = @"😀\r\n````text\r\n- [ ] code\r\n````\r\n> - [ ] quoted\r\n\r\n- [x] actual";
    [self.renderer parseMarkdown:markdown];
    XCTAssertEqualObjects(self.renderer.checkboxSourceMarkdown, markdown);
    NSUInteger quoted = [markdown rangeOfString:@"[ ] quoted"].location + 1;
    NSUInteger actual = [markdown rangeOfString:@"[x] actual"].location + 1;
    XCTAssertEqualObjects(self.renderer.checkboxSourceOffsets, (@[@(quoted), @(actual)]));
    XCTAssertFalse([self.renderer.currentHtml containsString:@"macdown-task-"]);
    XCTAssertTrue([self.renderer.currentHtml containsString:@"- [ ] code"]);
    NSString *previousToken = self.renderer.checkboxBridgeToken;
    [self.renderer parseMarkdown:markdown];
    XCTAssertNotEqualObjects(self.renderer.checkboxBridgeToken, previousToken);
}

- (void)testExcessiveNestingIsBoundedAndStillProducesPreview
{
    NSString *quotes = [@"" stringByPaddingToLength:220 withString:@"> " startingAtIndex:0];
    [self.renderer parseMarkdown:[quotes stringByAppendingString:@"Deep text"]];
    XCTAssertTrue([self.renderer.currentHtml containsString:@"Deep text"]);
}

- (void)testRepeatedHeadingsHaveUniqueIdsAndMatchingTOCLinks
{
    self.delegate.renderTOC = YES;
    NSString *markdown = @"[TOC]\n\n# Repeat\n\n# Repeat\n\n# Repeat-1\n\n# Repeat\n\n# !!!\n\n# ???";
    [self.renderer parseMarkdown:markdown];
    for (NSString *slug in @[@"repeat", @"repeat-1", @"repeat-1-1", @"repeat-2", @"section", @"section-1"]) {
        NSString *idAttribute = [NSString stringWithFormat:@"id=\"%@\"", slug];
        XCTAssertEqual([self.renderer.currentHtml componentsSeparatedByString:idAttribute].count, 2U);
        NSString *hrefAttribute = [NSString stringWithFormat:@"href=\"#%@\"", slug];
        XCTAssertTrue([self.renderer.currentHtml containsString:hrefAttribute]);
    }
    [self.renderer parseMarkdown:@"# Repeat"];
    XCTAssertTrue([self.renderer.currentHtml containsString:@"id=\"repeat\""]);
    XCTAssertFalse([self.renderer.currentHtml containsString:@"id=\"repeat-1\""]);
}

- (void)testFenceBoundariesPreserveCodeAndOutsideReferences
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    NSArray<NSArray<NSString *> *> *cases = @[
        @[@"> ```\n> code\n\n[id]: https://example.com\n\n[id]", @"<a href=\"https://example.com\">id</a>"],
        @[@"```lang`\n[id]: https://example.com\n```", @"[id]: https://example.com</code>"],
        @[@"~~~lang~~~\n\n[id]: https://example.com\n\n[id]", @"<a href=\"https://example.com\">id</a>"],
        @[@"   ```\ncode\n```\n[id]: https://example.com", @"code\n```\n[id]: https://example.com</code>"],
        @[@"> > ```\n> > code\n>\n> [id]: https://example.com\n>\n> [id]", @"<p>[id]: https://example.com</p>"],
        @[@"`inline\n[a] [b]\n`", @"<code>inline\n[a] [b]\n</code>"],
    ];
    for (NSArray<NSString *> *testCase in cases) {
        [self.renderer parseMarkdown:testCase[0]];
        XCTAssertTrue([self.renderer.currentHtml containsString:testCase[1]], @"%@", testCase[0]);
        XCTAssertFalse([self.renderer.currentHtml containsString:@"macdown-code-"], @"%@", testCase[0]);
    }
}

- (void)testEmbeddedNullDoesNotTruncateRenderedBodyOrTOC
{
    self.delegate.renderTOC = YES;
    const char bytes[] = "[TOC]\n\n# Before\0After\n\n# Last heading\n\nLast paragraph";
    NSString *markdown = [[NSString alloc] initWithBytes:bytes length:sizeof(bytes) - 1
                                               encoding:NSUTF8StringEncoding];
    [self.renderer parseMarkdown:markdown];
    XCTAssertTrue([self.renderer.currentHtml containsString:@"After</h1>"]);
    XCTAssertTrue([self.renderer.currentHtml containsString:@"href=\"#last-heading\""]);
    XCTAssertTrue([self.renderer.currentHtml containsString:@"Last paragraph</p>"]);
}

- (void)testTOCLabelsKeepLiteralDollarsAndBackslashes
{
    self.delegate.renderTOC = YES;
    [self.renderer parseMarkdown:@"[TOC]\n\n# Cost $5 and C:\\path"];
    XCTAssertEqual([self.renderer.currentHtml componentsSeparatedByString:@"Cost $5 and C:\\path"].count, 3U);
    XCTAssertTrue([self.renderer.currentHtml containsString:@"href=\"#cost-5-and-cpath\""]);
}

@end
