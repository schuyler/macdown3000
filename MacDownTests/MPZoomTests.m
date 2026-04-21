//
//  MPZoomTests.m
//  MacDownTests
//
//  TDD tests for the zoom feature in MPDocument.
//  Some tests are RED regression guards and are expected to FAIL against the
//  current code until the corresponding bug is fixed:
//
//  Bug 2: setupEditor: resets the editor font to the base (unzoomed) size,
//         clobbering any zoom that was applied via applyCurrentZoom.
//
//  Bug 3: setupEditor: computes tab stops from the base font (not the zoomed
//         font), so tab stops do not scale with zoom.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPEditorView.h"
#import "MPPreferences.h"

#pragma mark - Testing Category

@interface MPDocument (ZoomTesting)
@property CGFloat zoomMultiplier;
@property (unsafe_unretained) IBOutlet MPEditorView *editor;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)resetZoom:(id)sender;
- (void)applyCurrentZoom;
- (void)setupEditor:(NSString *)changedKey;
@end

#pragma mark - Mock Menu Item

// Separate class from MPPaneToggleTests.m's MockMenuItem to avoid duplicate symbol.
@interface MockZoomMenuItem : NSMenuItem
@end

@implementation MockZoomMenuItem
@end

#pragma mark - Test Case

@interface MPZoomTests : XCTestCase
@property (strong) MPDocument *document;
@end

@implementation MPZoomTests

- (void)setUp
{
    [super setUp];
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    self.document = nil;
    [super tearDown];
}


#pragma mark - Zoom Multiplier Basics

/**
 * A new document should start with zoomMultiplier of 1.0.
 */
- (void)testZoomMultiplierDefaultsToOne
{
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.0, 0.001,
                               @"New document should default to zoom multiplier of 1.0");
}

/**
 * After calling zoomIn:nil the multiplier should increase by 0.1 (to 1.1).
 */
- (void)testZoomInIncrementsMultiplier
{
    [self.document zoomIn:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.1, 0.001,
                               @"zoomIn: should increment multiplier by 0.1");
}

/**
 * After calling zoomOut:nil the multiplier should decrease by 0.1 (to 0.9).
 */
- (void)testZoomOutDecrementsMultiplier
{
    [self.document zoomOut:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 0.9, 0.001,
                               @"zoomOut: should decrement multiplier by 0.1");
}

/**
 * Setting multiplier to 2.0 then calling resetZoom:nil should restore 1.0.
 */
- (void)testResetZoomSetsMultiplierToOne
{
    self.document.zoomMultiplier = 2.0;
    [self.document resetZoom:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.0, 0.001,
                               @"resetZoom: should restore multiplier to 1.0");
}

/**
 * When already at kMPMaxZoom (3.0), zoomIn: should be a no-op.
 */
- (void)testZoomInAtMaxZoomIsNoOp
{
    self.document.zoomMultiplier = 3.0;
    [self.document zoomIn:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 3.0, 0.001,
                               @"zoomIn: at maximum zoom should not increase multiplier");
}

/**
 * When already at kMPMinZoom (0.5), zoomOut: should be a no-op.
 */
- (void)testZoomOutAtMinZoomIsNoOp
{
    self.document.zoomMultiplier = 0.5;
    [self.document zoomOut:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 0.5, 0.001,
                               @"zoomOut: at minimum zoom should not decrease multiplier");
}

/**
 * 25 zoomIn, then 50 zoomOut, then 25 zoomIn must keep multiplier within [0.5, 3.0].
 */
- (void)testRapidZoomInOut
{
    for (int i = 0; i < 25; i++)
        [self.document zoomIn:nil];
    for (int i = 0; i < 50; i++)
        [self.document zoomOut:nil];
    for (int i = 0; i < 25; i++)
        [self.document zoomIn:nil];

    CGFloat m = self.document.zoomMultiplier;
    XCTAssertGreaterThanOrEqual(m, 0.5 - 0.001,
                                @"Rapid zoom sequence must not go below minimum (0.5)");
    XCTAssertLessThanOrEqual(m, 3.0 + 0.001,
                             @"Rapid zoom sequence must not exceed maximum (3.0)");
}


#pragma mark - Menu Validation

/**
 * validateUserInterfaceItem: should return YES for zoomIn: at default zoom (1.0).
 */
- (void)testZoomInMenuValidationEnabledAtDefault
{
    MockZoomMenuItem *item = [[MockZoomMenuItem alloc] initWithTitle:@"Zoom In"
                                                      action:@selector(zoomIn:)
                                               keyEquivalent:@""];
    BOOL result = [self.document validateUserInterfaceItem:item];
    XCTAssertTrue(result, @"Zoom In should be enabled at default zoom (1.0)");
}

/**
 * validateUserInterfaceItem: should return YES for zoomOut: at default zoom (1.0).
 */
- (void)testZoomOutMenuValidationEnabledAtDefault
{
    MockZoomMenuItem *item = [[MockZoomMenuItem alloc] initWithTitle:@"Zoom Out"
                                                      action:@selector(zoomOut:)
                                               keyEquivalent:@""];
    BOOL result = [self.document validateUserInterfaceItem:item];
    XCTAssertTrue(result, @"Zoom Out should be enabled at default zoom (1.0)");
}

/**
 * validateUserInterfaceItem: should return NO for resetZoom: at default zoom (1.0),
 * because there is nothing to reset.
 */
- (void)testResetZoomMenuValidationDisabledAtDefault
{
    MockZoomMenuItem *item = [[MockZoomMenuItem alloc] initWithTitle:@"Reset Zoom"
                                                      action:@selector(resetZoom:)
                                               keyEquivalent:@""];
    BOOL result = [self.document validateUserInterfaceItem:item];
    XCTAssertFalse(result, @"Reset Zoom should be disabled when multiplier is already 1.0");
}

/**
 * validateUserInterfaceItem: should return YES for resetZoom: when multiplier != 1.0.
 */
- (void)testResetZoomMenuValidationEnabledWhenZoomed
{
    self.document.zoomMultiplier = 1.5;
    MockZoomMenuItem *item = [[MockZoomMenuItem alloc] initWithTitle:@"Reset Zoom"
                                                      action:@selector(resetZoom:)
                                               keyEquivalent:@""];
    BOOL result = [self.document validateUserInterfaceItem:item];
    XCTAssertTrue(result, @"Reset Zoom should be enabled when multiplier is not 1.0");
}

/**
 * validateUserInterfaceItem: should return NO for zoomIn: when at maximum zoom (3.0).
 */
- (void)testZoomInMenuValidationDisabledAtMaxZoom
{
    self.document.zoomMultiplier = 3.0;
    MockZoomMenuItem *item = [[MockZoomMenuItem alloc] initWithTitle:@"Zoom In"
                                                      action:@selector(zoomIn:)
                                               keyEquivalent:@""];
    BOOL result = [self.document validateUserInterfaceItem:item];
    XCTAssertFalse(result, @"Zoom In should be disabled at maximum zoom (3.0)");
}

/**
 * validateUserInterfaceItem: should return NO for zoomOut: when at minimum zoom (0.5).
 */
- (void)testZoomOutMenuValidationDisabledAtMinZoom
{
    self.document.zoomMultiplier = 0.5;
    MockZoomMenuItem *item = [[MockZoomMenuItem alloc] initWithTitle:@"Zoom Out"
                                                      action:@selector(zoomOut:)
                                               keyEquivalent:@""];
    BOOL result = [self.document validateUserInterfaceItem:item];
    XCTAssertFalse(result, @"Zoom Out should be disabled at minimum zoom (0.5)");
}


#pragma mark - Preference Observer — Bug 2 Regression Tests

/**
 * setupEditor: must not reset zoomMultiplier to 1.0.
 * Bug 2: If setupEditor: calls applyCurrentZoom internally with the base font it
 * resets, zoom is effectively lost even though zoomMultiplier itself is unchanged.
 * This test guards the multiplier value directly (no editor required).
 */
- (void)testSetupEditorDoesNotResetZoomMultiplier
{
    self.document.zoomMultiplier = 1.5;
    XCTAssertNoThrow([self.document setupEditor:@"editorBaseFontInfo"],
                     @"setupEditor:editorBaseFontInfo should not throw");
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.5, 0.001,
                               @"setupEditor: must not reset zoomMultiplier");
}

/**
 * Calling setupEditor: while zoomed should not crash.
 * Bug 2 regression: nil changedKey exercises the full setup path.
 */
- (void)testSetupEditorDoesNotCrashWhileZoomed
{
    self.document.zoomMultiplier = 2.0;
    XCTAssertNoThrow([self.document setupEditor:nil],
                     @"setupEditor:nil should not crash when zoomed to 2.0");
}

/**
 * Calling setupEditor: for a line-spacing change while zoomed should not crash.
 * Bug 2 regression guard for the editorLineSpacing code path.
 */
- (void)testSetupEditorDoesNotCrashForLineSpacingChangeWhileZoomed
{
    self.document.zoomMultiplier = 1.3;
    XCTAssertNoThrow([self.document setupEditor:@"editorLineSpacing"],
                     @"setupEditor:editorLineSpacing should not crash when zoomed");
}

/**
 * Calling setupEditor: for a style change while zoomed should not crash.
 * Bug 2 regression guard for the editorStyleName code path.
 */
- (void)testSetupEditorDoesNotCrashForStyleChangeWhileZoomed
{
    self.document.zoomMultiplier = 1.3;
    XCTAssertNoThrow([self.document setupEditor:@"editorStyleName"],
                     @"setupEditor:editorStyleName should not crash when zoomed");
}

/**
 * CONDITIONAL / RED TEST — expected to FAIL until Bug 2 is fixed.
 *
 * After zooming to 1.5 and calling applyCurrentZoom, the editor font's point
 * size should reflect the zoom. After a subsequent setupEditor:editorBaseFontInfo,
 * the editor font should NOT revert to the base (unzoomed) size.
 *
 * This test skips gracefully in headless environments where the editor outlet
 * is nil (e.g. CI without a display server).
 */
- (void)testSetupEditorPreservesZoomedFontSize
{
    [self.document makeWindowControllers];

    if (!self.document.editor) {
        NSLog(@"Skipping testSetupEditorPreservesZoomedFontSize - editor outlet is nil (headless)");
        return;
    }

    // Zoom to 1.5x and apply.
    self.document.zoomMultiplier = 1.5;
    [self.document applyCurrentZoom];

    CGFloat zoomedPointSize = self.document.editor.font.pointSize;

    // Simulate a preference change that triggers font re-application.
    [self.document setupEditor:@"editorBaseFontInfo"];

    CGFloat afterSetupPointSize = self.document.editor.font.pointSize;

    // BUG 2: setupEditor: resets the font to the base size, so afterSetupPointSize
    // will equal the unzoomed base size, not zoomedPointSize.
    // This assertion FAILS until Bug 2 is fixed.
    XCTAssertEqualWithAccuracy(afterSetupPointSize, zoomedPointSize, 0.1,
                               @"Bug 2: setupEditor: must not revert the editor font to "
                               @"the unzoomed base size after applyCurrentZoom has run");
}

/**
 * After zooming, a preference change (setupEditor:), and another zoomIn:,
 * the multiplier should reflect both the original zoom and the new step.
 * This exercises the multiplier state across a full zoom -> preference -> zoom cycle.
 */
- (void)testZoomThenPreferenceChangeThenZoomAgain
{
    self.document.zoomMultiplier = 1.5;
    XCTAssertNoThrow([self.document setupEditor:@"editorBaseFontInfo"],
                     @"setupEditor: should not throw while zoomed");

    [self.document zoomIn:nil];

    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.6, 0.001,
                               @"After zoom(1.5) -> setupEditor -> zoomIn, "
                               @"multiplier should be 1.6");
}


#pragma mark - Tab Stop Calculation — Bug 3 Regression Tests

/**
 * Pure math test: a font at 2x size must produce a wider space character and
 * therefore a wider tab interval than the same font at base size.
 * This test does not require a window controller and always runs.
 */
- (void)testZoomedFontProducesDifferentTabWidth
{
    NSFont *baseFont = [MPPreferences sharedInstance].editorBaseFont;
    XCTAssertNotNil(baseFont, @"editorBaseFont must not be nil");

    CGFloat baseSize = baseFont.pointSize;
    CGFloat zoomedSize = baseSize * 2.0;

    NSFont *zoomedFont = [NSFont fontWithName:baseFont.fontName size:zoomedSize];
    XCTAssertNotNil(zoomedFont, @"Could not create zoomed font");

    NSDictionary *baseAttrs  = @{NSFontAttributeName: baseFont};
    NSDictionary *zoomedAttrs = @{NSFontAttributeName: zoomedFont};

    CGFloat baseSpaceWidth   = [@" " sizeWithAttributes:baseAttrs].width;
    CGFloat zoomedSpaceWidth = [@" " sizeWithAttributes:zoomedAttrs].width;

    XCTAssertGreaterThan(zoomedSpaceWidth, baseSpaceWidth,
                         @"Space character must be wider in a larger font");

    CGFloat baseTabInterval   = baseSpaceWidth   * 4.0;
    CGFloat zoomedTabInterval = zoomedSpaceWidth * 4.0;

    XCTAssertGreaterThan(zoomedTabInterval, baseTabInterval,
                         @"Tab interval (4 spaces) must be wider at 2x zoom than at base size");
}

/**
 * CONDITIONAL / RED TEST — expected to FAIL until Bug 3 is fixed.
 *
 * After zooming to 2.0, applyCurrentZoom, and setupEditor:editorBaseFontInfo,
 * the first tab stop in the editor's paragraph style should match the tab
 * interval computed from the zoomed font (not the base font).
 *
 * Skips in headless environments where the editor outlet is nil.
 */
- (void)testTabStopsReflectZoomedFontSize
{
    [self.document makeWindowControllers];

    if (!self.document.editor) {
        NSLog(@"Skipping testTabStopsReflectZoomedFontSize - editor outlet is nil (headless)");
        return;
    }

    if (self.document.editor.defaultParagraphStyle.tabStops.count == 0) {
        NSLog(@"Skipping testTabStopsReflectZoomedFontSize - no tab stops (headless)");
        return;
    }

    // Zoom to 2.0 and apply.
    self.document.zoomMultiplier = 2.0;
    [self.document applyCurrentZoom];

    // Trigger the code path that recomputes tab stops.
    [self.document setupEditor:@"editorBaseFontInfo"];

    // Compute the expected tab interval from the zoomed font.
    NSFont *baseFont = [MPPreferences sharedInstance].editorBaseFont;
    CGFloat zoomedSize = baseFont.pointSize * 2.0;
    NSFont *zoomedFont = [NSFont fontWithName:baseFont.fontName size:zoomedSize];
    NSDictionary *attrs = @{NSFontAttributeName: zoomedFont};
    CGFloat spaceWidth = [@" " sizeWithAttributes:attrs].width;
    CGFloat expectedTabInterval = spaceWidth * 4.0;

    NSArray *tabStops = self.document.editor.defaultParagraphStyle.tabStops;
    XCTAssertGreaterThan(tabStops.count, 0U, @"There should be at least one tab stop");

    NSTextTab *firstTab = tabStops[0];

    // BUG 3: setupEditor: uses the base font (not the zoomed font) to compute
    // tab stops, so firstTab.location will equal the base-font tab interval.
    // This assertion FAILS until Bug 3 is fixed.
    XCTAssertEqualWithAccuracy(firstTab.location, expectedTabInterval, 0.5,
                               @"Bug 3: First tab stop must reflect zoomed font size, "
                               @"not the unzoomed base font size");
}

/**
 * CONDITIONAL test: at default zoom (1.0), tab stops should match the interval
 * computed from the base font.  This is a green test that verifies the baseline
 * behaviour is correct before any zoom is applied.
 *
 * Skips in headless environments where the editor outlet is nil.
 */
- (void)testTabStopsAtDefaultZoomMatchBaseFont
{
    [self.document makeWindowControllers];

    if (!self.document.editor) {
        NSLog(@"Skipping testTabStopsAtDefaultZoomMatchBaseFont - editor outlet is nil (headless)");
        return;
    }

    if (self.document.editor.defaultParagraphStyle.tabStops.count == 0) {
        NSLog(@"Skipping testTabStopsAtDefaultZoomMatchBaseFont - no tab stops (headless)");
        return;
    }

    // Ensure default zoom.
    self.document.zoomMultiplier = 1.0;
    [self.document setupEditor:@"editorBaseFontInfo"];

    NSFont *baseFont = [MPPreferences sharedInstance].editorBaseFont;
    NSDictionary *attrs = @{NSFontAttributeName: baseFont};
    CGFloat spaceWidth = [@" " sizeWithAttributes:attrs].width;
    CGFloat expectedTabInterval = spaceWidth * 4.0;

    NSArray *tabStops = self.document.editor.defaultParagraphStyle.tabStops;
    XCTAssertGreaterThan(tabStops.count, 0U, @"There should be at least one tab stop");

    NSTextTab *firstTab = tabStops[0];
    XCTAssertEqualWithAccuracy(firstTab.location, expectedTabInterval, 0.5,
                               @"At default zoom, first tab stop should match "
                               @"the base-font tab interval");
}

@end
