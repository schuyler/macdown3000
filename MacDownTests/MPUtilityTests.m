//
//  MPUtilityTests.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 23/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPUtilities.h"

@interface MPUtilityTests : XCTestCase
@property (strong) NSString *tempDir;
@end


@implementation MPUtilityTests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Existing Tests

- (void)testGetObjectFromJavaScript
{
    NSString *code = (
        @"var obj = { foo: 'bar', baz: 42 };"
        @"var arr = [0, null, {}];"
    );
    id obj = MPGetObjectFromJavaScript(code, @"obj");
    id objx = @{@"foo": @"bar", @"baz": @42};
    XCTAssertEqualObjects(obj, objx, @"JavaScript object to NSDictionary");

    id arr = MPGetObjectFromJavaScript(code, @"arr");
    id arrx = @[@0, [NSNull null], @{}];
    XCTAssertEqualObjects(arr, arrx, @"JavaScript object to NSDictionary");
}

#pragma mark - MPHighlightingThemeURLForNameInPaths Tests

- (void)testHighlightingThemeURLReturnsUserThemeWhenPresent
{
    // Create a user theme directory with a custom theme file
    NSString *userThemeDir = [self.tempDir
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *themeFile = [userThemeDir
        stringByAppendingPathComponent:@"prism-custom.css"];
    [@"/* custom theme */" writeToFile:themeFile
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:nil];

    NSURL *result = MPHighlightingThemeURLForNameInPaths(@"Custom",
                                                         self.tempDir,
                                                         nil);
    XCTAssertNotNil(result, @"Should find user-provided theme");
    XCTAssertTrue([result.path hasSuffix:@"prism-custom.css"],
                  @"Should return user theme path, got: %@", result.path);
}

- (void)testHighlightingThemeURLReturnsBundleURLWhenNoUserTheme
{
    // Create a fake bundle theme directory
    NSString *bundleThemeDir = [self.tempDir
        stringByAppendingPathComponent:@"bundle/Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *bundleThemeFile = [bundleThemeDir
        stringByAppendingPathComponent:@"prism-tomorrow.css"];
    [@"/* bundle tomorrow */" writeToFile:bundleThemeFile
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:nil];

    NSString *emptyUserDir = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    [[NSFileManager defaultManager] createDirectoryAtPath:emptyUserDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];

    NSURL *result = MPHighlightingThemeURLForNameInPaths(@"Tomorrow",
                                                         emptyUserDir,
                                                         bundleRoot);
    XCTAssertNotNil(result, @"Should fall back to bundle theme");
    XCTAssertTrue([result.path hasSuffix:@"prism-tomorrow.css"],
                  @"Should return bundle theme path, got: %@", result.path);
}

- (void)testHighlightingThemeURLUserOverridesBundleTheme
{
    // Both user and bundle have the same theme name; user should win
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* bundle version */" writeToFile:[bundleThemeDir
        stringByAppendingPathComponent:@"prism-okaidia.css"]
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:nil];

    NSString *userRoot = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    NSString *userThemeDir = [userRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* user version */" writeToFile:[userThemeDir
        stringByAppendingPathComponent:@"prism-okaidia.css"]
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:nil];

    NSURL *result = MPHighlightingThemeURLForNameInPaths(@"Okaidia",
                                                         userRoot,
                                                         bundleRoot);
    XCTAssertNotNil(result, @"Should find theme");
    XCTAssertTrue([result.path containsString:@"user/"],
                  @"User theme should override bundle, got: %@", result.path);
}

- (void)testHighlightingThemeURLFallsBackToDefaultTheme
{
    // Non-existent theme name; should fall back to prism.css (default)
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* default */" writeToFile:[bundleThemeDir
        stringByAppendingPathComponent:@"prism.css"]
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:nil];

    NSString *userRoot = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userRoot
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSURL *result = MPHighlightingThemeURLForNameInPaths(@"Nonexistent",
                                                         userRoot,
                                                         bundleRoot);
    XCTAssertNotNil(result, @"Should fall back to default theme");
    XCTAssertTrue([result.path hasSuffix:@"prism.css"],
                  @"Should return default prism.css, got: %@", result.path);
}

- (void)testHighlightingThemeURLHandlesCSSExtensionInName
{
    // Name already includes .css extension — should still work
    NSString *userRoot = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    NSString *userThemeDir = [userRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* theme */" writeToFile:[userThemeDir
        stringByAppendingPathComponent:@"prism-solarized.css"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil];

    NSURL *result = MPHighlightingThemeURLForNameInPaths(@"solarized.css",
                                                         userRoot,
                                                         nil);
    XCTAssertNotNil(result, @"Should handle .css in name");
    XCTAssertTrue([result.path hasSuffix:@"prism-solarized.css"],
                  @"Should strip extra .css, got: %@", result.path);
}

#pragma mark - MPListHighlightingThemes Tests

- (void)testListHighlightingThemesReturnsBundledThemes
{
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    // Create bundled theme files
    for (NSString *name in @[@"prism.css", @"prism-okaidia.css",
                             @"prism-tomorrow.css"])
    {
        [@"/* theme */" writeToFile:[bundleThemeDir
            stringByAppendingPathComponent:name]
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:nil];
    }

    NSString *emptyUserDir = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    [[NSFileManager defaultManager] createDirectoryAtPath:emptyUserDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSArray *themes = MPListHighlightingThemesInPaths(emptyUserDir,
                                                       bundleRoot);
    XCTAssertTrue(themes.count >= 2,
                  @"Should include bundled themes, got %lu",
                  (unsigned long)themes.count);
    XCTAssertTrue([themes containsObject:@"Okaidia"],
                  @"Should include Okaidia");
    XCTAssertTrue([themes containsObject:@"Tomorrow"],
                  @"Should include Tomorrow");
    // prism.css (default) should NOT appear in the list — it's shown
    // separately as "(Default)"
    XCTAssertFalse([themes containsObject:@""],
                   @"Default theme should not produce empty name");
}

- (void)testListHighlightingThemesIncludesUserThemes
{
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* theme */" writeToFile:[bundleThemeDir
        stringByAppendingPathComponent:@"prism-okaidia.css"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil];

    NSString *userRoot = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    NSString *userThemeDir = [userRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* custom */" writeToFile:[userThemeDir
        stringByAppendingPathComponent:@"prism-mytheme.css"]
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];

    NSArray *themes = MPListHighlightingThemesInPaths(userRoot, bundleRoot);
    XCTAssertTrue([themes containsObject:@"Okaidia"],
                  @"Should include bundled theme");
    XCTAssertTrue([themes containsObject:@"Mytheme"],
                  @"Should include user theme");
}

- (void)testListHighlightingThemesDeduplicatesOnConflict
{
    // Same theme name in both user and bundle — should appear only once
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* bundle */" writeToFile:[bundleThemeDir
        stringByAppendingPathComponent:@"prism-okaidia.css"]
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];

    NSString *userRoot = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    NSString *userThemeDir = [userRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* user */" writeToFile:[userThemeDir
        stringByAppendingPathComponent:@"prism-okaidia.css"]
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:nil];

    NSArray *themes = MPListHighlightingThemesInPaths(userRoot, bundleRoot);
    NSUInteger count = 0;
    for (NSString *name in themes) {
        if ([name isEqualToString:@"Okaidia"])
            count++;
    }
    XCTAssertEqual(count, 1UL,
                   @"Theme name should appear only once, got %lu",
                   (unsigned long)count);
}

- (void)testListHighlightingThemesIgnoresNonCSSFiles
{
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* theme */" writeToFile:[bundleThemeDir
        stringByAppendingPathComponent:@"prism-okaidia.css"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil];
    [@"not a theme" writeToFile:[bundleThemeDir
        stringByAppendingPathComponent:@"README.md"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil];

    NSString *emptyUserDir = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    [[NSFileManager defaultManager] createDirectoryAtPath:emptyUserDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSArray *themes = MPListHighlightingThemesInPaths(emptyUserDir,
                                                       bundleRoot);
    XCTAssertEqual(themes.count, 1UL,
                   @"Should only include CSS files, got %lu",
                   (unsigned long)themes.count);
    XCTAssertTrue([themes containsObject:@"Okaidia"]);
}

- (void)testListHighlightingThemesReturnsEmptyWhenNoThemes
{
    NSString *emptyUserDir = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    NSString *emptyBundleDir = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    [[NSFileManager defaultManager] createDirectoryAtPath:emptyUserDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:emptyBundleDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSArray *themes = MPListHighlightingThemesInPaths(emptyUserDir,
                                                       emptyBundleDir);
    XCTAssertNotNil(themes, @"Should return non-nil array");
    XCTAssertEqual(themes.count, 0UL,
                   @"Should be empty when no themes exist");
}

- (void)testListHighlightingThemesSortedAlphabetically
{
    NSString *bundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"bundle"];
    NSString *bundleThemeDir = [bundleRoot
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    for (NSString *name in @[@"prism-tomorrow.css", @"prism-atelierdune.css",
                             @"prism-okaidia.css"])
    {
        [@"/* theme */" writeToFile:[bundleThemeDir
            stringByAppendingPathComponent:name]
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:nil];
    }

    NSString *emptyUserDir = [self.tempDir
        stringByAppendingPathComponent:@"user"];
    [[NSFileManager defaultManager] createDirectoryAtPath:emptyUserDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSArray *themes = MPListHighlightingThemesInPaths(emptyUserDir,
                                                       bundleRoot);
    NSArray *sorted = [themes sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(themes, sorted,
                          @"Themes should be sorted alphabetically");
}

@end
