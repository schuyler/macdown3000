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

// The stream is created with kFSEventStreamCreateFlagIgnoreSelf, so a file
// written by THIS process is deliberately not reported. Use an external process
// to produce a change the stream should see.
- (void)createFileExternallyNamed:(NSString *)name
{
    NSURL *f = [self.root URLByAppendingPathComponent:name];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/touch"];
    task.arguments = @[f.path];
    XCTAssertTrue([task launchAndReturnError:NULL], @"could not launch touch");
    [task waitUntilExit];
}

- (void)testFiresHandlerOnExternalFileCreation
{
    XCTestExpectation *changed =
        [self expectationWithDescription:@"handler fired"];
    __block BOOL fulfilled = NO;
    MPFolderWatcher *watcher =
        [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{
            if (!fulfilled) { fulfilled = YES; [changed fulfill]; }
        }];
    // Give the stream a moment to arm, then create a file from another process.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self createFileExternallyNamed:@"new.md"];
    });
    [self waitForExpectations:@[changed] timeout:10.0];
    [watcher stop];
}

// Guards the reload-storm fix: MacDown's own saves inside a watched folder must
// not re-trigger the sidebar reload.
- (void)testDoesNotFireForWritesFromThisProcess
{
    XCTestExpectation *changed =
        [self expectationWithDescription:@"handler must not fire"];
    changed.inverted = YES;
    MPFolderWatcher *watcher =
        [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{
            [changed fulfill];
        }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        for (int i = 0; i < 5; i++)
        {
            NSString *name = [NSString stringWithFormat:@"self-%d.md", i];
            NSURL *f = [self.root URLByAppendingPathComponent:name];
            [@"# hi" writeToURL:f atomically:YES
                       encoding:NSUTF8StringEncoding error:NULL];
        }
    });
    [self waitForExpectations:@[changed] timeout:3.0];
    [watcher stop];
}

// The stream must deliver on the main queue: that is what serializes callbacks
// with -stop and with the sidebar reload they drive.
- (void)testHandlerRunsOnMainQueue
{
    XCTestExpectation *changed =
        [self expectationWithDescription:@"handler fired"];
    __block BOOL fulfilled = NO;
    __block BOOL onMain = NO;
    MPFolderWatcher *watcher =
        [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{
            if (fulfilled)
                return;
            fulfilled = YES;
            onMain = [NSThread isMainThread];
            [changed fulfill];
        }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self createFileExternallyNamed:@"main-queue.md"];
    });
    [self waitForExpectations:@[changed] timeout:10.0];
    XCTAssertTrue(onMain, @"FSEvents callbacks must arrive on the main queue");
    [watcher stop];
}

// After -stop the handler must never run again, even if the watcher itself is
// gone: the stream retains an internal target, not the watcher.
- (void)testHandlerNeverRunsAfterStopOrDealloc
{
    XCTestExpectation *changed =
        [self expectationWithDescription:@"handler must not fire"];
    changed.inverted = YES;
    @autoreleasepool {
        MPFolderWatcher *watcher =
            [[MPFolderWatcher alloc] initWithRootURL:self.root handler:^{
                [changed fulfill];
            }];
        [watcher stop];
    }
    [self createFileExternallyNamed:@"after-stop.md"];
    [self waitForExpectations:@[changed] timeout:2.0];
}

@end
