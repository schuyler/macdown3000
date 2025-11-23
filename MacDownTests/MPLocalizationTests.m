//
//  MPLocalizationTests.m
//  MacDownTests
//
//  Created to validate localization completeness.
//  Ensures all preference view controller localization files contain required keys.
//

#import <XCTest/XCTest.h>

@interface MPLocalizationTests : XCTestCase
@end

@implementation MPLocalizationTests

#pragma mark - Helper Methods

- (NSSet *)objectIDsFromStringsFile:(NSString *)path
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return nil;
    }

    NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!strings) {
        return nil;
    }

    NSMutableSet *objectIDs = [NSMutableSet set];
    for (NSString *key in strings.allKeys) {
        // Keys are in format "ObjectID.property", we want just the ObjectID
        NSString *objectID = [[key componentsSeparatedByString:@"."] firstObject];
        if (objectID) {
            [objectIDs addObject:objectID];
        }
    }

    return objectIDs;
}

- (void)validateLocalization:(NSString *)locale
              viewController:(NSString *)viewControllerName
               expectedCount:(NSUInteger)expectedCount
{
    // Get the MacDown app bundle (not the test bundle)
    NSBundle *appBundle = [NSBundle bundleWithIdentifier:@"com.uranusjr.macdown"];
    XCTAssertNotNil(appBundle, @"Could not find MacDown app bundle");

    if (!appBundle) {
        return;
    }

    // Load the localized strings from the app bundle
    NSString *stringsPath = [appBundle pathForResource:viewControllerName
                                                ofType:@"strings"
                                           inDirectory:nil
                                       forLocalization:locale];

    XCTAssertNotNil(stringsPath,
                    @"Localization file missing for %@ locale: %@",
                    locale, viewControllerName);

    if (!stringsPath) {
        return;
    }

    NSSet *localeObjectIDs = [self objectIDsFromStringsFile:stringsPath];

    XCTAssertNotNil(localeObjectIDs,
                    @"Failed to load localization file for %@ locale: %@",
                    locale, viewControllerName);

    if (localeObjectIDs) {
        XCTAssertEqual(localeObjectIDs.count, expectedCount,
                       @"Incomplete localization for %@ locale in %@. Expected %lu keys, found %lu",
                       locale, viewControllerName, (unsigned long)expectedCount, (unsigned long)localeObjectIDs.count);
    }
}

#pragma mark - Korean (ko-KR) Localization Tests

- (void)testKoreanMarkdownPreferencesLocalization
{
    [self validateLocalization:@"ko-KR"
                viewController:@"MPMarkdownPreferencesViewController"
                 expectedCount:14]; // 14 localizable elements
}

- (void)testKoreanTerminalPreferencesLocalization
{
    [self validateLocalization:@"ko-KR"
                viewController:@"MPTerminalPreferencesViewController"
                 expectedCount:6]; // 6 localizable elements
}

- (void)testKoreanGeneralPreferencesLocalization
{
    [self validateLocalization:@"ko-KR"
                viewController:@"MPGeneralPreferencesViewController"
                 expectedCount:9]; // 9 localizable elements
}

- (void)testKoreanHtmlPreferencesLocalization
{
    [self validateLocalization:@"ko-KR"
                viewController:@"MPHtmlPreferencesViewController"
                 expectedCount:20]; // 20 localizable elements
}

- (void)testKoreanEditorPreferencesLocalization
{
    [self validateLocalization:@"ko-KR"
                viewController:@"MPEditorPreferencesViewController"
                 expectedCount:20]; // 20 localizable elements
}

#pragma mark - Japanese (ja) Localization Tests - Reference

- (void)testJapaneseMarkdownPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPMarkdownPreferencesViewController"
                 expectedCount:14];
}

- (void)testJapaneseTerminalPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPTerminalPreferencesViewController"
                 expectedCount:6];
}

- (void)testJapaneseGeneralPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPGeneralPreferencesViewController"
                 expectedCount:9];
}

- (void)testJapaneseHtmlPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPHtmlPreferencesViewController"
                 expectedCount:20];
}

- (void)testJapaneseEditorPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPEditorPreferencesViewController"
                 expectedCount:20];
}

#pragma mark - Chinese Simplified (zh-Hans) Localization Tests

- (void)testChineseSimplifiedMarkdownPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPMarkdownPreferencesViewController"
                 expectedCount:14];
}

- (void)testChineseSimplifiedTerminalPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPTerminalPreferencesViewController"
                 expectedCount:6];
}

- (void)testChineseSimplifiedGeneralPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPGeneralPreferencesViewController"
                 expectedCount:9];
}

- (void)testChineseSimplifiedHtmlPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPHtmlPreferencesViewController"
                 expectedCount:20];
}

- (void)testChineseSimplifiedEditorPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPEditorPreferencesViewController"
                 expectedCount:20];
}

@end
