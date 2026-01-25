//
//  MPEditorViewSubstitutionTests.m
//  MacDown 3000
//
//  Tests for Issue #263: NSTextView substitution property getter overrides.
//  Verifies that MPEditorView getters return values from NSUserDefaults
//  rather than the internal ivar, preventing NSTextView from ignoring
//  or resetting our preferences.
//
//  TDD: These tests are designed to FAIL until the getter overrides
//  are implemented in MPEditorView.
//

#import <XCTest/XCTest.h>
#import "MPEditorView.h"

#pragma mark - Test Constants

/**
 * Preference key prefix for editor substitution settings.
 * The pattern is: "editor" + capitalized property name.
 * Example: "automaticDashSubstitutionEnabled" -> "editorAutomaticDashSubstitutionEnabled"
 */
static NSString * const kEditorPreferencePrefix = @"editor";

/**
 * Test value used to distinguish preference-sourced values from defaults.
 * For boolean properties, we test with YES since the defaults are NO.
 */
static const BOOL kTestBoolValue = YES;

/**
 * Test value for enabledTextCheckingTypes.
 * Uses a distinctive bitmask different from NSTextCheckingAllTypes.
 */
static const NSTextCheckingTypes kTestCheckingTypes = (NSTextCheckingTypeSpelling | NSTextCheckingTypeGrammar);

#pragma mark - Test Case

@interface MPEditorViewSubstitutionTests : XCTestCase
@property (strong, nonatomic) MPEditorView *editorView;
@property (strong, nonatomic) NSMutableDictionary *savedPreferences;
@end

@implementation MPEditorViewSubstitutionTests

#pragma mark - Setup and Teardown

- (void)setUp
{
    [super setUp];

    // Create editor view instance for testing
    self.editorView = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];

    // Save current preference values to restore after tests
    self.savedPreferences = [NSMutableDictionary dictionary];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSArray *preferenceKeys = @[
        @"editorAutomaticDashSubstitutionEnabled",
        @"editorAutomaticDataDetectionEnabled",
        @"editorAutomaticQuoteSubstitutionEnabled",
        @"editorAutomaticSpellingCorrectionEnabled",
        @"editorAutomaticTextReplacementEnabled",
        @"editorContinuousSpellCheckingEnabled",
        @"editorGrammarCheckingEnabled",
        @"editorSmartInsertDeleteEnabled",
        @"editorEnabledTextCheckingTypes"
    ];

    for (NSString *key in preferenceKeys)
    {
        id value = [defaults objectForKey:key];
        if (value)
            self.savedPreferences[key] = value;
    }
}

- (void)tearDown
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Restore saved preferences
    for (NSString *key in self.savedPreferences)
    {
        [defaults setObject:self.savedPreferences[key] forKey:key];
    }

    // Remove any test keys that weren't originally present
    NSArray *preferenceKeys = @[
        @"editorAutomaticDashSubstitutionEnabled",
        @"editorAutomaticDataDetectionEnabled",
        @"editorAutomaticQuoteSubstitutionEnabled",
        @"editorAutomaticSpellingCorrectionEnabled",
        @"editorAutomaticTextReplacementEnabled",
        @"editorContinuousSpellCheckingEnabled",
        @"editorGrammarCheckingEnabled",
        @"editorSmartInsertDeleteEnabled",
        @"editorEnabledTextCheckingTypes"
    ];

    for (NSString *key in preferenceKeys)
    {
        if (!self.savedPreferences[key])
            [defaults removeObjectForKey:key];
    }

    [defaults synchronize];

    self.editorView = nil;
    self.savedPreferences = nil;

    [super tearDown];
}

#pragma mark - Helper Methods

/**
 * Sets a boolean preference and synchronizes NSUserDefaults.
 */
- (void)setBoolPreference:(BOOL)value forKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:key];
    [defaults synchronize];
}

/**
 * Sets an integer preference and synchronizes NSUserDefaults.
 */
- (void)setIntegerPreference:(NSInteger)value forKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:value forKey:key];
    [defaults synchronize];
}

/**
 * Removes a preference key to test default behavior.
 */
- (void)removePreferenceForKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:key];
    [defaults synchronize];
}

#pragma mark - Automatic Dash Substitution Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 * Verifies the getter reads from NSUserDefaults, not the ivar.
 */
- (void)testAutomaticDashSubstitution_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorAutomaticDashSubstitutionEnabled"];

    BOOL result = self.editorView.isAutomaticDashSubstitutionEnabled;

    XCTAssertTrue(result,
        @"isAutomaticDashSubstitutionEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testAutomaticDashSubstitution_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorAutomaticDashSubstitutionEnabled"];

    BOOL result = self.editorView.isAutomaticDashSubstitutionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticDashSubstitutionEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testAutomaticDashSubstitution_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorAutomaticDashSubstitutionEnabled"];

    BOOL result = self.editorView.isAutomaticDashSubstitutionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticDashSubstitutionEnabled should return NO when preference is not set");
}

/**
 * Test: Getter ignores ivar value and uses preference.
 * Sets the ivar via the setter, then verifies getter returns preference value.
 */
- (void)testAutomaticDashSubstitution_IgnoresIvar_ReturnsPreference
{
    // Set preference to NO
    [self setBoolPreference:NO forKey:@"editorAutomaticDashSubstitutionEnabled"];

    // Set ivar to YES via superclass setter (bypasses our override)
    [self.editorView setAutomaticDashSubstitutionEnabled:YES];

    // Getter should return preference value (NO), not ivar value (YES)
    BOOL result = self.editorView.isAutomaticDashSubstitutionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticDashSubstitutionEnabled should return preference value, not ivar");
}

#pragma mark - Automatic Data Detection Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 */
- (void)testAutomaticDataDetection_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorAutomaticDataDetectionEnabled"];

    BOOL result = self.editorView.isAutomaticDataDetectionEnabled;

    XCTAssertTrue(result,
        @"isAutomaticDataDetectionEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testAutomaticDataDetection_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorAutomaticDataDetectionEnabled"];

    BOOL result = self.editorView.isAutomaticDataDetectionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticDataDetectionEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testAutomaticDataDetection_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorAutomaticDataDetectionEnabled"];

    BOOL result = self.editorView.isAutomaticDataDetectionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticDataDetectionEnabled should return NO when preference is not set");
}

#pragma mark - Automatic Quote Substitution Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 */
- (void)testAutomaticQuoteSubstitution_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorAutomaticQuoteSubstitutionEnabled"];

    BOOL result = self.editorView.isAutomaticQuoteSubstitutionEnabled;

    XCTAssertTrue(result,
        @"isAutomaticQuoteSubstitutionEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testAutomaticQuoteSubstitution_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorAutomaticQuoteSubstitutionEnabled"];

    BOOL result = self.editorView.isAutomaticQuoteSubstitutionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticQuoteSubstitutionEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testAutomaticQuoteSubstitution_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorAutomaticQuoteSubstitutionEnabled"];

    BOOL result = self.editorView.isAutomaticQuoteSubstitutionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticQuoteSubstitutionEnabled should return NO when preference is not set");
}

#pragma mark - Automatic Spelling Correction Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 */
- (void)testAutomaticSpellingCorrection_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorAutomaticSpellingCorrectionEnabled"];

    BOOL result = self.editorView.isAutomaticSpellingCorrectionEnabled;

    XCTAssertTrue(result,
        @"isAutomaticSpellingCorrectionEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testAutomaticSpellingCorrection_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorAutomaticSpellingCorrectionEnabled"];

    BOOL result = self.editorView.isAutomaticSpellingCorrectionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticSpellingCorrectionEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testAutomaticSpellingCorrection_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorAutomaticSpellingCorrectionEnabled"];

    BOOL result = self.editorView.isAutomaticSpellingCorrectionEnabled;

    XCTAssertFalse(result,
        @"isAutomaticSpellingCorrectionEnabled should return NO when preference is not set");
}

#pragma mark - Automatic Text Replacement Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 */
- (void)testAutomaticTextReplacement_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorAutomaticTextReplacementEnabled"];

    BOOL result = self.editorView.isAutomaticTextReplacementEnabled;

    XCTAssertTrue(result,
        @"isAutomaticTextReplacementEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testAutomaticTextReplacement_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorAutomaticTextReplacementEnabled"];

    BOOL result = self.editorView.isAutomaticTextReplacementEnabled;

    XCTAssertFalse(result,
        @"isAutomaticTextReplacementEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testAutomaticTextReplacement_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorAutomaticTextReplacementEnabled"];

    BOOL result = self.editorView.isAutomaticTextReplacementEnabled;

    XCTAssertFalse(result,
        @"isAutomaticTextReplacementEnabled should return NO when preference is not set");
}

#pragma mark - Continuous Spell Checking Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 */
- (void)testContinuousSpellChecking_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorContinuousSpellCheckingEnabled"];

    BOOL result = self.editorView.isContinuousSpellCheckingEnabled;

    XCTAssertTrue(result,
        @"isContinuousSpellCheckingEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testContinuousSpellChecking_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorContinuousSpellCheckingEnabled"];

    BOOL result = self.editorView.isContinuousSpellCheckingEnabled;

    XCTAssertFalse(result,
        @"isContinuousSpellCheckingEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testContinuousSpellChecking_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorContinuousSpellCheckingEnabled"];

    BOOL result = self.editorView.isContinuousSpellCheckingEnabled;

    XCTAssertFalse(result,
        @"isContinuousSpellCheckingEnabled should return NO when preference is not set");
}

#pragma mark - Grammar Checking Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 */
- (void)testGrammarChecking_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorGrammarCheckingEnabled"];

    BOOL result = self.editorView.isGrammarCheckingEnabled;

    XCTAssertTrue(result,
        @"isGrammarCheckingEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testGrammarChecking_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorGrammarCheckingEnabled"];

    BOOL result = self.editorView.isGrammarCheckingEnabled;

    XCTAssertFalse(result,
        @"isGrammarCheckingEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testGrammarChecking_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorGrammarCheckingEnabled"];

    BOOL result = self.editorView.isGrammarCheckingEnabled;

    XCTAssertFalse(result,
        @"isGrammarCheckingEnabled should return NO when preference is not set");
}

#pragma mark - Smart Insert Delete Tests

/**
 * Test: Getter returns YES when preference is set to YES.
 * Note: This property uses "smartInsertDeleteEnabled" not "isSmartInsertDeleteEnabled".
 */
- (void)testSmartInsertDelete_WhenPreferenceIsYES_ReturnsYES
{
    [self setBoolPreference:YES forKey:@"editorSmartInsertDeleteEnabled"];

    BOOL result = self.editorView.smartInsertDeleteEnabled;

    XCTAssertTrue(result,
        @"smartInsertDeleteEnabled should return YES when preference is YES");
}

/**
 * Test: Getter returns NO when preference is set to NO.
 */
- (void)testSmartInsertDelete_WhenPreferenceIsNO_ReturnsNO
{
    [self setBoolPreference:NO forKey:@"editorSmartInsertDeleteEnabled"];

    BOOL result = self.editorView.smartInsertDeleteEnabled;

    XCTAssertFalse(result,
        @"smartInsertDeleteEnabled should return NO when preference is NO");
}

/**
 * Test: Getter returns NO (default) when preference key doesn't exist.
 */
- (void)testSmartInsertDelete_WhenPreferenceNotSet_ReturnsDefaultNO
{
    [self removePreferenceForKey:@"editorSmartInsertDeleteEnabled"];

    BOOL result = self.editorView.smartInsertDeleteEnabled;

    XCTAssertFalse(result,
        @"smartInsertDeleteEnabled should return NO when preference is not set");
}

#pragma mark - Enabled Text Checking Types Tests

/**
 * Test: Getter returns stored value when preference is set.
 */
- (void)testEnabledTextCheckingTypes_WhenPreferenceIsSet_ReturnsValue
{
    [self setIntegerPreference:kTestCheckingTypes forKey:@"editorEnabledTextCheckingTypes"];

    NSTextCheckingTypes result = self.editorView.enabledTextCheckingTypes;

    XCTAssertEqual(result, kTestCheckingTypes,
        @"enabledTextCheckingTypes should return stored preference value");
}

/**
 * Test: Getter returns NSTextCheckingAllTypes when preference is not set.
 */
- (void)testEnabledTextCheckingTypes_WhenPreferenceNotSet_ReturnsAllTypes
{
    [self removePreferenceForKey:@"editorEnabledTextCheckingTypes"];

    NSTextCheckingTypes result = self.editorView.enabledTextCheckingTypes;

    XCTAssertEqual(result, NSTextCheckingAllTypes,
        @"enabledTextCheckingTypes should return NSTextCheckingAllTypes when preference not set");
}

/**
 * Test: Getter returns zero when preference is explicitly set to zero.
 */
- (void)testEnabledTextCheckingTypes_WhenPreferenceIsZero_ReturnsZero
{
    [self setIntegerPreference:0 forKey:@"editorEnabledTextCheckingTypes"];

    NSTextCheckingTypes result = self.editorView.enabledTextCheckingTypes;

    XCTAssertEqual(result, (NSTextCheckingTypes)0,
        @"enabledTextCheckingTypes should return 0 when preference is explicitly set to 0");
}

/**
 * Test: Getter ignores ivar value and uses preference.
 */
- (void)testEnabledTextCheckingTypes_IgnoresIvar_ReturnsPreference
{
    // Set preference to a specific value
    [self setIntegerPreference:kTestCheckingTypes forKey:@"editorEnabledTextCheckingTypes"];

    // Set ivar to a different value via superclass setter
    [self.editorView setEnabledTextCheckingTypes:NSTextCheckingAllTypes];

    // Getter should return preference value, not ivar value
    NSTextCheckingTypes result = self.editorView.enabledTextCheckingTypes;

    XCTAssertEqual(result, kTestCheckingTypes,
        @"enabledTextCheckingTypes should return preference value, not ivar");
}

#pragma mark - Preference Change Response Tests

/**
 * Test: Getter reflects preference changes dynamically.
 * Verifies the getter always reads from NSUserDefaults, not a cached value.
 */
- (void)testAutomaticDashSubstitution_ReflectsPreferenceChanges
{
    // Start with NO
    [self setBoolPreference:NO forKey:@"editorAutomaticDashSubstitutionEnabled"];
    XCTAssertFalse(self.editorView.isAutomaticDashSubstitutionEnabled,
        @"Should initially return NO");

    // Change to YES
    [self setBoolPreference:YES forKey:@"editorAutomaticDashSubstitutionEnabled"];
    XCTAssertTrue(self.editorView.isAutomaticDashSubstitutionEnabled,
        @"Should return YES after preference changes to YES");

    // Change back to NO
    [self setBoolPreference:NO forKey:@"editorAutomaticDashSubstitutionEnabled"];
    XCTAssertFalse(self.editorView.isAutomaticDashSubstitutionEnabled,
        @"Should return NO after preference changes back to NO");
}

@end
