//
//  MPMainControllerFolderTests.m
//  MacDown 3000
//

#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPPreferences.h"

@interface MPMainController (FolderTesting)
- (void)openPendingFolders;
@end

@interface MPMainControllerFolderTests : XCTestCase
@property (strong) MPMainController *controller;
@end

@implementation MPMainControllerFolderTests

- (void)setUp
{
    [super setUp];
    self.controller = [[MPMainController alloc] init];
}

- (void)tearDown
{
    self.controller = nil;
    [super tearDown];
}

- (void)testUntitledIsSuppressedWhenFoldersPending
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    NSArray *savedFiles = prefs.filesToOpen;
    NSArray *savedFolders = prefs.foldersToOpen;
    @try
    {
        prefs.filesToOpen = nil;
        prefs.foldersToOpen = @[@"/tmp/some-folder"];
        [prefs synchronize];
        XCTAssertFalse([self.controller applicationShouldOpenUntitledFile:NSApp],
                       @"a pending folder must suppress the blank untitled document");
    }
    @finally
    {
        prefs.filesToOpen = savedFiles;
        prefs.foldersToOpen = savedFolders;
        [prefs synchronize];
    }
}

- (void)testOpenPendingFoldersClearsTheList
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    NSArray *saved = prefs.foldersToOpen;
    @try
    {
        // A non-reachable path is skipped for opening but the list is still cleared.
        prefs.foldersToOpen = @[@"/nonexistent/path/xyz"];
        [prefs synchronize];
        [self.controller openPendingFolders];
        XCTAssertNil(prefs.foldersToOpen, @"openPendingFolders must clear the list");
    }
    @finally
    {
        prefs.foldersToOpen = saved;
        [prefs synchronize];
    }
}

@end
