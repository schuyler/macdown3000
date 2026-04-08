//
//  MPGraphvizRenderingTests.m
//  MacDownTests
//
//  Tests for Graphviz diagram rendering in the Obj-C pipeline.
//  Verifies that graphviz scripts are included/excluded correctly,
//  code blocks get the proper language class, and rendering
//  survives preference changes and re-renders.
//
//  Related to #332
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import "hoedown/document.h"


#pragma mark - Test Class

@interface MPGraphvizRenderingTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPGraphvizRenderingTests

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


#pragma mark - Basic Graphviz Code Block Rendering

- (void)testDotCodeBlockProducesLanguageClass
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"language-dot"],
                  @"Dot code block should have language-dot class");
}

- (void)testDotCodeBlockPreservesGraphSource
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"digraph G"],
                  @"Graph source text should be preserved in HTML output");
    XCTAssertTrue([html containsString:@"A -&gt; B"] ||
                  [html containsString:@"A -> B"],
                  @"Graph edges should be preserved (escaped or literal)");
}

- (void)testDotCodeBlockWithoutFencedCodeExtension
{
    self.delegate.extensions = 0;  // No fenced code extension
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertFalse([html containsString:@"language-dot"],
                   @"Without fenced code extension, no language-dot class");
}


#pragma mark - Graphviz Script Inclusion

- (void)testGraphvizScriptsIncludedWhenEnabled
{
    self.delegate.graphviz = YES;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertTrue([self.delegate.lastHTML containsString:@"viz.js"],
                  @"Should include Graphviz library");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"viz.init.js"],
                  @"Should include Graphviz init script");
}

- (void)testGraphvizScriptsExcludedWhenDisabled
{
    self.delegate.graphviz = NO;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertFalse([self.delegate.lastHTML containsString:@"viz.init.js"],
                   @"Should NOT include Graphviz init script when disabled");
}

- (void)testGraphvizScriptsExcludedWhenSyntaxHighlightingDisabled
{
    self.delegate.graphviz = YES;
    self.delegate.syntaxHighlighting = NO;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertFalse([self.delegate.lastHTML containsString:@"viz.init.js"],
                   @"Graphviz requires syntax highlighting to be enabled");
}


#pragma mark - Preference Change Detection

- (void)testRenderIfPreferencesChangedDetectsGraphvizToggle
{
    self.delegate.graphviz = NO;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // Initial render to cache state
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    self.delegate.lastHTML = nil;

    // Toggle graphviz on
    self.delegate.graphviz = YES;
    [self.renderer renderIfPreferencesChanged];

    XCTAssertNotNil(self.delegate.lastHTML,
                    @"Toggling graphviz should trigger a re-render");
}

- (void)testRenderIfPreferencesChangedIgnoresWhenGraphvizUnchanged
{
    self.delegate.graphviz = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // Initial render to cache state
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    self.delegate.lastHTML = nil;

    // No change
    [self.renderer renderIfPreferencesChanged];

    XCTAssertNil(self.delegate.lastHTML,
                 @"Should NOT re-render when graphviz preference is unchanged");
}

- (void)testStyleNameChangeTriggersReRender
{
    self.delegate.graphviz = YES;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.styleName = @"GitHub2";
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // Initial render
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    self.delegate.lastHTML = nil;

    // Change theme
    self.delegate.styleName = @"Clearness";
    [self.renderer renderIfPreferencesChanged];

    XCTAssertNotNil(self.delegate.lastHTML,
                    @"Changing theme should trigger re-render (full reload path)");
}


#pragma mark - Multiple Diagrams and Mixed Content

- (void)testMultipleGraphvizDiagramsInSameDocument
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown =
        @"```dot\ndigraph G { A -> B }\n```\n\n"
        @"Some text\n\n"
        @"```dot\ndigraph H { C -> D }\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    // Count occurrences of language-dot
    NSUInteger count = 0;
    NSRange searchRange = NSMakeRange(0, html.length);
    while (searchRange.location < html.length) {
        NSRange found = [html rangeOfString:@"language-dot"
                                   options:0
                                     range:searchRange];
        if (found.location == NSNotFound) break;
        count++;
        searchRange.location = found.location + found.length;
        searchRange.length = html.length - searchRange.location;
    }

    XCTAssertEqual(count, 2,
                   @"Both dot blocks should have language-dot class");
}

- (void)testGraphvizWithOtherFencedCodeBlocks
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown =
        @"```dot\ndigraph G { A -> B }\n```\n\n"
        @"```javascript\nconst x = 1;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"language-dot"],
                  @"Should contain graphviz code block");
    XCTAssertTrue([html containsString:@"language-javascript"],
                  @"Should contain javascript code block alongside graphviz");
}


#pragma mark - Edge Cases

- (void)testEmptyDotCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown = @"```dot\n\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertNotNil(html, @"Should not crash on empty dot block");
    XCTAssertTrue([html containsString:@"language-dot"],
                  @"Empty dot block should still have language class");
}

- (void)testGraphvizAfterReparse
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;

    // First parse: plain markdown
    self.dataSource.markdown = @"# Hello";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    // Second parse: graphviz
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"language-dot"],
                  @"Re-parse should produce graphviz content");
    XCTAssertFalse([html containsString:@"Hello"],
                   @"Previous parse content should be gone");
}

- (void)testGraphvizDisabledAfterBeingEnabled
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.dataSource.markdown = @"```dot\ndigraph G { A -> B }\n```";

    // First: enabled — use render (MPAssetFullLink) for filename checks
    self.delegate.graphviz = YES;
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    XCTAssertTrue([self.delegate.lastHTML containsString:@"viz.init.js"],
                  @"Should include graphviz scripts when enabled");

    // Second: disabled
    self.delegate.graphviz = NO;
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    XCTAssertFalse([self.delegate.lastHTML containsString:@"viz.init.js"],
                   @"Should exclude graphviz scripts after disabling");
}


#pragma mark - Graphviz with Other Features

- (void)testGraphvizWithMermaid
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.graphviz = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown =
        @"```dot\ndigraph G { A -> B }\n```\n\n"
        @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // Use render (MPAssetFullLink) for filename checks
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertTrue([self.delegate.lastHTML containsString:@"viz.init.js"],
                  @"Should include graphviz init script");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                  @"Should include mermaid init script alongside graphviz");
}

@end
