//
//  MPRenderDeferralTests.m
//  MacDownTests
//
//  Tests for Issue #16: Render deferral mechanism for export/print operations
//  when preview pane is hidden. Verifies performAfterRender: queueing logic.
//
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>
#import "MPDocument.h"
#import "MPDocumentWindowTestSupport.h"
#import "MPPreferences.h"

#pragma mark - Test Category to Expose Private Methods

@interface MPDocument (RenderDeferralTesting)
@property (nonatomic, strong) NSMutableArray *renderCompletionHandlers;
@property (nonatomic, readonly) BOOL needsHtml;
@property (nonatomic) BOOL isPreviewReady;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (weak) WebView *preview;
@property (unsafe_unretained) NSTextView *editor;
- (void)performAfterRender:(void (^)(void))handler;
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource;
// IBActions used in tests
- (IBAction)togglePreviewPane:(id)sender;
- (IBAction)render:(id)sender;
- (IBAction)copyHtml:(id)sender;
- (IBAction)exportHtml:(id)sender;
- (IBAction)exportPdf:(id)sender;
@end


#pragma mark - Test Document

// Keeps the preview off the network. The page's MathJax script comes from the
// app bundle, and MathJax then asks its CDN for everything else; those
// requests are sent to a file that does not exist. With mathJaxMissing set the
// bundled script is refused as well, so the page has no MathJax object.
@interface MPRenderDeferralTestDocument : MPDocument
@property BOOL mathJaxMissing;
@end

@implementation MPRenderDeferralTestDocument

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource
{
    request = [super webView:sender resource:identifier
             willSendRequest:request redirectResponse:redirectResponse
              fromDataSource:dataSource];
    NSURL *url = request.URL;
    BOOL isMathJax = [url.lastPathComponent isEqualToString:@"MathJax.js"];
    if ([url.scheme hasPrefix:@"http"] || (self.mathJaxMissing && isMathJax))
    {
        NSURL *missing =
            [NSURL fileURLWithPath:@"/var/empty/MPRenderDeferralTests.js"];
        return [NSURLRequest requestWithURL:missing];
    }
    return request;
}

@end


#pragma mark - Test Case

@interface MPRenderDeferralTests : XCTestCase
@property (strong) MPDocument *document;
@property (assign) BOOL handlerWasInvoked;
@property (assign) NSInteger handlerInvocationCount;
@property (strong) NSMutableArray *handlerInvocationOrder;
@property BOOL originalManualRender;
@property BOOL originalShowWordCount;
@property BOOL originalStartInPreviewMode;
@property BOOL originalMathJax;
@property (copy) NSString *pageStateAtHandler;
@end


@implementation MPRenderDeferralTests

- (void)setUp
{
    [super setUp];
    // needsHtml = !manualRender && (previewVisible || showWordCount); pin the
    // preferences so it tracks preview visibility only.
    MPPreferences *preferences = [MPPreferences sharedInstance];
    self.originalManualRender = preferences.markdownManualRender;
    self.originalShowWordCount = preferences.editorShowWordCount;
    self.originalStartInPreviewMode = preferences.editorStartInPreviewMode;
    preferences.markdownManualRender = NO;
    preferences.editorShowWordCount = NO;
    preferences.editorStartInPreviewMode = NO;
    self.originalMathJax = preferences.htmlMathJax;
    preferences.htmlMathJax = NO;
    self.document = [[MPDocument alloc] init];
    self.handlerWasInvoked = NO;
    self.handlerInvocationCount = 0;
    self.handlerInvocationOrder = [NSMutableArray array];
}

- (void)tearDown
{
    self.document = nil;
    self.handlerInvocationOrder = nil;
    MPPreferences *preferences = [MPPreferences sharedInstance];
    preferences.markdownManualRender = self.originalManualRender;
    preferences.editorShowWordCount = self.originalShowWordCount;
    preferences.editorStartInPreviewMode = self.originalStartInPreviewMode;
    preferences.htmlMathJax = self.originalMathJax;
    [super tearDown];
}


#pragma mark - Helper Methods

- (void (^)(void))testHandlerBlock
{
    __weak MPRenderDeferralTests *weakSelf = self;
    return ^{
        weakSelf.handlerWasInvoked = YES;
        weakSelf.handlerInvocationCount++;
    };
}

- (void (^)(void))testHandlerBlockWithIdentifier:(NSInteger)identifier
{
    __weak MPRenderDeferralTests *weakSelf = self;
    return ^{
        [weakSelf.handlerInvocationOrder addObject:@(identifier)];
    };
}


#pragma mark - Basic Existence Tests

/**
 * Test that performAfterRender: method exists and is callable.
 * Issue #16: Baseline test for the new mechanism.
 */
- (void)testPerformAfterRenderMethodExists
{
    XCTAssertTrue([self.document respondsToSelector:@selector(performAfterRender:)],
                  @"MPDocument should respond to performAfterRender:");
}

/**
 * Test that performAfterRender: doesn't crash with empty block.
 * Issue #16: Safety test.
 */
- (void)testPerformAfterRenderDoesNotCrashWithEmptyBlock
{
    XCTAssertNoThrow([self.document performAfterRender:^{}],
                     @"performAfterRender: with empty block should not crash");
}

/**
 * Test that performAfterRender: handles nil gracefully.
 * Issue #16: Safety test for nil input.
 */
- (void)testPerformAfterRenderHandlesNilBlock
{
    XCTAssertNoThrow([self.document performAfterRender:nil],
                     @"performAfterRender: with nil should not crash");
}

/**
 * Test that renderCompletionHandlers property exists.
 * Issue #16: Property existence test.
 */
- (void)testRenderCompletionHandlersPropertyExists
{
    XCTAssertNoThrow((void)self.document.renderCompletionHandlers,
                     @"renderCompletionHandlers property should be accessible");
}


#pragma mark - Immediate Execution Tests (When Preview Visible)

/**
 * Test that handler executes immediately when preview is visible.
 * Issue #16: Core behavior - no deferral when needsHtml is YES.
 */
- (void)testPerformAfterRenderExecutesImmediatelyWhenPreviewVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");
    XCTAssertTrue(self.document.needsHtml,
                  @"needsHtml should be YES while the preview is visible");

    [self.document performAfterRender:[self testHandlerBlock]];

    XCTAssertTrue(self.handlerWasInvoked,
                  @"Handler should execute immediately when needsHtml is YES");
    XCTAssertEqual(self.handlerInvocationCount, 1,
                   @"Handler should be invoked exactly once");
}

/**
 * Test that handler is NOT queued when executed immediately.
 * Issue #16: When preview visible, handlers bypass the queue.
 */
- (void)testNoQueueingWhenPreviewVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");
    XCTAssertTrue(self.document.needsHtml,
                  @"needsHtml should be YES while the preview is visible");

    [self.document performAfterRender:[self testHandlerBlock]];

    // Queue should remain empty after immediate execution
    NSArray *handlers = self.document.renderCompletionHandlers;
    XCTAssertTrue(handlers == nil || handlers.count == 0,
                  @"Handler queue should be empty after immediate execution");
}


#pragma mark - Deferred Execution Tests (When Preview Hidden)

/**
 * Test that handler is queued when preview is hidden.
 * Issue #16: Core behavior - deferral when needsHtml is NO.
 */
- (void)testPerformAfterRenderQueuesHandlerWhenPreviewHidden
{
    // In headless mode without window controller, needsHtml should be NO
    // because preview frame width is 0
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO without window controller");

    [self.document performAfterRender:[self testHandlerBlock]];

    // Handler should NOT have executed yet
    XCTAssertFalse(self.handlerWasInvoked,
                   @"Handler should not execute immediately when preview is hidden");

    // Handler should be queued
    NSArray *handlers = self.document.renderCompletionHandlers;
    XCTAssertNotNil(handlers, @"Handler queue should exist");
    XCTAssertEqual(handlers.count, 1,
                   @"One handler should be queued");
}

/**
 * Test that multiple handlers are queued in order.
 * Issue #16: FIFO ordering for multiple operations.
 */
- (void)testMultipleHandlersAreQueuedInOrder
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO for this test");

    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:1]];
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:2]];
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:3]];

    NSArray *handlers = self.document.renderCompletionHandlers;
    XCTAssertEqual(handlers.count, 3,
                   @"Three handlers should be queued");
}


#pragma mark - Handler Invocation Tests

/**
 * Test that queued handlers are all invoked when render completes.
 * Issue #16: All queued handlers must execute.
 *
 * Loads the document window, hides the preview so handlers queue, then shows
 * the preview again and waits for the render to complete them.
 */
- (void)testAllQueuedHandlersAreInvoked
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide preview
    [self.document togglePreviewPane:nil];
    XCTAssertFalse(self.document.needsHtml,
                   @"Hiding the preview should make needsHtml NO");

    // Queue multiple handlers
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:1]];
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:2]];

    // Show the preview again, which triggers a render
    [self.document togglePreviewPane:nil];

    MPRunLoopUntil(10.0, ^BOOL{
        return self.handlerInvocationOrder.count == 2;
    });

    // Both handlers should have been invoked
    XCTAssertEqual(self.handlerInvocationOrder.count, 2,
                   @"Both handlers should have been invoked");
}

/**
 * Test that handlers execute in FIFO order.
 * Issue #16: Order preservation for queued operations.
 */
- (void)testHandlersExecuteInFIFOOrder
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO for this test");

    // Queue handlers
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:1]];
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:2]];
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:3]];

    // Manually invoke handlers to simulate render completion
    NSArray *handlers = [self.document.renderCompletionHandlers copy];
    [self.document.renderCompletionHandlers removeAllObjects];

    for (void (^handler)(void) in handlers) {
        handler();
    }

    // Verify FIFO order
    XCTAssertEqual(self.handlerInvocationOrder.count, 3,
                   @"Three handlers should have been invoked");
    XCTAssertEqualObjects(self.handlerInvocationOrder[0], @1, @"First handler should execute first");
    XCTAssertEqualObjects(self.handlerInvocationOrder[1], @2, @"Second handler should execute second");
    XCTAssertEqualObjects(self.handlerInvocationOrder[2], @3, @"Third handler should execute third");
}

/**
 * Test that handler queue is cleared after invocation.
 * Issue #16: Prevent duplicate invocations.
 */
- (void)testHandlerQueueClearedAfterInvocation
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO for this test");

    [self.document performAfterRender:[self testHandlerBlock]];

    // Simulate clearing the queue after invocation
    NSArray *handlers = [self.document.renderCompletionHandlers copy];
    [self.document.renderCompletionHandlers removeAllObjects];

    for (void (^handler)(void) in handlers) {
        handler();
    }

    XCTAssertEqual(self.document.renderCompletionHandlers.count, 0,
                   @"Handler queue should be empty after invocation");
}


#pragma mark - Edge Case Tests

/**
 * Test rapid successive calls queue all handlers.
 * Issue #16: Stress test for rapid operations.
 */
- (void)testRapidSuccessiveCallsQueueAllHandlers
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO for this test");

    // Rapidly queue 10 handlers
    for (NSInteger i = 1; i <= 10; i++) {
        [self.document performAfterRender:[self testHandlerBlockWithIdentifier:i]];
    }

    XCTAssertEqual(self.document.renderCompletionHandlers.count, 10,
                   @"All 10 handlers should be queued");
}

/**
 * Test that subsequent operations after completion work correctly.
 * Issue #16: Verify mechanism resets properly.
 */
- (void)testSubsequentOperationsAfterCompletionWork
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO for this test");

    // First batch
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:1]];

    // Simulate completion
    NSArray *handlers1 = [self.document.renderCompletionHandlers copy];
    [self.document.renderCompletionHandlers removeAllObjects];
    for (void (^handler)(void) in handlers1) {
        handler();
    }

    // Second batch
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:2]];

    XCTAssertEqual(self.document.renderCompletionHandlers.count, 1,
                   @"Second handler should be queued");

    // Simulate completion
    NSArray *handlers2 = [self.document.renderCompletionHandlers copy];
    [self.document.renderCompletionHandlers removeAllObjects];
    for (void (^handler)(void) in handlers2) {
        handler();
    }

    // Verify both batches executed
    XCTAssertEqual(self.handlerInvocationOrder.count, 2,
                   @"Both handlers should have been invoked");
    XCTAssertEqualObjects(self.handlerInvocationOrder[0], @1, @"First batch handler");
    XCTAssertEqualObjects(self.handlerInvocationOrder[1], @2, @"Second batch handler");
}


#pragma mark - Integration Tests (With Window Controller)

/**
 * Test that operations don't crash with window controller.
 * Issue #16: Integration safety test.
 */
- (void)testPerformAfterRenderWithWindowController
{
    [self.document makeWindowControllers];

    XCTAssertNoThrow([self.document performAfterRender:[self testHandlerBlock]],
                     @"performAfterRender: should not crash with window controller");
}

/**
 * Test copyHtml: triggers render deferral when preview hidden.
 * Issue #16: Verify copyHtml uses the mechanism.
 */
- (void)testCopyHtmlUsesDeferralMechanism
{
    // Without window controller, preview is hidden (needsHtml = NO)
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO without window controller");

    // Call copyHtml - should trigger render
    XCTAssertNoThrow([self.document copyHtml:nil],
                     @"copyHtml: should not crash");

    // In the new implementation, this should queue a handler
    // (Test will fail until implementation is complete)
}

/**
 * Test exportHtml: triggers render deferral when preview hidden.
 * Issue #16: Verify exportHtml uses the mechanism.
 */
- (void)testExportHtmlUsesDeferralMechanism
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO without window controller");

    // exportHtml: opens a save panel, so just verify it doesn't crash
    // Full testing requires mocking NSSavePanel
    XCTAssertNoThrow([self.document exportHtml:nil],
                     @"exportHtml: should not crash");
}

/**
 * Test exportPdf: triggers render deferral when preview hidden.
 * Issue #16: Verify exportPdf uses the mechanism.
 */
- (void)testExportPdfUsesDeferralMechanism
{
    XCTAssertFalse(self.document.needsHtml,
                   @"needsHtml should be NO without window controller");

    // exportPdf: opens a save panel, so just verify it doesn't crash
    XCTAssertNoThrow([self.document exportPdf:nil],
                     @"exportPdf: should not crash");
}

#pragma mark - Handlers Queued After The Preview Has Loaded

- (NSString *)previewStringFromScript:(NSString *)script
{
    JSContext *context = self.document.preview.mainFrame.javaScriptContext;
    return [[context evaluateScript:script] toString];
}

- (void)drainMainQueue
{
    __block BOOL drained = NO;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        drained = YES;
    }];
    MPRunLoopUntil(5.0, ^BOOL{
        return drained;
    });
}

/// Waits until the preview shows `text` with no load or MathJax startup still
/// going on, and whatever the load left on the main queue has run.
- (BOOL)waitForPreviewShowing:(NSString *)text
{
    NSString *script = [NSString stringWithFormat:
        @"(function(){"
        @"  if(!document.body||document.body.innerHTML.indexOf('%@')<0)"
        @"    return 'no';"
        @"  if(!window.MathJax||!MathJax.Hub)"
        @"    return 'yes';"
        @"  var posted = MathJax.Hub.Startup.signal.posted;"
        @"  return posted.indexOf('End')<0 ? 'no' : 'yes';"
        @"})()", text];
    BOOL shown = MPRunLoopUntil(10.0, ^BOOL{
        return self.document.isPreviewReady
            && !self.document.alreadyRenderingInWeb
            && !self.document.preview.loading
            && [[self previewStringFromScript:script] isEqualToString:@"yes"];
    });
    [self drainMainQueue];
    return shown;
}

/// Loads a window for a document that stays off the network and waits for its
/// first preview load. Returns NO if no window can be loaded here.
- (BOOL)loadWindowShowing:(NSString *)text mathJaxMissing:(BOOL)missing
{
    MPRenderDeferralTestDocument *document =
        [[MPRenderDeferralTestDocument alloc] init];
    document.mathJaxMissing = missing;
    self.document = document;
    if (!MPLoadDocumentWindow(document))
        return NO;
    document.editor.string = text;
    XCTAssertTrue([self waitForPreviewShowing:text],
                  @"the first preview load should show the editor's text");
    return YES;
}

/// An ordinary render, with no handler waiting, replaces the page's body and
/// keeps the page. A property set on its window tells the two apart.
- (void)assertRenderUpdatesInPlaceShowing:(NSString *)text
{
    [self previewStringFromScript:@"window.__renderDeferralPage = 'kept'"];
    self.document.editor.string = text;
    [self.document render:nil];
    XCTAssertTrue([self waitForPreviewShowing:text],
                  @"an ordinary render should show the new text");
    XCTAssertEqualObjects(
        [self previewStringFromScript:@"String(window.__renderDeferralPage)"],
        @"kept", @"an ordinary render should update the page in place");
}

/// Queues a handler that records what `script` returns in the preview at the
/// moment it runs, and waits for it. Returns whether the handler ran.
- (BOOL)performAfterRenderRecording:(NSString *)script
{
    __weak MPRenderDeferralTests *weakSelf = self;
    [self.document performAfterRender:^{
        weakSelf.pageStateAtHandler =
            [weakSelf previewStringFromScript:script];
        weakSelf.handlerInvocationCount++;
    }];
    return MPRunLoopUntil(10.0, ^BOOL{
        return self.handlerInvocationCount > 0;
    });
}

- (void)hidePreview
{
    [self.document togglePreviewPane:nil];
    XCTAssertFalse(self.document.needsHtml,
                   @"Hiding the preview should make needsHtml NO");
}

/**
 * Print, Export and Copy HTML with the preview pane hidden: the handler runs
 * once the preview shows the current text.
 */
- (void)testQueuedHandlerRunsWithPreviewHidden
{
    XCTSkipUnless([self loadWindowShowing:@"first" mathJaxMissing:NO],
                  @"no document window can be loaded here");
    [self assertRenderUpdatesInPlaceShowing:@"second"];

    [self hidePreview];
    self.document.editor.string = @"third";
    BOOL ran = [self performAfterRenderRecording:@"document.body.innerHTML"];

    XCTAssertTrue(ran, @"the handler should run when the render finishes");
    XCTAssertEqual(self.handlerInvocationCount, 1);
    XCTAssertTrue([self.pageStateAtHandler containsString:@"third"],
                  @"the preview should show the current text by then");

    // With nothing waiting any more, renders update the page in place again.
    XCTAssertTrue([self waitForPreviewShowing:@"third"]);
    [self assertRenderUpdatesInPlaceShowing:@"fourth"];
}

/**
 * The same with Manual Render on and the preview visible.
 */
- (void)testQueuedHandlerRunsWithManualRender
{
    XCTSkipUnless([self loadWindowShowing:@"first" mathJaxMissing:NO],
                  @"no document window can be loaded here");
    [self assertRenderUpdatesInPlaceShowing:@"second"];

    [MPPreferences sharedInstance].markdownManualRender = YES;
    [self drainMainQueue];
    XCTAssertTrue(self.document.previewVisible);
    XCTAssertFalse(self.document.needsHtml,
                   @"Manual Render should make needsHtml NO");
    self.document.editor.string = @"third";
    BOOL ran = [self performAfterRenderRecording:@"document.body.innerHTML"];

    XCTAssertTrue(ran, @"the handler should run when the render finishes");
    XCTAssertEqual(self.handlerInvocationCount, 1);
    XCTAssertTrue([self.pageStateAtHandler containsString:@"third"],
                  @"the preview should show the current text by then");
}

/**
 * Print and Export PDF print the preview, so an image added since the last
 * render has to be loaded when the handler runs.
 */
- (void)testQueuedHandlerRunsAfterImagesLoad
{
    XCTSkipUnless([self loadWindowShowing:@"first" mathJaxMissing:NO],
                  @"no document window can be loaded here");
    [self assertRenderUpdatesInPlaceShowing:@"second"];

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0
                    bitsPerPixel:0];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG
                                       properties:@{}];
    [self hidePreview];
    self.document.editor.string = [NSString stringWithFormat:
        @"third ![](data:image/png;base64,%@)",
        [png base64EncodedStringWithOptions:0]];
    BOOL ran = [self performAfterRenderRecording:
        @"(function(){"
        @"  var image = document.querySelector('img');"
        @"  if(!image) return 'no image';"
        @"  return image.complete + ' ' + image.naturalWidth;"
        @"})()"];

    XCTAssertTrue(ran, @"the handler should run when the render finishes");
    XCTAssertEqualObjects(self.pageStateAtHandler, @"true 40",
                          @"the new image should be loaded by then");
}

/**
 * With MathJax on, the handler waits until MathJax has finished with the page.
 */
- (void)testQueuedHandlerWaitsForMathJax
{
    [MPPreferences sharedInstance].htmlMathJax = YES;
    XCTSkipUnless([self loadWindowShowing:@"first" mathJaxMissing:NO],
                  @"no document window can be loaded here");
    XCTAssertEqualObjects(
        [self previewStringFromScript:@"String(!!window.MathJax)"], @"true",
        @"the page should have loaded the bundled MathJax");
    [self assertRenderUpdatesInPlaceShowing:@"second"];

    [self hidePreview];
    self.document.editor.string = @"third";
    BOOL ran = [self performAfterRenderRecording:
        @"(function(){"
        @"  var text = document.body.innerHTML.indexOf('third') >= 0;"
        @"  var posted = MathJax.Hub.Startup.signal.posted;"
        @"  return 'text ' + text + ', MathJax done ' +"
        @"      (posted.indexOf('End') >= 0);"
        @"})()"];

    XCTAssertTrue(ran, @"the handler should run when the render finishes");
    XCTAssertEqual(self.handlerInvocationCount, 1);
    XCTAssertEqualObjects(self.pageStateAtHandler,
                          @"text true, MathJax done true");
}

/**
 * With MathJax on but not in the page, there is nothing to wait for.
 */
- (void)testQueuedHandlerRunsWhenMathJaxIsMissing
{
    [MPPreferences sharedInstance].htmlMathJax = YES;
    XCTSkipUnless([self loadWindowShowing:@"first" mathJaxMissing:YES],
                  @"no document window can be loaded here");
    XCTAssertEqualObjects(
        [self previewStringFromScript:@"String(!!window.MathJax)"], @"false",
        @"the page should have no MathJax");
    [self assertRenderUpdatesInPlaceShowing:@"second"];

    [self hidePreview];
    self.document.editor.string = @"third";
    BOOL ran = [self performAfterRenderRecording:@"document.body.innerHTML"];

    XCTAssertTrue(ran, @"the handler should run when the render finishes");
    XCTAssertEqual(self.handlerInvocationCount, 1);
    XCTAssertTrue([self.pageStateAtHandler containsString:@"third"],
                  @"the preview should show the current text by then");

    XCTAssertTrue([self waitForPreviewShowing:@"third"]);
    [self assertRenderUpdatesInPlaceShowing:@"fourth"];
}

/**
 * A subframe finishes loading before the page around it has, so it must not
 * run the handlers. The main frame finishing does.
 */
- (void)testSubframeLoadDoesNotRunQueuedHandlers
{
    XCTSkipUnless([self loadWindowShowing:@"first" mathJaxMissing:NO],
                  @"no document window can be loaded here");
    self.document.editor.string =
        @"second\n\n<iframe src=\"about:blank\"></iframe>";
    [self.document render:nil];
    XCTAssertTrue([self waitForPreviewShowing:@"second"]);
    WebView *preview = self.document.preview;
    WebFrame *subframe = preview.mainFrame.childFrames.firstObject;
    XCTAssertNotNil(subframe, @"the page should have a subframe");

    self.document.renderCompletionHandlers =
        [NSMutableArray arrayWithObject:[self testHandlerBlock]];

    [self.document webView:preview didFinishLoadForFrame:subframe];
    [self drainMainQueue];
    XCTAssertEqual(self.handlerInvocationCount, 0,
                   @"a subframe finishing should not run the handlers");

    [self.document webView:preview didFinishLoadForFrame:preview.mainFrame];
    XCTAssertEqual(self.handlerInvocationCount, 1,
                   @"the main frame finishing should run the handlers");
}

@end
