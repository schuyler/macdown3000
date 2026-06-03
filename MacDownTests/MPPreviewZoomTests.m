//
//  MPPreviewZoomTests.m
//  MacDown 3000
//
//  Tests for the preview pane zoom feature: preset snap-step semantics,
//  default level, clamping at the bounds, and the actualPreviewSize:
//  reset action. These tests exercise the preference/snap logic in
//  isolation from the WebView. The integration with WebView
//  setPageSizeMultiplier: is covered manually because the page-size
//  multiplier is a private WebKit API that is meaningful only when a
//  real WebView is rendering loaded HTML.
//

#import <XCTest/XCTest.h>
#import "MPPreferences.h"
#import "MPDocument.h"


// Expose the private snap-step helper so tests can drive the snap logic
// directly without instantiating the full nib. The implementation lives
// in MPDocument.m; this category just makes the selector visible.
@interface MPDocument (MPPreviewZoomTests)
- (void)stepPreviewZoomDirection:(NSInteger)direction;
@end


@interface MPPreviewZoomTests : XCTestCase
@property (strong) MPDocument *document;
@property (assign) CGFloat originalZoomLevel;
@end


@implementation MPPreviewZoomTests

- (void)setUp
{
    [super setUp];
    self.originalZoomLevel = [MPPreferences sharedInstance].previewZoomLevel;
    // Instantiate MPDocument directly. The IBOutlet `preview` will be
    // nil, which is fine: applyPreviewZoom guards against a nil preview
    // and the snap-step logic operates on the preference only.
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    // Restore the previous preference so the user's persisted setting is
    // not perturbed by the test run.
    [MPPreferences sharedInstance].previewZoomLevel = self.originalZoomLevel;
    [[MPPreferences sharedInstance] synchronize];
    self.document = nil;
    [super tearDown];
}

#pragma mark - Default

/**
 * After fresh-install initialization, previewZoomLevel must be 1.0.
 * loadDefaultUserDefaults sets the defensive default, and the migration
 * path also sets 1.0 for upgrades. Either way, an existing test
 * environment must observe a non-zero (specifically 1.0) zoom level.
 */
- (void)testDefaultZoomLevelIsOne
{
    // Re-initialize a fresh instance — sharedInstance has already run
    // initialization at the start of the test process.
    MPPreferences *prefs = [MPPreferences sharedInstance];
    XCTAssertEqualWithAccuracy(prefs.previewZoomLevel, 1.0, 1e-9,
                               @"Default preview zoom level should be 1.0");
}

#pragma mark - Stepping at preset boundaries

- (void)testStepUpFromOneHundredGoesTo110
{
    [MPPreferences sharedInstance].previewZoomLevel = 1.0;
    [self.document stepPreviewZoomDirection:+1];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               1.1, 1e-9,
                               @"Step up from 100%% should land on 110%%");
}

- (void)testStepDownFromOneHundredGoesTo90
{
    [MPPreferences sharedInstance].previewZoomLevel = 1.0;
    [self.document stepPreviewZoomDirection:-1];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               0.9, 1e-9,
                               @"Step down from 100%% should land on 90%%");
}

#pragma mark - Clamping at bounds

- (void)testStepUpAtMaxIsClamped
{
    [MPPreferences sharedInstance].previewZoomLevel = 2.0;
    [self.document stepPreviewZoomDirection:+1];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               2.0, 1e-9,
                               @"Stepping up at the max preset must not change the level");
}

- (void)testStepDownAtMinIsClamped
{
    [MPPreferences sharedInstance].previewZoomLevel = 0.5;
    [self.document stepPreviewZoomDirection:-1];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               0.5, 1e-9,
                               @"Stepping down at the min preset must not change the level");
}

#pragma mark - Snap-from-off-preset

- (void)testSnapFromOffPresetUpRoundsUp
{
    [MPPreferences sharedInstance].previewZoomLevel = 1.05;
    [self.document stepPreviewZoomDirection:+1];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               1.1, 1e-9,
                               @"Step up from 105%% should snap to the next preset above (110%%)");
}

- (void)testSnapFromOffPresetDownRoundsDown
{
    [MPPreferences sharedInstance].previewZoomLevel = 1.05;
    [self.document stepPreviewZoomDirection:-1];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               1.0, 1e-9,
                               @"Step down from 105%% should snap to the next preset below (100%%)");
}

#pragma mark - Actual size action

- (void)testActualSizeResets
{
    [MPPreferences sharedInstance].previewZoomLevel = 1.5;
    [self.document actualPreviewSize:nil];
    XCTAssertEqualWithAccuracy([MPPreferences sharedInstance].previewZoomLevel,
                               1.0, 1e-9,
                               @"actualPreviewSize: must reset zoom level to 1.0");
}

@end
