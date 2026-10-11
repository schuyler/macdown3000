//
//  MPMainControllerMenuTests.m
//  MacDown 3000
//

#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPDocument.h"

@interface MPMainController (BundledFileTesting)
+ (NSURL *)copyBundledFile:(NSString *)resource extension:(NSString *)extension error:(NSError **)error;
@end

// Declared for @selector() only: these are the responder-chain actions the nib
// wires its items to, and neither is exposed in a header.
@interface MPDocument (MenuActionTesting)
- (IBAction)toggleFolderSidebar:(id)sender;
- (IBAction)togglePreviewPane:(id)sender;
@end

// The folder-workspace menu items live in MainMenu.xib rather than being added
// programmatically, so that their titles go through the project's per-locale
// MainMenu.strings workflow. These tests assert they are actually in the nib.
@interface MPMainControllerMenuTests : XCTestCase
@end

@implementation MPMainControllerMenuTests

- (NSMenu *)submenuContainingAction:(SEL)action
{
    for (NSMenuItem *top in [NSApp mainMenu].itemArray)
    {
        NSMenu *submenu = top.submenu;
        if (submenu && [submenu indexOfItemWithTarget:nil andAction:action] >= 0)
            return submenu;
    }
    return nil;
}

- (NSMenuItem *)itemInMenu:(NSMenu *)menu withAction:(SEL)action
{
    for (NSMenuItem *item in menu.itemArray)
        if (item.action == action)
            return item;
    return nil;
}

- (void)setUp
{
    [super setUp];
    XCTAssertNotNil([NSApp mainMenu], @"tests must run against the loaded nib");
}

- (void)testFileMenuHasOpenFolderRightAfterOpen
{
    NSMenu *fileMenu = [self submenuContainingAction:@selector(openDocument:)];
    XCTAssertNotNil(fileMenu);

    // Not -indexOfItemWithTarget:andAction:, which also matches on target:
    // Open… routes through the responder chain (nil target) while Open Folder…
    // is wired straight to the delegate.
    NSInteger openIdx = [fileMenu indexOfItem:
        [self itemInMenu:fileMenu withAction:@selector(openDocument:)]];
    NSInteger folderIdx = [fileMenu indexOfItem:
        [self itemInMenu:fileMenu withAction:@selector(openFolder:)]];
    XCTAssertNotEqual(folderIdx, -1, @"Open Folder… is missing from the File menu");
    XCTAssertEqual(folderIdx, openIdx + 1, @"Open Folder… should follow Open…");
}

- (void)testOpenFolderTargetsTheAppDelegate
{
    NSMenu *fileMenu = [self submenuContainingAction:@selector(openDocument:)];
    NSMenuItem *item = [self itemInMenu:fileMenu
                             withAction:@selector(openFolder:)];
    XCTAssertNotNil(item);
    // Wired to the MPMainController instance in the nib, not the responder chain.
    XCTAssertTrue([item.target isKindOfClass:[MPMainController class]],
                  @"Open Folder… must be wired to MPMainController, got %@",
                  item.target);
}

- (void)testViewMenuHasSidebarToggleWithCommandBackslash
{
    NSMenu *viewMenu = [self submenuContainingAction:@selector(togglePreviewPane:)];
    XCTAssertNotNil(viewMenu);

    NSMenuItem *toggle = [self itemInMenu:viewMenu
                               withAction:@selector(toggleFolderSidebar:)];
    XCTAssertNotNil(toggle, @"Show Sidebar is missing from the View menu");
    // AppKit may adapt this shortcut to the active keyboard layout.
    // Check the declared shortcut while preserving the user's runtime menu.
    if (@available(macOS 12.0, *)) {
        BOOL automatic = toggle.allowsAutomaticKeyEquivalentLocalization;
        @try {
            toggle.allowsAutomaticKeyEquivalentLocalization = NO;
            XCTAssertEqualObjects(toggle.keyEquivalent, @"\\");
        } @finally {
            toggle.allowsAutomaticKeyEquivalentLocalization = automatic;
        }
    } else {
        XCTAssertEqualObjects(toggle.keyEquivalent, @"\\");
    }
    XCTAssertEqual(toggle.keyEquivalentModifierMask, NSEventModifierFlagCommand);
    XCTAssertNil(toggle.target,
                 @"the toggle must route through the responder chain to the "
                 @"key window's document");
}

// Exactly one of each: a stray programmatic installer would double them up.
- (void)testFolderMenuItemsAreNotDuplicated
{
    NSInteger openFolder = 0, sidebar = 0;
    for (NSMenuItem *top in [NSApp mainMenu].itemArray)
    {
        for (NSMenuItem *item in top.submenu.itemArray)
        {
            if (item.action == @selector(openFolder:)) openFolder++;
            if (item.action == @selector(toggleFolderSidebar:)) sidebar++;
        }
    }
    XCTAssertEqual(openFolder, 1);
    XCTAssertEqual(sidebar, 1);
}

- (void)testBundledHelpCopiesRemainIndependentAndResolveRelativeImages
{
    NSError *error = nil;
    NSURL *first = [MPMainController copyBundledFile:@"help" extension:@"md" error:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);
    NSURL *second = [MPMainController copyBundledFile:@"help" extension:@"md" error:&error];
    XCTAssertNotNil(second);
    @try
    {
        XCTAssertNotEqualObjects(first.URLByDeletingLastPathComponent, second.URLByDeletingLastPathComponent);
        NSURL *source = [[NSBundle mainBundle] URLForResource:@"help" withExtension:@"md"];
        NSData *expected = [NSData dataWithContentsOfURL:source];
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:first], expected);
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:second], expected);
        NSURL *imagesSource = [[NSBundle mainBundle] URLForResource:@"Images" withExtension:nil];
        NSArray<NSURL *> *images = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:imagesSource
                                       includingPropertiesForKeys:nil options:0 error:&error];
        XCTAssertGreaterThan(images.count, 0u);
        for (NSURL *image in images)
        {
            NSURL *resolved = [[first.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Images"]
                               URLByAppendingPathComponent:image.lastPathComponent];
            XCTAssertEqualObjects([NSData dataWithContentsOfURL:resolved], [NSData dataWithContentsOfURL:image]);
        }
    }
    @finally
    {
        if (first) [[NSFileManager defaultManager] removeItemAtURL:first.URLByDeletingLastPathComponent error:nil];
        if (second) [[NSFileManager defaultManager] removeItemAtURL:second.URLByDeletingLastPathComponent error:nil];
    }
}

@end
