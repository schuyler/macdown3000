//
//  MPInsertTextReplacementRangeTests.m
//  MacDown 3000
//
//  RED tests for porting upstream fix (MacDownApp/macdown PR #1379, Fix 2):
//  NSTextView+Autocomplete.m has five call sites that use the deprecated
//  1-arg -insertText: instead of -insertText:replacementRange:. Unlike most
//  other call sites in this file (which already use the 2-arg form), these
//  five rely on NSTextView's *real*, non-overridable 1-arg implementation.
//
//  Discriminator (verified empirically against the live AppKit
//  implementation on macOS 15.6.1 / Xcode 16.1 -- this differs from what
//  was assumed during design review, see below): the deprecated 1-arg
//  -insertText: DOES funnel through our -insertText:replacementRange:
//  override on a real, windowed-or-not NSTextView, but it passes the
//  *current selection* as replacementRange, not NSNotFound. Concretely,
//  pre-fix each of these five sites records a replacementRange whose
//  location equals wherever the selection/cursor happened to be for that
//  call (e.g. 2, 7, 13, 17 in the fixtures below) -- never NSNotFound.
//  Post-fix, once each site calls -insertText:replacementRange: directly
//  with NSMakeRange(NSNotFound, 0) (Apple's documented sentinel for "use
//  the current selection / marked range"), the recorded range is exactly
//  NSNotFound.
//
//  NOTE ON DESIGN DEVIATION: the design assumed the override would never
//  fire pre-fix (1-arg not funneling into 2-arg at all). That assumption
//  does not hold on this SDK -- the override always fires; only the
//  *range value* differs pre/post-fix. The tests below were adjusted
//  accordingly: XCTAssertTrue(insertTextReplacementRangeCalled) now
//  passes both pre- and post-fix (it is a sanity check, not the
//  discriminator), and XCTAssertEqual(...location, NSNotFound) is the
//  actual RED/GREEN discriminator -- it fails pre-fix (location is a
//  real offset) and passes post-fix (location is NSNotFound). This still
//  faithfully exercises the same production code change the upstream fix
//  makes; only the failure mechanism differs from the original hypothesis.
//
//  Each test therefore asserts:
//    1. mock.insertTextReplacementRangeCalled is YES (true both pre/post-fix)
//    2. mock.recordedReplacementRange isEqual to NSMakeRange(NSNotFound, 0)
//       (false pre-fix, true post-fix -- this is the RED/GREEN discriminator)
//  We deliberately do NOT assert on .string contents, and do NOT expect a
//  crash pre-fix -- the deprecated 1-arg path degrades silently in terms
//  of range semantics, it doesn't crash.
//

#import <XCTest/XCTest.h>
#import "NSTextView+Autocomplete.h"
#import "MPDocument.h"
#import "MPEditorView.h"

#pragma mark - Mock Text View

/**
 * Overrides ONLY the 2-arg -insertText:replacementRange: (never calls
 * super), so we can detect whether production code funneled through it.
 * Mirrors the pattern in MPSmartQuoteTests.m's MockTextViewForQuotes.
 */
@interface MockTextView : NSTextView
@property (nonatomic) BOOL insertTextReplacementRangeCalled;
@property (nonatomic, strong) NSString *recordedInsertedString;
@property (nonatomic) NSRange recordedReplacementRange;
@end

@implementation MockTextView

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    self.insertTextReplacementRangeCalled = YES;
    self.recordedInsertedString = [string isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)string string] : string;
    self.recordedReplacementRange = replacementRange;
    // Deliberately do NOT call super. We only care whether production code
    // reaches this override, not about actually mutating text storage.
}

@end

#pragma mark - Mock Editor View (Site 6)

/**
 * Overrides ONLY the 2-arg -insertText:replacementRange: (never calls
 * super), exactly like MockTextView above, so we can detect whether
 * MPDocument's -insertNewParagraph: funneled through it. Must subclass
 * MPEditorView (not plain NSTextView) because MPDocument.editor is
 * declared as MPEditorView *.
 */
@interface MockEditorView : MPEditorView
@property (nonatomic) BOOL insertTextReplacementRangeCalled;
@property (nonatomic, strong) NSString *recordedInsertedString;
@property (nonatomic) NSRange recordedReplacementRange;
@end

@implementation MockEditorView

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    self.insertTextReplacementRangeCalled = YES;
    self.recordedInsertedString = [string isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)string string] : string;
    self.recordedReplacementRange = replacementRange;
    // Deliberately do NOT call super. We only care whether production code
    // reaches this override, not about actually mutating text storage.
}

@end

#pragma mark - MPDocument Testing Category (Site 6)

// -insertNewParagraph: is an IBAction defined only in MPDocument.m (not
// declared in MPDocument.h), and -editor is a private IBOutlet. Redeclare
// both here so the test can invoke/assign them directly, following the
// established idiom in MPScrollSyncTests.m and MPDocumentLifecycleTests.m.
@interface MPDocument (InsertNewParagraphTesting)
@property (weak) IBOutlet MPEditorView *editor;
- (IBAction)insertNewParagraph:(id)sender;
@end

#pragma mark - Test Case

@interface MPInsertTextReplacementRangeTests : XCTestCase
@property (strong) MockTextView *textView;
@end

@implementation MPInsertTextReplacementRangeTests

- (void)setUp
{
    [super setUp];
    self.textView = [[MockTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    self.textView.insertTextReplacementRangeCalled = NO;
    self.textView.recordedInsertedString = nil;
    self.textView.recordedReplacementRange = NSMakeRange(0, 0);
}

- (void)tearDown
{
    self.textView = nil;
    [super tearDown];
}

- (void)assertReplacementRangeFiredOnTextView:(MockTextView *)view
{
    // Sanity check only: on this SDK, the override fires whether the
    // production call site uses the 1-arg or 2-arg form. It is NOT the
    // RED/GREEN discriminator -- see file header.
    XCTAssertTrue(view.insertTextReplacementRangeCalled,
        @"Expected -insertText:replacementRange: to be called (directly or "
        @"via the deprecated 1-arg -insertText:).");
    // RED/GREEN discriminator: pre-fix, the 1-arg call site passes the
    // current selection as the replacement range (a real offset, never
    // NSNotFound). Post-fix, the 2-arg call site explicitly passes
    // NSMakeRange(NSNotFound, 0).
    XCTAssertEqual(view.recordedReplacementRange.location, (NSUInteger)NSNotFound,
        @"Expected replacementRange.location == NSNotFound (Apple's "
        @"documented sentinel for \"use current selection / marked range\"). "
        @"Pre-fix, the deprecated 1-arg -insertText: call sites instead "
        @"pass the live selection/cursor offset here.");
    XCTAssertEqual(view.recordedReplacementRange.length, (NSUInteger)0,
        @"Expected replacementRange.length == 0.");
}

#pragma mark - Site 1: insertSpacesForTab (NSTextView+Autocomplete.m L96)

- (void)testInsertSpacesForTabUsesReplacementRange
{
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"ab"]];
    self.textView.selectedRange = NSMakeRange(2, 0);

    [self.textView insertSpacesForTab];

    [self assertReplacementRangeFiredOnTextView:self.textView];
}

#pragma mark - Site 2: completeNextListItem: indent-only branch (L592)

// Cursor at the end of an indented, otherwise-empty list marker line
// ("    - "), immediately followed by an already-indented continuation
// line ("    -rest"). previousLineEmpty is true (no non-whitespace after
// the marker), so t == "", and after the newline is inserted the very next
// characters already equal t (trivially, since t is empty) -- landing in
// the "Has matching list item. Only insert indent." branch at L588-593,
// which fires a bare -insertText:indent with no replacementRange.
- (void)testCompleteNextListItemIndentOnlyBranchUsesReplacementRange
{
    NSString *content = @"    - \n    -rest";
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:content]];
    self.textView.selectedRange = NSMakeRange(6, 0);   // End of "    - "

    BOOL handled = [self.textView completeNextListItem:YES];

    XCTAssertTrue(handled, @"Fixture should reach the list-completion path.");
    [self assertReplacementRangeFiredOnTextView:self.textView];
}

#pragma mark - Site 3: completeNextListItem: normal branch (L607)

// Cursor at the end of a single-line unordered list item ("- item1") with
// nothing after it. The following line doesn't already contain a matching
// marker (there is no following line), so this falls through to the
// "Insert completion for normal cases" branch at L604-607.
- (void)testCompleteNextListItemNormalBranchUsesReplacementRange
{
    NSString *content = @"- item1";
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:content]];
    self.textView.selectedRange = NSMakeRange(content.length, 0);

    BOOL handled = [self.textView completeNextListItem:YES];

    XCTAssertTrue(handled, @"Fixture should reach the list-completion path.");
    [self assertReplacementRangeFiredOnTextView:self.textView];
}

#pragma mark - Site 4: completeNextBlockquoteLine (L648)

// Cursor at the end of a single-line blockquote ("> quoted line") with
// nothing after it, so the "already has identical markers on next line"
// short-circuit at L638-645 cannot fire, and control falls through to the
// "Insert completion." branch at L647-648.
- (void)testCompleteNextBlockquoteLineUsesReplacementRange
{
    NSString *content = @"> quoted line";
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:content]];
    self.textView.selectedRange = NSMakeRange(content.length, 0);

    BOOL handled = [self.textView completeNextBlockquoteLine];

    XCTAssertTrue(handled, @"Fixture should reach the blockquote-completion path.");
    [self assertReplacementRangeFiredOnTextView:self.textView];
}

#pragma mark - Site 5: completeNextIndentedLine (L667)

// Cursor at the end of an indented line ("    indented text"). The
// leading-whitespace span (start..end) is non-empty, so the method
// inserts a newline and then re-inserts that same leading indent via
// -insertText: at L667.
- (void)testCompleteNextIndentedLineUsesReplacementRange
{
    NSString *content = @"    indented text";
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:content]];
    self.textView.selectedRange = NSMakeRange(content.length, 0);

    BOOL handled = [self.textView completeNextIndentedLine];

    XCTAssertTrue(handled, @"Fixture should reach the indented-line-completion path.");
    [self assertReplacementRangeFiredOnTextView:self.textView];
}

#pragma mark - Site 6: insertNewParagraph: (MPDocument.m L2436-2438)

// Cursor at the end of a single-line, non-empty document ("abc", selection
// at location=3, length=0). locationOfFirstNewlineBefore: returns -1 (no
// preceding newline), so the empty-line short-circuit
// (location == newlineBefore + 1 && location == newlineAfter) requires
// location == 0, which is false here (location is 3). Control therefore
// falls through to the else-branch at L2431-2437, which -- post-fix --
// calls -insertText:replacementRange: directly with
// NSMakeRange(NSNotFound, 0) instead of the deprecated 1-arg form. This is
// the only call site of the six covered by this file that lives in
// MPDocument.m rather than NSTextView+Autocomplete.m, and it requires a
// distinct mock (MockEditorView, subclassing MPEditorView) because
// MPDocument.editor is declared as MPEditorView *, not NSTextView *.
- (void)testInsertNewParagraphUsesReplacementRange
{
    MPDocument *doc = [[MPDocument alloc] init];
    MockEditorView *editor = [[MockEditorView alloc] initWithFrame:NSZeroRect];
    editor.string = @"abc";
    editor.selectedRange = NSMakeRange(3, 0);
    doc.editor = editor;

    [doc insertNewParagraph:nil];

    // Inlined equivalent of -assertReplacementRangeFiredOnTextView: (that
    // helper is typed MockTextView * and is not reused here, per the
    // review guidance -- MockEditorView is a distinct, unrelated class).
    XCTAssertTrue(editor.insertTextReplacementRangeCalled,
        @"Expected -insertText:replacementRange: to be called (directly or "
        @"via the deprecated 1-arg -insertText:).");
    XCTAssertEqual(editor.recordedReplacementRange.location, (NSUInteger)NSNotFound,
        @"Expected replacementRange.location == NSNotFound (Apple's "
        @"documented sentinel for \"use current selection / marked range\"). "
        @"Pre-fix, the deprecated 1-arg -insertText: call site instead "
        @"passes the live selection/cursor offset here.");
    XCTAssertEqual(editor.recordedReplacementRange.length, (NSUInteger)0,
        @"Expected replacementRange.length == 0.");
}

@end
