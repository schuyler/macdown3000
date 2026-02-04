//
//  MPPreferencesTests.m
//  MPPreferencesTests
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPPreferences.h"

@interface MPPreferencesTests : XCTestCase
@property MPPreferences *preferences;
@property NSDictionary *oldFontInfo;
@end


@implementation MPPreferencesTests

- (void)setUp
{
    [super setUp];
    self.preferences = [MPPreferences sharedInstance];
    self.oldFontInfo = [self.preferences.editorBaseFontInfo copy];
}

- (void)tearDown
{
    // Only restore font info which is what the original test modified
    self.preferences.editorBaseFontInfo = self.oldFontInfo;
    [self.preferences synchronize];
    [super tearDown];
}

#pragma mark - Font Tests

- (void)testFont
{
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    self.preferences.editorBaseFont = font;

    XCTAssertTrue([self.preferences synchronize],
                  @"Failed to synchronize user defaults.");

    NSFont *result = [self.preferences.editorBaseFont copy];
    XCTAssertEqualObjects(font, result,
                          @"Preferences not preserving font info correctly.");
}

- (void)testFontWithDifferentSizes
{
    // Test various font sizes
    CGFloat sizes[] = {10.0, 12.0, 14.0, 18.0, 24.0, 36.0};

    for (int i = 0; i < sizeof(sizes)/sizeof(sizes[0]); i++) {
        NSFont *font = [NSFont systemFontOfSize:sizes[i]];
        self.preferences.editorBaseFont = font;
        [self.preferences synchronize];

        CGFloat resultSize = self.preferences.editorBaseFontSize;
        XCTAssertEqualWithAccuracy(resultSize, sizes[i], 0.01,
                                   @"Font size should be preserved");
    }
}

- (void)testFontWithMonospaceFont
{
    NSFont *monoFont = [NSFont monospacedSystemFontOfSize:14.0 weight:NSFontWeightRegular];
    if (monoFont) {
        self.preferences.editorBaseFont = monoFont;
        [self.preferences synchronize];

        NSFont *result = self.preferences.editorBaseFont;
        XCTAssertNotNil(result, @"Should retrieve font");
        XCTAssertEqualWithAccuracy(result.pointSize, 14.0, 0.01, @"Size should match");
    }
}


#pragma mark - Boolean Preference Tests

- (void)testSyntaxHighlightingToggle
{
    // Save original
    BOOL original = self.preferences.htmlSyntaxHighlighting;

    // Toggle ON
    self.preferences.htmlSyntaxHighlighting = YES;
    XCTAssertTrue([self.preferences synchronize], @"Should sync");
    XCTAssertTrue(self.preferences.htmlSyntaxHighlighting, @"Should be ON");

    // Toggle OFF
    self.preferences.htmlSyntaxHighlighting = NO;
    XCTAssertTrue([self.preferences synchronize], @"Should sync");
    XCTAssertFalse(self.preferences.htmlSyntaxHighlighting, @"Should be OFF");

    // Restore
    self.preferences.htmlSyntaxHighlighting = original;
    [self.preferences synchronize];
}

- (void)testMathJaxToggle
{
    BOOL original = self.preferences.htmlMathJax;

    self.preferences.htmlMathJax = YES;
    [self.preferences synchronize];
    XCTAssertTrue(self.preferences.htmlMathJax, @"MathJax should be ON");

    self.preferences.htmlMathJax = NO;
    [self.preferences synchronize];
    XCTAssertFalse(self.preferences.htmlMathJax, @"MathJax should be OFF");

    // Restore
    self.preferences.htmlMathJax = original;
    [self.preferences synchronize];
}

- (void)testExtensionFlags
{
    // Save originals
    BOOL originalTables = self.preferences.extensionTables;
    BOOL originalStrike = self.preferences.extensionStrikethough;

    // Test table extension
    self.preferences.extensionTables = YES;
    [self.preferences synchronize];
    XCTAssertTrue(self.preferences.extensionTables, @"Tables should be ON");

    self.preferences.extensionTables = NO;
    [self.preferences synchronize];
    XCTAssertFalse(self.preferences.extensionTables, @"Tables should be OFF");

    // Test strikethrough extension
    self.preferences.extensionStrikethough = YES;
    [self.preferences synchronize];
    XCTAssertTrue(self.preferences.extensionStrikethough, @"Strikethrough should be ON");

    // Restore
    self.preferences.extensionTables = originalTables;
    self.preferences.extensionStrikethough = originalStrike;
    [self.preferences synchronize];
}


#pragma mark - String Preference Tests

- (void)testStyleNamePersistence
{
    // Save original
    NSString *original = self.preferences.htmlStyleName;

    NSString *testStyleName = @"GitHub2";
    self.preferences.htmlStyleName = testStyleName;
    [self.preferences synchronize];

    NSString *result = self.preferences.htmlStyleName;
    XCTAssertEqualObjects(result, testStyleName, @"Style name should persist");

    // Restore
    self.preferences.htmlStyleName = original;
    [self.preferences synchronize];
}

- (void)testHighlightingThemeNamePersistence
{
    // Save original
    NSString *original = self.preferences.htmlHighlightingThemeName;

    NSString *testTheme = @"tomorrow";
    self.preferences.htmlHighlightingThemeName = testTheme;
    [self.preferences synchronize];

    NSString *result = self.preferences.htmlHighlightingThemeName;
    XCTAssertEqualObjects(result, testTheme, @"Theme name should persist");

    // Restore
    self.preferences.htmlHighlightingThemeName = original;
    [self.preferences synchronize];
}


#pragma mark - Singleton Tests

- (void)testSharedInstanceReturnsSameObject
{
    MPPreferences *instance1 = [MPPreferences sharedInstance];
    MPPreferences *instance2 = [MPPreferences sharedInstance];

    XCTAssertTrue(instance1 == instance2, @"Should return same singleton instance");
}


#pragma mark - Edge Cases

- (void)testNilFontInfoHandledGracefully
{
    // Setting font info to nil should not crash
    NSDictionary *original = self.preferences.editorBaseFontInfo;

    // This should not throw an exception
    XCTAssertNoThrow(self.preferences.editorBaseFontInfo = nil,
                     @"Setting nil font info should not throw");
    XCTAssertNoThrow([self.preferences synchronize],
                     @"Synchronize with nil font info should not throw");

    // Restore
    self.preferences.editorBaseFontInfo = original;
    [self.preferences synchronize];
}

- (void)testSynchronizeReturnsSuccess
{
    // Simple change and sync
    BOOL originalValue = self.preferences.htmlMathJax;
    self.preferences.htmlMathJax = !originalValue;

    BOOL success = [self.preferences synchronize];
    XCTAssertTrue(success, @"Synchronize should succeed");

    // Restore
    self.preferences.htmlMathJax = originalValue;
    [self.preferences synchronize];
}


#pragma mark - Numeric Preference Tests

- (void)testEditorInsetValues
{
    CGFloat original = self.preferences.editorHorizontalInset;

    CGFloat testInset = 25.0;
    self.preferences.editorHorizontalInset = testInset;
    [self.preferences synchronize];

    CGFloat result = self.preferences.editorHorizontalInset;
    XCTAssertEqualWithAccuracy(result, testInset, 0.01, @"Inset should persist");

    // Restore
    self.preferences.editorHorizontalInset = original;
    [self.preferences synchronize];
}

- (void)testEditorMaximumWidth
{
    CGFloat original = self.preferences.editorMaximumWidth;

    CGFloat testWidth = 800.0;
    self.preferences.editorMaximumWidth = testWidth;
    [self.preferences synchronize];

    CGFloat result = self.preferences.editorMaximumWidth;
    XCTAssertEqualWithAccuracy(result, testWidth, 0.01, @"Width should persist");

    // Restore
    self.preferences.editorMaximumWidth = original;
    [self.preferences synchronize];
}

- (void)testEditorLineSpacing
{
    CGFloat original = self.preferences.editorLineSpacing;

    CGFloat testSpacing = 1.5;
    self.preferences.editorLineSpacing = testSpacing;
    [self.preferences synchronize];

    CGFloat result = self.preferences.editorLineSpacing;
    XCTAssertEqualWithAccuracy(result, testSpacing, 0.01, @"Line spacing should persist");

    // Restore
    self.preferences.editorLineSpacing = original;
    [self.preferences synchronize];
}


#pragma mark - Checkbox/Task List Migration Tests

/**
 * Test that checkbox/task list is enabled by default for fresh installs.
 * Related to GitHub issue #269.
 */
- (void)testCheckboxEnabledByDefaultForFreshInstall
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalTaskList = [defaults objectForKey:@"htmlTaskList"];
    NSNumber *originalMigrationFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalMigrationVersion = [defaults objectForKey:@"MPMigrationVersion"];

    // Simulate fresh install: remove the migration flag, version, and preference
    [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults removeObjectForKey:@"MPMigrationVersion"];
    [defaults removeObjectForKey:@"htmlTaskList"];

    // Create a new preferences instance to trigger loadDefaultUserDefaults
    // Note: Since MPPreferences is a singleton, we call loadDefaultUserDefaults directly
    // by reinitializing - this simulates app launch
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // After migration, htmlTaskList should be enabled
    XCTAssertTrue(prefs.htmlTaskList,
                  @"Checkbox/task list should be enabled by default for fresh installs");

    // Migration flag should be set (for backward compatibility)
    XCTAssertTrue([defaults boolForKey:@"MPDidApplyTaskListDefaultFix"],
                  @"Migration flag should be set after first run");

    // Restore original values
    if (originalMigrationFlag)
        [defaults setObject:originalMigrationFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalTaskList)
        [defaults setObject:originalTaskList forKey:@"htmlTaskList"];
    else
        [defaults removeObjectForKey:@"htmlTaskList"];

    if (originalMigrationVersion)
        [defaults setObject:originalMigrationVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];
}

/**
 * Test that checkbox migration applies to existing users who haven't set a preference.
 * Related to GitHub issue #269.
 */
- (void)testCheckboxMigrationAppliesWhenPreferenceUnset
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalTaskList = [defaults objectForKey:@"htmlTaskList"];
    NSNumber *originalMigrationFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalMigrationVersion = [defaults objectForKey:@"MPMigrationVersion"];

    // Simulate existing user without migration: no flag, no version, no explicit preference
    [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults removeObjectForKey:@"MPMigrationVersion"];
    [defaults removeObjectForKey:@"htmlTaskList"];

    // Trigger preferences loading
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // htmlTaskList should now be enabled
    XCTAssertTrue(prefs.htmlTaskList,
                  @"Migration should enable checkbox for users without explicit preference");

    // Restore original values
    if (originalMigrationFlag)
        [defaults setObject:originalMigrationFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalTaskList)
        [defaults setObject:originalTaskList forKey:@"htmlTaskList"];
    else
        [defaults removeObjectForKey:@"htmlTaskList"];

    if (originalMigrationVersion)
        [defaults setObject:originalMigrationVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];
}

/**
 * Test that user's explicit choice to disable checkboxes is preserved after migration.
 * Related to GitHub issue #269.
 */
- (void)testCheckboxMigrationPreservesUserDisableChoice
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalTaskList = [defaults objectForKey:@"htmlTaskList"];
    NSNumber *originalMigrationFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalMigrationVersion = [defaults objectForKey:@"MPMigrationVersion"];

    // Simulate user who has already had migration applied AND explicitly disabled
    // Use version 3 to indicate all migrations have been applied
    [defaults setInteger:3 forKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults setBool:NO forKey:@"htmlTaskList"];

    // Trigger preferences loading
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // User's explicit disable choice should be preserved
    XCTAssertFalse(prefs.htmlTaskList,
                   @"User's explicit choice to disable checkbox should be preserved");

    // Restore original values
    if (originalMigrationFlag)
        [defaults setObject:originalMigrationFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalTaskList)
        [defaults setObject:originalTaskList forKey:@"htmlTaskList"];
    else
        [defaults removeObjectForKey:@"htmlTaskList"];

    if (originalMigrationVersion)
        [defaults setObject:originalMigrationVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];
}

/**
 * Test that migration flag prevents reapplication of defaults.
 * Related to GitHub issue #269.
 */
- (void)testCheckboxMigrationFlagPreventsReapplication
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalTaskList = [defaults objectForKey:@"htmlTaskList"];
    NSNumber *originalMigrationFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalMigrationVersion = [defaults objectForKey:@"MPMigrationVersion"];

    // Set up: migration already applied (version 3), user explicitly disabled
    [defaults setInteger:3 forKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults setBool:NO forKey:@"htmlTaskList"];

    // Trigger preferences loading multiple times
    MPPreferences *prefs1 = [[MPPreferences alloc] init];
    XCTAssertFalse(prefs1.htmlTaskList, @"Should remain disabled after first load");

    MPPreferences *prefs2 = [[MPPreferences alloc] init];
    XCTAssertFalse(prefs2.htmlTaskList, @"Should remain disabled after second load");

    // Restore original values
    if (originalMigrationFlag)
        [defaults setObject:originalMigrationFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalTaskList)
        [defaults setObject:originalTaskList forKey:@"htmlTaskList"];
    else
        [defaults removeObjectForKey:@"htmlTaskList"];

    if (originalMigrationVersion)
        [defaults setObject:originalMigrationVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];
}

#pragma mark - Text Substitution Defaults (Issue #263)

/**
 * Verify automatic dash substitution is disabled by default.
 * This prevents --- horizontal rules from being converted to em-dash.
 * Regression test for Issue #263.
 */
- (void)testAutomaticDashSubstitutionDisabledByDefault
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // If the key doesn't exist, the default in MPEditorKeysToObserve() is @NO
    BOOL value = [defaults boolForKey:@"editorAutomaticDashSubstitutionEnabled"];
    XCTAssertFalse(value, @"Smart dashes should be disabled by default to preserve markdown syntax");
}

/**
 * Verify automatic quote substitution is disabled by default.
 * Regression test for Issue #263.
 */
- (void)testAutomaticQuoteSubstitutionDisabledByDefault
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL value = [defaults boolForKey:@"editorAutomaticQuoteSubstitutionEnabled"];
    XCTAssertFalse(value, @"Smart quotes should be disabled by default");
}

/**
 * Verify automatic text replacement is disabled by default.
 * Regression test for Issue #263.
 */
- (void)testAutomaticTextReplacementDisabledByDefault
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL value = [defaults boolForKey:@"editorAutomaticTextReplacementEnabled"];
    XCTAssertFalse(value, @"Text replacement should be disabled by default");
}

/**
 * Verify automatic spelling correction is disabled by default.
 * Regression test for Issue #263.
 */
- (void)testAutomaticSpellingCorrectionDisabledByDefault
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL value = [defaults boolForKey:@"editorAutomaticSpellingCorrectionEnabled"];
    XCTAssertFalse(value, @"Spelling correction should be disabled by default");
}


#pragma mark - Version-Based Migration System Tests (Issue #293)

/**
 * Test that fresh installations get the current migration version set.
 * Related to GitHub issue #293.
 */
- (void)testFreshInstallGetsCurrentMigrationVersion
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalSubstitutionFlag = [defaults objectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    NSNumber *originalTaskListFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Simulate fresh install: remove all migration-related keys
    [defaults removeObjectForKey:@"MPMigrationVersion"];
    [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults removeObjectForKey:@"extensionIntraEmphasis"];

    // Create new preferences instance
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Fresh install should set migration version to current (3)
    NSInteger version = [defaults integerForKey:@"MPMigrationVersion"];
    XCTAssertEqual(version, 3,
                   @"Fresh installation should set migration version to 3");

    // Intra-emphasis should be disabled
    XCTAssertFalse(prefs.extensionIntraEmphasis,
                   @"Fresh install should have intra-emphasis disabled");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalSubstitutionFlag)
        [defaults setObject:originalSubstitutionFlag forKey:@"MPDidApplySubstitutionDefaultsFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];

    if (originalTaskListFlag)
        [defaults setObject:originalTaskListFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

/**
 * Test that users with only substitution flag get inferred version 1.
 * Migrations 2 and 3 should be applied.
 * Related to GitHub issue #293.
 */
- (void)testMigrationFromLegacySubstitutionFlagOnly
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalSubstitutionFlag = [defaults objectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    NSNumber *originalTaskListFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];
    NSNumber *originalTaskList = [defaults objectForKey:@"htmlTaskList"];

    // Simulate user at version 1: only substitution flag set
    [defaults removeObjectForKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];  // Old default
    [defaults removeObjectForKey:@"htmlTaskList"];

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Migration version should be updated to 3
    NSInteger version = [defaults integerForKey:@"MPMigrationVersion"];
    XCTAssertEqual(version, 3,
                   @"Migration version should be updated to 3");

    // Version 2 migration: task list should be enabled
    XCTAssertTrue(prefs.htmlTaskList,
                  @"Task list migration (v2) should be applied");

    // Version 3 migration: intra-emphasis should be disabled
    XCTAssertFalse(prefs.extensionIntraEmphasis,
                   @"Intra-emphasis migration (v3) should be applied");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalSubstitutionFlag)
        [defaults setObject:originalSubstitutionFlag forKey:@"MPDidApplySubstitutionDefaultsFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];

    if (originalTaskListFlag)
        [defaults setObject:originalTaskListFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];

    if (originalTaskList)
        [defaults setObject:originalTaskList forKey:@"htmlTaskList"];
    else
        [defaults removeObjectForKey:@"htmlTaskList"];
}

/**
 * Test that users with both legacy flags get inferred version 2.
 * Only migration 3 should be applied.
 * Related to GitHub issue #293.
 */
- (void)testMigrationFromBothLegacyFlags
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalSubstitutionFlag = [defaults objectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    NSNumber *originalTaskListFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Simulate user at version 2: both legacy flags set
    [defaults removeObjectForKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults setBool:YES forKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];  // Old default

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Migration version should be updated to 3
    NSInteger version = [defaults integerForKey:@"MPMigrationVersion"];
    XCTAssertEqual(version, 3,
                   @"Migration version should be updated to 3");

    // Version 3 migration: intra-emphasis should be disabled
    XCTAssertFalse(prefs.extensionIntraEmphasis,
                   @"Intra-emphasis migration (v3) should be applied");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalSubstitutionFlag)
        [defaults setObject:originalSubstitutionFlag forKey:@"MPDidApplySubstitutionDefaultsFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];

    if (originalTaskListFlag)
        [defaults setObject:originalTaskListFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

/**
 * Test that explicit migration version takes precedence over legacy flags.
 * Related to GitHub issue #293.
 */
- (void)testExplicitMigrationVersionTakesPrecedence
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalSubstitutionFlag = [defaults objectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    NSNumber *originalTaskListFlag = [defaults objectForKey:@"MPDidApplyTaskListDefaultFix"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Set explicit version 3 - should skip all migrations even if legacy flags missing
    [defaults setInteger:3 forKey:@"MPMigrationVersion"];
    [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];  // User has it enabled

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Version 3 should NOT apply any migrations - user's choice preserved
    XCTAssertTrue(prefs.extensionIntraEmphasis,
                  @"Explicit version 3 should not change user's intra-emphasis setting");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalSubstitutionFlag)
        [defaults setObject:originalSubstitutionFlag forKey:@"MPDidApplySubstitutionDefaultsFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];

    if (originalTaskListFlag)
        [defaults setObject:originalTaskListFlag forKey:@"MPDidApplyTaskListDefaultFix"];
    else
        [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}


#pragma mark - Intra-Emphasis Migration Tests (Issue #293)

/**
 * Test that intra-emphasis is disabled by default for fresh installs.
 * This prevents underscore filenames from being italicized.
 * Related to GitHub issue #293.
 */
- (void)testIntraEmphasisDisabledByDefaultForFreshInstall
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];

    // Simulate fresh install
    [defaults removeObjectForKey:@"extensionIntraEmphasis"];
    [defaults removeObjectForKey:@"MPMigrationVersion"];
    [defaults removeObjectForKey:@"MPDidApplySubstitutionDefaultsFix"];
    [defaults removeObjectForKey:@"MPDidApplyTaskListDefaultFix"];

    // Create new preferences instance
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Fresh install should have intra-emphasis DISABLED
    XCTAssertFalse(prefs.extensionIntraEmphasis,
                   @"Fresh install should have intra-emphasis disabled (Issue #293)");

    // Restore originals
    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];

    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];
}

/**
 * Test that existing users at version 2 get migrated to disabled intra-emphasis.
 * Related to GitHub issue #293.
 */
- (void)testExistingUserAtVersion2GetsMigrated
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Simulate existing user at migration version 2 with intra-emphasis enabled
    [defaults setInteger:2 forKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Migration should disable intra-emphasis
    XCTAssertFalse(prefs.extensionIntraEmphasis,
                   @"Version 3 migration should disable intra-emphasis for existing users");

    // Migration version should be updated to 3
    NSInteger version = [defaults integerForKey:@"MPMigrationVersion"];
    XCTAssertEqual(version, 3,
                   @"Migration version should be updated to 3 after migration");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

/**
 * Test that user can re-enable intra-emphasis after migration and it persists.
 * Related to GitHub issue #293.
 */
- (void)testUserCanReEnableIntraEmphasisAfterMigration
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Simulate fully migrated user who then re-enabled the setting
    [defaults setInteger:3 forKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];  // User chose to enable

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // User's explicit choice should be preserved
    XCTAssertTrue(prefs.extensionIntraEmphasis,
                  @"Already migrated user's choice to enable intra-emphasis should be preserved");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

/**
 * Test that migration only applies once and doesn't reapply on subsequent launches.
 * Related to GitHub issue #293.
 */
- (void)testMigrationOnlyAppliesOnce
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Set up pre-migration state (version 2)
    [defaults setInteger:2 forKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];

    // First launch - migration applies
    MPPreferences *prefs1 = [[MPPreferences alloc] init];
    XCTAssertFalse(prefs1.extensionIntraEmphasis, @"First launch should migrate");

    // User re-enables
    prefs1.extensionIntraEmphasis = YES;
    [prefs1 synchronize];

    // Second launch - migration should NOT reapply
    MPPreferences *prefs2 = [[MPPreferences alloc] init];
    XCTAssertTrue(prefs2.extensionIntraEmphasis,
                  @"Second launch should not reapply migration - user choice preserved");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

/**
 * Test that migration preserves already disabled intra-emphasis.
 * Related to GitHub issue #293.
 */
- (void)testMigrationPreservesAlreadyDisabledIntraEmphasis
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // User at v2 who already manually disabled intra-emphasis
    [defaults setInteger:2 forKey:@"MPMigrationVersion"];
    [defaults setBool:NO forKey:@"extensionIntraEmphasis"];  // Already disabled

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Migration should keep it disabled (not re-enable)
    XCTAssertFalse(prefs.extensionIntraEmphasis,
                   @"Migration should not re-enable already disabled intra-emphasis");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

/**
 * Test that future version numbers are handled gracefully (skip migrations).
 * Related to GitHub issue #293.
 */
- (void)testFutureVersionSkipsMigrations
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Save original values
    NSNumber *originalVersion = [defaults objectForKey:@"MPMigrationVersion"];
    NSNumber *originalIntraEmphasis = [defaults objectForKey:@"extensionIntraEmphasis"];

    // Simulate higher version (e.g., downgrade scenario)
    [defaults setInteger:99 forKey:@"MPMigrationVersion"];
    [defaults setBool:YES forKey:@"extensionIntraEmphasis"];

    // Trigger initialization
    MPPreferences *prefs = [[MPPreferences alloc] init];

    // Should NOT apply any migrations
    XCTAssertTrue(prefs.extensionIntraEmphasis,
                  @"Future version should not apply any migrations");

    // Restore original values
    if (originalVersion)
        [defaults setObject:originalVersion forKey:@"MPMigrationVersion"];
    else
        [defaults removeObjectForKey:@"MPMigrationVersion"];

    if (originalIntraEmphasis)
        [defaults setObject:originalIntraEmphasis forKey:@"extensionIntraEmphasis"];
    else
        [defaults removeObjectForKey:@"extensionIntraEmphasis"];
}

@end
