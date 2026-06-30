//
//  MPDocumentWorkspaceTests.m
//  MacDown 3000
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"

@interface MPDocument (WorkspaceTesting)
- (IBAction)toggleFolderSidebar:(id)sender;
@end

@interface MPDocumentWorkspaceTests : XCTestCase
@end

@implementation MPDocumentWorkspaceTests

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

@end
