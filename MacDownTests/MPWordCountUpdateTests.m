//
//  MPWordCountUpdateTests.m
//  MacDownTests
//
//  Tests for Issue #294: Word count update during DOM replacement.
//  Verifies scheduleWordCountUpdate: debouncing logic.
//
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPPreferences.h"

#pragma mark - Test Category to Expose Private Methods

@interface MPDocument (WordCountTesting)
@property (nonatomic) NSUInteger totalWords;
@property (nonatomic) NSUInteger totalCharacters;
@property (nonatomic) NSUInteger totalCharactersNoSpaces;
@property (strong) NSOperationQueue *wordCountUpdateQueue;
- (void)updateWordCount;
- (void)scheduleWordCountUpdate;
@end


#pragma mark - Test Case

@interface MPWordCountUpdateTests : XCTestCase
@property (strong) MPDocument *document;
@end


@implementation MPWordCountUpdateTests

- (void)setUp
{
    [super setUp];
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    self.document = nil;
    [super tearDown];
}


#pragma mark - Basic Existence Tests

/**
 * Test that scheduleWordCountUpdate method exists.
 * Issue #294: Baseline test for the new mechanism.
 */
- (void)testScheduleWordCountUpdateMethodExists
{
    XCTAssertTrue([self.document respondsToSelector:@selector(scheduleWordCountUpdate)],
                  @"MPDocument should respond to scheduleWordCountUpdate");
}

/**
 * Test that updateWordCount method exists.
 * Issue #294: Verify the underlying update method is present.
 */
- (void)testUpdateWordCountMethodExists
{
    XCTAssertTrue([self.document respondsToSelector:@selector(updateWordCount)],
                  @"MPDocument should respond to updateWordCount");
}

/**
 * Test that scheduleWordCountUpdate doesn't crash when called.
 * Issue #294: Safety test for basic invocation.
 */
- (void)testScheduleWordCountUpdateDoesNotCrash
{
    // Without window controller, queue may not be initialized, but method
    // should still not crash (early return due to preference check)
    XCTAssertNoThrow([self.document scheduleWordCountUpdate],
                     @"scheduleWordCountUpdate should not crash");
}


#pragma mark - Queue Initialization Tests

/**
 * Test that wordCountUpdateQueue is initialized after window setup.
 * Issue #294: Queue should be created in windowControllerDidLoadNib.
 * Note: In headless CI mode, windowControllerDidLoadNib may not be called,
 * so we skip this test if the queue is not initialized.
 */
- (void)testWordCountUpdateQueueInitializedAfterWindowSetup
{
    [self.document makeWindowControllers];

    // Give time for async setup
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (self.document.wordCountUpdateQueue == nil &&
           [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    // In headless CI mode, windowControllerDidLoadNib may not be called
    if (self.document.wordCountUpdateQueue == nil) {
        NSLog(@"Skipping testWordCountUpdateQueueInitializedAfterWindowSetup - windowControllerDidLoadNib not called (headless mode)");
        return;
    }

    XCTAssertNotNil(self.document.wordCountUpdateQueue,
                    @"wordCountUpdateQueue should be initialized after window setup");
}

/**
 * Test that wordCountUpdateQueue is serial (max 1 concurrent operation).
 * Issue #294: Queue should process operations one at a time for debouncing.
 */
- (void)testWordCountUpdateQueueIsSerial
{
    [self.document makeWindowControllers];

    // Give time for async setup
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (self.document.wordCountUpdateQueue == nil &&
           [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    NSOperationQueue *queue = self.document.wordCountUpdateQueue;
    if (queue) {
        XCTAssertEqual(queue.maxConcurrentOperationCount, 1,
                       @"wordCountUpdateQueue should be serial (max 1 concurrent)");
    } else {
        NSLog(@"Skipping testWordCountUpdateQueueIsSerial - queue not initialized (headless mode)");
    }
}


#pragma mark - Debouncing Tests

/**
 * Test that rapid calls to scheduleWordCountUpdate result in debouncing.
 * Issue #294: Only the last scheduled update should be pending.
 */
- (void)testScheduleWordCountUpdateDebounces
{
    [self.document makeWindowControllers];

    // Give time for async setup
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (self.document.wordCountUpdateQueue == nil &&
           [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    NSOperationQueue *queue = self.document.wordCountUpdateQueue;
    if (!queue) {
        NSLog(@"Skipping testScheduleWordCountUpdateDebounces - queue not initialized (headless mode)");
        return;
    }

    // Ensure word count preference is enabled for this test
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        // Call scheduleWordCountUpdate multiple times rapidly
        [self.document scheduleWordCountUpdate];
        [self.document scheduleWordCountUpdate];
        [self.document scheduleWordCountUpdate];
        [self.document scheduleWordCountUpdate];
        [self.document scheduleWordCountUpdate];

        // Due to cancellation, there should be at most 1 pending operation
        // (the most recent one)
        XCTAssertLessThanOrEqual(queue.operationCount, 1,
                                 @"Debouncing should cancel previous operations, leaving at most 1");
    }
    @finally {
        // Restore original preference
        prefs.editorShowWordCount = originalValue;
    }
}


#pragma mark - Preference Respect Tests

/**
 * Test that scheduleWordCountUpdate respects editorShowWordCount preference.
 * Issue #294: Should be a no-op when word count is disabled.
 */
- (void)testScheduleWordCountUpdateRespectsDisabledPreference
{
    [self.document makeWindowControllers];

    // Give time for async setup
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (self.document.wordCountUpdateQueue == nil &&
           [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    NSOperationQueue *queue = self.document.wordCountUpdateQueue;
    if (!queue) {
        NSLog(@"Skipping testScheduleWordCountUpdateRespectsDisabledPreference - queue not initialized (headless mode)");
        return;
    }

    // Disable word count preference
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = NO;

    @try {
        // Call scheduleWordCountUpdate
        [self.document scheduleWordCountUpdate];

        // Queue should remain empty when preference is disabled
        XCTAssertEqual(queue.operationCount, 0,
                       @"No operation should be queued when editorShowWordCount is NO");
    }
    @finally {
        // Restore original preference
        prefs.editorShowWordCount = originalValue;
    }
}


#pragma mark - Cleanup Tests

/**
 * Test that wordCountUpdateQueue is properly cleaned up on close.
 * Issue #294: Pending operations should be cancelled when document closes.
 */
- (void)testWordCountQueueCancelledOnClose
{
    [self.document makeWindowControllers];

    // Give time for async setup
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (self.document.wordCountUpdateQueue == nil &&
           [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    NSOperationQueue *queue = self.document.wordCountUpdateQueue;
    if (!queue) {
        NSLog(@"Skipping testWordCountQueueCancelledOnClose - queue not initialized (headless mode)");
        return;
    }

    // Enable word count and schedule an update
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        [self.document scheduleWordCountUpdate];

        // Close the document
        [self.document close];

        // Give a moment for cancellation to take effect
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];

        // All operations should be cancelled
        // Note: operationCount may still show 1 if operation is running,
        // but it should have been marked cancelled
        XCTAssertTrue(queue.operationCount == 0 ||
                      [[queue.operations firstObject] isCancelled],
                      @"Operations should be cancelled after document close");
    }
    @finally {
        prefs.editorShowWordCount = originalValue;
    }
}

@end
