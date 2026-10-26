//
//  MPZoomTests.m
//  MacDownTests
//
//  Tests for the per-document zoom feature in MPDocument
//  (zoomIn:/zoomOut:/resetZoom: actions, zoomMultiplier property,
//  and the zoom-aware font and tab-stop code paths).
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
- (CGFloat)previewScale;
@end

#pragma mark - Cross-Window Zoom Testing Category

// Fix #4 (MPDocument.m ~line 800-816) extracted registration of the shared
// documentZoomLevel KVO observer out of the nib-loading path into these two
// methods so a headless test can drive it directly. They are declared only
// in MPDocument.m's private class extension (~line 393-394), not in
// MPDocument.h, so re-declare them here. -applyCurrentZoom and
// -zoomMultiplier are already exposed by the ZoomTesting category above;
// do not redeclare them here to avoid duplicate-declaration conflicts.
@interface MPDocument (MPCrossWindowZoomTesting)
- (void)registerSharedPreferenceObservers;
- (void)unregisterSharedPreferenceObservers;
@end

#pragma mark - Cross-Window Zoom Spy Document

// Spies on -applyCurrentZoom (MPDocument.m ~line 3171, the KVO handler side
// effect invoked by -observeValueForKeyPath:... when the shared
// documentZoomLevel default changes) so the test can prove the *handler
// actually ran* on doc B, rather than merely reading doc B's zoomMultiplier
// (which is a passthrough over the shared pref and would read the new value
// regardless of whether doc B's observer ever fired).
@interface MPZoomSpyDocument : MPDocument
@property (nonatomic) NSInteger applyCurrentZoomCount;
@property (nonatomic) CGFloat lastAppliedMultiplier;
@end

@implementation MPZoomSpyDocument

- (void)applyCurrentZoom
{
    self.applyCurrentZoomCount++;
    self.lastAppliedMultiplier = self.zoomMultiplier;
    [super applyCurrentZoom];
}

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
@property (assign) CGFloat originalZoomLevel;
@end

@implementation MPZoomTests

- (void)setUp
{
    [super setUp];
    self.originalZoomLevel = [MPPreferences sharedInstance].documentZoomLevel;
    [MPPreferences sharedInstance].documentZoomLevel = 1.0;
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    [MPPreferences sharedInstance].documentZoomLevel = self.originalZoomLevel;
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
 * zoomIn:/zoomOut: route through -stepDocumentZoomDirection: (MPDocument.m,
 * defined ~line 4409), which steps across the fixed, non-uniform preset
 * list returned by MPDocumentZoomLevels() (MPDocument.m ~line 133-141):
 *   0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0, 3.0
 * From an exact preset it moves one entry in the requested direction; from
 * an off-preset value it snaps to the nearest preset on the requested side
 * (see the corrected "SnapsFromOffGrid" tests below, and the equivalent
 * coverage of the private helper itself in MPPreviewZoomTests.m).
 * There is no flat +/-0.1 step for arbitrary starting values: e.g. zoomIn:
 * from 1.25 lands on 1.5, not 1.35, and zoomIn: from 0.75 lands on 0.9, not
 * 0.85. The two tests that used to live here (testZoomInIncrementsMultiplier /
 * testZoomOutDecrementsMultiplier) asserted 1.0 -> 1.1 and 1.0 -> 0.9, which
 * happen to be numerically correct at exactly 1.0 (a preset immediately
 * flanked by 0.9 and 1.1) but whose docstrings claimed a general flat-0.1
 * stepping rule that the shipped preset-snap model does not follow. They
 * were removed in favor of the off-grid snap tests below, which exercise
 * the actual preset-list/snap behavior rather than a coincidental data point.
 */

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

/**
 * zoomIn: from an off-preset multiplier must snap UP to the nearest preset
 * on the requested side, using the same model exercised against the
 * private helper directly in MPPreviewZoomTests.m
 * (-testSnapFromOffPresetUpRoundsUp). Per -stepDocumentZoomDirection:
 * (MPDocument.m ~line 4409-4454): when the current value does not match a
 * preset within epsilon, zooming in snaps to the smallest preset greater
 * than the current value. 1.05 sits equidistant between the 1.0 and 1.1
 * presets (MPDocumentZoomLevels(), MPDocument.m ~line 138); the nearest-index
 * scan (MPDocument.m ~line 4416-4426) keeps the first minimum found, i.e.
 * 1.0, and since 1.0 < 1.05 the "snap up" branch (~line 4434-4440)
 * advances one further to 1.1.
 */
- (void)testZoomInSnapsUpFromOffGridMultiplier
{
    self.document.zoomMultiplier = 1.05;
    [self.document zoomIn:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.1, 0.001,
                               @"zoomIn: from an off-grid 1.05 should snap up "
                               @"to the next preset above (1.1)");
}

/**
 * zoomOut: from an off-preset multiplier must snap DOWN to the nearest
 * preset on the requested side (MPDocument.m ~line 4441-4447), mirroring
 * -testSnapFromOffPresetDownRoundsDown in MPPreviewZoomTests.m. From 1.05,
 * the nearest-index scan again lands on the 1.0 preset; since 1.0 is not
 * greater than 1.05 the "snap down" branch does not decrement further, so
 * the result is 1.0.
 */
- (void)testZoomOutSnapsDownFromOffGridMultiplier
{
    self.document.zoomMultiplier = 1.05;
    [self.document zoomOut:nil];
    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 1.0, 0.001,
                               @"zoomOut: from an off-grid 1.05 should snap down "
                               @"to the next preset below (1.0)");
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


#pragma mark - Preference Observer Tests

/**
 * Calling setupEditor: while zoomed should not crash.
 * nil changedKey exercises the full setup path.
 */
- (void)testSetupEditorDoesNotCrashWhileZoomed
{
    self.document.zoomMultiplier = 2.0;
    XCTAssertNoThrow([self.document setupEditor:nil],
                     @"setupEditor:nil should not crash when zoomed to 2.0");
}

/**
 * Calling setupEditor: for a line-spacing change while zoomed should not crash.
 */
- (void)testSetupEditorDoesNotCrashForLineSpacingChangeWhileZoomed
{
    self.document.zoomMultiplier = 1.3;
    XCTAssertNoThrow([self.document setupEditor:@"editorLineSpacing"],
                     @"setupEditor:editorLineSpacing should not crash when zoomed");
}

/**
 * Calling setupEditor: for a style change while zoomed should not crash.
 */
- (void)testSetupEditorDoesNotCrashForStyleChangeWhileZoomed
{
    self.document.zoomMultiplier = 1.3;
    XCTAssertNoThrow([self.document setupEditor:@"editorStyleName"],
                     @"setupEditor:editorStyleName should not crash when zoomed");
}

/**
 * After zooming to 1.5 and calling applyCurrentZoom, a subsequent
 * setupEditor:editorBaseFontInfo must not revert the editor font to the
 * unzoomed base size.
 *
 * Skips in headless environments where the editor outlet is nil.
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

    XCTAssertEqualWithAccuracy(afterSetupPointSize, zoomedPointSize, 0.1,
                               @"setupEditor: must not revert the editor font to "
                               @"the unzoomed base size after applyCurrentZoom has run");
}

/**
 * After zooming, a preference change (setupEditor:), and another zoomIn:,
 * the multiplier should advance to the next persisted preset.
 * This exercises the multiplier state across a full zoom -> preference -> zoom cycle.
 *
 * CORRECTED replacement for the removed testZoomThenPreferenceChangeThenZoomAgain:
 * the original test's numeric expectation (1.5 -> 2.0) was actually already
 * correct, but its docstring attributed that to a flat-model "advance by
 * 0.1 per step" story, which is not what the code does. Per
 * MPDocumentZoomLevels() (MPDocument.m ~line 133-141) the preset list is
 * ..., 1.25, 1.5, 2.0, 3.0 - so 1.5 is itself an exact preset, and
 * -stepDocumentZoomDirection: (MPDocument.m ~line 4409, exact-match branch
 * ~line 4430-4433) simply advances to the very next entry in that list,
 * which is 2.0, not "1.5 + 0.1". setupEditor: (MPDocument.m ~line 2887)
 * does not read or write documentZoomLevel, so it cannot perturb the
 * multiplier between the two zoom calls; this test still confirms that.
 */
- (void)testZoomThenPreferenceChangeThenZoomAgainSnapsToNextPreset
{
    self.document.zoomMultiplier = 1.5;
    XCTAssertNoThrow([self.document setupEditor:@"editorBaseFontInfo"],
                     @"setupEditor: should not throw while zoomed");

    [self.document zoomIn:nil];

    XCTAssertEqualWithAccuracy(self.document.zoomMultiplier, 2.0, 0.001,
                               @"After zoom(1.5) -> setupEditor -> zoomIn, "
                               @"multiplier should advance to the next preset "
                               @"in the list (2.0), per the preset-snap model");
}


/**
 * Cross-window zoom propagation: when doc A changes the shared
 * documentZoomLevel default, doc B's KVO handler must actually run.
 *
 * Every MPDocument KVO-registers on [NSUserDefaults standardUserDefaults]
 * for the keys in MPEditorPreferencesToObserve() (MPDocument.m ~line 109),
 * which includes "documentZoomLevel". -observeValueForKeyPath:... (~line
 * 2179-2203) special-cases that key: it calls -applyCurrentZoom and returns
 * immediately (~line 2194-2198), with no other code path that could also
 * invoke -applyCurrentZoom for the same KVO change. So a single write to
 * the shared documentZoomLevel pref must produce exactly one call to
 * -applyCurrentZoom on every registered observer -- hence the exact ( == 1
 * ) count assertion below, rather than a >= 1 relaxation.
 *
 * -setZoomMultiplier: (~line 3101-3105) is the writer: it clamps and stores
 * into self.preferences.documentZoomLevel, which is @dynamic-backed by
 * [NSUserDefaults standardUserDefaults] (MPPreferences.m line 261), so
 * writing through doc A's zoomMultiplier is the same shared-pref write
 * doc B's observer is watching.
 *
 * Doc B registers via -registerSharedPreferenceObservers directly (the
 * headless entry point extracted from the nib-loading path in Fix #4)
 * instead of via -makeWindowControllers/a loaded nib, keeping this test
 * fully headless. Because doc B never goes through that nib path,
 * -close's cleanup is gated on `needsToUnregister`, which is only set to
 * YES from within that same path (~line 746) -- so -close would NOT
 * unregister doc B here. Explicitly calling
 * -unregisterSharedPreferenceObservers before releasing doc B is therefore
 * required to avoid a KVO-observer-still-registered crash on dealloc.
 *
 * [super applyCurrentZoom] is headless-safe: it calls
 * -applyEditorFontAndParagraphStyle, which only assigns to
 * self.editor.defaultParagraphStyle/.font (~line 3151-3153) -- messaging
 * the nil `editor` outlet in a headless doc B is a no-op, not a crash --
 * and -scaleWebview, which guards `if (!self.preview) return;`
 * (~line 3107-3110) before touching the (nil, headless) preview.
 */
- (void)testZoomChangeInDocAPropagatesToDocB
{
    MPZoomSpyDocument *docB = [[MPZoomSpyDocument alloc] init];
    MPDocument *docA = [[MPDocument alloc] init];

    // Known baseline on the shared pref, using the same accessor this
    // file's setUp/tearDown already save and restore.
    [MPPreferences sharedInstance].documentZoomLevel = 1.0;

    [docB registerSharedPreferenceObservers];
    docB.applyCurrentZoomCount = 0; // Ignore any registration-time noise.

    docA.zoomMultiplier = 1.5; // Writes the shared documentZoomLevel pref.

    XCTAssertEqual(docB.applyCurrentZoomCount, 1,
        @"Doc B's zoom observer must fire exactly once when Doc A changes the shared zoom");
    XCTAssertEqualWithAccuracy(docB.lastAppliedMultiplier, 1.5, 0.001,
        @"Doc B must observe the propagated multiplier");

    // REQUIRED: doc B registered outside the nib path, so -close's
    // needsToUnregister-gated cleanup will not run for it.
    [docB unregisterSharedPreferenceObservers];
    docB = nil;
    docA = nil;
}


#pragma mark - Tab Stop Calculation Tests

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
 * After zooming to 2.0 and applying, the first tab stop should match the
 * tab interval computed from the zoomed font, not the base font.
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

    XCTAssertEqualWithAccuracy(firstTab.location, expectedTabInterval, 0.5,
                               @"First tab stop must reflect zoomed font size, "
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


#pragma mark - Preview Scale Calculation Tests

/**
 * scaleWebview routes through previewScale. These tests pin the scale
 * computation across both branches of the previewZoomRelativeToBaseFontSize
 * preference, including the regression risk introduced by removing the
 * old early-return when the preference is OFF.
 *
 * Each test saves and restores the preference values it touches so the
 * shared MPPreferences instance is not mutated across tests.
 */

- (void)testPreviewScaleAtDefaultZoomWhenPreferenceOffIsOne
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL savedPref = prefs.previewZoomRelativeToBaseFontSize;
    @try {
        prefs.previewZoomRelativeToBaseFontSize = NO;
        self.document.zoomMultiplier = 1.0;

        XCTAssertEqualWithAccuracy([self.document previewScale], 1.0, 0.001,
                                   @"At default zoom with preference OFF, "
                                   @"previewScale must be 1.0 (no-op).");
    } @finally {
        prefs.previewZoomRelativeToBaseFontSize = savedPref;
    }
}

- (void)testPreviewScaleTracksZoomMultiplierWhenPreferenceOff
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL savedPref = prefs.previewZoomRelativeToBaseFontSize;
    @try {
        prefs.previewZoomRelativeToBaseFontSize = NO;
        self.document.zoomMultiplier = 1.5;

        XCTAssertEqualWithAccuracy([self.document previewScale], 1.5, 0.001,
                                   @"With preference OFF, previewScale should "
                                   @"equal zoomMultiplier (1.5).");

        self.document.zoomMultiplier = 0.5;
        XCTAssertEqualWithAccuracy([self.document previewScale], 0.5, 0.001,
                                   @"With preference OFF, previewScale should "
                                   @"track zoomMultiplier across changes.");
    } @finally {
        prefs.previewZoomRelativeToBaseFontSize = savedPref;
    }
}

- (void)testPreviewScaleCombinesFontRatioAndZoomWhenPreferenceOn
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL savedPref = prefs.previewZoomRelativeToBaseFontSize;
    NSFont *savedFont = prefs.editorBaseFont;
    @try {
        prefs.previewZoomRelativeToBaseFontSize = YES;

        NSFont *font21 = [NSFont fontWithName:savedFont.fontName size:21.0];
        if (!font21) {
            NSLog(@"Skipping testPreviewScaleCombinesFontRatioAndZoomWhenPreferenceOn"
                  @" - cannot construct 21pt variant of base font.");
            return;
        }
        prefs.editorBaseFont = font21;

        self.document.zoomMultiplier = 2.0;

        // 21pt / 14pt default = 1.5; combined with 2.0 zoom = 3.0.
        XCTAssertEqualWithAccuracy([self.document previewScale], 3.0, 0.01,
                                   @"With preference ON, previewScale should "
                                   @"be (fontSize/14) * zoomMultiplier.");
    } @finally {
        prefs.editorBaseFont = savedFont;
        prefs.previewZoomRelativeToBaseFontSize = savedPref;
    }
}

- (void)testPreviewScaleAtDefaultZoomWhenPreferenceOnMatchesFontRatio
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL savedPref = prefs.previewZoomRelativeToBaseFontSize;
    @try {
        prefs.previewZoomRelativeToBaseFontSize = YES;
        self.document.zoomMultiplier = 1.0;

        // At zoom 1.0, scale should match the legacy fontSize/14 behaviour.
        CGFloat expected = prefs.editorBaseFontSize / 14.0;
        XCTAssertEqualWithAccuracy([self.document previewScale], expected, 0.001,
                                   @"At zoom 1.0 with preference ON, previewScale"
                                   @" must equal the pre-PR fontSize/14 ratio.");
    } @finally {
        prefs.previewZoomRelativeToBaseFontSize = savedPref;
    }
}

@end
