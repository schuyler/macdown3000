//
//  MPLocalizationContentTests.m
//  MacDownTests
//
//  Checks bundled localization content: the ru-RU tables carry the Ukrainian
//  strings, and every Credits.rtf (the About panel body) carries the
//  «Слава Україні! 🇺🇦» line.
//

#import <XCTest/XCTest.h>

static NSString * const kMPSlavaUkrainiLine = @"Слава Україні! 🇺🇦";

@interface MPLocalizationContentTests : XCTestCase
@end

@implementation MPLocalizationContentTests

- (NSString *)lprojPath:(NSString *)locale
{
    NSString *resources = [NSBundle mainBundle].resourcePath;
    return [resources stringByAppendingPathComponent:
            [locale stringByAppendingPathExtension:@"lproj"]];
}

- (NSDictionary *)table:(NSString *)table locale:(NSString *)locale
{
    NSString *path = [[self lprojPath:locale] stringByAppendingPathComponent:
                      [table stringByAppendingPathExtension:@"strings"]];
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

- (void)testEveryCreditsFileContainsSlavaUkraini
{
    NSArray *locales = @[@"ar", @"de", @"en", @"es", @"fr", @"is", @"it-IT",
                         @"ja", @"ko-KR", @"pt-BR", @"sk", @"sv", @"zh-Hans",
                         @"zh-Hant"];
    for (NSString *locale in locales)
    {
        NSString *path = [[self lprojPath:locale]
                          stringByAppendingPathComponent:@"Credits.rtf"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        XCTAssertNotNil(data, @"%@ has no bundled Credits.rtf", locale);
        NSError *error = nil;
        NSAttributedString *credits = [[NSAttributedString alloc]
            initWithData:data ?: [NSData data]
                 options:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType}
      documentAttributes:NULL error:&error];
        XCTAssertNotNil(credits, @"%@ Credits.rtf did not parse: %@", locale, error);
        XCTAssertTrue([credits.string containsString:kMPSlavaUkrainiLine],
                      @"%@ Credits.rtf lacks the line", locale);
    }
}

- (void)testRussianAndUkrainianUseEnglishCredits
{
    // Neither has its own Credits.rtf, so the About panel falls back to the
    // development region (en), which the test above covers.
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *locale in @[@"ru-RU", @"uk"])
    {
        NSString *path = [[self lprojPath:locale]
                          stringByAppendingPathComponent:@"Credits.rtf"];
        XCTAssertFalse([manager fileExistsAtPath:path], @"%@", locale);
    }
}

- (void)testRussianTablesMatchUkrainian
{
    NSArray *tables = @[@"Localizable", @"MainMenu", @"MPDocument",
                        @"MPEditorPreferencesViewController",
                        @"MPGeneralPreferencesViewController",
                        @"MPHtmlPreferencesViewController",
                        @"MPMarkdownPreferencesViewController",
                        @"MPTerminalPreferencesViewController"];
    for (NSString *table in tables)
    {
        NSDictionary *uk = [self table:table locale:@"uk"];
        NSDictionary *ru = [self table:table locale:@"ru-RU"];
        XCTAssertGreaterThan(uk.count, 0u, @"uk %@ missing", table);
        XCTAssertGreaterThan(ru.count, 0u, @"ru-RU %@ missing", table);
        XCTAssertEqualObjects(ru, uk, @"%@", table);
    }
}

- (void)testUkrainianCoversMenuAndDialogStrings
{
    NSDictionary *menu = [self table:@"MainMenu" locale:@"uk"];
    XCTAssertEqual(menu.count, [self titledKeysInBaseXIB:@"MainMenu"].count,
                   @"uk MainMenu has an entry for every menu and menu item");
    XCTAssertEqualObjects(menu[@"5kV-Vb-QxS.title"], @"Про MacDown 3000");
    XCTAssertEqualObjects(menu[@"5QF-Oa-p0T.title"], @"Редагування");

    NSDictionary *document = [self table:@"MPDocument" locale:@"uk"];
    XCTAssertEqualObjects(document[@"dPo-OZ-Hdz.title"], @"Текст");

    NSDictionary *strings = [self table:@"Localizable" locale:@"uk"];
    XCTAssertEqualObjects(strings[@"File Modified Externally"],
                          @"Файл змінено ззовні");
    XCTAssertEqualObjects(strings[@"This file has been changed by another "
                                  "application. Do you want to discard your "
                                  "changes?"],
                          @"Цей файл було змінено іншою програмою. Бажаєте "
                           "відкинути свої зміни?");
    XCTAssertEqualObjects(strings[@"Discard"], @"Відкинути");
    XCTAssertEqualObjects(strings[@"Keep"], @"Залишити");
}

// Issue #639: every titled control in Settings › Rendering has an entry in
// each bundled MPHtmlPreferencesViewController.strings table. The keys come
// from the Base xib in the source tree, so a control added without
// translations fails here.
- (NSDictionary<NSString *, NSString *> *)titledKeysInBaseXIB:(NSString *)name
{
    NSString *testsDir = [@__FILE__ stringByDeletingLastPathComponent];
    NSString *path = [[testsDir stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:[NSString stringWithFormat:
            @"MacDown/Localization/Base.lproj/%@.xib", name]];
    NSError *error = nil;
    NSXMLDocument *xib = [[NSXMLDocument alloc]
        initWithContentsOfURL:[NSURL fileURLWithPath:path] options:0
                        error:&error];
    XCTAssertNotNil(xib, @"Cannot read %@: %@", path, error);

    NSMutableDictionary *keys = [NSMutableDictionary dictionary];
    for (NSXMLElement *element in [xib nodesForXPath:@"//*[@id and @title]"
                                               error:NULL])
    {
        NSString *title = [element attributeForName:@"title"].stringValue;
        if (!title.length)
            continue;
        NSString *identifier = [element attributeForName:@"id"].stringValue;
        keys[[identifier stringByAppendingString:@".title"]] = title;
    }
    for (NSXMLElement *cell in [xib nodesForXPath:@"//segmentedCell[@id]"
                                            error:NULL])
    {
        NSString *identifier = [cell attributeForName:@"id"].stringValue;
        NSArray *segments = [cell nodesForXPath:@"segments/segment" error:NULL];
        for (NSUInteger i = 0; i < segments.count; i++)
        {
            NSString *label =
                [segments[i] attributeForName:@"label"].stringValue;
            if (!label.length)
                continue;
            NSString *key = [NSString stringWithFormat:
                @"%@.ibShadowedLabels[%lu]", identifier, (unsigned long)i];
            keys[key] = label;
        }
    }
    return keys;
}

- (void)testRenderingPaneTablesCoverEveryTitledControl
{
    NSString *table = @"MPHtmlPreferencesViewController";
    NSDictionary *english = [self titledKeysInBaseXIB:table];
    XCTAssertGreaterThan(english.count, 0u, @"No titled controls found");

    NSArray *mustTranslate = @[@"iXi-Pv-mFl.title",
                               @"311-HC-cel.ibShadowedLabels[0]",
                               @"311-HC-cel.ibShadowedLabels[1]"];
    for (NSString *key in mustTranslate)
        XCTAssertNotNil(english[key], @"%@ is not in the Base xib", key);

    NSString *resources = [NSBundle mainBundle].resourcePath;
    NSArray *entries = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:resources error:NULL];
    NSUInteger tableCount = 0;
    for (NSString *entry in entries)
    {
        if (![entry.pathExtension isEqualToString:@"lproj"])
            continue;
        NSString *locale = entry.stringByDeletingPathExtension;
        NSDictionary *strings = [self table:table locale:locale];
        if (!strings)
            continue;
        tableCount++;
        for (NSString *key in english)
            XCTAssertNotNil(strings[key], @"%@ %@ has no entry for %@ (\"%@\")",
                            locale, table, key, english[key]);
        for (NSString *key in mustTranslate)
            XCTAssertNotEqualObjects(strings[key], english[key],
                                     @"%@ %@ leaves %@ in English",
                                     locale, table, key);
    }
    XCTAssertGreaterThanOrEqual(tableCount, 23u,
                                @"Expected the 23 localized %@ tables", table);
}

// Issue #653: every localized xib's tables have an entry for every titled
// control and menu item in the Base xib. A table that exists but is empty or
// unreadable fails rather than being skipped.
- (void)testEveryLocalizedXIBTableCoversEveryTitledControl
{
    NSString *repo = [[@__FILE__ stringByDeletingLastPathComponent]
                      stringByDeletingLastPathComponent];
    NSString *localization =
        [repo stringByAppendingPathComponent:@"MacDown/Localization"];
    NSString *resources = [NSBundle mainBundle].resourcePath;
    NSFileManager *manager = [NSFileManager defaultManager];

    NSArray *baseEntries = [manager contentsOfDirectoryAtPath:
        [localization stringByAppendingPathComponent:@"Base.lproj"] error:NULL];
    NSUInteger xibCount = 0;
    for (NSString *entry in baseEntries)
    {
        if (![entry.pathExtension isEqualToString:@"xib"])
            continue;
        xibCount++;
        NSString *table = entry.stringByDeletingPathExtension;
        NSString *file = [table stringByAppendingPathExtension:@"strings"];
        NSDictionary *english = [self titledKeysInBaseXIB:table];
        XCTAssertGreaterThan(english.count, 0u,
                             @"No titled controls found in %@.xib", table);

        NSMutableSet *sourceLocales = [NSMutableSet set];
        for (NSString *dir in [manager contentsOfDirectoryAtPath:localization
                                                          error:NULL])
        {
            if ([dir.pathExtension isEqualToString:@"lproj"]
                && [manager fileExistsAtPath:[[localization
                       stringByAppendingPathComponent:dir]
                       stringByAppendingPathComponent:file]])
                [sourceLocales addObject:dir.stringByDeletingPathExtension];
        }
        NSMutableSet *bundledLocales = [NSMutableSet set];
        for (NSString *dir in [manager contentsOfDirectoryAtPath:resources
                                                          error:NULL])
        {
            if ([dir.pathExtension isEqualToString:@"lproj"]
                && [manager fileExistsAtPath:[[resources
                       stringByAppendingPathComponent:dir]
                       stringByAppendingPathComponent:file]])
                [bundledLocales addObject:dir.stringByDeletingPathExtension];
        }
        XCTAssertGreaterThan(sourceLocales.count, 0u,
                             @"No localized %@ tables in the source tree", table);
        XCTAssertEqualObjects(bundledLocales, sourceLocales,
                              @"The bundled %@ tables differ from the source "
                               "tree's; a table is missing from the project",
                              file);

        for (NSString *locale in bundledLocales)
        {
            NSDictionary *strings = [self table:table locale:locale];
            XCTAssertGreaterThan(strings.count, 0u,
                                 @"%@ %@ is empty or unreadable", locale, file);
            if (!strings.count)
                continue;
            for (NSString *key in english)
                XCTAssertNotNil(strings[key],
                                @"%@ %@ has no entry for %@ (\"%@\")",
                                locale, file, key, english[key]);
        }
    }
    XCTAssertGreaterThanOrEqual(xibCount, 8u,
                                @"Expected every localized xib to be checked");
}

@end
