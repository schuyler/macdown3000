//
//  MPDocumentWorkspaceTests.m
//  MacDown 3000
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPSidebarSyncCoordinator.h"

@interface MPDocument (WorkspaceTesting)
- (IBAction)toggleFolderSidebar:(id)sender;
@end

/// MPDocument's -dataOfType: reads the editor text view, which only exists once
/// the window nib has loaded. Supplying the bytes directly leaves the rest of
/// the save path — -writeSafelyToURL:, -writeToURL: and the sidebar
/// announcement — exactly as it runs in the app.
@interface MPHeadlessSavingDocument : MPDocument
@end

@implementation MPHeadlessSavingDocument
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    return [@"# hello" dataUsingEncoding:NSUTF8StringEncoding];
}
- (void)makeWindowControllers { }
@end

@interface MPDocumentWorkspaceTests : XCTestCase
@property (strong) NSURL *dir;
@end

@implementation MPDocumentWorkspaceTests

- (void)setUp
{
    [super setUp];
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:unique isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.dir
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.dir error:NULL];
    self.dir = nil;
    [super tearDown];
}

- (void)testToggleSidebarDoesNotCrashWithoutWorkspace
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertNoThrow([doc toggleFolderSidebar:nil]);
}

- (void)testSidebarMenuItemDisabledWithoutWorkspace
{
    MPDocument *doc = [[MPDocument alloc] init];
    NSMenuItem *item = [[NSMenuItem alloc]
        initWithTitle:@"Show Sidebar"
               action:@selector(toggleFolderSidebar:) keyEquivalent:@"\\"];
    XCTAssertFalse([doc validateUserInterfaceItem:item],
                   @"sidebar toggle should be disabled when not a workspace");
}

- (void)testSidebarMenuItemEnabledWithWorkspace
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.workspaceRootURL = [NSURL fileURLWithPath:@"/tmp" isDirectory:YES];
    NSMenuItem *item = [[NSMenuItem alloc]
        initWithTitle:@"Show Sidebar"
               action:@selector(toggleFolderSidebar:) keyEquivalent:@"\\"];
    XCTAssertTrue([doc validateUserInterfaceItem:item]);
}

#pragma mark - Workspace identity

// One folder must be one workspace however it was reached, or two windows on
// the same directory silently stop sharing sidebar width, visibility and
// expansion. `macdown /tmp/proj` yields file:///tmp/proj/ while the Open Folder
// panel yields file:///private/tmp/proj/.
- (void)testWorkspaceRootIsStoredCanonicalised
{
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *name = [@"mp-workspace-" stringByAppendingString:unique];
    NSURL *viaTmp = [NSURL fileURLWithPath:
        [@"/tmp" stringByAppendingPathComponent:name] isDirectory:YES];
    NSURL *viaPrivate = [NSURL fileURLWithPath:
        [@"/private/tmp" stringByAppendingPathComponent:name] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:viaPrivate
        withIntermediateDirectories:YES attributes:nil error:NULL];

    MPDocument *a = [[MPDocument alloc] init];
    MPDocument *b = [[MPDocument alloc] init];
    a.workspaceRootURL = viaTmp;
    b.workspaceRootURL = viaPrivate;

    XCTAssertEqualObjects(a.workspaceRootURL.absoluteString,
                          b.workspaceRootURL.absoluteString,
                          @"the same folder reached two ways must be one workspace");

    [[NSFileManager defaultManager] removeItemAtURL:viaPrivate error:NULL];
}

- (void)testWorkspaceRootSurvivesAPathThatDoesNotExist
{
    MPDocument *doc = [[MPDocument alloc] init];
    NSURL *missing = [NSURL fileURLWithPath:@"/tmp/mp-does-not-exist-xyz"
                                isDirectory:YES];
    doc.workspaceRootURL = missing;
    XCTAssertNotNil(doc.workspaceRootURL,
                    @"an unresolvable path must not become nil");
}

- (void)testWorkspaceRootCanBeCleared
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.workspaceRootURL = [NSURL fileURLWithPath:@"/tmp" isDirectory:YES];
    doc.workspaceRootURL = nil;
    XCTAssertNil(doc.workspaceRootURL);
}

#pragma mark - Announcing files MacDown itself creates

// The folder watcher runs with kFSEventStreamCreateFlagIgnoreSelf, so a file
// MacDown writes is invisible to it. These drive a real save through
// NSDocument, which hands -writeToURL: a temp path inside an
// NSItemReplacementDirectory and swaps it into place — so a test that only
// called the coordinator directly would not notice the announcement breaking.

/// Saves `doc` to `url` and returns the URL announced to sidebars, if any.
- (NSURL *)announcedURLWhileSaving:(MPDocument *)doc
                             toURL:(NSURL *)url
                         operation:(NSSaveOperationType)operation
{
    __block NSURL *announced = nil;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:MPSidebarSyncDidChangeNotification object:nil
                     queue:nil usingBlock:^(NSNotification *note) {
            if ([note.userInfo[MPSidebarSyncKindKey]
                    isEqualToString:MPSidebarSyncKindTreeChanged])
                announced = note.userInfo[MPSidebarSyncURLKey];
        }];

    XCTestExpectation *saved = [self expectationWithDescription:@"saved"];
    [doc saveToURL:url ofType:@"net.daringfireball.markdown"
  forSaveOperation:operation
 completionHandler:^(NSError *error) {
        XCTAssertNil(error, @"save failed: %@", error);
        [saved fulfill];
    }];
    [self waitForExpectations:@[saved] timeout:10.0];

    // The announcement is dispatched to the main queue after the write.
    for (int i = 0; i < 20 && !announced; i++)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    return announced;
}

- (void)testFirstSaveAnnouncesTheNewFile
{
    MPDocument *doc = [[MPHeadlessSavingDocument alloc] init];
    NSURL *target = [self.dir URLByAppendingPathComponent:@"created.md"];

    NSURL *announced = [self announcedURLWhileSaving:doc toURL:target
                                           operation:NSSaveAsOperation];
    XCTAssertNotNil(announced,
                    @"a file MacDown creates must be announced — the watcher "
                    @"ignores our own writes, so nothing else would show it");
    XCTAssertEqualObjects(announced.lastPathComponent, @"created.md");
    XCTAssertFalse([announced.path containsString:@"NSIRD"],
                   @"the announced URL must be the saved file, not the "
                   @"temporary one the safe save writes through");
    [doc close];
}

- (void)testPlainReSaveAnnouncesNothing
{
    MPDocument *doc = [[MPHeadlessSavingDocument alloc] init];
    NSURL *target = [self.dir URLByAppendingPathComponent:@"resaved.md"];
    XCTAssertNotNil([self announcedURLWhileSaving:doc toURL:target
                                        operation:NSSaveAsOperation]);

    XCTAssertNil([self announcedURLWhileSaving:doc toURL:target
                                     operation:NSSaveOperation],
                 @"re-saving the same file cannot change the tree; announcing "
                 @"would reintroduce the reload storm");
    [doc close];
}

@end
