//
//  MPPreferencesViewControllerResizabilityTests.m
//  MacDownTests
//
//  Tests for preference panel resizability (Issues #361, #362).
//  Verifies that all five preference panels declare themselves as resizable.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "MPPreferencesViewController.h"
#import "MPGeneralPreferencesViewController.h"
#import "MPMarkdownPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPHtmlPreferencesViewController.h"
#import "MPTerminalPreferencesViewController.h"

#pragma mark - View-tree helpers

/// Recursively gathers every descendant of @c view (including @c view itself)
/// that is a kind of @c cls. NSBox content views are reached because an
/// NSBox lists its content view among its subviews.
static void MPCollectViews(NSView *view, Class cls, NSMutableArray *out)
{
    if ([view isKindOfClass:cls])
        [out addObject:view];
    for (NSView *sub in view.subviews)
        MPCollectViews(sub, cls, out);
}

/// Returns the first descendant (including @c view) with ambiguous layout, or
/// nil if the whole tree is unambiguous.
static NSView *MPFirstAmbiguousView(NSView *view)
{
    if (view.hasAmbiguousLayout)
        return view;
    for (NSView *sub in view.subviews)
    {
        NSView *found = MPFirstAmbiguousView(sub);
        if (found)
            return found;
    }
    return nil;
}

/// Loads a preference controller's view and returns the wrapped content view
/// (the original XIB view, which loadView centers inside a resizable wrapper).
static NSView *MPContentView(MPPreferencesViewController *vc)
{
    NSView *wrapper = vc.view;          // triggers loadView
    [wrapper layoutSubtreeIfNeeded];
    return wrapper.subviews.firstObject;
}

/// Collects the checkbox buttons in a pane. Checkboxes use the regular-square
/// bezel; push buttons (e.g. "Change…") are rounded, so this excludes them.
static NSArray<NSButton *> *MPCheckboxes(NSView *content)
{
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    MPCollectViews(content, [NSButton class], buttons);
    NSMutableArray<NSButton *> *checkboxes = [NSMutableArray array];
    for (NSButton *button in buttons)
    {
        if (button.bezelStyle == NSBezelStyleRegularSquare)
            [checkboxes addObject:button];
    }
    return checkboxes;
}

@interface MPPreferencesViewControllerResizabilityTests : XCTestCase
@end

@implementation MPPreferencesViewControllerResizabilityTests

#pragma mark - hasResizableWidth

- (void)testGeneralPanelRespondsToHasResizableWidth
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"General panel should respond to hasResizableWidth");
}

- (void)testMarkdownPanelRespondsToHasResizableWidth
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Markdown panel should respond to hasResizableWidth");
}

- (void)testEditorPanelRespondsToHasResizableWidth
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Editor panel should respond to hasResizableWidth");
}

- (void)testHtmlPanelRespondsToHasResizableWidth
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Html panel should respond to hasResizableWidth");
}

- (void)testTerminalPanelRespondsToHasResizableWidth
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Terminal panel should respond to hasResizableWidth");
}

#pragma mark - hasResizableHeight

- (void)testGeneralPanelRespondsToHasResizableHeight
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"General panel should respond to hasResizableHeight");
}

- (void)testMarkdownPanelRespondsToHasResizableHeight
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Markdown panel should respond to hasResizableHeight");
}

- (void)testEditorPanelRespondsToHasResizableHeight
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Editor panel should respond to hasResizableHeight");
}

- (void)testHtmlPanelRespondsToHasResizableHeight
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Html panel should respond to hasResizableHeight");
}

- (void)testTerminalPanelRespondsToHasResizableHeight
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Terminal panel should respond to hasResizableHeight");
}

#pragma mark - Return values

- (void)testGeneralPanelHasResizableWidth
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"General panel hasResizableWidth should return YES");
}

- (void)testGeneralPanelHasResizableHeight
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"General panel hasResizableHeight should return YES");
}

- (void)testMarkdownPanelHasResizableWidth
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Markdown panel hasResizableWidth should return YES");
}

- (void)testMarkdownPanelHasResizableHeight
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Markdown panel hasResizableHeight should return YES");
}

- (void)testEditorPanelHasResizableWidth
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Editor panel hasResizableWidth should return YES");
}

- (void)testEditorPanelHasResizableHeight
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Editor panel hasResizableHeight should return YES");
}

- (void)testHtmlPanelHasResizableWidth
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Html panel hasResizableWidth should return YES");
}

- (void)testHtmlPanelHasResizableHeight
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Html panel hasResizableHeight should return YES");
}

- (void)testTerminalPanelHasResizableWidth
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Terminal panel hasResizableWidth should return YES");
}

- (void)testTerminalPanelHasResizableHeight
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Terminal panel hasResizableHeight should return YES");
}

#pragma mark - Locale-aware layout (Issue #397)

// Every preference controller, keyed by a readable name, for table-driven tests.
- (NSDictionary<NSString *, MPPreferencesViewController *> *)allControllers
{
    return @{
        @"General":  [[MPGeneralPreferencesViewController alloc] init],
        @"Markdown": [[MPMarkdownPreferencesViewController alloc] init],
        @"Editor":   [[MPEditorPreferencesViewController alloc] init],
        @"Html":     [[MPHtmlPreferencesViewController alloc] init],
        @"Terminal": [[MPTerminalPreferencesViewController alloc] init],
    };
}

// The boxes that group checkboxes must hug their content rather than fixing a
// height, otherwise wrapped (e.g. French) text gets clipped — the Editor
// "Behavior" box did this with a hard height=200 constraint.
- (void)testGroupingBoxesHaveNoFixedHeight
{
    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        NSView *content = MPContentView(vc);
        NSMutableArray<NSBox *> *boxes = [NSMutableArray array];
        MPCollectViews(content, [NSBox class], boxes);
        for (NSBox *box in boxes)
        {
            for (NSLayoutConstraint *c in box.constraints)
            {
                BOOL fixesHeight = (c.active
                    && c.firstItem == box && c.secondItem == nil
                    && c.firstAttribute == NSLayoutAttributeHeight
                    && c.relation == NSLayoutRelationEqual
                    && c.constant > 0);
                XCTAssertFalse(fixesHeight,
                    @"%@ pane: grouping box must hug its content, not pin a fixed "
                    @"height (found %@)", name, c);
            }
        }
    }];
}

// Coupling two labels' widths makes the longer localized label dictate the
// other's column width, which pushes adjacent controls into overlap (the
// Compilation pane coupled "CSS:" to "Default path:"). Labels must size
// independently.
- (void)testHtmlLabelWidthsAreIndependent
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    NSView *content = MPContentView(vc);
    for (NSLayoutConstraint *c in content.constraints)
    {
        BOOL couplesLabelWidths = (c.active
            && c.firstAttribute == NSLayoutAttributeWidth
            && c.secondAttribute == NSLayoutAttributeWidth
            && [c.firstItem isKindOfClass:[NSTextField class]]
            && [c.secondItem isKindOfClass:[NSTextField class]]);
        XCTAssertFalse(couplesLabelWidths,
            @"Html pane: label widths must be independent so a long localized "
            @"label cannot force an adjacent column to overlap (found %@)", c);
    }
}

// Checkbox titles must wrap; otherwise long localized titles are truncated or
// clipped instead of flowing onto a second line.
- (void)testCheckboxTitlesWrap
{
    // Terminal has no checkboxes; track the total so the suite still proves it
    // exercised real controls across the panes that do.
    __block NSUInteger totalCheckboxes = 0;
    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        NSView *content = MPContentView(vc);
        NSArray<NSButton *> *checkboxes = MPCheckboxes(content);
        totalCheckboxes += checkboxes.count;
        for (NSButton *checkbox in checkboxes)
        {
            NSCell *cell = checkbox.cell;
            XCTAssertEqual(cell.lineBreakMode, NSLineBreakByWordWrapping,
                @"%@ pane: checkbox '%@' must wrap long localized titles",
                name, checkbox.title);
        }
    }];
    XCTAssertGreaterThan(totalCheckboxes, 0,
        @"expected to find checkboxes across the preference panes");
}

// No pane should ship with ambiguous Auto Layout — that would make localized
// positioning undefined.
- (void)testPanesHaveNoAmbiguousLayout
{
    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        NSView *content = MPContentView(vc);
        NSView *ambiguous = MPFirstAmbiguousView(content);
        XCTAssertNil(ambiguous,
            @"%@ pane: view has ambiguous layout: %@", name, ambiguous);
    }];
}

// loadView must size each pane to fit its content for the active locale rather
// than the static English design frame, so localized text is never clipped.
- (void)testContentIsSizedToFitItsContent
{
    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        NSView *content = MPContentView(vc);

        // The width/height pins loadView applies to the content view.
        NSLayoutConstraint *widthPin = nil, *heightPin = nil;
        for (NSLayoutConstraint *c in content.constraints)
        {
            if (c.firstItem != content || c.secondItem != nil
                || c.relation != NSLayoutRelationEqual)
                continue;
            if (c.firstAttribute == NSLayoutAttributeWidth)
                widthPin = c;
            else if (c.firstAttribute == NSLayoutAttributeHeight)
                heightPin = c;
        }
        XCTAssertNotNil(widthPin,
            @"%@ pane: loadView should pin the content width", name);
        XCTAssertNotNil(heightPin,
            @"%@ pane: loadView should pin the content height", name);

        // Measure the height the content needs at its pinned width (the width
        // must stay fixed, or wrapping labels would balloon the height). The
        // applied height must accommodate that — i.e. nothing is clipped.
        CGFloat appliedHeight = heightPin.constant;
        heightPin.active = NO;
        [content layoutSubtreeIfNeeded];
        CGFloat neededHeight = content.fittingSize.height;

        XCTAssertGreaterThanOrEqual(appliedHeight + 0.5, neededHeight,
            @"%@ pane: content height (%g) must accommodate its content (%g)",
            name, appliedHeight, neededHeight);
    }];
}

@end
