#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "MPFolderSidebarViewController.h"
#import "MPFileNode.h"
#import "MPSidebarSplitView.h"
#import "MPSidebarSyncCoordinator.h"

@interface MPFolderSidebarViewController (Testing)
    <NSOutlineViewDataSource, NSSplitViewDelegate>
@property (nonatomic, strong) NSOutlineView *outlineView;
- (void)copyPath:(NSString *)path toPasteboard:(NSPasteboard *)pasteboard;
- (void)handleDoubleClick:(id)sender;
- (NSInteger)rowForURL:(NSURL *)url resolvingLinks:(BOOL)resolvingLinks;
@end

/// Lets a test say which row was clicked/selected without a real mouse.
/// Subclasses the production outline view so -keyDown: exercises the real path
/// rather than calling the controller directly.
@interface MPStubOutlineView : MPSidebarOutlineView
@property (nonatomic) NSInteger stubClickedRow;
@property (nonatomic) NSInteger stubSelectedRow;
@end

@implementation MPStubOutlineView
- (NSInteger)clickedRow { return self.stubClickedRow; }
- (NSInteger)selectedRow { return self.stubSelectedRow; }
@end

/// Records what the sidebar asked to open.
@interface MPRecordingSidebarDelegate : NSObject <MPFolderSidebarDelegate>
@property (nonatomic, strong) NSMutableArray<NSURL *> *activated;
@end

@implementation MPRecordingSidebarDelegate
- (instancetype)init
{
    self = [super init];
    if (self)
        _activated = [NSMutableArray array];
    return self;
}
- (void)folderSidebar:(MPFolderSidebarViewController *)sidebar
   didActivateFileURL:(NSURL *)url
{
    [self.activated addObject:url];
}
@end

@interface MPFolderSidebarViewControllerTests : XCTestCase
@property (strong) NSURL *root;
@property (strong) MPFolderSidebarViewController *vc;
@property (strong) MPStubOutlineView *outline;
@property (strong) MPRecordingSidebarDelegate *delegate;
@property (strong) NSNumber *savedWidthDefault;
@property (strong) NSURL *outsideDir;
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

    // Swap in an outline view whose clicked/selected row the test controls.
    // Rows, collapsed: 0 = sub/, 1 = a.md, 2 = b.md.
    self.outline = [[MPStubOutlineView alloc]
        initWithFrame:NSMakeRect(0, 0, 220, 400)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [self.outline addTableColumn:col];
    self.outline.outlineTableColumn = col;
    self.outline.dataSource = (id)self.vc;
    self.outline.delegate = (id)self.vc;
    self.outline.stubClickedRow = -1;
    self.outline.stubSelectedRow = -1;
    self.outline.sidebar = self.vc;
    self.vc.outlineView = self.outline;
    [self.outline reloadData];

    self.delegate = [[MPRecordingSidebarDelegate alloc] init];
    self.vc.sidebarDelegate = self.delegate;

    self.savedWidthDefault = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"MPSidebarSharedWidth"];
}

- (void)tearDown
{
    // The geometry tests set a sidebar width, which persists as the global
    // seed; don't leave the running user's preference changed.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (self.savedWidthDefault)
        [defaults setObject:self.savedWidthDefault forKey:@"MPSidebarSharedWidth"];
    else
        [defaults removeObjectForKey:@"MPSidebarSharedWidth"];
    self.savedWidthDefault = nil;

    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
    if (self.outsideDir)
        [[NSFileManager defaultManager] removeItemAtURL:self.outsideDir error:NULL];
    self.outsideDir = nil;
    self.outline = nil;
    self.delegate = nil;
    self.vc = nil;
    self.root = nil;
    [super tearDown];
}

- (NSEvent *)returnKeyEvent
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:0
                           timestamp:0
                        windowNumber:0
                             context:nil
                          characters:@"\r"
         charactersIgnoringModifiers:@"\r"
                           isARepeat:NO
                             keyCode:36];
}

- (void)testRootURLIsExposed
{
    XCTAssertEqualObjects(self.vc.rootURL, self.root);
}

- (void)testTopLevelChildCountAndOrder
{
    // nil item == root level. Expect sub/ (dir first), then a.md, b.md.
    NSInteger n = [self.vc outlineView:self.outline numberOfChildrenOfItem:nil];
    XCTAssertEqual(n, 3);
    id first = [self.vc outlineView:self.outline child:0 ofItem:nil];
    XCTAssertTrue([self.vc outlineView:self.outline isItemExpandable:first],
                  @"first row should be the 'sub' directory (expandable)");
}

- (void)testCopyPathWritesPathToNamedPasteboard
{
    NSPasteboard *pb = [NSPasteboard pasteboardWithName:@"MPFolderSidebarCopyPathTestPB"];
    [pb clearContents];
    [self.vc copyPath:@"/tmp/example.md" toPasteboard:pb];
    XCTAssertEqualObjects([pb stringForType:NSPasteboardTypeString], @"/tmp/example.md");
}

#pragma mark - Activation: double click

- (void)testDoubleClickOnMarkdownFileActivatesIt
{
    self.outline.stubClickedRow = 1;              // a.md
    [self.vc handleDoubleClick:nil];
    XCTAssertEqual(self.delegate.activated.count, 1u);
    XCTAssertEqualObjects(self.delegate.activated.firstObject.lastPathComponent,
                          @"a.md");
}

- (void)testDoubleClickOnDirectoryTogglesExpansionWithoutActivating
{
    id sub = [self.vc outlineView:self.outline child:0 ofItem:nil];
    XCTAssertFalse([self.outline isItemExpanded:sub]);

    self.outline.stubClickedRow = 0;              // sub/
    [self.vc handleDoubleClick:nil];
    XCTAssertTrue([self.outline isItemExpanded:sub], @"should expand");
    XCTAssertEqual(self.delegate.activated.count, 0u,
                   @"a folder is not a document");

    [self.vc handleDoubleClick:nil];
    XCTAssertFalse([self.outline isItemExpanded:sub], @"and collapse again");
    XCTAssertEqual(self.delegate.activated.count, 0u);
}

- (void)testDoubleClickOnEmptySpaceDoesNothing
{
    self.outline.stubClickedRow = -1;             // click below the last row
    XCTAssertNoThrow([self.vc handleDoubleClick:nil]);
    XCTAssertEqual(self.delegate.activated.count, 0u);
}

- (void)testDoubleClickOnNonMarkdownFileDoesNotActivate
{
    [@"binary" writeToURL:[self.root URLByAppendingPathComponent:@"image.png"]
               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self.vc reload];

    // image.png is filtered out of the tree entirely, so the row count is
    // unchanged and nothing can activate it.
    XCTAssertEqual([self.vc outlineView:self.outline
                 numberOfChildrenOfItem:nil], 3);
    for (NSInteger row = 0; row < 3; row++)
    {
        self.outline.stubClickedRow = row;
        [self.vc handleDoubleClick:nil];
    }
    for (NSURL *url in self.delegate.activated)
        XCTAssertNotEqualObjects(url.lastPathComponent, @"image.png");
}

// Activating a symlink must report its target: NSDocumentController refuses a
// link's own URL as public.symlink rather than Markdown. Covers the delegate
// call sites, which the MPFileNode-level tests do not reach.
- (NSInteger)addLinkedFileAndReturnItsRow
{
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.outsideDir = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                       URLByAppendingPathComponent:unique isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.outsideDir
        withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *target = [self.outsideDir URLByAppendingPathComponent:@"target.md"];
    [@"# t" writeToURL:target atomically:YES
              encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager]
        createSymbolicLinkAtURL:[self.root URLByAppendingPathComponent:@"alias.md"]
             withDestinationURL:target error:NULL];

    [self.vc reload];
    for (NSInteger row = 0; row < self.outline.numberOfRows; row++)
    {
        MPFileNode *node = [self.outline itemAtRow:row];
        if ([node.name isEqualToString:@"alias.md"])
            return row;
    }
    XCTFail(@"the linked file should be listed");
    return -1;
}

- (void)testDoubleClickOnSymlinkedFileReportsItsTarget
{
    NSInteger row = [self addLinkedFileAndReturnItsRow];
    self.outline.stubClickedRow = row;
    [self.vc handleDoubleClick:nil];

    XCTAssertEqual(self.delegate.activated.count, 1u);
    NSURL *opened = self.delegate.activated.firstObject;
    XCTAssertEqualObjects(opened.lastPathComponent, @"target.md",
                          @"opening a link must reach the file it points at");
}

- (void)testReturnOnSymlinkedFileReportsItsTarget
{
    NSInteger row = [self addLinkedFileAndReturnItsRow];
    self.outline.stubSelectedRow = row;
    [self.outline keyDown:[self returnKeyEvent]];

    XCTAssertEqual(self.delegate.activated.count, 1u);
    XCTAssertEqualObjects(self.delegate.activated.firstObject.lastPathComponent,
                          @"target.md");
}

#pragma mark - Activation: Return key

- (void)testReturnKeyActivatesSelectedMarkdownFile
{
    self.outline.stubSelectedRow = 2;             // b.md
    [self.outline keyDown:[self returnKeyEvent]];
    XCTAssertEqual(self.delegate.activated.count, 1u);
    XCTAssertEqualObjects(self.delegate.activated.firstObject.lastPathComponent,
                          @"b.md");
}

- (void)testReturnKeyWithDirectorySelectedDoesNotActivate
{
    self.outline.stubSelectedRow = 0;             // sub/
    XCTAssertNoThrow([self.outline keyDown:[self returnKeyEvent]]);
    XCTAssertEqual(self.delegate.activated.count, 0u);
}

- (void)testReturnKeyWithNothingSelectedDoesNotActivate
{
    self.outline.stubSelectedRow = -1;
    XCTAssertNoThrow([self.outline keyDown:[self returnKeyEvent]]);
    XCTAssertEqual(self.delegate.activated.count, 0u);
}

- (void)testOtherKeysDoNotActivate
{
    self.outline.stubSelectedRow = 1;             // a.md selected
    NSEvent *letter = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                     characters:@"x"
                    charactersIgnoringModifiers:@"x"
                                      isARepeat:NO
                                        keyCode:7];
    XCTAssertNoThrow([self.outline keyDown:letter]);
    XCTAssertEqual(self.delegate.activated.count, 0u);
}

#pragma mark - Production wiring

// The tests above swap in their own outline view, so they would still pass if
// -loadView stopped wiring the real one up. These pin that wiring.

- (void)testLoadViewBuildsAnOutlineViewWiredForActivation
{
    MPFolderSidebarViewController *vc =
        [[MPFolderSidebarViewController alloc] initWithRootURL:self.root];
    NSScrollView *scroll = (NSScrollView *)vc.view;
    XCTAssertTrue([scroll isKindOfClass:[NSScrollView class]]);

    id outline = scroll.documentView;
    XCTAssertTrue([outline isKindOfClass:[MPSidebarOutlineView class]],
                  @"Return is handled by the outline view, not the controller");
    XCTAssertEqual([(MPSidebarOutlineView *)outline sidebar], vc,
                   @"without this back-reference Return does nothing");
    XCTAssertEqual([outline target], vc);
    XCTAssertEqual([outline doubleAction], @selector(handleDoubleClick:));
}

#pragma mark - Split view geometry

- (NSSplitView *)splitViewWithSidebarWidth:(CGFloat)width
                                totalWidth:(CGFloat)total
{
    MPSidebarSplitView *split = [[MPSidebarSplitView alloc]
        initWithFrame:NSMakeRect(0, 0, total, 600)];
    split.vertical = YES;
    NSView *sidebar = self.vc.view;
    sidebar.frame = NSMakeRect(0, 0, width, 600);
    [split addSubview:sidebar];
    [split addSubview:[[NSView alloc]
        initWithFrame:NSMakeRect(width + 1, 0, total - width - 1, 600)]];
    split.delegate = (id)self.vc;
    return split;
}

- (void)testSidebarKeepsItsWidthWhenTheWindowGrows
{
    [[MPSidebarSyncCoordinator sharedCoordinator]
        setSidebarWidth:220 forRoot:self.root source:self];
    NSSplitView *split = [self splitViewWithSidebarWidth:220 totalWidth:800];

    split.frame = NSMakeRect(0, 0, 1400, 600);
    [self.vc splitView:split resizeSubviewsWithOldSize:NSMakeSize(800, 600)];
    XCTAssertEqualWithAccuracy(NSWidth(split.subviews[0].frame), 220.0, 0.5,
                               @"all the extra width belongs to the editor");
}

// Squeezing the window must not shrink the sidebar permanently.
- (void)testSidebarWidthIsRestoredAfterTheWindowIsSqueezed
{
    [[MPSidebarSyncCoordinator sharedCoordinator]
        setSidebarWidth:220 forRoot:self.root source:self];
    NSSplitView *split = [self splitViewWithSidebarWidth:220 totalWidth:800];

    // Below the sidebar's own width: it has to give way...
    split.frame = NSMakeRect(0, 0, 94, 600);
    [self.vc splitView:split resizeSubviewsWithOldSize:NSMakeSize(800, 600)];
    XCTAssertLessThanOrEqual(NSWidth(split.subviews[0].frame), 94.0);
    XCTAssertGreaterThanOrEqual(NSWidth(split.subviews[1].frame), 0.0,
                                @"the editor pane must never go negative");

    // ...and take it back when there is room again.
    split.frame = NSMakeRect(0, 0, 800, 600);
    [self.vc splitView:split resizeSubviewsWithOldSize:NSMakeSize(94, 600)];
    XCTAssertEqualWithAccuracy(NSWidth(split.subviews[0].frame), 220.0, 0.5,
                               @"the sidebar width must not ratchet down");
}

- (void)testCollapsedSidebarLeavesNoGapBesideTheEditor
{
    NSSplitView *split = [self splitViewWithSidebarWidth:220 totalWidth:800];
    // A collapsed pane keeps its frame width and is merely hidden.
    self.vc.view.hidden = YES;
    XCTAssertTrue([split isSubviewCollapsed:self.vc.view],
                  @"precondition: AppKit reports the pane as collapsed");

    split.frame = NSMakeRect(0, 0, 900, 600);
    [self.vc splitView:split resizeSubviewsWithOldSize:NSMakeSize(800, 600)];

    NSRect editor = split.subviews[1].frame;
    XCTAssertEqualWithAccuracy(NSMinX(editor), split.dividerThickness, 0.5,
                               @"the editor should start at the leading edge");
    XCTAssertEqualWithAccuracy(NSWidth(editor),
                               900.0 - split.dividerThickness, 0.5);
}

#pragma mark - Selection with links present

/// The listed node with this name, or nil.
- (MPFileNode *)nodeNamed:(NSString *)name
{
    for (NSInteger row = 0; row < self.outline.numberOfRows; row++)
    {
        MPFileNode *node = [self.outline itemAtRow:row];
        if ([node.name isEqualToString:name])
            return node;
    }
    return nil;
}

/// Name of whatever row is currently selected, or nil. Reads the index set
/// rather than -selectedRow, which the stub overrides for the activation tests.
- (NSString *)selectedNodeName
{
    NSIndexSet *selected = self.outline.selectedRowIndexes;
    if (!selected.count)
        return nil;
    return [(MPFileNode *)[self.outline itemAtRow:selected.firstIndex] name];
}

// A file and a link to it can both be listed. The file's own row must win,
// whichever sorts first — the link only counts when the file itself is absent.
- (void)testSelectionPrefersTheFileOverALinkToIt
{
    NSURL *real = [self.root URLByAppendingPathComponent:@"real.md"];
    [@"# r" writeToURL:real atomically:YES
              encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager]
        createSymbolicLinkAtURL:[self.root URLByAppendingPathComponent:@"alias.md"]
             withDestinationURL:real error:NULL];
    [self.vc reload];

    // Ask with the node's own URL, as every production caller does — node URLs
    // are canonical, built from the resolved root.
    MPFileNode *realNode = [self nodeNamed:@"real.md"];
    XCTAssertNotNil(realNode);
    // "alias.md" sorts before "real.md", so a single-pass match picks the link.
    [self.vc selectFileURL:realNode.URL];
    XCTAssertEqualObjects([self selectedNodeName], @"real.md",
                          @"the file's own row must win over a link to it");
}

// With no row for the file itself, the link is the right answer: that is the
// case activation relies on.
- (void)testSelectionFallsBackToALinkWhenTheTargetIsNotListed
{
    NSInteger row = [self addLinkedFileAndReturnItsRow];
    XCTAssertGreaterThanOrEqual(row, 0);
    MPFileNode *alias = [self.outline itemAtRow:row];

    [self.vc selectFileURL:alias.resolvedURL];
    XCTAssertEqualObjects([self selectedNodeName], @"alias.md",
                          @"the target lives outside the tree, so the link "
                          @"itself is the row to highlight");
}

// A symlinked folder resolves equal to the real folder's URL; the real one
// must still be the row that gets selected.
- (void)testSelectionPrefersTheRealFolderOverALinkToIt
{
    NSURL *realDir = [self.root URLByAppendingPathComponent:@"realdir"
                                                isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:realDir withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    [@"# d" writeToURL:[realDir URLByAppendingPathComponent:@"in.md"]
            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fm createSymbolicLinkAtURL:[self.root URLByAppendingPathComponent:@"aliasdir"]
             withDestinationURL:realDir error:NULL];
    [self.vc reload];

    MPFileNode *realNode = [self nodeNamed:@"realdir"];
    XCTAssertNotNil(realNode);
    [self.vc selectFileURL:realNode.URL];
    XCTAssertEqualObjects([self selectedNodeName], @"realdir",
                          @"'aliasdir' sorts first but is not the folder asked for");

    // Asserted on the helper directly: -selectFileURL: finds realdir in pass 1
    // and returns, so only this reaches the pass that resolves links. A
    // symlinked folder's resolvedURL equals the real folder's own URL, so
    // without the directory guard 'aliasdir' would match here.
    XCTAssertEqual([self.vc rowForURL:realNode.URL resolvingLinks:YES], -1,
                   @"link resolution must never match a directory");
}

#pragma mark - Workspace containment

- (void)testContainsURLMatchesFilesUnderTheRoot
{
    XCTAssertTrue([self.vc containsURL:
        [self.root URLByAppendingPathComponent:@"a.md"]]);
    XCTAssertTrue([self.vc containsURL:
        [self.root URLByAppendingPathComponent:@"sub/deep.md"]]);
    XCTAssertTrue([self.vc containsURL:self.root], @"the root itself counts");
}

- (void)testContainsURLRejectsOutsiders
{
    XCTAssertFalse([self.vc containsURL:
        [NSURL fileURLWithPath:@"/etc/hosts"]]);
    // A sibling whose path merely starts with the root's path.
    NSURL *sibling = [NSURL fileURLWithPath:
        [self.root.path stringByAppendingString:@"-other/x.md"]];
    XCTAssertFalse([self.vc containsURL:sibling],
                   @"prefix matching must respect path boundaries");
}

@end
