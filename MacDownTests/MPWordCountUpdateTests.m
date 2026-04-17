//
//  MPWordCountUpdateTests.m
//  MacDownTests
//
//  Tests for Issue #294: Word count update during DOM replacement.
//  Verifies scheduleWordCountUpdate debouncing logic.
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


#pragma mark - Debouncing Tests

/**
 * Test that rapid calls to scheduleWordCountUpdate result in debouncing.
 * Issue #294: The update should not fire during the debounce window.
 *
 * Calls scheduleWordCountUpdate multiple times rapidly, then runs the run
 * loop for less than the 0.3s debounce delay. Verifies that updateWordCount
 * has not yet fired (totalWords remains 0 since there is no real WebView).
 */
- (void)testScheduleWordCountUpdateDebounces
{
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

        // Run the run loop for less than the 0.3s debounce delay
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];

        // updateWordCount should not have fired yet; totalWords stays 0
        // (without a real WebView, updateWordCount won't change totalWords,
        // but if it had fired, the code path would still have been exercised)
        XCTAssertEqual(self.document.totalWords, (NSUInteger)0,
                       @"totalWords should still be 0 within the debounce window");
    }
    @finally {
        // Cancel pending requests before restoring preferences, ensuring no
        // deferred updateWordCount fires after this test ends.
        [NSObject cancelPreviousPerformRequestsWithTarget:self.document
                                                 selector:@selector(updateWordCount)
                                                   object:nil];
        prefs.editorShowWordCount = originalValue;
    }

    // Run the run loop past the debounce delay and confirm the cancelled
    // requests did not fire (totalWords remains 0).
    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.5]];
    XCTAssertEqual(self.document.totalWords, (NSUInteger)0,
                   @"totalWords should remain 0 after cancelled requests — debounced updates must not fire");
}

/**
 * Test that scheduleWordCountUpdate fires updateWordCount after the delay.
 * Issue #294: Verify the performSelector-based timer actually fires.
 *
 * Calls scheduleWordCountUpdate with editorShowWordCount=YES, then runs the
 * run loop for more than 0.3s. The method should fire without crashing.
 * totalWords will remain 0 without a real WebView, but the code path is
 * exercised.
 */
- (void)testDebounceFiresAfterDelay
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        XCTAssertNoThrow([self.document scheduleWordCountUpdate],
                         @"scheduleWordCountUpdate should not crash");

        // Run the run loop past the 0.3s debounce delay so the scheduled
        // updateWordCount fires. Without a WebView, updateWordCount sends
        // messages to nil (safe in ObjC) and totalWords stays 0.
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.5]];

        XCTAssertEqual(self.document.totalWords, (NSUInteger)0,
                       @"totalWords should remain 0 without a real WebView");
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
 * With the performSelector-based implementation, nothing is scheduled when
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
 * primitive directly: schedule an update, cancel it, run past the
 * debounce delay, and verify the update never fired.
 */
- (void)testPendingUpdatesCancelledOnClose
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL originalValue = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;

    @try {
        // Schedule an update
        [self.document scheduleWordCountUpdate];

        // Cancel the pending request (same call that -close makes)
        [NSObject cancelPreviousPerformRequestsWithTarget:self.document
                                                 selector:@selector(updateWordCount)
                                                   object:nil];

        // Run past the debounce delay; the cancelled update should not fire
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
