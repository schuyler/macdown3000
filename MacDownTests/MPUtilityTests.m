//
//  MPUtilityTests.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 23/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPUtilities.h"
#import "MPEditorView.h"
#import "pmh_styleparser.h"
#import "YAMLSerialization.h"
#import "NSTextView+Autocomplete.h"
#import "NSDocumentController+Document.h"
#import "FileURLInlining.h"
#import "NSString+Lookup.h"
#import "NSPasteboard+Types.h"
#import "MPRendererTestHelpers.h"
#import <hoedown/document.h>
#import "../MacDownCore/MPMarkdownPreprocessor.h"

@interface MPAuditOutputStream : NSOutputStream
@property (strong) NSOutputStream *backingStream;
@property BOOL didClose;
@end
@implementation MPAuditOutputStream
- (void)open { [self.backingStream open]; }
- (void)close { self.didClose = YES; [self.backingStream close]; }
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)length {
    return [self.backingStream write:buffer maxLength:length];
}
@end

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

- (void)testHighlightingThemeURLPreservesUserThemeFilenameCase
{
    NSString *userThemeDir = [self.tempDir
        stringByAppendingPathComponent:@"Prism/themes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userThemeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@"/* custom theme */" writeToFile:[userThemeDir
        stringByAppendingPathComponent:@"prism-Embark6.css"]
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:nil];

    NSURL *result = MPHighlightingThemeURLForNameInPaths(@"Embark6",
                                                         self.tempDir,
                                                         nil);
    XCTAssertNotNil(result, @"Should find mixed-case user theme");
    XCTAssertEqualObjects(result.lastPathComponent, @"prism-Embark6.css",
                          @"Should return the actual theme filename");
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

#pragma mark - MPStylePathForNameInPaths Tests

- (void)testStylePathForNameResolvesUserBundleAndCSSExtension
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *userDir = [self.tempDir stringByAppendingPathComponent:@"user/Styles"];
    NSString *bundleDir = [self.tempDir stringByAppendingPathComponent:@"bundle/Styles"];
    [fm createDirectoryAtPath:userDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:bundleDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *userRoot = [self.tempDir stringByAppendingPathComponent:@"user"];
    NSString *bundleRoot = [self.tempDir stringByAppendingPathComponent:@"bundle"];

    // User style shadows a same-named bundle style.
    NSString *userShared = [userDir stringByAppendingPathComponent:@"GitHub.css"];
    NSString *bundleShared = [bundleDir stringByAppendingPathComponent:@"GitHub.css"];
    [@"/* user */" writeToFile:userShared atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"/* bundle */" writeToFile:bundleShared atomically:YES encoding:NSUTF8StringEncoding error:nil];
    XCTAssertEqualObjects(MPStylePathForNameInPaths(@"GitHub", userRoot, bundleRoot),
                          userShared, @"User style should shadow same-named bundle style");

    // Bundle style is used as a fallback when absent from the user root.
    NSString *bundleOnly = [bundleDir stringByAppendingPathComponent:@"BundleOnly.css"];
    [@"/* bundle only */" writeToFile:bundleOnly atomically:YES encoding:NSUTF8StringEncoding error:nil];
    XCTAssertEqualObjects(MPStylePathForNameInPaths(@"BundleOnly", userRoot, bundleRoot),
                          bundleOnly, @"Should fall back to bundle when absent from user root");

    // A name without an extension gets ".css" appended.
    NSString *result = MPStylePathForNameInPaths(@"GitHub", userRoot, bundleRoot);
    XCTAssertTrue([result hasSuffix:@".css"],
                  @"Should append the .css extension, got: %@", result);
}

- (void)testStylePathForNameHandlesNilAndMissingNames
{
    NSString *userRoot = [self.tempDir stringByAppendingPathComponent:@"user"];
    NSString *bundleRoot = [self.tempDir stringByAppendingPathComponent:@"bundle"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userRoot
        withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleRoot
        withIntermediateDirectories:YES attributes:nil error:nil];

    XCTAssertNil(MPStylePathForNameInPaths(nil, userRoot, bundleRoot),
                @"A nil name should produce a nil result");

    NSString *result = MPStylePathForNameInPaths(@"Nonexistent", userRoot, bundleRoot);
    NSString *expected = [NSString pathWithComponents:@[
        userRoot, kMPStylesDirectoryName, @"Nonexistent.css"]];
    XCTAssertEqualObjects(result, expected,
                          @"Should fall through to the (nonexistent) user path "
                          @"when absent from both roots");
}

#pragma mark - MPListStylesheetsInPaths Tests

- (void)testListStylesheetsUnionsDedupsAndFiltersByExtension
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundleDir = [self.tempDir stringByAppendingPathComponent:@"bundle/Styles"];
    NSString *userDir = [self.tempDir stringByAppendingPathComponent:@"user/Styles"];
    [fm createDirectoryAtPath:bundleDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:userDir withIntermediateDirectories:YES attributes:nil error:nil];

    // GitHub.css in both roots (dedup), Solarized.css only in bundle
    // (extension stripped), MyStyle.css only in user (union), and a
    // non-.css file that must be ignored.
    for (NSString *name in @[@"GitHub.css", @"Solarized.css"])
        [@"/* bundle */" writeToFile:[bundleDir stringByAppendingPathComponent:name]
                           atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"not a stylesheet" writeToFile:[bundleDir stringByAppendingPathComponent:@"README.md"]
                           atomically:YES encoding:NSUTF8StringEncoding error:nil];
    for (NSString *name in @[@"GitHub.css", @"MyStyle.css"])
        [@"/* user */" writeToFile:[userDir stringByAppendingPathComponent:name]
                         atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSString *userRoot = [self.tempDir stringByAppendingPathComponent:@"user"];
    NSString *bundleRoot = [self.tempDir stringByAppendingPathComponent:@"bundle"];

    NSArray *result = MPListStylesheetsInPaths(userRoot, bundleRoot);
    XCTAssertEqualObjects(result, (@[@"GitHub", @"MyStyle", @"Solarized"]),
        @"Should union distinct names, dedup names present in both roots, "
        @"strip .css, and ignore non-.css files, got: %@", result);
}

- (void)testListStylesheetsSortsAndTreatsEmptyOrNilInputsAsEmpty
{
    NSString *bundleDir = [self.tempDir stringByAppendingPathComponent:@"bundle/Styles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *name in @[@"Zebra.css", @"Apple.css", @"Mango10.css", @"Mango2.css"])
        [@"/* theme */" writeToFile:[bundleDir stringByAppendingPathComponent:name]
                         atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *bundleRoot = [self.tempDir stringByAppendingPathComponent:@"bundle"];

    NSArray *result = MPListStylesheetsInPaths(nil, bundleRoot);
    NSArray *expected = [result sortedArrayUsingComparator:
        ^NSComparisonResult(NSString *a, NSString *b) {
            return [a localizedStandardCompare:b];
        }];
    XCTAssertEqualObjects(result, expected,
                          @"Result should be sorted via localizedStandardCompare: "
                          @"(e.g. Mango2 before Mango10)");

    XCTAssertEqualObjects(MPListStylesheetsInPaths(nil, nil), @[],
                          @"Should return an empty array for nil roots");
}

#pragma mark - MPContentHashOfFileAtPath Tests

- (void)testContentHashOfFileAtPath
{
    // Expected value computed via:
    //   printf 'test\n' | shasum -a 256
    // => f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2
    NSString *knownFile = [self.tempDir stringByAppendingPathComponent:@"known.txt"];
    [@"test\n" writeToFile:knownFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *expectedHash =
        @"f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2";
    XCTAssertEqualObjects(MPContentHashOfFileAtPath(knownFile), expectedHash,
                          @"Hash of known content should match the precomputed SHA-256");

    NSString *missingFile = [self.tempDir stringByAppendingPathComponent:@"does-not-exist.css"];
    XCTAssertNil(MPContentHashOfFileAtPath(missingFile),
                @"Hashing a nonexistent path should return nil");
}

#pragma mark - MPPruneStockStylesheetsInDirectory Tests

- (void)testPruneStockStylesheetsDeletesFileMatchingNameAndHash
{
    NSString *stylesDir = [self.tempDir stringByAppendingPathComponent:@"Styles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:stylesDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *stockFile = [stylesDir stringByAppendingPathComponent:@"Stock.css"];
    [@"/* stock content */" writeToFile:stockFile atomically:YES
                              encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *hashesByName = @{
        @"Stock.css": [NSSet setWithObject:MPContentHashOfFileAtPath(stockFile)],
    };

    NSUInteger deleted = MPPruneStockStylesheetsInDirectory(stylesDir, hashesByName);
    XCTAssertEqual(deleted, 1UL, @"Should report one deleted stylesheet");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:stockFile],
                   @"Matching stock file should be deleted");
}

- (void)testPruneStockStylesheetsKeepsFileWhenContentDoesNotMatch
{
    NSString *stylesDir = [self.tempDir stringByAppendingPathComponent:@"Styles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:stylesDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *customFile = [stylesDir stringByAppendingPathComponent:@"Custom.css"];
    [@"/* custom, not stock */" writeToFile:customFile atomically:YES
                                    encoding:NSUTF8StringEncoding error:nil];
    // The dict has an entry for this filename, but not this content's hash.
    NSDictionary *hashesByName = @{
        @"Custom.css": [NSSet setWithObject:
            @"0000000000000000000000000000000000000000000000000000000000000000"],
    };

    NSUInteger deleted = MPPruneStockStylesheetsInDirectory(stylesDir, hashesByName);
    XCTAssertEqual(deleted, 0UL,
                   @"A non-matching file should not be counted as deleted");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:customFile],
                  @"Non-matching custom file should survive pruning");
}

- (void)testPruneStockStylesheetsDoesNotDeleteHashMatchUnderDifferentFilename
{
    // Regression test for the bug this API shape fixes: a user file whose
    // content happens to be byte-identical to a historical stock style
    // must NOT be deleted if it is filed under a different filename.
    NSString *stylesDir = [self.tempDir stringByAppendingPathComponent:@"Styles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:stylesDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *userFile = [stylesDir stringByAppendingPathComponent:@"MyBackup.css"];
    [@"/* byte-identical to a stock style */" writeToFile:userFile atomically:YES
                                                  encoding:NSUTF8StringEncoding error:nil];
    // The matching hash is filed only under "GitHub.css", not the
    // "MyBackup.css" name this user file actually has on disk.
    NSDictionary *hashesByName = @{
        @"GitHub.css": [NSSet setWithObject:MPContentHashOfFileAtPath(userFile)],
    };

    NSUInteger deleted = MPPruneStockStylesheetsInDirectory(stylesDir, hashesByName);
    XCTAssertEqual(deleted, 0UL,
                   @"A content-hash match under an unrelated filename must not "
                   @"cause deletion");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:userFile],
                  @"User file should survive despite the hash collision under "
                  @"a different filename");
}

- (void)testPruneStockStylesheetsOnAbsentDirectoryReturnsZero
{
    NSString *missingDir = [self.tempDir stringByAppendingPathComponent:@"NoSuchStyles"];
    NSDictionary *hashesByName = @{
        @"Stock.css": [NSSet setWithObject:
            @"1111111111111111111111111111111111111111111111111111111111111111"],
    };

    NSUInteger deleted = MPPruneStockStylesheetsInDirectory(missingDir, hashesByName);
    XCTAssertEqual(deleted, 0UL,
                   @"An absent directory should report zero deletions");
}

#pragma mark - MPKnownStockStyleHashesByName Tests

- (void)testKnownStockStyleHashesByNameStructureAndFormat
{
    NSDictionary *hashesByName = MPKnownStockStyleHashesByName();
    NSPredicate *hexPredicate = [NSPredicate predicateWithFormat:
        @"SELF MATCHES %@", @"^[0-9a-f]{64}$"];

    NSUInteger total = 0;
    for (NSString *fileName in hashesByName)
    {
        XCTAssertTrue([fileName hasSuffix:@".css"],
                      @"Every key should be a .css filename, got: %@", fileName);
        NSSet *hashes = hashesByName[fileName];
        total += hashes.count;
        for (NSString *hash in hashes)
            XCTAssertTrue([hexPredicate evaluateWithObject:hash],
                          @"Hash should be 64 lowercase hex characters, got: %@", hash);
    }
    XCTAssertEqual(total, 48UL,
                   @"Expected 48 known stock stylesheet hashes across all "
                   @"filenames, got %lu", (unsigned long)total);
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

- (void)testEmptyPasteboardDoesNotProduceURL {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [pasteboard clearContents];
    XCTAssertNil([pasteboard URLForType:NSPasteboardTypeString]);
    [pasteboard releaseGlobally];
}

- (void)testFrontMatterClosingDelimiterMustOccupyWholeLine {
    NSString *input = @"---\ntitle: sample\n---not a delimiter\nbody";
    NSUInteger offset = NSNotFound;
    XCTAssertNil([input frontMatter:&offset]);
    XCTAssertEqual(offset, 0u);
}

- (void)testJavaScriptJSONPreservesUnicode {
    XCTAssertEqualObjects(MPGetObjectFromJavaScript(@"var value = {text:'é漢😀'};", @"value"),
                          (@{@"text": @"é漢😀"}));
}

- (void)testJavaScriptMissingAndUnserializableValuesReturnNil {
    XCTAssertNil(MPGetObjectFromJavaScript(@"var value = 1;", @"missing"));
    XCTAssertNil(MPGetObjectFromJavaScript(@"var value = function() {};", @"value"));
    XCTAssertNil(MPGetObjectFromJavaScript(@"var value = {}; value.self = value;", @"value"));
}

- (void)testMalformedTextClippingReturnsFilePath {
    NSURL *url = [NSURL fileURLWithPath:[self.tempDir stringByAppendingPathComponent:@"bad.textClipping"]];
    for (id value in @[@"invalid dictionary", @{@"public.utf8-plain-text": @42}]) {
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"UTI-Data": value}
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        [data writeToURL:url atomically:YES];
        XCTAssertEqualObjects([[FileURLInlining alloc] initWithURL:url].inlineContent, url.path);
    }
}

- (void)testNewEmptyDocumentDoesNotOverwriteExistingFileAndReportsWriteFailure {
    NSURL *url = [NSURL fileURLWithPath:[self.tempDir stringByAppendingPathComponent:@"existing.md"]];
    NSData *content = [@"preserve me" dataUsingEncoding:NSUTF8StringEncoding];
    [content writeToURL:url atomically:YES];
    NSError *error = nil;
    XCTAssertNil([[NSDocumentController sharedDocumentController]
        createNewEmptyDocumentForURL:url display:NO error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:url], content);
    error = nil;
    NSURL *missingParent = [NSURL fileURLWithPath:[self.tempDir stringByAppendingPathComponent:@"missing/target.md"]];
    XCTAssertNil([[NSDocumentController sharedDocumentController]
        createNewEmptyDocumentForURL:missingParent display:NO error:&error]);
    XCTAssertNotNil(error);
}

- (void)testUniqueTemporaryFilesDoNotOverwriteAndRejectTraversal {
    NSData *first = [@"first" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *a = MPWriteDataToUniqueTemporaryFile(first, @"document.md", NULL);
    NSString *b = MPWriteDataToUniqueTemporaryFile([@"second" dataUsingEncoding:NSUTF8StringEncoding], @"document.md", NULL);
    XCTAssertNotNil(a);
    XCTAssertNotEqualObjects(a, b);
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:a], first);
    XCTAssertNil(MPWriteDataToUniqueTemporaryFile(first, @"../document.md", NULL));
    [[NSFileManager defaultManager] removeItemAtPath:a.stringByDeletingLastPathComponent error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:b.stringByDeletingLastPathComponent error:NULL];
}

- (void)testUnindentPreservesCursorInsideRemovedIndent {
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string = @"    content";
    view.selectedRange = NSMakeRange(0, 0);
    [view unindentSelectedLines];
    XCTAssertEqualObjects(view.string, @"content");
    XCTAssertTrue(NSEqualRanges(view.selectedRange, NSMakeRange(0, 0)));
}

- (void)testUnindentRemovesWhitespaceOnlyLineAndPreservesSelection {
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string = @"    \n    text";
    view.selectedRange = NSMakeRange(0, view.string.length);
    [view unindentSelectedLines];
    XCTAssertEqualObjects(view.string, @"\ntext");
    XCTAssertTrue(NSEqualRanges(view.selectedRange, NSMakeRange(0, view.string.length)));
}

- (void)testHeaderRemovalKeepsCursorInsideMarkerInBounds {
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string = @"### heading";
    view.selectedRange = NSMakeRange(0, 0);
    MPRenderer *renderer=[[MPRenderer alloc] init];
    [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){return [renderer HTMLForMarkdownSnapshot:markdown];}];
    XCTAssertEqualObjects(view.string, @"heading");
    XCTAssertTrue(NSEqualRanges(view.selectedRange, NSMakeRange(0, 0)));
}

- (void)testNormalTextKeepsAdjacentLinesSelectionAndUndoForHeadingLevels {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSTextView *view = [[NSTextView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:view];
    view.allowsUndo = YES;
    for (NSUInteger level = 1; level <= 3; level++) {
        NSString *prefix = [[@"###" substringToIndex:level] stringByAppendingString:@" "];
        NSString *source = [NSString stringWithFormat:@"# Previous\n%@Title é 日本語 **bold**\n### Following", prefix];
        NSString *expected = @"# Previous\nTitle é 日本語 **bold**\n### Following";
        view.string = source;
        NSUInteger cursor = [source rangeOfString:@"日本語"].location;
        view.selectedRange = NSMakeRange(cursor, 3);
        [view.undoManager removeAllActions];
        [view.undoManager beginUndoGrouping];
        MPRenderer *renderer=[[MPRenderer alloc] init];
        [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){return [renderer HTMLForMarkdownSnapshot:markdown];}];
        [view.undoManager endUndoGrouping];
        XCTAssertEqualObjects(view.string, expected);
        XCTAssertTrue(NSEqualRanges(view.selectedRange, NSMakeRange(cursor-prefix.length, 3)));
        XCTAssertTrue(view.undoManager.canUndo);
        [view.undoManager undo];
        XCTAssertEqualObjects(view.string, source);
        [view.undoManager redo];
        XCTAssertEqualObjects(view.string, expected);
    }
}

- (void)testNormalTextConsumesActualHeadingDelimitersAndPreservesNeighborsAndUndo {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSTextView *view = [[NSTextView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:view];
    view.allowsUndo = YES;
    window.releasedWhenClosed=NO;
    MPRenderer *renderer = [[MPRenderer alloc] init];
    MPMockRendererDelegate *delegate = [[MPMockRendererDelegate alloc] init];
    renderer.delegate = delegate;
    NSArray *cases = @[
        @[@"# Before\n\nTitle\n====\n\n---\n\n# After\n", @"# Before\n\nTitle\n\n---\n\n# After\n", @"Title", @0],
        @[@"# Before\r\n\r\nTitle\r\n----\r\n\r\n---\r\n\r\n# After\r\n", @"# Before\r\n\r\nTitle\r\n\r\n---\r\n\r\n# After\r\n", @"Title", @0],
        @[@"# Before\n\n# Title ###\n\n# After\n", @"# Before\n\nTitle\n\n# After\n", @"Title", @0],
        @[@"# Before\r\n\r\n### Title ###\r\n\r\n# After\r\n", @"# Before\r\n\r\nTitle\r\n\r\n# After\r\n", @"Title", @0],
        @[@"Title\n====\n\n# After\n", @"## Title\n\n# After\n", @"Title", @2],
        @[@"# Before\n\nTitle\n====\n\n# After\n", @"# Before\n\nTitle\n\n# After\n", @"====", @0]
    ];
    @try {
    for (NSArray *item in cases) {
        NSString *source=item[0], *expected=item[1], *selected=item[2];
        view.string=source;
        view.selectedRange=[source rangeOfString:selected];
        [view.undoManager removeAllActions];
        [view.undoManager beginUndoGrouping];
        [view makeHeaderForSelectedLinesWithLevel:[item[3] unsignedIntegerValue]
            renderMarkdown:^NSString *(NSString *markdown){return [renderer HTMLForMarkdownSnapshot:markdown];}];
        [view.undoManager endUndoGrouping];
        XCTAssertEqualObjects(view.string,expected,@"%@",source);
        NSString *html=[renderer HTMLForMarkdownSnapshot:view.string];
        XCTAssertTrue([html containsString:[item[3] unsignedIntegerValue] ? @">Title</h2>" : @"<p>Title</p>"],@"%@",html);
        XCTAssertTrue([html containsString:@">After</h1>"],@"%@",html);
        if (![selected isEqualToString:@"===="])
            XCTAssertEqualObjects([view.string substringWithRange:view.selectedRange],@"Title");
        else XCTAssertLessThanOrEqual(NSMaxRange(view.selectedRange),view.string.length);
        XCTAssertTrue(view.undoManager.canUndo);
        [view.undoManager undo];
        XCTAssertEqualObjects(view.string,source);
        [view.undoManager redo];
        XCTAssertEqualObjects(view.string,expected);
    }
    } @finally { [window close]; }
}

- (void)testNormalTextKeepsLiteralHeadingSyntaxInCodeHTMLAndNonHeadings {
    MPRenderer *renderer=[[MPRenderer alloc] init];
    MPMockRendererDelegate *delegate=[[MPMockRendererDelegate alloc] init];
    delegate.extensions=HOEDOWN_EXT_FENCED_CODE|HOEDOWN_EXT_SPACE_HEADERS;
    renderer.delegate=delegate;
    for(NSString *source in @[@"```markdown\n# Title ###\n```\n",@"<div>\n# Title ###\n</div>\n",
        @"Title ###\n",@"#Title ###\n",@"Title\n\n---\n",@"Title\n= =\n",
        @"<h1>\nTitle\n====\n</h1>\n",@"#######Title\n",@"#\tTitle\n"]) {
        NSTextView *view=[[NSTextView alloc] initWithFrame:NSZeroRect];
        view.string=source; view.selectedRange=[source rangeOfString:@"Title"];
        NSString *before=[renderer HTMLForMarkdownSnapshot:source];
        [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){return [renderer HTMLForMarkdownSnapshot:markdown];}];
        XCTAssertEqualObjects(view.string,source);
        XCTAssertEqualObjects([renderer HTMLForMarkdownSnapshot:view.string],before);
        XCTAssertEqualObjects([view.string substringWithRange:view.selectedRange],@"Title");
    }
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string=@"### Title ###  \n";
    view.selectedRange=[view.string rangeOfString:@"Title"];
    XCTAssertTrue([[renderer HTMLForMarkdownSnapshot:view.string] containsString:@">Title ###</h3>"]);
    [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){return [renderer HTMLForMarkdownSnapshot:markdown];}];
    XCTAssertEqualObjects(view.string,@"Title ###\n");
    XCTAssertTrue([[renderer HTMLForMarkdownSnapshot:view.string] containsString:@"<p>Title ###</p>"]);
    XCTAssertEqualObjects([view.string substringWithRange:view.selectedRange],@"Title");
}

- (void)testNormalTextKeepsHeadingBodyLiteralAndDoesNotCreateAnotherBlock {
    MPRenderer *renderer=[[MPRenderer alloc] init];
    MPMockRendererDelegate *delegate=[[MPMockRendererDelegate alloc] init];
    renderer.delegate=delegate;
    NSArray *cases=@[
        @[@"# - Title\n",@"\\- Title\n",@"<p>- Title</p>"],
        @[@"# # Title\n",@"\\# Title\n",@"<p># Title</p>"],
        @[@"# 1. Title\n",@"1\\. Title\n",@"<p>1. Title</p>"],
        @[@"# Title\n---\n",@"Title\n\n---\n",@"<p>Title</p>"],
        @[@"# Title\r\n---\r\n",@"Title\r\n\r\n---\r\n",@"<p>Title</p>"]
    ];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;
    NSTextView *view=[[NSTextView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:view]; view.allowsUndo=YES;
    @try {
    for(NSArray *item in cases) {
        view.string=item[0]; view.selectedRange=[view.string rangeOfString:@"Title"];
        [view.undoManager removeAllActions];
        [view.undoManager beginUndoGrouping];
        [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){return [renderer HTMLForMarkdownSnapshot:markdown];}];
        [view.undoManager endUndoGrouping];
        XCTAssertEqualObjects(view.string,item[1]);
        NSString *html=[renderer HTMLForMarkdownSnapshot:view.string];
        XCTAssertTrue([html containsString:item[2]],@"%@",html);
        if([item[0] containsString:@"---"]) XCTAssertTrue([html containsString:@"<hr>"]);
        XCTAssertEqualObjects([view.string substringWithRange:view.selectedRange],@"Title");
        XCTAssertTrue(view.undoManager.canUndo);
        [view.undoManager undo]; XCTAssertEqualObjects(view.string,item[0]);
        [view.undoManager redo]; XCTAssertEqualObjects(view.string,item[1]);
    }
    } @finally { [window close]; }
}

- (void)testNormalTextSetextConversionPreservesConsecutiveUnderlineContext {
    MPRenderer *renderer=[[MPRenderer alloc] init];
    MPMockRendererDelegate *delegate=[[MPMockRendererDelegate alloc] init];
    renderer.delegate=delegate;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;
    NSTextView *view=[[NSTextView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:view]; view.allowsUndo=YES;
    @try {
    for(NSString *ending in @[@"\n",@"\r\n"]) {
        NSString *source=[NSString stringWithFormat:@"Title%@---%@===%@",ending,ending,ending];
        NSString *expected=[NSString stringWithFormat:@"Title%@%@===%@",ending,ending,ending];
        NSString *before=[renderer HTMLForMarkdownSnapshot:source];
        XCTAssertTrue([before containsString:@">Title</h2>"]);
        XCTAssertTrue([before containsString:@"<h1 id=\"section\"></h1>"]);
        for(NSNumber *length in @[@5,@(5+ending.length+3)]) {
            view.string=source; view.selectedRange=NSMakeRange(0,length.unsignedIntegerValue);
            [view.undoManager removeAllActions];
            [view.undoManager beginUndoGrouping];
            [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){
                return [renderer HTMLForMarkdownSnapshot:markdown];
            }];
            [view.undoManager endUndoGrouping];
            XCTAssertEqualObjects(view.string,expected);
            NSString *html=[renderer HTMLForMarkdownSnapshot:view.string];
            XCTAssertTrue([html containsString:@"<p>Title</p>"],@"%@",html);
            XCTAssertFalse([html containsString:@">Title</h"]);
            XCTAssertTrue([html containsString:@"<h1 id=\"section\"></h1>"]);
            XCTAssertLessThanOrEqual(NSMaxRange(view.selectedRange),view.string.length);
            XCTAssertTrue([[view.string substringWithRange:view.selectedRange] hasPrefix:@"Title"]);
            XCTAssertTrue(view.undoManager.canUndo);
            if(view.undoManager.canUndo) {
                [view.undoManager undo]; XCTAssertEqualObjects(view.string,source);
                [view.undoManager redo]; XCTAssertEqualObjects(view.string,expected);
            }
        }
    }
    } @finally { [window close]; }
}

- (void)testNormalTextLargeHeadingSelectionUsesActualParserAndKeepsContents {
    NSMutableString *source=[NSMutableString string],*expected=[NSMutableString string];
    for(NSUInteger i=0;i<1000;i++) {
        [source appendFormat:@"## Heading %lu é 😀\n",(unsigned long)i];
        [expected appendFormat:@"Heading %lu é 😀\n",(unsigned long)i];
    }
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string=source; view.selectedRange=NSMakeRange(0,source.length);
    MPRenderer *renderer=[[MPRenderer alloc] init];
    MPMockRendererDelegate *delegate=[[MPMockRendererDelegate alloc] init];
    renderer.delegate=delegate;
    __block NSUInteger fullDocumentParses=0,totalParses=0;
    NSDate *started=NSDate.date;
    [view makeHeaderForSelectedLinesWithLevel:0 renderMarkdown:^NSString *(NSString *markdown){
        totalParses++;
        if(markdown.length>=source.length) fullDocumentParses++;
        return [renderer HTMLForMarkdownSnapshot:markdown];
    }];
    NSLog(@"Source heading conversion: 1000 lines, %lu UTF16 units, %.6f seconds, %lu full document parses / %lu total parses",
        (unsigned long)source.length,-started.timeIntervalSinceNow,(unsigned long)fullDocumentParses,(unsigned long)totalParses);
    XCTAssertEqualObjects(view.string,expected);
    XCTAssertLessThanOrEqual(NSMaxRange(view.selectedRange),view.string.length);
    XCTAssertEqualObjects([view.string substringWithRange:view.selectedRange],expected);
    NSString *html=[renderer HTMLForMarkdownSnapshot:view.string];
    XCTAssertFalse([html containsString:@"<h2"]);
    XCTAssertTrue([html containsString:@"Heading 0 é 😀"]);
    XCTAssertTrue([html containsString:@"Heading 999 é 😀"]);
}

- (void)testOrderedBlockToggleRemovesEntireMarkerAndPreservesSelectedText {
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string = @"12. first\n123. second";
    view.selectedRange = NSMakeRange(0, view.string.length);
    [view toggleBlockWithPattern:@"^[0-9]+\\.[ \t]+" prefix:@"1. "];
    XCTAssertEqualObjects(view.string, @"first\nsecond");
    XCTAssertTrue(NSEqualRanges(view.selectedRange, NSMakeRange(0, view.string.length)));
}

- (void)testBlockToggleRemovesEmptyMarkerWithCursorInsideMarker {
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    view.string = @"12. ";
    view.selectedRange = NSMakeRange(0, 0);
    [view toggleBlockWithPattern:@"^[0-9]+\\.[ \t]+" prefix:@"1. "];
    XCTAssertEqualObjects(view.string, @"");
    XCTAssertTrue(NSEqualRanges(view.selectedRange, NSMakeRange(0, 0)));
}

- (void)testYAMLRejectsRecursiveAliasesAndClosesStream {
    NSInputStream *stream = [NSInputStream inputStreamWithData:
        [@"value: &value [*value]" dataUsingEncoding:NSUTF8StringEncoding]];
    NSError *error = nil;
    XCTAssertNil([YAMLSerialization objectsWithYAMLStream:stream
        options:kYAMLReadOptionStringScalars error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(stream.streamStatus, NSStreamStatusClosed);
}

- (void)testYAMLParseErrorsCloseStreamAndValidAliasesRemainReadable {
    NSInputStream *stream = [NSInputStream inputStreamWithData:
        [@"value: [" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertNil([YAMLSerialization objectsWithYAMLStream:stream
        options:kYAMLReadOptionStringScalars error:NULL]);
    XCTAssertEqual(stream.streamStatus, NSStreamStatusClosed);
    NSArray *objects = [YAMLSerialization objectsWithYAMLString:@"one: &one [é]\ntwo: *one"
        options:kYAMLReadOptionStringScalars error:NULL];
    XCTAssertEqualObjects([objects.firstObject objectForKey:@"two"], (@[@"é"]));
    XCTAssertNil([YAMLSerialization objectWithYAMLString:@""
        options:kYAMLReadOptionStringScalars error:NULL]);
}

- (void)testYAMLWriterPreservesUnicodeAndEmitsEachDocument {
    NSError *error = nil;
    NSArray *documents = @[@{@"title": @"é漢😀"}, @{@"title": @"second"}];
    NSData *yaml = [YAMLSerialization YAMLDataWithObject:documents
        options:kYAMLWriteOptionMultipleDocuments error:&error];
    XCTAssertNotNil(yaml);
    XCTAssertNil(error);
    NSArray *decoded = [YAMLSerialization objectsWithYAMLData:yaml
        options:kYAMLReadOptionStringScalars error:&error];
    XCTAssertEqual(decoded.count, 2u);
    XCTAssertEqualObjects([decoded[0] objectForKey:@"title"], @"é漢😀");
    XCTAssertEqualObjects([decoded[1] objectForKey:@"title"], @"second");
}

- (void)testYAMLWriterRejectsRecursiveAndUnsupportedObjects {
    NSMutableArray *recursive = [NSMutableArray array];
    [recursive addObject:recursive];
    NSError *error = nil;
    XCTAssertNil([YAMLSerialization YAMLDataWithObject:recursive
        options:kYAMLWriteOptionSingleDocument error:&error]);
    XCTAssertNotNil(error);
    [recursive removeAllObjects];
    XCTAssertNil([YAMLSerialization YAMLDataWithObject:NSObject.new
        options:kYAMLWriteOptionSingleDocument error:NULL]);
}

- (void)testYAMLWriterReportsOutputStreamFailure {
    MPAuditOutputStream *stream = [[MPAuditOutputStream alloc] init];
    stream.backingStream = [NSOutputStream outputStreamToFileAtPath:
        [self.tempDir stringByAppendingPathComponent:@"missing/output.yaml"] append:NO];
    NSError *error = nil;
    XCTAssertFalse([YAMLSerialization writeObject:@{@"title": @"sample"}
        toYAMLStream:stream options:kYAMLWriteOptionSingleDocument error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue(stream.didClose);
}

- (void)testYAMLMutabilityOptionsAreIndependent {
    id immutable = [YAMLSerialization objectWithYAMLString:@"[hello, [world]]"
        options:kYAMLReadOptionStringScalars error:NULL];
    XCTAssertFalse([immutable isKindOfClass:NSMutableArray.class]);
    XCTAssertFalse([immutable[1] isKindOfClass:NSMutableArray.class]);
    id containers = [YAMLSerialization objectWithYAMLString:@"[hello]"
        options:kYAMLReadOptionStringScalars | kYAMLReadOptionMutableContainers error:NULL];
    XCTAssertTrue([containers isKindOfClass:NSMutableArray.class]);
    XCTAssertFalse([containers[0] isKindOfClass:NSMutableString.class]);
    id leaves = [YAMLSerialization objectWithYAMLString:@"[hello]"
        options:kYAMLReadOptionStringScalars | kYAMLReadOptionMutableContainersAndLeaves error:NULL];
    XCTAssertTrue([leaves[0] isKindOfClass:NSMutableString.class]);
}

- (void)testYAMLCollectionKeysArePopulatedBeforeDictionaryCopiesThem {
    NSArray *cases = @[@"? [a, b]\n: value\n",
                       @"? {a: b}\n: value\n",
                       @"one: &key [a, b]\n? *key\n: value\n",
                       @"? [{a: b}]\n: value\n"];
    NSArray *options = @[@(kYAMLReadOptionStringScalars),
                         @(kYAMLReadOptionStringScalars | kYAMLReadOptionMutableContainers),
                         @(kYAMLReadOptionStringScalars | kYAMLReadOptionMutableContainersAndLeaves)];
    for (NSNumber *option in options) {
        for (NSString *yaml in cases) {
            NSError *error = nil;
            id document = [YAMLSerialization objectWithYAMLString:yaml
                options:option.unsignedIntegerValue error:&error];
            XCTAssertNotNil(document);
            XCTAssertNil(error);
            id collectionKey = nil;
            for (id key in [document allKeys])
                if (![key isKindOfClass:NSString.class]) collectionKey = key;
            XCTAssertNotNil(collectionKey);
            XCTAssertEqualObjects([document objectForKey:collectionKey], @"value");
            if ([collectionKey isKindOfClass:NSArray.class]) {
                if ([collectionKey count] == 2)
                    XCTAssertEqualObjects(collectionKey, (@[@"a", @"b"]));
                else
                    XCTAssertEqualObjects([collectionKey[0] objectForKey:@"a"], @"b");
            } else {
                XCTAssertEqualObjects([collectionKey objectForKey:@"a"], @"b");
            }
        }
    }
}

- (void)testYAMLStringWriterReturnsNilOnSerializationFailure {
    NSError *error = nil;
    XCTAssertNil([YAMLSerialization YAMLStringWithObject:NSObject.new
        options:kYAMLWriteOptionSingleDocument error:&error]);
    XCTAssertNotNil(error);
    XCTAssertNil([YAMLSerialization YAMLStringWithObject:nil
        options:kYAMLWriteOptionSingleDocument error:NULL]);
    NSString *yaml = [YAMLSerialization YAMLStringWithObject:@{@"title": @"é漢😀"}
        options:kYAMLWriteOptionSingleDocument error:&error];
    XCTAssertNotNil(yaml);
    XCTAssertNil(error);
    id decoded = [YAMLSerialization objectWithYAMLString:yaml
        options:kYAMLReadOptionStringScalars error:&error];
    XCTAssertEqualObjects([decoded objectForKey:@"title"], @"é漢😀");
}

- (void)testStylesheetRepeatedLanguageRulesStayWithinCollectionCapacity {
    NSMutableString *stylesheet = [NSMutableString string];
    for (NSUInteger i = 0; i < 100; i++)
        [stylesheet appendString:@"H1\ncolor: ff0000\n\n"];
    pmh_style_collection *styles = pmh_parse_styles((char *)stylesheet.UTF8String, NULL, NULL);
    NSUInteger count = 0;
    for (int i = 0; i < pmh_NUM_LANG_TYPES; i++)
        for (pmh_style_attribute *attribute = styles->element_styles[i]; attribute; attribute = attribute->next) {
            XCTAssertEqual(attribute->lang_element_type, pmh_H1);
            count++;
        }
    XCTAssertEqual(count, 100u);
    pmh_free_style_collection(styles);
}

- (void)testPastingURLPreservesBracketsAndUnbalancedURLParenthesis {
    NSPasteboard *board = NSPasteboard.generalPasteboard;
    NSMutableArray *savedItems = [NSMutableArray array];
    for (NSPasteboardItem *item in board.pasteboardItems) {
        NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
        for (NSString *type in item.types) {
            NSData *data = [item dataForType:type];
            if (data) [copy setData:data forType:type];
        }
        [savedItems addObject:copy];
    }
    @try {
        [board clearContents];
        [board setString:@"https://example.com/a)" forType:NSPasteboardTypeString];
        MPEditorView *view = [[MPEditorView alloc] initWithFrame:NSZeroRect];
        view.string = @"a]b";
        view.selectedRange = NSMakeRange(0, 3);
        [view paste:nil];
        XCTAssertEqualObjects(view.string, @"[a\\]b](https://example.com/a%29)");
    } @finally {
        [board clearContents];
        if (savedItems.count) [board writeObjects:savedItems];
    }
}

- (void)testEditorGeometryAcceptsTrailingWhitespaceAfterSurrogatePairs {
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    view.string = @"😀👨‍👩‍👧‍👦\n\n\n";
    XCTAssertNoThrow([view performSelector:NSSelectorFromString(@"updateContentGeometry")]);
}


- (void)testCalloutIndentationUsesTabStopsAndEquivalentClosingMargins
{
    XCTAssertEqual(MPMarkdownPrefixColumns(@"\t"),4u);
    XCTAssertEqual(MPMarkdownPrefixColumns(@" \t"),4u);
    XCTAssertEqual(MPMarkdownPrefixColumns(@"\t \t"),8u);
    for (NSString *ending in @[@"\n",@"\r\n"]) for (NSString *openingMargin in @[@"    ",@"\t",@" \t"]) {
        NSString *source=[[NSString stringWithFormat:@"- Owner\n\n%@::: {.callout-note}\n    ## Title\n\n    Body\n\t:::\n\n- Next\n",openingMargin] stringByReplacingOccurrencesOfString:@"\n" withString:ending];
        NSArray *entries=MPPrepareCallouts(source)[@"callouts"];
        XCTAssertEqual(entries.count,1u);
        if (entries.count!=1) continue;
        XCTAssertEqualObjects([source substringWithRange:[entries.firstObject[@"sourceOpenRange"] rangeValue]],[[openingMargin stringByAppendingString:@"::: {.callout-note}"] stringByAppendingString:ending]);
        XCTAssertEqualObjects([source substringWithRange:[entries.firstObject[@"sourceCloseRange"] rangeValue]],[@"\t:::" stringByAppendingString:ending]);
    }
    for (NSString *margin in @[@"    ",@"\t",@" \t"]) {
        NSString *code=[NSString stringWithFormat:@"%@::: {.callout-note}\n%@literal\n%@:::\n",margin,margin,margin];
        XCTAssertEqual([MPPrepareCallouts(code)[@"callouts"] count],0u,@"Standalone indentation remains literal code");
    }
}

- (void)testCalloutSourceMetadataPreservesExactUTF16DelimiterRanges {
    for (NSString *ending in @[@"\n", @"\r\n"]) {
        NSString *source = [NSString stringWithFormat:@"Before 😀%@::: {.callout-caution}%@## Attention%@Test%@:::%@After%@",
            ending, ending, ending, ending, ending, ending];
        NSArray *pairs = MPPrepareCallouts(source)[@"callouts"];
        XCTAssertEqual(pairs.count, 1u);
        if (pairs.count != 1) continue;
        NSDictionary *pair = pairs.firstObject;
        XCTAssertNotNil(pair[@"sourceOpenRange"]);
        XCTAssertNotNil(pair[@"sourceCloseRange"]);
        XCTAssertNotNil(pair[@"sourceContentRange"]);
        if (!pair[@"sourceOpenRange"] || !pair[@"sourceCloseRange"] || !pair[@"sourceContentRange"]) continue;
        NSRange opening = [pair[@"sourceOpenRange"] rangeValue];
        NSRange closing = [pair[@"sourceCloseRange"] rangeValue];
        NSRange content = [pair[@"sourceContentRange"] rangeValue];
        XCTAssertEqualObjects([source substringWithRange:opening], [@"::: {.callout-caution}" stringByAppendingString:ending]);
        XCTAssertEqualObjects([source substringWithRange:closing], [@":::" stringByAppendingString:ending]);
        XCTAssertEqualObjects([source substringWithRange:content], ([NSString stringWithFormat:@"## Attention%@Test%@", ending, ending]));
        XCTAssertEqual(NSMaxRange(opening), content.location);
        XCTAssertEqual(NSMaxRange(content), closing.location);
        XCTAssertEqualObjects(pair[@"type"], @"caution");
        XCTAssertEqualObjects(pair[@"start"], @1);
        XCTAssertEqualObjects(pair[@"end"], @4);
        NSMutableString *unwrapped = source.mutableCopy;
        [unwrapped deleteCharactersInRange:closing];
        [unwrapped deleteCharactersInRange:opening];
        XCTAssertEqualObjects(unwrapped, ([NSString stringWithFormat:@"Before 😀%@## Attention%@Test%@After%@", ending, ending, ending, ending]));
    }
}

- (void)testCalloutSourceMetadataPairsNestedContainersAndKeepsUnrecognizedSyntaxLiteral {
    NSString *source = @"::: {.callout-note collapse=\"true\"}\n## Outer\n::: {.callout-tip}\nInner\n:::\n:::\n";
    NSArray *pairs = MPPrepareCallouts(source)[@"callouts"];
    XCTAssertEqual(pairs.count, 2u);
    if (pairs.count == 2) {
        NSDictionary *inner = pairs[0], *outer = pairs[1];
        XCTAssertEqualObjects(inner[@"type"], @"tip");
        XCTAssertEqualObjects(outer[@"collapse"], @"true");
        XCTAssertEqualObjects(inner[@"start"], @2);
        XCTAssertEqualObjects(inner[@"end"], @4);
        XCTAssertEqualObjects(outer[@"start"], @0);
        XCTAssertEqualObjects(outer[@"end"], @5);
        XCTAssertNotNil(inner[@"sourceContentRange"]);
        if (inner[@"sourceContentRange"])
            XCTAssertEqualObjects([source substringWithRange:[inner[@"sourceContentRange"] rangeValue]], @"Inner\n");
    }
    for (NSString *literal in @[@"```markdown\n::: {.callout-note}\nLiteral\n:::\n```\n",
        @"~~~\n::: {.callout-note}\nLiteral\n:::\n~~~\n",
        @"    ::: {.callout-note}\n    Literal\n    :::\n",
        @"- Action\n\n        ::: {.callout-note}\n        Literal\n        :::\n",
        @"`::: {.callout-note}\nLiteral\n:::`\n",
        @"::: {.callout-unknown}\nLiteral\n:::\n", @"::: {.callout-note unknown=\"yes\"}\nLiteral\n:::\n",
        @"::: {.callout-note}\nUnclosed\n"]) {
        XCTAssertEqual([MPPrepareCallouts(literal)[@"callouts"] count], 0u, @"%@", literal);
    }
    NSString *eof = @"::: {.callout-note}\nContent\n:::";
    NSDictionary *last = [MPPrepareCallouts(eof)[@"callouts"] firstObject];
    XCTAssertNotNil(last[@"sourceCloseRange"]);
    if (last[@"sourceCloseRange"])
        XCTAssertEqual(NSMaxRange([last[@"sourceCloseRange"] rangeValue]), eof.length);
}

- (void)testDefaultCalloutTitlesAreLocalizedInFrenchAndEnglishResources {
    NSDictionary *expected = @{
        @"en": @[@"Note", @"Tip", @"Warning", @"Important", @"Caution", @"Prerequisites"],
        @"fr": @[@"Note", @"Conseil", @"Avertissement", @"Important", @"Attention", @"Pré-requis"]
    };
    NSArray *keys = @[@"PreviewCalloutTitleNote", @"PreviewCalloutTitleTip", @"PreviewCalloutTitleWarning",
        @"PreviewCalloutTitleImportant", @"PreviewCalloutTitleCaution", @"PreviewToggleTitle"];
    for (NSString *language in expected) {
        NSString *path = [NSBundle.mainBundle pathForResource:language ofType:@"lproj"];
        XCTAssertNotNil(path);
        NSBundle *bundle = path ? [NSBundle bundleWithPath:path] : nil;
        for (NSUInteger i = 0; i < keys.count; i++)
            XCTAssertEqualObjects([bundle localizedStringForKey:keys[i] value:@"missing" table:nil], expected[language][i]);
    }
}

@end
