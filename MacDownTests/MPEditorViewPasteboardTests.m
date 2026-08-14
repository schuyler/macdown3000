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
//  TDD: These tests are designed to FAIL until the fix is implemented in
//  MPEditorView.
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

// Exercises the same shared write path AppKit's cut: uses (copy-then-delete),
// since MPEditorView doesn't override cut:/copy: separately.
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
    if (success) {
        XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
        XCTAssertTrue([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
        NSString *interopText = [[NSString alloc] initWithData:[self.pasteboard dataForType:kNewMarkdownInteropPasteboardType] encoding:NSUTF8StringEncoding];
        XCTAssertEqualObjects(interopText, @"");
    } else {
        XCTAssertFalse([self.pasteboard.types containsObject:kOldMarkdownPasteboardType]);
        XCTAssertFalse([self.pasteboard.types containsObject:kNewMarkdownInteropPasteboardType]);
    }
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

@end
