//
//  MPMermaidRenderingTests.m
//  MacDownTests
//
//  Tests for Mermaid diagram rendering in the Obj-C pipeline.
//  Verifies that mermaid scripts are included/excluded correctly,
//  code blocks get the proper language class, and rendering
//  survives preference changes and re-renders.
//
//  Related to #331
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import "hoedown/document.h"


#pragma mark - Test Class

@interface MPMermaidRenderingTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPMermaidRenderingTests

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


#pragma mark - Basic Mermaid Code Block Rendering

- (void)testMermaidCodeBlockProducesLanguageClass
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"language-mermaid"],
                  @"Mermaid code block should have language-mermaid class");
}

- (void)testMermaidCodeBlockPreservesGraphSource
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    // The graph source should survive parsing (possibly HTML-escaped)
    XCTAssertTrue([html containsString:@"graph TD"] ||
                  [html containsString:@"graph TD;"],
                  @"Graph source text should be preserved in HTML output");
    XCTAssertTrue([html containsString:@"A--&gt;B"] ||
                  [html containsString:@"A-->B"],
                  @"Graph edges should be preserved (escaped or literal)");
}

- (void)testMermaidCodeBlockWithoutFencedCodeExtension
{
    self.delegate.extensions = 0;  // No fenced code extension
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertFalse([html containsString:@"language-mermaid"],
                   @"Without fenced code extension, no language-mermaid class");
}


#pragma mark - Mermaid Script Inclusion

- (void)testMermaidScriptsIncludedWhenEnabled
{
    self.delegate.mermaid = YES;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertTrue([html containsString:@"mermaid.min.js"],
                  @"Should include Mermaid library");
    XCTAssertTrue([html containsString:@"mermaid.init.js"],
                  @"Should include Mermaid init script");
}

- (void)testMermaidScriptsExcludedWhenDisabled
{
    self.delegate.mermaid = NO;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertFalse([html containsString:@"mermaid.min.js"],
                   @"Should NOT include Mermaid library when disabled");
    XCTAssertFalse([html containsString:@"mermaid.init.js"],
                   @"Should NOT include Mermaid init script when disabled");
}

- (void)testMermaidScriptsExcludedWhenSyntaxHighlightingDisabled
{
    self.delegate.mermaid = YES;
    self.delegate.syntaxHighlighting = NO;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertFalse([html containsString:@"mermaid.min.js"],
                   @"Mermaid requires syntax highlighting to be enabled");
}

- (void)testMermaidScriptsExcludedFromExportWithoutHighlighting
{
    self.delegate.mermaid = YES;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertFalse([html containsString:@"mermaid.min.js"],
                   @"Mermaid scripts should not be in export without highlighting");
}


#pragma mark - Export CSS for Full-Width Mermaid Diagrams

- (void)testExportCSSIncludedWithStyles
{
    self.dataSource.markdown = @"# Test";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    // export.css is embedded as inline styles in the export path
    XCTAssertTrue([html containsString:@"overflow-wrap"],
                  @"export.css content should be present in styled export");
}


#pragma mark - Preference Change Detection

- (void)testRenderIfPreferencesChangedDetectsMermaidToggle
{
    self.delegate.mermaid = NO;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // Initial render to cache state
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    self.delegate.lastHTML = nil;

    // Toggle mermaid on
    self.delegate.mermaid = YES;
    [self.renderer renderIfPreferencesChanged];

    XCTAssertNotNil(self.delegate.lastHTML,
                    @"Toggling mermaid should trigger a re-render");
}

- (void)testRenderIfPreferencesChangedIgnoresWhenMermaidUnchanged
{
    self.delegate.mermaid = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // Initial render to cache state
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    self.delegate.lastHTML = nil;

    // No change
    [self.renderer renderIfPreferencesChanged];

    XCTAssertNil(self.delegate.lastHTML,
                 @"Should NOT re-render when mermaid preference is unchanged");
}

- (void)testStyleNameChangeTriggersReRender
{
    self.delegate.mermaid = YES;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.styleName = @"GitHub2";
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

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


#pragma mark - Multiple Mermaid Diagrams and Mixed Content

- (void)testMultipleMermaidDiagramsInSameDocument
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown =
        @"```mermaid\ngraph TD;\n    A-->B;\n```\n\n"
        @"Some text\n\n"
        @"```mermaid\nsequenceDiagram\n    Alice->>Bob: Hello\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    // Count occurrences of language-mermaid
    NSUInteger count = 0;
    NSRange searchRange = NSMakeRange(0, html.length);
    while (searchRange.location < html.length) {
        NSRange found = [html rangeOfString:@"language-mermaid"
                                   options:0
                                     range:searchRange];
        if (found.location == NSNotFound) break;
        count++;
        searchRange.location = found.location + found.length;
        searchRange.length = html.length - searchRange.location;
    }

    XCTAssertEqual(count, 2,
                   @"Both mermaid blocks should have language-mermaid class");
}

- (void)testMermaidWithOtherFencedCodeBlocks
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown =
        @"```mermaid\ngraph TD;\n    A-->B;\n```\n\n"
        @"```javascript\nconst x = 1;\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"language-mermaid"],
                  @"Should contain mermaid code block");
    XCTAssertTrue([html containsString:@"language-javascript"],
                  @"Should contain javascript code block alongside mermaid");
}

- (void)testMermaidDiagramTypesPreserved
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown =
        @"```mermaid\ngraph TD;\n    A-->B;\n```\n\n"
        @"```mermaid\nsequenceDiagram\n    Alice->>Bob: Hello\n```\n\n"
        @"```mermaid\ngantt\n    title A Gantt\n    section S1\n    Task1 :a1, 2024-01-01, 30d\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"graph TD"],
                  @"Flow chart source should be preserved");
    XCTAssertTrue([html containsString:@"sequenceDiagram"],
                  @"Sequence diagram source should be preserved");
    XCTAssertTrue([html containsString:@"gantt"],
                  @"Gantt chart source should be preserved");
}


#pragma mark - Edge Cases

- (void)testEmptyMermaidCodeBlock
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.dataSource.markdown = @"```mermaid\n\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertNotNil(html, @"Should not crash on empty mermaid block");
    XCTAssertTrue([html containsString:@"language-mermaid"],
                  @"Empty mermaid block should still have language class");
}

- (void)testMermaidAfterReparse
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;

    // First parse: plain markdown
    self.dataSource.markdown = @"# Hello";
    [self.renderer parseMarkdown:self.dataSource.markdown];

    // Second parse: mermaid
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer currentHtml];

    XCTAssertTrue([html containsString:@"language-mermaid"],
                  @"Re-parse should produce mermaid content");
    XCTAssertFalse([html containsString:@"Hello"],
                   @"Previous parse content should be gone");
}

- (void)testMermaidDisabledAfterBeingEnabled
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // First: enabled
    self.delegate.mermaid = YES;
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html1 = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];
    XCTAssertTrue([html1 containsString:@"mermaid.min.js"],
                  @"Should include mermaid scripts when enabled");

    // Second: disabled
    self.delegate.mermaid = NO;
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html2 = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];
    XCTAssertFalse([html2 containsString:@"mermaid.min.js"],
                   @"Should exclude mermaid scripts after disabling");
}


#pragma mark - Mermaid with Other Features

- (void)testMermaidWithMathJax
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.delegate.mathJax = YES;
    self.dataSource.markdown =
        @"```mermaid\ngraph TD;\n    A-->B;\n```\n\nInline math: $x^2$";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertTrue([html containsString:@"mermaid.init.js"],
                  @"Should include mermaid init script");
    XCTAssertTrue([html containsString:@"MathJax.js"],
                  @"Should include MathJax script alongside mermaid");
}

- (void)testMermaidWithGraphviz
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.mermaid = YES;
    self.delegate.graphviz = YES;
    self.dataSource.markdown =
        @"```mermaid\ngraph TD;\n    A-->B;\n```\n\n"
        @"```dot\ndigraph G { A -> B }\n```";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertTrue([html containsString:@"mermaid.init.js"],
                  @"Should include mermaid init script");
    XCTAssertTrue([html containsString:@"viz.init.js"],
                  @"Should include graphviz init script alongside mermaid");
}

@end
