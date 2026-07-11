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

// T3: no lasting retain cycle. The terminationHandler block captures self
// strongly (deliberately, to keep the controller alive until the task
// exits), but must break the cycle as its first action -- `task.
// terminationHandler = nil;` -- so the block (and its captured self) does
// not outlive a single invocation.
//
// NSTask.h does not document that -terminationHandler is cleared after the
// block is invoked, and empirically it IS cleared (verified separately, via
// a standalone compiled test program) when NSTask invokes it itself on
// real process exit -- but that's incidental behavior on this SDK, not a
// documented contract, and it makes a naive "let the real process exit,
// then check task.terminationHandler == nil (or that the controller
// deallocates)" test pass regardless of whether the controller's own
// cycle-break line is present.
//
// To exercise only the controller's own code, this test captures the
// terminationHandler block into a local synchronously (right after
// -runWithCompletionHandler: assigns it, before the real background
// process necessarily exits) and invokes it MANUALLY, exactly as NSTask
// would. Manual invocation does not go through NSTask's own invoke+clear
// machinery at all, so `capturedTask.terminationHandler` reflects only
// what the block's OWN body did to it -- specifically, whether its first
// statement (`task.terminationHandler = nil;`) ran. This is checked
// synchronously immediately after the manual call returns, sidestepping
// any dependency on deallocation timing or NSTask's async internals.
- (void)testNoRetainCycleControllerDeallocates
{
    MPHomebrewStubController *controller =
        [[MPHomebrewStubController alloc] initWithArguments:@[@"marker"]];
    controller.stubBrewPath = @"/bin/echo";

    // The real background process and our manual invocation below can
    // both legitimately end up delivering completion (this test cares
    // about the terminationHandler block's cycle-break behavior, not
    // about completion being delivered exactly once), so don't fail on
    // over-fulfillment.
    XCTestExpectation *expectation =
        [self expectationWithDescription:@"completion handler fires"];
    expectation.assertForOverFulfill = NO;
    [controller runWithCompletionHandler:^(NSString *output) {
        [expectation fulfill];
    }];

    // Capture synchronously, right after assignment -- before the real
    // background process necessarily exits and NSTask's own machinery has
    // a chance to invoke (and auto-clear) it first.
    void (^capturedTerminationHandler)(NSTask *) =
        [controller.task.terminationHandler copy];
    NSTask *task = controller.task;

    XCTAssertNotNil(capturedTerminationHandler,
                    @"sanity check: -runWithCompletionHandler: should have "
                    @"assigned a terminationHandler block synchronously");

    // Invoke manually -- this does NOT go through NSTask's own
    // invoke-then-clear machinery, so `task.terminationHandler` afterward
    // reflects only the block's own body, i.e. whether the controller's
    // cycle-break line ran.
    if (capturedTerminationHandler)
        capturedTerminationHandler(task);

    XCTAssertNil(task.terminationHandler,
                @"task.terminationHandler should have been nil'd out by "
                @"the block's own first statement -- if this is non-nil, "
                @"the controller's cycle-break line did not run (or was "
                @"removed), meaning the retain cycle was not broken");

    // Let the real background process (still running independently) and
    // the block's internal dispatch_async to main both settle, so nothing
    // dangles after the test returns.
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
