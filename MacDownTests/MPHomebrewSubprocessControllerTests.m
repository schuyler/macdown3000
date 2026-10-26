//
//  MPHomebrewSubprocessControllerTests.m
//  MacDownTests
//
//  Tests for PR #1379 Fix 3: MPHomebrewSubprocessController modernization.
//
//  The production bug: `_task.launchPath = @"brew"` was a bare relative
//  path. NSTask never searches PATH, so `-launch` always threw
//  NSInvalidArgumentException, and the @catch delivered `handler(nil)`
//  synchronously on the CALLER's thread. Homebrew detection was therefore
//  silently and unconditionally broken, and (pre-fix) the completion
//  handler's threading contract was undefined -- callers that mutate
//  AppKit UI from it were relying on being called from the main thread by
//  accident (whatever thread happened to call -runWithCompletionHandler:).
//
//  Post-fix, completion is ALWAYS delivered via dispatch_async(main queue),
//  for both the not-found path and the success/failure-after-launch path.
//

#import <XCTest/XCTest.h>
#import "MPHomebrewSubprocessControllerTesting.h"

#pragma mark - Stub Controller

/**
 * Test-only subclass that lets us substitute a known-good (or nil) brew
 * path instead of depending on whether Homebrew is actually installed on
 * the test-running machine.
 */
@interface MPHomebrewStubController : MPHomebrewSubprocessController
@property (nonatomic, copy) NSString *stubBrewPath;
@end

@implementation MPHomebrewStubController

- (NSString *)resolvedBrewPath
{
    return self.stubBrewPath;
}

@end

#pragma mark - Test Case

@interface MPHomebrewSubprocessControllerTests : XCTestCase
@end

@implementation MPHomebrewSubprocessControllerTests

// T1: happy path. /bin/echo stands in for `brew`; its stdout is exactly
// its arguments, so we can assert the pipe wiring/parsing works, and that
// completion fires on the main thread.
- (void)testSuccessDeliversOutputOnMainThread
{
    MPHomebrewStubController *controller =
        [[MPHomebrewStubController alloc] initWithArguments:@[@"macdown-test-marker"]];
    controller.stubBrewPath = @"/bin/echo";

    XCTestExpectation *expectation =
        [self expectationWithDescription:@"completion handler fires"];

    // Capture facts inside the handler instead of asserting there. An
    // XCTAssert executed off the test thread records a failure that raises
    // an uncaught exception and SIGABRTs the whole test host -- masking
    // every other test's results -- instead of failing just this one test
    // cleanly. Assert after -waitForExpectationsWithTimeout: returns,
    // which is guaranteed to be on the main/test thread.
    __block BOOL handlerCalled = NO;
    __block BOOL wasMainThread = NO;
    __block NSString *capturedOutput = nil;

    [controller runWithCompletionHandler:^(NSString *output) {
        handlerCalled = YES;
        wasMainThread = [NSThread isMainThread];
        capturedOutput = output;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCTAssertTrue(handlerCalled, @"completion handler was never called");
    XCTAssertTrue([capturedOutput containsString:@"macdown-test-marker"],
                  @"expected echoed marker in output, got: %@", capturedOutput);
    XCTAssertTrue(wasMainThread,
                  @"completion handler must be delivered on the main thread");
}

// T2: the genuine red/green discriminator for the launchPath bug. Pre-fix,
// the @catch delivered handler(nil) SYNCHRONOUSLY on whatever thread called
// -runWithCompletionHandler: -- here, a background queue. Post-fix, the
// not-found path is always dispatched to the main queue. Invoking from a
// background queue makes the two behaviors observably different.
- (void)testNotFoundDeliversNilOnMainThread
{
    MPHomebrewStubController *controller =
        [[MPHomebrewStubController alloc] initWithArguments:nil];
    controller.stubBrewPath = nil;

    XCTestExpectation *expectation =
        [self expectationWithDescription:@"completion handler fires"];

    // Capture facts inside the handler instead of asserting there. An
    // XCTAssert executed off the test thread records a failure that raises
    // an uncaught exception and SIGABRTs the whole test host -- masking
    // every other test's results -- instead of failing just this one test
    // cleanly. Assert after -waitForExpectationsWithTimeout: returns,
    // which is guaranteed to be on the main/test thread.
    __block BOOL handlerCalled = NO;
    __block BOOL wasMainThread = NO;
    __block NSString *capturedOutput = nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [controller runWithCompletionHandler:^(NSString *output) {
            handlerCalled = YES;
            wasMainThread = [NSThread isMainThread];
            capturedOutput = output;
            [expectation fulfill];
        }];
    });

    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCTAssertTrue(handlerCalled, @"completion handler was never called");
    XCTAssertNil(capturedOutput);
    XCTAssertTrue(wasMainThread,
                  @"completion handler must be delivered on the main thread "
                  @"even when -runWithCompletionHandler: is invoked from a "
                  @"background queue");
}

// Completion survives release of the controller and does not depend on a
// private termination callback or on NSTask's incidental block clearing.
- (void)testCompletionSurvivesControllerRelease
{
    XCTestExpectation *expectation =
        [self expectationWithDescription:@"completion survives controller release"];
    __weak MPHomebrewStubController *weakController;
    __block NSString *capturedOutput = nil;
    __block BOOL wasMainThread = NO;
    @autoreleasepool {
        MPHomebrewStubController *controller =
            [[MPHomebrewStubController alloc] initWithArguments:@[@"marker"]];
        controller.stubBrewPath = @"/bin/echo";
        weakController = controller;
        [controller runWithCompletionHandler:^(NSString *output) {
            capturedOutput = output;
            wasMainThread = NSThread.isMainThread;
            [expectation fulfill];
        }];
    }
    [self waitForExpectationsWithTimeout:5 handler:nil];
    XCTAssertEqualObjects(capturedOutput, @"marker\n");
    XCTAssertTrue(wasMainThread);
    XCTAssertNil(weakController);
}

- (void)testOutputLargerThanPipeCapacityCompletesOnMainThread
{
    MPHomebrewStubController *controller = [[MPHomebrewStubController alloc]
        initWithArguments:@[@"BEGIN { for (i=0; i<1048576; i++) printf \"x\"; }"]];
    controller.stubBrewPath = @"/usr/bin/awk";
    XCTestExpectation *expectation =
        [self expectationWithDescription:@"large stdout completes"];
    __block NSString *capturedOutput = nil;
    __block BOOL wasMainThread = NO;
    [controller runWithCompletionHandler:^(NSString *output) {
        capturedOutput = output;
        wasMainThread = NSThread.isMainThread;
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    // Clean up only this fixture if a regression leaves it blocked in write().
    if (controller.task.running) [controller.task terminate];
    XCTAssertEqualObjects(capturedOutput,
        [@"" stringByPaddingToLength:1048576 withString:@"x" startingAtIndex:0]);
    XCTAssertTrue(wasMainThread);
}

@end
