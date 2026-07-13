//
//  MPMainControllerMenuTests.m
//  MacDown 3000
//

#import <XCTest/XCTest.h>
#import "MPMainController.h"

@interface MPMainController (MenuTesting)
- (void)installFolderMenuItems;
@end

@interface MPMainControllerMenuTests : XCTestCase
@end

@implementation MPMainControllerMenuTests

- (void)testInstallAddsOpenFolderAndSidebarItemsIdempotently
{
    // Build a minimal main menu mirroring the app's File/View structure.
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    fileItem.submenu = fileMenu;
    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
    viewItem.submenu = [[NSMenu alloc] initWithTitle:@"View"];
    [mainMenu addItem:fileItem];
    [mainMenu addItem:viewItem];

    NSMenu *previous = [NSApp mainMenu];
    [NSApp setMainMenu:mainMenu];
    @try
    {
        MPMainController *controller = [[MPMainController alloc] init];
        [controller installFolderMenuItems];
        [controller installFolderMenuItems];   // idempotent

        NSInteger openFolderCount = 0, sidebarCount = 0;
        for (NSMenuItem *it in fileMenu.itemArray)
            if (it.action == @selector(openFolder:)) openFolderCount++;
        for (NSMenuItem *it in viewItem.submenu.itemArray)
            if (it.action == @selector(toggleFolderSidebar:)) sidebarCount++;

        XCTAssertEqual(openFolderCount, 1);
        XCTAssertEqual(sidebarCount, 1);

        NSMenuItem *sidebar = nil;
        for (NSMenuItem *it in viewItem.submenu.itemArray)
            if (it.action == @selector(toggleFolderSidebar:)) sidebar = it;
        XCTAssertEqualObjects(sidebar.keyEquivalent, @"\\");
        XCTAssertEqual(sidebar.keyEquivalentModifierMask, NSEventModifierFlagCommand);
    }
    @finally
    {
        [NSApp setMainMenu:previous];
    }
}

@end
