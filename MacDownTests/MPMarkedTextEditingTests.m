//
//  MPMarkedTextEditingTests.m
//  MacDownTests
//
//  Commands that edit the editor's text from code commit text an input
//  method has marked (a composition) first, as confirming it would, and a
//  save leaves a pending composition alone.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPDocumentWindowTestSupport.h"
#import "MPEditorView.h"
#import "MPPreferences.h"
#import "NSTextView+Autocomplete.h"


@interface MPDocument (MarkedTextTesting)
@property (weak) IBOutlet MPEditorView *editor;
@end


#pragma mark - Test doubles

/** Counts -discardMarkedText instead of passing it to an input method. */
@interface MPRecordingInputContext : NSTextInputContext
@property (nonatomic) NSUInteger discardCount;
@end

@implementation MPRecordingInputContext

- (void)discardMarkedText
{
    self.discardCount++;
}

@end


/** A text view whose input context records, and which counts the
 * marked-text calls made to it. */
@interface MPMarkedTextSpyView : NSTextView
@property (nonatomic, strong) MPRecordingInputContext *recordingContext;
@property (nonatomic) NSUInteger unmarkCount;
@property (nonatomic) NSUInteger setMarkedCount;
@end

@implementation MPMarkedTextSpyView

- (NSTextInputContext *)inputContext
{
    if (!self.recordingContext)
        self.recordingContext =
            [[MPRecordingInputContext alloc] initWithClient:self];
    return self.recordingContext;
}

- (void)unmarkText
{
    self.unmarkCount++;
    [super unmarkText];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange
{
    self.setMarkedCount++;
    [super setMarkedText:string selectedRange:selectedRange
        replacementRange:replacementRange];
}

@end


/** A window that reports itself key without being ordered in. */
@interface MPMarkedTextTestWindow : NSWindow
@property (nonatomic) BOOL reportsKey;
@end

@implementation MPMarkedTextTestWindow

- (BOOL)isKeyWindow
{
    return self.reportsKey;
}

@end


#pragma mark - Helpers

static NSString * const kMPMarkedTextTyped = @"# Heading\n\nSome text ";
static NSString * const kMPMarkedTextPlainText = @"pasted";
static NSString * const kMPMarkedTextURL = @"https://example.com/";

/** A composition: its text, and the input method's selection in it. */
static NSArray<NSArray *> *MPMarkedTextCompositions(void)
{
    return @[
        // The caret at the end of the composition.
        @[@"日本語", [NSValue valueWithRange:NSMakeRange(3, 0)]],
        // A clause selected while converting.
        @[@"日本語を",
          [NSValue valueWithRange:NSMakeRange(0, 3)]],
    ];
}

/** Every command that edits the editor's text from code: the Format menu
 * and toolbar commands, Insert Table, New Paragraph, and Paste. */
static NSArray<NSString *> *MPMarkedTextCommands(void)
{
    return @[@"toggleStrong:", @"toggleEmphasis:", @"toggleInlineCode:",
             @"toggleStrikethrough:", @"toggleUnderline:",
             @"toggleHighlight:", @"toggleComment:", @"toggleLink:",
             @"toggleImage:", @"convertToH1:", @"convertToH2:",
             @"convertToH3:", @"convertToH4:", @"convertToH5:",
             @"convertToH6:", @"convertToParagraph:",
             @"toggleUnorderedList:", @"toggleOrderedList:",
             @"toggleBlockquote:", @"indent:", @"unindent:",
             @"insertTable:", @"insertNewParagraph:", @"paste:"];
}

/** What would handle `action` were `window` key: its first responder and
 * the responders after it, each asked for a supplemental target too (how
 * a window controller hands an action to its document). Test windows are
 * never key, so the test names the window. */
static id MPMarkedTextTarget(NSWindow *window, SEL action)
{
    for (NSResponder *responder = window.firstResponder; responder;
         responder = responder.nextResponder)
    {
        if ([responder respondsToSelector:action])
            return responder;
        id target = [responder supplementalTargetForAction:action
                                                    sender:nil];
        if (target)
            return target;
    }
    return nil;
}

static NSString *MPMarkedTextState(NSTextView *editor)
{
    NSString *text = [editor.string
        stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return [NSString stringWithFormat:@"\"%@\" %@%@", text,
            NSStringFromRange(editor.selectedRange),
            editor.hasMarkedText ? @" (marked)" : @""];
}

static void MPMarkedTextSetPasteboard(NSString *string)
{
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    [board clearContents];
    [board setString:string forType:NSPasteboardTypeString];
}

static NSArray<NSPasteboardItem *> *MPMarkedTextCopyItems(NSPasteboard *board)
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSPasteboardItem *item in board.pasteboardItems)
    {
        NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
        for (NSPasteboardType type in item.types)
        {
            NSData *data = [item dataForType:type];
            if (data)
                [copy setData:data forType:type];
        }
        [items addObject:copy];
    }
    return items;
}


#pragma mark - Tests

@interface MPMarkedTextEditingTests : XCTestCase
@property (nonatomic, strong) NSArray<NSPasteboardItem *> *savedPasteboard;
@property (nonatomic) BOOL savedEnsuresNewline;
@end

@implementation MPMarkedTextEditingTests

- (void)setUp
{
    [super setUp];
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    self.savedPasteboard = MPMarkedTextCopyItems(board);
    MPMarkedTextSetPasteboard(kMPMarkedTextPlainText);
    MPPreferences *preferences = [MPPreferences sharedInstance];
    self.savedEnsuresNewline = preferences.editorEnsuresNewlineAtEndOfFile;
}

- (void)tearDown
{
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    [board clearContents];
    if (self.savedPasteboard.count)
        [board writeObjects:self.savedPasteboard];
    [MPPreferences sharedInstance].editorEnsuresNewlineAtEndOfFile =
        self.savedEnsuresNewline;
    [super tearDown];
}

/** Puts `composition` at the end of the editor's text, pending, with the
 * input method's selection at `selection` in it. */
- (void)typeComposition:(NSString *)composition selection:(NSRange)selection
             inDocument:(MPDocument *)document
{
    NSWindow *window = document.windowControllers.firstObject.window;
    MPEditorView *editor = document.editor;
    editor.string = kMPMarkedTextTyped;
    editor.selectedRange = NSMakeRange(kMPMarkedTextTyped.length, 0);
    XCTAssertTrue([window makeFirstResponder:editor]);
    [editor setMarkedText:composition selectedRange:selection
         replacementRange:NSMakeRange(NSNotFound, 0)];
    XCTAssertTrue(editor.hasMarkedText, @"precondition");
}

/** Runs `block` with what `action` needs on the general pasteboard: a URL
 * for Paste, which MPEditorView would wrap around a selection as a link,
 * and plain text for everything else, Link and Image included. */
- (void)withPasteboardForAction:(NSString *)action run:(void (^)(void))block
{
    BOOL pastesURL = [action isEqualToString:@"paste:"];
    if (pastesURL)
        MPMarkedTextSetPasteboard(kMPMarkedTextURL);
    @try
    {
        block();
    }
    @finally
    {
        if (pastesURL)
            MPMarkedTextSetPasteboard(kMPMarkedTextPlainText);
    }
}

/** Sends `action` as the menu, toolbar or a key equivalent does. With
 * `commitFirst`, AppKit's own -unmarkText first commits what is pending,
 * as confirming the composition before the command would. */
- (void)sendAction:(NSString *)action toDocument:(MPDocument *)document
       commitFirst:(BOOL)commitFirst
{
    NSWindow *window = document.windowControllers.firstObject.window;
    MPEditorView *editor = document.editor;
    if (commitFirst)
        [editor unmarkText];
    SEL selector = NSSelectorFromString(action);
    // Insert Table is a toolbar item, which sends it to the document.
    id target = [action isEqualToString:@"insertTable:"]
        ? document : MPMarkedTextTarget(window, selector);
    id expected = [action isEqualToString:@"paste:"] ? editor : document;
    XCTAssertEqual(target, expected, @"%@ reaches its handler", action);
    [NSApp sendAction:selector to:target from:nil];
}

/** Each command gives what it gives after the composition is committed:
 * nothing typed is lost, and with a clause selected the command applies
 * at the end of the committed text rather than to the clause. */
- (void)testCommandsCommitPendingComposition
{
    MPDocument *document = [[MPDocument alloc] init];
    @try
    {
        MPLoadDocumentWindow(document);
        MPRunLoopUntil(0.2, ^BOOL{ return NO; });   // queued setup
        for (NSArray *composition in MPMarkedTextCompositions())
        {
            NSRange selection = [composition[1] rangeValue];
            for (NSString *action in MPMarkedTextCommands())
            {
                [self withPasteboardForAction:action run:^{
                    [self typeComposition:composition[0] selection:selection
                               inDocument:document];
                    [self sendAction:action toDocument:document
                         commitFirst:YES];
                    NSString *expected = MPMarkedTextState(document.editor);
                    [self typeComposition:composition[0] selection:selection
                               inDocument:document];
                    [self sendAction:action toDocument:document
                         commitFirst:NO];
                    XCTAssertEqualObjects(MPMarkedTextState(document.editor),
                                          expected,
                                          @"%@ with %@ selected in %@",
                                          action,
                                          NSStringFromRange(selection),
                                          composition[0]);
                }];
                if (document.editor.hasMarkedText)
                    [document.editor unmarkText];
            }
        }
    }
    @finally
    {
        [document close];
    }
}

/** The text and whether undo is possible after `action`, then after each
 * undo until there is nothing left to undo. Typing the composition and
 * the command are separate undo groups, as separate events make them. */
- (NSArray<NSString *> *)undoHistoryOfAction:(NSString *)action
                                 composition:(NSArray *)composition
                                 commitFirst:(BOOL)commitFirst
{
    NSMutableArray *history = [NSMutableArray array];
    MPDocument *document = [[MPDocument alloc] init];
    @try
    {
        MPLoadDocumentWindow(document);
        MPRunLoopUntil(0.2, ^BOOL{ return NO; });
        NSUndoManager *undoManager = document.editor.undoManager;
        XCTAssertNotNil(undoManager);
        [undoManager removeAllActions];
        undoManager.groupsByEvent = NO;
        [undoManager beginUndoGrouping];
        [self typeComposition:composition[0]
                    selection:[composition[1] rangeValue]
                   inDocument:document];
        [undoManager endUndoGrouping];
        [undoManager beginUndoGrouping];
        [self sendAction:action toDocument:document commitFirst:commitFirst];
        [undoManager endUndoGrouping];
        for (NSUInteger i = 0; i < 20; i++)
        {
            [history addObject:[NSString stringWithFormat:@"%@ canUndo=%d",
                                MPMarkedTextState(document.editor),
                                undoManager.canUndo]];
            if (!undoManager.canUndo)
                break;
            [undoManager undo];
        }
    }
    @finally
    {
        [document close];
    }
    return history;
}

/** Undo goes back through the same states as after a commit by AppKit,
 * one step at a time, all the way. */
- (void)testUndoMatchesCommittedComposition
{
    NSArray *actions = @[@"toggleStrong:", @"toggleUnorderedList:",
                         @"convertToH2:", @"indent:", @"insertTable:",
                         @"insertNewParagraph:", @"paste:"];
    for (NSArray *composition in MPMarkedTextCompositions())
    {
        for (NSString *action in actions)
        {
            __block NSArray *expected = nil;
            __block NSArray *actual = nil;
            [self withPasteboardForAction:action run:^{
                expected = [self undoHistoryOfAction:action
                                         composition:composition
                                         commitFirst:YES];
                actual = [self undoHistoryOfAction:action
                                       composition:composition
                                       commitFirst:NO];
            }];
            XCTAssertGreaterThan(expected.count, 1u, @"%@ is undoable",
                                 action);
            XCTAssertEqualObjects(actual, expected, @"%@ with %@", action,
                                  composition[0]);
        }
    }
}

/** The input context hears that the composition ended only while it is
 * active: the view is first responder in the key window. Otherwise the
 * composition is still committed. Counts are relative to AppKit's own
 * -unmarkText, which the commit calls. */
- (void)testDiscardMarkedTextOnlyWhenKeyAndFirstResponder
{
    MPMarkedTextTestWindow *window = [[MPMarkedTextTestWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 400, 200)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    NSView *content = [[NSView alloc] initWithFrame:window.contentLayoutRect];
    window.contentView = content;
    MPMarkedTextSpyView *view = [[MPMarkedTextSpyView alloc]
        initWithFrame:NSMakeRect(0, 0, 200, 200)];
    NSTextView *other = [[NSTextView alloc]
        initWithFrame:NSMakeRect(200, 0, 200, 200)];
    [content addSubview:view];
    [content addSubview:other];

    // [reports key, first responder, discards beyond -unmarkText's own]
    NSArray *cases = @[@[@YES, view, @1], @[@NO, view, @0],
                       @[@YES, other, @0]];
    @try
    {
        for (NSArray *c in cases)
        {
            NSUInteger counts[2] = {0, 0};
            for (NSUInteger viaCommit = 0; viaCommit < 2; viaCommit++)
            {
                window.reportsKey = NO;
                XCTAssertTrue([window makeFirstResponder:c[1]]);
                view.string = @"text ";
                view.selectedRange = NSMakeRange(5, 0);
                [view setMarkedText:@"日本" selectedRange:
                     NSMakeRange(2, 0) replacementRange:
                     NSMakeRange(NSNotFound, 0)];
                XCTAssertTrue(view.hasMarkedText, @"precondition");
                window.reportsKey = [c[0] boolValue];
                NSUInteger before = view.recordingContext.discardCount;
                if (viaCommit)
                    [view commitMarkedText];
                else
                    [view unmarkText];
                counts[viaCommit] = view.recordingContext.discardCount
                    - before;
                XCTAssertFalse(view.hasMarkedText);
                XCTAssertEqualObjects(view.string, @"text 日本");
            }
            XCTAssertEqual(counts[1] - counts[0], [c[2] unsignedIntegerValue],
                           @"key=%@, first responder %@", c[0],
                           NSStringFromClass([c[1] class]));
        }
    }
    @finally
    {
        window.reportsKey = NO;
        [window close];
    }
}

/** With nothing marked, committing makes no input-client calls and
 * leaves the text and selection alone. */
- (void)testCommitWithoutMarkedTextDoesNothing
{
    MPMarkedTextTestWindow *window = [[MPMarkedTextTestWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 400, 200)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    MPMarkedTextSpyView *view = [[MPMarkedTextSpyView alloc]
        initWithFrame:NSMakeRect(0, 0, 400, 200)];
    window.contentView = view;
    @try
    {
        XCTAssertTrue([window makeFirstResponder:view]);
        window.reportsKey = YES;
        view.string = @"some text";
        view.selectedRange = NSMakeRange(5, 4);
        (void)view.inputContext;
        view.unmarkCount = 0;
        view.setMarkedCount = 0;

        [view commitMarkedText];

        XCTAssertEqual(view.unmarkCount, 0u);
        XCTAssertEqual(view.setMarkedCount, 0u);
        XCTAssertEqual(view.recordingContext.discardCount, 0u);
        XCTAssertEqualObjects(view.string, @"some text");
        XCTAssertEqualObjects(NSStringFromRange(view.selectedRange),
                              NSStringFromRange(NSMakeRange(5, 4)));
    }
    @finally
    {
        window.reportsKey = NO;
        [window close];
    }
}

/** A save with a composition pending writes the text as shown and leaves
 * the composition pending, so "Ensure newline at end of file" adds
 * nothing then; the next save without one adds the newline. */
- (void)testSaveLeavesPendingCompositionAlone
{
    [MPPreferences sharedInstance].editorEnsuresNewlineAtEndOfFile = YES;
    NSString *name = [NSString stringWithFormat:@"MPMarkedText-%@.md",
                      [NSUUID UUID].UUIDString];
    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSString *type = @"net.daringfireball.markdown";
    MPDocument *document = [[MPDocument alloc] init];
    @try
    {
        NSWindow *window = MPLoadDocumentWindow(document);
        MPRunLoopUntil(0.2, ^BOOL{ return NO; });
        MPEditorView *editor = document.editor;
        editor.string = kMPMarkedTextTyped;
        editor.selectedRange = NSMakeRange(kMPMarkedTextTyped.length, 0);
        XCTAssertTrue([window makeFirstResponder:editor]);
        [editor setMarkedText:@"日本語"
                selectedRange:NSMakeRange(3, 0)
             replacementRange:NSMakeRange(NSNotFound, 0)];
        NSString *shown = [editor.string copy];
        NSRange selection = editor.selectedRange;
        NSRange marked = editor.markedRange;

        NSError *error = nil;
        XCTAssertTrue([document writeToURL:url ofType:type error:&error],
                      @"%@", error);
        XCTAssertEqualObjects(editor.string, shown);
        XCTAssertTrue(editor.hasMarkedText, @"the composition is pending");
        XCTAssertEqualObjects(NSStringFromRange(editor.markedRange),
                              NSStringFromRange(marked));
        XCTAssertEqualObjects(NSStringFromRange(editor.selectedRange),
                              NSStringFromRange(selection));
        NSString *written = [NSString stringWithContentsOfURL:url
            encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertEqualObjects(written, shown);

        [editor unmarkText];
        XCTAssertTrue([document writeToURL:url ofType:type error:&error],
                      @"%@", error);
        written = [NSString stringWithContentsOfURL:url
            encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertEqualObjects(written, [shown stringByAppendingString:@"\n"]);
    }
    @finally
    {
        [document close];
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }
}

@end
