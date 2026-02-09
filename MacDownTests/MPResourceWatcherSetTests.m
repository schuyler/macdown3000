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

@end
