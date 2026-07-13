#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "MPFolderSidebarViewController.h"

@interface MPFolderSidebarViewController (Testing) <NSOutlineViewDataSource>
- (void)copyPath:(NSString *)path toPasteboard:(NSPasteboard *)pasteboard;
@end

@interface MPFolderSidebarViewControllerTests : XCTestCase
@property (strong) NSURL *root;
@property (strong) MPFolderSidebarViewController *vc;
@end

@implementation MPFolderSidebarViewControllerTests

- (void)setUp
{
    [super setUp];
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                 URLByAppendingPathComponent:unique isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:self.root withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    [@"# a" writeToURL:[self.root URLByAppendingPathComponent:@"a.md"]
            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"# b" writeToURL:[self.root URLByAppendingPathComponent:@"b.md"]
            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fm createDirectoryAtURL:[self.root URLByAppendingPathComponent:@"sub" isDirectory:YES]
        withIntermediateDirectories:YES attributes:nil error:NULL];
    self.vc = [[MPFolderSidebarViewController alloc] initWithRootURL:self.root];
    (void)self.vc.view;   // force loadView so the outline view exists
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
    self.vc = nil;
    self.root = nil;
    [super tearDown];
}

- (void)testRootURLIsExposed
{
    XCTAssertEqualObjects(self.vc.rootURL, self.root);
}

- (void)testTopLevelChildCountAndOrder
{
    // nil item == root level. Expect sub/ (dir first), then a.md, b.md.
    NSInteger n = [self.vc outlineView:nil numberOfChildrenOfItem:nil];
    XCTAssertEqual(n, 3);
    id first = [self.vc outlineView:nil child:0 ofItem:nil];
    XCTAssertTrue([self.vc outlineView:nil isItemExpandable:first],
                  @"first row should be the 'sub' directory (expandable)");
}

- (void)testCopyPathWritesPathToNamedPasteboard
{
    NSPasteboard *pb = [NSPasteboard pasteboardWithName:@"MPFolderSidebarCopyPathTestPB"];
    [pb clearContents];
    [self.vc copyPath:@"/tmp/example.md" toPasteboard:pb];
    XCTAssertEqualObjects([pb stringForType:NSPasteboardTypeString], @"/tmp/example.md");
}

@end
