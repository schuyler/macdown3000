#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "MPDocument.h"
#import "MPEditorView.h"
#import "MPRenderer.h"
#import "MPPreferences.h"
#import "WebView+WebViewPrivateHeaders.h"

@interface MPPreferences (FormattingScopeMenuTests)
- (int)rendererFlags;
@end

@interface MPDocument (FormattingScopeMenuTests)
@property (strong) MPRenderer *renderer;
@property (weak) MPEditorView *editor;
@property (weak) WebView *preview;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (copy) NSString *previewEditSource;
@property (copy) NSString *previewEditToken;
@property (copy) NSArray<NSDictionary *> *previewEditRanges;
- (IBAction)convertToH1:(id)sender;
- (IBAction)toggleStrong:(id)sender;
- (IBAction)toggleLink:(id)sender;
- (BOOL)previewHasFindFocus;
- (void)scaleWebview;
- (BOOL)applyPreviewEditPayload:(NSDictionary *)payload;
- (BOOL)formatSourceInlineAction:(NSString *)action value:(NSString *)value;
- (void)editorSelectionDidChange:(NSNotification *)notification;
@end

// Exercise rendered selections, the JavaScript controls and native formatting
// transactions together. The matrix tests cover the full conversion product;
// these tests prove that the menus expose those independent scopes correctly.
@interface MPFormattingScopeMenuTests : XCTestCase
@property (strong) MPDocument *document;
@property (strong) MPEditorView *editor;
@property (strong) WebView *web;
@property (strong) NSWindow *window;
@property (strong) MPRenderer *renderer;
@property (copy) NSDictionary<NSString *, NSNumber *> *savedPreferences;
@property (copy) NSString *savedStyleName;
@property (strong) NSURL *fixtureDirectory;
@property (copy) NSString *settledPreviewToken;
@end

@implementation MPFormattingScopeMenuTests

- (void)setUp
{
    [super setUp];
    self.fixtureDirectory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.fixtureDirectory withIntermediateDirectories:YES attributes:nil error:NULL]);
    self.document=[MPDocument new];
    self.document.fileURL=[self.fixtureDirectory URLByAppendingPathComponent:@"scopes.md"];
    self.editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,600,450)];
    self.web=[[WebView alloc] initWithFrame:NSMakeRect(600,0,600,450)];
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1200,450) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed=NO;
    [self.window.contentView addSubview:self.editor];
    [self.window.contentView addSubview:self.web];
    self.renderer=[MPRenderer new];
    self.document.editor=self.editor; self.document.preview=self.web; self.document.renderer=self.renderer;
    self.renderer.delegate=(id<MPRendererDelegate>)self.document;
    self.renderer.dataSource=(id<MPRendererDataSource>)self.document;
    self.web.frameLoadDelegate=(id<WebFrameLoadDelegate>)self.document;
    self.web.policyDelegate=(id<WebPolicyDelegate>)self.document;
    self.web.editingDelegate=(id<WebEditingDelegate>)self.document;
    self.savedStyleName=self.document.preferences.htmlStyleName;
    // Keep resource loading local and independent of another suite's theme.
    self.document.preferences.htmlStyleName=@"GitHub2";
    NSDictionary *settings=@{@"htmlMathJax":@NO,@"extensionSmartyPants":@NO,@"htmlSyntaxHighlighting":@NO,
        @"htmlMermaid":@NO,@"htmlGraphviz":@NO,@"extensionTables":@YES,@"htmlTaskList":@YES,@"extensionFencedCode":@YES,
        @"extensionIntraEmphasis":@YES,@"extensionUnderline":@YES,@"extensionStrikethough":@YES};
    NSMutableDictionary *saved=[NSMutableDictionary dictionary];
    for (NSString *key in settings) {
        saved[key]=[self.document.preferences valueForKey:key];
        [self.document.preferences setValue:settings[key] forKey:key];
    }
    self.savedPreferences=saved;
    self.renderer.rendererFlags=self.document.preferences.rendererFlags;
}

- (void)tearDown
{
    self.web.frameLoadDelegate=nil; self.web.policyDelegate=nil; self.web.editingDelegate=nil;
    self.window.contentView=nil; [self.window close];
    [self.document close];
    for (NSString *key in self.savedPreferences) [self.document.preferences setValue:self.savedPreferences[key] forKey:key];
    self.document.preferences.htmlStyleName=self.savedStyleName;
    [NSFileManager.defaultManager removeItemAtURL:self.fixtureDirectory error:NULL];
    self.renderer=nil; self.document=nil; self.editor=nil; self.web=nil; self.window=nil;
    [super tearDown];
}

- (void)waitUntil:(BOOL (^)(void))condition description:(NSString *)description
{
    XCTestExpectation *expectation=[[XCTestExpectation alloc] initWithDescription:description];
    __block BOOL finished=NO;
    __block void (^poll)(void);
    poll=^{
        if (finished) {poll=nil;return;}
        if (condition()) {finished=YES;[expectation fulfill];poll=nil;return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),poll);
    };
    poll();
    XCTWaiterResult result=[XCTWaiter waitForExpectations:@[expectation] timeout:10];
    finished=YES;
    if (result!=XCTWaiterResultCompleted) {
        NSString *state=[self JS:@"JSON.stringify({selection:getSelection().toString(),payload:window.macdownPreviewEditor&&macdownPreviewEditor.selectionPayload('bold'),panel:document.getElementById('macdown-preview-format')&&getComputedStyle(document.getElementById('macdown-preview-format')).display,menus:Array.from(document.querySelectorAll('#macdown-preview-format select')).map(function(s){return {scope:s.getAttribute('data-mp-scope'),value:s.value,active:s.hasAttribute('data-mp-active')};})})"];
        XCTFail(@"%@ timed out after 10 seconds; loading=%d rendering=%d mapped=%lu sourceCurrent=%d previewToken=%@ rendererToken=%@ pending=%@ DOM=%@",description,self.web.isLoading,self.document.alreadyRenderingInWeb,(unsigned long)self.document.previewEditRanges.count,[self.document.previewEditSource isEqualToString:self.editor.string],self.document.previewEditToken,self.renderer.checkboxBridgeToken,[self.document valueForKey:@"renderToWebPending"],state);
    }
}

- (NSString *)JS:(NSString *)script
{
    return [self.web stringByEvaluatingJavaScriptFromString:script];
}

- (void)loadSource:(NSString *)source
{
    // Establish the window before selecting: activating a previously hidden
    // WebView window can clear its DOM selection as it changes responder.
    [self.window makeKeyAndOrderFront:nil];
    self.editor.string=source;
    // Preferences can already have scheduled an asynchronous parse. Use the
    // application's public entry point to supersede it; a private synchronous
    // parse would leave that older generation free to publish stale identities.
    [self.renderer parseAndRenderNow];
    [self waitUntil:^BOOL{
        return !self.web.isLoading && !self.document.alreadyRenderingInWeb &&
            [self.document.previewEditSource isEqualToString:source] &&
            [self.document.previewEditToken isEqualToString:self.renderer.checkboxBridgeToken] &&
            self.document.previewEditRanges.count>0;
    } description:@"Load document and install preview mapping"];
    XCTAssertTrue([self.window makeFirstResponder:self.web]);
    self.settledPreviewToken=self.document.previewEditToken;
}

- (void)waitForFormatting
{
    [self waitUntil:^BOOL{
        return !self.web.isLoading && !self.document.alreadyRenderingInWeb &&
            ![self.document.previewEditToken isEqualToString:self.settledPreviewToken] &&
            [self.document.previewEditSource isEqualToString:self.editor.string] &&
            ![self.document valueForKey:@"previewSelectionToRestore"] &&
            ![[self.document valueForKey:@"previewQueuedFormatting"] count];
    } description:@"Finish formatting and restore selection"];
    self.settledPreviewToken=self.document.previewEditToken;
}

- (void)selectFromText:(NSString *)first throughText:(NSString *)last
{
    NSData *JSON=[NSJSONSerialization dataWithJSONObject:@[first,last] options:0 error:NULL];
    NSString *arguments=[[NSString alloc] initWithData:JSON encoding:NSUTF8StringEncoding];
    NSString *script=[NSString stringWithFormat:
        @"(function(){var text=%@,nodes=macdownPreviewEditor.elements().spans,a=nodes.find(function(n){return n.textContent===text[0];})||nodes.find(function(n){return n.textContent.includes(text[0]);}),b=nodes.find(function(n){return n.textContent===text[1];})||nodes.find(function(n){return n.textContent.includes(text[1]);});if(!a||!b)return false;a.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}));var r=document.createRange();r.setStart(a.firstChild,a.textContent.indexOf(text[0]));r.setEnd(b.firstChild,b.textContent.indexOf(text[1])+text[1].length);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return true;})()",arguments];
    XCTAssertTrue([[self JS:script] boolValue],@"Mapped selection %@ through %@ must exist",first,last);
    [self waitUntil:^BOOL{return [[self JS:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"] isEqualToString:@"block"];} description:[NSString stringWithFormat:@"Show panel for selection %@ through %@",first,last]];
}

- (void)assertMenuScope:(NSString *)scope value:(NSString *)value active:(BOOL)active
{
    NSString *selector=[NSString stringWithFormat:@"document.querySelector('[data-mp-scope=\"%@\"] [data-mp-option=\"%@\"]')",scope,value];
    if (!value.length) {
        XCTAssertEqualObjects(([self JS:[NSString stringWithFormat:@"String(document.querySelectorAll('[data-mp-scope=\"%@\"] [data-mp-active]').length)",scope]]),@"0");
        return;
    }
    XCTAssertEqual([[self JS:[selector stringByAppendingString:@".hasAttribute('data-mp-active')"]] boolValue],active);
    XCTAssertEqualObjects([self JS:[selector stringByAppendingString:@".getAttribute('aria-checked')"]],active ? @"true" : @"false");
    if (active) XCTAssertEqualObjects(([self JS:[NSString stringWithFormat:@"getComputedStyle(%@).color",selector]]),@"rgb(39, 132, 222)");
}

- (void)chooseContainer:(NSString *)value
{
    [self JS:[NSString stringWithFormat:@"(function(){document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-scope=container] [data-mp-option=\"%@\"]').click();})()",value]];
}

- (NSArray<NSView *> *)allSubviewsOf:(NSView *)view
{
    NSMutableArray *views=[NSMutableArray array];
    for (NSView *child in view.subviews) {
        [views addObject:child];
        [views addObjectsFromArray:[self allSubviewsOf:child]];
    }
    return views;
}

// Drive NSAlert's native controls inside its modal run loop. A bounded callback
// aborts only this test's modal session if the expected controls never appear;
// no Accessibility or UI-automation permission is required.
- (void)invokeLinkWithAddress:(NSString *)address apply:(BOOL)apply
{
    XCTAssertTrue([self.document previewHasFindFocus]);
    XCTAssertTrue([[self JS:@"Boolean(macdownPreviewEditor.selectionPayload('link'))"] boolValue]);
    __block BOOL answered=NO,finished=NO;
    __block NSString *modalDescription=@"No modal observed";
    __block NSUInteger attempts=0;
    __block void (^respond)(void);
    respond=^{
        if (finished) {respond=nil;return;}
        NSWindow *modal=NSApp.modalWindow;
        NSTextField *field=nil;
        NSButton *button=nil;
        NSMutableArray *controls=[NSMutableArray array];
        for (NSView *view in [self allSubviewsOf:modal.contentView]) {
            if ([view isKindOfClass:NSButton.class]) [controls addObject:[NSString stringWithFormat:@"button %@ tag %ld",[(NSButton *)view title],(long)view.tag]];
            if ([view isKindOfClass:NSTextField.class] && [(NSTextField *)view isEditable]) [controls addObject:[NSString stringWithFormat:@"editable field %@",[(NSTextField *)view stringValue]]];
            if ([view isKindOfClass:NSTextField.class] && [(NSTextField *)view isEditable] &&
                [[(NSTextField *)view stringValue] isEqualToString:@"https://"]) field=(NSTextField *)view;
            if ([view isKindOfClass:NSButton.class] && view.tag==(apply ? NSAlertFirstButtonReturn : NSAlertSecondButtonReturn)) button=(NSButton *)view;
        }
        if (modal) modalDescription=[controls componentsJoinedByString:@"; "];
        if (field && button) {
            field.stringValue=address;
            answered=YES; finished=YES;
            [button performClick:nil];
            respond=nil;
        } else if (++attempts>=40) {
            finished=YES;
            if (NSApp.modalWindow) [NSApp abortModal];
            respond=nil;
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.05*NSEC_PER_SEC)),dispatch_get_main_queue(),respond);
        }
    };
    dispatch_async(dispatch_get_main_queue(),respond);
    XCTAssertTrue([NSApp sendAction:@selector(toggleLink:) to:self.document from:nil]);
    finished=YES; respond=nil;
    XCTAssertTrue(answered,@"Expected link address field and %@ button must be available; %@",apply ? @"Apply" : @"Cancel",modalDescription);
}

- (void)testNativeLinkActionPreservesHeadingContainerSelectionAndRejectsCancelOrUnsafeURLAtomically
{
    NSString *source=@"::: {.callout-note}\n## Title\n# **Heading**\n\nBody\n:::\n\nNeighbor.\n";
    [self loadSource:source];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self invokeLinkWithAddress:@"https://example.com/scopes" apply:NO];
    XCTAssertEqualObjects(self.editor.string,source,@"Cancel must not create a Markdown link");
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self invokeLinkWithAddress:@"javascript:alert(1)" apply:YES];
    XCTAssertEqualObjects(self.editor.string,source,@"An unsafe URL must leave every scope unchanged");
    XCTAssertFalse([[self JS:@"!!document.querySelector('h1 a')"] boolValue]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self invokeLinkWithAddress:@"https://example.com/scopes" apply:YES];
    [self waitUntil:^BOOL{return [self.editor.string containsString:@"https://example.com/scopes"];} description:@"Native link action creates source Markdown"];
    [self waitForFormatting];
    XCTAssertFalse([self.editor.string containsString:@"<a"]);
    XCTAssertTrue([self.editor.string containsString:@"](https://example.com/scopes)"] ||
        [self.editor.string containsString:@"](<https://example.com/scopes>)"]);
    XCTAssertTrue([self.editor.string containsString:@"::: {.callout-note}"]);
    XCTAssertTrue([self.editor.string containsString:@"## Title"]);
    XCTAssertTrue([self.editor.string containsString:@"Body"]);
    XCTAssertTrue([self.editor.string hasSuffix:@"\nNeighbor.\n"]);
    XCTAssertEqualObjects([self JS:@"document.querySelector('h1 a').getAttribute('href')"],@"https://example.com/scopes");
    XCTAssertEqualObjects([self JS:@"document.querySelector('h1 a').textContent"],@"Heading");
    XCTAssertTrue([[self JS:@"!!document.querySelector('h1 strong')"] boolValue]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self assertMenuScope:@"block" value:@"h1" active:YES];
    [self assertMenuScope:@"container" value:@"callout-note" active:YES];
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-style=link]').getAttribute('aria-pressed')"],@"true");
}

- (void)testPreviewToolbarAndMenuHavePhysicalSizeCeilingAtHighZoom
{
    MPPreferences *preferences=self.document.preferences;
    CGFloat oldZoom=preferences.documentZoomLevel;
    BOOL oldRelative=preferences.previewZoomRelativeToBaseFontSize;
    @try {
        preferences.previewZoomRelativeToBaseFontSize=NO;
        [self loadSource:@"Heading\n\nBody\n"];
        for(NSNumber *level in @[@1,@1.5,@2,@3,@0.5,@3,@1]) {
            preferences.documentZoomLevel=level.doubleValue;
            [self.document scaleWebview];
            XCTAssertEqualWithAccuracy(self.web.pageSizeMultiplier,level.doubleValue,0.001);
            [self selectFromText:@"Heading" throughText:@"Heading"];
            NSString *dimensions=[self JS:@"JSON.stringify(document.querySelector('#macdown-preview-format').getBoundingClientRect().toJSON())"];
            NSDictionary *rect=[NSJSONSerialization JSONObjectWithData:[dimensions dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            XCTAssertLessThanOrEqual([rect[@"width"] doubleValue]*level.doubleValue,345,@"Toolbar width at %@",level);
            XCTAssertLessThanOrEqual([rect[@"height"] doubleValue]*level.doubleValue,110,@"Toolbar height at %@",level);
            [self JS:@"document.querySelector('[data-mp-format-menu]').dispatchEvent(new MouseEvent('mouseenter'))"];
            dimensions=[self JS:@"JSON.stringify(document.querySelector('[role=menu]').getBoundingClientRect().toJSON())"];
            rect=[NSJSONSerialization JSONObjectWithData:[dimensions dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            XCTAssertLessThanOrEqual([rect[@"width"] doubleValue]*level.doubleValue,261,@"Menu width at %@",level);
            XCTAssertTrue([[self JS:@"(function(){var m=document.querySelector('[role=menu]').getBoundingClientRect();return m.left>=0 && m.right<=innerWidth && m.top>=0 && m.bottom<=innerHeight;})()"] boolValue],@"Menu stays visible at %@",level);
            XCTAssertTrue([[self JS:@"(function(){var b=document.querySelector('[data-mp-option=h2]'),r=b.getBoundingClientRect(),target=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);return target && target.closest('button')===b;})()"] boolValue],@"Menu hit target at %@",level);
            XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
        }
        preferences.documentZoomLevel=3;
        [self.document scaleWebview];
        [self selectFromText:@"Heading" throughText:@"Heading"];
        [self JS:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForFormatting];
        XCTAssertEqualObjects(self.editor.string,@"**Heading**\n\nBody\n");
        XCTAssertTrue([[self JS:@"document.querySelector('#macdown-preview-format').getBoundingClientRect().width*3<=345"] boolValue]);
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    } @finally {
        preferences.documentZoomLevel=oldZoom;
        preferences.previewZoomRelativeToBaseFontSize=oldRelative;
    }
}

- (void)testPopoverCeilingAlsoAppliesOnInitialLoadWithRelativeFontZoom
{
    MPPreferences *preferences=self.document.preferences;
    CGFloat oldZoom=preferences.documentZoomLevel;
    NSFont *oldFont=preferences.editorBaseFont;
    BOOL oldRelative=preferences.previewZoomRelativeToBaseFontSize;
    @try {
        preferences.previewZoomRelativeToBaseFontSize=YES;
        NSFont *font=[NSFont fontWithName:oldFont.fontName size:21];
        XCTAssertNotNil(font);
        preferences.editorBaseFont=font;
        preferences.documentZoomLevel=3;
        [self loadSource:@"Heading\n\nBody\n"];
        XCTAssertEqualWithAccuracy(self.web.pageSizeMultiplier,4.5,0.001);
        [self selectFromText:@"Heading" throughText:@"Heading"];
        XCTAssertTrue([[self JS:@"document.querySelector('#macdown-preview-format').getBoundingClientRect().width*4.5<=345"] boolValue]);
        [self JS:@"document.querySelector('[data-mp-format-menu]').dispatchEvent(new MouseEvent('mouseenter'))"];
        XCTAssertTrue([[self JS:@"(function(){var p=document.querySelector('#macdown-preview-format').getBoundingClientRect(),m=document.querySelector('[role=menu]').getBoundingClientRect();return m.width*4.5<=261 && Math.abs(p.right-m.left)<1 && m.bottom<=innerHeight;})()"] boolValue]);
        XCTAssertEqualObjects(self.editor.string,@"Heading\n\nBody\n");
    } @finally {
        preferences.documentZoomLevel=oldZoom;
        preferences.editorBaseFont=oldFont;
        preferences.previewZoomRelativeToBaseFontSize=oldRelative;
    }
}

- (void)testNormalTextClearsRenderedStylesAndHeadingWithoutLosingSelection
{
    [self loadSource:@"# **Heading**\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self.document resetToNormalText:nil];
    [self waitForFormatting];
    [self waitUntil:^BOOL{return [self.editor.string isEqualToString:@"Heading\n\nBody\n"] && ![self.document valueForKey:@"previewSelectionToRestore"];} description:@"Complete both normal-text formatting stages"];
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
}
- (void)testNewSelectionAlwaysReopensCompactToolbar
{
    [self loadSource:@"Heading\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"document.querySelector('[data-mp-format-menu]').click()"];
    XCTAssertFalse([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
    [self JS:@"document.body.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0,detail:1}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));"];
    [self selectFromText:@"Body" throughText:@"Body"];
    XCTAssertTrue([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-format-menu]').getAttribute('aria-expanded')"],@"false");
}

- (void)testHoverPreviewsEveryEnabledFormattingChoiceWithoutChangingMarkdown
{
    NSString *source=@"# **Heading**\n\nBody\n";
    [self loadSource:source];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    BOOL dirty=self.document.isDocumentEdited;
    BOOL canUndo=self.editor.undoManager.canUndo;
    NSString *token=self.document.previewEditToken;
    NSArray *choices=@[@[@"paragraph",@"p"],@[@"h1",@"h1"],@[@"h2",@"h2"],@[@"h3",@"h3"],
        @[@"h4",@"h4"],@[@"h5",@"h5"],@[@"h6",@"h6"],@[@"unordered",@"ul"],@[@"ordered",@"ol"],
        @[@"tasks",@"input[type=checkbox]"],@[@"quote",@"blockquote"],@[@"code-block",@"pre code"],
        @[@"callout-note",@".mp-callout-note"],@[@"callout-tip",@".mp-callout-tip"],@[@"callout-warning",@".mp-callout-warning"],
        @[@"callout-important",@".mp-callout-important"],@[@"callout-caution",@".mp-callout-caution"],
        @[@"toggle",@"details"],@[@"toggle-h1",@"details summary h1"],@[@"toggle-h2",@"details summary h2"],
        @[@"toggle-h3",@"details summary h3"],@[@"toggle-h4",@"details summary h4"],@[@"no-container",@"h1"]];
    [self JS:@"window.__originalNodes=Array.from(document.body.childNodes);document.querySelector('[data-mp-format-menu]').click()"];
    for (NSUInteger cycle=0;cycle<2;cycle++) for (NSArray *choice in choices) {
        NSString *hover=[NSString stringWithFormat:@"document.querySelector('[data-mp-option=\"%@\"]').dispatchEvent(new MouseEvent('mouseenter'))",choice[0]];
        [self JS:hover];
        NSString *probe=[NSString stringWithFormat:@"!!document.querySelector('%@')",choice[1]];
        XCTAssertTrue([[self JS:probe] boolValue],@"Preview %@",choice[0]);
        if ([choice[0] hasPrefix:@"callout-"])
            XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('.mp-callout')).borderLeftWidth"],@"4px",@"Preview includes the callout stylesheet");
        XCTAssertEqualObjects(self.editor.string,source);
        XCTAssertEqualObjects(self.document.previewEditToken,token);
        XCTAssertEqual(self.document.isDocumentEdited,dirty);
        XCTAssertEqual(self.editor.undoManager.canUndo,canUndo);
        [self JS:@"document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))"];
        XCTAssertTrue([[self JS:@"window.__originalNodes.every(function(n,i){return document.body.childNodes[i]===n;}) && document.body.childNodes.length===window.__originalNodes.length"] boolValue]);
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
        [self JS:@"document.querySelector('[data-mp-format-menu]').click()"];
    }
    [self JS:@"document.querySelector('[data-mp-option=math-block]').dispatchEvent(new MouseEvent('mouseenter'))"];
    XCTAssertFalse([[self JS:@"!!document.querySelector('pre')"] boolValue]);
    XCTAssertEqualObjects(self.editor.string,source);
}

- (void)testHoverPreviewSurvivesGapsAndSeparatorsUntilLeavingMenu
{
    NSString *source=@"Heading\n\nBody\n";
    [self loadSource:source];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=h2]').dispatchEvent(new MouseEvent('mouseenter'));window.__hoverHeading=document.querySelector('h2');"];
    NSArray *gaps=@[@"[role=group]",@"[role=separator]",@"[role=menu]",@"[data-mp-option=math-block]"];
    for (NSString *gap in gaps) {
        NSString *script=[NSString stringWithFormat:@"(function(){var gap=document.querySelector('%@'),choice=document.querySelector('[data-mp-option=h2]');choice.dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:gap}));gap.dispatchEvent(new MouseEvent('mouseenter',{relatedTarget:choice}));})()",gap];
        [self JS:script];
        XCTAssertTrue([[self JS:@"document.querySelector('h2')===window.__hoverHeading && window.__hoverHeading.isConnected"] boolValue],@"Keep the same preview over %@",gap);
        XCTAssertEqualObjects(self.editor.string,source);
    }
    [self JS:@"document.querySelector('[data-mp-option=quote]').dispatchEvent(new MouseEvent('mouseenter'));document.querySelector('[data-mp-option=quote]').dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:document.querySelector('[role=separator]')}))"];
    XCTAssertTrue([[self JS:@"!!document.querySelector('blockquote') && !document.querySelector('h2')"] boolValue]);
    [self JS:@"document.querySelector('[role=menu]').dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:document.body}))"];
    [self waitUntil:^BOOL{return [[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue];} description:@"Leaving the menu cancels the last preview"];
    XCTAssertFalse([[self JS:@"!!document.querySelector('blockquote,h2')"] boolValue]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    XCTAssertEqualObjects(self.editor.string,source);
}

- (void)testHoverCancellationRestoresCalloutDOMStateAndSelection
{
    NSString *source=@"::: {.callout-note}\n## Title\nHeading\n:::\n\nBody\n";
    [self loadSource:source];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"window.__originalNodes=Array.from(document.body.childNodes);window.__selectedSpan=macdownPreviewEditor.elements().spans.find(function(n){return n.textContent==='Heading';});window.__selectedSpan.__retainedState='original';window.__neighbor=macdownPreviewEditor.elements().spans.find(function(n){return n.textContent==='Body';});"];
    NSArray *cancellations=@[@"document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))",
        @"window.dispatchEvent(new Event('blur'))",
        @"document.querySelector('[role=menu]').dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:document.body}))"];
    for (NSString *cancel in cancellations) {
        [self JS:@"document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=h2]').dispatchEvent(new MouseEvent('mouseenter'))"];
        XCTAssertTrue([[self JS:@"Array.from(document.querySelectorAll('.mp-callout-note h2')).some(function(n){return n.textContent==='Heading';})"] boolValue]);
        XCTAssertTrue([[self JS:@"window.__neighbor.isConnected"] boolValue],@"Unchanged neighbors remain live during the preview");
        [self JS:cancel];
        [self waitUntil:^BOOL{return [[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue];} description:@"Cancel hover menu"];
        XCTAssertTrue([[self JS:@"window.__originalNodes.every(function(n,i){return document.body.childNodes[i]===n;})"] boolValue]);
        XCTAssertEqualObjects([self JS:@"window.__selectedSpan.__retainedState"],@"original");
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
        XCTAssertEqualObjects(self.editor.string,source);
        XCTAssertFalse([[self JS:@"Array.from(document.querySelectorAll('.mp-callout-note h2')).some(function(n){return n.textContent==='Heading';})"] boolValue]);
    }
}

- (void)testHoverAcrossBlocksPreservesUnicodeAndUnchangedExpandedDetails
{
    NSString *source=@"Alpha 😀\n\nBêta 漢字\n\n<details><summary>Keep</summary><p>Neighbor</p></details>\n";
    [self loadSource:source];
    [self selectFromText:@"Alpha 😀" throughText:@"Bêta 漢字"];
    NSString *selected=[self JS:@"getSelection().toString()"];
    [self JS:@"window.__neighborDetails=document.querySelector('details');window.__neighborDetails.open=true;document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=quote]').dispatchEvent(new MouseEvent('mouseenter'))"];
    XCTAssertTrue([[self JS:@"document.querySelector('blockquote').textContent.includes('Alpha 😀') && document.querySelector('blockquote').textContent.includes('Bêta 漢字')"] boolValue]);
    XCTAssertTrue([[self JS:@"window.__neighborDetails.isConnected && window.__neighborDetails.open"] boolValue]);
    [self JS:@"document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))"];
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],selected);
    XCTAssertEqualObjects(self.editor.string,source);
    XCTAssertTrue([[self JS:@"document.querySelector('details')===window.__neighborDetails && window.__neighborDetails.open"] boolValue]);
}

- (void)testClickCommitsHoveredChoiceAndOtherChoicesNeverAccumulate
{
    [self loadSource:@"Heading\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=callout-warning]').dispatchEvent(new MouseEvent('mouseenter'));document.querySelector('[data-mp-option=quote]').dispatchEvent(new MouseEvent('mouseenter'));document.querySelector('[data-mp-option=h2]').dispatchEvent(new MouseEvent('mouseenter'))"];
    XCTAssertTrue([[self JS:@"!!document.querySelector('h2') && !document.querySelector('blockquote,.mp-callout-warning')"] boolValue]);
    XCTAssertEqualObjects(self.editor.string,@"Heading\n\nBody\n");
    [self JS:@"document.querySelector('[data-mp-option=h2]').click()"];
    [self waitForFormatting];
    XCTAssertEqualObjects(self.editor.string,@"## Heading\n\nBody\n");
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    XCTAssertTrue([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
    XCTAssertFalse([[self JS:@"!!document.querySelector('blockquote,.mp-callout-warning')"] boolValue]);
}

- (void)testHoverRejectsStaleSourceAndRestoresBeforeOutsideSelection
{
    [self loadSource:@"Heading\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"document.querySelector('[data-mp-format-menu]').click()"];
    self.editor.string=@"Changed\n\nBody\n";
    [self JS:@"document.querySelector('[data-mp-option=h2]').dispatchEvent(new MouseEvent('mouseenter'))"];
    XCTAssertFalse([[self JS:@"!!document.querySelector('h2')"] boolValue]);
    XCTAssertEqualObjects(self.editor.string,@"Changed\n\nBody\n");
    [self loadSource:@"Heading\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=quote]').dispatchEvent(new MouseEvent('mouseenter'));document.body.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0,detail:1}));window.dispatchEvent(new MouseEvent('mouseup'))"];
    XCTAssertFalse([[self JS:@"!!document.querySelector('blockquote')"] boolValue]);
    [self selectFromText:@"Body" throughText:@"Body"];
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Body");
    XCTAssertEqualObjects(self.editor.string,@"Heading\n\nBody\n");
}

- (void)testHoverMenuKeepsCompactGeometrySelectionAndExistingOptions
{
    [self loadSource:@"# **Heading**\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    NSString *options=[self JS:@"JSON.stringify(Array.from(document.querySelectorAll('[data-mp-option]')).map(function(b){return b.getAttribute('data-mp-option');}))"];
    for (NSNumber *width in @[@900,@600,@300]) {
        [self.web setFrameSize:NSMakeSize(width.doubleValue,450)];
        [self selectFromText:@"Heading" throughText:@"Heading"];
        [self JS:@"window.dispatchEvent(new Event('resize'));window.__compactLeft=document.querySelector('#macdown-preview-format').getBoundingClientRect().left;window.__compactHeight=document.querySelector('#macdown-preview-format').offsetHeight;document.querySelector('[data-mp-format-menu]').dispatchEvent(new MouseEvent('mouseenter'));"];
        XCTAssertFalse([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
        XCTAssertTrue([[self JS:@"document.querySelector('#macdown-preview-format').offsetHeight===window.__compactHeight"] boolValue]);
        XCTAssertTrue([[self JS:@"document.querySelector('#macdown-preview-format').getBoundingClientRect().left===window.__compactLeft"] boolValue]);
        XCTAssertTrue([[self JS:@"(function(){var p=document.querySelector('#macdown-preview-format'),o=p.querySelector('[data-mp-format-menu]'),buttons=Array.from(p.children).filter(function(b){return b.tagName==='BUTTON' && b!==o;});return Math.abs(o.getBoundingClientRect().right-Math.max.apply(null,buttons.map(function(b){return b.getBoundingClientRect().right;})))<1;})()"] boolValue]);
        XCTAssertTrue([[self JS:@"(function(){var m=document.querySelector('[role=menu]').getBoundingClientRect();return m.left>=12 && m.right<=innerWidth-12 && m.top>=8 && m.bottom<=innerHeight-8;})()"] boolValue],@"%@",[self JS:@"JSON.stringify({menu:document.querySelector(\'[role=menu]\').getBoundingClientRect().toJSON(),width:innerWidth,height:innerHeight})"]);
        if(width.intValue>=600) {
            XCTAssertTrue([[self JS:@"(function(){var p=document.querySelector('#macdown-preview-format').getBoundingClientRect(),m=document.querySelector('[role=menu]').getBoundingClientRect();return Math.abs(p.right-m.left)<1;})()"] boolValue]);
        }
        if(width.intValue==300) {
            XCTAssertTrue([[self JS:@"(function(){var p=document.querySelector('#macdown-preview-format').getBoundingClientRect(),m=document.querySelector('[role=menu]').getBoundingClientRect();return m.top>=p.bottom || m.bottom<=p.top;})()"] boolValue]);
        }
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
        XCTAssertEqualObjects([self JS:@"JSON.stringify(Array.from(document.querySelectorAll('[data-mp-option]')).map(function(b){return b.getAttribute('data-mp-option');}))"],options);
        [self JS:@"(function(){var o=document.querySelector('[data-mp-format-menu]'),m=document.querySelector('[role=menu]');o.dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:m}));m.dispatchEvent(new MouseEvent('mouseenter',{relatedTarget:o}));m.dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true}));})()"];
        [self JS:@"window.__menuCrossed=false;setTimeout(function(){window.__menuCrossed=true;},220)"];
        [self waitUntil:^BOOL{return [[self JS:@"window.__menuCrossed"] boolValue];} description:@"Crossing into menu must not trigger delayed closure"];
        XCTAssertFalse([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
        XCTAssertEqualObjects([self JS:@"document.activeElement.getAttribute('data-mp-option')"],@"toggle-h4");
        XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('[data-mp-format-menu]')).opacity"],@"0.08");
        XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('[role=menu]')).opacity"],@"1");
        XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('#macdown-preview-format')).opacity"],@"1",@"The parent must not fade its dropdown");
        [self JS:@"document.querySelector('[role=menu]').dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:document.querySelector('[data-mp-format-menu]')}))"];
        XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('[data-mp-format-menu]')).opacity"],@"1");
        XCTAssertFalse([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
        [self JS:@"document.querySelector('[role=menu]').dispatchEvent(new MouseEvent('mouseenter'))"];
        [self JS:@"document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))"];
        XCTAssertTrue([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
        XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('[data-mp-format-menu]')).opacity"],@"1");
    }
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self JS:@"document.querySelector('[data-mp-format-menu]').dispatchEvent(new MouseEvent('mouseenter'));document.querySelector('[role=menu]').dispatchEvent(new MouseEvent('mouseleave',{relatedTarget:document.body}))"];
    [self waitUntil:^BOOL{return [[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue];} description:@"Menu closes after leaving both surfaces"];
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self JS:@"document.querySelector('[data-mp-format-menu]').dispatchEvent(new MouseEvent('mouseenter'));document.querySelector('[data-mp-option=h2] span').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));document.querySelector('[data-mp-option=h2]').click()"];
    [self waitForFormatting];
    XCTAssertEqualObjects(self.editor.string,@"## **Heading**\n\nBody\n");
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    XCTAssertTrue([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
}

- (void)testTextDropdownHasSeparatedScopesAndInlineIconsKeepTooltips
{
    [self loadSource:@"# **Heading**\n\nBody\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    XCTAssertEqualObjects([self JS:@"String(document.querySelectorAll('#macdown-preview-format select').length)"],@"0");
    XCTAssertEqualObjects([self JS:@"String(document.querySelectorAll('#macdown-preview-format [role=separator]').length)"],@"1");
    XCTAssertTrue([[self JS:@"Array.from(document.querySelectorAll('#macdown-preview-format > [data-mp-inline],#macdown-preview-format > [data-mp-edit-text]')).every(function(b){return b.querySelector('svg') && b.title && b.getAttribute('aria-label')===b.title && !Array.from(b.childNodes).some(function(n){return n.nodeType===3 && n.textContent.trim();});})"] boolValue]);
    XCTAssertTrue([[self JS:@"Array.from(document.querySelectorAll('[data-mp-option]')).every(function(b){return b.querySelector('span').textContent===b.getAttribute('aria-label');})"] boolValue]);
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-format-menu]').textContent"],@"Titre 1");
    XCTAssertTrue([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
    [self JS:@"document.querySelector('[data-mp-format-menu]').click()"];
    XCTAssertFalse([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
    XCTAssertTrue([[self JS:@"(function(){var r=document.querySelector('#macdown-preview-format').getBoundingClientRect();return r.top>=0 && r.bottom<=innerHeight;})()"] boolValue]);
    [self assertMenuScope:@"block" value:@"h1" active:YES];
    [self assertMenuScope:@"container" value:@"no-container" active:YES];
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self JS:@"document.querySelector('[data-mp-format-menu]').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}))"];
    XCTAssertEqualObjects([self JS:@"document.activeElement.getAttribute('data-mp-option')"],@"paragraph");
    [self JS:@"document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}))"];
    XCTAssertEqualObjects([self JS:@"document.activeElement.getAttribute('data-mp-option')"],@"h1");
    [self JS:@"document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))"];
    XCTAssertTrue([[self JS:@"document.querySelector('[role=menu]').hidden"] boolValue]);
    XCTAssertTrue([[self JS:@"document.activeElement.hasAttribute('data-mp-format-menu')"] boolValue]);
    XCTAssertEqualObjects(self.editor.string,@"# **Heading**\n\nBody\n");
    [self JS:@"document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=h2]').click()"];
    [self waitForFormatting];
    XCTAssertEqualObjects(self.editor.string,@"## **Heading**\n\nBody\n");
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self assertMenuScope:@"block" value:@"h2" active:YES];
    [self assertMenuScope:@"container" value:@"no-container" active:YES];
}

- (void)testHeadingAndContainerAreIndependentAndMixedBlocksKeepOnlyTheirCommonContainer
{
    [self loadSource:@"::: {.callout-note}\n## Title\n# **Heading**\n\nBody\n:::\n\nNeighbor.\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    XCTAssertEqualObjects([self JS:@"String(document.querySelectorAll('#macdown-preview-format [data-mp-format-menu]').length)"],@"1");
    [self assertMenuScope:@"block" value:@"h1" active:YES];
    [self assertMenuScope:@"container" value:@"callout-note" active:YES];
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"true");
    [self selectFromText:@"Heading" throughText:@"Body"];
    [self assertMenuScope:@"block" value:@"" active:NO];
    [self assertMenuScope:@"container" value:@"callout-note" active:YES];
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"false");
    [self selectFromText:@"Heading" throughText:@"Neighbor."];
    [self assertMenuScope:@"block" value:@"" active:NO];
    [self assertMenuScope:@"container" value:@"" active:NO];
    XCTAssertEqualObjects(self.editor.string,@"::: {.callout-note}\n## Title\n# **Heading**\n\nBody\n:::\n\nNeighbor.\n");
}

- (void)testForceTouchPreparationIsCancelledOnlyForMappedPreviewProse
{
    for (NSString *style in @[@"GitHub2",@"Github2 (dark)"]) {
        self.document.preferences.htmlStyleName=style;
        for (NSString *prefix in @[@"",@"> ",@"# "]) {
            NSString *source=[NSString stringWithFormat:@"%@Plainword [Linkword](https://example.com) **Boldword**\n\nNeighbor.\n",prefix];
            [self loadSource:source];
            [self selectFromText:@"Plainword " throughText:@"Plainword "];
            NSString *result=[self JS:@"(function(){var nodes=macdownPreviewEditor.elements().spans,p=nodes.find(function(n){return n.textContent==='Plainword ';}),bold=nodes.find(function(n){return n.textContent==='Boldword';}),link=nodes.find(function(n){return n.textContent==='Linkword';}),button=document.querySelector('[data-mp-style=bold]');if(!p||!bold||!link)return 'missing mapped fixture';return JSON.stringify([p,bold,link,button,document.body].map(function(target){var event=new MouseEvent('webkitmouseforcewillbegin',{bubbles:true,cancelable:true,button:0});target.dispatchEvent(event);return event.defaultPrevented;}));})()"];
            XCTAssertEqualObjects(result,@"[true,true,false,false,false]",@"%@ %@",style,prefix);
            XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Plainword ");
            XCTAssertEqualObjects(self.editor.string,source);
            [self JS:@"document.querySelector('[data-mp-edit-text]').click()"];
            XCTAssertEqualObjects([self JS:@"(function(){var p=document.querySelector('[contenteditable=true]');if(!p)return 'missing active edit';var event=new MouseEvent('webkitmouseforcewillbegin',{bubbles:true,cancelable:true,button:0});p.dispatchEvent(event);p.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Escape'}));return String(event.defaultPrevented);})()"],@"false");
            [self waitForFormatting];
            XCTAssertEqualObjects(self.editor.string,source);
        }
    }
}

- (void)testMultilineBoldBecomesIndependentStyledListItemsInRealPreview
{
    for(NSString *style in @[@"GitHub2",@"Github2 (dark)"]) for(NSString *target in @[@"unordered",@"ordered",@"tasks"]) for(NSNumber *intra in @[@NO,@YES]) {
        self.document.preferences.htmlStyleName=style;
        self.document.preferences.extensionIntraEmphasis=intra.boolValue;
        self.renderer.rendererFlags=self.document.preferences.rendererFlags;
        [self loadSource:@"**first\nsecond\nthird**\nplain\n"];
        [self selectFromText:@"first" throughText:@"plain"];
        [self JS:[NSString stringWithFormat:@"document.querySelector('[data-mp-format-menu]').click();document.querySelector('[data-mp-option=\"%@\"]').click()",target]];
        [self waitForFormatting];
        XCTAssertEqualObjects([self JS:@"String(document.querySelectorAll('li').length)"],@"4");
        XCTAssertEqualObjects([self JS:@"String(document.querySelectorAll('li strong').length)"],@"3");
        XCTAssertEqualObjects([self JS:@"Array.from(document.querySelectorAll('li strong')).map(function(n){return n.textContent;}).join('|')"],@"first|second|third");
        XCTAssertFalse([[self JS:@"document.body.textContent.includes('**')"] boolValue]);
        XCTAssertTrue([[self JS:@"getSelection().toString().includes('first') && getSelection().toString().includes('plain')"] boolValue],@"%@ %@ source=%@ selection=%@ mapped=%lu",style,target,self.editor.string,[self JS:@"getSelection().toString()"],(unsigned long)self.document.previewEditRanges.count);
        XCTAssertEqualObjects([self JS:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"],@"block");
        [self JS:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForFormatting];
        XCTAssertEqualObjects([self JS:@"String(document.querySelectorAll('li strong').length)"],@"4");
        XCTAssertTrue([[self JS:@"getSelection().toString().includes('first') && getSelection().toString().includes('plain')"] boolValue]);
    }
}

- (void)testMixedPreviewSelectionWorksWithIntraWordEmphasisDisabledAndEnabled
{
    NSArray *cases=@[
        @[@"test **mot** selection\n",@"test ",@"mot",@"test mot"],
        @[@"**premier** **second**\n",@"premier",@"second",@"premier second"],
        @[@"**mot** et **mot**\n",@"mot",@" et ",@"mot et "]
    ];
    for (NSNumber *enabled in @[@NO,@YES]) for (NSString *prefix in @[@"",@"> ",@"# "]) for (NSArray *scenario in cases) {
        self.document.preferences.extensionIntraEmphasis=enabled.boolValue;
        self.renderer.rendererFlags=self.document.preferences.rendererFlags;
        NSString *source=[NSString stringWithFormat:@"%@%@\n[Preserved link](https://example.com)\n",prefix,scenario[0]];
        [self loadSource:source];
        if ([scenario[0] hasPrefix:@"**mot**"]) XCTAssertEqualObjects([self JS:@"String(macdownPreviewEditor.elements().spans.filter(function(n){return n.textContent==='mot';}).length)"],@"2");
        [self selectFromText:scenario[1] throughText:scenario[2]];
        XCTAssertEqualObjects([self JS:@"macdownPreviewEditor.selectionPayload('bold').text"],scenario[3],@"%@ %@ %@",enabled,prefix,scenario[0]);
        XCTAssertEqual(self.document.preferences.extensionIntraEmphasis,enabled.boolValue,@"Installing the mapping must preserve the user's setting");
        [self JS:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForFormatting];
        // Inline actions intentionally exclude edge whitespace from their
        // retained range; all selected letters must survive the render.
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],[scenario[3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]);
        XCTAssertTrue([self.editor.string hasSuffix:@"[Preserved link](https://example.com)\n"]);
        XCTAssertFalse([self.editor.string containsString:@"<"]);
    }
}

- (void)testWhitespaceMappingRejectsAttributeLookalikesAndAcceptsLiteralSeparators
{
    for (NSNumber *enabled in @[@NO,@YES]) {
        self.document.preferences.extensionIntraEmphasis=enabled.boolValue;
        self.renderer.rendererFlags=self.document.preferences.rendererFlags;
        NSString *source=@"first<span title=\"  \">&#32;&#32;</span>second\n";
        [self loadSource:source];
        XCTAssertEqualObjects([self JS:@"JSON.stringify(macdownPreviewEditor.elements().spans.map(function(n){return n.textContent;}))"],@"[\"first\",\"second\"]");
        [self JS:@"(function(){var p=document.querySelector('p'),r=document.createRange();r.selectNodeContents(p);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));})()"];
        XCTAssertEqualObjects([self JS:@"String(macdownPreviewEditor.selectionPayload('bold'))"],@"null");
        XCTAssertEqualObjects(self.editor.string,source);
        for (NSString *separator in @[@" ",@"  "]) {
            source=[NSString stringWithFormat:@"**first**%@**second**\n",separator];
            [self loadSource:source];
            [self selectFromText:@"first" throughText:@"second"];
            XCTAssertEqualObjects([self JS:@"macdownPreviewEditor.selectionPayload('bold').text"],([NSString stringWithFormat:@"first%@second",separator]));
            XCTAssertEqualObjects(self.editor.string,source);
        }
        // Hoedown normalizes a source tab into a displayed space. Literal
        // provenance cannot equate those two offsets and must refuse safely.
        source=@"**first**\t**second**\n";
        [self loadSource:source];
        [self JS:@"(function(){var p=document.querySelector('p'),r=document.createRange();r.selectNodeContents(p);getSelection().removeAllRanges();getSelection().addRange(r);})()"];
        XCTAssertEqualObjects([self JS:@"String(macdownPreviewEditor.selectionPayload('bold'))"],@"null");
        XCTAssertEqualObjects(self.editor.string,source);
    }
}

- (void)testAllInlineSubsetsMapAcrossParserModesAndLightAndDarkThemes
{
    NSArray *styles=@[@"code",@"underline",@"strike",@"italic",@"bold",@"link"];
    NSUInteger exercised=0;
    for (NSString *theme in @[@"GitHub2",@"Github2 (dark)"]) for (NSNumber *enabled in @[@NO,@YES]) for (NSUInteger mask=0;mask<64;mask++) {
        self.document.preferences.htmlStyleName=theme;
        self.document.preferences.extensionIntraEmphasis=enabled.boolValue;
        self.renderer.rendererFlags=self.document.preferences.rendererFlags;
        // Compose through the public source adapter, then independently prove
        // that the real WebView maps the result and exposes the expected styles.
        self.editor.string=@"Lead Needle tail.\n\nNeighbor unchanged.\n";
        for (NSUInteger bit=0;bit<styles.count;bit++) if (mask&(1u<<bit)) {
            self.editor.selectedRange=[self.editor.string rangeOfString:@"Needle"];
            XCTAssertTrue([self.document formatSourceInlineAction:styles[bit] value:[styles[bit] isEqual:@"link"]?@"https://example.org/target":nil],@"mask=%lu %@",(unsigned long)mask,styles[bit]);
        }
        NSString *source=self.editor.string.copy;
        self.document.preferences.extensionIntraEmphasis=enabled.boolValue;
        self.renderer.rendererFlags=self.document.preferences.rendererFlags;
        [self loadSource:source];
        [self selectFromText:@"Needle" throughText:@"Needle"];
        XCTAssertEqual(self.document.preferences.extensionIntraEmphasis,enabled.boolValue);
        XCTAssertEqualObjects([self JS:@"macdownPreviewEditor.selectionPayload('bold').text"],@"Needle",@"%@ %@ mask=%lu",theme,enabled,(unsigned long)mask);
        for (NSUInteger bit=0;bit<styles.count;bit++) {
            NSString *script=[NSString stringWithFormat:@"document.querySelector('[data-mp-style=%@]').getAttribute('aria-pressed')",styles[bit]];
            XCTAssertEqualObjects([self JS:script],(mask&(1u<<bit))?@"true":@"false",@"mask=%lu %@",(unsigned long)mask,styles[bit]);
        }
        XCTAssertEqualObjects(self.editor.string,source);
        XCTAssertTrue([source hasSuffix:@"Neighbor unchanged.\n"]);
        exercised++;
    }
    XCTAssertEqual(exercised,256u);
}

- (void)testMixedUnicodeMappingAcrossLineTypesContainersAndLineEndings
{
    NSUInteger exercised=0;
    for (NSString *ending in @[@"\n",@"\r\n"]) for (NSString *prefix in @[@"",@"# ",@"## ",@"> ",@"- ",@"1. ",@"- [ ] "]) for (NSString *container in @[@"",@"::: {.callout-note}\n## Title\n",@"::: {.callout-note collapse=\"true\"}\n## Title\n"]) {
        NSString *source=[NSString stringWithFormat:@"%@%@Été 👩🏽‍💻 **émoji** suite\n%@\nNeighbor unchanged.\n",container,prefix,container.length?@":::\n":@""];
        source=[source stringByReplacingOccurrencesOfString:@"\n" withString:ending];
        [self loadSource:source];
        [self JS:@"document.querySelectorAll('details').forEach(function(d){d.open=true;})"];
        [self selectFromText:@"Été 👩🏽‍💻 " throughText:@"émoji"];
        XCTAssertEqualObjects([self JS:@"macdownPreviewEditor.selectionPayload('bold').text"],@"Été 👩🏽‍💻 émoji");
        [self JS:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForFormatting];
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Été 👩🏽‍💻 émoji");
        XCTAssertTrue([self.editor.string hasSuffix:[@"Neighbor unchanged." stringByAppendingString:ending]]);
        if (container.length) XCTAssertEqualObjects([self JS:@"document.querySelector('aside,details').textContent.includes('Title')"],@"true");
        if ([container containsString:@"collapse"]) XCTAssertEqualObjects([self JS:@"String(document.querySelector('details').open)"],@"true");
        exercised++;
    }
    XCTAssertEqual(exercised,42u);
}

- (void)testSourceInlineActionsKeepTheChosenWordWithSelectionNotifications
{
    // Real document windows subscribe to this notification; these lightweight
    // WebView fixtures must install the same observer to exercise focus handoff.
    [NSNotificationCenter.defaultCenter addObserver:self.document selector:@selector(editorSelectionDidChange:)
        name:NSTextViewDidChangeSelectionNotification object:self.editor];
    @try {
        for (NSString *prefix in @[@"",@"# ",@"> ",@"::: {.callout-note}\n## Title\n"]) {
            for (NSString *action in @[@"bold",@"italic",@"underline",@"strike",@"code",@"link",@"clear"]) {
                BOOL clear=[action isEqualToString:@"clear"];
                NSString *source=[NSString stringWithFormat:@"%@Bonjour %@ après test\n%@",prefix,clear?@"**test**":@"test",[prefix hasPrefix:@":::"]?@":::\n":@""];
                [self loadSource:source];
                XCTAssertTrue([self.window makeFirstResponder:self.editor]);
                NSRange word=[source rangeOfString:@"test"];
                self.editor.selectedRange=word;
                XCTAssertTrue([self.document formatSourceInlineAction:action value:[action isEqualToString:@"link"]?@"https://example.org":nil],@"%@ %@",prefix,action);
                NSRange selected=self.editor.selectedRange;
                XCTAssertTrue(NSMaxRange(selected)<=self.editor.string.length);
                XCTAssertEqualObjects([self.editor.string substringWithRange:selected],@"test",@"%@ %@ — immediately after formatting",prefix,action);
                [self waitForFormatting];
                XCTAssertTrue(NSEqualRanges(self.editor.selectedRange,selected),@"%@ %@ — after preview rendering",prefix,action);
                XCTAssertTrue([self.editor.string containsString:@" après test"],@"Neighbouring repeated word remains outside selection");
                // Reapply using the retained selection, without selecting anew.
                if (!clear && ![action isEqualToString:@"link"]) {
                    XCTAssertTrue([self.document formatSourceInlineAction:action value:nil]);
                    XCTAssertEqualObjects([self.editor.string substringWithRange:self.editor.selectedRange],@"test");
                    [self waitForFormatting];
                }
            }
        }
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:self.document name:NSTextViewDidChangeSelectionNotification object:self.editor];
    }
}

- (void)testBlankPreviewPressClearsSelectionAndKeepsPanelClosed
{
    for (NSString *style in @[@"GitHub2",@"Github2 (dark)"]) {
        self.document.preferences.htmlStyleName=style;
        for (NSString *prefix in @[@"",@"> ",@"# "]) {
            NSString *source=[NSString stringWithFormat:@"%@Bonjour test\n",prefix];
            [self loadSource:source];
            for (NSString *target in @[@"body",@"block",@"blank"]) {
                [self selectFromText:@"Bonjour test" throughText:@"Bonjour test"];
                NSData *data=[NSJSONSerialization dataWithJSONObject:@[target] options:0 error:NULL];
                NSString *argument=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                [self JS:[NSString stringWithFormat:@"(function(){var kind=%@[0],span=macdownPreviewEditor.elements().spans[0],range=document.createRange();range.setStart(span.firstChild,8);range.setEnd(span.firstChild,12);getSelection().removeAllRanges();getSelection().addRange(range);var blank=document.createElement('div');document.body.appendChild(blank);var node=kind==='body'?document.body:kind==='block'?span.parentElement:blank;window.blankPressResult=null;node.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0,detail:1}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));setTimeout(function(){window.blankPressResult=JSON.stringify([getSelection().toString(),getComputedStyle(document.getElementById('macdown-preview-format')).display]);blank.remove();},250);})()",argument]];
                [self waitUntil:^BOOL{return [[self JS:@"String(window.blankPressResult!==null)"] boolValue];} description:@"Wait past the selection-change panel timer"];
                XCTAssertEqualObjects([self JS:@"window.blankPressResult"],@"[\"\",\"none\"]",@"%@ %@ %@",style,prefix,target);
                XCTAssertEqualObjects(self.editor.string,source);
            }
        }
    }
}

- (void)testFreshPreviewPressClearsOnlyUnmodifiedSingleClickSelections
{
    for (NSString *prefix in @[@"",@"> ",@"# "]) {
        NSString *source=[NSString stringWithFormat:@"%@Plainword [Linkword](https://example.com) **Boldword**\n\nNeighbor.\n",prefix];
        [self loadSource:source];
        NSArray *gestures=@[
            @{@"name":@"fresh press",@"options":@{@"detail":@1},@"target":@"plain",@"retained":@NO},
            @{@"name":@"double click",@"options":@{@"detail":@2},@"target":@"plain",@"retained":@YES},
            @{@"name":@"triple click",@"options":@{@"detail":@3},@"target":@"plain",@"retained":@YES},
            @{@"name":@"shift extension",@"options":@{@"detail":@1,@"shiftKey":@YES},@"target":@"plain",@"retained":@YES},
            @{@"name":@"command gesture",@"options":@{@"detail":@1,@"metaKey":@YES},@"target":@"plain",@"retained":@YES},
            @{@"name":@"control gesture",@"options":@{@"detail":@1,@"ctrlKey":@YES},@"target":@"plain",@"retained":@YES},
            @{@"name":@"option gesture",@"options":@{@"detail":@1,@"altKey":@YES},@"target":@"plain",@"retained":@YES},
            @{@"name":@"context menu",@"options":@{@"detail":@1,@"button":@2},@"target":@"plain",@"retained":@YES},
            @{@"name":@"link activation",@"options":@{@"detail":@1},@"target":@"link",@"retained":@YES},
            @{@"name":@"formatting control",@"options":@{@"detail":@1},@"target":@"button",@"retained":@YES},
            @{@"name":@"empty preview background",@"options":@{@"detail":@1},@"target":@"body",@"retained":@NO}
        ];
        for (NSDictionary *gesture in gestures) {
            NSData *data=[NSJSONSerialization dataWithJSONObject:gesture options:0 error:NULL];
            NSString *arguments=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSString *result=[self JS:[NSString stringWithFormat:
                @"(function(){var g=%@,nodes=macdownPreviewEditor.elements().spans,p=nodes.find(function(n){return n.textContent==='Plainword ';}),link=nodes.find(function(n){return n.textContent==='Linkword';});if(!p||!link)return 'missing mapped fixture';var r=document.createRange();r.setStart(p.firstChild,0);r.setEnd(p.firstChild,9);getSelection().removeAllRanges();getSelection().addRange(r);var targets={plain:p,link:link,button:document.querySelector('[data-mp-style=bold]'),body:document.body};targets[g.target].dispatchEvent(new MouseEvent('mousedown',Object.assign({bubbles:true,button:0},g.options)));var selected=getSelection().toString();window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return selected;})()",arguments]];
            XCTAssertEqualObjects(result,[gesture[@"retained"] boolValue]?@"Plainword":@"",@"%@ %@",prefix,gesture[@"name"]);
            XCTAssertEqualObjects(self.editor.string,source);
        }
        // Explicit text editing owns its range, even during a single press.
        [self selectFromText:@"Plainword " throughText:@"Plainword "];
        [self JS:@"document.querySelector('[data-mp-edit-text]').click()"];
        XCTAssertEqualObjects([self JS:@"(function(){var p=document.querySelector('[contenteditable=true]');if(!p)return 'missing active edit';p.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0,detail:1}));var text=getSelection().toString();window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));p.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Escape'}));return text;})()"],@"Plainword ");
        [self waitForFormatting];
        XCTAssertEqualObjects(self.editor.string,source);
    }
}

- (void)testInlineCodeAndEmphasisCanCoexistWhileFencedCodeKeepsStructuralMenus
{
    [self loadSource:@"::: {.callout-tip}\n## Title\n# **`Inline`**\n\n```\nLiteral\n```\n:::\n"];
    [self selectFromText:@"Inline" throughText:@"Inline"];
    [self assertMenuScope:@"block" value:@"h1" active:YES];
    [self assertMenuScope:@"container" value:@"callout-tip" active:YES];
    for (NSString *style in @[@"bold",@"code"]) {
        XCTAssertEqualObjects(([self JS:[NSString stringWithFormat:@"document.querySelector('[data-mp-style=%@]').getAttribute('aria-pressed')",style]]),@"true");
    }
    for (NSString *style in @[@"bold",@"italic",@"underline",@"strike",@"link",@"code"]) {
        XCTAssertFalse(([[self JS:[NSString stringWithFormat:@"document.querySelector('[data-mp-style=%@]').disabled",style]] boolValue]));
    }
    // The native endpoint must write the style outside the backticks and keep
    // the rendered selection instead of exposing literal Markdown markers.
    XCTAssertTrue([NSApp sendAction:@selector(toggleStrong:) to:self.document from:nil]);
    [self waitForFormatting];
    XCTAssertTrue([self.editor.string containsString:@"# `Inline`"]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Inline");
    XCTAssertTrue([NSApp sendAction:@selector(toggleStrong:) to:self.document from:nil]);
    [self waitForFormatting];
    XCTAssertTrue([self.editor.string containsString:@"# **`Inline`**"]);
    [self selectFromText:@"Literal" throughText:@"Literal"];
    [self assertMenuScope:@"block" value:@"code-block" active:YES];
    [self assertMenuScope:@"container" value:@"callout-tip" active:YES];
    XCTAssertTrue([[self JS:@"Array.from(document.querySelectorAll('#macdown-preview-format [data-mp-inline],#macdown-preview-format [data-mp-edit-text]')).every(function(b){return b.disabled;})"] boolValue]);
    XCTAssertTrue([[self JS:@"!document.querySelector('[data-mp-format-menu]').disabled && !document.querySelector('[data-mp-option=paragraph]').disabled"] boolValue]);
}

- (void)testRemovingContainerViaItsMenuPreservesTitleBodyHeadingAndInlineStyle
{
    [self loadSource:@"::: {.callout-warning}\n## Title\n# **Heading**\n\nBody\n:::\n\nNeighbor.\n"];
    [self selectFromText:@"Heading" throughText:@"Heading"];
    [self chooseContainer:@"no-container"];
    [self waitUntil:^BOOL{return ![self.editor.string containsString:@":::"];} description:@"Container menu removes callout envelope"];
    [self waitForFormatting];
    XCTAssertTrue([self.editor.string containsString:@"## Title"]);
    XCTAssertTrue([self.editor.string containsString:@"# **Heading**"]);
    XCTAssertTrue([self.editor.string containsString:@"Body"]);
    XCTAssertTrue([self.editor.string hasSuffix:@"\nNeighbor.\n"]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Heading");
    [self assertMenuScope:@"block" value:@"h1" active:YES];
    [self assertMenuScope:@"container" value:@"no-container" active:YES];
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"true");
    XCTAssertFalse([[self JS:@"!!document.querySelector('.mp-callout')"] boolValue]);
    XCTAssertEqualObjects([self JS:@"document.querySelector('h1').textContent"],@"Heading");
}

- (void)testRapidQueuedBlockAndInlineFormattingPreservesContainerSelectionAndDisclosure
{
    [self loadSource:@"::: {.callout-note collapse=\"true\"}\n## Title\nBody\n:::\n\nNeighbor.\n"];
    [self JS:@"document.querySelector('details').open=true"];
    [self selectFromText:@"Body" throughText:@"Body"];
    // Invoke the actual quick-toolbar actions without yielding to WebKit.
    // The second action must queue against the first action's pending render.
    XCTAssertTrue([NSApp sendAction:@selector(convertToH1:) to:self.document from:nil]);
    XCTAssertNotNil([self.document valueForKey:@"previewSelectionToRestore"]);
    XCTAssertTrue([NSApp sendAction:@selector(toggleStrong:) to:self.document from:nil]);
    XCTAssertEqual([[self.document valueForKey:@"previewQueuedFormatting"] count],1u);
    [self waitForFormatting];
    XCTAssertTrue([self.editor.string containsString:@"::: {.callout-note collapse=\"true\"}"]);
    XCTAssertTrue([self.editor.string containsString:@"## Title"]);
    XCTAssertTrue([self.editor.string containsString:@"# **Body**"]);
    XCTAssertTrue([self.editor.string hasSuffix:@"\nNeighbor.\n"]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Body");
    XCTAssertEqualObjects([self JS:@"String(document.querySelector('details').open)"],@"true");
    [self assertMenuScope:@"block" value:@"h1" active:YES];
    [self assertMenuScope:@"container" value:@"toggle-h2" active:YES];
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"true");
    XCTAssertEqualObjects([self JS:@"document.querySelector('details .mp-callout-body h1 strong').textContent"],@"Body");
}

- (void)chooseTableAlignment:(NSString *)alignment
{
    [self JS:[NSString stringWithFormat:@"document.querySelector('[data-mp-align=%@]').click()",alignment]];
    [self waitForFormatting];
}

- (void)testTableAlignmentRoundTripsEveryColumnAndAlignment
{
    NSArray *alignments=@[@"left",@"center",@"right"];
    NSDictionary *markers=@{@"left":@":---",@"center":@":---:",@"right":@"---:"};
    for (NSString *before in alignments) for (NSString *after in alignments) for (NSUInteger column=0;column<3;column++) {
        // Different dash lengths and a second table prove precise ownership.
        NSString *source=[NSString stringWithFormat:@"| HeadA | HeadB | HeadC |\n| %@ | %@ | %@ |\n| Alpha | Beta | Gamma |\n| Delta | Epsilon | Zeta |\n\n| Other | Neighbor |\n| --- | --- |\n| untouched | text |\n",markers[before],markers[before],markers[before]];
        [self loadSource:source];
        NSString *word=@[@"Alpha",@"Beta",@"Gamma"][column];
        [self selectFromText:word throughText:word];
        XCTAssertEqualObjects([self JS:@"String(document.querySelector('[data-mp-table-alignment]').hidden)"],@"false");
        if ([before isEqual:after]) {
            [self JS:[NSString stringWithFormat:@"document.querySelector('[data-mp-align=%@]').click()",after]];
        } else [self chooseTableAlignment:after];
        NSMutableArray *expected=[@[markers[before],markers[before],markers[before]] mutableCopy];expected[column]=markers[after];
        NSString *separator=[NSString stringWithFormat:@"| %@ | %@ | %@ |",expected[0],expected[1],expected[2]];
        XCTAssertTrue([self.editor.string containsString:separator],@"%@ to %@ column %lu",before,after,(unsigned long)column);
        XCTAssertTrue([self.editor.string hasSuffix:@"| Other | Neighbor |\n| --- | --- |\n| untouched | text |\n"]);
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],word);
        NSString *check=[NSString stringWithFormat:@"Array.from(document.querySelector('table').rows).every(function(r){return r.cells[%lu].style.textAlign==='%@';})",(unsigned long)column,after];
        XCTAssertTrue([[self JS:check] boolValue]);
        XCTAssertEqualObjects(([self JS:[NSString stringWithFormat:@"document.querySelector('[data-mp-align=%@]').getAttribute('aria-pressed')",after]]),@"true");
    }
}

- (void)testTableAlignmentPreservesStyledPartialHeaderAndAllowsSuccessiveActions
{
    [self loadSource:@"| **First heading** | Second |\n| --- | --- |\n| Value | Other |\n"];
    [self selectFromText:@"heading" throughText:@"heading"];
    [self chooseTableAlignment:@"center"];
    XCTAssertEqualObjects(self.editor.string,@"| **First heading** | Second |\n| :---: | --- |\n| Value | Other |\n");
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"heading");
    XCTAssertEqualObjects([self JS:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"true");
    [self chooseTableAlignment:@"right"];
    XCTAssertTrue([self.editor.string containsString:@"| ---: | --- |"]);
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"heading");
    XCTAssertEqualObjects([self JS:@"getComputedStyle(document.querySelector('[data-mp-align=right]')).color"],@"rgb(39, 132, 222)");
}

- (void)testTableAlignmentSupportsContainersOptionalPipesAndCRLF
{
    NSArray *fixtures=@[
        @"First | Second\n------ | ------\nNeedle | Other\n",
        @"> | First | Second |\n> | --- | --- |\n> | Needle | Other |\n",
        @"::: {.callout-note}\n\n| First | Second |\n| --- | --- |\n| Needle | Other |\n\n:::\n",
        @"| First | Second |\r\n| --- | --- |\r\n| Needle | Other |\r\n",
        @"| First | Second |\n| --- | --- |\n| Needle **styled** `code` | Other |\n"];
    for (NSString *source in fixtures) {
        [self loadSource:source];
        [self selectFromText:@"Needle" throughText:@"Needle"];
        [self chooseTableAlignment:@"center"];
        XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Needle");
        XCTAssertTrue([[self JS:@"Array.from(document.querySelector('table').rows).every(function(r){return r.cells[0].style.textAlign==='center' && !r.cells[1].style.textAlign;})"] boolValue]);
        if ([source containsString:@"\r\n"]) XCTAssertTrue([self.editor.string containsString:@"| :---: | --- |\r\n"]);
        if ([source containsString:@"------"]) XCTAssertTrue([self.editor.string containsString:@":------: | ------"]);
    }
}

- (void)testTableAlignmentAppearsOnlyForTableSelections
{
    [self loadSource:@"Prose.\n\n| First | Second |\n| --- | --- |\n| Needle | Other |\n"];
    [self selectFromText:@"Prose" throughText:@"Prose"];
    XCTAssertEqualObjects([self JS:@"String(document.querySelector('[data-mp-table-alignment]').hidden)"],@"true");
    [self selectFromText:@"Needle" throughText:@"Needle"];
    XCTAssertEqualObjects([self JS:@"String(document.querySelector('[data-mp-table-alignment]').hidden)"],@"false");
    [self selectFromText:@"Prose" throughText:@"Prose"];
    XCTAssertEqualObjects([self JS:@"String(document.querySelector('[data-mp-table-alignment]').hidden)"],@"true");
}

- (void)testTableAlignmentAppliesToAllColumnsTouchedBySelection
{
    [self loadSource:@"| First | Second | Third |\n| --- | --- | --- |\n| Alpha | Beta | Gamma |\n| Delta | Epsilon | Zeta |\n"];
    [self selectFromText:@"Alpha" throughText:@"Beta"];
    [self chooseTableAlignment:@"center"];
    XCTAssertTrue([self.editor.string containsString:@"| :---: | :---: | --- |"]);
    XCTAssertTrue([[self JS:@"Array.from(document.querySelector('table').rows).every(function(r){return r.cells[0].style.textAlign==='center' && r.cells[1].style.textAlign==='center' && !r.cells[2].style.textAlign;})"] boolValue]);
    XCTAssertTrue([[self JS:@"getSelection().toString().includes('Alpha') && getSelection().toString().includes('Beta')"] boolValue]);
}

- (void)testTableAlignmentRejectsInvalidOrNonMarkdownTargets
{
    [self loadSource:@"Prose.\n\n| First | Second |\n| --- | --- |\n| Needle | Other |\n"];
    [self selectFromText:@"Prose" throughText:@"Prose"];
    NSDictionary *prose=[self.web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('table-align','center')"].toDictionary;
    NSString *original=self.editor.string.copy;
    XCTAssertFalse([self.document applyPreviewEditPayload:prose]);
    XCTAssertEqualObjects(self.editor.string,original);
    [self selectFromText:@"Needle" throughText:@"Needle"];
    NSMutableDictionary *payload=[[self.web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('table-align','center')"].toDictionary mutableCopy];
    payload[@"value"]=@"justify";
    XCTAssertFalse([self.document applyPreviewEditPayload:payload]);
    payload[@"value"]=@"center";payload[@"token"]=@"stale";
    XCTAssertFalse([self.document applyPreviewEditPayload:payload]);
    XCTAssertEqualObjects(self.editor.string,original);
    [self loadSource:@"<table><tr><th>Header</th></tr><tr><td>RawCell</td></tr></table>\n\n| Another | Table |\n| --- | --- |\n| Safe | Other |\n"];
    [self selectFromText:@"RawCell" throughText:@"RawCell"];
    original=self.editor.string.copy;
    NSDictionary *raw=[self.web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('table-align','center')"].toDictionary;
    XCTAssertFalse([self.document applyPreviewEditPayload:raw]);
    XCTAssertEqualObjects(self.editor.string,original);
}

- (void)testTableAlignmentUsesProvenColumnAndQueuesRapidChanges
{
    [self loadSource:@"| First | Second |\n| --- | --- |\n| Needle | Other |\n"];
    [self selectFromText:@"Needle" throughText:@"Needle"];
    NSMutableDictionary *payload=[[self.web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('table-align','center')"].toDictionary mutableCopy];
    // A page-provided column must never override ownership of the selected leaf.
    payload[@"column"]=@1;
    XCTAssertTrue([self.document applyPreviewEditPayload:payload]);
    [self JS:@"document.querySelector('[data-mp-align=right]').click()"];
    [self waitForFormatting];
    XCTAssertEqualObjects(self.editor.string,@"| First | Second |\n| ---: | --- |\n| Needle | Other |\n");
    XCTAssertEqualObjects([self JS:@"getSelection().toString()"],@"Needle");
}

- (void)testTableAlignmentRetainsMixedInlineRunsAndEscapedPipes
{
    NSString *source=@"| Heading | Other |\n| --- | --- |\n| **Bold** plain *italic* `code` escaped\\|pipe | Neighbor |\n";
    [self loadSource:source];
    [self selectFromText:@"Bold" throughText:@"code"];
    [self chooseTableAlignment:@"center"];
    XCTAssertEqualObjects(self.editor.string,[source stringByReplacingOccurrencesOfString:@"| --- | --- |" withString:@"| :---: | --- |"]);
    XCTAssertTrue([[self JS:@"getSelection().toString().includes('Bold') && getSelection().toString().includes('code')"] boolValue]);
    XCTAssertTrue([[self JS:@"!!document.querySelector('td strong') && !!document.querySelector('td em') && !!document.querySelector('td code')"] boolValue]);
}

- (void)testTableAlignmentAcrossRowsRetainsSelectionAndDisclosure
{
    [self loadSource:@"::: {.callout-note collapse=\"true\"}\n## Title\n\n| First | Second |\n| --- | --- |\n| Alpha | Beta |\n| Delta | Epsilon |\n\n:::\n"];
    [self JS:@"document.querySelector('details').open=true"];
    [self selectFromText:@"Alpha" throughText:@"Epsilon"];
    [self chooseTableAlignment:@"right"];
    XCTAssertTrue([self.editor.string containsString:@"| ---: | ---: |"]);
    XCTAssertEqualObjects([self JS:@"String(document.querySelector('details').open)"],@"true");
    XCTAssertTrue([[self JS:@"getSelection().toString().includes('Alpha') && getSelection().toString().includes('Epsilon')"] boolValue]);
}

@end
