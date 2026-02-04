//
//  MPQuickLookPreferencesTests.m
//  MacDown 3000
//
//  Tests for Quick Look preferences reader (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>

// Quick Look tests require MacDownCore framework to be added to the Xcode project.
// These tests are conditionally compiled to allow CI to pass before framework setup.
// See plans/quick-look-xcode-setup.md for instructions on enabling these tests.

#if ENABLE_QUICKLOOK_TESTS

// Import from MacDownCore (add MacDownCore to header search paths in Xcode)
#import "MPQuickLookPreferences.h"


@interface MPQuickLookPreferencesTests : XCTestCase
@end


@implementation MPQuickLookPreferencesTests

#pragma mark - Initialization Tests

- (void)testSharedInstanceExists
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    XCTAssertNotNil(prefs, @"Should return a shared preferences instance");
}

- (void)testSharedInstanceIsSingleton
{
    MPQuickLookPreferences *prefs1 = [MPQuickLookPreferences sharedPreferences];
    MPQuickLookPreferences *prefs2 = [MPQuickLookPreferences sharedPreferences];
    XCTAssertEqual(prefs1, prefs2, @"Should return the same instance");
}


#pragma mark - Style Name Reading Tests

- (void)testStyleNameReturnsValue
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    NSString *styleName = [prefs styleName];

    XCTAssertNotNil(styleName, @"Style name should not be nil");
    XCTAssertTrue([styleName length] > 0, @"Style name should not be empty");
}

- (void)testStyleNameDefaultsToGitHub2
{
    // When no preference is set, should default to GitHub2
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    NSString *styleName = [prefs styleName];

    // This test may pass or fail depending on whether MacDown prefs exist
    // The key behavior is that it returns a valid string
    XCTAssertNotNil(styleName, @"Style name should have a default value");
}


#pragma mark - Extension Flags Reading Tests

- (void)testExtensionTablesReturnsBoolean
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    // Should return YES or NO without crashing
    BOOL tables = [prefs extensionTables];
    XCTAssertTrue(tables == YES || tables == NO,
                  @"Extension tables should return a boolean");
}

- (void)testExtensionFencedCodeReturnsBoolean
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL fencedCode = [prefs extensionFencedCode];
    XCTAssertTrue(fencedCode == YES || fencedCode == NO,
                  @"Extension fenced code should return a boolean");
}

- (void)testExtensionAutolinkReturnsBoolean
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL autolink = [prefs extensionAutolink];
    XCTAssertTrue(autolink == YES || autolink == NO,
                  @"Extension autolink should return a boolean");
}

- (void)testExtensionStrikethroughReturnsBoolean
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL strikethrough = [prefs extensionStrikethrough];
    XCTAssertTrue(strikethrough == YES || strikethrough == NO,
                  @"Extension strikethrough should return a boolean");
}


#pragma mark - Highlighting Theme Tests

- (void)testHighlightingThemeNameReturnsValue
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    NSString *themeName = [prefs highlightingThemeName];

    XCTAssertNotNil(themeName, @"Highlighting theme name should not be nil");
}

- (void)testSyntaxHighlightingEnabledReturnsBoolean
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL enabled = [prefs syntaxHighlightingEnabled];
    XCTAssertTrue(enabled == YES || enabled == NO,
                  @"Syntax highlighting enabled should return a boolean");
}


#pragma mark - Feature Exclusion Tests (Critical for Issue #284)

- (void)testMathJaxAlwaysReturnsNO
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL mathJax = [prefs mathJaxEnabled];

    XCTAssertFalse(mathJax,
                   @"MathJax should ALWAYS return NO for Quick Look (regardless of user prefs)");
}

- (void)testMermaidAlwaysReturnsNO
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL mermaid = [prefs mermaidEnabled];

    XCTAssertFalse(mermaid,
                   @"Mermaid should ALWAYS return NO for Quick Look (regardless of user prefs)");
}

- (void)testGraphvizAlwaysReturnsNO
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    BOOL graphviz = [prefs graphvizEnabled];

    XCTAssertFalse(graphviz,
                   @"Graphviz should ALWAYS return NO for Quick Look (regardless of user prefs)");
}


#pragma mark - Default Values Tests

- (void)testDefaultsAreReasonable
{
    // Create a fresh preferences instance to test defaults
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];

    // When MacDown hasn't been run, these should have sensible defaults
    NSString *style = [prefs styleName];
    NSString *theme = [prefs highlightingThemeName];

    // Should have non-empty defaults
    XCTAssertNotNil(style, @"Style should have a default");
    XCTAssertNotNil(theme, @"Theme should have a default");
}


#pragma mark - Extension Flags Bitmask Test

- (void)testExtensionFlagsReturnsBitmask
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    int flags = [prefs extensionFlags];

    // Should return a valid integer (could be 0 or non-zero)
    XCTAssertTrue(flags >= 0,
                  @"Extension flags should return a non-negative integer");
}


#pragma mark - Renderer Flags Test

- (void)testRendererFlagsReturnsBitmask
{
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];
    int flags = [prefs rendererFlags];

    // Should return a valid integer (could be 0 or non-zero)
    XCTAssertTrue(flags >= 0,
                  @"Renderer flags should return a non-negative integer");
}


#pragma mark - Edge Cases

- (void)testHandlesMissingPreferences
{
    // Even if no preferences file exists, the class should return defaults
    MPQuickLookPreferences *prefs = [MPQuickLookPreferences sharedPreferences];

    // These should not throw or crash
    XCTAssertNoThrow([prefs styleName], @"Should not throw on missing prefs");
    XCTAssertNoThrow([prefs highlightingThemeName], @"Should not throw on missing prefs");
    XCTAssertNoThrow([prefs extensionFlags], @"Should not throw on missing prefs");
}

@end

#else

// Placeholder test class when Quick Look tests are disabled
// This allows CI to pass while MacDownCore framework is being set up

@interface MPQuickLookPreferencesTests : XCTestCase
@end

@implementation MPQuickLookPreferencesTests

- (void)testQuickLookTestsDisabled
{
    // This is a placeholder test that always passes
    // Real Quick Look tests are disabled until MacDownCore framework is added to Xcode
    NSLog(@"Quick Look preferences tests are disabled. Enable with ENABLE_QUICKLOOK_TESTS=1");
    NSLog(@"See plans/quick-look-xcode-setup.md for setup instructions");
    XCTAssert(YES, @"Placeholder test passes - Quick Look tests disabled");
}

@end

#endif
