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
@property (nonatomic) NSUInteger externalReloadScrollGeneration;
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


// Runs the real -processExternalFileChange, but counts the two outcomes it can
// reach instead of touching disk or showing a sheet. This lets the decision
// method's own guards (self-save re-check, file-URL guard, modification-date
// check, prompt-vs-silent branch) be exercised end-to-end rather than only in
// isolated pieces.
@interface MPProcessSpyDocument : MPDocument
@property (nonatomic) NSUInteger reloadCount;
@property (nonatomic) NSUInteger promptCount;
@property (nonatomic) BOOL stubbedDocumentEdited;
@end

@implementation MPProcessSpyDocument
- (void)reloadFromDisk { self.reloadCount++; }
- (void)promptForReloadWithExternalChanges { self.promptCount++; }
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
@property (strong) NSScrollView *scrollView;
@end


@implementation MPExternalChangeReloadTests

// dispatch_after targets the main queue, and XCTest runs on the main thread, so
// the queue is only drained while the run loop is spinning.
- (void)spinRunLoopForInterval:(NSTimeInterval)interval
{
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
}

// A fixed-duration spin assumes the coalescing window reliably elapses within
// some fixed margin over externalChangeCoalesceInterval. Under a loaded or
// coverage-instrumented CI runner that margin isn't reliable, and the spin can
// expire before dispatch_after's block has actually run — this polls in short
// increments instead, returning as soon as the count is reached (or the
// generous timeout is, whichever comes first), so the common case is still
// fast and a slow one doesn't produce a false failure.
- (void)waitForProcessCount:(NSUInteger)count
                  onDocument:(MPCoalescingSpyDocument *)doc
                     timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (doc.processCount < count && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop]
            runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
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

// Embeds the editor in a real NSScrollView so reloadFromLoadedString's
// scroll-restoration branch (only taken when the editor has an enclosing scroll
// view) is actually entered. Returns the scroll view for the caller to drive.
- (NSScrollView *)wireScrollableEditorInto:(MPDocument *)doc
{
    NSScrollView *scrollView =
        [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    scrollView.hasVerticalScroller = YES;
    MPEditorView *editor =
        [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    editor.verticallyResizable = YES;
    editor.horizontallyResizable = NO;
    scrollView.documentView = editor;

    // The scroll view must outlive this method: reloadFromLoadedString only
    // takes its restoration branch while editor.enclosingScrollView is non-nil.
    self.scrollView = scrollView;
    self.editor = editor;
    doc.editor = editor;
    doc.renderer = [[MPInertRenderer alloc] init];
    doc.highlighter = [[MPInertHighlighter alloc] initWithTextView:editor
                                                      waitInterval:0.0];
    return scrollView;
}

// Writes a throwaway file and schedules its removal, returning its URL. Used by
// the tests that drive the real -processExternalFileChange, which reads the
// file's on-disk modification date.
- (NSURL *)writeTempFileWithContents:(NSString *)contents
{
    NSString *name = [NSString stringWithFormat:@"MPExtChange-%@.md",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                  URLByAppendingPathComponent:name];
    [contents writeToURL:url atomically:YES
                encoding:NSUTF8StringEncoding error:NULL];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }];
    return url;
}

- (void)tearDown
{
    self.editor = nil;
    self.scrollView = nil;
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

    [self waitForProcessCount:1 onDocument:doc timeout:5.0];

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
    [self waitForProcessCount:1 onDocument:doc timeout:5.0];
    [doc handleExternalFileChange];
    [self waitForProcessCount:2 onDocument:doc timeout:5.0];

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
    [self waitForProcessCount:1 onDocument:doc timeout:5.0];

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
// editorAutoSave is a shared singleton setting, so it is restored in a teardown
// block rather than inline — a failed assertion mid-test would otherwise skip an
// inline restore and leak the change into every test that follows.
- (void)setEditorAutoSave:(BOOL)autoSave
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;
    [self addTeardownBlock:^{ prefs.editorAutoSave = original; }];
    prefs.editorAutoSave = autoSave;
}

- (void)testCleanDocumentDoesNotPromptWhenAutoSaveIsOff
{
    [self setEditorAutoSave:NO];

    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.stubbedDocumentEdited = NO;

    XCTAssertFalse([doc shouldPromptBeforeReloadingExternalChanges],
                   @"An unmodified document has nothing to lose, so an external "
                    "change should reload silently even with Auto Save off");
}

// The other half of the contract: unsaved work must still be defended, and the
// Auto Save setting must not change that either way.
- (void)testEditedDocumentPromptsRegardlessOfAutoSaveSetting
{
    MPPromptSpyDocument *doc = [[MPPromptSpyDocument alloc] init];
    doc.stubbedDocumentEdited = YES;

    [self setEditorAutoSave:YES];
    XCTAssertTrue([doc shouldPromptBeforeReloadingExternalChanges],
                  @"Unsaved changes must always be defended by a dialog");

    [self setEditorAutoSave:NO];
    XCTAssertTrue([doc shouldPromptBeforeReloadingExternalChanges],
                  @"Unsaved changes must always be defended by a dialog");
}


#pragma mark - Decision Path End-to-End (Issue #543)

// These drive the real -processExternalFileChange (not a spy override) so its
// own guards are exercised together, the way they ship.

// The coalescing window can straddle the start of one of our own saves, so the
// decision method re-checks isSelfSaving even though the entry point already did.
- (void)testProcessDoesNothingDuringASelfSave
{
    MPProcessSpyDocument *doc = [[MPProcessSpyDocument alloc] init];
    doc.isSelfSaving = YES;

    [doc processExternalFileChange];

    XCTAssertEqual(doc.reloadCount, 0u,
                   @"A change seen mid self-save must not reload");
    XCTAssertEqual(doc.promptCount, 0u,
                   @"A change seen mid self-save must not prompt");
}

// An untitled document has no file on disk to reconcile against.
- (void)testProcessDoesNothingWithoutAFileURL
{
    MPProcessSpyDocument *doc = [[MPProcessSpyDocument alloc] init];
    XCTAssertNil(doc.fileURL, @"Precondition: the document has no file URL");

    [doc processExternalFileChange];

    XCTAssertEqual(doc.reloadCount, 0u,
                   @"With no backing file there is nothing to reload");
    XCTAssertEqual(doc.promptCount, 0u,
                   @"With no backing file there is nothing to prompt about");
}

// A spurious notification whose on-disk date is no newer than what we last read
// is not a real change and must not reload.
- (void)testProcessDoesNotReloadWhenModificationDateIsUnchanged
{
    NSURL *url = [self writeTempFileWithContents:@"on disk\n"];
    NSDate *diskDate = [[NSFileManager defaultManager]
        attributesOfItemAtPath:url.path error:NULL][NSFileModificationDate];

    MPProcessSpyDocument *doc = [[MPProcessSpyDocument alloc] init];
    doc.fileURL = url;
    doc.fileModificationDate = diskDate;
    doc.stubbedDocumentEdited = NO;

    [doc processExternalFileChange];

    XCTAssertEqual(doc.reloadCount, 0u,
                   @"A notification with no newer content on disk must not "
                    "trigger a reload");
    XCTAssertEqual(doc.promptCount, 0u);
}

// A genuinely newer file with nothing unsaved locally reloads silently.
- (void)testProcessReloadsSilentlyWhenFileIsNewerAndDocumentIsClean
{
    NSURL *url = [self writeTempFileWithContents:@"newer on disk\n"];

    MPProcessSpyDocument *doc = [[MPProcessSpyDocument alloc] init];
    doc.fileURL = url;
    doc.fileModificationDate = [NSDate distantPast];   // disk is newer
    doc.stubbedDocumentEdited = NO;

    [doc processExternalFileChange];

    XCTAssertEqual(doc.reloadCount, 1u,
                   @"A newer file with nothing unsaved must reload silently");
    XCTAssertEqual(doc.promptCount, 0u,
                   @"A clean document must not be interrupted with a dialog");
}

// The same newer file, but with unsaved local work, must ask before discarding.
- (void)testProcessPromptsWhenFileIsNewerAndDocumentIsEdited
{
    NSURL *url = [self writeTempFileWithContents:@"newer on disk\n"];

    MPProcessSpyDocument *doc = [[MPProcessSpyDocument alloc] init];
    doc.fileURL = url;
    doc.fileModificationDate = [NSDate distantPast];   // disk is newer
    doc.stubbedDocumentEdited = YES;

    [doc processExternalFileChange];

    XCTAssertEqual(doc.promptCount, 1u,
                   @"Unsaved work plus a newer file on disk must prompt");
    XCTAssertEqual(doc.reloadCount, 0u,
                   @"A prompt must not also silently reload");
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


#pragma mark - Scroll Restoration Across Reload (Issue #543)

// With the editor inside a scroll view, reloadFromLoadedString takes its
// deferred scroll-restoration branch. The restore runs a later main-queue turn,
// so the run loop has to be spun before its effect is visible. This exercises
// the branch a follow-up commit had to fix, end-to-end, without crashing.
- (void)testReloadWithAScrollViewRestoresSelectionAndDoesNotThrow
{
    MPDocument *doc = [[MPDocument alloc] init];
    (void)[self wireScrollableEditorInto:doc];
    self.editor.string = @"# Title\n\nOriginal body text.\n";
    self.editor.selectedRange = NSMakeRange(12, 0);

    doc.loadedString = @"# Title\n\nBody text changed by another app.\n";
    XCTAssertNoThrow([doc reloadFromLoadedString]);
    [self spinRunLoopForInterval:0.05];   // let the deferred scroll block run

    XCTAssertEqual(self.editor.selectedRange.location, 12u,
                   @"The caret must survive a reload even on the scroll-view "
                    "path");
    XCTAssertEqualObjects(self.editor.string,
                          @"# Title\n\nBody text changed by another app.\n",
                          @"The reloaded content must be applied");
}

// The restore is deferred, so a second reload can start before the first's
// block runs. Bumping the generation on each reload lets the earlier block
// bail; here two reloads must leave the generation at 2, so the first block's
// captured value no longer matches and its stale scroll is skipped.
- (void)testASecondReloadSupersedesTheFirstScrollRestore
{
    MPDocument *doc = [[MPDocument alloc] init];
    (void)[self wireScrollableEditorInto:doc];
    self.editor.string = @"first content";

    doc.loadedString = @"second content";
    [doc reloadFromLoadedString];          // schedules restore, generation -> 1
    doc.loadedString = @"third content";
    [doc reloadFromLoadedString];          // schedules restore, generation -> 2

    XCTAssertEqual(doc.externalReloadScrollGeneration, 2u,
                   @"Each reload must advance the scroll-restore generation so "
                    "a superseded restore no-ops instead of applying a stale "
                    "viewport");

    [self spinRunLoopForInterval:0.05];    // drain both blocks; only the last acts
}

@end
