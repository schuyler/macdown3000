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
#import "MPDocument.h"
#import "MPPreferences.h"
#import "MPEditorView.h"
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "MPBlockquoteTestCases.h"

@interface MPDocument (UnderlineTesting)
@property (nonatomic, weak) MPEditorView *editor;
- (IBAction)toggleUnderline:(id)sender;
@end

@interface MPDocument (CalloutStateTesting)
@property (nonatomic, weak) MPEditorView *editor;
@property (nonatomic, weak) WebView *preview;
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic) BOOL isPreviewReady;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (nonatomic) NSUInteger previewRenderGeneration;
- (void)reloadPreview:(id)sender;
- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)items;
@end

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

- (void)testMarkdownSnapshotsDoNotPublishOrChangeLivePreviewAndExportResources
{
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;
    self.delegate.syntaxHighlighting = YES;
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST | HOEDOWN_HTML_BLOCKCODE_INFORMATION;
    self.dataSource.markdown = @"- [ ] Published task\n\n```javascript\nconst published = 42;\n```\n";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];
    NSString *publishedHTML = self.renderer.currentHtml;
    NSString *publishedPage = self.delegate.lastHTML;
    NSString *publishedToken = self.renderer.checkboxBridgeToken;
    NSArray *publishedOffsets = self.renderer.checkboxSourceOffsets;
    NSString *publishedMarkdown = self.renderer.checkboxSourceMarkdown;
    NSArray *publishedCallouts = self.renderer.calloutSourceEntries;
    NSString *publishedExport = [self.renderer HTMLForExportWithStyles:NO highlighting:YES];
    XCTAssertTrue([publishedPage containsString:@"prism-javascript"]);

    for (NSString *candidate in @[@"", @"- [x] Probe task\n\n```python\nprint('probe')\n```\n",
                                 @"::: {.callout-note}\n## Probe title\n\nProbe body\n:::\n"]) {
        NSString *snapshot = [self.renderer HTMLForMarkdownSnapshot:candidate];
        XCTAssertNotNil(snapshot);
        XCTAssertEqualObjects(self.renderer.currentHtml, publishedHTML);
        XCTAssertEqualObjects(self.delegate.lastHTML, publishedPage);
        XCTAssertEqualObjects(self.renderer.checkboxBridgeToken, publishedToken);
        XCTAssertEqualObjects(self.renderer.checkboxSourceOffsets, publishedOffsets);
        XCTAssertEqualObjects(self.renderer.checkboxSourceMarkdown, publishedMarkdown);
        XCTAssertEqualObjects(self.renderer.calloutSourceEntries, publishedCallouts);
        XCTAssertEqualObjects([self.renderer HTMLForExportWithStyles:NO highlighting:YES], publishedExport);
    }
    XCTAssertEqualObjects([self.renderer HTMLForMarkdownSnapshot:nil], @"");
    [self.renderer render];
    XCTAssertEqualObjects(self.delegate.lastHTML, publishedPage);
    XCTAssertFalse([self.delegate.lastHTML containsString:@"prism-python"]);
}

- (void)testMarkdownSnapshotUsesCurrentParseOptionsWithoutReplacingPublishedState
{
    [self.renderer parseMarkdown:@"Published **body**\n"];
    NSString *published = self.renderer.currentHtml;
    self.delegate.detectFrontMatter = YES;
    self.delegate.renderTOC = YES;
    self.delegate.extensions = HOEDOWN_EXT_UNDERLINE | HOEDOWN_EXT_STRIKETHROUGH;
    NSString *source = @"---\ntitle: Private metadata\n---\n\n[TOC]\n\n## Visible heading\n\n_underlined_ and ~~deleted~~\n";
    NSString *snapshot = [self.renderer HTMLForMarkdownSnapshot:source];
    XCTAssertFalse([snapshot containsString:@"Private metadata"]);
    XCTAssertTrue([snapshot containsString:@"href=\"#visible-heading\""]);
    XCTAssertTrue([snapshot containsString:@"<u>underlined</u>"]);
    XCTAssertTrue([snapshot containsString:@"<del>deleted</del>"]);
    XCTAssertEqualObjects(self.renderer.currentHtml, published);

    self.delegate.detectFrontMatter = NO;
    self.delegate.renderTOC = NO;
    self.delegate.extensions = 0;
    snapshot = [self.renderer HTMLForMarkdownSnapshot:source];
    XCTAssertTrue([snapshot containsString:@"Private metadata"]);
    XCTAssertTrue([snapshot containsString:@"[TOC]"]);
    XCTAssertTrue([snapshot containsString:@"<em>underlined</em>"]);
    XCTAssertTrue([snapshot containsString:@"~~deleted~~"]);
    XCTAssertEqualObjects(self.renderer.currentHtml, published);
}

- (void)testCalloutSnapshotsRemoveOnlyTheirOwnTransportIdentities
{
    NSString *source = @"<p data-macdown-callout-token=\"authored\">Authored identity</p>\n\n::: {.callout-caution}\n## Attention\n**Body**\n:::\n\n::: {.callout-note collapse=\"true\"}\n## Prerequisites\nOther body\n:::\n";
    self.dataSource.markdown = source;
    [self.renderer parseMarkdown:source];
    [self.renderer render];
    NSString *publishedHTML = self.renderer.currentHtml;
    NSString *publishedPage = self.delegate.lastHTML;
    NSArray *publishedEntries = self.renderer.calloutSourceEntries;
    NSString *publishedToken = self.renderer.checkboxBridgeToken;
    XCTAssertEqual(publishedEntries.count,2u);
    NSString *snapshot = [self.renderer HTMLForMarkdownSnapshot:source];
    XCTAssertEqualObjects([self.renderer HTMLForMarkdownSnapshot:source],snapshot,
        @"Equivalent callout snapshots have stable semantic HTML");
    XCTAssertTrue([snapshot containsString:@"data-macdown-callout-token=\"authored\""],
        @"An authored attribute remains part of the semantic oracle");
    XCTAssertTrue([snapshot containsString:@"<aside class=\"mp-callout mp-callout-caution\">"]);
    XCTAssertTrue([snapshot containsString:@"<details class=\"mp-callout mp-callout-note\">"]);
    XCTAssertTrue([snapshot containsString:@"<strong>Body</strong>"]);
    for (NSDictionary *entry in publishedEntries) {
        NSString *attribute = [NSString stringWithFormat:@"data-macdown-callout-token=\"%@\"",entry[@"token"]];
        XCTAssertTrue([publishedHTML containsString:attribute]);
        XCTAssertTrue([publishedPage containsString:attribute]);
        XCTAssertFalse([snapshot containsString:attribute]);
    }
    XCTAssertEqualObjects(self.renderer.currentHtml,publishedHTML);
    XCTAssertEqualObjects(self.delegate.lastHTML,publishedPage);
    XCTAssertEqualObjects(self.renderer.calloutSourceEntries,publishedEntries);
    XCTAssertEqualObjects(self.renderer.checkboxBridgeToken,publishedToken);
    XCTAssertEqualObjects(self.renderer.checkboxSourceMarkdown,source);
}

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

- (void)testHTMLExportRetainsTaskMarkerSuppressionWithOrWithoutTheme
{
    [self renderMarkdown:@"- [ ] Task\n- Ordinary\n" withExtensions:0 rendererFlags:HOEDOWN_HTML_USE_TASK_LIST];
    for (NSNumber *styles in @[@NO,@YES]) {
        NSString *HTML=[self.renderer HTMLForExportWithStyles:styles.boolValue highlighting:NO];
        XCTAssertTrue([HTML containsString:@"id=\"macdown-task-list-markers\""]);
        XCTAssertTrue([HTML containsString:@"li.task-list-item{list-style-type:none!important;}"]);
        XCTAssertTrue([HTML containsString:@"<li>Ordinary</li>"]);
        XCTAssertTrue([HTML containsString:@"type=\"checkbox\""]);
    }
}

- (void)testTaskListCheckboxesReplaceBulletsWithoutChangingOrdinaryLists
{
    MPDocument *document=[MPDocument new];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    document.editor=editor; document.preview=web; document.renderer=[MPRenderer new];
    document.renderer.dataSource=(id<MPRendererDataSource>)document;
    document.renderer.delegate=(id<MPRendererDelegate>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    MPPreferences *preferences=document.preferences;
    BOOL tasks=preferences.htmlTaskList,math=preferences.htmlMathJax;
    BOOL mermaid=preferences.htmlMermaid,graphviz=preferences.htmlGraphviz;
    NSString *style=preferences.htmlStyleName;
    NSString *source=@"- [ ] erftgesqzsq\n- [ ] v\n- [ ] er\n- [x] checked\n    - Ordinary nested bullet\n\n1. Ordinary number\n2. [ ] Ordered task\n";
    @try {
        preferences.htmlTaskList=YES; preferences.htmlMathJax=NO;
        preferences.htmlMermaid=NO; preferences.htmlGraphviz=NO;
        for (NSString *theme in @[@"GitHub2",@"GitHub Tomorrow"]) {
            preferences.htmlStyleName=theme;
            document.renderer.rendererFlags=HOEDOWN_HTML_USE_TASK_LIST;
            [self renderCalloutDocument:document source:source];
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('li.task-list-item'),function(e){return getComputedStyle(e).listStyleType;}))"],@"[\"none\",\"none\",\"none\",\"none\",\"none\"]",@"%@",theme);
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('li:not(.task-list-item)'),function(e){return getComputedStyle(e).listStyleType==='none';}))"],@"[false,false]",@"Ordinary nested bullets and numbering stay visible: %@",theme);
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelectorAll('input[type=checkbox]').length)"],@"5");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelectorAll('input[checked]').length)"],@"1");
            XCTAssertEqualObjects(editor.string,source);
        }
    } @finally {
        web.frameLoadDelegate=nil; [document close];
        preferences.htmlTaskList=tasks; preferences.htmlMathJax=math;
        preferences.htmlMermaid=mermaid; preferences.htmlGraphviz=graphviz;
        preferences.htmlStyleName=style;
    }
}

- (void)testTaskCheckboxesOccupyMarkerColumnAndTextAlignsWithOrdinaryItems
{
    MPDocument *document=[MPDocument new];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;window.contentView=web;[window makeKeyAndOrderFront:nil];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:web.frame];
    document.editor=editor; document.preview=web; document.renderer=[MPRenderer new];
    document.renderer.dataSource=(id<MPRendererDataSource>)document;
    document.renderer.delegate=(id<MPRendererDelegate>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    MPPreferences *p=document.preferences;
    BOOL tasks=p.htmlTaskList,math=p.htmlMathJax,mermaid=p.htmlMermaid,graph=p.htmlGraphviz;
    NSString *style=p.htmlStyleName;
    NSString *source=@"- [ ] zaert\n- azerty\n\nzaertyt\n\n- Parent\n    - [x] nested task\n    - nested bullet\n\n1. [ ] ordered task\n\n2. ordered item\n";
    @try {
        p.htmlTaskList=YES;p.htmlMathJax=NO;p.htmlMermaid=NO;p.htmlGraphviz=NO;
        for (NSString *theme in @[@"GitHub2",@"GitHub Tomorrow",@"Dracula",@"GitHub-2020",@"Github2 (dark)"]) {
            p.htmlStyleName=theme;document.renderer.rendererFlags=HOEDOWN_HTML_USE_TASK_LIST;
            [self renderCalloutDocument:document source:source];
            [web stringByEvaluatingJavaScriptFromString:@"document.body.style.fontSize='24px'"];
            NSArray *measurements=[[web.mainFrame.javaScriptContext evaluateScript:
                @"(function(){function textStart(row){var w=document.createTreeWalker(row,NodeFilter.SHOW_TEXT),n;while(n=w.nextNode()){if(n.parentElement.closest('li')!==row)continue;var at=n.nodeValue.search(/\\S/);if(at<0)continue;var r=document.createRange();r.setStart(n,at);r.setEnd(n,at+1);return r.getBoundingClientRect().left;}return null;}return Array.from(document.querySelectorAll('ul,ol')).map(function(list){var rows=Array.from(list.children).filter(function(e){return e.tagName==='LI';}),task=rows.find(function(e){return e.classList.contains('task-list-item');}),ordinary=rows.find(function(e){return !e.classList.contains('task-list-item');});if(!task||!ordinary)return null;var box=task.querySelector('input[type=checkbox]').getBoundingClientRect(),item=task.getBoundingClientRect();return {task:textStart(task),ordinary:textStart(ordinary),boxLeft:box.left,boxRight:box.right,itemLeft:item.left,listLeft:list.getBoundingClientRect().left,width:box.width,itemFont:parseFloat(getComputedStyle(task).fontSize),boxFont:parseFloat(getComputedStyle(task.querySelector('input[type=checkbox]')).fontSize)};}).filter(Boolean);})()"] toArray];
            XCTAssertEqual(measurements.count,3u,@"Tight, nested and loose ordered lists: %@",theme);
            for (NSDictionary *m in measurements) {
                XCTAssertNotEqualObjects(m[@"task"],NSNull.null);
                XCTAssertNotEqualObjects(m[@"ordinary"],NSNull.null);
                XCTAssertEqualWithAccuracy([m[@"task"] doubleValue],[m[@"ordinary"] doubleValue],0.5,@"Task and ordinary text must share their start: %@ %@",theme,m);
                XCTAssertGreaterThan([m[@"width"] doubleValue],0.0);
                XCTAssertEqualWithAccuracy([m[@"boxFont"] doubleValue],[m[@"itemFont"] doubleValue],0.01,@"The marker offset must scale with the list text, not the native input font: %@",theme);
                XCTAssertLessThan([m[@"boxRight"] doubleValue],[m[@"itemLeft"] doubleValue],@"Checkbox belongs in the list-marker column: %@ %@",theme,m);
                XCTAssertGreaterThanOrEqual([m[@"boxLeft"] doubleValue],[m[@"listLeft"] doubleValue],@"Checkbox remains inside list indentation: %@ %@",theme,m);
            }
            XCTAssertEqualObjects(editor.string,source);

        }
    } @finally {
        web.frameLoadDelegate=nil;window.contentView=nil;[window close];[document close];
        p.htmlTaskList=tasks;p.htmlMathJax=math;p.htmlMermaid=mermaid;p.htmlGraphviz=graph;p.htmlStyleName=style;
    }
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

- (void)testUppercaseCheckedCheckboxHasDataIndex
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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

/**
 * Test that an uppercase [X] checkbox renders as a checked checkbox, matching
 * the GFM spec. Related to GitHub issue #369.
 */
- (void)testUppercaseCheckboxRendersChecked
{
    self.delegate.extensions = 0;
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
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
 * FIXED: The preprocessor protects reference-shaped code with per-parse
 * markers that the block-code renderer removes, preserving the original
 * code bytes without invisible characters in the rendered result.
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

/**
 * Regression test for Issue #25: Adjacent shortcut links
 *
 * FIXED: The markdown preprocessor converts shortcut-style links [text]
 * to explicit form [text][] when followed by another [, preventing Hoedown
 * from misinterpreting the adjacent link syntax.
 *
 * Related: Issue #25
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
 * MPPreprocessMarkdown Issue #254 workaround: list immediately after paragraph.
 * The regex that inserts a blank line uses \n, so it must also work with CRLF.
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
 * MPPreprocessMarkdown Issue #36 workaround: fenced code block immediately after text.
 * The fence regex must also work when lines are terminated with CRLF.
 */
- (void)testFencedCodeAfterTextWithCRLFLineEndings
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
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

// Distinct headings whose punctuation collapses to the same base slug still
// need distinct DOM destinations so links can target each section.
- (void)testCollidingHeadingsHaveDistinctIds
{
    NSString *html = [self renderMarkdown:@"## C\n\n## C++\n"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"<h2 id=\"c\">C</h2>"],
                  @"First heading keeps its base slug. Got: %@", html);
    XCTAssertTrue([html containsString:@"<h2 id=\"c-1\">C++</h2>"],
                  @"Colliding heading must have a distinct destination. Got: %@", html);
    XCTAssertEqual([html componentsSeparatedByString:@"id=\"c\""].count, 2u);
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

#pragma mark - GitHub-slugger Parity: UTF-8 Decoder Coverage (#503)

// These exercise decode_utf8_codepoint through the render path -- the newest
// and most intricate code in the slug algorithm. Ground truth for every parity
// assertion was captured by running github-slugger on the same input.
// Related to #503, #471.

// Valid 3-byte UTF-8 (CJK): decoded and, as ordinary letters, passed through
// unchanged -- github-slugger parity ("日本語" -> "日本語").
- (void)testHeadingAnchorIdPassesThroughThreeByteCJK
{
    NSString *html = [self renderMarkdown:@"## 日本語"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"日本語\""],
                  @"Three-byte CJK codepoints must pass through unchanged. Got: %@", html);
}

// The U+00D7 (×) / U+00DE (Þ) boundary, symbol side: the multiplication sign is
// dropped while surrounding text stays -- "3×4 Grid" -> "34-grid".
- (void)testHeadingAnchorIdDropsMultiplicationSignAtBoundary
{
    NSString *html = [self renderMarkdown:@"## 3×4 Grid"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"34-grid\""],
                  @"The U+00D7 multiplication sign must be dropped. Got: %@", html);
}

// The same boundary, letter side: Þ (U+00DE) and Ð (U+00D0) both lowercase to
// their two-byte forms -- "Þorn Ðeth" -> "þorn-ðeth".
- (void)testHeadingAnchorIdLowercasesLatin1BoundaryLetters
{
    NSString *html = [self renderMarkdown:@"## Þorn Ðeth"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"þorn-ðeth\""],
                  @"Þ and Ð must lowercase to þ and ð. Got: %@", html);
}

// Back-to-back dropped codepoints (em dash, en dash, ellipsis) collapse to
// nothing, leaving no stray hyphens -- "Foo—–…Bar" -> "foobar".
- (void)testHeadingAnchorIdDropsConsecutivePunctuationCodepoints
{
    NSString *html = [self renderMarkdown:@"## Foo—–…Bar"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"foobar\""],
                  @"Consecutive dropped punctuation must leave no hyphens. Got: %@", html);
}

// Valid 4-byte UTF-8 (emoji) is decoded and passed through raw. This is a
// documented scope boundary, NOT github-slugger parity: github-slugger drops
// emoji ("😀 Hi" -> "-hi"), but our algorithm only classifies the Latin-1 and
// General Punctuation ranges and passes every other codepoint through, so the
// emoji survives. The test pins today's behavior.
- (void)testHeadingAnchorIdPassesThroughFourByteEmoji
{
    NSString *html = [self renderMarkdown:@"## 😀 Hi"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"😀-hi\""],
                  @"Four-byte emoji must be decoded and passed through raw. Got: %@", html);
}

#pragma mark - GitHub-slugger Parity: Leading Hyphen (#503)

// A heading that starts with dropped punctuation followed by a space yields a
// leading hyphen. Verified against github-slugger ("— Título" -> "-título"),
// so the leading hyphen is intentional GitHub parity, not a bug. Related to
// #503.
- (void)testHeadingAnchorIdKeepsLeadingHyphenFromDroppedPunctuation
{
    NSString *html = [self renderMarkdown:@"## — Título"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"-título\""],
                  @"A leading dropped em dash + space must yield a leading hyphen. Got: %@", html);
}

#pragma mark - GitHub-slugger Parity: Scope Boundary (#503)

// Documented divergence: github-slugger lowercases every script via
// String.toLowerCase() ("Привет Мир" -> "привет-мир"), but our algorithm only
// lowercases the Latin-1 range and passes every other letter through raw, so
// Cyrillic keeps its original case. This pins today's behavior to make the
// scope boundary explicit for future readers. Related to #503, #471.
- (void)testHeadingAnchorIdDoesNotLowercaseCyrillic
{
    NSString *html = [self renderMarkdown:@"## Привет Мир"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"Привет-Мир\""],
                  @"Cyrillic is passed through without lowercasing (scope boundary). Got: %@", html);
}

// Same scope boundary for Greek: github-slugger gives "καλημέρα-κόσμε"; we keep
// the original case.
- (void)testHeadingAnchorIdDoesNotLowercaseGreek
{
    NSString *html = [self renderMarkdown:@"## Καλημέρα Κόσμε"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"Καλημέρα-Κόσμε\""],
                  @"Greek is passed through without lowercasing (scope boundary). Got: %@", html);
}

#pragma mark - Empty Heading Crash Regression (#479)

// A lone setext underline ('-' or '=') with no preceding text makes Hoedown
// emit a heading whose content is empty. The slug buffer must not be created
// with a zero unit, or Hoedown's hoedown_buffer_grow assertion aborts the
// whole app on the background render queue. These render through the real
// parse path, so before the fix they crash the test process outright.
// Related to #479.

- (void)testLoneHyphenHeadingDoesNotCrash
{
    NSString *html = [self renderMarkdown:@"-"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"section\""],
                  @"Empty setext heading must render with the fallback id without "
                  @"crashing. Got: %@", html);
}

- (void)testLoneEqualsHeadingDoesNotCrash
{
    NSString *html = [self renderMarkdown:@"="
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertTrue([html containsString:@"id=\"section\""],
                  @"Empty setext H1 heading must render with the fallback id "
                  @"without crashing. Got: %@", html);
}

- (void)testReportedHyphenCrashInputRenders
{
    // Exact document from the issue: it ends in a lone '-' after a blank line,
    // which Hoedown treats as an empty setext heading underline.
    NSString *html = [self renderMarkdown:@"_ - _ - _ -\n-\n\n-"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertNotNil(html,
                  @"Reported crash input must render to a non-nil string.");
    XCTAssertTrue([html containsString:@"id=\"section\""],
                  @"The trailing empty heading must render with the fallback id. "
                  @"Got: %@", html);
}

- (void)assertUnderlineActionWithExtensionEnabled:(BOOL)enabled
{
    MPDocument *document = [[MPDocument alloc] init];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    document.editor = editor;
    BOOL previous = document.preferences.extensionUnderline;
    @try {
        document.preferences.extensionUnderline = enabled;
        editor.string = @"avant azerqzs après";
        editor.selectedRange = NSMakeRange(6, 7);
        [document toggleUnderline:nil];
        XCTAssertEqualObjects(editor.string, @"avant _azerqzs_ après");
        XCTAssertTrue(document.preferences.extensionUnderline);
        XCTAssertEqualObjects([editor.string substringWithRange:editor.selectedRange], @"azerqzs");
        NSString *html = [self renderMarkdown:editor.string
                               withExtensions:HOEDOWN_EXT_UNDERLINE
                                rendererFlags:0];
        XCTAssertTrue([html containsString:@"<u>azerqzs</u>"], @"%@", html);
        XCTAssertFalse([html containsString:@"<em>azerqzs</em>"], @"%@", html);
        [document toggleUnderline:nil];
        XCTAssertEqualObjects(editor.string, @"avant azerqzs après");
        XCTAssertTrue(NSEqualRanges(editor.selectedRange, NSMakeRange(6, 7)));
    } @finally {
        document.preferences.extensionUnderline = previous;
        [document close];
    }
}

- (void)testUnderlineActionWithoutExtensionRendersUnderlineAndTogglesOff
{
    [self assertUnderlineActionWithExtensionEnabled:NO];
}

- (void)testUnderlineActionWithExtensionRendersUnderlineAndTogglesOff
{
    [self assertUnderlineActionWithExtensionEnabled:YES];
}

- (void)testAsterisksRemainItalicWithUnderlineExtension
{
    for (NSNumber *enabled in @[@NO, @YES]) {
        NSString *html = [self renderMarkdown:@"*azerqzs*"
                               withExtensions:enabled.boolValue ? HOEDOWN_EXT_UNDERLINE : 0
                                rendererFlags:0];
        XCTAssertTrue([html containsString:@"<em>azerqzs</em>"], @"%@", html);
    }
}

- (void)testEmptyHeadingWithTOCDoesNotCrash
{
    // The TOC header renderer has the same buffer-creation pattern and must
    // also survive empty heading content.
    self.delegate.renderTOC = YES;
    NSString *html = [self renderMarkdown:@"[TOC]\n\n-"
                           withExtensions:0
                            rendererFlags:0];
    XCTAssertNotNil(html,
                  @"Empty heading with TOC enabled must render without crashing.");
}

- (void)testBlockquoteStructureMatrixInsideAndOutsideCallouts
{
    for (NSDictionary *testCase in MPBlockquoteTestCases()) {
        for (NSUInteger wrapper = 0; wrapper < 3; wrapper++) {
            for (NSNumber *CRLF in @[@NO, @YES]) {
                NSString *context = [NSString stringWithFormat:@"%@ / wrapper=%lu / CRLF=%@", testCase[@"name"], (unsigned long)wrapper, CRLF];
                NSString *source = MPBlockquoteSource(testCase[@"source"], wrapper, CRLF.boolValue);
                NSString *html = [self renderMarkdown:source withExtensions:HOEDOWN_EXT_SPACE_HEADERS | HOEDOWN_EXT_FENCED_CODE rendererFlags:0];
                NSError *error = nil;
                NSXMLDocument *DOM = MPBlockquoteDOM(html, &error);
                XCTAssertNotNil(DOM, @"%@ / %@", context, error);
                for (NSString *xpath in testCase[@"counts"]) {
                    NSArray *nodes = MPBlockquoteNodes(DOM, xpath, &error);
                    XCTAssertNotNil(nodes, @"%@ / %@ / %@", context, xpath, error);
                    XCTAssertEqual(nodes.count, [testCase[@"counts"][xpath] unsignedIntegerValue], @"%@ / %@ / %@", context, xpath, html);
                }
                if (wrapper) {
                    NSString *container = wrapper == 1 ? @"//aside" : @"//details";
                    XCTAssertEqual(MPBlockquoteNodes(DOM, [container stringByAppendingString:@"//blockquote"], NULL).count,
                                   MPBlockquoteNodes(DOM, @"//blockquote", NULL).count,
                                   @"%@ / citation escaped its callout", context);
                }
            }
        }
    }
}

- (void)testUnquotedHeadingsEndBlockquotesInsideAndOutsideCallouts
{
    for (NSUInteger level = 1; level <= 6; level++) {
        NSString *hashes = [@"######" substringToIndex:level];
        for (NSNumber *insideCallout in @[@NO, @YES]) {
            NSString *source = [NSString stringWithFormat:@"> citation\n%@ Outside\n\nAfter\n", hashes];
            if (insideCallout.boolValue)
                source = [NSString stringWithFormat:@"::: {.callout-important}\n## Title\n%@:::\n", source];
            NSString *html = [self renderMarkdown:source withExtensions:HOEDOWN_EXT_SPACE_HEADERS rendererFlags:0];
            NSRange quoteEnd = [html rangeOfString:@"</blockquote>"];
            NSRange heading = [html rangeOfString:[NSString stringWithFormat:@">Outside</h%lu>", (unsigned long)level]];
            XCTAssertNotEqual(quoteEnd.location, NSNotFound, @"%@", html);
            XCTAssertNotEqual(heading.location, NSNotFound, @"%@", html);
            XCTAssertLessThan(NSMaxRange(quoteEnd), heading.location, @"%@", html);
            if (insideCallout.boolValue)
                XCTAssertLessThan(NSMaxRange(heading), [html rangeOfString:@"</aside>"].location, @"%@", html);
        }
    }
}

- (void)testExplicitQuotedHeadingsAndLazyTextRemainInsideBlockquote
{
    NSString *html = [self renderMarkdown:@"> citation\ncontinued\n> # Quoted\n"
                          withExtensions:HOEDOWN_EXT_SPACE_HEADERS rendererFlags:0];
    XCTAssertTrue([html containsString:@"<p>citation\ncontinued</p>"], @"%@", html);
    NSRange heading = [html rangeOfString:@">Quoted</h1>"];
    XCTAssertNotEqual(heading.location, NSNotFound, @"%@", html);
    XCTAssertLessThan(NSMaxRange(heading), [html rangeOfString:@"</blockquote>"].location, @"%@", html);

    NSString *literal = [self renderMarkdown:@"> citation\n#hashtag\n"
                             withExtensions:HOEDOWN_EXT_SPACE_HEADERS rendererFlags:0];
    XCTAssertTrue([literal containsString:@"<p>citation\n#hashtag</p>"], @"%@", literal);
}

- (void)testQuartoCalloutsUseApplicationMarkdownRendererAndKeepTitleAnchors
{
    self.delegate.renderTOC = YES;
    NSString *html = [self renderMarkdown:@"[TOC]\n\n::: {.callout-warning collapse=\"true\"}\n## Keep **this title**\n\nA *body*.\n:::\n"
                              withExtensions:HOEDOWN_EXT_FENCED_CODE rendererFlags:0];
    XCTAssertTrue([html containsString:@"<details class=\"mp-callout mp-callout-warning\" data-macdown-callout-token=\""]);
    XCTAssertTrue([html containsString:@"<strong>this title</strong>"]);
    XCTAssertTrue([html containsString:@"<em>body</em>"]);
    XCTAssertFalse([html containsString:@"OPEN</p>"]);
    XCTAssertFalse([html containsString:@"CLOSE</p>"]);
    XCTAssertTrue([html containsString:@"@media print"]);
    XCTAssertTrue([html containsString:@"id=\"keep-this-title\""]);
    XCTAssertTrue([html containsString:@"href=\"#keep-this-title\""]);
}

- (void)testQuartoCalloutSyntaxInsideCodeIsLiteral
{
    NSString *html = [self renderMarkdown:@"```markdown\n::: {.callout-note}\nKeep literal\n:::\n```\n"
                              withExtensions:HOEDOWN_EXT_FENCED_CODE rendererFlags:0];
    XCTAssertFalse([html containsString:@"class=\"mp-callout"]);
    XCTAssertTrue([html containsString:@".callout-note"]);
}

- (void)testCalloutSourceMetadataIncludesOnlyGeneratedContainers
{
    NSString *source = @"<div>\n::: {.callout-note collapse=\"true\"}\n## Raw title\nRaw body\n:::\n</div>\n\n::: {.callout-tip collapse=\"true\"}\n## Real title\nReal body\n:::\n";
    NSString *html = [self renderMarkdown:source withExtensions:HOEDOWN_EXT_FENCED_CODE rendererFlags:0];
    XCTAssertTrue([html containsString:@".callout-note"], @"Raw HTML keeps the original delimiter literal");
    XCTAssertEqual(self.renderer.calloutSourceEntries.count,1u,
        @"An unrendered source pair cannot authorize a callout conversion");
    NSDictionary *entry = self.renderer.calloutSourceEntries.lastObject;
    XCTAssertEqualObjects(entry[@"type"],@"tip");
    NSRange opening = [source rangeOfString:@"::: {.callout-tip collapse=\"true\"}\n"];
    XCTAssertTrue(NSEqualRanges([entry[@"sourceOpenRange"] rangeValue],opening));
    NSString *attribute = [NSString stringWithFormat:@"data-macdown-callout-token=\"%@\"",entry[@"token"]];
    XCTAssertTrue([html containsString:attribute]);
}

- (void)renderCalloutDocument:(MPDocument *)document source:(NSString *)source
{
    NSUInteger generation = document.previewRenderGeneration;
    document.editor.string = source;
    [document.renderer parseAndRenderNow];
    XCTNSPredicateExpectation *rendered = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return document.previewRenderGeneration > generation && document.isPreviewReady &&
                !document.alreadyRenderingInWeb && !document.preview.isLoading;
        }] object:document];
    [self waitForExpectations:@[rendered] timeout:10];
}

- (void)testCalloutDisclosureStateSurvivesBodyReplacementAndResourceReload
{
    MPDocument *document = [MPDocument new];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    document.editor = editor; document.preview = web;
    document.renderer = [MPRenderer new];
    document.renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer.delegate = (id<MPRendererDelegate>)document;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid;
    BOOL graphviz = preferences.htmlGraphviz, sync = preferences.editorSyncScrolling;
    BOOL highlight = preferences.htmlSyntaxHighlighting;
    BOOL fenced = preferences.extensionFencedCode;
    NSString *source = @"::: {.callout-note collapse=\"true\"}\n## Same title\nOuter body\n\n::: {.callout-note collapse=\"false\"}\n## Same title\nNested body\n:::\n\n:::\n\n::: {.callout-note collapse=\"true\"}\n## Same title\nNeighbor body\n:::\n\n<details class=\"mp-callout mp-callout-note\" open><summary>Authored HTML</summary>Authored body</details>\n";
    @try {
        preferences.htmlMathJax = NO; preferences.htmlMermaid = NO;
        preferences.htmlGraphviz = NO; preferences.editorSyncScrolling = NO;
        preferences.htmlSyntaxHighlighting = YES;
        preferences.extensionFencedCode = YES;
        [self renderCalloutDocument:document source:source];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[false,true,false,true]");
        [web stringByEvaluatingJavaScriptFromString:@"var a=document.querySelectorAll('details');a[0].open=true;a[1].open=false;a[2].open=true;a[3].open=false;window.calloutStateSentinel='survived';"];
        NSString *formatted = [source stringByReplacingOccurrencesOfString:@"Outer body" withString:@"Outer **body**"];
        [self renderCalloutDocument:document source:formatted];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"window.calloutStateSentinel"], @"survived", @"Unchanged resources use the actual body replacement path");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[true,false,true,true]", @"Generated nested and duplicate callouts keep independent state; authored HTML retains its source default");
        formatted = [formatted stringByReplacingCharactersInRange:[formatted rangeOfString:@"## Same title"]
            withString:@"## Same *title*"];
        [self renderCalloutDocument:document source:formatted];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[true,false,true,true]", @"Formatting a summary also preserves independent disclosure state");
        NSString *withLanguage = [formatted stringByAppendingString:@"\n```javascript\nconst answer = 42;\n```\n"];
        [self renderCalloutDocument:document source:withLanguage];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"typeof window.calloutStateSentinel"], @"undefined", @"New Prism resources exercise an actual full page load");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[true,false,true,true]");
        // Inserting source before the callouts must translate their anchors,
        // rather than assigning a saved state to whichever block has that index.
        [self renderCalloutDocument:document source:[@"Prefix paragraph.\n\n" stringByAppendingString:withLanguage]];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[true,false,true,true]");
        // Removing the outer wrapper preserves the untouched nested callout and neighbor.
        NSString *unwrapped = [withLanguage stringByReplacingOccurrencesOfString:@"::: {.callout-note collapse=\"true\"}\n## Same *title*\nOuter **body**" withString:@"## Same *title*\nOuter **body**"];
        unwrapped = [unwrapped stringByReplacingOccurrencesOfString:@":::\n\n:::\n\n::: {.callout-note collapse=\"true\"}" withString:@":::\n\n::: {.callout-note collapse=\"true\"}"];
        [self renderCalloutDocument:document source:unwrapped];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[false,true,true]");
        XCTAssertEqualObjects(editor.string, unwrapped, @"View state never rewrites the source collapse attribute");
    } @finally {
        web.frameLoadDelegate = nil; [document close];
        preferences.htmlMathJax = math; preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz; preferences.editorSyncScrolling = sync;
        preferences.htmlSyntaxHighlighting = highlight;
        preferences.extensionFencedCode = fenced;
    }
}

- (void)testExplicitPreviewContextReloadResetsDisclosureToSourceDefaults
{
    MPDocument *document = [MPDocument new];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    document.editor = editor; document.preview = web;
    document.renderer = [MPRenderer new];
    document.renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer.delegate = (id<MPRendererDelegate>)document;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid;
    BOOL graphviz = preferences.htmlGraphviz, sync = preferences.editorSyncScrolling;
    NSString *source = @"::: {.callout-note collapse=\"true\"}\n## Closed default\nFirst body\n:::\n\n::: {.callout-tip collapse=\"false\"}\n## Open default\nSecond body\n:::\n";
    @try {
        preferences.htmlMathJax = NO; preferences.htmlMermaid = NO;
        preferences.htmlGraphviz = NO; preferences.editorSyncScrolling = NO;
        [self renderCalloutDocument:document source:source];
        [web stringByEvaluatingJavaScriptFromString:@"var a=document.querySelectorAll('details');a[0].open=true;a[1].open=false;"];
        NSMenuItem *defaultReload = [[NSMenuItem alloc] initWithTitle:@"Reload" action:nil keyEquivalent:@""];
        defaultReload.tag = WebMenuItemTagReload;
        NSArray *menu = [document webView:web contextMenuItemsForElement:@{} defaultMenuItems:@[defaultReload]];
        NSMenuItem *reload = menu.firstObject;
        XCTAssertEqual(reload.target, document);
        XCTAssertEqual(reload.action, @selector(reloadPreview:));
        NSUInteger generation = document.previewRenderGeneration;
        XCTAssertTrue([NSApp sendAction:reload.action to:reload.target from:reload]);
        XCTNSPredicateExpectation *reloaded = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return document.previewRenderGeneration > generation && document.isPreviewReady &&
                    !document.alreadyRenderingInWeb && !web.isLoading;
            }] object:document];
        [self waitForExpectations:@[reloaded] timeout:10];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[false,true]");
        XCTAssertEqualObjects(editor.string, source);
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('details').open=true;"];
        [self renderCalloutDocument:document source:[source stringByReplacingOccurrencesOfString:@"First body" withString:@"First *body*"]];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('details'),function(e){return e.open;}))"], @"[true,true]", @"Only the explicit reload resets state, not the following edit");
    } @finally {
        web.frameLoadDelegate = nil; [document close];
        preferences.htmlMathJax = math; preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz; preferences.editorSyncScrolling = sync;
    }
}

- (void)testCalloutDisclosureAnchorsUseOriginalCRLFSourceBeforePreprocessing
{
    MPDocument *document = [MPDocument new];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    document.editor = editor; document.preview = web;
    document.renderer = [MPRenderer new];
    document.renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer.delegate = (id<MPRendererDelegate>)document;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid;
    BOOL graphviz = preferences.htmlGraphviz, sync = preferences.editorSyncScrolling;
    BOOL frontMatter = preferences.htmlDetectFrontMatter;
    NSString *source = @"---\r\ntitle: State test\r\n---\r\n\r\n😀 Context\r\n- [ ] Task before callout\r\n\r\n::: {.callout-note collapse=\"true\"}\r\n## Title\r\nBody\r\n:::\r\n";
    @try {
        preferences.htmlMathJax = NO; preferences.htmlMermaid = NO;
        preferences.htmlGraphviz = NO; preferences.editorSyncScrolling = NO;
        preferences.htmlDetectFrontMatter = YES;
        [self renderCalloutDocument:document source:source];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('details').open)"], @"false");
        XCTAssertEqual(document.renderer.calloutSourceEntries.count, 1u);
        NSDictionary *entry = document.renderer.calloutSourceEntries.firstObject;
        NSRange opening = [source rangeOfString:@"::: {.callout-note collapse=\"true\"}\r\n"];
        NSRange closing = [source rangeOfString:@":::\r\n" options:NSBackwardsSearch];
        XCTAssertTrue(NSEqualRanges([entry[@"sourceOpenRange"] rangeValue],opening));
        XCTAssertTrue(NSEqualRanges([entry[@"sourceCloseRange"] rangeValue],closing));
        XCTAssertTrue(NSEqualRanges([entry[@"sourceContentRange"] rangeValue],
            NSMakeRange(NSMaxRange(opening),closing.location-NSMaxRange(opening))));
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:
            @"document.querySelector('details').getAttribute('data-macdown-callout-token')"],entry[@"token"]);
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('details').open=true;"];
        NSString *changed = [source stringByReplacingOccurrencesOfString:@"Body\r\n" withString:@"**Body**\r\n"];
        [self renderCalloutDocument:document source:changed];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('details').open)"], @"true");
        changed = [changed stringByReplacingOccurrencesOfString:@"collapse=\"true\"" withString:@"collapse=\"false\""];
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('details').open=false;"];
        [self renderCalloutDocument:document source:changed];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('details').open)"], @"true", @"An explicit source change to collapse resets the default rather than inheriting the former wrapper's state");
        XCTAssertEqualObjects(editor.string, changed);
    } @finally {
        web.frameLoadDelegate = nil; [document close];
        preferences.htmlMathJax = math; preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz; preferences.editorSyncScrolling = sync;
        preferences.htmlDetectFrontMatter = frontMatter;
    }
}

@end
