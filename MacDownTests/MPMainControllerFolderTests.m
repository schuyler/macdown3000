// CLI handoff consumer tests. Run inside the suite's isolated HOME/preferences
// vault: real MPDocuments load their nibs and the application preferences.
#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPPreferences.h"
#import "MPDocument.h"
#import "MPGlobals.h"
#import "../macdown-cmd/MPCommandQueue.h"

@interface MPMainController (CommandTesting)
- (void)openPendingCommandRequests;
- (void)applyApplicationAppearance;
- (BOOL)migrateLegacyCommandRequests:(NSError **)error;
- (NSURL *)commandQueueDirectory;
- (NSString *)commandPreferencesSuiteName;
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls;
@end

// Only the launch policy is needed by Main. Avoid MPPreferences initialization,
// which would run migrations and initialize PAPreferences' shared metadata.
@interface MPCommandTestPreferences : MPPreferences
@property BOOL suppressUntitled;
@property NSInteger testAppearance;
@end
@implementation MPCommandTestPreferences
- (BOOL)supressesUntitledDocumentOnLaunch { return self.suppressUntitled; }
- (NSInteger)applicationAppearance { return self.testAppearance; }
@end

@interface MPCommandTestController : MPMainController
@property (strong) NSURL *testQueueDirectory;
@property (copy) NSString *testSuiteName;
@property (strong) MPCommandTestPreferences *testPreferences;
@end
@implementation MPCommandTestController
- (MPPreferences *)preferences
{
    if (!self.testPreferences) self.testPreferences = [MPCommandTestPreferences alloc];
    return self.testPreferences;
}
- (NSURL *)commandQueueDirectory { return self.testQueueDirectory; }
- (NSString *)commandPreferencesSuiteName { return self.testSuiteName; }
- (void)copyFiles {} // Fixtures must never prune/copy the user's support files.
@end

@interface MPMainControllerFolderTests : XCTestCase
@property (strong) MPCommandTestController *controller;
@property (strong) NSURL *temporaryDirectory;
@property (strong) NSArray *originalDocuments;
@end

@implementation MPMainControllerFolderTests
- (void)setUp
{
    [super setUp];
    XCTAssertTrue(NSThread.isMainThread);
    self.temporaryDirectory = [NSURL fileURLWithPath:[NSTemporaryDirectory()
        stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:self.temporaryDirectory
        withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]);
    self.originalDocuments = [[NSDocumentController sharedDocumentController].documents copy];
    self.controller = [[MPCommandTestController alloc] init];
    self.controller.testQueueDirectory = [self.temporaryDirectory URLByAppendingPathComponent:@"queue"];
    self.controller.testSuiteName = [@"audit.commands." stringByAppendingString:NSUUID.UUID.UUIDString];
}

- (void)testAppearanceCanBeForcedAndReturnToSystem
{
    NSAppearance *original = NSApp.appearance;
    @try {
        self.controller.testPreferences.testAppearance = 2;
        [self.controller applyApplicationAppearance];
        XCTAssertEqualObjects(NSApp.appearance.name, NSAppearanceNameDarkAqua);
        self.controller.testPreferences.testAppearance = 1;
        [self.controller applyApplicationAppearance];
        XCTAssertEqualObjects(NSApp.appearance.name, NSAppearanceNameAqua);
        self.controller.testPreferences.testAppearance = 0;
        [self.controller applyApplicationAppearance];
        XCTAssertNil(NSApp.appearance);
        self.controller.testPreferences.testAppearance = 999;
        [self.controller applyApplicationAppearance];
        XCTAssertNil(NSApp.appearance);
    } @finally { NSApp.appearance = original; }
}

- (void)tearDown
{
    // Only close documents created by this test, with no save prompt.
    for (NSDocument *document in [self openedDocuments]) {
        [document updateChangeCount:NSChangeCleared];
        [document close];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self.controller];
    CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)@[kMPFilesToOpenKey,
        kMPFoldersToOpenKey, kMPPipedContentFileToOpen],
        (__bridge CFStringRef)self.controller.testSuiteName,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)self.controller.testSuiteName,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    [[NSFileManager defaultManager] removeItemAtURL:self.temporaryDirectory error:NULL];
    self.controller = nil;
    [super tearDown];
}

- (NSArray<MPDocument *> *)openedDocuments
{
    NSMutableArray *created = [NSMutableArray array];
    for (NSDocument *document in [NSDocumentController sharedDocumentController].documents)
        if (![self.originalDocuments containsObject:document]) [created addObject:document];
    return created;
}

- (NSURL *)folderNamed:(NSString *)name
{
    NSURL *url = [self.temporaryDirectory URLByAppendingPathComponent:name isDirectory:YES];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:url
        withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]);
    return url;
}

- (void)enqueueFiles:(NSArray *)files folders:(NSArray *)folders text:(NSString *)text
{
    NSMutableDictionary *request = [@{@"files":files, @"folders":folders} mutableCopy];
    if (text) request[@"pipedContent"] = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    XCTAssertTrue(MPCommandQueueEnqueue(self.controller.testQueueDirectory, request, &error), @"%@", error);
}

- (void)setLegacyValue:(id)value key:(NSString *)key
{
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)self.controller.testSuiteName,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    XCTAssertTrue(CFPreferencesSynchronize((__bridge CFStringRef)self.controller.testSuiteName,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}

- (id)legacyValueForKey:(NSString *)key
{
    return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key,
        (__bridge CFStringRef)self.controller.testSuiteName,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}

- (void)testPendingFolderSuppressesUntitledWithoutConsumingRequest
{
    [self enqueueFiles:@[] folders:@[[self folderNamed:@"workspace"].path] text:nil];
    XCTAssertFalse([self.controller applicationShouldOpenUntitledFile:NSApp]);
    XCTAssertEqual(MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL).count, 1u);
    XCTAssertEqual(self.openedDocuments.count, 0u);
}

- (void)testEmptyLegacyArraysDoNotSuppressUntitledAndPreferenceStillApplies
{
    [self setLegacyValue:@[] key:kMPFilesToOpenKey];
    [self setLegacyValue:@[] key:kMPFoldersToOpenKey];
    XCTAssertTrue([self.controller applicationShouldOpenUntitledFile:NSApp]);
    self.controller.testPreferences.suppressUntitled = YES;
    XCTAssertFalse([self.controller applicationShouldOpenUntitledFile:NSApp]);
}

- (void)testActivationConsumesEveryWorkspaceAndPipeThenReopenConsumesNewRequestOnce
{
    NSURL *first = [self folderNamed:@"first"], *second = [self folderNamed:@"second"];
    [self enqueueFiles:@[] folders:@[first.path] text:@"first pipe é\n"];
    [self enqueueFiles:@[] folders:@[second.path] text:@"second pipe 日本語\n"];
    [self.controller applicationDidBecomeActive:nil];
    NSArray *documents = self.openedDocuments;
    XCTAssertEqual(documents.count, 4u);
    NSMutableSet *roots = [NSMutableSet set], *texts = [NSMutableSet set];
    for (MPDocument *document in documents) {
        if (document.workspaceRootURL) {
            [roots addObject:document.workspaceRootURL.path];
            XCTAssertGreaterThan(document.windowControllers.count, 0u);
            XCTAssertNotNil([document.windowControllers.firstObject window]);
        } else [texts addObject:document.markdown ?: @""];
    }
    XCTAssertEqualObjects(roots, ([NSSet setWithArray:@[first.URLByResolvingSymlinksInPath.path,
                                                       second.URLByResolvingSymlinksInPath.path]]));
    XCTAssertEqualObjects(texts, ([NSSet setWithArray:@[@"first pipe é\n", @"second pipe 日本語\n"]]));
    XCTAssertEqual(MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL).count, 0u);
    [self enqueueFiles:@[] folders:@[] text:@"reopened while already active"];
    XCTAssertTrue([self.controller applicationShouldHandleReopen:NSApp hasVisibleWindows:YES]);
    XCTAssertEqual(self.openedDocuments.count, 5u);
    XCTAssertTrue([[self.openedDocuments valueForKey:@"markdown"] containsObject:@"reopened while already active"]);
    [self.controller applicationDidBecomeActive:nil];
    [self.controller applicationShouldHandleReopen:NSApp hasVisibleWindows:YES];
    XCTAssertEqual(self.openedDocuments.count, 5u, @"drained commands must not reopen documents");
}

- (void)testMissingFolderDoesNotDiscardOtherCommandsInTheBatch
{
    NSString *missing = [self.temporaryDirectory URLByAppendingPathComponent:@"missing"].path;
    [self enqueueFiles:@[] folders:@[missing] text:@"pipe beside missing folder"];
    [self.controller openPendingCommandRequests];
    XCTAssertEqual(self.openedDocuments.count, 1u);
    XCTAssertEqualObjects(self.openedDocuments.firstObject.markdown, @"pipe beside missing folder");
    XCTAssertNil(self.openedDocuments.firstObject.workspaceRootURL);
    XCTAssertEqual(MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL).count, 0u);
}

- (void)testExistingFileIsOpenedWithItsActualContent
{
    NSURL *file = [self.temporaryDirectory URLByAppendingPathComponent:@"actual.md"];
    XCTAssertTrue([@"# actual file\n" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    [self enqueueFiles:@[file.path] folders:@[] text:nil];
    [self.controller applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
    NSPredicate *opened = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        for (MPDocument *document in self.openedDocuments)
            if ([document.fileURL.URLByResolvingSymlinksInPath isEqual:file.URLByResolvingSymlinksInPath]
                && [document.markdown isEqualToString:@"# actual file\n"]) return YES;
        return NO;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:opened object:self];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:5], XCTWaiterResultCompleted);
    XCTAssertEqual(self.openedDocuments.count, 1u);
}

- (void)testFinderOpenURLsRoutesFoldersAndFilesToTheirExistingConsumers
{
    SEL action = @selector(application:openURLs:);
    XCTAssertTrue([self.controller respondsToSelector:action],
                  @"Finder folder drops need an application URL handler");
    if (![self.controller respondsToSelector:action]) return;
    NSURL *first = [self folderNamed:@"Finder workspace é"];
    NSURL *second = [self folderNamed:@"second"];
    NSURL *file = [self.temporaryDirectory URLByAppendingPathComponent:@"actual.md"];
    XCTAssertTrue([@"# Finder file\n" writeToURL:file atomically:YES
                                    encoding:NSUTF8StringEncoding error:NULL]);
    [self.controller application:NSApp openURLs:@[first, file, second]];
    XCTNSPredicateExpectation *opened = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,
                                                               NSDictionary *bindings) {
            return self.openedDocuments.count == 3;
        }] object:self];
    [self waitForExpectations:@[opened] timeout:5];
    NSMutableSet *roots = [NSMutableSet set];
    NSUInteger files = 0;
    for (MPDocument *document in self.openedDocuments) {
        if (document.workspaceRootURL) {
            [roots addObject:document.workspaceRootURL.path];
            XCTAssertNil(document.fileURL);
            XCTAssertGreaterThan(document.windowControllers.count, 0u);
        } else {
            files++;
            XCTAssertEqualObjects(document.markdown, @"# Finder file\n");
            XCTAssertEqualObjects(document.fileURL.URLByResolvingSymlinksInPath,
                                  file.URLByResolvingSymlinksInPath);
        }
    }
    XCTAssertEqual(files, 1u);
    XCTAssertEqualObjects(roots, ([NSSet setWithArray:@[
        first.URLByResolvingSymlinksInPath.path,
        second.URLByResolvingSymlinksInPath.path]]));
}

- (void)testLegacyMigrationUsesSameConsumerAndIsNotRepeated
{
    NSURL *folder = [self folderNamed:@"legacy"];
    NSURL *pipe = [self.temporaryDirectory URLByAppendingPathComponent:@"legacy-pipe"];
    NSData *bytes = [@"legacy pipe\n" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([bytes writeToURL:pipe options:NSDataWritingAtomic error:NULL]);
    [self setLegacyValue:@[] key:kMPFilesToOpenKey];
    [self setLegacyValue:@[folder.path] key:kMPFoldersToOpenKey];
    [self setLegacyValue:pipe.path key:kMPPipedContentFileToOpen];
    NSError *error = nil;
    XCTAssertTrue([self.controller migrateLegacyCommandRequests:&error], @"%@", error);
    NSArray *pending = MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL);
    XCTAssertEqual(pending.count, 1u);
    XCTAssertEqualObjects([pending.firstObject objectForKey:@"pipedContent"], bytes);
    for (NSString *key in @[kMPFilesToOpenKey, kMPFoldersToOpenKey, kMPPipedContentFileToOpen])
        XCTAssertNil([self legacyValueForKey:key]);
    XCTAssertTrue([self.controller migrateLegacyCommandRequests:&error]);
    XCTAssertEqual(MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL).count, 1u);
    [self.controller openPendingCommandRequests];
    XCTAssertEqual(self.openedDocuments.count, 2u);
    XCTAssertTrue([[self.openedDocuments valueForKey:@"markdown"] containsObject:@"legacy pipe\n"]);
    XCTAssertEqualObjects([[self.openedDocuments valueForKey:@"workspaceRootURL"] filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id value, NSDictionary *bindings) { return [value isKindOfClass:NSURL.class]; }]],
        (@[folder.URLByResolvingSymlinksInPath]));
}

- (void)testFailedLegacyMigrationPreservesKeysAndCorruptQueue
{
    [self setLegacyValue:@[[self folderNamed:@"retained"].path] key:kMPFoldersToOpenKey];
    XCTAssertNotNil(MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL));
    NSURL *file = [self.controller.testQueueDirectory URLByAppendingPathComponent:@"requests.plist"];
    NSData *corrupt = [@"not a plist" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([corrupt writeToURL:file options:NSDataWritingAtomic error:NULL]);
    NSError *error = nil;
    XCTAssertFalse([self.controller migrateLegacyCommandRequests:&error]);
    XCTAssertNotNil(error);
    XCTAssertNotNil([self legacyValueForKey:kMPFoldersToOpenKey]);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:file], corrupt);
    XCTAssertEqual(self.openedDocuments.count, 0u);
    // A failed attempt must not mark the per-process migration as completed.
    XCTAssertTrue(MPCommandQueueSave(@[], file, &error));
    XCTAssertTrue([self.controller migrateLegacyCommandRequests:&error], @"%@", error);
    XCTAssertNil([self legacyValueForKey:kMPFoldersToOpenKey]);
    XCTAssertEqual(MPCommandQueueReadPending(self.controller.testQueueDirectory, NULL).count, 1u);
}
@end
