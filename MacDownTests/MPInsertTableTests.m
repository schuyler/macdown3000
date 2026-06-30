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

// Expose the pure class helper for testing.
@interface MPDocument (InsertTableTesting)
+ (NSString *)tableInsertionForContent:(NSString *)content
                         selectedRange:(NSRange)selectedRange
                      replacementRange:(NSRange *)outReplacementRange
                         caretLocation:(NSUInteger *)outCaretLocation;
@end

static NSString *const kHeaderRow = @"| Column 1 | Column 2 | Column 3 |";
static NSString *const kSeparatorRow = @"| --- | --- | --- |";
static NSString *const kBodyRow = @"|  |  |  |";

@interface MPInsertTableTests : XCTestCase
@end

@implementation MPInsertTableTests

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
        if (![lines[i] isEqualToString:kHeaderRow])
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
    XCTAssertTrue([result hasPrefix:kHeaderRow]);
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
    XCTAssertTrue([inserted hasPrefix:kHeaderRow]);
}

@end
