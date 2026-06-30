#import <XCTest/XCTest.h>
#import "MPSidebarSyncCoordinator.h"

@interface MPSidebarSyncCoordinatorTests : XCTestCase
@end

@implementation MPSidebarSyncCoordinatorTests

- (void)testWidthIsClampedToRange
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:5000 source:self];
    XCTAssertLessThanOrEqual(c.sidebarWidth, 420.0);
    [c setSidebarWidth:10 source:self];
    XCTAssertGreaterThanOrEqual(c.sidebarWidth, 150.0);
}

- (void)testEqualWidthDoesNotNotify
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:250 source:self];
    __block NSInteger count = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) { count++; }];
    [c setSidebarWidth:250 source:self];   // equal → no broadcast (breaks the loop)
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(count, 0);
    XCTAssertEqualWithAccuracy(c.sidebarWidth, 250.0, 0.5);
}

- (void)testChangedWidthNotifiesWithKind
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:200 source:self];
    id token = [NSObject new];
    XCTestExpectation *e = [self expectationWithDescription:@"notified"];
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:token
                     queue:nil usingBlock:^(NSNotification *n) {
            XCTAssertEqualObjects(n.userInfo[MPSidebarSyncKindKey], MPSidebarSyncKindWidth);
            [e fulfill];
        }];
    [c setSidebarWidth:321 source:token];
    [self waitForExpectations:@[e] timeout:1.0];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
}

- (void)testVisibleToggleNotifiesOnlyOnChange
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarVisible:YES source:self];
    __block NSInteger count = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) {
            if ([n.userInfo[MPSidebarSyncKindKey] isEqualToString:MPSidebarSyncKindVisible])
                count++;
        }];
    [c setSidebarVisible:YES source:self];   // no change → no notify
    [c setSidebarVisible:NO source:self];    // change → notify
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(count, 1);
    XCTAssertFalse(c.sidebarVisible);
}

- (void)testExpansionIsPerRootAndOrderIndependent
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    NSURL *rootA = [NSURL fileURLWithPath:@"/tmp/sync-a" isDirectory:YES];
    NSURL *rootB = [NSURL fileURLWithPath:@"/tmp/sync-b" isDirectory:YES];
    [c setExpandedPaths:@[@"/tmp/sync-a/x", @"/tmp/sync-a/y"] forRoot:rootA source:self];
    [c setExpandedPaths:@[@"/tmp/sync-b/z"] forRoot:rootB source:self];

    XCTAssertEqualObjects([NSSet setWithArray:[c expandedPathsForRoot:rootA]],
                          ([NSSet setWithObjects:@"/tmp/sync-a/x", @"/tmp/sync-a/y", nil]));
    XCTAssertEqualObjects([c expandedPathsForRoot:rootB], @[@"/tmp/sync-b/z"]);

    // Same set, different order → treated as no change.
    __block NSInteger count = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) {
            if ([n.userInfo[MPSidebarSyncKindKey] isEqualToString:MPSidebarSyncKindExpansion])
                count++;
        }];
    [c setExpandedPaths:@[@"/tmp/sync-a/y", @"/tmp/sync-a/x"] forRoot:rootA source:self];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(count, 0);
}

@end
