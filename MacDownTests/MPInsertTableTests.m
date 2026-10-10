//
//  MPInsertTableTests.m
//  MacDownTests
//
//  Regression tests for Issue #278: "Insert Table" toolbar action.
//
//  The rc.1 build shipped a table button that (1) did nothing when the editor
//  pane had keyboard focus and (2) corrupted the document on repeated clicks by
//  inserting a second table inside the first table's first cell. These tests
//  exercise the pure insertion helper that drives the action, covering block
//  separation, caret placement, and the repeated-insertion case.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPRenderer.h"
#import "MPPreferences.h"

// Expose the pure class helper for testing.
@interface MPDocument (InsertTableTesting)
+ (NSString *)tableInsertionForContent:(NSString *)content selectedRange:(NSRange)selectedRange columns:(NSUInteger)columns rows:(NSUInteger)rows replacementRange:(NSRange *)replacement caretLocation:(NSUInteger *)caret;
+ (NSString *)tableInsertionForContent:(NSString *)content
                         selectedRange:(NSRange)selectedRange
                      replacementRange:(NSRange *)outReplacementRange
                         caretLocation:(NSUInteger *)outCaretLocation;
@end

static NSString *MPExpectedTableHeaderRow(void)
{
    NSString *format=NSLocalizedString(@"Column %lu", @"Default Markdown table column heading");
    return [NSString stringWithFormat:@"| %@ | %@ | %@ |",
        [NSString stringWithFormat:format,1ul],
        [NSString stringWithFormat:format,2ul],
        [NSString stringWithFormat:format,3ul]];
}
static NSString *const kSeparatorRow = @"| :---: | :---: | :---: |";
static NSString *const kBodyRow = @"|  |  |  |";

@interface MPInsertTableTests : XCTestCase
@end

@implementation MPInsertTableTests
- (void)testAll64TableDimensionsAndInvalidSizes
{
    for(NSUInteger rows=1;rows<=8;rows++) for(NSUInteger columns=1;columns<=8;columns++) {
        NSRange replacement;NSUInteger caret;
        NSString *text=[MPDocument tableInsertionForContent:@"Before\nAfter" selectedRange:NSMakeRange(6,0) columns:columns rows:rows replacementRange:&replacement caretLocation:&caret];
        NSArray *lines=[[text stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsSeparatedByString:@"\n"];
        XCTAssertEqual(lines.count,rows+1);
        for(NSString *line in lines) XCTAssertEqual([line componentsSeparatedByString:@"|"].count,columns+2);
        XCTAssertLessThanOrEqual(caret,12+text.length);
        XCTAssertEqual(replacement.location,6u);
    }
    for(NSArray *size in @[@[@0,@1],@[@1,@0],@[@9,@1],@[@1,@9],@[@(NSUIntegerMax),@1]]) {
        XCTAssertNil([MPDocument tableInsertionForContent:@"" selectedRange:NSMakeRange(0,0) columns:[size[0] unsignedIntegerValue] rows:[size[1] unsignedIntegerValue] replacementRange:NULL caretLocation:NULL]);
    }
}


#pragma mark - Helpers

/// Apply the helper once and return the resulting document, reporting the caret.
- (NSString *)applyInsertToContent:(NSString *)content
                        atSelection:(NSRange)selection
                         caretOut:(NSUInteger *)caretOut
{
    NSRange replacement = NSMakeRange(0, 0);
    NSUInteger caret = 0;
    NSString *inserted = [MPDocument tableInsertionForContent:content
                                                selectedRange:selection
                                             replacementRange:&replacement
                                                caretLocation:&caret];
    XCTAssertNotNil(inserted);
    // The replacement range must be valid for the supplied content.
    XCTAssertLessThanOrEqual(NSMaxRange(replacement), content.length);
    NSString *result = [content stringByReplacingCharactersInRange:replacement
                                                        withString:inserted];
    // The caret must land within the resulting document.
    XCTAssertLessThanOrEqual(caret, result.length);
    if (caretOut)
        *caretOut = caret;
    return result;
}

/// Assert that every table in `document` is structurally intact: each header
/// row is immediately followed by the separator row and the body row, and the
/// header row appears exactly `expectedCount` times (no nesting/splicing).
- (void)assertDocument:(NSString *)document
   hasIntactTableCount:(NSUInteger)expectedCount
{
    NSArray<NSString *> *lines = [document componentsSeparatedByString:@"\n"];
    NSUInteger headerCount = 0;
    for (NSUInteger i = 0; i < lines.count; i++)
    {
        if (![lines[i] isEqualToString:MPExpectedTableHeaderRow()])
            continue;
        headerCount++;
        XCTAssertLessThan(i + 2, lines.count,
                          @"table at line %lu is truncated", (unsigned long)i);
        if (i + 2 < lines.count)
        {
            XCTAssertEqualObjects(lines[i + 1], kSeparatorRow,
                                  @"separator row mangled after header at line %lu",
                                  (unsigned long)i);
            XCTAssertEqualObjects(lines[i + 2], kBodyRow,
                                  @"body row mangled after header at line %lu",
                                  (unsigned long)i);
        }
        // The line directly above a table (if any) must be blank — the table is
        // its own block.
        if (i > 0)
            XCTAssertEqualObjects(lines[i - 1], @"",
                                  @"table at line %lu is not preceded by a blank line",
                                  (unsigned long)i);
    }
    XCTAssertEqual(headerCount, expectedCount,
                   @"expected %lu intact tables, found %lu",
                   (unsigned long)expectedCount, (unsigned long)headerCount);
}

/// Insert a marker at the caret and assert it lands inside the first body cell,
/// i.e. the first cell reads "| X |".
- (void)assertCaret:(NSUInteger)caret
       inFirstCellOf:(NSString *)document
{
    NSString *typed = [document stringByReplacingCharactersInRange:NSMakeRange(caret, 0)
                                                        withString:@"X"];
    XCTAssertTrue([typed rangeOfString:@"| X |  |  |"].location != NSNotFound,
                  @"caret did not land in the first body cell; got around: %@",
                  [typed substringWithRange:NSMakeRange(
                       caret > 6 ? caret - 6 : 0,
                       MIN((NSUInteger)13, typed.length - (caret > 6 ? caret - 6 : 0)))]);
}

#pragma mark - Insertion into an empty document

- (void)testInsertIntoEmptyDocument
{
    NSUInteger caret = 0;
    NSString *result = [self applyInsertToContent:@""
                                       atSelection:NSMakeRange(0, 0)
                                          caretOut:&caret];
    [self assertDocument:result hasIntactTableCount:1];
    [self assertCaret:caret inFirstCellOf:result];
    // No spurious leading blank line at the very start of the document.
    XCTAssertTrue([result hasPrefix:MPExpectedTableHeaderRow()]);
}

#pragma mark - Caret at start / middle / end

- (void)testInsertAtStartOfNonEmptyDocument
{
    NSString *content = @"existing paragraph\n";
    NSUInteger caret = 0;
    NSString *result = [self applyInsertToContent:content
                                       atSelection:NSMakeRange(0, 0)
                                          caretOut:&caret];
    [self assertDocument:result hasIntactTableCount:1];
    [self assertCaret:caret inFirstCellOf:result];
}

- (void)testInsertMidLineDoesNotSplitTheLine
{
    NSString *content = @"hello world";
    // Caret between "hello" and " world".
    NSUInteger caret = 0;
    NSString *result = [self applyInsertToContent:content
                                       atSelection:NSMakeRange(5, 0)
                                          caretOut:&caret];
    [self assertDocument:result hasIntactTableCount:1];
    [self assertCaret:caret inFirstCellOf:result];
    // The original line must survive intact (snapped to end of line, not split).
    XCTAssertTrue([result rangeOfString:@"hello world"].location != NSNotFound,
                  @"the existing line was split: %@", result);
}

- (void)testInsertAtEndWithoutTrailingNewline
{
    NSString *content = @"abc";
    NSUInteger caret = 0;
    NSString *result = [self applyInsertToContent:content
                                       atSelection:NSMakeRange(3, 0)
                                          caretOut:&caret];
    [self assertDocument:result hasIntactTableCount:1];
    [self assertCaret:caret inFirstCellOf:result];
    XCTAssertTrue([result hasPrefix:@"abc\n\n"],
                  @"expected a blank line between content and table: %@", result);
}

- (void)testInsertAtEndWithTrailingNewlineHasSingleBlankLine
{
    NSString *content = @"abc\n";
    NSString *result = [self applyInsertToContent:content
                                       atSelection:NSMakeRange(4, 0)
                                          caretOut:NULL];
    [self assertDocument:result hasIntactTableCount:1];
    // Exactly one blank line (two newlines) between "abc" and the table.
    XCTAssertTrue([result hasPrefix:@"abc\n\n"]);
    XCTAssertFalse([result hasPrefix:@"abc\n\n\n"],
                   @"too much separation before table: %@", result);
}

#pragma mark - Selection replacement

- (void)testNonEmptySelectionIsReplaced
{
    NSString *content = @"keep XXX keep";
    NSRange selection = [content rangeOfString:@"XXX"];
    NSUInteger caret = 0;
    NSString *result = [self applyInsertToContent:content
                                       atSelection:selection
                                          caretOut:&caret];
    [self assertDocument:result hasIntactTableCount:1];
    [self assertCaret:caret inFirstCellOf:result];
    XCTAssertTrue([result rangeOfString:@"XXX"].location == NSNotFound,
                  @"selection was not replaced: %@", result);
}

#pragma mark - Repeated insertion (the regression)

- (void)testRepeatedInsertionProducesTwoSiblingTables
{
    // First insertion into an empty document.
    NSUInteger caret1 = 0;
    NSString *doc1 = [self applyInsertToContent:@""
                                     atSelection:NSMakeRange(0, 0)
                                        caretOut:&caret1];
    [self assertDocument:doc1 hasIntactTableCount:1];

    // Second insertion at the caret left by the first (inside the first body
    // cell). Previously this spliced a table into the middle of the first one.
    NSUInteger caret2 = 0;
    NSString *doc2 = [self applyInsertToContent:doc1
                                     atSelection:NSMakeRange(caret1, 0)
                                        caretOut:&caret2];

    // Both tables must be present and structurally intact, with no nesting.
    [self assertDocument:doc2 hasIntactTableCount:2];
    [self assertCaret:caret2 inFirstCellOf:doc2];
    // No malformed merged row from splicing one table into another.
    XCTAssertTrue([doc2 rangeOfString:@"|  |  |  |  |"].location == NSNotFound,
                  @"tables were spliced together: %@", doc2);
}

- (void)testThreeRepeatedInsertionsStayIntact
{
    NSString *doc = @"";
    NSRange selection = NSMakeRange(0, 0);
    for (NSUInteger i = 0; i < 3; i++)
    {
        NSUInteger caret = 0;
        doc = [self applyInsertToContent:doc atSelection:selection caretOut:&caret];
        selection = NSMakeRange(caret, 0);
    }
    [self assertDocument:doc hasIntactTableCount:3];
}

#pragma mark - Range / bounds safety

- (void)testOutOfBoundsSelectionIsClamped
{
    NSString *content = @"short";
    NSRange replacement = NSMakeRange(0, 0);
    NSUInteger caret = 0;
    NSString *inserted =
        [MPDocument tableInsertionForContent:content
                               selectedRange:NSMakeRange(999, 999)
                            replacementRange:&replacement
                               caretLocation:&caret];
    XCTAssertNotNil(inserted);
    XCTAssertLessThanOrEqual(NSMaxRange(replacement), content.length);
    // Applying must not throw.
    NSString *result = [content stringByReplacingCharactersInRange:replacement
                                                        withString:inserted];
    [self assertDocument:result hasIntactTableCount:1];
}

- (void)testNilContentIsTreatedAsEmpty
{
    NSRange replacement = NSMakeRange(0, 0);
    NSUInteger caret = 0;
    NSString *inserted = [MPDocument tableInsertionForContent:nil
                                                selectedRange:NSMakeRange(0, 0)
                                             replacementRange:&replacement
                                                caretLocation:&caret];
    XCTAssertNotNil(inserted);
    XCTAssertEqual(replacement.location, (NSUInteger)0);
    XCTAssertEqual(replacement.length, (NSUInteger)0);
    XCTAssertTrue([inserted hasPrefix:MPExpectedTableHeaderRow()]);
}

- (void)testGeneratedTablesRenderEveryCellCenteredForAll64Dimensions
{
    MPPreferences *prefs=[MPPreferences sharedInstance];
    BOOL savedTables=prefs.extensionTables;
    @try {
        prefs.extensionTables=YES;
        MPDocument *owner=[MPDocument new];
        MPRenderer *renderer=[MPRenderer new];
        renderer.delegate=(id<MPRendererDelegate>)owner;
        for (NSUInteger rows=1;rows<=8;rows++) for (NSUInteger columns=1;columns<=8;columns++) {
            NSString *markdown=[MPDocument tableInsertionForContent:@"" selectedRange:NSMakeRange(0,0) columns:columns rows:rows replacementRange:NULL caretLocation:NULL];
            NSString *html=[renderer HTMLForMarkdownSnapshot:markdown];
            NSError *error=nil;
            NSXMLDocument *document=[[NSXMLDocument alloc] initWithXMLString:[NSString stringWithFormat:@"<root>%@</root>",html] options:0 error:&error];
            XCTAssertNotNil(document,@"%@",error);
            NSArray *cells=[document nodesForXPath:@"//th | //td" error:&error];
            XCTAssertEqual(cells.count,columns*rows,@"%lu columns and %lu rows",(unsigned long)columns,(unsigned long)rows);
            for (NSXMLElement *cell in cells) {
                XCTAssertEqualObjects([cell attributeForName:@"style"].stringValue,@"text-align: center");
            }
        }
    } @finally {
        prefs.extensionTables=savedTables;
    }
}

- (void)testTableHeadingTranslationsAreAvailableForAllApplicationLanguages
{
    NSArray *languages=@[@"ar",@"cs",@"da",@"da-DK",@"de",@"en",@"es",@"et",@"fi",@"fr",@"he",@"hi",@"is",@"it-IT",@"ja",@"ko-KR",@"nb-NO",@"nl-NL",@"pt-BR",@"ru-RU",@"sk",@"sv",@"tr",@"uk",@"zh-Hans",@"zh-Hant"];
    for (NSString *language in languages) {
        NSString *path=[NSBundle.mainBundle pathForResource:language ofType:@"lproj"];
        XCTAssertNotNil(path,@"Missing language %@",language);
        NSBundle *bundle=[NSBundle bundleWithPath:path];
        NSString *format=[bundle localizedStringForKey:@"Column %lu" value:@"MISSING" table:nil];
        XCTAssertNotEqualObjects(format,@"MISSING",@"Missing table heading in %@",language);
        XCTAssertEqual([format componentsSeparatedByString:@"%lu"].count,2u);
        NSString *withoutPlaceholder=[format stringByReplacingOccurrencesOfString:@"%lu" withString:@""];
        XCTAssertFalse([withoutPlaceholder containsString:@"%"],@"Unexpected format specifier in %@",language);
        XCTAssertFalse([format containsString:@"|"]);
        XCTAssertFalse([format containsString:@"\n"]);
    }
    NSDictionary *expected=@{@"en":@"Column 1",@"fr":@"Colonne 1",@"de":@"Spalte 1",@"es":@"Columna 1"};
    for (NSString *language in expected) {
        NSBundle *bundle=[NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:language ofType:@"lproj"]];
        NSString *format=[bundle localizedStringForKey:@"Column %lu" value:nil table:nil];
        XCTAssertEqualObjects(([NSString stringWithFormat:format,1ul]),expected[language]);
    }
}

- (void)testGeneratedHeadersFollowTheActiveApplicationLanguage
{
    NSString *markdown=[MPDocument tableInsertionForContent:@"" selectedRange:NSMakeRange(0,0) columns:3 rows:2 replacementRange:NULL caretLocation:NULL];
    NSString *language=NSBundle.mainBundle.preferredLocalizations.firstObject;
    NSLog(@"Table generation test language: %@",language);
    if ([language isEqual:@"fr"]) {XCTAssertTrue([markdown hasPrefix:@"| Colonne 1 | Colonne 2 | Colonne 3 |\n"]);}
    else if ([language isEqual:@"en"]) {XCTAssertTrue([markdown hasPrefix:@"| Column 1 | Column 2 | Column 3 |\n"]);}
    else {XCTAssertTrue([markdown hasPrefix:MPExpectedTableHeaderRow()]);}
    XCTAssertTrue([markdown containsString:@"| :---: | :---: | :---: |"]);
}

@end
