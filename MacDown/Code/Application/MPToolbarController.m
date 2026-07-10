//
//  MPToolbarController.m
//  MacDown 3000
//
//  Created by Niklas Berglund on 2017-02-12.
//  Copyright © 2017 Tzu-ping Chung . All rights reserved.
//

#import "MPToolbarController.h"
#import "MPPreferences.h"

// Because we're creating selectors for methods which aren't in this class
#pragma GCC diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Wundeclared-selector"


static CGFloat itemWidth = 37;
// Document-zoom presets must match MPDocumentZoomLevels() in MPDocument.m.
static NSArray<NSNumber *> *MPToolbarDocumentZoomLevels(void)
{
    static NSArray *levels = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        levels = @[@0.5, @0.75, @0.9, @1.0, @1.1, @1.25, @1.5, @2.0, @3.0];
    });
    return levels;
}


@implementation MPToolbarController
{
    NSArray *toolbarItems;
    NSArray *toolbarItemIdentifiers;

    /**
     * Map toolbar item identifier to it's NSToolbarItem or NSToolbarItemGroup object
     */
    NSMutableDictionary *toolbarItemIdentifierObjectDictionary;

    /**
     * Map toolbar item identifier to the selector name (NSString) that should
     * be dispatched to self.document when a standalone button is clicked.
     * Needed because self.document is nil during init when toolbar items are
     * created, so we can't set target = self.document at construction time.
     */
    NSMutableDictionary<NSString *, NSString *> *standaloneItemActions;

    /**
     * Weak reference to the zoom popup so we can re-sync its selected item
     * when the preference changes from elsewhere (menu, keyboard shortcut).
     */
    __weak NSPopUpButton *_zoomPopUp;
}

- (id)init
{
    self = [super init];

    if (!self)
    {
        return nil;
    }

    self->toolbarItemIdentifierObjectDictionary = [NSMutableDictionary new];
    self->standaloneItemActions = [NSMutableDictionary new];
    [self setupToolbarItems];

    // Observe NSUserDefaults so the popup's selection reflects external
    // changes (View menu actions, ⌘+/⌘-/⌘0). Using KVO on the standard
    // defaults avoids threading a sync callback through MPDocument.
    [[NSUserDefaults standardUserDefaults]
        addObserver:self
         forKeyPath:@"documentZoomLevel"
            options:NSKeyValueObservingOptionNew
            context:NULL];

    return self;
}

- (void)dealloc
{
    @try {
        [[NSUserDefaults standardUserDefaults]
            removeObserver:self forKeyPath:@"documentZoomLevel"];
    } @catch (NSException *exception) {
        // removeObserver may throw if not registered; ignore on teardown.
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"documentZoomLevel"])
    {
        [self syncDocumentZoomDisplay];
    }
}


#pragma mark - Private

- (void)setupToolbarItems
{
    // Set up layout drop down alternatives. title will be set in validateUserInterfaceItem:
    NSMenuItem *toggleEditorMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(toggleEditorPane:) keyEquivalent:@"e"];
    NSMenuItem *togglePreviewMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(togglePreviewPane:) keyEquivalent:@"p"];
    
    // Set up all available toolbar items
    self->toolbarItems = @[
        [self toolbarItemGroupWithIdentifier:@"indent-group" separated:YES label:NSLocalizedString(@"Shift Left/Right", @"") items:@[
            [self toolbarItemWithIdentifier:@"shift-left" label:NSLocalizedString(@"Shift Left", @"Shift text to the left toolbar button") icon:@"ToolbarIconShiftLeft" action:@selector(unindent:)],
            [self toolbarItemWithIdentifier:@"shift-right" label:NSLocalizedString(@"Shift Right", @"Shift text to the right toolbar button") icon:@"ToolbarIconShiftRight" action:@selector(indent:)]
            ]
        ],
        [self toolbarItemGroupWithIdentifier:@"text-formatting-group" separated:NO label:NSLocalizedString(@"Text Styles", @"") items:@[
            [self toolbarItemWithIdentifier:@"bold" label:NSLocalizedString(@"Strong", @"Strong toolbar button") icon:@"ToolbarIconBold" action:@selector(toggleStrong:)],
            [self toolbarItemWithIdentifier:@"italic" label:NSLocalizedString(@"Emphasize", @"Emphasize toolbar button") icon:@"ToolbarIconItalic" action:@selector(toggleEmphasis:)],
            [self toolbarItemWithIdentifier:@"underline" label:NSLocalizedString(@"Underline", @"Underline toolbar button") icon:@"ToolbarIconUnderlined" action:@selector(toggleUnderline:)]
            ]
         ],
        [self toolbarItemGroupWithIdentifier:@"heading-group" separated:NO label:NSLocalizedString(@"Headings", @"") items:@[
            [self toolbarItemWithIdentifier:@"heading1" label:NSLocalizedString(@"Heading 1", @"Heading 1 toolbar button") icon:@"ToolbarIconHeading1" action:@selector(convertToH1:)],
            [self toolbarItemWithIdentifier:@"heading2" label:NSLocalizedString(@"Heading 2", @"Heading 2 toolbar button") icon:@"ToolbarIconHeading2" action:@selector(convertToH2:)],
            [self toolbarItemWithIdentifier:@"heading3" label:NSLocalizedString(@"Heading 3", @"Heading 3 toolbar button") icon:@"ToolbarIconHeading3" action:@selector(convertToH3:)]
            ]
         ],
        [self toolbarItemGroupWithIdentifier:@"list-group" separated:YES label:NSLocalizedString(@"Ordered/Unordered List", @"") items:@[
            [self toolbarItemWithIdentifier:@"unordered-list" label:NSLocalizedString(@"Unordered List", @"Unordered list toolbar button") icon:@"ToolbarIconUnorderedList" action:@selector(toggleUnorderedList:)],
            [self toolbarItemWithIdentifier:@"ordered-list" label:NSLocalizedString(@"Ordered List", @"Ordered list toolbar button") icon:@"ToolbarIconOrderedList" action:@selector(toggleOrderedList:)]
            ]
         ],
        [self toolbarItemWithIdentifier:@"blockquote" label:NSLocalizedString(@"Blockquote", @"Blockquote toolbar button") icon:@"ToolbarIconBlockquote" action:@selector(toggleBlockquote:)],
        [self toolbarItemWithIdentifier:@"code" label:NSLocalizedString(@"Inline Code", @"Inline code toolbar button") icon:@"ToolbarIconInlineCode" action:@selector(toggleInlineCode:)],
        [self toolbarItemWithIdentifier:@"link" label:NSLocalizedString(@"Link", @"Link toolbar button") icon:@"ToolbarIconLink" action:@selector(toggleLink:)],
        [self toolbarItemWithIdentifier:@"image" label:NSLocalizedString(@"Image", @"Image toolbar button") icon:@"ToolbarIconImage" action:@selector(toggleImage:)],
        [self toolbarItemWithIdentifier:@"table" label:NSLocalizedString(@"Table", @"Table toolbar button") icon:NSImageNameListViewTemplate action:@selector(insertTable:)],
        [self toolbarItemWithIdentifier:@"copy-html" label:NSLocalizedString(@"Copy HTML", @"Copy HTML toolbar button") icon:@"ToolbarIconCopyHTML" action:@selector(copyHtml:)],
        [self toolbarItemWithIdentifier:@"comment" label:NSLocalizedString(@"Comment", @"Comment toolbar button") icon:@"ToolbarIconComment" action:@selector(toggleComment:)],
        [self toolbarItemWithIdentifier:@"highlight" label:NSLocalizedString(@"Highlight", @"Highlight toolbar button") icon:@"ToolbarIconHighlight" action:@selector(toggleHighlight:)],
        [self toolbarItemWithIdentifier:@"strikethrough" label:NSLocalizedString(@"Strikethrough", @"Strikethrough toolbar button") icon:@"ToolbarIconStrikethrough" action:@selector(toggleStrikethrough:)],
        [self toolbarItemDropDownWithIdentifier:@"layout" label:NSLocalizedString(@"Layout", @"Layout toolbar button") icon:@"ToolbarIconEditorAndPreview" menuItems:
            @[
              toggleEditorMenuItem, togglePreviewMenuItem
            ]
        ],
        [self toolbarItemDocumentZoomPopUpWithIdentifier:@"document-zoom" label:NSLocalizedString(@"Zoom", @"Preview pane zoom toolbar item")]
    ];

    self->toolbarItemIdentifiers = [self toolbarItemIdentifiersFromItemsArray:self->toolbarItems];

    // Reflect the persisted preference once everything is wired up.
    [self syncDocumentZoomDisplay];
}

/**
 * Returns an array with all item identifiers for the toolbar items in the passed in _toolbarItemsArray_.
 */
- (NSArray *)toolbarItemIdentifiersFromItemsArray:(NSArray *)toolbarItemsArray {
    NSMutableArray *orderedIdentifiers = [NSMutableArray new];
    
    for (NSToolbarItem *item in self->toolbarItems) {
        [orderedIdentifiers addObject:item.itemIdentifier];
    }
    
    return [orderedIdentifiers copy];
}

- (void)selectedToolbarItemGroupItem:(NSSegmentedControl *)sender
{
    NSInteger selectedIndex = sender.selectedSegment;

    NSToolbarItemGroup *selectedGroup = self->toolbarItemIdentifierObjectDictionary[sender.identifier];
    NSAssert(selectedGroup != nil,
             @"selectedToolbarItemGroupItem: sender identifier '%@' is not registered "
             @"in toolbarItemIdentifierObjectDictionary",
             sender.identifier);
    if (!selectedGroup) { return; }

    NSAssert(selectedIndex >= 0 && (NSUInteger)selectedIndex < selectedGroup.subitems.count,
             @"selectedToolbarItemGroupItem: selectedSegment %ld is out of bounds "
             @"for group '%@' with %lu subitems",
             (long)selectedIndex, sender.identifier,
             (unsigned long)selectedGroup.subitems.count);
    if (selectedIndex < 0 || (NSUInteger)selectedIndex >= selectedGroup.subitems.count) { return; }

    NSToolbarItem *selectedItem = selectedGroup.subitems[selectedIndex];

    // Invoke the toolbar item's action on the document. Use performSelector:
    // (rather than a raw IMP cast) so the ObjC ABI correctly sets up self,
    // _cmd, and the sender argument. The previous IMP cast to `void (*)(id)`
    // left _cmd and sender as uninitialized register values, which produced
    // garbage senders like 0x400000000000bad0 and random EXC_BAD_ACCESS
    // crashes when the invoked action (or its responder-chain validation)
    // touched sender.
    MPDocument *document = self.document;
    SEL action = selectedItem.action;
    if (document && action && [document respondsToSelector:action])
    {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [document performSelector:action withObject:selectedItem];
        #pragma clang diagnostic pop
    }
}


/**
 * Forward validation for dropdown menu items to the document so that
 * validateUserInterfaceItem: can set titles, hidden state, and
 * enable/disable based on the real action (stored in representedObject).
 */
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    if (item.action == @selector(dropdownMenuItemClicked:)
        && [(id)item isKindOfClass:[NSMenuItem class]])
    {
        NSMenuItem *menuItem = (NSMenuItem *)item;
        NSString *actionName = menuItem.representedObject;
        if (!actionName) return NO;

        MPDocument *document = self.document;
        if (!document) return NO;

        // Temporarily restore the real action and target so the document's
        // validateUserInterfaceItem: can identify and configure the item.
        // This is safe: validation is synchronous and single-threaded.
        SEL realAction = NSSelectorFromString(actionName);
        menuItem.action = realAction;
        menuItem.target = document;
        BOOL result = [document validateUserInterfaceItem:menuItem];
        menuItem.target = self;
        menuItem.action = @selector(dropdownMenuItemClicked:);
        return result;
    }
    return YES;
}


- (void)standaloneToolbarItemClicked:(NSButton *)sender
{
    NSString *actionName = self->standaloneItemActions[sender.identifier];
    if (!actionName) return;
    SEL action = NSSelectorFromString(actionName);
    MPDocument *document = self.document;
    if (document && [document respondsToSelector:action])
    {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [document performSelector:action withObject:sender];
        #pragma clang diagnostic pop
    }
}

- (void)dropdownMenuItemClicked:(NSMenuItem *)sender
{
    NSString *actionName = sender.representedObject;
    if (!actionName) return;
    SEL action = NSSelectorFromString(actionName);
    MPDocument *document = self.document;
    if (document && [document respondsToSelector:action])
    {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [document performSelector:action withObject:sender];
        #pragma clang diagnostic pop
    }
}


#pragma mark - NSToolbarDelegate
- (NSArray<NSString *> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    // From toolbar item dictionary(setupToolbarItems)
    //NSArray *orderedToolbarItemIdentifiers = [self orderedToolbarDefaultItemKeysForDictionary:self->toolbarItems];
    NSArray *orderedToolbarItemIdentifiers = [self toolbarItemIdentifiersFromItemsArray:self->toolbarItems];
    
    // Mixed identifiers from dictionary and space at below specified indices
    NSMutableArray *defaultItemIdentifiers = [NSMutableArray new];
    
    // Add space after the specified toolbar item indices
    int spaceAfterIndices[] = {}; // No space in the default set
    int flexibleSpaceAfterIndices[] = {2, 3, 5, 8, 12};

    // Bounds checking to prevent buffer overflow when accessing C arrays
    // Empty spaceAfterIndices array must not be accessed (count = 0)
    // flexibleSpaceAfterIndices has 5 elements, so k must be < 5
    size_t spaceAfterIndicesCount = sizeof(spaceAfterIndices) / sizeof(int);
    size_t flexibleSpaceAfterIndicesCount = sizeof(flexibleSpaceAfterIndices) / sizeof(int);

    int i = 0;
    int j = 0;
    int k = 0;

    for (NSString *itemIdentifier in orderedToolbarItemIdentifiers)
    {
        // exclude some toolbar items from the default toolbar
        if ([itemIdentifier  isEqual: @"comment"]
            || [itemIdentifier  isEqual: @"highlight"]
            || [itemIdentifier  isEqual: @"strikethrough"]) {
            // do nothing here
        }else {
            [defaultItemIdentifiers addObject:itemIdentifier];
        }

        if (j < spaceAfterIndicesCount && i == spaceAfterIndices[j])
        {
            [defaultItemIdentifiers addObject:NSToolbarSpaceItemIdentifier];
            j++;
        }

        if (k < flexibleSpaceAfterIndicesCount && i == flexibleSpaceAfterIndices[k])
        {
            [defaultItemIdentifiers addObject:NSToolbarFlexibleSpaceItemIdentifier];
            k++;
        }

        i++;
    }
    
    return [defaultItemIdentifiers copy];
}

- (NSArray<NSString *> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [self->toolbarItemIdentifiers arrayByAddingObjectsFromArray:@[
        NSToolbarFlexibleSpaceItemIdentifier,
        NSToolbarSpaceItemIdentifier,
        NSToolbarSeparatorItemIdentifier,
    ]];
}

- (NSArray<NSString *> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
    return self->toolbarItemIdentifiers;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item;
    
    for (NSToolbarItem *currentItem in self->toolbarItems) {
        if ([currentItem.itemIdentifier isEqualToString:itemIdentifier]) {
            item = currentItem;
            break;
        }
    }
    
    return item;
}


#pragma mark - Toolbar item factory methods

/**
 * Factory method for creating and configuring a NSToolbarItemGroup object.
 */
- (NSToolbarItemGroup *)toolbarItemGroupWithIdentifier:(NSString *)itemIdentifier separated:(BOOL)separated label:(NSString *)label items:(NSArray <NSToolbarItem *>*)items {
    NSToolbarItemGroup *itemGroup = [[NSToolbarItemGroup alloc] initWithItemIdentifier:itemIdentifier];
    itemGroup.subitems = items;
    itemGroup.label = label;
    itemGroup.paletteLabel = label;
    
    CGFloat itemGroupWidth = itemWidth * items.count;
    
    NSSegmentedControl *segmentedControl = [[NSSegmentedControl alloc] init];
    segmentedControl.identifier = itemIdentifier;
    segmentedControl.segmentStyle = separated ? NSSegmentStyleSeparated : NSSegmentStyleTexturedRounded;
    segmentedControl.trackingMode = NSSegmentSwitchTrackingMomentary;
    segmentedControl.segmentCount = items.count;
    segmentedControl.target = self;
    segmentedControl.action = @selector(selectedToolbarItemGroupItem:);
    
    int segmentIndex = 0;
    
    for (NSToolbarItem *subItem in items)
    {
        [segmentedControl setImage:subItem.image forSegment:segmentIndex];
        [segmentedControl setImageScaling:NSImageScaleProportionallyDown forSegment:segmentIndex];
        [segmentedControl setWidth:itemWidth-4 forSegment:segmentIndex];
        if (@available(macOS 10.13, *)) {
            [segmentedControl setToolTip:subItem.label forSegment:segmentIndex];
        }
        
        segmentIndex++;
    }
    
    itemGroup.view = segmentedControl;
    
    [self->toolbarItemIdentifierObjectDictionary setObject:itemGroup forKey:itemIdentifier];
    
    return itemGroup;
}

/**
 * Factory method for creating and configuring a NSToolbarItem object.
 */
- (NSToolbarItem *)toolbarItemWithIdentifier:(NSString *)itemIdentifier label:(NSString *)label icon:(NSString *)iconImageName action:(SEL)action {
    NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    toolbarItem.label = label;
    toolbarItem.paletteLabel = label;
    toolbarItem.toolTip = label;
    
    NSImage *itemImage = [NSImage imageNamed:iconImageName];
    [itemImage setTemplate:YES];
    [itemImage setSize:CGSizeMake(19, 19)];
    NSButton *itemButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, itemWidth, 27)];
    itemButton.image = itemImage;
    itemButton.imageScaling = NSImageScaleProportionallyDown;
    itemButton.bezelStyle = NSBezelStyleTexturedRounded;
    itemButton.focusRingType = NSFocusRingTypeDefault;
    [self->standaloneItemActions setObject:NSStringFromSelector(action)
                                    forKey:itemIdentifier];
    itemButton.identifier = itemIdentifier;
    itemButton.target = self;
    itemButton.action = @selector(standaloneToolbarItemClicked:);
    
    toolbarItem.view = itemButton;
    
    [self->toolbarItemIdentifierObjectDictionary setObject:toolbarItem forKey:itemIdentifier];
    
    return toolbarItem;
}

/**
 * Factory method for creating and configuring a NSToolbarItem object with a NSPopupButton holding menu options as passed in the menuItems parameter.
 */
- (NSToolbarItem *)toolbarItemDropDownWithIdentifier:(NSString *)itemIdentifier label:(NSString *)label icon:(NSString *)iconImageName menuItems:(NSArray <NSMenuItem *>*)menuItems {
    NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    toolbarItem.label = label;
    toolbarItem.paletteLabel = label;
    toolbarItem.toolTip = label;
    
    NSImage *itemImage = [NSImage imageNamed:iconImageName];
    [itemImage setTemplate:YES];
    [itemImage setSize:CGSizeMake(19, 19)];
    
    NSPopUpButton *popupButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 42, 27) pullsDown:YES];
    popupButton.bezelStyle = NSBezelStyleTexturedRounded;
    popupButton.focusRingType = NSFocusRingTypeDefault;
    //popupButton.imageScaling = NSImageScaleProportionallyDown;
    
    // First item's image is displayed as button image, therefor we need a dummy with the icon
    [popupButton addItemWithTitle:@""];
    [[popupButton lastItem] setImage:itemImage];
    
    for (NSMenuItem *menuItem in menuItems) {
        [popupButton addItemWithTitle:menuItem.title];
        [[popupButton lastItem] setRepresentedObject:NSStringFromSelector(menuItem.action)];
        [[popupButton lastItem] setTarget:self];
        [[popupButton lastItem] setAction:@selector(dropdownMenuItemClicked:)];
    }

    toolbarItem.view = popupButton;

    [self->toolbarItemIdentifierObjectDictionary setObject:toolbarItem forKey:itemIdentifier];

    return toolbarItem;
}

/**
 * Factory method for the document-zoom popup. Unlike the layout dropdown
 * this is a regular (non-pull-down) NSPopUpButton: the currently selected
 * item is shown as the button label so the user sees the active zoom
 * percentage at a glance. Each menu item is wired to
 * -selectDocumentZoom: on the document, with the target zoom level
 * (NSNumber) attached as the item's representedObject.
 */
- (NSToolbarItem *)toolbarItemDocumentZoomPopUpWithIdentifier:(NSString *)itemIdentifier label:(NSString *)label
{
    NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    toolbarItem.label = label;
    toolbarItem.paletteLabel = label;
    toolbarItem.toolTip = label;

    NSPopUpButton *popupButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 70, 27) pullsDown:NO];
    popupButton.bezelStyle = NSBezelStyleTexturedRounded;
    popupButton.focusRingType = NSFocusRingTypeDefault;

    NSArray<NSNumber *> *levels = MPToolbarDocumentZoomLevels();
    for (NSNumber *level in levels)
    {
        NSString *title = [NSString stringWithFormat:@"%.0f%%", level.doubleValue * 100.0];
        [popupButton addItemWithTitle:title];
        NSMenuItem *added = [popupButton lastItem];
        added.representedObject = level;
        added.target = self.document;
        added.action = @selector(selectDocumentZoom:);
    }

    toolbarItem.view = popupButton;

    [self->toolbarItemIdentifierObjectDictionary setObject:toolbarItem forKey:itemIdentifier];
    _zoomPopUp = popupButton;

    return toolbarItem;
}

/**
 * Update the popup's selection to match the current document-zoom
 * preference. If the current preference matches a preset (within
 * epsilon), that item is selected. Otherwise the popup falls back to
 * the closest preset so the button always shows a sensible label.
 */
- (void)syncDocumentZoomDisplay
{
    NSPopUpButton *popup = _zoomPopUp;
    if (!popup)
        return;

    CGFloat current = [MPPreferences sharedInstance].documentZoomLevel;
    NSArray<NSNumber *> *levels = MPToolbarDocumentZoomLevels();

    NSUInteger nearestIdx = 0;
    CGFloat bestDiff = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < levels.count; i++)
    {
        CGFloat diff = fabs(levels[i].doubleValue - current);
        if (diff < bestDiff)
        {
            bestDiff = diff;
            nearestIdx = i;
        }
    }
    [popup selectItemAtIndex:(NSInteger)nearestIdx];
}


@end
