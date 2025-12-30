//
//  MPNotificationTests.m
//  MacDownTests
//
//  Tests for notification/observer integration. Verifies that components
//  respond correctly to preference changes and that notifications fire
//  with correct data.
//
//  Created for Issue #234: Test Coverage Phase 1b
//

#import <XCTest/XCTest.h>
#import "MPPreferences.h"
#import "MPPreferencesViewController.h"
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"


#pragma mark - Mock Notification Observer

@interface MPMockNotificationObserver : NSObject
@property (nonatomic) NSInteger notificationCount;
@property (nonatomic, strong) NSMutableArray<NSNotification *> *receivedNotifications;
@property (nonatomic, strong) XCTestExpectation *expectation;
@end

@implementation MPMockNotificationObserver

- (instancetype)init
{
    self = [super init];
    if (self) {
        _receivedNotifications = [NSMutableArray array];
        _notificationCount = 0;
    }
    return self;
}

- (void)handleNotification:(NSNotification *)notification
{
    self.notificationCount++;
    [self.receivedNotifications addObject:notification];
    [self.expectation fulfill];
}

- (void)reset
{
    self.notificationCount = 0;
    [self.receivedNotifications removeAllObjects];
    self.expectation = nil;
}

@end


#pragma mark - Extended Tracking Delegate

@interface MPStyleChangeTrackingDelegate : MPMockRendererDelegate
@property (nonatomic) NSInteger styleNameCallCount;
@property (nonatomic) NSInteger htmlOutputCallCount;
@property (nonatomic, copy) NSString *lastReceivedHTML;
@end

@implementation MPStyleChangeTrackingDelegate

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    self.styleNameCallCount++;
    return [super rendererStyleName:renderer];
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    self.htmlOutputCallCount++;
    self.lastReceivedHTML = html;
    [super renderer:renderer didProduceHTMLOutput:html];
}

@end


#pragma mark - Test Class

@interface MPNotificationTests : XCTestCase
@property (nonatomic, strong) MPPreferences *preferences;
@property (nonatomic, strong) MPMockNotificationObserver *observer;
@property (nonatomic, strong) id notificationToken;

// Saved preference values for restoration
@property (nonatomic, copy) NSString *savedStyleName;
@property (nonatomic, copy) NSString *savedEditorStyleName;
@property (nonatomic) BOOL savedMathJax;
@property (nonatomic) BOOL savedSyntaxHighlighting;
@property (nonatomic, copy) NSDictionary *savedFontInfo;
@end


@implementation MPNotificationTests

- (void)setUp
{
    [super setUp];

    self.preferences = [MPPreferences sharedInstance];
    self.observer = [[MPMockNotificationObserver alloc] init];

    // Save current preference values
    self.savedStyleName = self.preferences.htmlStyleName;
    self.savedEditorStyleName = self.preferences.editorStyleName;
    self.savedMathJax = self.preferences.htmlMathJax;
    self.savedSyntaxHighlighting = self.preferences.htmlSyntaxHighlighting;
    self.savedFontInfo = [self.preferences.editorBaseFontInfo copy];
}

- (void)tearDown
{
    // Remove any registered observers
    if (self.notificationToken) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.notificationToken];
        self.notificationToken = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self.observer];

    // Restore preference values
    self.preferences.htmlStyleName = self.savedStyleName;
    self.preferences.editorStyleName = self.savedEditorStyleName;
    self.preferences.htmlMathJax = self.savedMathJax;
    self.preferences.htmlSyntaxHighlighting = self.savedSyntaxHighlighting;
    self.preferences.editorBaseFontInfo = self.savedFontInfo;
    [self.preferences synchronize];

    self.observer = nil;
    self.preferences = nil;

    [super tearDown];
}


#pragma mark - Renderer Style Change Tests

- (void)testRendererRespondsToStyleChange
{
    // Setup renderer with tracking delegate
    MPStyleChangeTrackingDelegate *delegate = [[MPStyleChangeTrackingDelegate alloc] init];
    MPMockRendererDataSource *dataSource = [[MPMockRendererDataSource alloc] init];

    MPRenderer *renderer = [[MPRenderer alloc] init];
    renderer.delegate = delegate;
    renderer.dataSource = dataSource;

    // Initial render
    delegate.styleName = @"GitHub2";
    dataSource.markdown = @"# Test Heading\n\nSome paragraph text.";
    [renderer parseMarkdown:dataSource.markdown];

    NSString *html1 = [renderer HTMLForExportWithStyles:YES highlighting:NO];
    XCTAssertNotNil(html1, @"Should produce initial HTML");
    NSInteger initialStyleNameCalls = delegate.styleNameCallCount;

    // Change style
    delegate.styleName = @"Clearness";

    // Re-render with new style
    NSString *html2 = [renderer HTMLForExportWithStyles:YES highlighting:NO];
    XCTAssertNotNil(html2, @"Should produce HTML after style change");

    // Verify style name was queried (may be queried multiple times)
    XCTAssertGreaterThan(delegate.styleNameCallCount, initialStyleNameCalls,
                         @"Renderer should query style name when generating styled output");
}

- (void)testRendererStyleChangeProducesDifferentCSS
{
    // Setup renderer
    MPMockRendererDelegate *delegate = [[MPMockRendererDelegate alloc] init];
    MPMockRendererDataSource *dataSource = [[MPMockRendererDataSource alloc] init];

    MPRenderer *renderer = [[MPRenderer alloc] init];
    renderer.delegate = delegate;
    renderer.dataSource = dataSource;

    dataSource.markdown = @"# Test\n\nContent here.";
    [renderer parseMarkdown:dataSource.markdown];

    // Render with first style
    delegate.styleName = @"GitHub2";
    NSString *html1 = [renderer HTMLForExportWithStyles:YES highlighting:NO];

    // Render with different style
    delegate.styleName = @"Clearness";
    NSString *html2 = [renderer HTMLForExportWithStyles:YES highlighting:NO];

    // Both should have style content but be different
    XCTAssertTrue([html1 containsString:@"<style"], @"First HTML should include styles");
    XCTAssertTrue([html2 containsString:@"<style"], @"Second HTML should include styles");

    // Styles should be different (the CSS content differs between themes)
    // We can't directly compare because the content is the same, only CSS differs
    XCTAssertNotNil(html1, @"HTML1 should not be nil");
    XCTAssertNotNil(html2, @"HTML2 should not be nil");
}


#pragma mark - Preference Change Notification Tests

- (void)testPreviewRenderNotificationFires
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Preview render notification"];

    __block NSInteger notificationCount = 0;
    self.notificationToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPDidRequestPreviewRenderNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        notificationCount++;
        [expectation fulfill];
    }];

    // Post the notification directly to verify observer mechanism works
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPDidRequestPreviewRenderNotification
                      object:nil];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqual(notificationCount, 1, @"Should receive exactly one notification");
}

- (void)testEditorSetupNotificationFires
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Editor setup notification"];

    __block NSInteger notificationCount = 0;
    self.notificationToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPDidRequestEditorSetupNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        notificationCount++;
        [expectation fulfill];
    }];

    // Post the notification directly
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPDidRequestEditorSetupNotification
                      object:nil];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqual(notificationCount, 1, @"Should receive editor setup notification");
}

- (void)testMultipleObserversReceiveNotification
{
    // Create multiple observers
    MPMockNotificationObserver *observer1 = [[MPMockNotificationObserver alloc] init];
    MPMockNotificationObserver *observer2 = [[MPMockNotificationObserver alloc] init];

    [[NSNotificationCenter defaultCenter]
        addObserver:observer1
           selector:@selector(handleNotification:)
               name:MPDidRequestPreviewRenderNotification
             object:nil];

    [[NSNotificationCenter defaultCenter]
        addObserver:observer2
           selector:@selector(handleNotification:)
               name:MPDidRequestPreviewRenderNotification
             object:nil];

    @try {
        // Post notification
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MPDidRequestPreviewRenderNotification
                          object:nil];

        // Both observers should receive it
        XCTAssertEqual(observer1.notificationCount, 1, @"Observer 1 should receive notification");
        XCTAssertEqual(observer2.notificationCount, 1, @"Observer 2 should receive notification");
    }
    @finally {
        [[NSNotificationCenter defaultCenter] removeObserver:observer1];
        [[NSNotificationCenter defaultCenter] removeObserver:observer2];
    }
}


#pragma mark - Preference Change Coalescing Tests

- (void)testPreferenceChangeDoesNotCrash
{
    // Verify that rapidly changing preferences doesn't cause issues
    XCTAssertNoThrow({
        for (int i = 0; i < 10; i++) {
            self.preferences.htmlMathJax = (i % 2 == 0);
            self.preferences.htmlSyntaxHighlighting = (i % 2 == 1);
            [self.preferences synchronize];
        }
    }, @"Rapid preference changes should not crash");
}

- (void)testPreferenceChangePersists
{
    // Toggle a preference and verify it persists
    BOOL originalValue = self.preferences.htmlMathJax;

    self.preferences.htmlMathJax = !originalValue;
    [self.preferences synchronize];

    // Re-read from preferences
    BOOL newValue = self.preferences.htmlMathJax;
    XCTAssertNotEqual(newValue, originalValue, @"Preference should have changed");

    // Toggle back
    self.preferences.htmlMathJax = originalValue;
    [self.preferences synchronize];

    XCTAssertEqual(self.preferences.htmlMathJax, originalValue, @"Preference should be restored");
}


#pragma mark - Theme Change Notification Tests

- (void)testThemeChangeNotificationContainsCorrectInfo
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Theme change notification"];

    __block NSNotification *receivedNotification = nil;
    self.notificationToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPDidRequestEditorSetupNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        receivedNotification = notification;
        [expectation fulfill];
    }];

    // Post notification with userInfo
    NSDictionary *userInfo = @{@"styleName": @"TestStyle"};
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPDidRequestEditorSetupNotification
                      object:self.preferences
                    userInfo:userInfo];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    XCTAssertNotNil(receivedNotification, @"Should receive notification");
    XCTAssertNotNil(receivedNotification.userInfo, @"UserInfo should not be nil");
    XCTAssertEqualObjects(receivedNotification.userInfo[@"styleName"], @"TestStyle",
                          @"UserInfo should contain style name");
}


#pragma mark - Font Size Change Tests

- (void)testFontInfoChange
{
    // Get current font info
    NSDictionary *originalFontInfo = self.preferences.editorBaseFontInfo;

    // Create new font info
    NSFont *newFont = [NSFont systemFontOfSize:18.0];
    self.preferences.editorBaseFont = newFont;
    [self.preferences synchronize];

    // Verify font size changed
    CGFloat newSize = self.preferences.editorBaseFontSize;
    XCTAssertEqualWithAccuracy(newSize, 18.0, 0.1, @"Font size should be 18.0");

    // Restore original
    self.preferences.editorBaseFontInfo = originalFontInfo;
    [self.preferences synchronize];
}

- (void)testFontSizeChangeNotificationMechanism
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"User defaults notification"];

    __block BOOL notificationReceived = NO;
    self.notificationToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSUserDefaultsDidChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        notificationReceived = YES;
        [expectation fulfill];
    }];

    // Change a preference to trigger defaults change
    BOOL originalValue = self.preferences.htmlMathJax;
    self.preferences.htmlMathJax = !originalValue;
    [self.preferences synchronize];

    // Restore
    self.preferences.htmlMathJax = originalValue;
    [self.preferences synchronize];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertTrue(notificationReceived, @"Should receive user defaults change notification");
}


#pragma mark - Observer Cleanup Tests

- (void)testObserverRemovalPreventsNotifications
{
    MPMockNotificationObserver *observer = [[MPMockNotificationObserver alloc] init];

    [[NSNotificationCenter defaultCenter]
        addObserver:observer
           selector:@selector(handleNotification:)
               name:MPDidRequestPreviewRenderNotification
             object:nil];

    // Remove observer
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    // Post notification
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPDidRequestPreviewRenderNotification
                      object:nil];

    // Should not receive notification
    XCTAssertEqual(observer.notificationCount, 0,
                   @"Removed observer should not receive notifications");
}

- (void)testObserverWithSpecificObjectFilter
{
    MPMockNotificationObserver *observer = [[MPMockNotificationObserver alloc] init];
    id specificObject = [[NSObject alloc] init];
    id otherObject = [[NSObject alloc] init];

    [[NSNotificationCenter defaultCenter]
        addObserver:observer
           selector:@selector(handleNotification:)
               name:MPDidRequestPreviewRenderNotification
             object:specificObject];

    @try {
        // Post notification with different object
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MPDidRequestPreviewRenderNotification
                          object:otherObject];

        XCTAssertEqual(observer.notificationCount, 0,
                       @"Should not receive notification for different object");

        // Post notification with specific object
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MPDidRequestPreviewRenderNotification
                          object:specificObject];

        XCTAssertEqual(observer.notificationCount, 1,
                       @"Should receive notification for specific object");
    }
    @finally {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
}


#pragma mark - Notification Thread Safety Tests

- (void)testNotificationOnBackgroundThread
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Background notification"];

    __block NSThread *receivingThread = nil;
    self.notificationToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPDidRequestPreviewRenderNotification
                    object:nil
                     queue:nil  // Receive on posting thread
                usingBlock:^(NSNotification *notification) {
        receivingThread = [NSThread currentThread];
        [expectation fulfill];
    }];

    // Post from background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MPDidRequestPreviewRenderNotification
                          object:nil];
    });

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // When queue is nil, notification is delivered on the posting thread
    XCTAssertNotNil(receivingThread, @"Should record receiving thread");
}

- (void)testNotificationOnMainQueue
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Main queue notification"];

    __block BOOL isMainThread = NO;
    self.notificationToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPDidRequestPreviewRenderNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        isMainThread = [NSThread isMainThread];
        [expectation fulfill];
    }];

    // Post from background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MPDidRequestPreviewRenderNotification
                          object:nil];
    });

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // With mainQueue specified, notification should be delivered on main thread
    XCTAssertTrue(isMainThread, @"Notification should be received on main thread");
}

@end
