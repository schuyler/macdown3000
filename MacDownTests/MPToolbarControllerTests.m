//
//  MPToolbarControllerTests.m
//  MacDownTests
//
//  Tests for Issue #313: Can't add Flexible Space to Toolbar
//  Verifies that all NSToolbarDelegate methods return correct identifiers,
//  including space, flexible space, and separator items in the allowed set,
//  and that selectable identifiers contain only custom (non-space) items.
//

#import <XCTest/XCTest.h>
#import "MPToolbarController.h"

// Expose internal action methods to the test target; they are not part of
// the public header but are callable via dynamic dispatch.
@interface MPToolbarController (MPToolbarControllerTests)
- (void)selectedToolbarItemGroupItem:(NSSegmentedControl *)sender;
- (void)standaloneToolbarItemClicked:(NSButton *)sender;
- (void)dropdownMenuItemClicked:(NSMenuItem *)sender;
@end


// Lightweight mock that records which selectors were invoked on it.
// Used to verify toolbar dispatch reaches the document with the correct action.
@interface MPToolbarDispatchRecorder : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *invokedSelectors;
@end

@implementation MPToolbarDispatchRecorder

- (instancetype)init
{
    self = [super init];
    if (self) {
        _invokedSelectors = [NSMutableArray array];
    }
    return self;
}

// Accept any message and record its selector name.
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    // Return a signature for a method that takes one object argument (sender).
    return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    [self.invokedSelectors addObject:NSStringFromSelector(anInvocation.selector)];
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    // Claim to respond to any selector so performSelector: dispatch proceeds.
    return YES;
}

@end

@interface MPToolbarControllerTests : XCTestCase
@property (strong) MPToolbarController *controller;
@end


@implementation MPToolbarControllerTests

- (void)setUp
{
    [super setUp];
    self.controller = [[MPToolbarController alloc] init];
}

- (void)tearDown
{
    self.controller = nil;
    [super tearDown];
}


#pragma mark - Initialization Tests

- (void)testControllerCanBeCreated
{
    XCTAssertNotNil(self.controller,
                    @"MPToolbarController should be creatable via alloc/init");
}

- (void)testControllerConformsToNSToolbarDelegate
{
    XCTAssertTrue([self.controller conformsToProtocol:@protocol(NSToolbarDelegate)],
                  @"MPToolbarController should conform to NSToolbarDelegate");
}


#pragma mark - toolbarAllowedItemIdentifiers: Tests (Issue #313)

- (void)testAllowedIdentifiersIncludeFlexibleSpace
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    XCTAssertTrue([allowed containsObject:NSToolbarFlexibleSpaceItemIdentifier],
                  @"Allowed identifiers must include NSToolbarFlexibleSpaceItemIdentifier "
                  @"so users can add flexible spaces via toolbar customization");
}

- (void)testAllowedIdentifiersIncludeSpace
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    XCTAssertTrue([allowed containsObject:NSToolbarSpaceItemIdentifier],
                  @"Allowed identifiers must include NSToolbarSpaceItemIdentifier "
                  @"so users can add fixed spaces via toolbar customization");
}

- (void)testAllowedIdentifiersIncludeSeparator
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    XCTAssertTrue([allowed containsObject:NSToolbarSeparatorItemIdentifier],
                  @"Allowed identifiers must include NSToolbarSeparatorItemIdentifier "
                  @"so users can add separators via toolbar customization");
}

- (void)testAllowedIdentifiersContainAllCustomItems
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];

    NSArray *expectedCustomIdentifiers = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group",
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"table",
        @"copy-html",
        @"comment",
        @"highlight",
        @"strikethrough",
        @"layout"
    ];

    for (NSString *identifier in expectedCustomIdentifiers) {
        XCTAssertTrue([allowed containsObject:identifier],
                      @"Allowed identifiers should contain '%@'", identifier);
    }
}

- (void)testAllowedIdentifiersTotalCount
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    // 14 custom + 3 system (flexible space, space, separator)
    XCTAssertEqual(allowed.count, 17,
                   @"Allowed identifiers should have 17 items: "
                   @"14 custom + flexible space + space + separator");
}

- (void)testAllowedIdentifiersOrderCustomItemsFirst
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];

    NSArray *expectedOrder = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group",
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"table",
        @"copy-html",
        @"comment",
        @"highlight",
        @"strikethrough",
        @"layout"
    ];

    for (NSUInteger i = 0; i < expectedOrder.count; i++) {
        XCTAssertEqualObjects(allowed[i], expectedOrder[i],
                              @"Allowed identifier at index %lu should be '%@', got '%@'",
                              (unsigned long)i, expectedOrder[i], allowed[i]);
    }

    NSUInteger flexIdx = [allowed indexOfObject:NSToolbarFlexibleSpaceItemIdentifier];
    NSUInteger spaceIdx = [allowed indexOfObject:NSToolbarSpaceItemIdentifier];
    NSUInteger sepIdx = [allowed indexOfObject:NSToolbarSeparatorItemIdentifier];

    XCTAssertTrue(flexIdx >= expectedOrder.count,
                  @"NSToolbarFlexibleSpaceItemIdentifier should be appended after custom items");
    XCTAssertTrue(spaceIdx >= expectedOrder.count,
                  @"NSToolbarSpaceItemIdentifier should be appended after custom items");
    XCTAssertTrue(sepIdx >= expectedOrder.count,
                  @"NSToolbarSeparatorItemIdentifier should be appended after custom items");
}

- (void)testAllowedIdentifiersNoDuplicateSystemItems
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];

    NSUInteger flexCount = [[allowed filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"SELF == %@", NSToolbarFlexibleSpaceItemIdentifier]] count];
    NSUInteger spaceCount = [[allowed filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"SELF == %@", NSToolbarSpaceItemIdentifier]] count];
    NSUInteger sepCount = [[allowed filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"SELF == %@", NSToolbarSeparatorItemIdentifier]] count];

    XCTAssertEqual(flexCount, 1,
                   @"NSToolbarFlexibleSpaceItemIdentifier should appear exactly once");
    XCTAssertEqual(spaceCount, 1,
                   @"NSToolbarSpaceItemIdentifier should appear exactly once");
    XCTAssertEqual(sepCount, 1,
                   @"NSToolbarSeparatorItemIdentifier should appear exactly once");
}

- (void)testAllowedIdentifiersAcceptsNilToolbar
{
    XCTAssertNoThrow([self.controller toolbarAllowedItemIdentifiers:nil],
                     @"toolbarAllowedItemIdentifiers: should accept nil toolbar");
}


#pragma mark - toolbarSelectableItemIdentifiers: Tests

- (void)testSelectableIdentifiersExcludeFlexibleSpace
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];
    XCTAssertFalse([selectable containsObject:NSToolbarFlexibleSpaceItemIdentifier],
                   @"Selectable identifiers must NOT include NSToolbarFlexibleSpaceItemIdentifier");
}

- (void)testSelectableIdentifiersExcludeSpace
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];
    XCTAssertFalse([selectable containsObject:NSToolbarSpaceItemIdentifier],
                   @"Selectable identifiers must NOT include NSToolbarSpaceItemIdentifier");
}

- (void)testSelectableIdentifiersExcludeSeparator
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];
    XCTAssertFalse([selectable containsObject:NSToolbarSeparatorItemIdentifier],
                   @"Selectable identifiers must NOT include NSToolbarSeparatorItemIdentifier");
}

- (void)testSelectableIdentifiersContainAllCustomItems
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];

    NSArray *expectedCustomIdentifiers = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group",
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"table",
        @"copy-html",
        @"comment",
        @"highlight",
        @"strikethrough",
        @"layout"
    ];

    for (NSString *identifier in expectedCustomIdentifiers) {
        XCTAssertTrue([selectable containsObject:identifier],
                      @"Selectable identifiers should contain '%@'", identifier);
    }
}

- (void)testSelectableIdentifiersCount
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];
    XCTAssertEqual(selectable.count, 14,
                   @"Selectable identifiers should have exactly 14 items (custom only, no system items)");
}

- (void)testSelectableIdentifiersAcceptsNilToolbar
{
    XCTAssertNoThrow([self.controller toolbarSelectableItemIdentifiers:nil],
                     @"toolbarSelectableItemIdentifiers: should accept nil toolbar");
}


#pragma mark - toolbarDefaultItemIdentifiers: Tests

- (void)testDefaultIdentifiersExcludeCommentHighlightStrikethrough
{
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];

    NSMutableArray *customDefaults = [NSMutableArray array];
    for (NSString *identifier in defaults) {
        if (![identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]
            && ![identifier isEqualToString:NSToolbarSpaceItemIdentifier]) {
            [customDefaults addObject:identifier];
        }
    }

    XCTAssertFalse([customDefaults containsObject:@"comment"],
                   @"Default toolbar should not include 'comment'");
    XCTAssertFalse([customDefaults containsObject:@"highlight"],
                   @"Default toolbar should not include 'highlight'");
    XCTAssertFalse([customDefaults containsObject:@"strikethrough"],
                   @"Default toolbar should not include 'strikethrough'");
}

- (void)testDefaultIdentifiersIncludeExpectedCustomItems
{
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];

    NSArray *expectedInDefaults = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group",
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"table",
        @"copy-html",
        @"layout"
    ];

    for (NSString *identifier in expectedInDefaults) {
        XCTAssertTrue([defaults containsObject:identifier],
                      @"Default identifiers should contain '%@'", identifier);
    }
}

- (void)testDefaultIdentifiersContainFlexibleSpaces
{
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];

    NSUInteger flexCount = 0;
    for (NSString *identifier in defaults) {
        if ([identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
            flexCount++;
        }
    }

    XCTAssertEqual(flexCount, 5,
                   @"Default toolbar should contain exactly 5 flexible space items");
}

- (void)testDefaultIdentifiersTotalCount
{
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];
    XCTAssertEqual(defaults.count, 16,
                   @"Default toolbar should have 16 items: 11 custom + 5 flexible spaces");
}

- (void)testDefaultIdentifiersDoNotContainFixedSpaces
{
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];
    XCTAssertFalse([defaults containsObject:NSToolbarSpaceItemIdentifier],
                   @"Default toolbar should not contain fixed space items");
}

- (void)testDefaultIdentifiersExactOrder
{
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];

    NSArray *expected = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"list-group",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"blockquote",
        @"code",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"link",
        @"image",
        @"table",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"copy-html",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"layout"
    ];

    XCTAssertEqual(defaults.count, expected.count,
                   @"Default toolbar length should match expected length");

    for (NSUInteger i = 0; i < MIN(defaults.count, expected.count); i++) {
        XCTAssertEqualObjects(defaults[i], expected[i],
                              @"Default toolbar item at index %lu should be '%@', got '%@'",
                              (unsigned long)i, expected[i], defaults[i]);
    }
}

- (void)testDefaultIdentifiersAcceptsNilToolbar
{
    XCTAssertNoThrow([self.controller toolbarDefaultItemIdentifiers:nil],
                     @"toolbarDefaultItemIdentifiers: should accept nil toolbar");
}


#pragma mark - toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: Tests

- (void)testItemForValidIdentifierReturnsNonNil
{
    NSArray *customIdentifiers = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group",
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"table",
        @"copy-html",
        @"comment",
        @"highlight",
        @"strikethrough",
        @"layout"
    ];

    for (NSString *identifier in customIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item,
                        @"toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: "
                        @"should return non-nil for '%@'", identifier);
    }
}

- (void)testItemForIdentifierHasCorrectIdentifier
{
    NSArray *customIdentifiers = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group",
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"table",
        @"copy-html",
        @"comment",
        @"highlight",
        @"strikethrough",
        @"layout"
    ];

    for (NSString *identifier in customIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        XCTAssertEqualObjects(item.itemIdentifier, identifier,
                              @"Returned item identifier should match requested '%@'", identifier);
    }
}

- (void)testItemForUnknownIdentifierReturnsNil
{
    NSToolbarItem *item = [self.controller toolbar:nil
                             itemForItemIdentifier:@"nonexistent-item"
                         willBeInsertedIntoToolbar:YES];
    XCTAssertNil(item,
                 @"toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: "
                 @"should return nil for unknown identifier");
}

- (void)testItemForFlexibleSpaceIdentifierReturnsNil
{
    NSToolbarItem *item = [self.controller toolbar:nil
                             itemForItemIdentifier:NSToolbarFlexibleSpaceItemIdentifier
                         willBeInsertedIntoToolbar:YES];
    XCTAssertNil(item,
                 @"Flexible space items are provided by AppKit, not the controller");
}

- (void)testItemForSpaceIdentifierReturnsNil
{
    NSToolbarItem *item = [self.controller toolbar:nil
                             itemForItemIdentifier:NSToolbarSpaceItemIdentifier
                         willBeInsertedIntoToolbar:YES];
    XCTAssertNil(item,
                 @"Space items are provided by AppKit, not the controller");
}

- (void)testItemForSeparatorIdentifierReturnsNil
{
    NSToolbarItem *item = [self.controller toolbar:nil
                             itemForItemIdentifier:NSToolbarSeparatorItemIdentifier
                         willBeInsertedIntoToolbar:YES];
    XCTAssertNil(item,
                 @"Separator items are provided by AppKit, not the controller");
}

- (void)testItemForIdentifierWorksWithBothInsertedFlags
{
    NSToolbarItem *itemYes = [self.controller toolbar:nil
                                itemForItemIdentifier:@"blockquote"
                            willBeInsertedIntoToolbar:YES];
    NSToolbarItem *itemNo = [self.controller toolbar:nil
                               itemForItemIdentifier:@"blockquote"
                           willBeInsertedIntoToolbar:NO];

    XCTAssertNotNil(itemYes, @"Should return item when willBeInsertedIntoToolbar is YES");
    XCTAssertNotNil(itemNo, @"Should return item when willBeInsertedIntoToolbar is NO");
    XCTAssertEqual(itemYes, itemNo,
                   @"Same item object should be returned regardless of willBeInsertedIntoToolbar");
}

- (void)testAllItemsHaveLabels
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];

    for (NSString *identifier in selectable) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item.label,
                        @"Toolbar item '%@' should have a label", identifier);
        XCTAssertGreaterThan(item.label.length, 0,
                             @"Toolbar item '%@' label should not be empty", identifier);
    }
}

- (void)testAllItemsHavePaletteLabels
{
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];

    for (NSString *identifier in selectable) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item.paletteLabel,
                        @"Toolbar item '%@' should have a palette label", identifier);
        XCTAssertGreaterThan(item.paletteLabel.length, 0,
                             @"Toolbar item '%@' palette label should not be empty", identifier);
    }
}


#pragma mark - Relationship Between Delegate Methods

- (void)testSelectableIsSubsetOfAllowed
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];

    NSSet *allowedSet = [NSSet setWithArray:allowed];

    for (NSString *identifier in selectable) {
        XCTAssertTrue([allowedSet containsObject:identifier],
                      @"Selectable identifier '%@' must also be in allowed identifiers", identifier);
    }
}

- (void)testAllowedHasMoreItemsThanSelectable
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];

    XCTAssertEqual(allowed.count, selectable.count + 3,
                   @"Allowed identifiers should have exactly 3 more items than selectable "
                   @"(flexible space, fixed space, and separator identifiers)");
}

- (void)testDefaultCustomItemsAreSubsetOfAllowed
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    NSArray *defaults = [self.controller toolbarDefaultItemIdentifiers:nil];

    NSSet *allowedSet = [NSSet setWithArray:allowed];

    for (NSString *identifier in defaults) {
        XCTAssertTrue([allowedSet containsObject:identifier],
                      @"Default identifier '%@' must also be in allowed identifiers", identifier);
    }
}

- (void)testDifferenceBetweenAllowedAndSelectableIsOnlySystemItems
{
    NSArray *allowed = [self.controller toolbarAllowedItemIdentifiers:nil];
    NSArray *selectable = [self.controller toolbarSelectableItemIdentifiers:nil];

    NSMutableSet *allowedSet = [NSMutableSet setWithArray:allowed];
    NSSet *selectableSet = [NSSet setWithArray:selectable];

    [allowedSet minusSet:selectableSet];

    NSSet *expectedDifference = [NSSet setWithObjects:
        NSToolbarFlexibleSpaceItemIdentifier,
        NSToolbarSpaceItemIdentifier,
        NSToolbarSeparatorItemIdentifier,
        nil];

    XCTAssertEqualObjects(allowedSet, expectedDifference,
                          @"The only items in allowed but not in selectable should be "
                          @"the three system toolbar identifiers");
}


#pragma mark - Idempotency and Consistency Tests

- (void)testAllowedIdentifiersAreConsistentAcrossCalls
{
    NSArray *first = [self.controller toolbarAllowedItemIdentifiers:nil];
    NSArray *second = [self.controller toolbarAllowedItemIdentifiers:nil];

    XCTAssertEqualObjects(first, second,
                          @"toolbarAllowedItemIdentifiers: should return the same result on repeated calls");
}

- (void)testSelectableIdentifiersAreConsistentAcrossCalls
{
    NSArray *first = [self.controller toolbarSelectableItemIdentifiers:nil];
    NSArray *second = [self.controller toolbarSelectableItemIdentifiers:nil];

    XCTAssertEqualObjects(first, second,
                          @"toolbarSelectableItemIdentifiers: should return the same result on repeated calls");
}

- (void)testDefaultIdentifiersAreConsistentAcrossCalls
{
    NSArray *first = [self.controller toolbarDefaultItemIdentifiers:nil];
    NSArray *second = [self.controller toolbarDefaultItemIdentifiers:nil];

    XCTAssertEqualObjects(first, second,
                          @"toolbarDefaultItemIdentifiers: should return the same result on repeated calls");
}

- (void)testDifferentInstancesReturnSameIdentifiers
{
    MPToolbarController *other = [[MPToolbarController alloc] init];

    NSArray *allowed1 = [self.controller toolbarAllowedItemIdentifiers:nil];
    NSArray *allowed2 = [other toolbarAllowedItemIdentifiers:nil];
    XCTAssertEqualObjects(allowed1, allowed2,
                          @"Different controller instances should return same allowed identifiers");

    NSArray *selectable1 = [self.controller toolbarSelectableItemIdentifiers:nil];
    NSArray *selectable2 = [other toolbarSelectableItemIdentifiers:nil];
    XCTAssertEqualObjects(selectable1, selectable2,
                          @"Different controller instances should return same selectable identifiers");

    NSArray *defaults1 = [self.controller toolbarDefaultItemIdentifiers:nil];
    NSArray *defaults2 = [other toolbarDefaultItemIdentifiers:nil];
    XCTAssertEqualObjects(defaults1, defaults2,
                          @"Different controller instances should return same default identifiers");
}


#pragma mark - Toolbar Item Group Tests

- (void)testGroupIdentifiersReturnToolbarItemGroups
{
    NSArray *groupIdentifiers = @[
        @"indent-group",
        @"text-formatting-group",
        @"heading-group",
        @"list-group"
    ];

    for (NSString *identifier in groupIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        XCTAssertTrue([item isKindOfClass:[NSToolbarItemGroup class]],
                      @"'%@' should return an NSToolbarItemGroup, got %@",
                      identifier, NSStringFromClass([item class]));
    }
}

- (void)testStandaloneItemsHaveViews
{
    NSArray *standaloneIdentifiers = @[
        @"blockquote",
        @"code",
        @"link",
        @"image",
        @"copy-html",
        @"comment",
        @"highlight",
        @"strikethrough"
    ];

    for (NSString *identifier in standaloneIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item.view,
                        @"Standalone toolbar item '%@' should have a view", identifier);
    }
}

- (void)testLayoutItemHasPopUpButtonView
{
    NSToolbarItem *item = [self.controller toolbar:nil
                             itemForItemIdentifier:@"layout"
                         willBeInsertedIntoToolbar:YES];

    XCTAssertNotNil(item.view, @"Layout item should have a view");
    XCTAssertTrue([item.view isKindOfClass:[NSPopUpButton class]],
                  @"Layout item view should be an NSPopUpButton");
}


#pragma mark - selectedToolbarItemGroupItem: Tests (Issue #394)

// CI runs tests in Debug with ENABLE_NS_ASSERTIONS enabled, so the nil- and
// bounds-guards' NSAsserts raise NSInternalInconsistencyException. In Release
// the asserts compile away and the trailing `if ... return;` keeps users out
// of the crash path; that branch is not directly testable from XCTest.

- (void)testSelectedToolbarItemGroupItemUnknownIdentifierAsserts
{
    NSSegmentedControl *sender = [[NSSegmentedControl alloc] init];
    sender.identifier = @"nonexistent-group";
    sender.segmentCount = 1;
    sender.selectedSegment = 0;

    XCTAssertThrowsSpecificNamed([self.controller selectedToolbarItemGroupItem:sender],
                                 NSException, NSInternalInconsistencyException,
                                 @"selectedToolbarItemGroupItem: must assert in Debug "
                                 @"when sender.identifier is not registered in the dictionary");
}

- (void)testSelectedToolbarItemGroupItemOutOfBoundsIndexAsserts
{
    // indent-group has 2 subitems; segment 2 is one past the end.
    NSSegmentedControl *sender = [[NSSegmentedControl alloc] init];
    sender.identifier = @"indent-group";
    sender.segmentCount = 3;
    sender.selectedSegment = 2;

    XCTAssertThrowsSpecificNamed([self.controller selectedToolbarItemGroupItem:sender],
                                 NSException, NSInternalInconsistencyException,
                                 @"selectedToolbarItemGroupItem: must assert in Debug "
                                 @"when selectedSegment is out of bounds for the group's subitems");
}

- (void)testSelectedToolbarItemGroupItemNegativeIndexAsserts
{
    NSSegmentedControl *sender = [[NSSegmentedControl alloc] init];
    sender.identifier = @"indent-group";
    sender.segmentCount = 2;
    sender.selectedSegment = -1;    // momentary tracking can theoretically produce -1

    // Confirm AppKit didn't clamp the assignment. If this precondition fails
    // on a given macOS version we'll need a different way to reach the
    // negative-index branch.
    XCTAssertEqual(sender.selectedSegment, (NSInteger)-1,
                   @"NSSegmentedControl should accept a -1 selectedSegment for this test");

    XCTAssertThrowsSpecificNamed([self.controller selectedToolbarItemGroupItem:sender],
                                 NSException, NSInternalInconsistencyException,
                                 @"selectedToolbarItemGroupItem: must assert in Debug "
                                 @"when selectedSegment is negative");
}

- (void)testSelectedToolbarItemGroupItemValidCallDoesNotCrash
{
    // Valid identifier and valid index. With no document connected the
    // internal performSelector: block is skipped, so this should complete
    // without throwing.
    NSSegmentedControl *sender = [[NSSegmentedControl alloc] init];
    sender.identifier = @"indent-group";
    sender.segmentCount = 2;
    sender.selectedSegment = 0;

    XCTAssertNoThrow([self.controller selectedToolbarItemGroupItem:sender],
                     @"selectedToolbarItemGroupItem: must not throw for a valid "
                     @"group identifier and in-bounds selected segment");
}

- (void)testGroupedItemDispatchSendsSubitemActionToDocument
{
    // Clicking a segment in a grouped toolbar item must dispatch that
    // subitem's own action (e.g. toggleStrong:) to the document. Previous
    // group tests only covered crash-freedom and bounds, never which selector
    // actually arrived, so a regression here could land unnoticed.
    NSDictionary<NSString *, NSArray<NSString *> *> *expectedMappings = @{
        @"indent-group":          @[@"unindent:", @"indent:"],
        @"text-formatting-group": @[@"toggleStrong:", @"toggleEmphasis:", @"toggleUnderline:"],
        @"heading-group":         @[@"convertToH1:", @"convertToH2:", @"convertToH3:"],
        @"list-group":            @[@"toggleUnorderedList:", @"toggleOrderedList:"],
    };

    for (NSString *groupIdentifier in expectedMappings) {
        NSArray<NSString *> *expectedActions = expectedMappings[groupIdentifier];

        for (NSUInteger segment = 0; segment < expectedActions.count; segment++) {
            NSString *expectedAction = expectedActions[segment];

            MPToolbarDispatchRecorder *recorder = [[MPToolbarDispatchRecorder alloc] init];
            self.controller.document = (MPDocument *)recorder;

            NSSegmentedControl *sender = [[NSSegmentedControl alloc] init];
            sender.identifier = groupIdentifier;
            sender.segmentCount = (NSInteger)expectedActions.count;
            sender.selectedSegment = (NSInteger)segment;

            [self.controller selectedToolbarItemGroupItem:sender];

            XCTAssertTrue([recorder.invokedSelectors containsObject:expectedAction],
                          @"Clicking segment %lu of '%@' should dispatch %@ to the "
                          @"document. Got: %@",
                          (unsigned long)segment, groupIdentifier, expectedAction,
                          recorder.invokedSelectors);
        }
    }
}


#pragma mark - Standalone Toolbar Item Dispatch Tests (Issue #278)

- (void)testStandaloneButtonsTargetToolbarController
{
    // Standalone buttons must target the toolbar controller so actions
    // dispatch correctly regardless of which pane has focus.
    NSArray *standaloneIdentifiers = @[
        @"blockquote", @"code", @"link", @"image", @"table",
        @"copy-html", @"comment", @"highlight", @"strikethrough"
    ];

    for (NSString *identifier in standaloneIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        NSButton *button = (NSButton *)item.view;
        XCTAssertEqual(button.target, self.controller,
                       @"Standalone button '%@' must target the toolbar controller, "
                       @"not nil or the document (which is nil during init)",
                       identifier);
    }
}

- (void)testStandaloneButtonsUseDispatchAction
{
    // Standalone buttons must use the dispatch selector, not the
    // document action directly.
    NSArray *standaloneIdentifiers = @[
        @"blockquote", @"code", @"link", @"image", @"table",
        @"copy-html", @"comment", @"highlight", @"strikethrough"
    ];

    SEL expectedAction = @selector(standaloneToolbarItemClicked:);
    for (NSString *identifier in standaloneIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        NSButton *button = (NSButton *)item.view;
        XCTAssertEqual(button.action, expectedAction,
                       @"Standalone button '%@' must use standaloneToolbarItemClicked: action",
                       identifier);
    }
}

- (void)testStandaloneButtonsHaveIdentifierSet
{
    // Each standalone button needs an identifier so the dispatch method
    // can look up the intended action.
    NSArray *standaloneIdentifiers = @[
        @"blockquote", @"code", @"link", @"image", @"table",
        @"copy-html", @"comment", @"highlight", @"strikethrough"
    ];

    for (NSString *identifier in standaloneIdentifiers) {
        NSToolbarItem *item = [self.controller toolbar:nil
                                 itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
        NSButton *button = (NSButton *)item.view;
        XCTAssertEqualObjects(button.identifier, identifier,
                              @"Standalone button '%@' must have its identifier set "
                              @"for action lookup during dispatch",
                              identifier);
    }
}

- (void)testStandaloneDispatchAllActionMappings
{
    // Verify every standalone identifier dispatches the correct action.
    NSDictionary *expectedMappings = @{
        @"blockquote":     @"toggleBlockquote:",
        @"code":           @"toggleInlineCode:",
        @"link":           @"toggleLink:",
        @"image":          @"toggleImage:",
        @"table":          @"insertTable:",
        @"copy-html":      @"copyHtml:",
        @"comment":        @"toggleComment:",
        @"highlight":      @"toggleHighlight:",
        @"strikethrough":  @"toggleStrikethrough:",
    };

    for (NSString *identifier in expectedMappings) {
        NSString *expectedAction = expectedMappings[identifier];
        MPToolbarDispatchRecorder *recorder = [[MPToolbarDispatchRecorder alloc] init];
        self.controller.document = (MPDocument *)recorder;

        NSButton *fakeButton = [[NSButton alloc] init];
        fakeButton.identifier = identifier;

        [self.controller standaloneToolbarItemClicked:fakeButton];

        XCTAssertTrue([recorder.invokedSelectors containsObject:expectedAction],
                      @"standaloneToolbarItemClicked: with identifier '%@' "
                      @"should dispatch %@ to the document. Got: %@",
                      identifier, expectedAction, recorder.invokedSelectors);
    }
}

- (void)testStandaloneDispatchWithNoDocumentDoesNotCrash
{
    // With no document set, dispatch should silently do nothing.
    NSButton *fakeButton = [[NSButton alloc] init];
    fakeButton.identifier = @"table";

    XCTAssertNoThrow([self.controller standaloneToolbarItemClicked:fakeButton],
                     @"standaloneToolbarItemClicked: must not crash when document is nil");
}

- (void)testStandaloneDispatchWithUnknownIdentifierDoesNotCrash
{
    MPToolbarDispatchRecorder *recorder = [[MPToolbarDispatchRecorder alloc] init];
    self.controller.document = (MPDocument *)recorder;

    NSButton *fakeButton = [[NSButton alloc] init];
    fakeButton.identifier = @"nonexistent-item";

    XCTAssertNoThrow([self.controller standaloneToolbarItemClicked:fakeButton],
                     @"standaloneToolbarItemClicked: must not crash for unknown identifier");
    XCTAssertEqual(recorder.invokedSelectors.count, 0,
                   @"No action should be dispatched for unknown identifier");
}


#pragma mark - Dropdown Menu Item Dispatch Tests (Issue #278)

- (void)testDropdownMenuItemsTargetToolbarController
{
    // Dropdown menu items must target the toolbar controller, not the
    // document (which is nil during init).
    NSToolbarItem *layoutItem = [self.controller toolbar:nil
                                   itemForItemIdentifier:@"layout"
                               willBeInsertedIntoToolbar:YES];
    NSPopUpButton *popup = (NSPopUpButton *)layoutItem.view;

    // Guard: the popup must have real menu items beyond the dummy icon at index 0.
    XCTAssertGreaterThan(popup.numberOfItems, 1,
                         @"Layout popup must have menu items beyond the dummy icon item");

    // Skip item 0 (the dummy icon item); real menu items start at index 1.
    for (NSInteger i = 1; i < popup.numberOfItems; i++) {
        NSMenuItem *menuItem = [popup itemAtIndex:i];
        XCTAssertEqual(menuItem.target, self.controller,
                       @"Dropdown menu item '%@' at index %ld must target the toolbar controller",
                       menuItem.title, (long)i);
    }
}

- (void)testDropdownMenuItemsUseDispatchAction
{
    NSToolbarItem *layoutItem = [self.controller toolbar:nil
                                   itemForItemIdentifier:@"layout"
                               willBeInsertedIntoToolbar:YES];
    NSPopUpButton *popup = (NSPopUpButton *)layoutItem.view;

    XCTAssertGreaterThan(popup.numberOfItems, 1,
                         @"Layout popup must have menu items beyond the dummy icon item");

    SEL expectedAction = @selector(dropdownMenuItemClicked:);
    for (NSInteger i = 1; i < popup.numberOfItems; i++) {
        NSMenuItem *menuItem = [popup itemAtIndex:i];
        XCTAssertEqual(menuItem.action, expectedAction,
                       @"Dropdown menu item '%@' at index %ld must use dropdownMenuItemClicked:",
                       menuItem.title, (long)i);
    }
}

- (void)testDropdownMenuItemsStoreActionInRepresentedObject
{
    NSToolbarItem *layoutItem = [self.controller toolbar:nil
                                   itemForItemIdentifier:@"layout"
                               willBeInsertedIntoToolbar:YES];
    NSPopUpButton *popup = (NSPopUpButton *)layoutItem.view;

    XCTAssertGreaterThan(popup.numberOfItems, 1,
                         @"Layout popup must have menu items beyond the dummy icon item");

    // The layout dropdown has toggleEditorPane: and togglePreviewPane:
    NSArray *expectedActions = @[@"toggleEditorPane:", @"togglePreviewPane:"];
    for (NSInteger i = 1; i < popup.numberOfItems; i++) {
        NSMenuItem *menuItem = [popup itemAtIndex:i];
        XCTAssertTrue([menuItem.representedObject isKindOfClass:[NSString class]],
                      @"Dropdown menu item at index %ld should store action name "
                      @"as representedObject string", (long)i);
        NSString *storedAction = menuItem.representedObject;
        XCTAssertTrue([expectedActions containsObject:storedAction],
                      @"Dropdown menu item at index %ld representedObject should be "
                      @"one of %@, got '%@'", (long)i, expectedActions, storedAction);
    }
}

- (void)testDropdownDispatchInvokesCorrectActionOnDocument
{
    MPToolbarDispatchRecorder *recorder = [[MPToolbarDispatchRecorder alloc] init];
    self.controller.document = (MPDocument *)recorder;

    NSMenuItem *fakeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Test"
                                                         action:nil
                                                  keyEquivalent:@""];
    fakeMenuItem.representedObject = @"toggleEditorPane:";

    [self.controller dropdownMenuItemClicked:fakeMenuItem];

    XCTAssertTrue([recorder.invokedSelectors containsObject:@"toggleEditorPane:"],
                  @"dropdownMenuItemClicked: should dispatch toggleEditorPane: "
                  @"to the document");
}

- (void)testDropdownDispatchTogglePreviewPane
{
    MPToolbarDispatchRecorder *recorder = [[MPToolbarDispatchRecorder alloc] init];
    self.controller.document = (MPDocument *)recorder;

    NSMenuItem *fakeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Test"
                                                         action:nil
                                                  keyEquivalent:@""];
    fakeMenuItem.representedObject = @"togglePreviewPane:";

    [self.controller dropdownMenuItemClicked:fakeMenuItem];

    XCTAssertTrue([recorder.invokedSelectors containsObject:@"togglePreviewPane:"],
                  @"dropdownMenuItemClicked: should dispatch togglePreviewPane: "
                  @"to the document");
}

- (void)testDropdownDispatchWithNoDocumentDoesNotCrash
{
    NSMenuItem *fakeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Test"
                                                         action:nil
                                                  keyEquivalent:@""];
    fakeMenuItem.representedObject = @"toggleEditorPane:";

    XCTAssertNoThrow([self.controller dropdownMenuItemClicked:fakeMenuItem],
                     @"dropdownMenuItemClicked: must not crash when document is nil");
}

- (void)testDropdownDispatchWithNilRepresentedObjectDoesNotCrash
{
    MPToolbarDispatchRecorder *recorder = [[MPToolbarDispatchRecorder alloc] init];
    self.controller.document = (MPDocument *)recorder;

    NSMenuItem *fakeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Test"
                                                         action:nil
                                                  keyEquivalent:@""];
    // representedObject is nil by default

    XCTAssertNoThrow([self.controller dropdownMenuItemClicked:fakeMenuItem],
                     @"dropdownMenuItemClicked: must not crash with nil representedObject");
    XCTAssertEqual(recorder.invokedSelectors.count, 0,
                   @"No action should be dispatched for nil representedObject");
}


@end
