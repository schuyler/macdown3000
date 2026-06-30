#import <XCTest/XCTest.h>
#import "MPFolderWatcher.h"

@interface MPFolderWatcherTests : XCTestCase
@property (strong) NSURL *root;
@end

@implementation MPFolderWatcherTests

- (void)setUp
{
    [super setUp];
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                 URLByAppendingPathComponent:unique isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.root
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
    self.root = nil;
    [super tearDown];
}

- (void)testWatchesLocalTempDirectory
{
    MPFolderWatcher *watcher =
        [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{ }];
    XCTAssertTrue(watcher.isWatching,
                  @"a local temp dir should be watchable");
    [watcher stop];
    XCTAssertFalse(watcher.isWatching);
}

- (void)testStopIsIdempotentAndNoCrash
{
    MPFolderWatcher *watcher =
        [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{ }];
    XCTAssertNoThrow([watcher stop]);
    XCTAssertNoThrow([watcher stop]);
}

- (void)testFiresHandlerOnFileCreation
{
    XCTestExpectation *changed =
        [self expectationWithDescription:@"handler fired"];
    __block BOOL fulfilled = NO;
    MPFolderWatcher *watcher =
        [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{
            if (!fulfilled) { fulfilled = YES; [changed fulfill]; }
        }];
    // Give the stream a moment to arm, then create a file.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSURL *f = [self.root URLByAppendingPathComponent:@"new.md"];
        [@"# hi" writeToURL:f atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    });
    [self waitForExpectations:@[changed] timeout:5.0];
    [watcher stop];
}

@end
