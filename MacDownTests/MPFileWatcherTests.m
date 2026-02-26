//
//  MPFileWatcherTests.m
//  MacDownTests
//
//  Tests for MPFileWatcher - single-file dispatch source watcher.
//  Related to GitHub issue #110.
//

#import <XCTest/XCTest.h>
#import "MPFileWatcher.h"

@interface MPFileWatcherTests : XCTestCase
@property (strong) NSString *testDirectory;
@property (strong) NSFileManager *fileManager;
@end

@implementation MPFileWatcherTests

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
}

- (void)tearDown
{
    if (self.testDirectory)
        [self.fileManager removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (NSString *)createTestFileWithName:(NSString *)name content:(NSString *)content
{
    NSString *path = [self.testDirectory stringByAppendingPathComponent:name];
    [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

#pragma mark - Initialization

- (void)testInitWithValidPath
{
    NSString *path = [self createTestFileWithName:@"test.txt" content:@"hello"];
    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
                                                         handler:^(NSString *p) {}
                                                   cancelHandler:^(NSString *p) {}];
    XCTAssertTrue(watcher.isWatching);
    XCTAssertEqualObjects(watcher.path, path);
    [watcher stopWatching];
}

- (void)testInitWithNonexistentPath
{
    NSString *path = [self.testDirectory stringByAppendingPathComponent:@"nope.txt"];
    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
                                                         handler:^(NSString *p) {}
                                                   cancelHandler:^(NSString *p) {}];
    XCTAssertFalse(watcher.isWatching);
    XCTAssertNil(watcher.path);
}

- (void)testInitWithNilPath
{
    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:nil
                                                         handler:^(NSString *p) {}
                                                   cancelHandler:^(NSString *p) {}];
    XCTAssertFalse(watcher.isWatching);
    XCTAssertNil(watcher.path);
}

#pragma mark - Event Handling

- (void)testHandlerCalledOnFileWrite
{
    NSString *path = [self createTestFileWithName:@"watched.txt" content:@"initial"];
    XCTestExpectation *exp = [self expectationWithDescription:@"handler called"];

    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
        handler:^(NSString *p) {
            XCTAssertEqualObjects(p, path);
            [exp fulfill];
        }
        cancelHandler:^(NSString *p) {}];

    // Modify the file after a short delay to ensure watcher is active
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [@"modified" writeToFile:path atomically:NO
                        encoding:NSUTF8StringEncoding error:nil];
    });

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    [watcher stopWatching];
}

#pragma mark - Stop Watching

- (void)testStopWatching
{
    NSString *path = [self createTestFileWithName:@"stop.txt" content:@"data"];
    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
                                                         handler:^(NSString *p) {}
                                                   cancelHandler:^(NSString *p) {}];
    XCTAssertTrue(watcher.isWatching);
    [watcher stopWatching];
    XCTAssertFalse(watcher.isWatching);
    XCTAssertNil(watcher.path);
}

- (void)testStopWatchingMultipleTimesIsSafe
{
    NSString *path = [self createTestFileWithName:@"multi.txt" content:@"data"];
    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
                                                         handler:^(NSString *p) {}
                                                   cancelHandler:^(NSString *p) {}];
    [watcher stopWatching];
    XCTAssertNoThrow([watcher stopWatching]);
    XCTAssertNoThrow([watcher stopWatching]);
}

- (void)testNoHandlerAfterStop
{
    NSString *path = [self createTestFileWithName:@"nosignal.txt" content:@"data"];
    __block BOOL handlerCalled = NO;

    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
        handler:^(NSString *p) {
            handlerCalled = YES;
        }
        cancelHandler:^(NSString *p) {}];

    [watcher stopWatching];

    // Modify after stop
    [@"changed" writeToFile:path atomically:NO
                   encoding:NSUTF8StringEncoding error:nil];

    // Run the run loop briefly to allow any pending events
    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.5]];

    XCTAssertFalse(handlerCalled);
}

#pragma mark - File Deletion

- (void)testCancelHandlerOnFileDelete
{
    NSString *path = [self createTestFileWithName:@"deleteme.txt" content:@"data"];
    XCTestExpectation *exp = [self expectationWithDescription:@"cancel on delete"];

    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
        handler:^(NSString *p) {}
        cancelHandler:^(NSString *p) {
            XCTAssertEqualObjects(p, path);
            [exp fulfill];
        }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.fileManager removeItemAtPath:path error:nil];
    });

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertFalse(watcher.isWatching);
}

#pragma mark - Dealloc Cleanup

- (void)testDeallocStopsWatching
{
    NSString *path = [self createTestFileWithName:@"dealloc.txt" content:@"data"];
    __block BOOL handlerCalled = NO;

    @autoreleasepool {
        __unused MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
            handler:^(NSString *p) {
                handlerCalled = YES;
            }
            cancelHandler:^(NSString *p) {}];
        // watcher goes out of scope here
    }

    [@"changed" writeToFile:path atomically:NO
                   encoding:NSUTF8StringEncoding error:nil];

    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.5]];

    XCTAssertFalse(handlerCalled);
}

@end
