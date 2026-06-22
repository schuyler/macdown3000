//
//  MPSelectionCountTests.m
//  MacDownTests
//
//  Tests for Issue #452: Selection character/word count.
//  Verifies the pure string-counting helper (MPTextCountForString) and the
//  selection/document display-mode coordination on MPDocument.
//
//  Copyright (c) 2026 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPPreferences.h"
#import "DOMNode+Text.h"


#pragma mark - Test Category to Expose Private API

@interface MPDocument (SelectionCountTesting)
@property (nonatomic) NSUInteger totalWords;
@property (nonatomic) NSUInteger totalCharacters;
@property (nonatomic) NSUInteger totalCharactersNoSpaces;
@property (nonatomic) BOOL showingSelectionCount;
- (void)editorSelectionDidChange:(NSNotification *)notification;
- (void)refreshDocumentWordCountTitles;
@end


#pragma mark - Test Case

@interface MPSelectionCountTests : XCTestCase
@property (strong) MPDocument *document;
@end


@implementation MPSelectionCountTests

- (void)setUp
{
    [super setUp];
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    self.document = nil;
    [super tearDown];
}


#pragma mark - MPTextCountForString: Core Counting Logic

/**
 * An empty string counts as zero on all three metrics.
 */
- (void)testCountEmptyString
{
    DOMNodeTextCount count = MPTextCountForString(@"");
    XCTAssertEqual(count.words, (NSUInteger)0);
    XCTAssertEqual(count.characters, (NSUInteger)0);
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)0);
}

/**
 * A nil string is handled gracefully as zero.
 */
- (void)testCountNilString
{
    DOMNodeTextCount count = MPTextCountForString(nil);
    XCTAssertEqual(count.words, (NSUInteger)0);
    XCTAssertEqual(count.characters, (NSUInteger)0);
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)0);
}

/**
 * A simple two-word string: 2 words, 11 characters (incl. the space),
 * 10 characters excluding the space.
 */
- (void)testCountSimpleSentence
{
    DOMNodeTextCount count = MPTextCountForString(@"hello world");
    XCTAssertEqual(count.words, (NSUInteger)2);
    XCTAssertEqual(count.characters, (NSUInteger)11);
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)10);
}

/**
 * Multiple/leading/trailing spaces do not change the word count, but are
 * reflected in the character (with spaces) count and excluded from the
 * no-spaces count.
 */
- (void)testCountExtraSpaces
{
    DOMNodeTextCount count = MPTextCountForString(@"  hi   there  ");
    XCTAssertEqual(count.words, (NSUInteger)2);
    XCTAssertEqual(count.characters, (NSUInteger)14);
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)7);
}

/**
 * Newlines are excluded from the character count (matching the document-wide
 * algorithm) but words on either side are still counted.
 */
- (void)testCountNewlinesExcludedFromCharacters
{
    DOMNodeTextCount count = MPTextCountForString(@"a\nb");
    XCTAssertEqual(count.words, (NSUInteger)2);
    XCTAssertEqual(count.characters, (NSUInteger)2);
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)2);
}

/**
 * Whitespace-only content has zero words and zero no-space characters, but
 * non-newline whitespace still contributes to the character count.
 */
- (void)testCountWhitespaceOnly
{
    DOMNodeTextCount count = MPTextCountForString(@"   \n  ");
    XCTAssertEqual(count.words, (NSUInteger)0);
    XCTAssertEqual(count.characters, (NSUInteger)5);   // newline excluded
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)0);
}

/**
 * Single word with no whitespace: all character metrics agree.
 */
- (void)testCountSingleWord
{
    DOMNodeTextCount count = MPTextCountForString(@"command");
    XCTAssertEqual(count.words, (NSUInteger)1);
    XCTAssertEqual(count.characters, (NSUInteger)7);
    XCTAssertEqual(count.characterWithoutSpaces, (NSUInteger)7);
}


#pragma mark - Display-Mode Coordination

/**
 * A freshly initialized document is not in selection-display mode.
 */
- (void)testShowingSelectionCountDefaultsToNo
{
    XCTAssertFalse(self.document.showingSelectionCount,
                   @"Document should start showing totals, not selection");
}

/**
 * refreshDocumentWordCountTitles clears selection-display mode.
 */
- (void)testRefreshDocumentTitlesClearsSelectionMode
{
    self.document.showingSelectionCount = YES;
    [self.document refreshDocumentWordCountTitles];
    XCTAssertFalse(self.document.showingSelectionCount,
                   @"Refreshing document titles should leave selection mode");
}

/**
 * While in selection-display mode, assigning a document total must not be
 * blocked — the stored value updates even though the title write is skipped.
 */
- (void)testTotalsStillStoredWhileShowingSelection
{
    self.document.showingSelectionCount = YES;
    self.document.totalWords = 42;
    self.document.totalCharacters = 100;
    self.document.totalCharactersNoSpaces = 80;
    XCTAssertEqual(self.document.totalWords, (NSUInteger)42);
    XCTAssertEqual(self.document.totalCharacters, (NSUInteger)100);
    XCTAssertEqual(self.document.totalCharactersNoSpaces, (NSUInteger)80);
}

/**
 * editorSelectionDidChange: must early-return safely when the word-count
 * preference is disabled, leaving display mode untouched.
 */
- (void)testSelectionChangeRespectsDisabledPreference
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorShowWordCount;
    prefs.editorShowWordCount = NO;
    @try {
        XCTAssertNoThrow([self.document editorSelectionDidChange:nil],
                         @"Should not crash when preference disabled");
        XCTAssertFalse(self.document.showingSelectionCount);
    }
    @finally {
        prefs.editorShowWordCount = original;
    }
}

/**
 * With no editor (bare document), a selection change resolves to an empty
 * selection and reverts to document totals without crashing.
 */
- (void)testSelectionChangeWithNoEditorRevertsToTotals
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorShowWordCount;
    prefs.editorShowWordCount = YES;
    @try {
        self.document.showingSelectionCount = YES;
        XCTAssertNoThrow([self.document editorSelectionDidChange:nil],
                         @"Should not crash without an editor");
        XCTAssertFalse(self.document.showingSelectionCount,
                       @"Empty selection should revert to document totals");
    }
    @finally {
        prefs.editorShowWordCount = original;
    }
}

@end
