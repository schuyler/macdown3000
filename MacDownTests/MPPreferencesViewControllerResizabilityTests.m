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

#pragma mark - Localized-string helpers (Issue #530)

/// The repository's MacDown/Localization directory, derived from this file's own
/// compile-time path. The panes' English titles live only in the Base XIB (there
/// is no en.lproj strings file for them), and the English/ObjectID pairing needed
/// to map them survives only in the source .strings comments — Xcode's
/// CopyStringsFile phase discards comments, and the shipped keys are button
/// *cell* IDs that no runtime API can recover from a view. So the mapping has to
/// come from the source tree.
static NSString *MPLocalizationSourceDirectory(void)
{
    NSString *testsDir = [@(__FILE__) stringByDeletingLastPathComponent];
    NSString *repoRoot = [testsDir stringByDeletingLastPathComponent];
    return [[repoRoot stringByAppendingPathComponent:@"MacDown"]
            stringByAppendingPathComponent:@"Localization"];
}

/// Parses one localized .strings file into an English title -> localized title
/// map. Values come from -dictionaryWithContentsOfFile: (which handles the
/// legacy-plist format, escapes and encoding); the English side and the class
/// come from the `/* Class = "…"; title = "…"; ObjectID = "…"; */` comment that
/// genstrings writes above each entry. Returns nil for a file that is empty or
/// unreadable. Only title-bearing classes that drive layout width are included;
/// NSMenuItem and NSSegmentedCell labels are deliberately skipped.
static NSDictionary<NSString *, NSString *> *MPLocalizedTitleMap(NSString *path)
{
    NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path];
    if (values.count == 0)
        return nil;

    NSString *source = [NSString stringWithContentsOfFile:path
                                             usedEncoding:NULL error:NULL];
    if (!source)
        source = [NSString stringWithContentsOfFile:path
                                           encoding:NSUTF8StringEncoding error:NULL];
    if (!source)
        return nil;

    static NSRegularExpression *comment = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        comment = [NSRegularExpression regularExpressionWithPattern:
                   @"Class = \"([^\"]+)\"; title = \"(.*)\"; ObjectID = \"([^\"]+)\";"
                                                            options:0 error:NULL];
    });

    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    [comment enumerateMatchesInString:source options:0
                                range:NSMakeRange(0, source.length)
                           usingBlock:^(NSTextCheckingResult *match,
                                        NSMatchingFlags flags, BOOL *stop) {
        NSString *className = [source substringWithRange:[match rangeAtIndex:1]];
        NSString *english   = [source substringWithRange:[match rangeAtIndex:2]];
        NSString *objectID  = [source substringWithRange:[match rangeAtIndex:3]];

        if (![className isEqualToString:@"NSButtonCell"]
            && ![className isEqualToString:@"NSTextFieldCell"]
            && ![className isEqualToString:@"NSBox"])
            return;

        NSString *localized = values[[objectID stringByAppendingString:@".title"]];
        if (english.length && localized.length)
            map[english] = localized;
    }];
    return map;
}

/// Retitles every control in @c view whose current (English) title appears in
/// @c titles, and returns how many were changed. Matching on the live title is
/// what makes this safe without object IDs: a bound numeric field's stringValue
/// never collides with a label or checkbox title.
static NSUInteger MPApplyLocalizedTitles(NSView *view,
                                         NSDictionary<NSString *, NSString *> *titles)
{
    NSUInteger applied = 0;
    if ([view isKindOfClass:[NSButton class]])
    {
        NSButton *button = (NSButton *)view;
        NSString *localized = titles[button.title];
        if (localized) { button.title = localized; applied++; }
    }
    else if ([view isKindOfClass:[NSBox class]])
    {
        NSBox *box = (NSBox *)view;
        NSString *localized = box.title ? titles[box.title] : nil;
        if (localized) { box.title = localized; applied++; }
    }
    else if ([view isKindOfClass:[NSTextField class]])
    {
        NSTextField *field = (NSTextField *)view;
        NSString *localized = titles[field.stringValue];
        if (localized) { field.stringValue = localized; applied++; }
    }
    for (NSView *sub in view.subviews)
        applied += MPApplyLocalizedTitles(sub, titles);
    return applied;
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
// as the bundled "GitHub Dark Default". Since #481 loadView treats the XIB
// design width as a floor and widens from there, so the design width itself
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

#pragma mark - Localized layout (Issue #530)

// Loads every pane with each bundled localization's titles applied and reports
// any checkbox that is truncated, clipped, or overlapping a sibling.
//
// This is the coverage gap behind #397, #498 and #530: every failure in this
// area was found by reporters running French and Italian builds, because no
// test had ever exercised pane geometry under a non-English locale.
//
// Titles are substituted through -contentDidLoadHook, i.e. before -loadView
// resolves and pins the pane's size, so the geometry measured here is what the
// real sizing pipeline produces for that locale. (Substituting titles after
// -loadView and re-resolving does not work: the pane's size is already pinned,
// and forcing a re-resolve produced degenerate frames — checkboxes 0 and 7
// points tall — that made every measurement meaningless.)
//
// It also logs the resolved geometry for the Editor pane, so a CI run doubles
// as a measurement instrument while the cause of #530 is still being pinned
// down. Diagnosis first, fix second.
- (void)testLocalizedTitlesLayOutWithoutTruncationOrOverlap
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *localizationDir = MPLocalizationSourceDirectory();

    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:localizationDir isDirectory:&isDirectory];
    XCTAssertTrue(exists && isDirectory,
        @"Localization sources not found at %@. This test reads them from the "
        @"source tree (see MPLocalizationSourceDirectory); if the layout moved, "
        @"update that helper rather than letting this test silently pass.",
        localizationDir);
    if (!exists || !isDirectory)
        return;

    NSArray<NSString *> *entries =
        [[fm contentsOfDirectoryAtPath:localizationDir error:NULL]
         sortedArrayUsingSelector:@selector(compare:)];

    NSMutableSet<NSString *> *localesExercised = [NSMutableSet set];
    NSUInteger controlsRetitled = 0;

    // Collected rather than asserted inline: 5 panes x 23 locales x 7 checkboxes
    // would bury the CI log in near-identical failures. Report a bounded,
    // readable sample with a total instead.
    NSMutableArray<NSString *> *problems = [NSMutableArray array];

    for (MPPreferencesViewController *prototype in self.allControllers.allValues)
    {
        Class paneClass = [prototype class];
        NSString *table = NSStringFromClass(paneClass);
        BOOL isEditor = [table isEqualToString:@"MPEditorPreferencesViewController"];

        for (NSString *entry in entries)
        {
            if (![entry hasSuffix:@".lproj"] || [entry isEqualToString:@"Base.lproj"])
                continue;

            NSString *path = [[localizationDir stringByAppendingPathComponent:entry]
                              stringByAppendingPathComponent:
                              [table stringByAppendingPathExtension:@"strings"]];
            if (![fm fileExistsAtPath:path])
                continue;   // coverage is uneven; not every pane has every locale

            NSDictionary<NSString *, NSString *> *titles = MPLocalizedTitleMap(path);
            if (titles.count == 0)
                continue;   // e.g. sv.lproj's Terminal strings file is empty

            // Substitute the localized titles before the pane measures itself.
            __block NSUInteger applied = 0;
            MPPreferencesViewController *vc = [[paneClass alloc] init];
            vc.contentDidLoadHook = ^(NSView *nibContent) {
                applied = MPApplyLocalizedTitles(nibContent, titles);
            };

            NSView *wrapper = vc.view;          // triggers loadView
            [wrapper layoutSubtreeIfNeeded];
            NSView *content = wrapper.subviews.firstObject;

            if (applied == 0)
                continue;
            controlsRetitled += applied;
            [localesExercised addObject:entry];

            NSString *where = [NSString stringWithFormat:@"%@, %@", table, entry];
            CGFloat paneWidth = NSWidth(content.frame);

            if (paneWidth >= 2000)
            {
                [problems addObject:[NSString stringWithFormat:
                    @"%@: resolved width %g is suspiciously wide", where, paneWidth]];
            }

            NSArray<NSButton *> *checkboxes = MPCheckboxes(content);
            for (NSButton *checkbox in checkboxes)
            {
                NSCell *cell = checkbox.cell;
                NSRect box = checkbox.frame;

                // cellSizeForBounds: with CGFLOAT_MAX returns NaN on some AppKit
                // versions; use a large finite value instead.
                NSSize oneLine = [cell cellSizeForBounds:
                                  NSMakeRect(0, 0, 10000, 10000)];
                NSSize wrapped = [cell cellSizeForBounds:
                                  NSMakeRect(0, 0, NSWidth(box), 10000)];

                if (isEditor)
                {
                    // intrinsic vs one-line is the diagnostic that matters for
                    // why the pane never widens: Auto Layout only pushes a
                    // container wider through the child's *intrinsic* width at
                    // its compression-resistance priority. If intrinsic tracks
                    // the frame rather than the width the title needs, there is
                    // no unmet demand for fittingSize to pick up.
                    NSLog(@"[#530] %@ w=%.1f | checkbox %.1fx%.1f at (%.1f,%.1f) "
                          @"intrinsic %.1f needs 1-line %.1f wrapped %.1fx%.1f "
                          @"compH=%.0f hugH=%.0f | %@",
                          where, paneWidth, NSWidth(box), NSHeight(box),
                          NSMinX(box), NSMinY(box),
                          checkbox.intrinsicContentSize.width, oneLine.width,
                          wrapped.width, wrapped.height,
                          [checkbox contentCompressionResistancePriorityForOrientation:
                              NSLayoutConstraintOrientationHorizontal],
                          [checkbox contentHuggingPriorityForOrientation:
                              NSLayoutConstraintOrientationHorizontal],
                          checkbox.title);
                }

                // A non-positive frame means the layout collapsed rather than
                // merely running out of room; report it as its own failure mode
                // so it is never mistaken for a truncation measurement.
                if (NSWidth(box) <= 0 || NSHeight(box) <= 0)
                {
                    [problems addObject:[NSString stringWithFormat:
                        @"%@: degenerate checkbox frame %@ — layout collapsed: '%@'",
                        where, NSStringFromRect(box), checkbox.title]];
                    continue;
                }

                if (NSWidth(box) + 0.5 < oneLine.width
                    && NSHeight(box) + 0.5 < wrapped.height)
                {
                    // Too narrow for one line AND too short for the wrapped
                    // text: the label cannot render in full either way.
                    [problems addObject:[NSString stringWithFormat:
                        @"%@: checkbox %.0fx%.0f fits neither one line (needs "
                        @"%.0f wide) nor wrapped text (needs %.0f tall): '%@'",
                        where, NSWidth(box), NSHeight(box), oneLine.width,
                        wrapped.height, checkbox.title]];
                }
            }

            // Siblings must not collide. This is the most direct assertion for
            // the reported symptom: a checkbox stretched over its neighbours.
            for (NSUInteger i = 0; i < checkboxes.count; i++)
            {
                for (NSUInteger j = i + 1; j < checkboxes.count; j++)
                {
                    NSButton *a = checkboxes[i], *b = checkboxes[j];
                    if (a.superview != b.superview)
                        continue;
                    if (NSIntersectsRect(a.frame, b.frame))
                    {
                        [problems addObject:[NSString stringWithFormat:
                            @"%@: checkboxes overlap (%@ vs %@): '%@' / '%@'",
                            where, NSStringFromRect(a.frame),
                            NSStringFromRect(b.frame), a.title, b.title]];
                    }
                }
            }

            // Probe: what width does the content actually ask for, versus what
            // loadView pinned it to? loadView takes MAX(fittingSize.width,
            // designWidth), so a pane stuck at its English design width in every
            // locale means fittingSize is not seeing the localized demand at
            // all. Done last, and restored immediately, so it cannot perturb the
            // measurements above.
            NSLayoutConstraint *widthPin = nil;
            for (NSLayoutConstraint *c in content.constraints)
            {
                if (c.firstItem == content && c.secondItem == nil
                    && c.relation == NSLayoutRelationEqual
                    && c.firstAttribute == NSLayoutAttributeWidth)
                    widthPin = c;
            }
            if (widthPin)
            {
                widthPin.active = NO;
                [wrapper layoutSubtreeIfNeeded];
                CGFloat unpinnedFitting = content.fittingSize.width;
                widthPin.active = YES;
                [wrapper layoutSubtreeIfNeeded];

                NSLog(@"[#530fit] %@ pinned=%.1f unpinnedFitting=%.1f",
                      where, widthPin.constant, unpinnedFitting);

                // Walk the chain a checkbox's width demand has to travel to
                // reach the pane: checkbox -> box content view -> box -> root.
                // Printing each link's fitting/intrinsic width shows exactly
                // which one stops reporting the demand. Compared across the
                // Editor (which never widens) and General (which does), this
                // isolates the difference.
                NSMutableArray<NSBox *> *boxes = [NSMutableArray array];
                MPCollectViews(content, [NSBox class], boxes);
                for (NSBox *b in boxes)
                {
                    NSView *cv = b.contentView;
                    NSSize cvFit = cv ? cv.fittingSize : NSZeroSize;
                    NSLog(@"[#530box] %@ box '%@' frame=%.1f fitting=%.1f "
                          @"intrinsic=%.1f | contentView fitting=%.1f tamic=%d "
                          @"ownConstraints=%lu cvConstraints=%lu",
                          where, b.title, NSWidth(b.frame),
                          b.fittingSize.width, b.intrinsicContentSize.width,
                          cvFit.width,
                          cv ? (int)cv.translatesAutoresizingMaskIntoConstraints : -1,
                          (unsigned long)b.constraints.count,
                          (unsigned long)(cv ? cv.constraints.count : 0));
                }
            }
        }
    }

    // Guard against the test quietly becoming a no-op if the .strings parsing
    // or the source path ever breaks.
    XCTAssertGreaterThanOrEqual(localesExercised.count, 20U,
        @"expected at least 20 localizations to be exercised, got %lu (%@)",
        (unsigned long)localesExercised.count,
        [[localesExercised allObjects] componentsJoinedByString:@", "]);
    XCTAssertGreaterThan(controlsRetitled, 0U,
        @"no controls were retitled — the .strings comment parsing is broken");

    if (problems.count)
    {
        NSUInteger shown = MIN((NSUInteger)12, problems.count);
        NSArray<NSString *> *sample =
            [problems subarrayWithRange:NSMakeRange(0, shown)];
        XCTFail(@"%lu localized layout problem(s) across %lu localization(s); "
                @"first %lu:\n  %@",
                (unsigned long)problems.count,
                (unsigned long)localesExercised.count,
                (unsigned long)shown,
                [sample componentsJoinedByString:@"\n  "]);
    }
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

@end
