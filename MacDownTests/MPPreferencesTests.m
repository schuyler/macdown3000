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
@property BOOL oldSyntaxHighlighting;
@property BOOL oldMathJax;
@property NSString *oldStyleName;
@property NSString *oldHighlightingThemeName;
@end


@implementation MPPreferencesTests

- (void)setUp
{
    [super setUp];
    self.preferences = [MPPreferences sharedInstance];

    // Save original values for restoration
    self.oldFontInfo = [self.preferences.editorBaseFontInfo copy];
    self.oldSyntaxHighlighting = self.preferences.htmlSyntaxHighlighting;
    self.oldMathJax = self.preferences.htmlMathJax;
    self.oldStyleName = [self.preferences.htmlStyleName copy];
    self.oldHighlightingThemeName = [self.preferences.htmlHighlightingThemeName copy];
}

- (void)tearDown
{
    // Restore original values
    self.preferences.editorBaseFontInfo = self.oldFontInfo;
    self.preferences.htmlSyntaxHighlighting = self.oldSyntaxHighlighting;
    self.preferences.htmlMathJax = self.oldMathJax;
    self.preferences.htmlStyleName = self.oldStyleName;
    self.preferences.htmlHighlightingThemeName = self.oldHighlightingThemeName;
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
    // Toggle ON
    self.preferences.htmlSyntaxHighlighting = YES;
    XCTAssertTrue([self.preferences synchronize], @"Should sync");
    XCTAssertTrue(self.preferences.htmlSyntaxHighlighting, @"Should be ON");

    // Toggle OFF
    self.preferences.htmlSyntaxHighlighting = NO;
    XCTAssertTrue([self.preferences synchronize], @"Should sync");
    XCTAssertFalse(self.preferences.htmlSyntaxHighlighting, @"Should be OFF");
}

- (void)testMathJaxToggle
{
    self.preferences.htmlMathJax = YES;
    [self.preferences synchronize];
    XCTAssertTrue(self.preferences.htmlMathJax, @"MathJax should be ON");

    self.preferences.htmlMathJax = NO;
    [self.preferences synchronize];
    XCTAssertFalse(self.preferences.htmlMathJax, @"MathJax should be OFF");
}

- (void)testExtensionFlags
{
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
}


#pragma mark - String Preference Tests

- (void)testStyleNamePersistence
{
    NSString *testStyleName = @"GitHub2";
    self.preferences.htmlStyleName = testStyleName;
    [self.preferences synchronize];

    NSString *result = self.preferences.htmlStyleName;
    XCTAssertEqualObjects(result, testStyleName, @"Style name should persist");
}

- (void)testHighlightingThemeNamePersistence
{
    NSString *testTheme = @"tomorrow";
    self.preferences.htmlHighlightingThemeName = testTheme;
    [self.preferences synchronize];

    NSString *result = self.preferences.htmlHighlightingThemeName;
    XCTAssertEqualObjects(result, testTheme, @"Theme name should persist");
}


#pragma mark - Singleton Tests

- (void)testSharedInstanceReturnsSameObject
{
    MPPreferences *instance1 = [MPPreferences sharedInstance];
    MPPreferences *instance2 = [MPPreferences sharedInstance];

    XCTAssertTrue(instance1 == instance2, @"Should return same singleton instance");
}


#pragma mark - Edge Cases

- (void)testEmptyStringPreference
{
    self.preferences.htmlStyleName = @"";
    [self.preferences synchronize];

    NSString *result = self.preferences.htmlStyleName;
    XCTAssertEqualObjects(result, @"", @"Empty string should persist");
}

- (void)testNilFontInfoFallback
{
    // Setting font info to nil should not crash
    NSDictionary *original = self.preferences.editorBaseFontInfo;

    self.preferences.editorBaseFontInfo = nil;
    [self.preferences synchronize];

    // When font info is nil, editorBaseFont should return a default
    NSFont *font = self.preferences.editorBaseFont;
    XCTAssertNotNil(font, @"Should return default font when info is nil");

    // Restore
    self.preferences.editorBaseFontInfo = original;
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
    CGFloat testInset = 25.0;
    self.preferences.editorHorizontalInset = testInset;
    [self.preferences synchronize];

    CGFloat result = self.preferences.editorHorizontalInset;
    XCTAssertEqualWithAccuracy(result, testInset, 0.01, @"Inset should persist");
}

- (void)testEditorMaximumWidth
{
    CGFloat testWidth = 800.0;
    self.preferences.editorMaximumWidth = testWidth;
    [self.preferences synchronize];

    CGFloat result = self.preferences.editorMaximumWidth;
    XCTAssertEqualWithAccuracy(result, testWidth, 0.01, @"Width should persist");
}

- (void)testEditorLineSpacing
{
    CGFloat testSpacing = 1.5;
    self.preferences.editorLineSpacing = testSpacing;
    [self.preferences synchronize];

    CGFloat result = self.preferences.editorLineSpacing;
    XCTAssertEqualWithAccuracy(result, testSpacing, 0.01, @"Line spacing should persist");
}

@end
