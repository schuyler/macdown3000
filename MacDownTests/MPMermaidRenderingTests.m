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
#import <WebKit/WebKit.h>
#import "WebView+WebViewPrivateHeaders.h"


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

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.min.js"],
                  @"Should include Mermaid library");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                  @"Should include Mermaid init script");
}

- (void)testMermaidScriptsExcludedWhenDisabled
{
    self.delegate.mermaid = NO;
    self.delegate.syntaxHighlighting = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertFalse([self.delegate.lastHTML containsString:@"mermaid.min.js"],
                   @"Should NOT include Mermaid library when disabled");
    XCTAssertFalse([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                   @"Should NOT include Mermaid init script when disabled");
}

- (void)testMermaidScriptsIncludedWhenSyntaxHighlightingDisabled
{
    self.delegate.mermaid = YES;
    self.delegate.syntaxHighlighting = NO;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.min.js"],
                  @"Should include Mermaid library");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                  @"Should include Mermaid init script");
}

- (void)testPrismScriptsExcludedWhenSyntaxHighlightingDisabledWithMermaidEnabled
{
    self.delegate.mermaid = YES;
    self.delegate.syntaxHighlighting = NO;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.dataSource.markdown = @"```mermaid\ngraph TD;\n    A-->B;\n```";

    // Use render (MPAssetFullLink) so script URLs contain filenames
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertFalse([self.delegate.lastHTML containsString:@"prism-core.min.js"],
                   @"Should NOT include Prism when syntax highlighting is "
                   @"disabled, even though Mermaid is enabled");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.min.js"],
                  @"Should still include Mermaid library");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                  @"Should still include Mermaid init script");
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

    // First: enabled — use render (MPAssetFullLink) for filename checks
    self.delegate.mermaid = YES;
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.min.js"],
                  @"Should include mermaid scripts when enabled");

    // Second: disabled
    self.delegate.mermaid = NO;
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    XCTAssertFalse([self.delegate.lastHTML containsString:@"mermaid.min.js"],
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

    // Use render (MPAssetFullLink) for filename checks
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                  @"Should include mermaid init script");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"MathJax.js"],
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

    // Use render (MPAssetFullLink) for filename checks
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    XCTAssertTrue([self.delegate.lastHTML containsString:@"mermaid.init.js"],
                  @"Should include mermaid init script");
    XCTAssertTrue([self.delegate.lastHTML containsString:@"viz.init.js"],
                  @"Should include graphviz init script alongside mermaid");
}

#pragma mark - Node Label Fit (Issue #35)

// Spins the main run loop until condition returns YES or timeout elapses.
static BOOL MPMermaidSpinUntil(NSTimeInterval timeout, BOOL (^condition)(void))
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}

// Renders the issue's flowchart with the bundled Mermaid and mermaid.init.js
// at the given page zoom and checks that every node label fits the box that
// clips it: the foreignObject when labels are HTML, and the node shape.
- (void)assertFlowchartLabelsFitAtPageSizeMultiplier:(float)multiplier
{
    NSURL *mermaidURL = [[NSBundle mainBundle] URLForResource:@"mermaid.min"
                                                withExtension:@"js"
                                                 subdirectory:@"Extensions"];
    XCTAssertNotNil(mermaidURL, @"The bundled Mermaid library is missing");
    if (!mermaidURL)
        return;
    NSURL *baseURL = mermaidURL.URLByDeletingLastPathComponent;

    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 800, 600)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;  // ARC owns the window.
    WebView *webView = [[WebView alloc]
        initWithFrame:NSMakeRect(0, 0, 800, 600)];
    window.contentView = webView;

    NSString *html =
        @"<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
         "<script src=\"mermaid.min.js\"></script>"
         "<script src=\"mermaid.init.js\"></script>"
         "</head><body></body></html>";
    [webView.mainFrame loadHTMLString:html baseURL:baseURL];
    BOOL loaded = MPMermaidSpinUntil(20.0, ^{
        return (BOOL)(!webView.isLoading && [[webView
            stringByEvaluatingJavaScriptFromString:
                @"String(document.readyState === 'complete' && "
                 "typeof mermaid !== 'undefined')"] isEqualToString:@"true"]);
    });
    XCTAssertTrue(loaded, @"The page with Mermaid did not finish loading");

    // A fresh load resets the multiplier, so apply it after loading and
    // before the diagram exists, so Mermaid measures labels at this zoom.
    [webView setPageSizeMultiplier:multiplier];
    double clientWidth = [[webView stringByEvaluatingJavaScriptFromString:
        @"document.documentElement.clientWidth"] doubleValue];
    XCTAssertEqualWithAccuracy(clientWidth, 800.0 / multiplier, 2.0,
                               @"Page zoom %.2f did not take effect",
                               multiplier);

    [webView stringByEvaluatingJavaScriptFromString:
        @"var pre = document.createElement('pre');"
         "var code = document.createElement('code');"
         "code.className = 'language-mermaid';"
         "code.textContent = 'graph TD\\n    A[Start] --> B[Process]\\n"
         "    B --> C[End]';"
         "pre.appendChild(code); document.body.appendChild(pre);"];
    NSString *countJS =
        @"String(document.querySelectorAll('svg[id^=\"mermaid_\"] g.node').length)";
    BOOL rendered = MPMermaidSpinUntil(20.0, ^{
        return [[webView stringByEvaluatingJavaScriptFromString:countJS]
                isEqualToString:@"3"];
    });
    XCTAssertTrue(rendered, @"The flowchart did not render three nodes at "
                             "zoom %.2f", multiplier);

    NSString *json = [webView stringByEvaluatingJavaScriptFromString:
        @"JSON.stringify(Array.prototype.map.call("
         "document.querySelectorAll('svg[id^=\"mermaid_\"] g.node'),"
         "function (n) {"
         "var shape = n.querySelector('rect, path, polygon, circle, ellipse');"
         "var fo = n.querySelector('g.label foreignObject');"
         "var content = fo ? (fo.querySelector('.nodeLabel') || fo.firstElementChild)"
         " : n.querySelector('g.label text');"
         "var c = content.getBoundingClientRect(), s = shape.getBoundingClientRect();"
         "var box = fo ? Math.min(fo.getBoundingClientRect().width, s.width) : s.width;"
         "return {text: content.textContent, label: c.width, box: box, html: !!fo};"
         "}))"];
    NSArray<NSDictionary *> *nodes = [NSJSONSerialization
        JSONObjectWithData:[json ?: @"[]" dataUsingEncoding:NSUTF8StringEncoding]
                   options:0 error:NULL];
    XCTAssertEqual(nodes.count, 3u, @"Expected three measured nodes; got %@",
                   json);
    for (NSDictionary *node in nodes)
    {
        double label = [node[@"label"] doubleValue];
        double box = [node[@"box"] doubleValue];
        XCTAssertLessThanOrEqual(label, box + 0.5,
            @"At zoom %.2f the label \"%@\" (%.2f wide, HTML label: %@) is "
             "clipped by its %.2f-wide box",
            multiplier, node[@"text"], label, node[@"html"], box);
    }

    [webView close];
    [window close];
}

- (void)testFlowchartNodeLabelsFitAtFullSize
{
    [self assertFlowchartLabelsFitAtPageSizeMultiplier:1.0];
}

- (void)testFlowchartNodeLabelsFitWhenPreviewIsScaledDown
{
    [self assertFlowchartLabelsFitAtPageSizeMultiplier:0.8];
}

@end
