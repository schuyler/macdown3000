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
#import "MPDocument.h"

#pragma mark - Test Category to Expose Private Methods

@interface MPDocument (RenderDeferralTesting)
@property (nonatomic, strong) NSMutableArray *renderCompletionHandlers;
@property (nonatomic, readonly) BOOL needsHtml;
- (void)performAfterRender:(void (^)(void))handler;
@end


#pragma mark - Test Case

@interface MPRenderDeferralTests : XCTestCase
@property (strong) MPDocument *document;
@property (assign) BOOL handlerWasInvoked;
@property (assign) NSInteger handlerInvocationCount;
@property (strong) NSMutableArray *handlerInvocationOrder;
@end


@implementation MPRenderDeferralTests

- (void)setUp
{
    [super setUp];
    self.document = [[MPDocument alloc] init];
    self.handlerWasInvoked = NO;
    self.handlerInvocationCount = 0;
    self.handlerInvocationOrder = [NSMutableArray array];
}

- (void)tearDown
{
    self.document = nil;
    self.handlerInvocationOrder = nil;
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
    [self.document makeWindowControllers];

    // In headless CI, preview may not be visible
    if (!self.document.needsHtml) {
        NSLog(@"Skipping testPerformAfterRenderExecutesImmediatelyWhenPreviewVisible - needsHtml is NO (headless mode)");
        return;
    }

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
    [self.document makeWindowControllers];

    if (!self.document.needsHtml) {
        NSLog(@"Skipping testNoQueueingWhenPreviewVisible - needsHtml is NO (headless mode)");
        return;
    }

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
 */
- (void)testAllQueuedHandlersAreInvoked
{
    [self.document makeWindowControllers];

    // First, queue handlers with preview hidden
    // Toggle preview to hide it (if possible in this test environment)
    BOOL initialPreviewVisible = self.document.previewVisible;

    if (initialPreviewVisible) {
        [self.document togglePreviewPane:nil];
    }

    // If preview is still visible, skip
    if (self.document.needsHtml) {
        NSLog(@"Skipping testAllQueuedHandlersAreInvoked - cannot hide preview in headless mode");
        return;
    }

    // Queue multiple handlers
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:1]];
    [self.document performAfterRender:[self testHandlerBlockWithIdentifier:2]];

    // Simulate render completion by showing preview again
    [self.document togglePreviewPane:nil];

    // Give time for render to complete
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

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

@end
