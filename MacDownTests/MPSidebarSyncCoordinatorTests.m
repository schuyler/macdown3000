#import <XCTest/XCTest.h>
#import "MPSidebarSyncCoordinator.h"

static NSString * const kMPSidebarWidthDefaultsKey = @"MPSidebarSharedWidth";

@interface MPSidebarSyncCoordinatorTests : XCTestCase
@property (strong) NSURL *rootA;
@property (strong) NSURL *rootB;
@property (strong) NSNumber *savedWidthDefault;
@end

@implementation MPSidebarSyncCoordinatorTests

- (void)setUp
{
    [super setUp];
    // Distinct roots per test method, so the shared coordinator's accumulated
    // state can't leak between tests.
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.rootA = [NSURL fileURLWithPath:
        [NSString stringWithFormat:@"/tmp/sync-a-%@", unique] isDirectory:YES];
    self.rootB = [NSURL fileURLWithPath:
        [NSString stringWithFormat:@"/tmp/sync-b-%@", unique] isDirectory:YES];

    // Setting a width persists it as the global seed; don't leave the running
    // user's preference changed.
    self.savedWidthDefault = [[NSUserDefaults standardUserDefaults]
        objectForKey:kMPSidebarWidthDefaultsKey];
}

- (void)tearDown
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (self.savedWidthDefault)
        [defaults setObject:self.savedWidthDefault
                     forKey:kMPSidebarWidthDefaultsKey];
    else
        [defaults removeObjectForKey:kMPSidebarWidthDefaultsKey];
    self.savedWidthDefault = nil;
    [super tearDown];
}

- (void)testWidthIsClampedToRange
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:5000 forRoot:self.rootA source:self];
    XCTAssertLessThanOrEqual([c sidebarWidthForRoot:self.rootA], 420.0);
    [c setSidebarWidth:10 forRoot:self.rootA source:self];
    XCTAssertGreaterThanOrEqual([c sidebarWidthForRoot:self.rootA], 150.0);
}

- (void)testEqualWidthDoesNotNotify
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:250 forRoot:self.rootA source:self];
    __block NSInteger count = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) { count++; }];
    // equal → no broadcast (breaks the loop)
    [c setSidebarWidth:250 forRoot:self.rootA source:self];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(count, 0);
    XCTAssertEqualWithAccuracy([c sidebarWidthForRoot:self.rootA], 250.0, 0.5);
}

- (void)testChangedWidthNotifiesWithKindAndRoot
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:200 forRoot:self.rootA source:self];
    id token = [NSObject new];
    XCTestExpectation *e = [self expectationWithDescription:@"notified"];
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:token
                     queue:nil usingBlock:^(NSNotification *n) {
            XCTAssertEqualObjects(n.userInfo[MPSidebarSyncKindKey],
                                  MPSidebarSyncKindWidth);
            XCTAssertEqualObjects(n.userInfo[MPSidebarSyncRootKey], self.rootA);
            [e fulfill];
        }];
    [c setSidebarWidth:321 forRoot:self.rootA source:token];
    [self waitForExpectations:@[e] timeout:1.0];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
}

- (void)testVisibleToggleNotifiesOnlyOnChange
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    XCTAssertTrue([c sidebarVisibleForRoot:self.rootA], @"defaults to visible");
    __block NSInteger count = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) {
            if ([n.userInfo[MPSidebarSyncKindKey]
                    isEqualToString:MPSidebarSyncKindVisible])
                count++;
        }];
    // no change → no notify
    [c setSidebarVisible:YES forRoot:self.rootA source:self];
    // change → notify
    [c setSidebarVisible:NO forRoot:self.rootA source:self];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(count, 1);
    XCTAssertFalse([c sidebarVisibleForRoot:self.rootA]);
}

#pragma mark - Per-workspace scoping

- (void)testWidthIsScopedPerRoot
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:200 forRoot:self.rootA source:self];
    [c setSidebarWidth:380 forRoot:self.rootB source:self];
    XCTAssertEqualWithAccuracy([c sidebarWidthForRoot:self.rootA], 200.0, 0.5);
    XCTAssertEqualWithAccuracy([c sidebarWidthForRoot:self.rootB], 380.0, 0.5,
                               @"resizing one workspace must not resize another");
}

- (void)testVisibilityIsScopedPerRoot
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarVisible:NO forRoot:self.rootA source:self];
    XCTAssertFalse([c sidebarVisibleForRoot:self.rootA]);
    XCTAssertTrue([c sidebarVisibleForRoot:self.rootB],
                  @"hiding one workspace's sidebar must not hide another's");
}

- (void)testWidthChangeOnlyNotifiesForItsOwnRoot
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:200 forRoot:self.rootA source:self];
    __block NSInteger forA = 0, forB = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) {
            if (![n.userInfo[MPSidebarSyncKindKey]
                     isEqualToString:MPSidebarSyncKindWidth])
                return;
            NSURL *root = n.userInfo[MPSidebarSyncRootKey];
            if ([root isEqual:self.rootA]) forA++;
            if ([root isEqual:self.rootB]) forB++;
        }];
    [c setSidebarWidth:345 forRoot:self.rootA source:self];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(forA, 1);
    XCTAssertEqual(forB, 0, @"an unrelated workspace must not be told to resize");
}

// An open workspace the user has never resized must keep its width when a
// different workspace is dragged: it has its own entry from the first read, so
// it stops tracking the global seed.
- (void)testUntouchedWorkspaceDoesNotFollowAnotherResize
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    // Both widths are stated outright rather than derived from whatever the
    // last run persisted: near the 150-420 clamp a relative delta collapses to
    // no change, and the assertion would then hold no matter what.
    [c setSidebarWidth:200 forRoot:self.rootA source:self];
    CGFloat before = [c sidebarWidthForRoot:self.rootB];   // never dragged
    XCTAssertEqualWithAccuracy(before, 200.0, 0.5,
                               @"a fresh workspace starts at the last width used");

    [c setSidebarWidth:400 forRoot:self.rootA source:self];
    XCTAssertEqualWithAccuracy([c sidebarWidthForRoot:self.rootB], 200.0, 0.5,
                               @"resizing one workspace must not move another "
                               @"that the user has not touched");
}

// A workspace seen for the first time opens at the last width the user chose,
// so new windows don't jump back to the built-in default.
- (void)testUnseenRootInheritsLastUsedWidth
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    [c setSidebarWidth:295 forRoot:self.rootA source:self];
    NSURL *fresh = [NSURL fileURLWithPath:
        [NSString stringWithFormat:@"/tmp/sync-fresh-%@",
            [NSProcessInfo processInfo].globallyUniqueString] isDirectory:YES];
    XCTAssertEqualWithAccuracy([c sidebarWidthForRoot:fresh], 295.0, 0.5);
}

- (void)testExpansionIsPerRootAndOrderIndependent
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    NSString *x = [self.rootA.path stringByAppendingPathComponent:@"x"];
    NSString *y = [self.rootA.path stringByAppendingPathComponent:@"y"];
    NSString *z = [self.rootB.path stringByAppendingPathComponent:@"z"];
    [c setExpandedPaths:@[x, y] forRoot:self.rootA source:self];
    [c setExpandedPaths:@[z] forRoot:self.rootB source:self];

    XCTAssertEqualObjects([NSSet setWithArray:[c expandedPathsForRoot:self.rootA]],
                          ([NSSet setWithObjects:x, y, nil]));
    XCTAssertEqualObjects([c expandedPathsForRoot:self.rootB], @[z]);

    // Same set, different order → treated as no change.
    __block NSInteger count = 0;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *n) {
            if ([n.userInfo[MPSidebarSyncKindKey]
                    isEqualToString:MPSidebarSyncKindExpansion])
                count++;
        }];
    [c setExpandedPaths:@[y, x] forRoot:self.rootA source:self];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    XCTAssertEqual(count, 0);
}

#pragma mark - Tree change announcements

- (void)testFileSavedNotificationCarriesURL
{
    MPSidebarSyncCoordinator *c = [MPSidebarSyncCoordinator sharedCoordinator];
    NSURL *saved = [self.rootA URLByAppendingPathComponent:@"fresh.md"];
    id token = [NSObject new];
    XCTestExpectation *e = [self expectationWithDescription:@"notified"];
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:token
                     queue:nil usingBlock:^(NSNotification *n) {
            XCTAssertEqualObjects(n.userInfo[MPSidebarSyncKindKey],
                                  MPSidebarSyncKindTreeChanged);
            XCTAssertEqualObjects(n.userInfo[MPSidebarSyncURLKey], saved);
            [e fulfill];
        }];
    [c notifyFileSavedAtURL:saved source:token];
    [self waitForExpectations:@[e] timeout:1.0];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
}

@end
