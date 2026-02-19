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
    // 13 custom + 3 system (flexible space, space, separator)
    XCTAssertEqual(allowed.count, 16,
                   @"Allowed identifiers should have 16 items: "
                   @"13 custom + flexible space + space + separator");
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
    XCTAssertEqual(selectable.count, 13,
                   @"Selectable identifiers should have exactly 13 items (custom only, no system items)");
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
    XCTAssertEqual(defaults.count, 15,
                   @"Default toolbar should have 15 items: 10 custom + 5 flexible spaces");
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


@end
