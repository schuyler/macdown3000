//
//  MPExternalChangeReloadTests.m
//  MacDownTests
//
//  Tests for how MPDocument reacts to changes made to the open file by another
//  application: how many notifications survive to become a decision, whether
//  that decision is a dialog or a silent reload, and what happens to the caret.
//
//  Created for Issue #543: Reduce number of popup 'keep/discard' dialogs.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPPreferences.h"
#import "MPRenderer.h"
#import "MPEditorView.h"
#import "HGMarkdownHighlighter.h"


#pragma mark - Test Infrastructure

// Expose the private external-change machinery under test.
@interface MPDocument (ExternalChangeTesting)
@property (nonatomic) BOOL isSelfSaving;
@property (nonatomic) BOOL externalChangeCoalescePending;
@property (nonatomic) BOOL externalChangePromptVisible;
@property (nonatomic) NSTimeInterval externalChangeCoalesceInterval;
@property (nonatomic, copy) void (^externalChangePromptPresenter)(void (^)(BOOL));
@property (strong) MPRenderer *renderer;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (weak) MPEditorView *editor;
@property (copy) NSString *loadedString;
- (void)handleExternalFileChange;
- (void)processExternalFileChange;
- (BOOL)shouldPromptBeforeReloadingExternalChanges;
- (void)promptForReloadWithExternalChanges;
- (void)reloadFromDisk;
- (void)reloadFromLoadedString;
+ (NSRange)selectionRange:(NSRange)range clampedToLength:(NSUInteger)length;
@end


// Counts the decisions that survive coalescing, without performing any of the
// file I/O a real decision would.
@interface MPCoalescingSpyDocument : MPDocument
@property (nonatomic) NSUInteger processCount;
@end

@implementation MPCoalescingSpyDocument
- (void)processExternalFileChange { self.processCount++; }
@end


// Counts reloads and lets a test dictate the document's dirty state, so the
// prompt/silent decision can be driven directly.
@interface MPPromptSpyDocument : MPDocument
@property (nonatomic) NSUInteger reloadCount;
@property (nonatomic) BOOL stubbedDocumentEdited;
@end

@implementation MPPromptSpyDocument
- (void)reloadFromDisk { self.reloadCount++; }
- (BOOL)isDocumentEdited { return self.stubbedDocumentEdited; }
@end


// Renderer and highlighter stand-ins, so reloadFromLoadedString's
// (editor && renderer && highlighter) guard is satisfied without kicking off
// real background work.
@interface MPInertRenderer : MPRenderer
@end

@implementation MPInertRenderer
- (void)parseAndRenderNow {}
@end

@interface MPInertHighlighter : HGMarkdownHighlighter
@end

@implementation MPInertHighlighter
- (void)parseAndHighlightNow {}
- (void)clearHighlighting {}
- (void)readClearTextStylesFromTextView {}
@end


@interface MPExternalChangeReloadTests : XCTestCase
@property (strong) MPEditorView *editor;
@end


@implementation MPExternalChangeReloadTests

// dispatch_after targets the main queue, and XCTest runs on the main thread, so
// the queue is only drained while the run loop is spinning.
- (void)spinRunLoopForInterval:(NSTimeInterval)interval
{
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
}

- (MPCoalescingSpyDocument *)coalescingDocument
{
    MPCoalescingSpyDocument *doc = [[MPCoalescingSpyDocument alloc] init];
    doc.externalChangeCoalesceInterval = 0.02;
    return doc;
}

// Wires the three collaborators reloadFromLoadedString requires. The editor is
// a weak property on MPDocument, so the test case holds it alive.
- (void)wireEditorInto:(MPDocument *)doc
{
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    self.editor = editor;
    doc.editor = editor;
    doc.renderer = [[MPInertRenderer alloc] init];
    doc.highlighter = [[MPInertHighlighter alloc] initWithTextView:editor
                                                      waitInterval:0.0];
}

- (void)tearDown
{
    self.editor = nil;
    [super tearDown];
}


#pragma mark - Coalescing of Watcher Notifications (Issue #543, point 1)

// A chunked external save arrives as several vnode write notifications. They
// should produce one decision, not one per chunk.
- (void)testBurstOfNotificationsProducesASingleDecision
{
    MPCoalescingSpyDocument *doc = [self coalescingDocument];

    for (NSUInteger i = 0; i < 5; i++)
        [doc handleExternalFileChange];

    [self spinRunLoopForInterval:0.2];

    XCTAssertEqual(doc.processCount, 1u,
                   @"Five notifications inside the coalescing window must "
                    "collapse into one reload decision");
}

// Coalescing must not swallow genuinely separate saves — once the window has
// closed, the next notification gets its own decision.
- (void)testNotificationAfterCoalescingWindowProducesAnotherDecision
{
    MPCoalescingSpyDocument *doc = [self coalescingDocument];

    [doc handleExternalFileChange];
    [self spinRunLoopForInterval:0.2];
    [doc handleExternalFileChange];
    [self spinRunLoopForInterval:0.2];

    XCTAssertEqual(doc.processCount, 2u,
                   @"A notification arriving after the window closed is a "
                    "separate save and deserves its own decision");
}

// The reporter's core complaint: changes that land while the dialog is up must
// not be remembered and replayed as further dialogs.
- (void)testNotificationsAreDroppedWhileThePromptIsVisible
{
    MPCoalescingSpyDocument *doc = [self coalescingDocument];
    doc.externalChangePromptVisible = YES;

    for (NSUInteger i = 0; i < 3; i++)
        [doc handleExternalFileChange];

    [self spinRunLoopForInterval:0.2];

    XCTAssertEqual(doc.processCount, 0u,
                   @"While a keep/discard dialog is pending, further changes "
                    "must be dropped rather than queued behind it");
}

// Once the user answers, the document must be responsive to new changes again.
- (void)testNotificationsResumeAfterThePromptIsDismissed
{
    MPCoalescingSpyDocument *doc = [self coalescingDocument];
    doc.externalChangePromptVisible = YES;
    [doc handleExternalFileChange];
    [self spinRunLoopForInterval:0.1];

    doc.externalChangePromptVisible = NO;
    [doc handleExternalFileChange];
    [self spinRunLoopForInterval:0.2];

    XCTAssertEqual(doc.processCount, 1u,
                   @"Dropping notifications must stop as soon as the dialog "
                    "is dismissed");
}

// Pre-existing behaviour (issue #290) that the rewrite must not lose: our own
// writes are not external changes.
- (void)testSelfSaveNotificationsAreIgnored
{
    MPCoalescingSpyDocument *doc = [self coalescingDocument];
    doc.isSelfSaving = YES;

    [doc handleExternalFileChange];
    [self spinRunLoopForInterval:0.2];

    XCTAssertEqual(doc.processCount, 0u,
                   @"A notification raised by the document's own save must not "
                    "trigger a reload decision");
}


#pragma mark - Prompt Re-entrancy (Issue #543, point 1)

// AppKit queues sheets rather than collapsing them, so the guard has to live in
// MacDown rather than being left to the frameworks.
- (void)testOnlyOnePromptIsPresentedWhileOneIsOutstanding
{
    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    __block NSUInteger presentCount = 0;
    doc.externalChangePromptPresenter = ^(void (^completion)(BOOL)) {
        // Deliberately never invoked: models a dialog still awaiting an answer.
        (void)completion;
        presentCount++;
    };

    [doc promptForReloadWithExternalChanges];
    [doc promptForReloadWithExternalChanges];
    [doc promptForReloadWithExternalChanges];

    XCTAssertEqual(presentCount, 1u,
                   @"A second dialog must not be presented while the first is "
                    "still awaiting an answer");
}

- (void)testPromptCanBePresentedAgainAfterItIsAnswered
{
    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    __block NSUInteger presentCount = 0;
    __block void (^pendingCompletion)(BOOL) = nil;
    doc.externalChangePromptPresenter = ^(void (^completion)(BOOL)) {
        presentCount++;
        pendingCompletion = [completion copy];
    };

    [doc promptForReloadWithExternalChanges];
    pendingCompletion(NO);                       // user chose "Keep"
    [doc promptForReloadWithExternalChanges];

    XCTAssertEqual(presentCount, 2u,
                   @"A change arriving after the dialog was answered must be "
                    "able to raise a new dialog");
}

- (void)testDiscardReloadsFromDisk
{
    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.externalChangePromptPresenter = ^(void (^completion)(BOOL)) {
        completion(YES);
    };

    [doc promptForReloadWithExternalChanges];

    XCTAssertEqual(doc.reloadCount, 1u,
                   @"Choosing Discard must reload the file from disk");
    XCTAssertFalse(doc.externalChangePromptVisible,
                   @"The guard must be cleared once the dialog is answered");
}

- (void)testKeepLeavesTheEditorAlone
{
    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.externalChangePromptPresenter = ^(void (^completion)(BOOL)) {
        completion(NO);
    };

    [doc promptForReloadWithExternalChanges];

    XCTAssertEqual(doc.reloadCount, 0u,
                   @"Choosing Keep must leave the editor's contents untouched");
    XCTAssertFalse(doc.externalChangePromptVisible,
                   @"The guard must be cleared once the dialog is answered");
}


#pragma mark - Prompt vs. Silent Reload (Issue #543, point 2)

// The regression this issue reports: Auto Save off used to force a dialog even
// when the document was pristine and there was nothing to keep.
- (void)testCleanDocumentDoesNotPromptWhenAutoSaveIsOff
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;
    prefs.editorAutoSave = NO;

    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.stubbedDocumentEdited = NO;

    XCTAssertFalse([doc shouldPromptBeforeReloadingExternalChanges],
                   @"An unmodified document has nothing to lose, so an external "
                    "change should reload silently even with Auto Save off");

    prefs.editorAutoSave = original;
}

- (void)testCleanDocumentDoesNotPromptWhenAutoSaveIsOn
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;
    prefs.editorAutoSave = YES;

    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.stubbedDocumentEdited = NO;

    XCTAssertFalse([doc shouldPromptBeforeReloadingExternalChanges],
                   @"An unmodified document should reload silently");

    prefs.editorAutoSave = original;
}

// The other half of the contract: unsaved work must still be defended, and the
// Auto Save setting must not change that either way.
- (void)testEditedDocumentPromptsRegardlessOfAutoSaveSetting
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;

    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.stubbedDocumentEdited = YES;

    prefs.editorAutoSave = YES;
    XCTAssertTrue([doc shouldPromptBeforeReloadingExternalChanges],
                  @"Unsaved changes must always be defended by a dialog");

    prefs.editorAutoSave = NO;
    XCTAssertTrue([doc shouldPromptBeforeReloadingExternalChanges],
                  @"Unsaved changes must always be defended by a dialog");

    prefs.editorAutoSave = original;
}


#pragma mark - Selection Clamping (Issue #543)

- (void)testSelectionRangeInsideDocumentIsUnchanged
{
    NSRange result = [MPDocument selectionRange:NSMakeRange(4, 6)
                                clampedToLength:20];
    XCTAssertEqual(result.location, 4u);
    XCTAssertEqual(result.length, 6u);
}

- (void)testSelectionRangeAtVeryEndIsUnchanged
{
    NSRange result = [MPDocument selectionRange:NSMakeRange(10, 0)
                                clampedToLength:10];
    XCTAssertEqual(result.location, 10u);
    XCTAssertEqual(result.length, 0u);
}

- (void)testSelectionRangeBeyondEndCollapsesToEnd
{
    NSRange result = [MPDocument selectionRange:NSMakeRange(50, 3)
                                clampedToLength:10];
    XCTAssertEqual(result.location, 10u,
                   @"A caret past the end of the shortened file lands on the "
                    "last character position");
    XCTAssertEqual(result.length, 0u,
                   @"There is nothing left to select past the end");
}

- (void)testSelectionRangeOverrunningEndIsTruncated
{
    NSRange result = [MPDocument selectionRange:NSMakeRange(6, 30)
                                clampedToLength:10];
    XCTAssertEqual(result.location, 6u);
    XCTAssertEqual(result.length, 4u,
                   @"A selection that runs off the end is cut back to the "
                    "remaining text");
}

- (void)testSelectionRangeIntoAnEmptyDocumentCollapsesToZero
{
    NSRange result = [MPDocument selectionRange:NSMakeRange(7, 2)
                                clampedToLength:0];
    XCTAssertEqual(result.location, 0u);
    XCTAssertEqual(result.length, 0u);
}

- (void)testNotFoundSelectionRangeCollapsesToZero
{
    NSRange result = [MPDocument selectionRange:NSMakeRange(NSNotFound, 0)
                                clampedToLength:10];
    XCTAssertEqual(result.location, 0u,
                   @"An absent selection must not be clamped to the end of the "
                    "document");
    XCTAssertEqual(result.length, 0u);
}


#pragma mark - Caret Preservation Across Reload (Issue #543)

- (void)testReloadKeepsTheCaretWhereItWas
{
    MPDocument *doc = [[MPDocument alloc] init];
    [self wireEditorInto:doc];
    self.editor.string = @"# Title\n\nOriginal body text.\n";
    self.editor.selectedRange = NSMakeRange(12, 0);

    doc.loadedString = @"# Title\n\nBody text changed by another app.\n";
    [doc reloadFromLoadedString];

    XCTAssertEqual(self.editor.selectedRange.location, 12u,
                   @"A silent reload must not throw the caret back to the top "
                    "of the document");
}

- (void)testReloadKeepsAnActiveSelection
{
    MPDocument *doc = [[MPDocument alloc] init];
    [self wireEditorInto:doc];
    self.editor.string = @"abcdefghijklmnopqrstuvwxyz";
    self.editor.selectedRange = NSMakeRange(3, 5);

    doc.loadedString = @"abcdefghijklmnopqrstuvwxyz0123456789";
    [doc reloadFromLoadedString];

    XCTAssertEqual(self.editor.selectedRange.location, 3u);
    XCTAssertEqual(self.editor.selectedRange.length, 5u,
                   @"An active selection should survive a reload that leaves "
                    "its range in bounds");
}

- (void)testReloadClampsTheCaretWhenTheFileShrinks
{
    MPDocument *doc = [[MPDocument alloc] init];
    [self wireEditorInto:doc];
    self.editor.string = @"A long line of text that is about to get shorter.";
    self.editor.selectedRange = NSMakeRange(40, 0);

    doc.loadedString = @"Short.";
    [doc reloadFromLoadedString];

    XCTAssertEqual(self.editor.selectedRange.location, 6u,
                   @"A caret beyond the new end of file must be clamped to the "
                    "end rather than left out of bounds");
    XCTAssertEqualObjects(self.editor.string, @"Short.",
                          @"The reloaded content must still be applied");
}

// The editor is untouched on this path, so there is no prior caret to keep and
// nothing should blow up.
- (void)testReloadWithoutLoadedStringLeavesTheCaretAlone
{
    MPDocument *doc = [[MPDocument alloc] init];
    [self wireEditorInto:doc];
    self.editor.string = @"Unchanged content";
    self.editor.selectedRange = NSMakeRange(5, 2);

    doc.loadedString = nil;
    XCTAssertNoThrow([doc reloadFromLoadedString]);

    XCTAssertEqual(self.editor.selectedRange.location, 5u);
    XCTAssertEqual(self.editor.selectedRange.length, 2u);
}

@end
