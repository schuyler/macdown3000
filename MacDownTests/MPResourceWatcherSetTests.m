//
//  MPResourceWatcherSetTests.m
//  MacDownTests
//
//  Tests for MPResourceWatcherSet.
//  Related to GitHub issue #110.
//

#import <XCTest/XCTest.h>
#import "MPResourceWatcherSet.h"

@interface MPResourceWatcherSetTests : XCTestCase <MPResourceWatcherSetDelegate>
@property (strong) MPResourceWatcherSet *watcherSet;
@property (strong) NSString *testDirectory;
@property (strong) NSFileManager *fileManager;
@property (strong) NSMutableArray<NSString *> *changedPaths;
@property (strong) XCTestExpectation *changeExpectation;
@end

@implementation MPResourceWatcherSetTests

- (void)setUp
{
    [super setUp];
    self.fileManager = [NSFileManager defaultManager];
    NSString *tempDir = NSTemporaryDirectory();
    self.testDirectory = [tempDir stringByAppendingPathComponent:
                          [[NSUUID UUID] UUIDString]];
    [self.fileManager createDirectoryAtPath:self.testDirectory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
    self.changedPaths = [NSMutableArray array];
    self.watcherSet = [[MPResourceWatcherSet alloc] init];
    self.watcherSet.delegate = self;
}

- (void)tearDown
{
    [self.watcherSet stopAll];
    if (self.testDirectory)
        [self.fileManager removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (NSString *)createTestFileWithName:(NSString *)name
{
    NSString *path = [self.testDirectory stringByAppendingPathComponent:name];
    [@"content" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

#pragma mark - MPResourceWatcherSetDelegate

- (void)resourceWatcherSet:(MPResourceWatcherSet *)set
    didDetectChangeAtPath:(NSString *)path
{
    [self.changedPaths addObject:path];
    if (self.changeExpectation)
        [self.changeExpectation fulfill];
}

#pragma mark - Tests

- (void)testInitiallyEmpty
{
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 0u);
}

- (void)testUpdateAddsWatchers
{
    NSString *path1 = [self createTestFileWithName:@"a.png"];
    NSString *path2 = [self createTestFileWithName:@"b.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithArray:@[path1, path2]]];
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 2u);
    XCTAssertTrue([self.watcherSet.watchedPaths containsObject:path1]);
    XCTAssertTrue([self.watcherSet.watchedPaths containsObject:path2]);
}

- (void)testUpdateRemovesStaleWatchers
{
    NSString *path1 = [self createTestFileWithName:@"a.png"];
    NSString *path2 = [self createTestFileWithName:@"b.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithArray:@[path1, path2]]];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path1]];
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 1u);
    XCTAssertTrue([self.watcherSet.watchedPaths containsObject:path1]);
    XCTAssertFalse([self.watcherSet.watchedPaths containsObject:path2]);
}

- (void)testUpdateKeepsExistingWatchers
{
    NSString *path = [self createTestFileWithName:@"keep.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 1u);
}

- (void)testUpdateWithEmptySetRemovesAll
{
    NSString *path = [self createTestFileWithName:@"remove.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];
    [self.watcherSet updateWatchedPaths:[NSSet set]];
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 0u);
}

- (void)testSkipsNonexistentFiles
{
    NSString *path = [self.testDirectory stringByAppendingPathComponent:@"nope.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 0u);
}

- (void)testDelegateCalledOnChange
{
    NSString *path = [self createTestFileWithName:@"watch.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];

    self.changeExpectation = [self expectationWithDescription:@"delegate called"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [@"modified" writeToFile:path atomically:NO
                        encoding:NSUTF8StringEncoding error:nil];
    });

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertTrue([self.changedPaths containsObject:path]);
}

- (void)testStopAll
{
    NSString *path1 = [self createTestFileWithName:@"x.png"];
    NSString *path2 = [self createTestFileWithName:@"y.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithArray:@[path1, path2]]];
    [self.watcherSet stopAll];
    XCTAssertEqual(self.watcherSet.watchedPaths.count, 0u);
}

- (void)testStopAllMultipleTimesIsSafe
{
    NSString *path = [self createTestFileWithName:@"safe.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];
    XCTAssertNoThrow([self.watcherSet stopAll]);
    XCTAssertNoThrow([self.watcherSet stopAll]);
}

// Tests for GitHub issue #349: atomic-save recovery and initial timestamp seeding.

- (void)testDelegateCalledOnAtomicSave
{
    // Create the watched file and register it.
    NSString *path = [self createTestFileWithName:@"atomic.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];

    self.changeExpectation = [self expectationWithDescription:@"delegate called after atomic save"];

    // After a short delay, simulate an atomic save: write to a temp file then
    // rename it over the watched path. This is exactly what editors like vim
    // and many frameworks do — it fires RENAME/DELETE on the original inode.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *tempPath = [self.testDirectory
                              stringByAppendingPathComponent:@"atomic.png.tmp"];
        [@"updated content" writeToFile:tempPath
                             atomically:NO
                               encoding:NSUTF8StringEncoding
                                  error:nil];
        [self.fileManager moveItemAtPath:tempPath toPath:path error:nil];
    });

    // 2.0s timeout: atomic save fires at 0.1s, recovery has a 300ms delay,
    // leaving over 1.6s of buffer.
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    XCTAssertTrue([self.changedPaths containsObject:path],
                  @"Delegate should have been called with the watched path after atomic save");
}

- (void)testWatcherReestablishedAfterAtomicSave
{
    // Create the watched file and register it.
    NSString *path = [self createTestFileWithName:@"rewatch.png"];
    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];

    // Phase 1: simulate an atomic save and wait for the recovery notification.
    self.changeExpectation = [self expectationWithDescription:@"first notification: atomic save recovery"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *tempPath = [self.testDirectory
                              stringByAppendingPathComponent:@"rewatch.png.tmp"];
        [@"updated content" writeToFile:tempPath
                             atomically:NO
                               encoding:NSUTF8StringEncoding
                                  error:nil];
        [self.fileManager moveItemAtPath:tempPath toPath:path error:nil];
    });

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // Phase 2: perform a direct (non-atomic) write and verify the watcher
    // fires again, proving it was re-established after recovery.
    self.changeExpectation = [self expectationWithDescription:@"second notification: direct write after recovery"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [@"second update" writeToFile:path
                           atomically:NO
                             encoding:NSUTF8StringEncoding
                                error:nil];
    });

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // changedPaths accumulates across both phases; path should appear at least twice.
    NSUInteger count = [[self.changedPaths filteredArrayUsingPredicate:
                         [NSPredicate predicateWithFormat:@"SELF == %@", path]] count];
    XCTAssertGreaterThanOrEqual(count, 2u,
        @"Watcher should have fired at least twice — once on recovery, once on subsequent write");
}

- (void)testDelegateSeededOnNewWatcher
{
    // Create the file BEFORE setting up any watcher.
    NSString *path = [self createTestFileWithName:@"seed.png"];

    // Expect the delegate to be called when the watcher is first installed,
    // seeding the initial timestamp without waiting for a file change.
    self.changeExpectation = [self expectationWithDescription:@"delegate seeded on watcher installation"];

    [self.watcherSet updateWatchedPaths:[NSSet setWithObject:path]];

    // Notification should be synchronous or near-immediate — 1.0s is generous.
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertTrue([self.changedPaths containsObject:path],
                  @"Delegate should be called immediately when a new watcher is installed");
}

@end
