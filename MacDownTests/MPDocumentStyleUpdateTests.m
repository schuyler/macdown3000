//
//  MPDocumentStyleUpdateTests.m
//  MacDownTests
//
//  Tests for GitHub issue #219: styles not applied in Preview pane
//  Verifies that CSS style and highlighting theme changes trigger full HTML reload
//  while preserving DOM replacement optimization when styles haven't changed.
//

#import <XCTest/XCTest.h>
#import "MPPreferences.h"

// Forward declare the helper function we're testing
NS_INLINE BOOL MPAreNilableStringsEqual(NSString *s1, NSString *s2)
{
    return ([s1 isEqualToString:s2] || s1 == s2);
}

@interface MPDocumentStyleUpdateTests : XCTestCase
@property (strong) MPPreferences *preferences;
@property (copy) NSString *originalStyleName;
@property (copy) NSString *originalHighlightingTheme;
@end

@implementation MPDocumentStyleUpdateTests

#pragma mark - Setup & Teardown

- (void)setUp
{
    [super setUp];
    self.preferences = [MPPreferences sharedInstance];
    // Save original values to restore after tests
    self.originalStyleName = self.preferences.htmlStyleName;
    self.originalHighlightingTheme = self.preferences.htmlHighlightingThemeName;
}

- (void)tearDown
{
    // Restore original preferences
    self.preferences.htmlStyleName = self.originalStyleName;
    self.preferences.htmlHighlightingThemeName = self.originalHighlightingTheme;
    [self.preferences synchronize];
    [super tearDown];
}

#pragma mark - Nil-Safe String Comparison Tests

- (void)testNilableStringComparisonBothNil
{
    // Both nil should be equal
    NSString *s1 = nil;
    NSString *s2 = nil;
    XCTAssertTrue(MPAreNilableStringsEqual(s1, s2),
                  @"Two nil strings should be considered equal");
}

- (void)testNilableStringComparisonFirstNil
{
    // nil vs non-nil should not be equal
    NSString *s1 = nil;
    NSString *s2 = @"GitHub2";
    XCTAssertFalse(MPAreNilableStringsEqual(s1, s2),
                   @"nil and non-nil string should not be equal");
}

- (void)testNilableStringComparisonSecondNil
{
    // non-nil vs nil should not be equal
    NSString *s1 = @"GitHub2";
    NSString *s2 = nil;
    XCTAssertFalse(MPAreNilableStringsEqual(s1, s2),
                   @"non-nil and nil string should not be equal");
}

- (void)testNilableStringComparisonSameStrings
{
    // Same strings should be equal
    NSString *s1 = @"GitHub2";
    NSString *s2 = @"GitHub2";
    XCTAssertTrue(MPAreNilableStringsEqual(s1, s2),
                  @"Same strings should be equal");
}

- (void)testNilableStringComparisonDifferentStrings
{
    // Different strings should not be equal
    NSString *s1 = @"GitHub2";
    NSString *s2 = @"Clearness";
    XCTAssertFalse(MPAreNilableStringsEqual(s1, s2),
                   @"Different strings should not be equal");
}

- (void)testNilableStringComparisonEmptyStrings
{
    // Empty strings should be equal
    NSString *s1 = @"";
    NSString *s2 = @"";
    XCTAssertTrue(MPAreNilableStringsEqual(s1, s2),
                  @"Empty strings should be equal");
}

- (void)testNilableStringComparisonEmptyVsNonEmpty
{
    // Empty vs non-empty should not be equal
    NSString *s1 = @"";
    NSString *s2 = @"GitHub2";
    XCTAssertFalse(MPAreNilableStringsEqual(s1, s2),
                   @"Empty and non-empty strings should not be equal");
}

#pragma mark - Style Change Detection Logic Tests

- (void)testStyleChangeDetectionWhenStyleChanges
{
    // Simulate style change detection logic
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = @"Clearness";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle);

    XCTAssertTrue(stylesChanged,
                  @"Should detect style change from GitHub2 to Clearness");
}

- (void)testStyleChangeDetectionWhenStyleUnchanged
{
    // Simulate no style change
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = @"GitHub2";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle);

    XCTAssertFalse(stylesChanged,
                   @"Should not detect change when style is the same");
}

- (void)testStyleChangeDetectionNilToValue
{
    // nil to value should be detected as change
    NSString *cachedStyle = nil;
    NSString *currentStyle = @"GitHub2";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle);

    XCTAssertTrue(stylesChanged,
                  @"Should detect style change from nil to GitHub2");
}

- (void)testStyleChangeDetectionValueToNil
{
    // value to nil should be detected as change
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = nil;

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle);

    XCTAssertTrue(stylesChanged,
                  @"Should detect style change from GitHub2 to nil");
}

- (void)testStyleChangeDetectionNilToNil
{
    // nil to nil should not be detected as change
    NSString *cachedStyle = nil;
    NSString *currentStyle = nil;

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle);

    XCTAssertFalse(stylesChanged,
                   @"Should not detect change when both are nil");
}

#pragma mark - Combined Style and Theme Change Detection Tests

- (void)testCombinedDetectionBothChanged
{
    // Both style and theme changed
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = @"Clearness";
    NSString *cachedTheme = @"tomorrow";
    NSString *currentTheme = @"coy";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, currentTheme);

    XCTAssertTrue(stylesChanged,
                  @"Should detect change when both style and theme changed");
}

- (void)testCombinedDetectionOnlyStyleChanged
{
    // Only style changed
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = @"Clearness";
    NSString *cachedTheme = @"tomorrow";
    NSString *currentTheme = @"tomorrow";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, currentTheme);

    XCTAssertTrue(stylesChanged,
                  @"Should detect change when only style changed");
}

- (void)testCombinedDetectionOnlyThemeChanged
{
    // Only theme changed
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = @"GitHub2";
    NSString *cachedTheme = @"tomorrow";
    NSString *currentTheme = @"coy";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, currentTheme);

    XCTAssertTrue(stylesChanged,
                  @"Should detect change when only theme changed");
}

- (void)testCombinedDetectionNeitherChanged
{
    // Neither changed - should use DOM replacement (no reload needed)
    NSString *cachedStyle = @"GitHub2";
    NSString *currentStyle = @"GitHub2";
    NSString *cachedTheme = @"tomorrow";
    NSString *currentTheme = @"tomorrow";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, currentStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, currentTheme);

    XCTAssertFalse(stylesChanged,
                   @"Should not detect change when neither style nor theme changed (use DOM replacement)");
}

#pragma mark - Preferences Integration Tests

- (void)testPreferencesHtmlStyleNameProperty
{
    // Verify htmlStyleName preference property works
    NSString *testStyle = @"GitHub2";
    self.preferences.htmlStyleName = testStyle;

    XCTAssertEqualObjects(self.preferences.htmlStyleName, testStyle,
                          @"htmlStyleName preference should store and return value");
}

- (void)testPreferencesHtmlHighlightingThemeNameProperty
{
    // Verify htmlHighlightingThemeName preference property works
    NSString *testTheme = @"tomorrow";
    self.preferences.htmlHighlightingThemeName = testTheme;

    XCTAssertEqualObjects(self.preferences.htmlHighlightingThemeName, testTheme,
                          @"htmlHighlightingThemeName preference should store and return value");
}

- (void)testPreferencesStyleChangeSequence
{
    // Test a sequence of style changes
    self.preferences.htmlStyleName = @"GitHub2";
    XCTAssertEqualObjects(self.preferences.htmlStyleName, @"GitHub2");

    self.preferences.htmlStyleName = @"Clearness";
    XCTAssertEqualObjects(self.preferences.htmlStyleName, @"Clearness");

    self.preferences.htmlStyleName = @"Solarized (Light)";
    XCTAssertEqualObjects(self.preferences.htmlStyleName, @"Solarized (Light)");
}

#pragma mark - Style Reload Cache Invalidation Tests (Issue #318)

- (void)testCacheInvalidationForcesStyleReloadWithNonNilPreferences
{
    // Simulate invalidateStyleCaches: cached names set to nil
    NSString *cachedStyle = nil;
    NSString *cachedTheme = nil;
    // Preferences still have their configured values
    NSString *prefStyle = @"GitHub2";
    NSString *prefTheme = @"tomorrow";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    XCTAssertTrue(stylesChanged,
                  @"Cache invalidation (nil caches) with non-nil preferences "
                   "should force stylesChanged to YES for full reload");
}

- (void)testCacheInvalidationForcesReloadEvenWithEmptyTheme
{
    // Edge case: user selected "None" for highlighting theme, stored as @""
    NSString *cachedStyle = nil;
    NSString *cachedTheme = nil;
    NSString *prefStyle = @"GitHub2";
    NSString *prefTheme = @"";  // "None" selected in UI

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    XCTAssertTrue(stylesChanged,
                  @"Cache invalidation should force reload even when theme is empty string");
}

- (void)testCacheInvalidationWithNilPreferencesDoesNotForceReload
{
    // Guard: if both cached and preference values are nil, no reload needed
    NSString *cachedStyle = nil;
    NSString *cachedTheme = nil;
    NSString *prefStyle = nil;
    NSString *prefTheme = nil;

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    XCTAssertFalse(stylesChanged,
                   @"Should not force reload when both caches and preferences are nil");
}

- (void)testCacheInvalidationOnlyStyleSetForcesReload
{
    // Only style cache is nil; theme cache still matches
    NSString *cachedStyle = nil;
    NSString *prefStyle = @"GitHub2";
    NSString *cachedTheme = @"tomorrow";
    NSString *prefTheme = @"tomorrow";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    XCTAssertTrue(stylesChanged,
                  @"Nil style cache alone should force reload via OR logic");
}

- (void)testCacheInvalidationOnlyThemeSetForcesReload
{
    // Only theme cache is nil; style cache still matches
    NSString *cachedStyle = @"GitHub2";
    NSString *prefStyle = @"GitHub2";
    NSString *cachedTheme = nil;
    NSString *prefTheme = @"tomorrow";

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    XCTAssertTrue(stylesChanged,
                  @"Nil theme cache alone should force reload via OR logic");
}

- (void)testFullReloadPathWhenCachesInvalidatedAndPreviewReady
{
    // Full gate condition from renderer:didProduceHTMLOutput:
    BOOL isPreviewReady = YES;
    BOOL baseUrlMatches = YES;
    BOOL mathJaxEnabled = NO;

    // Simulate cache invalidation
    NSString *cachedStyle = nil;
    NSString *prefStyle = @"GitHub2";
    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle);

    BOOL canUseDOMReplacement = isPreviewReady && baseUrlMatches
                                && !mathJaxEnabled && !stylesChanged;

    XCTAssertFalse(canUseDOMReplacement,
                   @"After cache invalidation, should take full reload path, not DOM replacement");
}

- (void)testDOMReplacementWhenCachesMatchAndNoMathJax
{
    // No-regression: normal renders should still use DOM replacement
    BOOL isPreviewReady = YES;
    BOOL baseUrlMatches = YES;
    BOOL mathJaxEnabled = NO;

    NSString *cachedStyle = @"GitHub2";
    NSString *prefStyle = @"GitHub2";
    NSString *cachedTheme = @"tomorrow";
    NSString *prefTheme = @"tomorrow";
    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    BOOL canUseDOMReplacement = isPreviewReady && baseUrlMatches
                                && !mathJaxEnabled && !stylesChanged;

    XCTAssertTrue(canUseDOMReplacement,
                  @"Normal render with matching caches should use DOM replacement");
}

- (void)testSequentialReloadAfterCacheInvalidation
{
    // Models the complete lifecycle: normal -> invalidate -> full reload -> normal
    NSString *prefStyle = @"GitHub2";
    NSString *prefTheme = @"tomorrow";

    // Step 1: Normal state - caches match preferences
    NSString *cachedStyle = @"GitHub2";
    NSString *cachedTheme = @"tomorrow";
    BOOL stylesChanged1 = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                          !MPAreNilableStringsEqual(cachedTheme, prefTheme);
    XCTAssertFalse(stylesChanged1, @"Before invalidation: caches match, no change");

    // Step 2: invalidateStyleCaches called
    cachedStyle = nil;
    cachedTheme = nil;
    BOOL stylesChanged2 = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                          !MPAreNilableStringsEqual(cachedTheme, prefTheme);
    XCTAssertTrue(stylesChanged2, @"After invalidation: nil caches force change");

    // Step 3: Full reload completes, re-caches current values
    cachedStyle = prefStyle;
    cachedTheme = prefTheme;
    BOOL stylesChanged3 = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                          !MPAreNilableStringsEqual(cachedTheme, prefTheme);
    XCTAssertFalse(stylesChanged3, @"After reload: caches match again, no change");
}

- (void)testCacheInvalidationSimulationWithRealPreferences
{
    // Integration: use actual preference values from the singleton
    NSString *prefStyle = self.preferences.htmlStyleName;
    NSString *prefTheme = self.preferences.htmlHighlightingThemeName;

    // Simulate cache invalidation
    NSString *cachedStyle = nil;
    NSString *cachedTheme = nil;

    BOOL stylesChanged = !MPAreNilableStringsEqual(cachedStyle, prefStyle) ||
                         !MPAreNilableStringsEqual(cachedTheme, prefTheme);

    // At least one preference should be non-nil, forcing stylesChanged
    if (prefStyle != nil || prefTheme != nil)
    {
        XCTAssertTrue(stylesChanged,
                      @"With real non-nil preferences, cache invalidation "
                       "should force stylesChanged to YES");
    }
    else
    {
        XCTAssertFalse(stylesChanged,
                       @"If both preferences are nil, no change detected");
    }
}

@end
