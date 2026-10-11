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

- (void)testPreviewFormattingControlsDoNotChangeDocumentTextCounts
{
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    @try {
        [web.mainFrame loadHTMLString:@"<html><head><meta name=\"macdown-checkbox-token\" content=\"count-fixture\"></head><body><p>hello world</p><code>inline words</code><pre><code>excluded code</code></pre></body></html>" baseURL:nil];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings){return !web.isLoading && web.mainFrame.DOMDocument.body!=nil;}] object:web]] timeout:10];
        DOMNodeTextCount original=web.mainFrame.DOMDocument.textCount;
        XCTAssertEqual(original.words,(NSUInteger)3);
        NSString *script=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"preview-edit" withExtension:@"js" subdirectory:@"Extensions"] encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertNotNil(script);
        [web stringByEvaluatingJavaScriptFromString:@"window.__macdownPreviewEditConfig={token:'count-fixture',nodes:[],math:false,strike:true,tasks:true,fenced:true};window.__macdownPreviewEditNodes=[];"];
        [web stringByEvaluatingJavaScriptFromString:script];
        for(NSString *display in @[@"none",@"block"]) {
            [web stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.macdownPreviewEditor.elements ? window.macdownPreviewEditor.elements().panel.style.display='%@' : document.getElementById('macdown-preview-format').style.display='%@'",display,display]];
            DOMNodeTextCount actual=web.mainFrame.DOMDocument.textCount;
            XCTAssertEqual(actual.words,original.words,@"%@",display);
            XCTAssertEqual(actual.characters,original.characters,@"%@",display);
            XCTAssertEqual(actual.characterWithoutSpaces,original.characterWithoutSpaces,@"%@",display);
        }
        // Authored content with the same ID remains countable: ownership is
        // tied to the live renderer nonce, not a globally reserved HTML ID.
        [web stringByEvaluatingJavaScriptFromString:@"var authored=document.createElement('div');authored.id='macdown-preview-format';authored.textContent='author words';authored.setAttribute('data-mp-preview-ui','different-token');document.body.appendChild(authored);"];
        DOMNodeTextCount withAuthor=web.mainFrame.DOMDocument.textCount;
        XCTAssertEqual(withAuthor.words,original.words+2);
        XCTAssertEqual(withAuthor.characters,original.characters+12);
        XCTAssertEqual(withAuthor.characterWithoutSpaces,original.characterWithoutSpaces+11);
    } @finally { [web close]; }
}

- (void)testDocumentWordCountUsesContinuousInlineTextAndSeparateBlocks
{
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    @try {
        [web.mainFrame loadHTMLString:@"<html><body><p>hello world</p></body></html>" baseURL:nil];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return !web.isLoading && web.mainFrame.DOMDocument.body != nil;
            }] object:web]] timeout:10];
        NSArray *cases = @[
            @[@"<p>hello world</p>", @2, @11, @10],
            @[@"<p>hel<strong>lo</strong> world</p>", @2, @11, @10],
            @[@"<p>he<em>ll</em>o world</p>", @2, @11, @10],
            @[@"<p>hel<a href='https://example.com'>lo</a> world</p>", @2, @11, @10],
            @[@"<p>he<span data-mp-edit-id='0'>ll</span>o world</p>", @2, @11, @10],
            @[@"<p>he<strong><em>ll</em></strong>o world</p>", @2, @11, @10],
            @[@"<p>hello</p><p>world</p>", @2, @10, @10],
            @[@"<p>hello<br>world</p>", @2, @10, @10],
            @[@"<ul><li>hello</li><li>world</li></ul>", @2, @10, @10],
            @[@"<p><code>inline words</code> tail</p><pre><code>excluded words</code></pre>", @2, @17, @15]
        ];
        for (NSArray *testCase in cases) {
            web.mainFrame.DOMDocument.body.innerHTML = testCase[0];
            DOMNodeTextCount count = web.mainFrame.DOMDocument.textCount;
            XCTAssertEqual(count.words, [testCase[1] unsignedIntegerValue], @"%@", testCase[0]);
            XCTAssertEqual(count.characters, [testCase[2] unsignedIntegerValue], @"%@", testCase[0]);
            XCTAssertEqual(count.characterWithoutSpaces, [testCase[3] unsignedIntegerValue], @"%@", testCase[0]);
        }
    } @finally { [web close]; }
}

@end
