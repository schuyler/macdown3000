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
#import "MPPreferences.h"
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

#pragma mark - Localized Editor pane (Issue #530)

/// Editor pane controller that swaps in localized checkbox titles as the NIB's
/// root view is connected, i.e. before MPPreferencesViewController's -loadView
/// runs its sizing passes. @c titleMap maps English title to localized title.
@interface MPLocalizedEditorPreferencesViewController : MPEditorPreferencesViewController
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *titleMap;
@property (nonatomic, assign) BOOL titlesApplied;
@end

@implementation MPLocalizedEditorPreferencesViewController

- (void)setView:(NSView *)view
{
    if (!self.titlesApplied && view && self.titleMap)
    {
        // First call is the NIB connecting its root view; later calls install
        // the sizing wrapper.
        self.titlesApplied = YES;
        NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
        MPCollectViews(view, [NSButton class], buttons);
        for (NSButton *button in buttons)
        {
            NSString *localized = self.titleMap[button.title];
            if (localized)
                button.title = localized;
        }
    }
    [super setView:view];
}

@end

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
                // Only an author-set height pin is a problem. AppKit installs an
                // NSContentSizeLayoutConstraint (a private NSLayoutConstraint
                // subclass) for every box's intrinsic height; that one is
                // expected, so consider only plain NSLayoutConstraint instances.
                BOOL fixesHeight = (c.active
                    && [c isMemberOfClass:[NSLayoutConstraint class]]
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

// The HTML pane's CSS theme popup and its Reveal/Reload controls were clipped
// at the original 430pt design width, most visibly with long theme names such
// as the bundled "GitHub Dark Default". loadView pins each pane to its XIB
// design width (it never widens, only grows height), so the design width itself
// must stay wide enough. This guards against the pane being narrowed back to the
// cramped value. (Issue #419.)
- (void)testHtmlPaneIsWideEnoughForThemeControls
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    NSView *content = MPContentView(vc);

    NSLayoutConstraint *widthPin = nil;
    for (NSLayoutConstraint *c in content.constraints)
    {
        if (c.firstItem == content && c.secondItem == nil
            && c.relation == NSLayoutRelationEqual
            && c.firstAttribute == NSLayoutAttributeWidth)
            widthPin = c;
    }
    XCTAssertNotNil(widthPin, @"Html pane: loadView should pin the content width");
    XCTAssertGreaterThanOrEqual(widthPin.constant, 482,
        @"Html pane must stay wide enough for the CSS theme popup and its "
        @"Reveal/Reload controls; long theme names like \"GitHub Dark Default\" "
        @"clip at the old 430pt width");
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
        XCTAssertTrue(widthPin.active,
            @"%@ pane: width pin must be active during height measurement", name);
        CGFloat appliedHeight = heightPin.constant;
        heightPin.active = NO;
        [content layoutSubtreeIfNeeded];
        CGFloat neededHeight = content.fittingSize.height;
        heightPin.active = YES;

        XCTAssertGreaterThanOrEqual(appliedHeight + 0.5, neededHeight,
            @"%@ pane: content height (%g) must accommodate its content (%g)",
            name, appliedHeight, neededHeight);
    }];
}

// When a checkbox title wraps to multiple lines, the checkbox frame must be
// tall enough for the full wrapped text. NSButton.intrinsicContentSize always
// returns single-line height even with lineBreakMode=wordWrap, so
// addHeightConstraintsForWrappingCheckboxesInView: must add explicit height
// constraints. (Issue #397 — French/Italian Editor "Behavior" checkboxes.)
//
// This test forces wrapping by setting long titles, then calls the class method
// and verifies the resulting frame heights. Produces a reliable red/green cycle
// in English CI because it doesn't depend on locale-driven wrapping.
- (void)testWrappingCheckboxHeightsAccommodateMultiLineText
{
    __block NSUInteger testedCheckboxes = 0;

    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        NSView *content = MPContentView(vc);
        NSArray<NSButton *> *checkboxes = MPCheckboxes(content);
        if (checkboxes.count == 0)
            return;  // Terminal has no checkboxes

        // Set long titles that force wrapping at the pane width.
        for (NSButton *checkbox in checkboxes)
        {
            checkbox.title = [NSString stringWithFormat:@"%@ — %@ — %@",
                              checkbox.title, checkbox.title, checkbox.title];
        }

        // Remove the pane's height pin so the checkbox height constraints
        // (added below) can expand the pane freely. Without this, the pin
        // conflicts with the new constraints and Auto Layout breaks them.
        for (NSLayoutConstraint *c in content.constraints)
        {
            if (c.firstItem == content && c.secondItem == nil
                && c.relation == NSLayoutRelationEqual
                && c.firstAttribute == NSLayoutAttributeHeight)
                c.active = NO;
        }

        // Apply the checkbox height constraint mechanism.
        [MPPreferencesViewController
            addHeightConstraintsForWrappingCheckboxesInView:content];
        [content layoutSubtreeIfNeeded];

        // Verify each wrapping checkbox's frame accommodates its wrapped text.
        for (NSButton *checkbox in checkboxes)
        {
            NSCell *cell = checkbox.cell;
            if (cell.lineBreakMode != NSLineBreakByWordWrapping)
                continue;

            CGFloat frameWidth = NSWidth(checkbox.frame);
            if (frameWidth <= 0)
                continue;

            // cellSizeForBounds: with CGFLOAT_MAX returns NaN on some AppKit
            // versions; use a large finite value instead.
            NSSize cellSize = [cell cellSizeForBounds:
                               NSMakeRect(0, 0, frameWidth, 10000)];
            CGFloat frameHeight = NSHeight(checkbox.frame);

            if (cellSize.height > checkbox.intrinsicContentSize.height + 0.5)
            {
                testedCheckboxes++;
                XCTAssertGreaterThanOrEqual(frameHeight + 0.5, cellSize.height,
                    @"%@ pane: checkbox frame height (%g) must accommodate "
                    @"wrapped text height (%g)",
                    name, frameHeight, cellSize.height);
            }
        }
    }];

    XCTAssertGreaterThan(testedCheckboxes, 0U,
        @"Expected at least one checkbox to require wrapping with long titles");
}

// Every resolved pane width should be within a sane range — wide enough to show
// content but not ballooning to absurd sizes (which would indicate a runaway
// fittingSize calculation).
- (void)testResolvedWidthIsWithinSaneBounds
{
    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        NSView *content = MPContentView(vc);

        NSLayoutConstraint *widthPin = nil;
        for (NSLayoutConstraint *c in content.constraints)
        {
            if (c.firstItem == content && c.secondItem == nil
                && c.relation == NSLayoutRelationEqual
                && c.firstAttribute == NSLayoutAttributeWidth)
                widthPin = c;
        }
        XCTAssertNotNil(widthPin,
            @"%@ pane: loadView should pin the content width", name);
        XCTAssertGreaterThan(widthPin.constant, 200,
            @"%@ pane: resolved width (%g) is suspiciously narrow",
            name, widthPin.constant);
        XCTAssertLessThan(widthPin.constant, 2000,
            @"%@ pane: resolved width (%g) is suspiciously wide",
            name, widthPin.constant);
    }];
}

#pragma mark - Include pre-releases checkbox (Sparkle 2 migration, Issue #129)

// Sparkle 1 had no channel concept, so the checkbox used to be permanently
// force-disabled in -viewDidLoad (with an "(unavailable)" title suffix) until
// Sparkle 2 landed. That override is gone now that channel-based pre-release
// opt-in is implemented; this guards against it silently coming back and
// re-disabling the control.
- (void)testGeneralPanelIncludePreReleasesCheckboxIsNotForceDisabled
{
    MPGeneralPreferencesViewController *vc =
        [[MPGeneralPreferencesViewController alloc] init];
    MPContentView(vc);  // triggers loadView

    // KVC, not dot syntax: includePreReleasesCheckbox is a private IBOutlet
    // declared in a class extension, not the public header (same pattern as
    // the updaterController/updater access in MPUpdaterTests.m).
    NSButton *checkbox = [vc valueForKey:@"includePreReleasesCheckbox"];
    XCTAssertNotNil(checkbox,
        @"General pane: expected an 'Include pre-releases' checkbox");
    XCTAssertTrue(checkbox.enabled,
        @"Include pre-releases checkbox must not be force-disabled; its "
        @"enabled state should be driven by normal AppKit defaults");
    XCTAssertFalse([checkbox.title containsString:@"unavailable"],
        @"Include pre-releases checkbox must not carry the retired "
        @"'(unavailable)' title suffix");
}

#pragma mark - Toolbar tab highlight (Issue #499)

// -viewDidAppear forces the toolbar to revalidate and the window to redraw
// once a pane's view actually lands in the window, so the toolbar's
// selection highlight doesn't lag the pane switch (Issue #499). This exercises
// the override directly; it must not crash even before the view has a window
// (the state exercised by every other test in this file, which never attaches
// panes to a real window).
- (void)testViewDidAppearDoesNotCrashWithoutAWindow
{
    [self.allControllers enumerateKeysAndObjectsUsingBlock:
     ^(NSString *name, MPPreferencesViewController *vc, BOOL *stop) {
        MPContentView(vc);  // triggers loadView
        XCTAssertNoThrow([vc viewDidAppear],
            @"%@ pane: viewDidAppear must not throw even without a window", name);
    }];
}

- (void)testDiagramPreferencesRemainEditableWithoutSyntaxHighlighting
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL highlighting = preferences.htmlSyntaxHighlighting;
    BOOL graphviz = preferences.htmlGraphviz;
    BOOL mermaid = preferences.htmlMermaid;
    @try
    {
        preferences.htmlSyntaxHighlighting = NO;
        preferences.htmlGraphviz = NO;
        preferences.htmlMermaid = NO;
        MPHtmlPreferencesViewController *controller =
            [[MPHtmlPreferencesViewController alloc] init];
        NSUInteger diagramCheckboxes = 0;
        for (NSButton *button in MPCheckboxes(MPContentView(controller)))
        {
            NSString *keyPath = [button infoForBinding:NSValueBinding][NSObservedKeyPathKey];
            if (![keyPath isEqualToString:@"self.preferences.htmlGraphviz"]
                && ![keyPath isEqualToString:@"self.preferences.htmlMermaid"])
                continue;
            diagramCheckboxes++;
            XCTAssertTrue(button.enabled);
            [button performClick:nil];
        }
        XCTAssertEqual(diagramCheckboxes, 2U);
        XCTAssertTrue(preferences.htmlGraphviz);
        XCTAssertTrue(preferences.htmlMermaid);
    }
    @finally
    {
        preferences.htmlSyntaxHighlighting = highlighting;
        preferences.htmlGraphviz = graphviz;
        preferences.htmlMermaid = mermaid;
    }
}

#pragma mark - Localized checkbox fit (Issue #530)

// Every checkbox label in the Editor pane must be shown in full in every
// bundled localization. For each locale the localized titles are applied as
// the NIB loads (before loadView's sizing passes), the pane is laid out in a
// window, and each checkbox's title must fit its cell's title rect and the
// button must lie within the pane.
- (void)testEditorPaneCheckboxTitlesFitInEveryLocalization
{
    // Checkbox cell id -> English title, from the source Base XIB (object IDs
    // are not exposed at runtime).
    NSString *repoRoot = [[@__FILE__ stringByDeletingLastPathComponent]
                          stringByDeletingLastPathComponent];
    NSString *xibPath = [repoRoot stringByAppendingPathComponent:
        @"MacDown/Localization/Base.lproj/MPEditorPreferencesViewController.xib"];
    NSError *error = nil;
    NSXMLDocument *xib = [[NSXMLDocument alloc]
        initWithContentsOfURL:[NSURL fileURLWithPath:xibPath] options:0 error:&error];
    XCTAssertNotNil(xib, @"cannot parse %@: %@", xibPath, error);
    NSArray<NSXMLNode *> *cells = [xib nodesForXPath:@"//buttonCell[@type='check']" error:&error];
    XCTAssertGreaterThanOrEqual(cells.count, 8U, @"expected checkbox cells in the XIB");
    NSMutableDictionary<NSString *, NSString *> *englishByID = [NSMutableDictionary dictionary];
    for (NSXMLElement *cell in cells)
    {
        NSString *cellID = [[cell attributeForName:@"id"] stringValue];
        NSString *title = [[cell attributeForName:@"title"] stringValue];
        if (cellID && title)
            englishByID[cellID] = title;
    }

    NSString *resources = [NSBundle mainBundle].resourcePath;
    NSArray<NSString *> *entries =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:resources error:nil];
    NSUInteger localesTested = 0;
    for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)])
    {
        if (![entry hasSuffix:@".lproj"])
            continue;
        NSString *locale = [entry stringByDeletingPathExtension];
        NSString *tablePath = [[resources stringByAppendingPathComponent:entry]
            stringByAppendingPathComponent:@"MPEditorPreferencesViewController.strings"];
        NSDictionary *table = [NSDictionary dictionaryWithContentsOfFile:tablePath];
        if (!table)
            continue;
        localesTested++;

        NSMutableDictionary<NSString *, NSString *> *titleMap = [NSMutableDictionary dictionary];
        [englishByID enumerateKeysAndObjectsUsingBlock:^(NSString *cellID, NSString *english, BOOL *stop) {
            NSString *localized = table[[cellID stringByAppendingString:@".title"]];
            if (localized.length)
                titleMap[english] = localized;
        }];

        MPLocalizedEditorPreferencesViewController *vc =
            [[MPLocalizedEditorPreferencesViewController alloc] init];
        vc.titleMap = titleMap;
        NSView *wrapper = vc.view;   // loadView: titles applied, then sizing
        XCTAssertTrue(vc.titlesApplied, @"%@: localized titles were not applied", locale);

        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, NSWidth(wrapper.frame), NSHeight(wrapper.frame))
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:YES];
        window.contentView = wrapper;
        [wrapper layoutSubtreeIfNeeded];

        // Resolve the English title for each laid-out checkbox for messages.
        NSMutableDictionary<NSString *, NSString *> *englishByLocalized = [NSMutableDictionary dictionary];
        [titleMap enumerateKeysAndObjectsUsingBlock:^(NSString *en, NSString *loc, BOOL *stop) {
            englishByLocalized[loc] = en;
        }];

        NSArray<NSButton *> *checkboxes = MPCheckboxes(wrapper);
        XCTAssertGreaterThanOrEqual(checkboxes.count, 8U,
            @"%@: expected the Editor pane's checkboxes", locale);
        for (NSButton *button in checkboxes)
        {
            NSButtonCell *cell = button.cell;
            NSString *english = englishByLocalized[button.title] ?: button.title;
            NSRect bounds = button.bounds;
            NSRect titleRect = [cell titleRectForBounds:bounds];
            NSRect needed = [button.attributedTitle
                boundingRectWithSize:NSMakeSize(titleRect.size.width, CGFLOAT_MAX)
                             options:NSStringDrawingUsesLineFragmentOrigin
                                     | NSStringDrawingUsesFontLeading];
            NSSize cellSize = [cell cellSizeForBounds:
                               NSMakeRect(0, 0, bounds.size.width, 10000)];
            NSRect inPane = [button convertRect:bounds toView:wrapper];
            NSString *detail = [NSString stringWithFormat:
                @"[%@] \"%@\" -> \"%@\": frame=%@ titleRect=%@ needed=%@ cellSize=%@ pane=%@",
                locale, english, button.title, NSStringFromRect(button.frame),
                NSStringFromRect(titleRect), NSStringFromSize(needed.size),
                NSStringFromSize(cellSize), NSStringFromRect(wrapper.bounds)];

            XCTAssertLessThanOrEqual(ceil(needed.size.height), ceil(titleRect.size.height) + 1,
                @"title does not fit title rect: %@", detail);
            XCTAssertLessThanOrEqual(cellSize.height, bounds.size.height + 1,
                @"cell needs more height than the button has: %@", detail);
            XCTAssertTrue(NSContainsRect(NSInsetRect(wrapper.bounds, -1, -1), inPane),
                @"button lies outside the pane: %@", detail);

            if ([english isEqualToString:@"Automatically insert line prefix for the current block"]
                && ([locale isEqualToString:@"fr"] || [locale isEqualToString:@"it-IT"]))
            {
                NSLog(@"#530 diag %@ contentViewWidth=%g windowWidth=%g",
                      detail, NSWidth(window.contentView.frame), NSWidth(window.frame));
            }
        }
        window.contentView = [[NSView alloc] init];   // detach before vc deallocates
    }

    // 23 bundled locales ship MPEditorPreferencesViewController.strings.
    XCTAssertGreaterThanOrEqual(localesTested, 23U,
        @"expected every bundled localization of the Editor pane to be tested");
}

@end
