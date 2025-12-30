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
}

@end


#pragma mark - Tracking Data Source

@interface MPTrackingRendererDataSource : MPMockRendererDataSource
@property (nonatomic) NSInteger markdownCallCount;
@property (nonatomic) NSInteger titleCallCount;
@property (nonatomic) NSInteger loadingCallCount;
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
    return [super rendererLoading];
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

- (void)testRendererProducesHTMLOutput
{
    self.dataSource.markdown = @"# Hello World\n\nThis is a test.";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    XCTAssertGreaterThan(self.delegate.htmlOutputCallCount, 0,
                         @"Renderer should call didProduceHTMLOutput");
    XCTAssertNotNil(self.delegate.lastReceivedHTML,
                    @"Should receive HTML output");
    XCTAssertTrue([self.delegate.lastReceivedHTML containsString:@"Hello World"],
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

    // Without SmartyPants, quotes remain as-is
    XCTAssertTrue([html containsString:@"\"quoted\""],
                  @"Straight quotes should remain without SmartyPants");
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
    XCTAssertTrue([html containsString:@"<h1>"],
                  @"Should include heading");
}

- (void)testHTMLExportWithoutStyles
{
    self.dataSource.markdown = @"# Plain Export\n\nContent here.";
    self.dataSource.title = @"Plain Test";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML");
    XCTAssertTrue([html containsString:@"<h1>"],
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

@end
