//
//  MPEditorViewPasteboardTests.m
//  MacDown 3000
//
//  Tests for Issue #571: MPEditorView writes a custom pasteboard flavor
//  (net.daringfireball.markdown) alongside plain text on every copy/cut.
//  That flavor's UTI conforms to both public.text and public.data with a
//  registered filename extension, which causes Messages.app to materialize
//  copied text as a file attachment instead of pasting it inline.
//
//  The approved fix stops writing net.daringfireball.markdown and instead
//  writes app.macdown.markdown-interop, a type with no filename-extension
//  registration.
//
//  Tests for issue #571: verify MPEditorView's pasteboard-writing methods no
//  longer advertise a file-representable Markdown UTI on copy/cut.
//

#import <XCTest/XCTest.h>
#import <CoreServices/CoreServices.h>
#import "MPEditorView.h"

static NSString * const kOldMarkdownPasteboardType = @"net.daringfireball.markdown";
static NSString * const kNewMarkdownInteropPasteboardType = @"app.macdown.markdown-interop";

@interface MPEditorViewPasteboardTests : XCTestCase
@property (strong) MPEditorView *editorView;
@property (strong) NSPasteboard *pasteboard;
@end

@implementation MPEditorViewPasteboardTests

- (void)setUp
{
    [super setUp];
    self.editorView = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    self.pasteboard = [NSPasteboard pasteboardWithName:@"MPEditorViewPasteboardTestPB"];
    [self.pasteboard clearContents];
}

- (void)tearDown
{
    [self.pasteboard clearContents];
    self.pasteboard = nil;
    self.editorView = nil;
    [super tearDown];
}

#pragma mark - writablePasteboardTypes

- (void)testWritablePasteboardTypesNoLongerAdvertisesOldMarkdownType
{
    XCTAssertFalse([[self.editorView writablePasteboardTypes] containsObject:kOldMarkdownPasteboardType]);
}

- (void)testWritablePasteboardTypesAdvertisesNewInteropType
{
    XCTAssertTrue([[self.editorView writablePasteboardTypes] containsObject:kNewMarkdownInteropPasteboardType]);
}

- (void)testWriteSelectionToPasteboardOmitsInteropTypeWhenNotRequested
{
    self.editorView.string = @"Hello World";
    self.editorView.selectedRange = NSMakeRange(0, self.editorView.string.length);
    NSMutableArray<NSPasteboardType> *typesWithoutInterop = [[self.editorView writablePasteboardTypes] mutableCopy];
    [typesWithoutInterop removeObject:kNewMarkdownInteropPasteboardType];
    BOOL success = [self.editorView writeSelectionToPasteboard:self.pasteboard types:typesWithoutInterop];
    XCTAssertTrue(success);
    XCTAssertFalse([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
    XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
}

#pragma mark - writeSelectionToPasteboard:types:

- (void)testFullSelectionCopyWritesOnlyNewInteropType
{
    self.editorView.string = @"# Hello\n\nWorld";
    self.editorView.selectedRange = NSMakeRange(0, self.editorView.string.length);
    NSArray<NSPasteboardType> *types = [self.editorView writablePasteboardTypes];
    BOOL success = [self.editorView writeSelectionToPasteboard:self.pasteboard types:types];
    XCTAssertTrue(success);
    XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
    XCTAssertTrue([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
    NSString *interopText = [[NSString alloc] initWithData:[self.pasteboard dataForType:kNewMarkdownInteropPasteboardType] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(interopText, @"# Hello\n\nWorld");
    XCTAssertEqualObjects([self.pasteboard stringForType:NSPasteboardTypeString], @"# Hello\n\nWorld");
}

- (void)testPartialSelectionCopyWritesOnlyNewInteropType
{
    self.editorView.string = @"Hello World";
    self.editorView.selectedRange = NSMakeRange(6, 5);
    NSArray<NSPasteboardType> *types = [self.editorView writablePasteboardTypes];
    BOOL success = [self.editorView writeSelectionToPasteboard:self.pasteboard types:types];
    XCTAssertTrue(success);
    XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
    XCTAssertTrue([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
    NSString *interopText = [[NSString alloc] initWithData:[self.pasteboard dataForType:kNewMarkdownInteropPasteboardType] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(interopText, @"World");
    XCTAssertEqualObjects([self.pasteboard stringForType:NSPasteboardTypeString], @"World");
}

// Exercises the same -writeSelectionToPasteboard:types: path that AppKit's
// cut: shares with copy: (MPEditorView doesn't override cut:/copy:
// separately); this test does not itself invoke -cut: or verify the
// subsequent deletion of the selection.
- (void)testCutSelectionWritesOnlyNewInteropType
{
    self.editorView.string = @"abcdef";
    self.editorView.selectedRange = NSMakeRange(1, 3);
    NSArray<NSPasteboardType> *types = [self.editorView writablePasteboardTypes];
    BOOL success = [self.editorView writeSelectionToPasteboard:self.pasteboard types:types];
    XCTAssertTrue(success);
    XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
    XCTAssertTrue([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
    NSString *interopText = [[NSString alloc] initWithData:[self.pasteboard dataForType:kNewMarkdownInteropPasteboardType] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(interopText, @"bcd");
    XCTAssertEqualObjects([self.pasteboard stringForType:NSPasteboardTypeString], @"bcd");
}

- (void)testEmptySelectionOnEmptyDocumentCopyBehavior
{
    self.editorView.string = @"";
    self.editorView.selectedRange = NSMakeRange(0, 0);
    NSArray<NSPasteboardType> *types = [self.editorView writablePasteboardTypes];
    BOOL success = [self.editorView writeSelectionToPasteboard:self.pasteboard types:types];

    // Regardless of what AppKit's stock -writeSelectionToPasteboard:types:
    // does with a zero-length selection on an empty document, MacDown must
    // never advertise the old markdown UTI (issue #571's regression guard).
    // This is the one invariant this test always enforces.
    XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);

    if (!success) {
        // Superclass declined to report success for a zero-length selection
        // on an empty document. NSPasteboard's `.types` reflects declared
        // type NAMES independently of whether data was ever written for
        // them, so AppKit's own writeSelectionToPasteboard:types: may leave
        // kNewMarkdownInteropPasteboardType listed in .types even though it
        // never produced real content. MacDown's own code that writes
        // interop DATA only runs when `success` is YES (see the
        // `if (success && ...)` guard in -[MPEditorView
        // writeSelectionToPasteboard:types:]), so it cannot have executed on
        // this path. What matters for issue #571 is that no interop DATA
        // exists here.
        NSData *interopData = [self.pasteboard dataForType:kNewMarkdownInteropPasteboardType];
        XCTAssertNil(interopData, @"no interop data should be written when the underlying write reports failure");
        return;
    }

    if (![self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]) {
        // AppKit's stock implementation reported success but performed a
        // vacuous write for the zero-length selection, establishing no
        // pasteboard entry for types it doesn't natively recognize
        // (including our custom interop UTI). This is real, observed AppKit
        // behavior for a code path unreachable through normal copy UI
        // (Copy is disabled with no selection), not a MacDown defect -- the
        // old-type guard above already covers the behavior MacDown controls.
        return;
    }

    // AppKit performed a full write and our type made it onto the
    // pasteboard: verify its content is the (empty) selection.
    NSString *interopText = [[NSString alloc] initWithData:[self.pasteboard dataForType:kNewMarkdownInteropPasteboardType] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(interopText, @"");
}

- (void)testSingleCharacterSelectionCopyWritesOnlyNewInteropType
{
    self.editorView.string = @"X";
    self.editorView.selectedRange = NSMakeRange(0, 1);
    NSArray<NSPasteboardType> *types = [self.editorView writablePasteboardTypes];
    BOOL success = [self.editorView writeSelectionToPasteboard:self.pasteboard types:types];
    XCTAssertTrue(success);
    XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
    XCTAssertTrue([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
    NSString *interopText = [[NSString alloc] initWithData:[self.pasteboard dataForType:kNewMarkdownInteropPasteboardType] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(interopText, @"X");
    XCTAssertEqualObjects([self.pasteboard stringForType:NSPasteboardTypeString], @"X");
}

#pragma mark - UTI declaration

// This test passes both before and after the fix (no Info.plist change in this
// design); it exists purely as a regression guard against ever registering a
// filename extension for the interop type.
- (void)testNewInteropTypeHasNoRegisteredFilenameExtension
{
    CFStringRef ext = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)kNewMarkdownInteropPasteboardType, kUTTagClassFilenameExtension);
    NSString *extension = (__bridge_transfer NSString *)ext;
    XCTAssertNil(extension, @"the interop type must have no registered filename extension");
}

- (NSString *)pasteExternalMarkdown:(NSString *)text
{
    [self.pasteboard setString:text forType:NSPasteboardTypeString];
    XCTAssertTrue([self.editorView readSelectionFromPasteboard:self.pasteboard type:NSPasteboardTypeString]);
    return self.editorView.string;
}

- (void)testNotionAsidePasteRemovesFormerIndentationAndPreservesFencedMessage
{
    NSString *copied=@"            <aside>\n            💡\n            \n            **Consigne**\n            ```jsx\n            Bonjour,\n            \n            Message.\n            ```\n            </aside>\n";
    NSString *expected=@"::: {.callout-tip}\n💡\n\n**Consigne**\n```jsx\nBonjour,\n\nMessage.\n```\n:::\n";
    XCTAssertEqualObjects([self pasteExternalMarkdown:copied],expected);
}

- (void)testNotionPastePreservesNestedListsMultipleContainersAndLineEndings
{
    for (NSString *ending in @[@"\n",@"\r\n"]) {
        NSString *copied=[@"Before\n\n- Action\n    <aside>\n    ⚠️\n    - Detail\n    </aside>\n\n<aside>\nOther\n<aside>\nNested\n</aside>\n</aside>\n" stringByReplacingOccurrencesOfString:@"\n" withString:ending];
        NSString *expected=[@"Before\n\n- Action\n    ::: {.callout-warning}\n    ⚠️\n    - Detail\n    :::\n\n::: {.callout-note}\nOther\n::: {.callout-note}\nNested\n:::\n:::\n" stringByReplacingOccurrencesOfString:@"\n" withString:ending];
        self.editorView.string=@"";
        XCTAssertEqualObjects([self pasteExternalMarkdown:copied],expected);
    }
}

- (void)testLiteralAndMalformedAsidesRemainUnchangedOnPaste
{
    for (NSString *source in @[@"```html\n<aside>\nExample\n</aside>\n```",@"~~~html\n<aside>\nExample\n</aside>\n~~~",@"`<aside>`",@"``\n<aside>\nExample\n</aside>\n``",@"<aside>\nUnclosed",@"</aside>\nUnmatched",@"<aside>\n<aside>\nPartial\n</aside>",@"<aside class=\"custom\">Body</aside>"]) {
        self.editorView.string=@"";
        XCTAssertEqualObjects([self pasteExternalMarkdown:source],source);
    }
}

- (void)testPasteIntoExistingCodeDoesNotConvertAsides
{
    NSString *copied=@"<aside>\n💡\nBody\n</aside>";
    for (NSString *prefix in @[@"```html\n",@"~~~\n",@"A `",@"A ``",@"A ``\n",@"- Action\n\n        ",@"    ",@"\t"]) {
        self.editorView.string=prefix;
        self.editorView.selectedRange=NSMakeRange(prefix.length,0);
        NSString *expected=[prefix stringByAppendingString:copied];
        XCTAssertEqualObjects([self pasteExternalMarkdown:copied],expected);
    }
}

- (void)testPasteAtListContinuationCarriesIndentationToEveryLine
{
    self.editorView.string=@"- Action\n\n    ";
    self.editorView.selectedRange=NSMakeRange(self.editorView.string.length,0);
    XCTAssertEqualObjects([self pasteExternalMarkdown:@"<aside>\n💡\nBody\n</aside>"],@"- Action\n\n    ::: {.callout-tip}\n    💡\n    Body\n    :::");
}

- (void)testInternalMarkdownCopiesKeepLiteralAsides
{
    NSString *source=@"<aside>\nOriginal HTML\n</aside>";
    [self.pasteboard setData:[source dataUsingEncoding:NSUTF8StringEncoding] forType:kNewMarkdownInteropPasteboardType];
    XCTAssertEqualObjects([self pasteExternalMarkdown:source],source);
}

- (void)testConvertedPasteReplacesOnlySelectionAndCanBeUndone
{
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;window.contentView=self.editorView;
    self.editorView.allowsUndo=YES;
    self.editorView.string=@"Before OLD after";
    self.editorView.selectedRange=NSMakeRange(7,3);
    XCTAssertEqualObjects([self pasteExternalMarkdown:@"<aside>\nBody\n</aside>"],@"Before \n\n::: {.callout-note}\nBody\n:::\n\n after");
    [self.editorView.undoManager undo];
    XCTAssertEqualObjects(self.editorView.string,@"Before OLD after");
    window.contentView=nil;[window close];
}

- (void)testNativePasteboardReadConvertsMultipleAsidesWithRichClipboardFlavors
{
    NSString *source=@"# Procedure\n\n- Parent\n    - Action\n\n        <aside>\n        💡\n\n        **Consigne**\n\n        ```jsx\n        Message.\n        ```\n\n        </aside>\n\n    - Next\n\n<aside>\nNote\n</aside>";
    self.editorView.richText=NO;
    [self.pasteboard setString:source forType:NSPasteboardTypeString];
    [self.pasteboard setString:@"<html><body>Rich clipboard representation</body></html>" forType:NSPasteboardTypeHTML];
    XCTAssertTrue([self.editorView readSelectionFromPasteboard:self.pasteboard]);
    XCTAssertFalse([self.editorView.string containsString:@"<aside>"]);
    XCTAssertTrue([self.editorView.string containsString:@"        ::: {.callout-tip}"]);
    XCTAssertTrue([self.editorView.string containsString:@"        ```jsx\n        Message.\n        ```"]);
    XCTAssertTrue([self.editorView.string hasSuffix:@"::: {.callout-note}\nNote\n:::"]);
}

- (void)testNormalPasteAndPasteMatchingStyleConvertAsidesAndSupportUndo
{
    NSPasteboard *board=NSPasteboard.generalPasteboard;
    NSMutableArray *saved=[NSMutableArray array];
    for (NSPasteboardItem *item in board.pasteboardItems) {
        NSPasteboardItem *copy=[[NSPasteboardItem alloc] init];
        for (NSString *type in item.types) {
            NSData *data=[item dataForType:type];
            if (data) [copy setData:data forType:type];
        }
        [saved addObject:copy];
    }
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;window.contentView=self.editorView;
    self.editorView.richText=NO;self.editorView.allowsUndo=YES;
    NSInteger ownedChangeCount=board.changeCount;
    @try {
        for (NSUInteger action=0;action<2;action++) {
            [board clearContents];
            [board setString:@"            <aside>\n            💡\n            Body\n            </aside>" forType:NSPasteboardTypeString];
            [board setString:@"<html><body>Body</body></html>" forType:NSPasteboardTypeHTML];
            ownedChangeCount=board.changeCount;
            self.editorView.string=@"Before\n\nOLD\n\nAfter";
            self.editorView.selectedRange=NSMakeRange(8,3);
            [self.editorView.undoManager removeAllActions];
            if (action) [self.editorView pasteAsPlainText:nil];else [self.editorView paste:nil];
            XCTAssertEqualObjects(self.editorView.string,@"Before\n\n::: {.callout-tip}\n💡\nBody\n:::\n\nAfter");
            [self.editorView.undoManager undo];
            XCTAssertEqualObjects(self.editorView.string,@"Before\n\nOLD\n\nAfter");
        }
    } @finally {
        if (board.changeCount==ownedChangeCount) {
            [board clearContents];
            if (saved.count) [board writeObjects:saved];
        }
        window.contentView=nil;[window close];
    }
}

@end
