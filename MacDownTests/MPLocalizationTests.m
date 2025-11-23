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
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *basePath = [bundle.bundlePath stringByDeletingLastPathComponent];
    basePath = [basePath stringByDeletingLastPathComponent]; // Go up to project root

    NSString *baseFile = [NSString stringWithFormat:@"%@/MacDown/Localization/Base.lproj/%@.strings", basePath, viewControllerName];
    NSString *localeFile = [NSString stringWithFormat:@"%@/MacDown/Localization/%@.lproj/%@.strings", basePath, locale, viewControllerName];

    NSSet *baseObjectIDs = [self objectIDsFromStringsFile:baseFile];
    NSSet *localeObjectIDs = [self objectIDsFromStringsFile:localeFile];

    // Base file might not exist if there are no localizable strings
    if (!baseObjectIDs && expectedCount == 0) {
        return;
    }

    XCTAssertNotNil(localeObjectIDs,
                    @"Localization file missing or invalid for %@ locale: %@",
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
                 expectedCount:12]; // 12 localizable elements
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
                 expectedCount:21]; // 21 localizable elements
}

- (void)testKoreanEditorPreferencesLocalization
{
    [self validateLocalization:@"ko-KR"
                viewController:@"MPEditorPreferencesViewController"
                 expectedCount:21]; // 21 localizable elements
}

#pragma mark - Japanese (ja) Localization Tests - Reference

- (void)testJapaneseMarkdownPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPMarkdownPreferencesViewController"
                 expectedCount:12];
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
                 expectedCount:21];
}

- (void)testJapaneseEditorPreferencesLocalization
{
    [self validateLocalization:@"ja"
                viewController:@"MPEditorPreferencesViewController"
                 expectedCount:21];
}

#pragma mark - Chinese Simplified (zh-Hans) Localization Tests

- (void)testChineseSimplifiedMarkdownPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPMarkdownPreferencesViewController"
                 expectedCount:12];
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
                 expectedCount:21];
}

- (void)testChineseSimplifiedEditorPreferencesLocalization
{
    [self validateLocalization:@"zh-Hans"
                viewController:@"MPEditorPreferencesViewController"
                 expectedCount:21];
}

@end
