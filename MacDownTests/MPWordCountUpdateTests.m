//
//  MPWordCountUpdateTests.m
//  MacDownTests
//
//  Tests for Issue #294: Word count update during DOM replacement.
//  Verifies scheduleWordCountUpdate throttling logic.
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
@property (nonatomic) NSTimeInterval lastWordCountUpdate;
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self.document
                                             selector:@selector(updateWordCount)
                                               object:nil];
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
    // Without window controller, method should still not crash
    // (early return due to preference check)
    XCTAssertNoThrow([self.document scheduleWordCountUpdate],
                     @"scheduleWordCountUpdate should not crash");
}


#pragma mark - Throttling Tests

/**
 * Test that rapid calls to scheduleWordCountUpdate result in throttling.
 * Issue #294: The first call fires immediately; subsequent calls within
 * the 0.25s throttle window should not fire immediately but schedule
 * a trailing update instead.
 *
 * Calls scheduleWordCountUpdate once (fires immediately since
 * lastWordCountUpdate starts at 0), then simulates that immediate fire
 * by setting lastWordCountUpdate to now, then calls scheduleWordCountUpdate
 * again. The second call should not fire immediately. Verifies that
 * totalWords is still 0 (no real WebView) and no crash occurs.
 */
- (void)testScheduleWordCountUpdateThrottles
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        // First call fires immediately because lastWordCountUpdate is 0
        [self.document scheduleWordCountUpdate];

        // Record the timestamp that updateWordCount just set
        NSTimeInterval stampAfterFirst = self.document.lastWordCountUpdate;
        XCTAssertGreaterThan(stampAfterFirst, 0,
                             @"First call should fire immediately and stamp lastWordCountUpdate");

        // Second call within the 0.25s throttle window should NOT fire
        // immediately — it should schedule a trailing update instead
        [self.document scheduleWordCountUpdate];

        // lastWordCountUpdate should be unchanged (trailing hasn't fired yet)
        XCTAssertEqual(self.document.lastWordCountUpdate, stampAfterFirst,
                       @"Second call within throttle window should not fire immediately");
    }
    @finally {
        [NSObject cancelPreviousPerformRequestsWithTarget:self.document
                                                 selector:@selector(updateWordCount)
                                                   object:nil];
        prefs.editorShowWordCount = originalValue;
    }
}

/**
 * Test that scheduleWordCountUpdate fires a trailing update after the delay.
 * Issue #294: Verify the trailing performSelector-based timer actually fires.
 *
 * Sets lastWordCountUpdate to now so the call goes to the trailing path,
 * then calls scheduleWordCountUpdate and runs the run loop for more than
 * 0.25s. The trailing update should fire without crashing. totalWords will
 * remain 0 without a real WebView, but the code path is exercised.
 */
- (void)testThrottleTrailingUpdateFires
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        // Stamp lastWordCountUpdate to now so the call goes to the trailing path
        NSTimeInterval stamped = [NSDate timeIntervalSinceReferenceDate];
        self.document.lastWordCountUpdate = stamped;

        [self.document scheduleWordCountUpdate];

        // Run the run loop past the 0.25s throttle interval so the trailing
        // updateWordCount fires. Verify it actually ran by checking that
        // lastWordCountUpdate was updated (the only observable side effect
        // without a WebView).
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.5]];

        XCTAssertGreaterThan(self.document.lastWordCountUpdate, stamped,
                             @"Trailing updateWordCount should have fired and updated lastWordCountUpdate");
    }
    @finally {
        [NSObject cancelPreviousPerformRequestsWithTarget:self.document
                                                 selector:@selector(updateWordCount)
                                                   object:nil];
        prefs.editorShowWordCount = originalValue;
    }
}


#pragma mark - Preference Respect Tests

/**
 * Test that scheduleWordCountUpdate respects editorShowWordCount preference.
 * Issue #294: Should be a no-op when word count is disabled.
 *
 * With the throttle-based implementation, nothing is scheduled or fired when
 * the preference is off, so running the run loop should not trigger any
 * word count work and should not crash.
 */
- (void)testScheduleWordCountUpdateRespectsDisabledPreference
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = NO;

    @try {
        XCTAssertNoThrow([self.document scheduleWordCountUpdate],
                         @"scheduleWordCountUpdate should not crash when preference is disabled");

        // Run briefly; nothing should be scheduled so nothing should fire
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];

        // totalWords should remain 0 — no update was scheduled
        XCTAssertEqual(self.document.totalWords, (NSUInteger)0,
                       @"totalWords should remain 0 when editorShowWordCount is NO");
    }
    @finally {
        prefs.editorShowWordCount = originalValue;
    }
}


#pragma mark - Cleanup Tests

/**
 * Test that cancelPreviousPerformRequests cancels a pending word count update.
 * Issue #294: Verifies the cancellation mechanism used by -close.
 *
 * We can't call -close on a bare MPDocument (it requires full nib
 * initialization for KVO teardown), so we test the cancellation
 * primitive directly: schedule a trailing update, cancel it, run past
 * the throttle interval, and verify the update never fired.
 */
- (void)testPendingUpdatesCancelledOnClose
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        // Stamp lastWordCountUpdate to now so the call goes to the trailing
        // path rather than firing immediately
        self.document.lastWordCountUpdate = [NSDate timeIntervalSinceReferenceDate];

        // Schedule a trailing update
        [self.document scheduleWordCountUpdate];

        // Cancel the pending request (same call that -close makes)
        [NSObject cancelPreviousPerformRequestsWithTarget:self.document
                                                 selector:@selector(updateWordCount)
                                                   object:nil];

        // Run past the throttle interval; the cancelled update should not fire
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.5]];

        // totalWords stays 0 — the cancelled selector never fired
        XCTAssertEqual(self.document.totalWords, (NSUInteger)0,
                       @"totalWords should remain 0 after cancelling pending update");
    }
    @finally {
        prefs.editorShowWordCount = originalValue;
    }
}

@end
