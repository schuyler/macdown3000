//
//  MPUpdaterTests.m
//  MacDownTests
//
//  Sparkle 2 migration (issue #129): Info.plist configuration, updater
//  controller initialization, and channel mapping for pre-releases.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPPreferences.h"

// Test-local declaration of the SPUUpdaterDelegate channel method so this
// target does not need Sparkle headers/linkage (the framework is already
// loaded via the host app). Parameter is typed `id` on purpose; the selector
// and ABI match the real implementation in MPMainController.
@interface MPMainController (MPUpdaterTestHooks)
- (NSSet<NSString *> *)allowedChannelsForUpdater:(id)updater;
@end


@interface MPUpdaterTests : XCTestCase
@property (nonatomic, strong) MPMainController *controller;
@property (nonatomic, assign) BOOL originalPreReleaseSetting;
@end


@implementation MPUpdaterTests

- (void)setUp
{
    [super setUp];
    self.controller = [[MPMainController alloc] init];
    self.originalPreReleaseSetting =
        [MPPreferences sharedInstance].updateIncludesPreReleases;
}

- (void)tearDown
{
    [MPPreferences sharedInstance].updateIncludesPreReleases =
        self.originalPreReleaseSetting;
    [[MPPreferences sharedInstance] synchronize];
    self.controller = nil;
    [super tearDown];
}

#pragma mark - Info.plist configuration

// T1
- (void)testFeedURLIsConfiguredForStableAppcast
{
    NSString *feed =
        [NSBundle mainBundle].infoDictionary[@"SUFeedURL"];
    XCTAssertEqualObjects(
        feed, @"https://macdown.app/sparkle/macdown3000/stable/appcast.xml",
        @"SUFeedURL must point at the single stable appcast");
    XCTAssertEqualObjects([NSURL URLWithString:feed].scheme, @"https",
                          @"Sparkle requires an HTTPS feed");
}

// T2
- (void)testBetaFeedURLIsRetired
{
    XCTAssertNil([NSBundle mainBundle].infoDictionary[@"SUBetaFeedURL"],
                 @"Dual-feed mechanism is replaced by Sparkle 2 channels");
}

// T3
- (void)testDSASigningIsRetired
{
    XCTAssertNil([NSBundle mainBundle].infoDictionary[@"SUPublicDSAKeyFile"],
                 @"DSA signing is replaced by EdDSA (SUPublicEDKey)");
    XCTAssertNil([[NSBundle mainBundle] pathForResource:@"dsa_pub"
                                                 ofType:@"pem"],
                 @"dsa_pub.pem must no longer ship in the bundle");
}

// T4 -- passes with the zero-key placeholder AND with the real key, but
// catches a missing, truncated, or non-base64 key.
- (void)testEdDSAPublicKeyIsPresentAndWellFormed
{
    NSString *key = [NSBundle mainBundle].infoDictionary[@"SUPublicEDKey"];
    XCTAssertNotNil(key, @"SUPublicEDKey missing from Info.plist");
    NSData *decoded =
        [[NSData alloc] initWithBase64EncodedString:key options:0];
    XCTAssertNotNil(decoded, @"SUPublicEDKey is not valid base64");
    XCTAssertEqual(decoded.length, (NSUInteger)32,
                   @"An ed25519 public key must decode to exactly 32 bytes");
}

#pragma mark - Updater controller initialization

// T5
- (void)testMainControllerOwnsAStandardUpdaterController
{
    XCTAssertNotNil(self.controller.updaterController,
                    @"MPMainController must create its updater at init");
    XCTAssertEqualObjects(
        NSStringFromClass([(id)self.controller.updaterController class]),
        @"SPUStandardUpdaterController",
        @"Updater must be Sparkle 2's SPUStandardUpdaterController");
}

// T6 -- regression test for the D2/D5 guard: under XCTest the updater is
// created but never started, so tests stay deterministic (no timers,
// network, or permission prompts). An unstarted updater reports
// canCheckForUpdates == NO. This must exercise the REAL app delegate
// (NSApp.delegate, as T9 below does), not a manually-alloc'd controller --
// a manually-alloc'd instance never receives -applicationDidFinishLaunching:,
// so its updater is never even reached by the MPUpdaterDisabled() guard, and
// the assertion would pass whether or not that guard exists at all. The real
// delegate, by contrast, genuinely receives -applicationDidFinishLaunching:
// during this hosted test run, so this pins the guard's actual effect.
- (void)testUpdaterIsNotStartedUnderXCTest
{
    // KVC, not dot syntax: updaterController's static type
    // (SPUStandardUpdaterController) is only forward-declared in
    // MPMainController.h, and this file deliberately avoids importing
    // Sparkle headers (see the class-extension comment above).
    MPMainController *delegate = (MPMainController *)NSApp.delegate;
    id updaterController = delegate.updaterController;
    id updater = [updaterController valueForKey:@"updater"];
    BOOL canCheckForUpdates =
        [[updater valueForKey:@"canCheckForUpdates"] boolValue];
    XCTAssertFalse(canCheckForUpdates,
                   @"canCheckForUpdates must be NO before startUpdater");
}

#pragma mark - Channel mapping (updateIncludesPreReleases -> allowed channels)

// T7
- (void)testAllowedChannelsIncludesBetaWhenPreReleasesEnabled
{
    [MPPreferences sharedInstance].updateIncludesPreReleases = YES;
    NSSet<NSString *> *channels =
        [self.controller allowedChannelsForUpdater:nil];
    XCTAssertEqualObjects(channels, [NSSet setWithObject:@"beta"],
                          @"Opting in must expose exactly the beta channel");
}

// T8
- (void)testAllowedChannelsIsEmptyWhenPreReleasesDisabled
{
    [MPPreferences sharedInstance].updateIncludesPreReleases = NO;
    NSSet<NSString *> *channels =
        [self.controller allowedChannelsForUpdater:nil];
    XCTAssertNotNil(channels,
                    @"Delegate must return an empty set, not nil");
    XCTAssertEqual(channels.count, (NSUInteger)0,
                   @"Default (stable) channel only when opted out");
}

#pragma mark - Menu wiring (MainMenu.xib)

// T9 -- hosted tests run inside the real app, so NSApp.mainMenu is the
// menu loaded from MainMenu.xib and NSApp.delegate is the xib-instantiated
// MPMainController (object eq0-c4-vgQ).
- (void)testCheckForUpdatesMenuItemIsWiredToMainController
{
    NSMenu *appMenu = [[NSApp.mainMenu itemAtIndex:0] submenu];
    NSMenuItem *updateItem = nil;
    for (NSMenuItem *item in appMenu.itemArray)
    {
        if (item.action == @selector(checkForUpdates:))
        {
            updateItem = item;
            break;
        }
    }
    XCTAssertNotNil(updateItem,
                    @"Application menu must contain a Check for Updates item "
                    @"with action checkForUpdates:");
    XCTAssertTrue(updateItem.target == NSApp.delegate,
                  @"Menu item must target MPMainController (eq0-c4-vgQ)");
    XCTAssertFalse([updateItem.title containsString:@"unavailable"],
                   @"Placeholder title must be gone");
}

@end
