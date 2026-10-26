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

@end
