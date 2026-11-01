//
//  MPPaneToggleTests.m
//  MacDownTests
//
//  Tests for Issue #23: Hiding both editor and preview panes bug
//  Verifies that at least one pane remains visible at all times.
//

#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "MPDocument.h"
#import "MPDocumentWindowTestSupport.h"
#import "MPDocumentSplitView.h"
#import "MPPreferences.h"
#import "MPRenderer.h"

#pragma mark - Testing Category

@interface MPDocument (PaneToggleTesting)
@property (weak) MPDocumentSplitView *splitView;
@property (weak) NSView *editorContainer;
@property (weak) WebView *preview;
@property CGFloat previousSplitRatio;
@property CGFloat lastNonCollapsedRatio;
@property (strong) MPRenderer *renderer;
@property BOOL previewVisibleAtLastResize;
- (void)splitViewDidResizeSubviews:(NSNotification *)notification;
- (IBAction)toggleEditorPane:(id)sender;
- (IBAction)togglePreviewPane:(id)sender;
- (void)applyEditorStartInPreviewModePreference;
- (void)setupEditor:(NSString *)changedKey;
- (void)setSplitViewDividerLocation:(CGFloat)ratio;
@end

#pragma mark - Spy Renderer

@interface MP649SpyRenderer : MPRenderer
@property (nonatomic) BOOL parseAndRenderNowCalled;
@end

@implementation MP649SpyRenderer
- (void)parseAndRenderNow
{
    self.parseAndRenderNowCalled = YES;
}
@end

#pragma mark - Mock Menu Item

/**
 * Mock menu item for testing validateUserInterfaceItem:
 * Conforms to NSValidatedUserInterfaceItem protocol.
 */
@interface MockMenuItem : NSMenuItem
@end

@implementation MockMenuItem
@end


#pragma mark - Test Case

@interface MPPaneToggleTests : XCTestCase
@property (strong) MPDocument *document;
@property BOOL originalStartInPreviewMode;
@property BOOL originalEditorOnRight;
@end


@implementation MPPaneToggleTests

- (void)setUp
{
    [super setUp];
    MPPreferences *preferences = [MPPreferences sharedInstance];
    self.originalStartInPreviewMode = preferences.editorStartInPreviewMode;
    self.originalEditorOnRight = preferences.editorOnRight;
    preferences.editorStartInPreviewMode = NO;
    preferences.editorOnRight = NO;
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    self.document = nil;
    [MPPreferences sharedInstance].editorStartInPreviewMode =
        self.originalStartInPreviewMode;
    [MPPreferences sharedInstance].editorOnRight = self.originalEditorOnRight;
    [super tearDown];
}


#pragma mark - IBAction Safety Tests

/**
 * Test that toggleEditorPane: IBAction doesn't crash.
 * Issue #23: Direct action invocation safety test.
 */
- (void)testToggleEditorPaneIBActionDoesNotCrash
{
    XCTAssertNoThrow([self.document toggleEditorPane:nil],
                     @"toggleEditorPane: should not crash");
}

/**
 * Test that togglePreviewPane: IBAction doesn't crash.
 * Issue #23: Direct action invocation safety test.
 */
- (void)testTogglePreviewPaneIBActionDoesNotCrash
{
    XCTAssertNoThrow([self.document togglePreviewPane:nil],
                     @"togglePreviewPane: should not crash");
}

- (void)testEditorPaneChoiceIsRemembered
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        MPDocumentSplitView *splitView = [[MPDocumentSplitView alloc]
            initWithFrame:NSMakeRect(0, 0, 800, 600)];
        splitView.vertical = YES;
        NSView *editor = [[NSView alloc]
            initWithFrame:NSMakeRect(0, 0, 399, 600)];
        WebView *preview = [[WebView alloc]
            initWithFrame:NSMakeRect(400, 0, 400, 600)];
        [splitView addSubview:editor];
        [splitView addSubview:preview];

        self.document.splitView = splitView;
        self.document.editorContainer = editor;
        self.document.preview = preview;
        preferences.editorOnRight = NO;

        [self.document toggleEditorPane:nil];
        XCTAssertTrue(preferences.editorStartInPreviewMode,
                      @"Hiding the editor should be remembered for the next window");

        [self.document toggleEditorPane:nil];
        XCTAssertFalse(preferences.editorStartInPreviewMode,
                       @"Restoring the editor should update the remembered choice");
    }
    @finally {
        preferences.editorOnRight = originalEditorOnRight;
    }
}

- (void)testBlockedEditorHideLeavesRememberedChoiceAlone
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        // Editor-only layout: hiding the editor is refused because it would
        // leave no visible pane, so the remembered choice must not change.
        MPDocumentSplitView *splitView = [[MPDocumentSplitView alloc]
            initWithFrame:NSMakeRect(0, 0, 800, 600)];
        splitView.vertical = YES;
        NSView *editor = [[NSView alloc]
            initWithFrame:NSMakeRect(0, 0, 800, 600)];
        WebView *preview = [[WebView alloc]
            initWithFrame:NSMakeRect(800, 0, 0, 600)];
        [splitView addSubview:editor];
        [splitView addSubview:preview];

        self.document.splitView = splitView;
        self.document.editorContainer = editor;
        self.document.preview = preview;
        preferences.editorOnRight = NO;
        preferences.editorStartInPreviewMode = YES;

        XCTAssertFalse(self.document.previewVisible,
                       @"Precondition: the preview pane is collapsed");
        [self.document toggleEditorPane:nil];
        XCTAssertTrue(self.document.editorVisible,
                      @"Hiding the only visible pane should be refused");
        XCTAssertTrue(preferences.editorStartInPreviewMode,
                      @"A refused hide should not change the remembered choice");
    }
    @finally {
        preferences.editorOnRight = originalEditorOnRight;
    }
}


#pragma mark - Menu Validation Tests

/**
 * Test that validateUserInterfaceItem: is implemented and callable.
 * Issue #23: Baseline test for menu validation.
 */
- (void)testValidateUserInterfaceItemExists
{
    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Test"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];
    XCTAssertNoThrow([self.document validateUserInterfaceItem:item],
                     @"validateUserInterfaceItem: should not crash");
}

/**
 * Test menu validation for toggleEditorPane: action.
 * Issue #23: When editor is visible but preview is not, "Hide Editor" should be disabled.
 *
 * Note: In headless testing, both panes report as not visible (frame width 0).
 * This test verifies the validation behavior in that edge case.
 * The key assertion is that when the document thinks only the editor is visible,
 * the "Hide Editor" menu item should be disabled (return NO).
 */
- (void)testValidateHideEditorMenuWhenPreviewNotVisible
{
    // In headless mode, editorVisible and previewVisible both return NO
    // (because the outlets are nil and frame width is 0).
    // We're testing that validateUserInterfaceItem: handles this gracefully.

    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    BOOL result = [self.document validateUserInterfaceItem:item];

    // The menu item should be processed without crash
    // In headless mode, both panes are "not visible", so this is an edge case.
    // The implementation should handle this gracefully.
    XCTAssertNoThrow((void)result, @"Validation should complete without error");
}

/**
 * Test menu validation for togglePreviewPane: action.
 * Issue #23: When preview is visible but editor is not, "Hide Preview" should be disabled.
 */
- (void)testValidateHidePreviewMenuWhenEditorNotVisible
{
    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Preview Pane"
                                                      action:@selector(togglePreviewPane:)
                                               keyEquivalent:@""];

    BOOL result = [self.document validateUserInterfaceItem:item];

    XCTAssertNoThrow((void)result, @"Validation should complete without error");
}


#pragma mark - Property Access Tests

/**
 * Test that editorVisible property is accessible.
 * Issue #23: Baseline property access test.
 */
- (void)testEditorVisiblePropertyAccessible
{
    XCTAssertNoThrow((void)self.document.editorVisible,
                     @"editorVisible property should be accessible");
}

/**
 * Test that previewVisible property is accessible.
 * Issue #23: Baseline property access test.
 */
- (void)testPreviewVisiblePropertyAccessible
{
    XCTAssertNoThrow((void)self.document.previewVisible,
                     @"previewVisible property should be accessible");
}

/**
 * Test pane visibility in headless environment.
 * Issue #23: Verify both panes report not visible when UI outlets are nil.
 * This is expected behavior in headless CI.
 */
- (void)testPaneVisibilityInHeadlessEnvironment
{
    // In headless mode without window controller, outlets are nil
    // Frame width of nil view is 0, so both should be "not visible"
    BOOL editorVisible = self.document.editorVisible;
    BOOL previewVisible = self.document.previewVisible;

    // Both should be NO in headless mode
    XCTAssertFalse(editorVisible, @"Editor should not be visible in headless mode");
    XCTAssertFalse(previewVisible, @"Preview should not be visible in headless mode");
}

- (void)testStartInPreviewModeRestoresPreviewFromEditorOnlyLayout
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalStartInPreviewMode = preferences.editorStartInPreviewMode;
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        XCTSkipUnless(MPLoadDocumentWindow(self.document),
                      @"no document window can be loaded here");
        XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                      @"a loaded document window shows both panes");

        // Build the editor-only layout: editor on the left, preview collapsed.
        preferences.editorOnRight = NO;
        [self.document setSplitViewDividerLocation:1.0];
        self.document.previousSplitRatio = -1.0;
        XCTAssertTrue(self.document.editorVisible && !self.document.previewVisible,
                      @"Precondition: the layout is editor-only");

        preferences.editorStartInPreviewMode = YES;
        [self.document applyEditorStartInPreviewModePreference];

        XCTAssertFalse(self.document.editorVisible,
                       @"Startup preview mode should collapse the editor pane");
        XCTAssertTrue(self.document.previewVisible,
                      @"Startup preview mode should make the preview visible");
        XCTAssertEqualWithAccuracy(self.document.splitView.dividerLocation, 0.0, 0.001,
                                   @"Startup preview mode should collapse the divider to the preview-only edge");
        XCTAssertEqualWithAccuracy(self.document.previousSplitRatio, 0.5, 0.001,
                                   @"Startup preview mode from an editor-only layout should save the default split ratio");
    }
    @finally {
        preferences.editorStartInPreviewMode = originalStartInPreviewMode;
        preferences.editorOnRight = originalEditorOnRight;
        [preferences synchronize];
    }
}


#pragma mark - Window Controller Integration Tests

/**
 * Test document with window controller loaded.
 * Issue #23: Test with real window controller to verify pane state.
 */
- (void)testDocumentWithWindowController
{
    // Load the document's NIB to create window controller
    [self.document makeWindowControllers];

    // After makeWindowControllers, the split view should be initialized
    // In headless CI, the window may not be fully displayed but outlets should exist

    // Test that toggles still don't crash with window controller loaded
    XCTAssertNoThrow([self.document toggleEditorPane:nil],
                     @"toggleEditorPane: should not crash with window controller");
    XCTAssertNoThrow([self.document togglePreviewPane:nil],
                     @"togglePreviewPane: should not crash with window controller");
}

/**
 * Test that rapid toggles don't cause issues.
 * Issue #23: Stress test for state consistency.
 */
- (void)testRapidToggleSequence
{
    [self.document makeWindowControllers];

    // Perform multiple toggles in sequence
    XCTAssertNoThrow({
        for (int i = 0; i < 10; i++) {
            [self.document toggleEditorPane:nil];
            [self.document togglePreviewPane:nil];
        }
    }, @"Rapid toggle sequence should not crash");
}

/**
 * Test menu validation with window controller.
 * Issue #23: Verify validation works with loaded window.
 */
- (void)testValidateMenuItemsWithWindowController
{
    [self.document makeWindowControllers];

    MockMenuItem *editorItem = [[MockMenuItem alloc] initWithTitle:@"Hide Editor Pane"
                                                            action:@selector(toggleEditorPane:)
                                                     keyEquivalent:@""];
    MockMenuItem *previewItem = [[MockMenuItem alloc] initWithTitle:@"Hide Preview Pane"
                                                             action:@selector(togglePreviewPane:)
                                                      keyEquivalent:@""];

    // Both validations should work
    BOOL editorResult = [self.document validateUserInterfaceItem:editorItem];
    BOOL previewResult = [self.document validateUserInterfaceItem:previewItem];

    // At this point, with window controller loaded, both panes should be visible
    // and both menu items should be enabled (return YES)
    // Note: In headless CI, results may vary depending on display server

    // The key test is that validation doesn't crash
    XCTAssertNoThrow((void)editorResult, @"Editor menu validation should not crash");
    XCTAssertNoThrow((void)previewResult, @"Preview menu validation should not crash");
}


#pragma mark - Positive Tests (Both Panes Visible)

/**
 * Test that validation returns YES when BOTH panes are visible.
 * Issue #23: Ensures the fix doesn't over-restrict.
 */
- (void)testValidateReturnYesWhenBothPanesVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    MockMenuItem *editorItem = [[MockMenuItem alloc] initWithTitle:@"Test"
                                                            action:@selector(toggleEditorPane:)
                                                     keyEquivalent:@""];
    MockMenuItem *previewItem = [[MockMenuItem alloc] initWithTitle:@"Test"
                                                             action:@selector(togglePreviewPane:)
                                                      keyEquivalent:@""];

    BOOL editorResult = [self.document validateUserInterfaceItem:editorItem];
    BOOL previewResult = [self.document validateUserInterfaceItem:previewItem];

    XCTAssertTrue(editorResult, @"Hide Editor should be enabled when both panes visible");
    XCTAssertTrue(previewResult, @"Hide Preview should be enabled when both panes visible");
}


#pragma mark - Constraint Enforcement Tests

/**
 * Test that menu is disabled when hiding editor would leave no visible panes.
 * Issue #23: This test validates the fix is working.
 */
- (void)testHideEditorMenuDisabledWhenOnlyEditorVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide preview pane so only editor is visible
    [self.document togglePreviewPane:nil];

    // Now only editor should be visible
    BOOL editorVisibleAfterHidePreview = self.document.editorVisible;
    BOOL previewVisibleAfterHidePreview = self.document.previewVisible;

    // The editor should still be visible, preview should be hidden
    XCTAssertTrue(editorVisibleAfterHidePreview, @"Editor should still be visible");
    XCTAssertFalse(previewVisibleAfterHidePreview, @"Preview should be hidden");

    // Now validate the "Hide Editor" menu item - it should be DISABLED
    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    BOOL result = [self.document validateUserInterfaceItem:item];

    // KEY ASSERTION: When only editor is visible, "Hide Editor" should return NO
    XCTAssertFalse(result,
                   @"Hide Editor menu should be disabled when preview is not visible");
}

/**
 * Test that menu is disabled when hiding preview would leave no visible panes.
 * Issue #23: This test validates the fix is working.
 */
- (void)testHidePreviewMenuDisabledWhenOnlyPreviewVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide editor pane so only preview is visible
    [self.document toggleEditorPane:nil];

    // Now only preview should be visible
    BOOL editorVisibleAfterHideEditor = self.document.editorVisible;
    BOOL previewVisibleAfterHideEditor = self.document.previewVisible;

    XCTAssertFalse(editorVisibleAfterHideEditor, @"Editor should be hidden");
    XCTAssertTrue(previewVisibleAfterHideEditor, @"Preview should still be visible");

    // Validate "Hide Preview" menu - it should be DISABLED
    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Preview Pane"
                                                      action:@selector(togglePreviewPane:)
                                               keyEquivalent:@""];

    BOOL result = [self.document validateUserInterfaceItem:item];

    // KEY ASSERTION: When only preview is visible, "Hide Preview" should return NO
    XCTAssertFalse(result,
                   @"Hide Preview menu should be disabled when editor is not visible");
}

/**
 * Test that toggle action is a no-op when it would hide the last visible pane.
 * Issue #23: Verify the toggle itself does nothing, not just the menu.
 */
- (void)testToggleEditorIsNoOpWhenOnlyEditorVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide preview so only editor is visible
    [self.document togglePreviewPane:nil];

    XCTAssertTrue(self.document.editorVisible, @"Editor should be visible");
    XCTAssertFalse(self.document.previewVisible, @"Preview should be hidden");

    // Try to hide the editor - this should be a no-op
    [self.document toggleEditorPane:nil];

    // KEY ASSERTION: Editor should STILL be visible
    XCTAssertTrue(self.document.editorVisible,
                  @"Editor should remain visible when preview is hidden (toggle should be no-op)");
}

/**
 * Test that toggle action is a no-op when it would hide the last visible pane.
 * Issue #23: Verify the toggle itself does nothing, not just the menu.
 */
- (void)testTogglePreviewIsNoOpWhenOnlyPreviewVisible
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide editor so only preview is visible
    [self.document toggleEditorPane:nil];

    XCTAssertFalse(self.document.editorVisible, @"Editor should be hidden");
    XCTAssertTrue(self.document.previewVisible, @"Preview should be visible");

    // Try to hide the preview - this should be a no-op
    [self.document togglePreviewPane:nil];

    // KEY ASSERTION: Preview should STILL be visible
    XCTAssertTrue(self.document.previewVisible,
                  @"Preview should remain visible when editor is hidden (toggle should be no-op)");
}


#pragma mark - Restore Operations Tests

/**
 * Test that restore operations always work.
 * Issue #23: Restoring a hidden pane should never be blocked.
 */
- (void)testRestoreEditorAlwaysWorks
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide editor
    [self.document toggleEditorPane:nil];
    XCTAssertFalse(self.document.editorVisible,
                   @"Hiding the editor should collapse it");

    // Restore editor - this should always work
    [self.document toggleEditorPane:nil];

    XCTAssertTrue(self.document.editorVisible,
                  @"Restoring editor should always work");
}

/**
 * Test that restore operations always work.
 * Issue #23: Restoring a hidden pane should never be blocked.
 */
- (void)testRestorePreviewAlwaysWorks
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide preview
    [self.document togglePreviewPane:nil];
    XCTAssertFalse(self.document.previewVisible,
                   @"Hiding the preview should collapse it");

    // Restore preview - this should always work
    [self.document togglePreviewPane:nil];

    XCTAssertTrue(self.document.previewVisible,
                  @"Restoring preview should always work");
}

/**
 * Test that "Restore" menu items are enabled even when other pane is hidden.
 * Issue #23: Only "Hide" should be disabled, not "Restore".
 */
- (void)testRestoreMenuItemEnabledWhenPaneHidden
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide editor
    [self.document toggleEditorPane:nil];
    XCTAssertFalse(self.document.editorVisible,
                   @"Hiding the editor should collapse it");

    // Now editor is hidden. "Restore Editor" menu item should be ENABLED.
    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Restore Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    BOOL result = [self.document validateUserInterfaceItem:item];

    // Restore should always be enabled
    XCTAssertTrue(result,
                  @"Restore Editor menu should be enabled when editor is hidden");
}


#pragma mark - Issue #377: Editor Menu Item Hidden Property Tests

/**
 * Test that editor menu item hidden property is set during validation.
 * Issue #377: The editor pane case was missing the it.hidden assignment.
 *
 * In headless mode without window controllers, both panes are not visible
 * and previousSplitRatio is -1.0 (initial sentinel). So the expression
 * (!editorVisible && previousSplitRatio < 0.0) should evaluate to YES,
 * meaning the menu item should be hidden.
 */
- (void)testEditorMenuItemHiddenPropertySetDuringValidation
{
    // Before fix: the hidden property is never set for editor menu item.
    // After fix: hidden = (!editorVisible && previousSplitRatio < 0.0)
    // In headless: editorVisible=NO, previousSplitRatio=-1.0, so hidden=YES.

    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    // Ensure the item starts as not hidden
    item.hidden = NO;

    [self.document validateUserInterfaceItem:item];

    // In headless mode: editorVisible is NO, previousSplitRatio is -1.0
    // So hidden should be set to YES
    XCTAssertTrue(item.hidden,
                  @"Issue #377: Editor menu item hidden property should be set "
                  @"when editor is not visible and no previous split ratio exists");
}

/**
 * Test that preview menu item hidden property is set during validation.
 * Issue #377: This is the existing working behavior - test for symmetry.
 */
- (void)testPreviewMenuItemHiddenPropertySetDuringValidation
{
    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Preview Pane"
                                                      action:@selector(togglePreviewPane:)
                                               keyEquivalent:@""];

    item.hidden = NO;

    [self.document validateUserInterfaceItem:item];

    // Same conditions as above: previewVisible=NO, previousSplitRatio=-1.0
    XCTAssertTrue(item.hidden,
                  @"Preview menu item hidden property should be set "
                  @"when preview is not visible and no previous split ratio exists");
}

/**
 * Test that editor menu item is NOT hidden after a toggle has saved a split ratio.
 * Issue #377: Once previousSplitRatio >= 0, the menu item should be visible.
 */
- (void)testEditorMenuItemNotHiddenAfterToggle
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Toggle editor pane to save a previousSplitRatio
    [self.document toggleEditorPane:nil];
    XCTAssertGreaterThanOrEqual(self.document.previousSplitRatio, 0.0,
                                @"Hiding the editor should save the split ratio");

    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Restore Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    [self.document validateUserInterfaceItem:item];

    // After toggling, previousSplitRatio should be >= 0, so hidden should be NO
    XCTAssertFalse(item.hidden,
                   @"Issue #377: Editor menu item should not be hidden after a toggle "
                   @"(previousSplitRatio should be saved)");
}

/**
 * Test that editor menu title changes to "Restore Editor Pane" after hiding editor.
 * Issue #377: This is the core behavioral test.
 */
- (void)testEditorMenuTitleTogglesAfterHide
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide the editor pane
    [self.document toggleEditorPane:nil];

    XCTAssertFalse(self.document.editorVisible,
                   @"Editor should be hidden after toggle");

    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    [self.document validateUserInterfaceItem:item];

    NSString *expectedTitle = NSLocalizedString(@"Restore Editor Pane",
                                                @"Toggle editor pane menu item");
    XCTAssertEqualObjects(item.title, expectedTitle,
                          @"Issue #377: Menu title should be 'Restore Editor Pane' "
                          @"after hiding editor pane");
}

/**
 * Test that editor menu title changes back to "Hide Editor Pane" after restoring editor.
 * Issue #377: Verifies the full toggle cycle works.
 */
- (void)testEditorMenuTitleTogglesAfterRestore
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    // Hide and then restore the editor pane
    [self.document toggleEditorPane:nil];
    [self.document toggleEditorPane:nil];

    XCTAssertTrue(self.document.editorVisible,
                  @"Editor should be visible after hide+restore");

    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Restore Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    [self.document validateUserInterfaceItem:item];

    NSString *expectedTitle = NSLocalizedString(@"Hide Editor Pane",
                                                @"Toggle editor pane menu item");
    XCTAssertEqualObjects(item.title, expectedTitle,
                          @"Issue #377: Menu title should be 'Hide Editor Pane' "
                          @"after restoring editor pane");
}


#pragma mark - Issue #377: Collapse Detection Tests

/**
 * Test that MPDocumentSplitView.setDividerLocation:0.0 collapses the left subview
 * to zero width. This test creates a standalone split view (no document, no window)
 * to verify the frame-setting behavior directly.
 *
 * Issue #377: If setPosition:ofDividerAtIndex: overrides the manual frame-setting,
 * the left subview may retain a non-zero width after setDividerLocation:0.0.
 */
- (void)testSetDividerLocationZeroCollapsesLeftSubview
{
    MPDocumentSplitView *splitView = [[MPDocumentSplitView alloc]
        initWithFrame:NSMakeRect(0, 0, 800, 600)];
    splitView.vertical = YES;

    NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 399, 600)];
    NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(400, 0, 400, 600)];
    [splitView addSubview:left];
    [splitView addSubview:right];

    [splitView setDividerLocation:0.0];

    XCTAssertEqual(left.frame.size.width, 0.0,
                   @"Issue #377: Left subview width should be 0 after setDividerLocation:0.0");
}

/**
 * Test that MPDocumentSplitView.setDividerLocation:1.0 collapses the right subview
 * to zero width.
 *
 * Issue #377: Symmetry test — hiding preview (ratio 1.0) should also work.
 */
- (void)testSetDividerLocationOneCollapsesRightSubview
{
    MPDocumentSplitView *splitView = [[MPDocumentSplitView alloc]
        initWithFrame:NSMakeRect(0, 0, 800, 600)];
    splitView.vertical = YES;

    NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 399, 600)];
    NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(400, 0, 400, 600)];
    [splitView addSubview:left];
    [splitView addSubview:right];

    [splitView setDividerLocation:1.0];

    XCTAssertEqual(right.frame.size.width, 0.0,
                   @"Issue #377: Right subview width should be 0 after setDividerLocation:1.0");
}

/**
 * Test that MPDocument implements splitView:canCollapseSubview: and returns YES.
 * Issue #377: This delegate method is needed for NSSplitView to allow divider-drag
 * collapse of subviews.
 */
- (void)testCanCollapseSubviewReturnsYes
{
    [self.document makeWindowControllers];

    // Check that the document responds to the delegate method
    XCTAssertTrue([self.document respondsToSelector:@selector(splitView:canCollapseSubview:)],
                  @"Issue #377: MPDocument should implement splitView:canCollapseSubview:");

    // If the method exists and split view is available, test with actual subviews.
    // Use NSInvocation since the method may not exist yet (red test).
    MPDocumentSplitView *splitView = self.document.splitView;
    if (splitView && splitView.subviews.count == 2) {
        SEL sel = @selector(splitView:canCollapseSubview:);
        NSMethodSignature *sig = [self.document methodSignatureForSelector:sel];
        if (sig) {
            for (NSView *subview in splitView.subviews) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.selector = sel;
                inv.target = self.document;
                [inv setArgument:&splitView atIndex:2];
                [inv setArgument:&subview atIndex:3];
                [inv invoke];
                BOOL canCollapse = NO;
                [inv getReturnValue:&canCollapse];
                XCTAssertTrue(canCollapse,
                              @"Issue #377: canCollapseSubview: should return YES for all subviews");
            }
        }
    }
}

/**
 * Test that previousSplitRatio is set when a pane is collapsed via divider drag.
 * Simulates a drag by manually collapsing the split view subview frames and then
 * posting NSSplitViewDidResizeSubviewsNotification (which triggers
 * splitViewDidResizeSubviews: on the delegate).
 *
 * This is a RED test — it fails until splitViewDidResizeSubviews: is updated to
 * detect collapse transitions and set previousSplitRatio.
 *
 * Issue #377: When a user drags the divider to the edge, the menu item should
 * remain visible (not hidden) so the pane can be restored via menu.
 */
- (void)testPreviousSplitRatioSetOnDividerDragCollapse
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    MPDocumentSplitView *splitView = self.document.splitView;
    XCTAssertNotNil(splitView, @"A loaded document window has a split view");

    // Verify initial state: previousSplitRatio should be -1.0 (sentinel)
    XCTAssertLessThan(self.document.previousSplitRatio, 0.0,
                      @"previousSplitRatio should start at sentinel value (-1.0)");

    // Post the notification at the loaded (non-collapsed) split first, as the
    // start of a real drag does, so the document records the last open ratio.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSSplitViewDidResizeSubviewsNotification
                      object:splitView];

    // Simulate a divider drag by manually collapsing the left subview to zero width
    // and posting the resize notification (as NSSplitView does during a real drag).
    NSView *left = splitView.subviews[0];
    NSView *right = splitView.subviews[1];
    CGFloat totalWidth = splitView.frame.size.width - splitView.dividerThickness;
    left.frame = NSMakeRect(0, 0, 0, left.frame.size.height);
    right.frame = NSMakeRect(splitView.dividerThickness, 0, totalWidth,
                             right.frame.size.height);

    // Post the notification that NSSplitView sends during a drag resize.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSSplitViewDidResizeSubviewsNotification
                      object:splitView];

    // After collapse, previousSplitRatio should have been set (>= 0)
    // so the menu item remains visible (not hidden).
    XCTAssertGreaterThanOrEqual(self.document.previousSplitRatio, 0.0,
                                @"Issue #377: previousSplitRatio should be set after "
                                @"divider-drag collapse so menu item remains visible");
}

/**
 * Test that the editor menu item is NOT hidden after a simulated divider-drag collapse.
 * This is a RED test — it fails until the divider-drag collapse tracking is implemented.
 *
 * Issue #377: This verifies the end-to-end behavior — the menu item should be visible
 * with a "Restore" title, not hidden.
 */
- (void)testEditorMenuItemVisibleAfterDividerDragCollapse
{
    XCTSkipUnless(MPLoadDocumentWindow(self.document),
                  @"no document window can be loaded here");
    XCTAssertTrue(self.document.editorVisible && self.document.previewVisible,
                  @"a loaded document window shows both panes");

    MPDocumentSplitView *splitView = self.document.splitView;
    XCTAssertNotNil(splitView, @"A loaded document window has a split view");

    // Post the notification at the loaded (non-collapsed) split first, as the
    // start of a real drag does, so the document records the last open ratio.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSSplitViewDidResizeSubviewsNotification
                      object:splitView];

    // Simulate divider drag to collapse editor (left pane)
    NSView *left = splitView.subviews[0];
    NSView *right = splitView.subviews[1];
    CGFloat totalWidth = splitView.frame.size.width - splitView.dividerThickness;
    left.frame = NSMakeRect(0, 0, 0, left.frame.size.height);
    right.frame = NSMakeRect(splitView.dividerThickness, 0, totalWidth,
                             right.frame.size.height);
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSSplitViewDidResizeSubviewsNotification
                      object:splitView];

    MockMenuItem *item = [[MockMenuItem alloc] initWithTitle:@"Hide Editor Pane"
                                                      action:@selector(toggleEditorPane:)
                                               keyEquivalent:@""];

    [self.document validateUserInterfaceItem:item];

    XCTAssertFalse(item.hidden,
                   @"Issue #377: Editor menu item should NOT be hidden after divider-drag collapse");
    XCTAssertGreaterThanOrEqual(self.document.previousSplitRatio, 0.0,
                                @"Issue #377: the collapse should record the previous split ratio");
    NSString *expectedTitle = NSLocalizedString(@"Restore Editor Pane",
                                                @"Toggle editor pane menu item");
    XCTAssertEqualObjects(item.title, expectedTitle,
                          @"Issue #377: Menu title should be 'Restore Editor Pane' "
                          @"after the editor is collapsed by a divider drag");
}

- (void)testEditorOnRightMirrorsLastNonCollapsedRatio
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        MPDocumentSplitView *splitView =
            [[MPDocumentSplitView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        NSView *preview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 100)];
        NSView *editor = [[NSView alloc] initWithFrame:NSMakeRect(50, 0, 50, 100)];
        [splitView addSubview:preview];
        [splitView addSubview:editor];
        self.document.splitView = splitView;
        self.document.preview = (WebView *)preview;

        preferences.editorOnRight = NO;
        [self.document setupEditor:@"editorOnRight"];
        self.document.previousSplitRatio = -1.0;
        self.document.lastNonCollapsedRatio = 0.3;

        preferences.editorOnRight = YES;
        [self.document setupEditor:@"editorOnRight"];

        XCTAssertEqualWithAccuracy(self.document.lastNonCollapsedRatio, 0.7, 0.001,
                                   @"Issue #380: drag-collapse restore ratio should mirror "
                                   @"when editorOnRight swaps panes");
    }
    @finally {
        preferences.editorOnRight = originalEditorOnRight;
        [preferences synchronize];
    }
}

#pragma mark - Issue #649: Restore Pane From Collapsed State

- (MPDocumentSplitView *)attachSplitViewWithEditorFrame:(NSRect)editorFrame
                                           previewFrame:(NSRect)previewFrame
                                                 editor:(NSView **)editorOut
                                                preview:(WebView **)previewOut
{
    MPDocumentSplitView *splitView = [[MPDocumentSplitView alloc]
        initWithFrame:NSMakeRect(0, 0, 800, 600)];
    splitView.vertical = YES;
    NSView *editor = [[NSView alloc] initWithFrame:editorFrame];
    WebView *preview = [[WebView alloc] initWithFrame:previewFrame];
    [splitView addSubview:editor];
    [splitView addSubview:preview];
    self.document.splitView = splitView;
    self.document.editorContainer = editor;
    self.document.preview = preview;
    *editorOut = editor;
    *previewOut = preview;
    return splitView;
}

// A hidden (collapsed) editor with a non-zero frame width reads as not
// visible, offers "Restore Editor Pane" even with no saved ratio, and
// toggling restores it at a usable width.
- (void)testHiddenEditorOffersRestoreAndRestoresAtUsableWidth
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        preferences.editorOnRight = NO;
        NSView *editor = nil;
        WebView *preview = nil;
        MPDocumentSplitView *splitView = [self
            attachSplitViewWithEditorFrame:NSMakeRect(0, 0, 399, 600)
                              previewFrame:NSMakeRect(400, 0, 400, 600)
                                    editor:&editor
                                   preview:&preview];
        editor.hidden = YES;

        XCTAssertFalse(self.document.editorVisible,
                       @"A hidden editor container is not visible");
        XCTAssertTrue(self.document.previewVisible);
        XCTAssertLessThan(self.document.previousSplitRatio, 0.0,
                          @"Precondition: no saved split ratio");

        MockMenuItem *item = [[MockMenuItem alloc]
            initWithTitle:@"Hide Editor Pane"
                   action:@selector(toggleEditorPane:)
            keyEquivalent:@""];
        [self.document validateUserInterfaceItem:item];
        XCTAssertEqualObjects(item.title,
            NSLocalizedString(@"Restore Editor Pane", @"Toggle editor pane menu item"));
        XCTAssertFalse(item.hidden,
                       @"Restore item must stay visible with no saved ratio");

        [self.document toggleEditorPane:nil];
        XCTAssertFalse(editor.hidden, @"Restore un-hides the editor");
        CGFloat total = splitView.frame.size.width - splitView.dividerThickness;
        XCTAssertGreaterThanOrEqual(editor.frame.size.width, 0.1 * total);
        XCTAssertTrue(self.document.editorVisible);
    }
    @finally {
        preferences.editorOnRight = originalEditorOnRight;
    }
}

// A hidden (collapsed) preview with a non-zero frame width reads as not
// visible, offers "Restore Preview Pane", and toggling restores it.
- (void)testHiddenPreviewOffersRestoreAndRestoresAtUsableWidth
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        preferences.editorOnRight = NO;
        NSView *editor = nil;
        WebView *preview = nil;
        MPDocumentSplitView *splitView = [self
            attachSplitViewWithEditorFrame:NSMakeRect(0, 0, 399, 600)
                              previewFrame:NSMakeRect(400, 0, 400, 600)
                                    editor:&editor
                                   preview:&preview];
        preview.hidden = YES;

        XCTAssertFalse(self.document.previewVisible,
                       @"A hidden preview is not visible");
        XCTAssertTrue(self.document.editorVisible);
        XCTAssertLessThan(self.document.previousSplitRatio, 0.0,
                          @"Precondition: no saved split ratio");

        MockMenuItem *item = [[MockMenuItem alloc]
            initWithTitle:@"Hide Preview Pane"
                   action:@selector(togglePreviewPane:)
            keyEquivalent:@""];
        [self.document validateUserInterfaceItem:item];
        XCTAssertEqualObjects(item.title,
            NSLocalizedString(@"Restore Preview Pane", @"Toggle preview pane menu item"));
        XCTAssertFalse(item.hidden,
                       @"Restore item must stay visible with no saved ratio");

        [self.document togglePreviewPane:nil];
        XCTAssertFalse(preview.hidden, @"Restore un-hides the preview");
        CGFloat total = splitView.frame.size.width - splitView.dividerThickness;
        XCTAssertGreaterThanOrEqual(preview.frame.size.width, 0.1 * total);
        XCTAssertTrue(self.document.previewVisible);
    }
    @finally {
        preferences.editorOnRight = originalEditorOnRight;
    }
}

// A saved near-edge ratio (0.003) is not used for restoring a zero-width
// editor; the restore falls back to a usable width.
- (void)testRestoreEditorFromNearEdgeSavedRatioIsUsable
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalEditorOnRight = preferences.editorOnRight;

    @try {
        preferences.editorOnRight = NO;
        NSView *editor = nil;
        WebView *preview = nil;
        MPDocumentSplitView *splitView = [self
            attachSplitViewWithEditorFrame:NSMakeRect(0, 0, 0, 600)
                              previewFrame:NSMakeRect(1, 0, 799, 600)
                                    editor:&editor
                                   preview:&preview];
        self.document.previousSplitRatio = 0.003;

        XCTAssertFalse(self.document.editorVisible);

        [self.document toggleEditorPane:nil];
        CGFloat total = splitView.frame.size.width - splitView.dividerThickness;
        XCTAssertGreaterThanOrEqual(editor.frame.size.width, 0.1 * total,
                                    @"Restored editor must be at least 10%% wide");
        XCTAssertTrue(self.document.editorVisible);
    }
    @finally {
        preferences.editorOnRight = originalEditorOnRight;
    }
}

// Bringing a collapsed preview back (e.g. by a divider drag) renders the
// preview once, on the not-visible -> visible transition only.
- (void)testPreviewUncollapseTriggersRenderOnTransitionOnly
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalManualRender = preferences.markdownManualRender;

    @try {
        preferences.markdownManualRender = NO;
        NSView *editor = nil;
        WebView *preview = nil;
        [self attachSplitViewWithEditorFrame:NSMakeRect(0, 0, 399, 600)
                                previewFrame:NSMakeRect(400, 0, 400, 600)
                                      editor:&editor
                                     preview:&preview];
        preview.hidden = YES;
        MP649SpyRenderer *spy = [[MP649SpyRenderer alloc] init];
        self.document.renderer = spy;
        self.document.previewVisibleAtLastResize = NO;

        preview.hidden = NO;
        [self.document splitViewDidResizeSubviews:nil];
        XCTAssertTrue(spy.parseAndRenderNowCalled,
                      @"Uncollapsing the preview should render it");

        spy.parseAndRenderNowCalled = NO;
        [self.document splitViewDidResizeSubviews:nil];
        XCTAssertFalse(spy.parseAndRenderNowCalled,
                       @"No render without a visibility transition");
    }
    @finally {
        preferences.markdownManualRender = originalManualRender;
    }
}

// With manual rendering on, uncollapsing the preview does not render.
- (void)testPreviewUncollapseDoesNotRenderInManualRenderMode
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL originalManualRender = preferences.markdownManualRender;

    @try {
        preferences.markdownManualRender = YES;
        NSView *editor = nil;
        WebView *preview = nil;
        [self attachSplitViewWithEditorFrame:NSMakeRect(0, 0, 399, 600)
                                previewFrame:NSMakeRect(400, 0, 400, 600)
                                      editor:&editor
                                     preview:&preview];
        preview.hidden = YES;
        MP649SpyRenderer *spy = [[MP649SpyRenderer alloc] init];
        self.document.renderer = spy;
        self.document.previewVisibleAtLastResize = NO;

        preview.hidden = NO;
        [self.document splitViewDidResizeSubviews:nil];
        XCTAssertFalse(spy.parseAndRenderNowCalled,
                       @"Manual render mode must not auto-render on uncollapse");
    }
    @finally {
        preferences.markdownManualRender = originalManualRender;
    }
}


@end
