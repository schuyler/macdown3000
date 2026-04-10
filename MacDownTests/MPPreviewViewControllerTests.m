//
//  MPPreviewViewControllerTests.m
//  MacDown 3000
//
//  Tests for the Quick Look PreviewViewController (Issue #367)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//
//  NOTE: These tests require ENABLE_QUICKLOOK_TESTS=1 in the MacDownTests
//  target preprocessor macros AND PreviewViewController.m must be added to
//  the MacDownTests target's Compile Sources build phase.
//  See plans/quick-look-xcode-setup.md for the broader setup context.
//

#import <XCTest/XCTest.h>

#if ENABLE_QUICKLOOK_TESTS

#import <WebKit/WebKit.h>
#import <Quartz/Quartz.h>
#import "PreviewViewController.h"


@interface MPPreviewViewControllerTests : XCTestCase
@end

@implementation MPPreviewViewControllerTests


#pragma mark - WKNavigationDelegate Conformance Tests (Bug 1, Bug 4)

- (void)testPreviewViewControllerConformsToWKNavigationDelegate
{
    // FAILS on current code: PreviewViewController only conforms to QLPreviewingController.
    // PASSES after fix: header declares <QLPreviewingController, WKNavigationDelegate>.
    XCTAssertTrue([PreviewViewController conformsToProtocol:@protocol(WKNavigationDelegate)],
                  @"PreviewViewController must conform to WKNavigationDelegate so the "
                  @"completion handler can be deferred until the page finishes rendering");
}

- (void)testPreviewViewControllerImplementsDidFinishNavigation
{
    // FAILS on current code: method not defined.
    // PASSES after fix: -webView:didFinishNavigation: is implemented and drains pendingHandler.
    XCTAssertTrue([PreviewViewController
                   instancesRespondToSelector:@selector(webView:didFinishNavigation:)],
                  @"Must implement -webView:didFinishNavigation: to fire the QL completion handler");
}

- (void)testPreviewViewControllerImplementsDidFailNavigation
{
    // FAILS on current code: method not defined.
    // PASSES after fix: -webView:didFailNavigation:withError: drains pendingHandler with error.
    XCTAssertTrue([PreviewViewController
                   instancesRespondToSelector:@selector(webView:didFailNavigation:withError:)],
                  @"Must implement -webView:didFailNavigation:withError: to propagate errors");
}

- (void)testPreviewViewControllerImplementsDidFailProvisionalNavigation
{
    // FAILS on current code: method not defined.
    // PASSES after fix: -webView:didFailProvisionalNavigation:withError: drains pendingHandler.
    XCTAssertTrue([PreviewViewController
                   instancesRespondToSelector:@selector(webView:didFailProvisionalNavigation:withError:)],
                  @"Must implement -webView:didFailProvisionalNavigation:withError: for sandbox errors");
}


#pragma mark - Completion Handler Deferral Test (Bug 1)

- (void)testCompletionHandlerIsNotCalledSynchronously
{
    // The old code calls handler(nil) immediately after loadHTMLString:baseURL:,
    // before WKWebView has rendered anything. Quick Look snapshots the blank view.
    // After the fix the handler is stored in pendingHandler and only called from
    // -webView:didFinishNavigation:.
    //
    // FAILS on current code: handlerCalled is YES immediately after the call.
    // PASSES after fix: handlerCalled remains NO until the run loop delivers
    // WKWebView's navigation callback.

    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test_ql_sync.md"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];
    [@"# Sync Test\n\nParagraph." writeToFile:tempFile
                                   atomically:YES
                                     encoding:NSUTF8StringEncoding
                                        error:nil];

    PreviewViewController *vc = [[PreviewViewController alloc] init];
    [vc loadView];

    __block BOOL handlerCalled = NO;
    [vc preparePreviewOfFileAtURL:[NSURL fileURLWithPath:tempFile]
                completionHandler:^(NSError * _Nullable error) {
        handlerCalled = YES;
    }];

    // Immediately after the call — before any run-loop turn — the handler must NOT
    // have been called. If it was called synchronously, Quick Look gets a blank pane.
    XCTAssertFalse(handlerCalled,
                   @"Completion handler must not be called synchronously; "
                   @"it must wait for -webView:didFinishNavigation:");
}

- (void)testCompletionHandlerIsEventuallyCalledAfterNavigation
{
    // Verify the handler IS called, just not synchronously.
    // This confirms the deferred path (WKWebView navigation + delegate callback) works end-to-end.

    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test_ql_async.md"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];
    [@"# Async Test\n\nParagraph." writeToFile:tempFile
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:nil];

    PreviewViewController *vc = [[PreviewViewController alloc] init];
    [vc loadView];

    XCTestExpectation *expectation = [self expectationWithDescription:@"QL completion handler called"];

    [vc preparePreviewOfFileAtURL:[NSURL fileURLWithPath:tempFile]
                completionHandler:^(NSError * _Nullable error) {
        [expectation fulfill];
    }];

    // Allow up to 10 seconds for WKWebView to load the HTML and fire the delegate callback.
    [self waitForExpectationsWithTimeout:10.0 handler:^(NSError * _Nullable error) {
        if (error) {
            XCTFail(@"Completion handler was never called within 10 seconds: %@", error);
        }
    }];
}


#pragma mark - View Setup Tests

- (void)testLoadViewCreatesWKWebViewWithNavigationDelegate
{
    // After the fix: the web view's navigationDelegate must be set to the view controller
    // so the delegate callbacks actually fire.
    //
    // FAILS on current code: navigationDelegate is nil (not set in loadView).
    // PASSES after fix: self.webView.navigationDelegate = self.

    PreviewViewController *vc = [[PreviewViewController alloc] init];
    [vc loadView];

    XCTAssertTrue([vc.view isKindOfClass:[WKWebView class]],
                  @"View must be a WKWebView");

    WKWebView *webView = (WKWebView *)vc.view;
    XCTAssertEqual(webView.navigationDelegate, (id<WKNavigationDelegate>)vc,
                   @"webView.navigationDelegate must be set to the view controller");
}

- (void)testPreferredContentSizeIsSet
{
    // After the fix: preferredContentSize must be non-zero so Quick Look has a
    // meaningful initial size to render into.
    //
    // FAILS on current code: preferredContentSize is CGSizeZero (NSZeroRect frame used).
    // PASSES after fix: preferredContentSize is set to 800×600.

    PreviewViewController *vc = [[PreviewViewController alloc] init];
    [vc loadView];

    NSSize size = vc.preferredContentSize;
    XCTAssertGreaterThan(size.width, 0,
                         @"preferredContentSize.width must be > 0");
    XCTAssertGreaterThan(size.height, 0,
                         @"preferredContentSize.height must be > 0");
}

@end

#else

// Placeholder when Quick Look tests are disabled.
@interface MPPreviewViewControllerTests : XCTestCase
@end

@implementation MPPreviewViewControllerTests

- (void)testPreviewViewControllerTestsDisabled
{
    NSLog(@"PreviewViewController tests are disabled. "
          @"Add ENABLE_QUICKLOOK_TESTS=1 to preprocessor macros and "
          @"add PreviewViewController.m to the MacDownTests Compile Sources phase.");
}

@end

#endif // ENABLE_QUICKLOOK_TESTS
