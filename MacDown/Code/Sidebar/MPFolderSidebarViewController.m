#import "MPFolderSidebarViewController.h"
#import "MPFileNode.h"
#import "MPFolderWatcher.h"
#import "MPSidebarSyncCoordinator.h"

@interface MPFolderSidebarViewController ()
    <NSOutlineViewDataSource, NSOutlineViewDelegate, NSSplitViewDelegate>
@property (nonatomic, copy) NSURL *rootURL;
@property (nonatomic, strong) MPFileNode *rootNode;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) MPFolderWatcher *watcher;
@property (nonatomic, assign) BOOL applyingSharedExpansion;  // suppress re-broadcast
@end

@implementation MPFolderSidebarViewController

- (instancetype)initWithRootURL:(NSURL *)rootURL
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
    {
        _rootURL = [rootURL copy];
        _rootNode = [[MPFileNode alloc] initWithURL:rootURL isDirectory:YES];
    }
    return self;
}

- (void)loadView
{
    NSScrollView *scroll =
        [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;

    NSOutlineView *outline =
        [[NSOutlineView alloc] initWithFrame:scroll.bounds];
    NSTableColumn *col =
        [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    col.minWidth = 60;
    [outline addTableColumn:col];
    outline.outlineTableColumn = col;
    // The single column must fill the panel width and grow when the sidebar is
    // widened; otherwise it stays at the default ~100pt and truncates names.
    outline.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    outline.headerView = nil;
    outline.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    outline.floatsGroupRows = NO;
    if (@available(macOS 11.0, *))
        outline.style = NSTableViewStyleSourceList;
    outline.dataSource = self;
    outline.delegate = self;
    outline.target = self;
    outline.doubleAction = @selector(handleDoubleClick:);

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *reveal = [menu addItemWithTitle:NSLocalizedString(@"Reveal in Finder", @"Sidebar context menu")
                                         action:@selector(revealInFinder:) keyEquivalent:@""];
    NSMenuItem *copy = [menu addItemWithTitle:NSLocalizedString(@"Copy Path", @"Sidebar context menu")
                                       action:@selector(copyPath:) keyEquivalent:@""];
    reveal.target = self;
    copy.target = self;
    outline.menu = menu;

    scroll.documentView = outline;
    [outline sizeLastColumnToFit];
    self.outlineView = outline;
    self.scrollView = scroll;
    self.view = scroll;

    [self startWatching];

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(sidebarSyncDidChange:)
               name:MPSidebarSyncDidChangeNotification object:nil];
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    // Match the folders other tabs of this workspace have expanded.
    [self applyExpandedPaths:
        [[MPSidebarSyncCoordinator sharedCoordinator] expandedPathsForRoot:self.rootURL]];
}

#pragma mark - Expansion sync across tabs

- (NSArray<NSString *> *)currentExpandedPaths
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSInteger row = 0; row < self.outlineView.numberOfRows; row++)
    {
        MPFileNode *node = [self.outlineView itemAtRow:row];
        if (node.isDirectory && [self.outlineView isItemExpanded:node])
            [paths addObject:node.URL.path];
    }
    return paths;
}

- (void)reportExpansion
{
    if (self.applyingSharedExpansion)
        return;                                  // don't echo a change we're applying
    [[MPSidebarSyncCoordinator sharedCoordinator]
        setExpandedPaths:[self currentExpandedPaths] forRoot:self.rootURL source:self];
}

- (void)applyExpandedPaths:(NSArray<NSString *> *)paths
{
    if (!self.outlineView)
        return;
    self.applyingSharedExpansion = YES;
    [self applyExpansionUnderItem:nil wanted:[NSSet setWithArray:paths]];
    self.applyingSharedExpansion = NO;
}

- (void)applyExpansionUnderItem:(MPFileNode *)item wanted:(NSSet<NSString *> *)wanted
{
    NSInteger count = [self outlineView:self.outlineView numberOfChildrenOfItem:item];
    for (NSInteger i = 0; i < count; i++)
    {
        MPFileNode *child = [self outlineView:self.outlineView child:i ofItem:item];
        if (!child.isDirectory)
            continue;
        BOOL want = [wanted containsObject:child.URL.path];
        if (want && ![self.outlineView isItemExpanded:child])
            [self.outlineView expandItem:child];
        else if (!want && [self.outlineView isItemExpanded:child])
            [self.outlineView collapseItem:child];
        if (want)
            [self applyExpansionUnderItem:child wanted:wanted];
    }
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
    [self reportExpansion];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    [self reportExpansion];
}

- (void)sidebarSyncDidChange:(NSNotification *)note
{
    if (note.object == self)
        return;
    if (![note.userInfo[MPSidebarSyncKindKey] isEqualToString:MPSidebarSyncKindExpansion])
        return;
    NSURL *root = note.userInfo[MPSidebarSyncRootKey];
    if (![root.absoluteString isEqualToString:self.rootURL.absoluteString])
        return;                                  // a different workspace
    [self applyExpandedPaths:
        [[MPSidebarSyncCoordinator sharedCoordinator] expandedPathsForRoot:self.rootURL]];
}

- (void)startWatching
{
    __weak typeof(self) weakSelf = self;
    self.watcher = [[MPFolderWatcher alloc] initWithRootURL:self.rootURL
                                                    handler:^{
        [weakSelf reload];
    }];
}

- (void)stopWatching
{
    [self.watcher stop];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_watcher stop];
}

#pragma mark - Reload / selection

- (void)reload
{
    if (!self.outlineView)
        return;
    // Preserve the set of expanded directory URLs and the selected URL.
    NSMutableSet<NSURL *> *expanded = [NSMutableSet set];
    for (NSInteger row = 0; row < self.outlineView.numberOfRows; row++)
    {
        MPFileNode *node = [self.outlineView itemAtRow:row];
        if ([self.outlineView isItemExpanded:node])
            [expanded addObject:node.URL];
    }
    MPFileNode *selected = [self.outlineView itemAtRow:self.outlineView.selectedRow];
    NSURL *selectedURL = selected.URL;

    [self.rootNode invalidateChildrenRecursively];
    [self.outlineView reloadData];

    // Restoring expansion fires didExpand notifications; don't echo them back
    // to the sync coordinator (the set is unchanged).
    self.applyingSharedExpansion = YES;
    [self expandNodesMatchingURLs:expanded underItem:nil];
    self.applyingSharedExpansion = NO;
    if (selectedURL)
        [self selectFileURL:selectedURL];
}

- (void)expandNodesMatchingURLs:(NSSet<NSURL *> *)urls underItem:(MPFileNode *)item
{
    NSInteger count = [self outlineView:self.outlineView numberOfChildrenOfItem:item];
    for (NSInteger i = 0; i < count; i++)
    {
        MPFileNode *child = [self outlineView:self.outlineView child:i ofItem:item];
        if (child.isDirectory && [urls containsObject:child.URL])
        {
            [self.outlineView expandItem:child];
            [self expandNodesMatchingURLs:urls underItem:child];
        }
    }
}

- (void)selectFileURL:(NSURL *)url
{
    for (NSInteger row = 0; row < self.outlineView.numberOfRows; row++)
    {
        MPFileNode *node = [self.outlineView itemAtRow:row];
        if ([node.URL isEqual:url])
        {
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                          byExtendingSelection:NO];
            [self.outlineView scrollRowToVisible:row];
            return;
        }
    }
}

#pragma mark - Activation

- (void)handleDoubleClick:(id)sender
{
    NSInteger row = self.outlineView.clickedRow;
    if (row < 0)
        return;
    MPFileNode *node = [self.outlineView itemAtRow:row];
    if (node.isDirectory)
    {
        if ([self.outlineView isItemExpanded:node])
            [self.outlineView collapseItem:node];
        else
            [self.outlineView expandItem:node];
        return;
    }
    if ([MPFileNode isMarkdownFileURL:node.URL])
        [self.sidebarDelegate folderSidebar:self didActivateFileURL:node.URL];
}

- (void)keyDown:(NSEvent *)event
{
    // Enter / Return activates the selected file.
    unichar c = [event.charactersIgnoringModifiers length]
        ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    if (c == NSCarriageReturnCharacter || c == NSEnterCharacter)
    {
        MPFileNode *node = [self.outlineView itemAtRow:self.outlineView.selectedRow];
        if (node && [MPFileNode isMarkdownFileURL:node.URL])
        {
            [self.sidebarDelegate folderSidebar:self didActivateFileURL:node.URL];
            return;
        }
    }
    [super keyDown:event];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(id)item
{
    MPFileNode *node = item ?: self.rootNode;
    return node.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    MPFileNode *node = item ?: self.rootNode;
    return node.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return [(MPFileNode *)item isDirectory];
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    return [(MPFileNode *)item name];
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView
     viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    MPFileNode *node = item;
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"cell" owner:self];
    if (!cell)
    {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"cell";
        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:icon];
        [cell addSubview:label];
        cell.imageView = icon;
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:16],
            [icon.heightAnchor constraintEqualToConstant:16],
            [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:4],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    cell.textField.stringValue = node.name;
    cell.imageView.image = node.isDirectory
        ? [NSImage imageNamed:NSImageNameFolder]
        : [[NSWorkspace sharedWorkspace] iconForFileType:node.URL.pathExtension];
    return cell;
}

#pragma mark - NSSplitViewDelegate (for the outer split view, set in Task 7)

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
    return dividerIndex == 0 ? 150.0 : proposedMin;   // min sidebar width
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    return dividerIndex == 0 ? 420.0 : proposedMax;   // max sidebar width
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    return subview == self.view;                      // only the sidebar collapses
}

// Pin the sidebar to its current width and give all window-resize delta to the
// editor pane. NSSplitView's holding priorities do NOT do this during an
// autoresize (it falls back to proportional resizing), which made a new tab's
// sidebar stretch when its window grew to join the tab group. A divider drag
// still works: NSSplitView sets the new sidebar width first, then this method
// preserves it.
- (void)splitView:(NSSplitView *)splitView
    resizeSubviewsWithOldSize:(NSSize)oldSize
{
    if (splitView.subviews.count != 2)
    {
        [splitView adjustSubviews];
        return;
    }
    NSView *sidebar = splitView.subviews[0];
    NSView *main = splitView.subviews[1];
    CGFloat thickness = splitView.dividerThickness;
    CGFloat sidebarWidth = NSWidth(sidebar.frame);
    NSSize newSize = splitView.frame.size;
    sidebar.frame = NSMakeRect(0, 0, sidebarWidth, newSize.height);
    CGFloat mainX = sidebarWidth + thickness;
    main.frame = NSMakeRect(mainX, 0, newSize.width - mainX, newSize.height);
}

// Note: the sidebar is kept at a fixed width via the outer split view's
// holding priorities (set in MPDocument), so no manual -resizeSubviewsWithOldSize:
// is needed here — overriding it desynced NSSplitView's own divider position
// and left a stray divider line.

#pragma mark - Context menu

- (MPFileNode *)contextTargetNode
{
    NSInteger row = self.outlineView.clickedRow;
    if (row < 0)
        row = self.outlineView.selectedRow;
    if (row < 0)
        return nil;
    return [self.outlineView itemAtRow:row];
}

- (IBAction)revealInFinder:(id)sender
{
    MPFileNode *node = [self contextTargetNode];
    if (node)
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[node.URL]];
}

- (IBAction)copyPath:(id)sender
{
    MPFileNode *node = [self contextTargetNode];
    if (node)
        [self copyPath:node.URL.path toPasteboard:[NSPasteboard generalPasteboard]];
}

// Factored for testability.
- (void)copyPath:(NSString *)path toPasteboard:(NSPasteboard *)pasteboard
{
    [pasteboard clearContents];
    [pasteboard setString:path forType:NSPasteboardTypeString];
}

@end
