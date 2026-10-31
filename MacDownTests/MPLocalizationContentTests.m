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
    XCTAssertEqual(menu.count, 53u);
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

@end
