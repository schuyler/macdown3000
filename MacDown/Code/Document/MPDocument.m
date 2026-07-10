//
//  MPDocument.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPDocument.h"
#import <WebKit/WebKit.h>
#import <JJPluralForm/JJPluralForm.h>
#import <hoedown/html.h>
#import "hoedown_html_patch.h"
#import "HGMarkdownHighlighter.h"
#import "MPUtilities.h"
#import "MPAutosaving.h"
#import "NSColor+HTML.h"
#import "NSDocumentController+Document.h"
#import "NSPasteboard+Types.h"
#import "NSString+Lookup.h"
#import "NSTextView+Autocomplete.h"
#import "DOMNode+Text.h"
#import "MPPreferences.h"
#import "MPDocumentSplitView.h"
#import "MPEditorView.h"
#import "MPRenderer.h"
#import "MPPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPExportPanelAccessoryViewController.h"
#import "MPMathJaxListener.h"
#import "WebView+WebViewPrivateHeaders.h"
#import "MPToolbarController.h"
#import "MPFileWatcher.h"
#import "MPResourceWatcherSet.h"
#import "MPHTMLResourceURLs.h"
#import "MPURLSecurityPolicy.h"
#import <JavaScriptCore/JavaScriptCore.h>

static NSString * const kMPDefaultAutosaveName = @"Untitled";

static const CGFloat kMPMinZoom = 0.5;
static const CGFloat kMPMaxZoom = 3.0;


NS_INLINE NSString *MPEditorPreferenceKeyWithValueKey(NSString *key)
{
    if (!key.length)
        return @"editor";
    NSString *first = [[key substringToIndex:1] uppercaseString];
    NSString *rest = [key substringFromIndex:1];
    return [NSString stringWithFormat:@"editor%@%@", first, rest];
}

NS_INLINE NSDictionary *MPEditorKeysToObserve()
{
    static NSDictionary *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = @{@"automaticDashSubstitutionEnabled": @NO,
                 @"automaticDataDetectionEnabled": @NO,
                 @"automaticQuoteSubstitutionEnabled": @NO,
                 @"automaticSpellingCorrectionEnabled": @NO,
                 @"automaticTextReplacementEnabled": @NO,
                 @"continuousSpellCheckingEnabled": @NO,
                 @"enabledTextCheckingTypes": @(NSTextCheckingAllTypes),
                 @"grammarCheckingEnabled": @NO,
                 @"smartInsertDeleteEnabled": @NO};
    });
    return keys;
}

NS_INLINE NSSet *MPEditorPreferencesToObserve()
{
    static NSSet *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = [NSSet setWithObjects:
            @"editorBaseFontInfo", @"extensionFootnotes",
            @"editorHorizontalInset", @"editorVerticalInset",
            @"editorWidthLimited", @"editorMaximumWidth", @"editorLineSpacing",
            @"editorOnRight", @"editorStyleName", @"editorShowWordCount",
            @"editorScrollsPastEnd", @"editorShowsInvisibleCharacters",
            @"htmlMathJax", @"htmlMathJaxInlineDollar",
            @"documentZoomLevel", nil
        ];
    });
    return keys;
}

/**
 * Ordered list of document zoom multipliers used by ⌘+/⌘- and the
 * toolbar dropdown. Kept as a single source of truth so the popup and the
 * snap-step helper cannot drift apart.
 */
NS_INLINE NSArray<NSNumber *> *MPDocumentZoomLevels()
{
    static NSArray *levels = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        levels = @[@0.5, @0.75, @0.9, @1.0, @1.1, @1.25, @1.5, @2.0, @3.0];
    });
    return levels;
}

NS_INLINE NSString *MPRectStringForAutosaveName(NSString *name)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [NSString stringWithFormat:@"NSWindow Frame %@", name];
    NSString *rectString = [defaults objectForKey:key];
    return rectString;
}

NS_INLINE BOOL MPAreNilableStringsEqual(NSString *s1, NSString *s2)
{
    // The == part takes care of cases where s1 and s2 are both nil.
    return ([s1 isEqualToString:s2] || s1 == s2);
}

NS_INLINE NSColor *MPGetWebViewBackgroundColor(WebView *webview)
{
    DOMDocument *doc = webview.mainFrameDocument;
    DOMNodeList *nodes = [doc getElementsByTagName:@"body"];
    if (!nodes.length)
        return nil;

    id bodyNode = [nodes item:0];
    DOMCSSStyleDeclaration *style = [doc getComputedStyle:bodyNode
                                            pseudoElement:nil];
    return [NSColor colorWithHTMLName:[style backgroundColor]];
}


@implementation NSURL (Convert)

- (NSString *)absoluteBaseURLString
{
    // Remove fragment (#anchor) and query string.
    NSString *base = self.absoluteString;
    base = [base componentsSeparatedByString:@"?"].firstObject;
    base = [base componentsSeparatedByString:@"#"].firstObject;
    return base;
}

@end


@implementation WebView (Shortcut)

- (NSScrollView *)enclosingScrollView
{
    return self.mainFrame.frameView.documentView.enclosingScrollView;
}

@end


@implementation MPPreferences (Hoedown)
- (int)extensionFlags
{
    int flags = 0;
    if (self.extensionAutolink)
        flags |= HOEDOWN_EXT_AUTOLINK;
    if (self.extensionFencedCode)
        flags |= HOEDOWN_EXT_FENCED_CODE;
    if (self.extensionFootnotes)
        flags |= HOEDOWN_EXT_FOOTNOTES;
    if (self.extensionHighlight)
        flags |= HOEDOWN_EXT_HIGHLIGHT;
    if (!self.extensionIntraEmphasis)
        flags |= HOEDOWN_EXT_NO_INTRA_EMPHASIS;
    if (self.extensionQuote)
        flags |= HOEDOWN_EXT_QUOTE;
    if (self.extensionStrikethough)
        flags |= HOEDOWN_EXT_STRIKETHROUGH;
    if (self.extensionSuperscript)
        flags |= HOEDOWN_EXT_SUPERSCRIPT;
    if (self.extensionTables)
        flags |= HOEDOWN_EXT_TABLES;
    if (self.extensionUnderline)
        flags |= HOEDOWN_EXT_UNDERLINE;
    if (self.htmlMathJax)
        flags |= HOEDOWN_EXT_MATH;
    if (self.htmlMathJaxInlineDollar)
        flags |= HOEDOWN_EXT_MATH_EXPLICIT;
    return flags;
}

- (int)rendererFlags
{
    int flags = 0;
    if (self.htmlTaskList)
        flags |= HOEDOWN_HTML_USE_TASK_LIST;
    if (self.htmlLineNumbers)
        flags |= HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS;
    if (self.htmlHardWrap)
        flags |= HOEDOWN_HTML_HARD_WRAP;
    if (self.htmlCodeBlockAccessory == MPCodeBlockAccessoryCustom)
        flags |= HOEDOWN_HTML_BLOCKCODE_INFORMATION;
    return flags;
}
@end


@interface MPDocument ()
    <NSSplitViewDelegate, NSTextViewDelegate,
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
     WebEditingDelegate, WebFrameLoadDelegate, WebPolicyDelegate, WebResourceLoadDelegate, WebUIDelegate,
#endif
     MPAutosaving, MPRendererDataSource, MPRendererDelegate, MPResourceWatcherSetDelegate>

typedef NS_ENUM(NSUInteger, MPWordCountType) {
    MPWordCountTypeWord,
    MPWordCountTypeCharacter,
    MPWordCountTypeCharacterNoSpaces,
};

// Issue #342: Scroll ownership model — replaces four boolean flags.
// Controls which pane is authoritative for the current scroll operation.
typedef NS_ENUM(NSUInteger, MPScrollOwner) {
    MPScrollOwnerEditor  = 0,  // Editor is authoritative; preview follows
    MPScrollOwnerPreview = 1,  // User is live-scrolling preview; editor follows
    MPScrollOwnerNeither = 2,  // Quiescent; sync in either direction is valid
};

// Issue #436: Reference-point kind tag. The editor (regex over markdown) and the
// preview (DOM query in updateHeaderLocations.js) detect reference points by
// independent mechanisms that can disagree mid-document. Tagging each point with its
// kind lets validateHeaderLocationAlignment align the two sequences instead of blindly
// assuming they correspond 1:1 by index. Header values equal the header level, matching
// the kind codes emitted by updateHeaderLocations.js.
typedef NS_ENUM(NSInteger, MPReferenceKind) {
    MPReferenceKindImage = 0,
    MPReferenceKindH1    = 1,
    MPReferenceKindH2    = 2,
    MPReferenceKindH3    = 3,
    MPReferenceKindH4    = 4,
    MPReferenceKindH5    = 5,
    MPReferenceKindH6    = 6,
};

@property (weak) IBOutlet NSToolbar *toolbar;
@property (weak) IBOutlet MPDocumentSplitView *splitView;
@property (weak) IBOutlet NSView *editorContainer;
@property (unsafe_unretained) IBOutlet MPEditorView *editor;
@property (weak) IBOutlet NSLayoutConstraint *editorPaddingBottom;
@property (weak) IBOutlet WebView *preview;
@property (weak) IBOutlet NSPopUpButton *wordCountWidget;
@property (strong) IBOutlet MPToolbarController *toolbarController;
@property (copy, nonatomic) NSString *autosaveName;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (strong) MPRenderer *renderer;
@property CGFloat previousSplitRatio;
@property CGFloat lastNonCollapsedRatio;
@property BOOL manualRender;
@property BOOL printing;
@property BOOL isPreviewReady;
@property (strong) NSURL *currentBaseUrl;
@property (copy) NSString *currentStyleName;
@property (copy) NSString *currentHighlightingThemeName;
@property CGFloat lastPreviewScrollTop;
@property (nonatomic, readonly) BOOL needsHtml;
@property (nonatomic) NSUInteger totalWords;
@property (nonatomic) NSUInteger totalCharacters;
@property (nonatomic) NSUInteger totalCharactersNoSpaces;
@property (strong) NSMenuItem *wordsMenuItem;
@property (strong) NSMenuItem *charMenuItem;
@property (strong) NSMenuItem *charNoSpacesMenuItem;
@property (nonatomic) BOOL needsToUnregister;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (nonatomic) BOOL renderToWebPending;
@property (strong) NSArray<NSNumber *> *webViewHeaderLocations;
@property (strong) NSArray<NSNumber *> *editorHeaderLocations;
// Issue #436: Kind tags running parallel to the *HeaderLocations arrays. Kept private;
// the public Y-coordinate arrays stay NSNumber arrays so existing consumers are unaffected.
@property (strong) NSArray<NSNumber *> *webViewHeaderTypes;
@property (strong) NSArray<NSNumber *> *editorHeaderTypes;
@property (nonatomic) MPScrollOwner scrollOwner;  // Issue #342: Scroll ownership model
// Issue #441: Last observed value of editorSyncScrolling, used purely for edge
// detection in userDefaultsDidChange: so we can settle/re-sync the panes the
// moment the user toggles Sync Panes mid-session. Never used for gating — gating
// always reads self.preferences.editorSyncScrolling live.
@property (nonatomic) BOOL lastKnownSyncScrolling;
@property (nonatomic) NSTimeInterval lastWordCountUpdate;  // Issue #294: Throttle timestamp
@property (nonatomic) BOOL showingSelectionCount;  // Issue #452: Widget showing selection counts

// Issue #290: File watching for auto-reload
@property (strong) MPFileWatcher *fileWatcher;
@property (nonatomic) BOOL isSelfSaving;

// Issue #371: Injection seam so tests can simulate a non-local save
// destination without a real network mount. Defaults to
// +[MPFileWatcher pathIsOnLocalVolume:].
@property (nonatomic, copy) BOOL (^volumeLocalityChecker)(NSString *path);

// Issue #320: Block-based observer token for main-thread-safe defaults notification
@property (strong) id userDefaultsObserverToken;

// Issue #110: Watch local resources for cache-busting
@property (strong) MPResourceWatcherSet *resourceWatcherSet;

// Completion handlers for deferred operations when preview is hidden (issue #16)
@property (strong) NSMutableArray<void (^)(void)> *renderCompletionHandlers;

// Store file content in initializer until nib is loaded.
@property (copy) NSString *loadedString;

@property CGFloat zoomMultiplier;

- (void)scaleWebview;
- (void)syncScrollers;
- (void)syncScrollersReverse;
- (void)updateHeaderLocations;
- (void)validateHeaderLocationAlignment;
// Issue #436: Pure helpers — no view/DOM dependencies, so they are unit-testable headless.
+ (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown
                                          outLineNumbers:(NSArray<NSNumber *> **)outLineNumbers;
+ (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs
          editorTypes:(NSArray<NSNumber *> *)editorTypes
            previewYs:(NSArray<NSNumber *> *)previewYs
         previewTypes:(NSArray<NSNumber *> *)previewTypes
      alignedEditorYs:(NSArray<NSNumber *> **)outEditorYs
     alignedPreviewYs:(NSArray<NSNumber *> **)outPreviewYs;
- (void)invokeRenderCompletionHandlers;
- (void)willStartPreviewLiveScroll:(NSNotification *)notification;
- (void)didEndPreviewLiveScroll:(NSNotification *)notification;
// Commit 6 (gaps 1+3): layout-change sync
- (void)refreshHeaderCacheAfterResize;
- (void)windowDidEndLiveResize:(NSNotification *)notification;
- (void)windowDidChangeFullScreen:(NSNotification *)notification;
- (void)applyEditorStartInPreviewModePreference;
// Issue #441: Settle / re-sync the panes when Sync Panes is toggled mid-session.
- (void)handleSyncScrollingEnabled;
- (void)handleSyncScrollingDisabled;
// Preview zoom helpers
- (void)applyPreviewZoom;
- (void)stepDocumentZoomDirection:(NSInteger)direction;
// Commit 8 (gap 9): MathJax generation counter accessor (used by tests via category)
- (NSUInteger)mathJaxRenderGeneration;

@end

// Commit 8 (gap 9): ivar declared in a separate class extension to keep it private
// while still making -mathJaxRenderGeneration accessible via a compiled method.
@interface MPDocument ()
{
    NSUInteger _mathJaxRenderGeneration;
}
@end

static void (^MPGetPreviewLoadingCompletionHandler(MPDocument *doc))()
{
    __weak MPDocument *weakObj = doc;
    return ^{
        // Gap 8: weak→strong dance to avoid repeated weakObj dereferences and
        // to ensure the object is not released mid-block.
        __strong MPDocument *strongObj = weakObj;
        if (!strongObj) return;

        WebView *webView = strongObj.preview;
        NSWindow *window = webView.window;

        // Set initial scroll position BEFORE scaling to prevent flash to top
        NSClipView *contentView = webView.enclosingScrollView.contentView;
        NSRect bounds = contentView.bounds;
        bounds.origin.y = strongObj.lastPreviewScrollTop;
        contentView.bounds = bounds;

        [strongObj scaleWebview];

        // Issue #342: Only sync if editor is not currently authoritative.
        // A full reload during active typing must not overwrite the editor's position.
        if (strongObj.preferences.editorSyncScrolling
            && strongObj.scrollOwner != MPScrollOwnerEditor)
        {
            [strongObj updateHeaderLocations];
            [strongObj syncScrollers];
        }

        // Force display update before enabling window flushing to ensure scroll position is applied
        [contentView displayIfNeeded];

        // Enable window flushing AFTER scroll position is set and displayed
        @synchronized(window) {
            if (window.isFlushWindowDisabled)
            {
                [window enableFlushWindow];
                // Force immediate flush to show the correct state
                [window flushWindow];
            }
        }

        // Gap 8: Reset ownership to Neither after the full-reload completion path.
        // The DOM-replacement path already resets ownership (lines ~1389, ~1370).
        // This closes the stuck-ownership gap on the full-reload path: if reloadFromLoadedString
        // set ownership to Editor, this handler restores quiescent state after rendering
        // completes, allowing forward sync to resume on the next user-initiated scroll.
        // Placed before invokeRenderCompletionHandlers so completion handlers see reset state.
        strongObj.scrollOwner = MPScrollOwnerNeither;

        // Issue #16: Invoke deferred operation handlers after render completes
        // (This is called for MathJax rendering completion path)
        [strongObj invokeRenderCompletionHandlers];
    };
}


/**
 * Issue #436: Scans a single line for a fenced-code-block marker (a run of 3+ backticks or
 * tildes, allowing 0-3 leading spaces). Returns YES and reports the marker character, its
 * length, and whether any non-whitespace follows the run. A backtick run whose info string
 * contains a backtick is not a valid fence marker (per CommonMark), so it returns NO.
 * The caller decides whether the marker opens or closes a fence.
 */
static BOOL MPScanFenceMarker(NSString *line, unichar *outChar, NSUInteger *outLength,
                              BOOL *outHasTrailingContent)
{
    NSUInteger length = line.length;
    NSUInteger i = 0;
    NSUInteger leadingSpaces = 0;
    while (i < length && [line characterAtIndex:i] == ' ') { i++; leadingSpaces++; }
    if (leadingSpaces > 3 || i >= length)
        return NO;  // 4+ leading spaces is indented code, not a fence.

    unichar marker = [line characterAtIndex:i];
    if (marker != '`' && marker != '~')
        return NO;

    NSUInteger runStart = i;
    while (i < length && [line characterAtIndex:i] == marker) i++;
    NSUInteger runLength = i - runStart;
    if (runLength < 3)
        return NO;

    BOOL hasTrailing = NO;
    BOOL hasBacktickAfter = NO;
    for (NSUInteger j = i; j < length; j++) {
        unichar c = [line characterAtIndex:j];
        if (c != ' ' && c != '\t') hasTrailing = YES;
        if (c == '`') hasBacktickAfter = YES;
    }
    // A backtick fence's info string may not contain backticks.
    if (marker == '`' && hasBacktickAfter)
        return NO;

    if (outChar) *outChar = marker;
    if (outLength) *outLength = runLength;
    if (outHasTrailingContent) *outHasTrailingContent = hasTrailing;
    return YES;
}


@implementation MPDocument

#pragma mark - Accessor

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSString *)markdown
{
    return self.editor.string;
}

- (void)setMarkdown:(NSString *)markdown
{
    self.editor.string = markdown;
}

- (NSString *)html
{
    return self.renderer.currentHtml;
}

- (BOOL)toolbarVisible
{
    return self.windowForSheet.toolbar.visible;
}

- (BOOL)previewVisible
{
    return (self.preview.frame.size.width != 0.0);
}

- (BOOL)editorVisible
{
    return (self.editorContainer.frame.size.width != 0.0);
}

- (BOOL)needsHtml
{
    if (self.preferences.markdownManualRender)
        return NO;
    return (self.previewVisible || self.preferences.editorShowWordCount);
}

// Issue #452: Build a localized, pluralized count title. The `selected` flag
// chooses the "… selected" variant of each key.
- (NSString *)wordCountTitleForKey:(NSString *)key number:(NSUInteger)value
{
    NSInteger rule = kJJPluralFormRule.integerValue;
    return [JJPluralForm pluralStringForNumber:value
                               withPluralForms:NSLocalizedString(key, @"")
                               usingPluralRule:rule localizeNumeral:NO];
}

- (void)applyWordsTitle:(NSUInteger)value selected:(BOOL)selected
{
    self.wordsMenuItem.title = [self wordCountTitleForKey:
        (selected ? @"WORDS_SELECTED_PLURAL_STRING" : @"WORDS_PLURAL_STRING")
                                                   number:value];
}

- (void)applyCharactersTitle:(NSUInteger)value selected:(BOOL)selected
{
    self.charMenuItem.title = [self wordCountTitleForKey:
        (selected ? @"CHARACTERS_SELECTED_PLURAL_STRING"
                  : @"CHARACTERS_PLURAL_STRING")
                                                  number:value];
}

- (void)applyCharactersNoSpacesTitle:(NSUInteger)value selected:(BOOL)selected
{
    self.charNoSpacesMenuItem.title = [self wordCountTitleForKey:
        (selected ? @"CHARACTERS_NO_SPACES_SELECTED_PLURAL_STRING"
                  : @"CHARACTERS_NO_SPACES_PLURAL_STRING")
                                                          number:value];
}

// Issue #452: Document-total setters always store the latest value, but only
// write the menu titles when the widget isn't showing selection counts — this
// keeps a throttled updateWordCount from clobbering the selection display.
- (void)setTotalWords:(NSUInteger)value
{
    _totalWords = value;
    if (!self.showingSelectionCount)
        [self applyWordsTitle:value selected:NO];
}

- (void)setTotalCharacters:(NSUInteger)value
{
    _totalCharacters = value;
    if (!self.showingSelectionCount)
        [self applyCharactersTitle:value selected:NO];
}

- (void)setTotalCharactersNoSpaces:(NSUInteger)value
{
    _totalCharactersNoSpaces = value;
    if (!self.showingSelectionCount)
        [self applyCharactersNoSpacesTitle:value selected:NO];
}

- (void)setAutosaveName:(NSString *)autosaveName
{
    _autosaveName = autosaveName;
    self.splitView.autosaveName = autosaveName;
}

// Commit 8 (gap 9): Accessor for test introspection. The ivar itself is private
// (declared in a class extension); this method is the exposed interface.
- (NSUInteger)mathJaxRenderGeneration
{
    return _mathJaxRenderGeneration;
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.isPreviewReady = NO;
    _scrollOwner = MPScrollOwnerNeither;
    self.previousSplitRatio = -1.0;
    self.lastNonCollapsedRatio = -1.0;
    // Issue #441: Seed the cached Sync Panes value from the live preference so the
    // first NSUserDefaultsDidChangeNotification (which fires for any default) is not
    // misread as a transition.
    _lastKnownSyncScrolling = [MPPreferences sharedInstance].editorSyncScrolling;

    // Issue #371: Default locality checker; tests may override this to
    // simulate a non-local destination.
    self.volumeLocalityChecker = ^BOOL(NSString *path) {
        return [MPFileWatcher pathIsOnLocalVolume:path];
    };
    return self;
}

- (NSString *)windowNibName
{
    return @"MPDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib:controller];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // All files use their absolute path to keep their window states.
    NSString *autosaveName = kMPDefaultAutosaveName;
    if (self.fileURL)
        autosaveName = self.fileURL.absoluteString;
    controller.window.frameAutosaveName = autosaveName;
    self.autosaveName = autosaveName;

    // Perform initial resizing manually because for some reason untitled
    // documents do not pick up the autosaved frame automatically in 10.10.
    NSString *rectString = MPRectStringForAutosaveName(autosaveName);
    if (!rectString)
        rectString = MPRectStringForAutosaveName(kMPDefaultAutosaveName);
    if (rectString)
        [controller.window setFrameFromString:rectString];
    else
        [controller.window center];  // No saved position;

    self.highlighter =
        [[HGMarkdownHighlighter alloc] initWithTextView:self.editor
                                           waitInterval:0.0];
    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self;
    self.renderer.delegate = self;

    for (NSString *key in MPEditorPreferencesToObserve())
    {
        [defaults addObserver:self forKeyPath:key
                      options:NSKeyValueObservingOptionNew context:NULL];
    }
    for (NSString *key in MPEditorKeysToObserve())
    {
        [self.editor addObserver:self forKeyPath:key
                         options:NSKeyValueObservingOptionNew context:NULL];
    }

    self.editor.postsFrameChangedNotifications = YES;
    self.preview.frameLoadDelegate = self;
    self.preview.policyDelegate = self;
    self.preview.editingDelegate = self;
    self.preview.resourceLoadDelegate = self;
    self.preview.UIDelegate = self;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(editorTextDidChange:)
                   name:NSTextDidChangeNotification object:self.editor];
    // Issue #452: Update the count widget to reflect the editor selection.
    [center addObserver:self selector:@selector(editorSelectionDidChange:)
                   name:NSTextViewDidChangeSelectionNotification
                 object:self.editor];
    // Issue #320: Use block-based observer with mainQueue to guarantee
    // main-thread delivery of NSUserDefaultsDidChangeNotification.
    __weak typeof(self) weakSelf = self;
    self.userDefaultsObserverToken = [center
        addObserverForName:NSUserDefaultsDidChangeNotification
                    object:[NSUserDefaults standardUserDefaults]
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        [weakSelf userDefaultsDidChange:notification];
    }];
    [center addObserver:self selector:@selector(editorBoundsDidChange:)
                   name:NSViewBoundsDidChangeNotification
                 object:self.editor.enclosingScrollView.contentView];
    [center addObserver:self selector:@selector(editorFrameDidChange:)
                   name:NSViewFrameDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(didRequestEditorReload:)
                   name:MPDidRequestEditorSetupNotification object:nil];
    [center addObserver:self selector:@selector(didRequestPreviewReload:)
                   name:MPDidRequestPreviewRenderNotification object:nil];
    [center addObserver:self selector:@selector(willStartLiveScroll:)
                   name:NSScrollViewWillStartLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    [center addObserver:self selector:@selector(didEndLiveScroll:)
                   name:NSScrollViewDidEndLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    // Issue #342: Observers for preview live-scroll ownership model
    [center addObserver:self selector:@selector(willStartPreviewLiveScroll:)
                   name:NSScrollViewWillStartLiveScrollNotification
                 object:self.preview.enclosingScrollView];
    [center addObserver:self selector:@selector(didEndPreviewLiveScroll:)
                   name:NSScrollViewDidEndLiveScrollNotification
                 object:self.preview.enclosingScrollView];
    [center addObserver:self selector:@selector(previewBoundsDidChange:)
                   name:NSViewBoundsDidChangeNotification
                 object:self.preview.enclosingScrollView.contentView];

    self.needsToUnregister = YES;

    self.wordsMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                             keyEquivalent:@""];
    self.charMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                            keyEquivalent:@""];
    self.charNoSpacesMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                           action:NULL
                                                    keyEquivalent:@""];

    NSPopUpButton *wordCountWidget = self.wordCountWidget;
    [wordCountWidget removeAllItems];
    [wordCountWidget.menu addItem:self.wordsMenuItem];
    [wordCountWidget.menu addItem:self.charMenuItem];
    [wordCountWidget.menu addItem:self.charNoSpacesMenuItem];
    [wordCountWidget selectItemAtIndex:self.preferences.editorWordCountType];
    wordCountWidget.alphaValue = 0.9;
    wordCountWidget.hidden = !self.preferences.editorShowWordCount;
    wordCountWidget.enabled = NO;

    // These needs to be queued until after the window is shown, so that editor
    // can have the correct dimention for size-limiting and stuff. See
    // https://github.com/uranusjr/macdown/issues/236
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self setupEditor:nil];
        [self redrawDivider];
        [self reloadFromLoadedString];

        // Issue #290: Start file watching for auto-reload
        [self startFileWatching];

        // Force layout before reading dividerLocation. The startup preference
        // path depends on current subview widths, and split-view autosave may
        // not have pushed those frames into the content view hierarchy yet.
        [controller.window.contentView layoutSubtreeIfNeeded];
        [self applyEditorStartInPreviewModePreference];

        // Commit 6 (gaps 1+3): Register for window resize/fullscreen notifications.
        // Registered here (not in the main setup block) because self.editor.window
        // may be nil before the window is shown.
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(windowDidEndLiveResize:)
                       name:NSWindowDidEndLiveResizeNotification object:self.editor.window];
        [center addObserver:self selector:@selector(windowDidChangeFullScreen:)
                       name:NSWindowDidEnterFullScreenNotification object:self.editor.window];
        [center addObserver:self selector:@selector(windowDidChangeFullScreen:)
                       name:NSWindowDidExitFullScreenNotification object:self.editor.window];
    }];
}

- (void)reloadFromLoadedString
{
    if (self.editor && self.renderer && self.highlighter)
    {
        if (self.loadedString)
        {
            self.editor.string = self.loadedString;
            self.loadedString = nil;
            [self.highlighter clearHighlighting];
            [self.highlighter readClearTextStylesFromTextView];
        }

        // Gap 8: Claim editor ownership before rendering so that the full-reload
        // completion handler's sync guard (scrollOwner != MPScrollOwnerEditor) skips
        // syncScrollers. This is correct — after a revert, the editor content changed
        // and the preview is about to re-render to match. The completion handler restores
        // lastPreviewScrollTop and resets ownership to Neither; forward sync resumes on
        // the next user-initiated scroll.
        //
        // isPreviewReady == NO during initial load (only YES after the first successful
        // frame load), so this only fires for revert-triggered calls, not the initial load.
        //
        // Note: if the user was mid-preview-scroll when an external change triggers reload,
        // MPScrollOwnerPreview gets overwritten to Editor. This is intentional — external
        // file changes take priority.
        if (self.isPreviewReady)
            _scrollOwner = MPScrollOwnerEditor;

        [self.renderer parseAndRenderNow];
        [self.highlighter parseAndHighlightNow];
    }
}

- (void)close
{
    if (self.needsToUnregister)
    {
        // Close can be called multiple times, but this can only be done once.
        // http://www.cocoabuilder.com/archive/cocoa/240166-nsdocument-close-method-calls-itself.html
        self.needsToUnregister = NO;

        // Issue #294: Cancel any pending word count updates
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(updateWordCount)
                                                   object:nil];

        // Commit 6 (gaps 1+3): Cancel any pending coalesced header cache refresh.
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                    selector:@selector(refreshHeaderCacheAfterResize) object:nil];

        // Issue #290: Stop file watching to prevent leaks
        [self stopFileWatching];

        // Need to cleanup these so that callbacks won't crash the app.
        [self.highlighter deactivate];
        self.highlighter.targetTextView = nil;
        self.highlighter = nil;
        self.renderer = nil;
        self.preview.frameLoadDelegate = nil;
        self.preview.policyDelegate = nil;
        self.preview.UIDelegate = nil;

        // Issue #320: Remove block-based defaults observer token
        if (self.userDefaultsObserverToken) {
            [[NSNotificationCenter defaultCenter]
                removeObserver:self.userDefaultsObserverToken];
            self.userDefaultsObserverToken = nil;
        }

        [[NSNotificationCenter defaultCenter] removeObserver:self];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        for (NSString *key in MPEditorPreferencesToObserve())
            [defaults removeObserver:self forKeyPath:key];
        for (NSString *key in MPEditorKeysToObserve())
            [self.editor removeObserver:self forKeyPath:key];
    }

    [super close];
}

+ (BOOL)autosavesInPlace
{
    return [MPPreferences sharedInstance].editorAutoSave;
}

+ (NSArray *)writableTypes
{
    return @[@"net.daringfireball.markdown"];
}

- (BOOL)isDocumentEdited
{
    // Prevent save dialog on an unnamed, empty document. The file will still
    // show as modified (because it is), but no save dialog will be presented
    // when the user closes it.
    if (!self.presentedItemURL && !self.editor.string.length)
        return NO;
    return [super isDocumentEdited];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
             error:(NSError *__autoreleasing *)outError
{
    // Issue #290: Mark that we're saving to avoid triggering reload
    self.isSelfSaving = YES;

    // Issue #290: Capture previous URL before super updates it (for Save As detection)
    NSURL *previousURL = self.fileURL;

    if (self.preferences.editorEnsuresNewlineAtEndOfFile)
    {
        NSCharacterSet *newline = [NSCharacterSet newlineCharacterSet];
        NSString *text = self.editor.string;
        NSUInteger end = text.length;
        if (end && ![newline characterIsMember:[text characterAtIndex:end - 1]])
        {
            NSRange selection = self.editor.selectedRange;
            [self.editor insertText:@"\n" replacementRange:NSMakeRange(end, 0)];
            self.editor.selectedRange = selection;
        }
    }

    BOOL result = [super writeToURL:url ofType:typeName error:outError];

    // Issue #290: Clear save flag after a short delay to ensure
    // the file watcher doesn't trigger (events may be coalesced)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.isSelfSaving = NO;
    });

    // If URL changed (Save As), restart watching the new file
    if (result && (!previousURL || ![url isEqual:previousURL]))
    {
        // URL was updated by super, restart watching the new file
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startFileWatching];
        });
    }

    return result;
}

- (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)typeName
         forSaveOperation:(NSSaveOperationType)saveOperation
                    error:(NSError *__autoreleasing *)outError
{
    // Issue #371: NSDocument's default "safe save" writes to a temp file and
    // swaps it into place via NSFileCoordinator, plus checks the destination's
    // on-disk modification date for conflicts. Both are unreliable on
    // FUSE/network volumes (mtime semantics are inconsistent, and the
    // temp-file swap can fail outright), producing a spurious "changed by
    // another application" conflict dialog followed by a hard save failure.
    // The "volume does not support permanent version storage" prompt is also
    // raised from within this same call chain, so it should no longer appear
    // for these documents either — confirmed by code inspection, but as with
    // the rest of this method, real-world behavior on an actual network mount
    // has not been (and cannot be, in CI) directly observed.
    //
    // For non-local destinations, skip NSFileCoordinator-mediated coordination
    // entirely and write directly. This is a deliberate trade-off: the
    // coordinated temp-file dance is itself what's unreliable on these
    // volumes, and MPFileWatcher already declines to watch (i.e. act as a
    // file presenter for) non-local paths, so there's no in-process presenter
    // left to race with here.
    //
    // Checked against `url` (the destination), not self.fileURL, so a Save As
    // across volumes is classified by where the file is going, not where it
    // came from.
    if ([self shouldBypassSafeSaveForURL:url])
    {
        return [self writeToURL:url ofType:typeName
                forSaveOperation:saveOperation
             originalContentsURL:self.fileURL error:outError];
    }
    return [super writeSafelyToURL:url ofType:typeName
                   forSaveOperation:saveOperation error:outError];
}

// Issue #371: Split out for test exposure. Checks `url` (the save
// destination) rather than self.fileURL, so Save As across volumes is
// classified by where the file is going, not where it came from. Goes
// through volumeLocalityChecker (rather than calling MPFileWatcher directly)
// so tests can simulate a non-local destination without a real network mount.
- (BOOL)shouldBypassSafeSaveForURL:(NSURL *)url
{
    return url.isFileURL && !self.volumeLocalityChecker(url.path);
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    return [self.editor.string dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName
               error:(NSError **)outError
{
    NSString *content = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (!content)
        return NO;

    // Normalize Windows CRLF to LF (Issue #382)
    content = [content stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];

    self.loadedString = content;
    [self reloadFromLoadedString];
    return YES;
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
    savePanel.extensionHidden = NO;
    if (self.fileURL && self.fileURL.isFileURL)
    {
        NSString *path = self.fileURL.path;

        // Use path of parent directory if this is a file. Otherwise this is it.
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path
                                                           isDirectory:&isDir];
        if (!exists || !isDir)
            path = [path stringByDeletingLastPathComponent];

        savePanel.directoryURL = [NSURL fileURLWithPath:path];
    }
    else
    {
        // Suggest a file name for new documents.
        NSString *fileName = self.presumedFileName;
        if (fileName && ![fileName hasExtension:@"md"])
        {
            fileName = [fileName stringByAppendingPathExtension:@"md"];
            savePanel.nameFieldStringValue = fileName;
        }
    }
    
    // Get supported extensions from plist
    static NSMutableArray *supportedExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supportedExtensions = [NSMutableArray array];
        NSDictionary *infoDict = [NSBundle mainBundle].infoDictionary;
        for (NSDictionary *docType in infoDict[@"CFBundleDocumentTypes"])
        {
            NSArray *exts = docType[@"CFBundleTypeExtensions"];
            if (exts.count)
            {
                [supportedExtensions addObjectsFromArray:exts];
            }
        }
    });
    
    savePanel.allowedFileTypes = supportedExtensions;
    savePanel.allowsOtherFileTypes = YES; // Allow all extensions.
    
    return [super prepareSavePanel:savePanel];
}

- (NSPrintInfo *)printInfo
{
    NSPrintInfo *info = [super printInfo];
    if (!info)
        info = [[NSPrintInfo sharedPrintInfo] copy];
    info.horizontalPagination = NSAutoPagination;
    info.verticalPagination = NSAutoPagination;
    info.verticallyCentered = NO;
    return info;
}

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings
                                           error:(NSError *__autoreleasing *)e
{
    NSPrintInfo *info = [self.printInfo copy];
    [info.dictionary addEntriesFromDictionary:printSettings];

    WebFrameView *view = self.preview.mainFrame.frameView;
    NSPrintOperation *op = [view printOperationWithPrintInfo:info];
    return op;
}

- (void)printDocumentWithSettings:(NSDictionary *)printSettings
                   showPrintPanel:(BOOL)showPrintPanel delegate:(id)delegate
                 didPrintSelector:(SEL)selector contextInfo:(void *)contextInfo
{
    // Issue #16: Ensure WebView content is up-to-date before printing.
    // Capture all parameters for use in the deferred block.
    NSDictionary *settings = [printSettings copy];
    BOOL showPanel = showPrintPanel;
    id printDelegate = delegate;
    SEL printSelector = selector;
    void *context = contextInfo;

    [self performAfterRender:^{
        self.printing = YES;
        NSInvocation *invocation = nil;
        if (printDelegate && printSelector)
        {
            NSMethodSignature *signature =
                [printDelegate methodSignatureForSelector:printSelector];
            invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = printDelegate;
            if (context)
                [invocation setArgument:&context atIndex:2];
        }
        [super printDocumentWithSettings:settings
                          showPrintPanel:showPanel delegate:self
                        didPrintSelector:@selector(document:didPrint:context:)
                             contextInfo:(void *)invocation];
    }];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    BOOL result = [super validateUserInterfaceItem:item];
    SEL action = item.action;
    
    // Zoom menu validation
    if (action == @selector(zoomIn:))
    {
        return self.zoomMultiplier < kMPMaxZoom;
    }
    else if (action == @selector(zoomOut:))
    {
        return self.zoomMultiplier > kMPMinZoom;
    }
    else if (action == @selector(resetZoom:))
    {
        return fabs(self.zoomMultiplier - 1.0) > 0.001;
    }
    else if (action == @selector(toggleToolbar:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.title = self.toolbarVisible ?
            NSLocalizedString(@"Hide Toolbar",
                              @"Toggle reveal toolbar") :
            NSLocalizedString(@"Show Toolbar",
                              @"Toggle reveal toolbar");
    }
    else if (action == @selector(togglePreviewPane:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.hidden = (!self.previewVisible && self.previousSplitRatio < 0.0);
        it.title = self.previewVisible ?
            NSLocalizedString(@"Hide Preview Pane",
                              @"Toggle preview pane menu item") :
            NSLocalizedString(@"Restore Preview Pane",
                              @"Toggle preview pane menu item");

        // Issue #23: Disable "Hide Preview" when editor is not visible
        // (hiding preview would leave no visible panes)
        if (self.previewVisible && !self.editorVisible)
        {
            return NO;
        }
    }
    else if (action == @selector(toggleEditorPane:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.hidden = (!self.editorVisible && self.previousSplitRatio < 0.0);
        it.title = self.editorVisible ?
            NSLocalizedString(@"Hide Editor Pane",
                              @"Toggle editor pane menu item") :
            NSLocalizedString(@"Restore Editor Pane",
                              @"Toggle editor pane menu item");

        // Issue #23: Disable "Hide Editor" when preview is not visible
        // (hiding editor would leave no visible panes)
        if (self.editorVisible && !self.previewVisible)
        {
            return NO;
        }
    }
    else if (action == @selector(toggleAutoSave:))
    {
        if ([(id)item isKindOfClass:[NSMenuItem class]])
            ((NSMenuItem *)item).state = self.preferences.editorAutoSave ?
                NSControlStateValueOn : NSControlStateValueOff;
    }
    else if (action == @selector(toggleInvisibleCharacters:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.state = self.preferences.editorShowsInvisibleCharacters
            ? NSControlStateValueOn : NSControlStateValueOff;
        return self.editor != nil;
    }
    else if (action == @selector(selectDocumentZoom:))
    {
        return YES;
    }
    return result;
}


#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    [self redrawDivider];
    self.editor.editable = self.editorVisible;
    // Issue #377: Track divider-drag collapses. When the ratio transitions from
    // a non-collapsed value to 0 or 1, save the pre-collapse ratio to
    // previousSplitRatio so the menu item remains visible (not hidden).
    CGFloat ratio = self.splitView.dividerLocation;
    if (ratio > 0.0 && ratio < 1.0)
    {
        self.lastNonCollapsedRatio = ratio;
    }
    else if (self.previousSplitRatio < 0.0 && self.lastNonCollapsedRatio > 0.0)
    {
        // Pane collapsed (ratio is 0 or 1) and previousSplitRatio was never set
        // by the menu toggle path — this is a divider-drag collapse.
        self.previousSplitRatio = self.lastNonCollapsedRatio;
    }
    // Commit 6 (gaps 1+3): Coalesce header cache refresh to next run loop iteration,
    // after layout manager reflows. Split-divider drags fire many notifications rapidly.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                selector:@selector(refreshHeaderCacheAfterResize) object:nil];
    [self performSelector:@selector(refreshHeaderCacheAfterResize)
               withObject:nil afterDelay:0];
}

// Issue #377: Allow NSSplitView to collapse subviews to zero width during
// divider drags. Without this, dragging the divider to the edge may not
// fully collapse the pane. Returns YES for both subviews unconditionally
// (regardless of editorOnRight preference) since either pane can be hidden.
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    return YES;
}


#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(insertTab:))
        return ![self textViewShouldInsertTab:textView];
    else if (commandSelector == @selector(insertBacktab:))
        return ![self textViewShouldInsertBacktab:textView];
    else if (commandSelector == @selector(insertNewline:))
        return ![self textViewShouldInsertNewline:textView];
    else if (commandSelector == @selector(deleteBackward:))
        return ![self textViewShouldDeleteBackward:textView];
    else if (commandSelector == @selector(moveToLeftEndOfLine:))
        return ![self textViewShouldMoveToLeftEndOfLine:textView];
    return NO;
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range
                                              replacementString:(NSString *)str
{
    // Ignore if this originates from an IM marked text commit event.
    if (NSIntersectionRange(textView.markedRange, range).length)
        return YES;

    if (self.preferences.editorCompleteMatchingCharacters)
    {
        BOOL strikethrough = self.preferences.extensionStrikethough;
        if ([textView completeMatchingCharactersForTextInRange:range
                                                    withString:str
                                          strikethroughEnabled:strikethrough])
            return NO;
    }
    
	// For every change, set the typing attributes
	if (range.location > 0) {
		NSRange prevRange = range;
		prevRange.location -= 1;
		prevRange.length = 1;

		NSDictionary *attr = [[textView attributedString] fontAttributesInRange:prevRange];
		[textView setTypingAttributes:attr];
	}

    return YES;
}

#pragma mark - Fake NSTextViewDelegate

- (BOOL)textViewShouldInsertTab:(NSTextView *)textView
{
    if (textView.selectedRange.length != 0)
    {
        [self indent:nil];
        return NO;
    }
    else if (self.preferences.editorConvertTabs)
    {
        [textView insertSpacesForTab];
        return NO;
    }
    return YES;
}

- (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView
{
    [self unindent:nil];
    return NO;
}

- (BOOL)textViewShouldInsertNewline:(NSTextView *)textView
{
    if ([textView insertMappedContent])
        return NO;

    BOOL inserts = self.preferences.editorInsertPrefixInBlock;
    if (inserts && [textView completeNextListItem:
            self.preferences.editorAutoIncrementNumberedLists])
        return NO;
    if (inserts && [textView completeNextBlockquoteLine])
        return NO;
    if ([textView completeNextIndentedLine])
        return NO;
    return YES;
}

- (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView
{
    NSRange selectedRange = textView.selectedRange;
    if (self.preferences.editorCompleteMatchingCharacters)
    {
        NSUInteger location = selectedRange.location;
        if ([textView deleteMatchingCharactersAround:location])
            return NO;
    }
    if (self.preferences.editorConvertTabs && !selectedRange.length)
    {
        NSUInteger location = selectedRange.location;
        if ([textView unindentForSpacesBefore:location])
            return NO;
    }
    return YES;
}

- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView
{
    if (!self.preferences.editorSmartHome)
        return YES;
    NSUInteger cur = textView.selectedRange.location;
    NSUInteger location =
        [textView.string locationOfFirstNonWhitespaceCharacterInLineBefore:cur];
    if (location == cur || cur == 0)
        return YES;
    else if (cur >= textView.string.length)
        cur = textView.string.length - 1;

    // We don't want to jump rows when the line is wrapped. (#103)
    // If the line is wrapped, the target will be higher than the current glyph.
    NSLayoutManager *manager = textView.layoutManager;
    NSTextContainer *container = textView.textContainer;
    NSRect targetRect =
        [manager boundingRectForGlyphRange:NSMakeRange(location, 1)
                           inTextContainer:container];
    NSRect currentRect =
        [manager boundingRectForGlyphRange:NSMakeRange(cur, 1)
                           inTextContainer:container];
    if (targetRect.origin.y != currentRect.origin.y)
        return YES;

    textView.selectedRange = NSMakeRange(location, 0);
    return NO;
}


#pragma mark - WebResourceLoadDelegate

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
{

    if ([[request.URL lastPathComponent] isEqualToString:@"MathJax.js"])
    {
        NSURLComponents *origComps = [NSURLComponents componentsWithURL:[request URL] resolvingAgainstBaseURL:YES];
        NSURLComponents *updatedComps = [NSURLComponents componentsWithURL:[[NSBundle mainBundle] URLForResource:@"MathJax" withExtension:@"js" subdirectory:@"MathJax"] resolvingAgainstBaseURL:NO];
        [updatedComps setQueryItems:[origComps queryItems]];

        request = [NSURLRequest requestWithURL:[updatedComps URL]];
    }

    return request;
}

#pragma mark - WebFrameLoadDelegate

- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    NSWindow *window = sender.window;

    @synchronized(window) {
        if (!window.isFlushWindowDisabled)
        {
            [window disableFlushWindow];
        }
    }

    // If MathJax is off, the on-completion callback will be invoked directly
    // when loading is done (in -webView:didFinishLoadForFrame:).
    if (self.preferences.htmlMathJax)
    {
        MPMathJaxListener *listener = [[MPMathJaxListener alloc] init];
        [listener addCallback:MPGetPreviewLoadingCompletionHandler(self)
                       forKey:@"End"];
        [sender.windowScriptObject setValue:listener forKey:@"MathJaxListener"];
    }
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    // If MathJax is on, the on-completion callback will be invoked by the
    // JavaScript handler injected in -webView:didCommitLoadForFrame:.
    if (!self.preferences.htmlMathJax)
    {
        id callback = MPGetPreviewLoadingCompletionHandler(self);
        NSOperationQueue *queue = [NSOperationQueue mainQueue];
        [queue addOperationWithBlock:callback];
    }

    self.isPreviewReady = YES;

    // Update word count
    if (self.preferences.editorShowWordCount)
        [self updateWordCount];

    self.alreadyRenderingInWeb = NO;

    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];

    self.renderToWebPending = NO;

    // Issue #16: Invoke deferred operation handlers after render completes
    [self invokeRenderCompletionHandlers];

    // Re-apply the preview pane page-size multiplier. WebKit resets the
    // multiplier when a new document loads, so each finished mainFrame load
    // needs to restore the user's preference. Restrict to mainFrame so
    // subframe (e.g. iframe) loads do not stomp the top-level zoom.
    if (frame == sender.mainFrame)
        [self applyPreviewZoom];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error
       forFrame:(WebFrame *)frame
{
    [self webView:sender didFinishLoadForFrame:frame];
    
    self.alreadyRenderingInWeb = NO;

    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];

    self.renderToWebPending = NO;
}


#pragma mark - WebPolicyDelegate

- (void)webView:(WebView *)webView
                decidePolicyForNavigationAction:(NSDictionary *)information
        request:(NSURLRequest *)request frame:(WebFrame *)frame
                decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL *url = request.URL;

    // Handle interactive checkbox toggle. Related to GitHub issue #269.
    if ([url.scheme isEqualToString:@"x-macdown-checkbox"])
    {
        [listener ignore];
        [self handleCheckboxToggle:url];
        return;
    }

    switch ([information[WebActionNavigationTypeKey] integerValue])
    {
        case WebNavigationTypeLinkClicked:
            // If the target is exactly as the current one, ignore.
            if ([self.currentBaseUrl isEqual:url])
            {
                [listener ignore];
                return;
            }
            // If this is a different page, intercept and handle ourselves.
            else if (![self isCurrentBaseUrl:url])
            {
                [listener ignore];
                [self openOrCreateFileForUrl:url];
                return;
            }
            // Otherwise this is somewhere else on the same page. Jump there.
            break;
        default:
            // CVE-2019-12173: Block file:// navigations from non-user-initiated
            // actions (e.g., JavaScript auto-click) unless they target the
            // current document scope and are not executable.
            //
            // Note: WebKit may classify JS element.click() as
            // WebNavigationTypeLinkClicked, routing it through
            // openOrCreateFileForUrl: instead. That path has its own
            // executable guard, so the CVE is closed either way.
            //
            // User-clicked file:// links intentionally skip the scope check —
            // opening local documents (PDFs, images) from Markdown links is a
            // legitimate use case. Only executables are blocked for user clicks.
            if (url.isFileURL)
            {
                NSURL *baseURL = self.currentBaseUrl ?: self.fileURL;
                if (!baseURL || !baseURL.isFileURL)
                {
                    // Untitled documents have no base URL; silently ignore.
                    [listener ignore];
                    return;
                }
                if (![MPURLSecurityPolicy url:url isWithinScopeOfBaseURL:baseURL]
                    || [MPURLSecurityPolicy isExecutableOrAppBundleAtURL:url])
                {
                    NSLog(@"MacDown: Blocked file:// navigation for security: %@", url);
                    [listener ignore];
                    return;
                }
            }
            break;
    }
    [listener use];
}


#pragma mark - WebEditingDelegate

- (BOOL)webView:(WebView *)webView doCommandBySelector:(SEL)selector
{
    if (selector == @selector(copy:))
    {
        NSString *html = webView.selectedDOMRange.markupString;

        // Inject the HTML content later so that it doesn't get cleared during
        // the native copy operation.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            if (![pb stringForType:@"public.html"])
                [pb setString:html forType:@"public.html"];
        }];
    }
    return NO;
}

#pragma mark - WebUIDelegate

- (NSUInteger)webView:(WebView *)webView
        dragDestinationActionMaskForDraggingInfo:(id<NSDraggingInfo>)info
{
    return WebDragDestinationActionNone;
}

- (NSArray *)webView:(WebView *)sender
        contextMenuItemsForElement:(NSDictionary *)element
        defaultMenuItems:(NSArray *)defaultMenuItems
{
    NSMutableArray *items = [NSMutableArray arrayWithArray:defaultMenuItems];

    for (NSInteger i = 0; i < items.count; i++)
    {
        NSMenuItem *item = items[i];
        if (item.tag == WebMenuItemTagReload)
        {
            NSMenuItem *reloadItem = [[NSMenuItem alloc]
                initWithTitle:item.title
                action:@selector(reloadPreview:)
                keyEquivalent:@""];
            reloadItem.target = self;
            [items replaceObjectAtIndex:i withObject:reloadItem];
            break;
        }
    }

    return items;
}

- (void)reloadPreview:(id)sender
{
    // Issue #318: Force CSS refresh from disk on explicit reload
    [self invalidateStyleCaches];
    [self.renderer parseAndRenderNow];
}

#pragma mark - MPRendererDataSource

- (BOOL)rendererLoading {
	return self.preview.loading;
}
    
- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    return self.editor.string;
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    NSString *n = self.fileURL.lastPathComponent.stringByDeletingPathExtension;
    return n ? n : @"";
}


#pragma mark - MPRendererDelegate

- (int)rendererExtensions:(MPRenderer *)renderer
{
    return self.preferences.extensionFlags;
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.preferences.extensionSmartyPants;
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    return self.preferences.htmlRendersTOC;
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    return self.preferences.htmlStyleName;
}

- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.preferences.htmlDetectFrontMatter;
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    return self.preferences.htmlSyntaxHighlighting;
}

- (BOOL)rendererHasMermaid:(MPRenderer *)renderer
{
    return self.preferences.htmlMermaid;
}

- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
{
    return self.preferences.htmlGraphviz;
}

- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return self.preferences.htmlCodeBlockAccessory;
}

- (BOOL)rendererHasMathJax:(MPRenderer *)renderer
{
    return self.preferences.htmlMathJax;
}

- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return self.preferences.htmlHighlightingThemeName;
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    // Issue #358: Only gate on alreadyRenderingInWeb when the preview has
    // completed its first load (isPreviewReady == YES).  Before the first
    // successful load, WebView frame-load delegate callbacks may not fire,
    // which leaves alreadyRenderingInWeb stuck at YES forever, blocking all
    // subsequent renders.  Allowing renders through before isPreviewReady
    // is safe because each call to loadHTMLString: simply replaces the
    // previous in-flight load.
    if (self.isPreviewReady && self.alreadyRenderingInWeb)
    {
        self.renderToWebPending = YES;
        return;
    }

    if (self.printing)
        return;

    self.alreadyRenderingInWeb = YES;

    NSURL *baseUrl = self.fileURL;
    if (!baseUrl)   // Unsaved doument; just use the default URL.
        baseUrl = self.preferences.htmlDefaultDirectoryUrl;
    baseUrl = [self previewSafeBaseURL:baseUrl];

    self.manualRender = self.preferences.markdownManualRender;

    // Issue #110: Update resource file watchers based on referenced local files.
    // Run on every render (both DOM replacement and full reload) so that newly
    // added resource references are watched immediately.
    if (self.resourceWatcherSet && baseUrl)
    {
        NSSet *paths = MPLocalFilePathsInHTML(html, baseUrl);
        [self.resourceWatcherSet updateWatchedPaths:paths];
    }

    // Check if CSS style or highlighting theme has changed.
    // If either changed, we must do a full reload to update <head> with new CSS links.
    NSString *newStyleName = self.preferences.htmlStyleName;
    NSString *newHighlightingTheme = self.preferences.htmlHighlightingThemeName;
    BOOL stylesChanged = !MPAreNilableStringsEqual(self.currentStyleName, newStyleName) ||
                         !MPAreNilableStringsEqual(self.currentHighlightingThemeName, newHighlightingTheme);

    // Try DOM replacement to preserve scroll position.
    // MathJax re-typesetting is handled via MathJax.Hub.Queue, which serializes
    // the async typesetting correctly. Scroll is restored after typesetting completes.
    // Skip DOM replacement if styles changed, since <head> CSS links need updating.
    // Related to issue #325.
    if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl] && !stylesChanged)
    {
        DOMDocument *doc = self.preview.mainFrame.DOMDocument;
        DOMNodeList *bodyNodes = [doc getElementsByTagName:@"body"];
        if (bodyNodes.length >= 1)
        {
            // Extract just the body content, not head or html tags
            static NSString *pattern = @"<body[^>]*>(.*)</body>";
            static int opts = NSRegularExpressionDotMatchesLineSeparators;

            NSRegularExpression *regex =
                [[NSRegularExpression alloc] initWithPattern:pattern
                                                     options:opts error:NULL];
            NSTextCheckingResult *result =
                [regex firstMatchInString:html options:0
                                    range:NSMakeRange(0, html.length)];
            if (result && [result rangeAtIndex:1].location != NSNotFound)
            {
                NSString *bodyContent = [html substringWithRange:[result rangeAtIndex:1]];

                CGFloat scrollBefore = NSMinY(self.preview.enclosingScrollView.contentView.bounds);

                // Only replace body content, preserving head (CSS, scripts)
                JSContext *context = self.preview.mainFrame.javaScriptContext;
                context[@"window"][@"__macdownTempHtml"] = bodyContent;

                NSString *updateScript = [NSString stringWithFormat:
                    @"(function(){"
                    @"  var scrollY = %.0f;"
                    @"  var html = window.__macdownTempHtml;"
                    @"  delete window.__macdownTempHtml;"
                    @"  var body = document.body;"
                    @"  body.innerHTML = html;"
                    @"  if(window.Prism){Prism.highlightAll();}"
                    @"  if(typeof window.macdownInitTaskList==='function'){window.macdownInitTaskList();}"
                    @"  if(window.MathJax&&MathJax.Hub){"
                    @"    MathJax.Hub.Queue(['Typeset',MathJax.Hub]);"
                    @"    MathJax.Hub.Queue(function(){"
                    @"      window.scrollTo(0,scrollY);"
                    @"      if(typeof MathJaxListener!=='undefined'){"
                    @"        MathJaxListener.invokeCallbackForKey_('DOMReplacementDone');"
                    @"      }"
                    @"    });"
                    @"  } else {"
                    @"    window.scrollTo(0,scrollY);"
                    @"  }"
                    @"})();",
                    scrollBefore];

                // Issue #325 / Commit 8 (gap 9): Set up MathJax completion callback to
                // update header locations after typesetting, which may change document height.
                // This overwrites the initial-load "End" listener, which is safe because
                // isPreviewReady guarantees the initial load completed.
                //
                // Generation counter: increment before capturing so that stale callbacks
                // from a superseded render are no-ops. Only the most recent render's
                // callback resets ownership and syncs.
                if (self.preferences.htmlMathJax)
                {
                    _mathJaxRenderGeneration++;
                    NSUInteger expectedGeneration = _mathJaxRenderGeneration;
                    MPMathJaxListener *listener = [[MPMathJaxListener alloc] init];
                    __weak MPDocument *weakSelf = self;
                    [listener addCallback:^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf)
                            return;
                        // Commit 8 (gap 9): If generation differs, this callback is stale —
                        // a newer render was started before MathJax finished. Skip entirely.
                        if (strongSelf->_mathJaxRenderGeneration != expectedGeneration)
                            return;
                        if (strongSelf.preferences.editorSyncScrolling)
                        {
                            [strongSelf updateHeaderLocations];
                            [strongSelf syncScrollers];
                        }
                        strongSelf->_scrollOwner = MPScrollOwnerNeither;
                    } forKey:@"DOMReplacementDone"];
                    [self.preview.windowScriptObject setValue:listener
                                                      forKey:@"MathJaxListener"];
                }

                [context evaluateScript:updateScript];

                // Issue #342: For non-MathJax, sync at render completion and
                // transition ownership to Neither. The deferred window.scrollTo
                // notification will arrive while scrollOwner is Editor (if user
                // typed again) or Neither (if not) — both suppress syncScrollersReverse.
                if (!self.preferences.htmlMathJax)
                {
                    if (self.preferences.editorSyncScrolling)
                    {
                        [self updateHeaderLocations];
                        [self syncScrollers];
                    }
                    _scrollOwner = MPScrollOwnerNeither;
                }

                // Mark rendering as complete so next edit will be processed
                self.alreadyRenderingInWeb = NO;

                // Issue #294: Update word count during DOM replacement
                [self scheduleWordCountUpdate];

                return;
            }
        }
    }

    // Issue #441: The full-reload completion handler unconditionally restores the
    // preview to lastPreviewScrollTop to avoid a flash-to-top. When sync is OFF the
    // preview scrolls independently, so capture its actual position here — before the
    // load blanks the view — so the restore preserves where the user is rather than
    // an editor-derived position left over from when sync was ON.
    if (!self.preferences.editorSyncScrolling && self.preview.enclosingScrollView)
        self.lastPreviewScrollTop =
            NSMinY(self.preview.enclosingScrollView.contentView.bounds);

    // Fall back to full reload
    [self.preview.mainFrame loadHTMLString:html baseURL:baseUrl];
    // Re-apply preview zoom immediately. The WebKit page-size multiplier
    // is reset by a fresh load; calling it now (in addition to the
    // didFinishLoadForFrame callback) shortens the visible window where
    // the preview could briefly render at 100% before our preference
    // takes effect.
    [self applyPreviewZoom];
    self.currentBaseUrl = baseUrl;
    self.currentStyleName = newStyleName;
    self.currentHighlightingThemeName = newHighlightingTheme;
}

- (NSURL *)rendererBaseURL:(MPRenderer *)renderer
{
    NSURL *baseUrl = self.fileURL;
    if (!baseUrl)
        baseUrl = self.preferences.htmlDefaultDirectoryUrl;
    return [self previewSafeBaseURL:baseUrl];
}

// Issues #405 and #431: On macOS 26, WebKit silently refuses to load file://
// preview content when the base resource is the real document file, based on
// file metadata WebKit inspects but the editor — which reads bytes via
// NSDocument, not WebKit — does not. The preview blanks while the editor works
// fine. Two known triggers, neither of which lives in the document bytes:
//
//   * The execute bit (0700) that some sync clients (notably OneDrive) set on
//     every synced file and revert after any manual `chmod -x`.
//   * Stale TCC / provenance / app-association state carried by a file's inode
//     and birthtime across its history (issue #431). `xattr -c` cannot clear it
//     because the relevant attributes are kernel-protected, and copying the
//     bytes to a fresh inode makes the very same content render correctly.
//
// Because there is no reliable runtime signal that a given file will trigger a
// blank load, and because the base URL is only ever needed for the document's
// *directory* — relative resource resolution, MPLocalFilePathsInHTML, cache
// busting, and the MPURLSecurityPolicy scope check (which keys off the base
// URL's parent directory) — the real document file never needs to be the base
// resource at all. Whenever the base URL points at a real file, substitute a
// non-existent sentinel in the same directory. WebKit then never inspects the
// document file as its base resource, while everything that depends on the
// directory is unchanged. Directory base URLs (unsaved documents use the default
// HTML directory), non-existent paths, and non-file URLs are already safe and
// pass through untouched.
- (NSURL *)previewSafeBaseURL:(NSURL *)baseURL
{
    if (!baseURL || !baseURL.isFileURL)
        return baseURL;

    NSString *path = baseURL.URLByResolvingSymlinksInPath.path;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path
                                              isDirectory:&isDirectory])
        return baseURL;
    if (isDirectory)
        return baseURL;

    return [baseURL.URLByDeletingLastPathComponent
            URLByAppendingPathComponent:@".macdown-preview-base"];
}

#pragma mark - Resource Watcher Delegate (Issue #110)

- (void)resourceWatcherSet:(MPResourceWatcherSet *)set
     didDetectChangeAtPath:(NSString *)path
{
    [self.renderer setTimestamp:[[NSDate date] timeIntervalSince1970]
               forResourcePath:path];
    [self.renderer render];
}

#pragma mark - Window Controller

- (void)makeWindowControllers
{
    [super makeWindowControllers];
}

#pragma mark - Notification handler

- (void)editorTextDidChange:(NSNotification *)notification
{
    if (self.needsHtml)
        [self.renderer parseAndRenderLater];

    // Issue #294: Throttled word count update on every text change
    [self scheduleWordCountUpdate];

    // Issue #342: Claim editor ownership unconditionally so that deferred WebKit
    // notifications from DOM replacement do not trigger syncScrollersReverse
    // while typing. Sync calls are separately gated by the pref.
    _scrollOwner = MPScrollOwnerEditor;
}

// Issue #452: When the editor has a non-empty selection, show the selection's
// word/character/character-no-spaces counts in the count widget; otherwise
// revert to the document-wide totals.
- (void)editorSelectionDidChange:(NSNotification *)notification
{
    if (!self.preferences.editorShowWordCount)
        return;

    // No editor yet (e.g. before the nib loads): nothing is selected.
    if (!self.editor)
    {
        [self refreshDocumentWordCountTitles];
        return;
    }

    NSString *string = self.editor.string;
    NSRange selection = self.editor.selectedRange;

    // Empty selection (caret only), or a stale range during a rapid
    // edit-and-select race: fall back to document totals.
    if (selection.length == 0
            || NSMaxRange(selection) > string.length)
    {
        [self refreshDocumentWordCountTitles];
        return;
    }

    NSString *selected = [string substringWithRange:selection];
    DOMNodeTextCount count = MPTextCountForString(selected);

    self.showingSelectionCount = YES;
    [self applyWordsTitle:count.words selected:YES];
    [self applyCharactersTitle:count.characters selected:YES];
    [self applyCharactersNoSpacesTitle:count.characterWithoutSpaces
                              selected:YES];
}

// Issue #452: Restore the document-wide totals to the count widget titles.
- (void)refreshDocumentWordCountTitles
{
    self.showingSelectionCount = NO;
    [self applyWordsTitle:self.totalWords selected:NO];
    [self applyCharactersTitle:self.totalCharacters selected:NO];
    [self applyCharactersNoSpacesTitle:self.totalCharactersNoSpaces
                              selected:NO];
}

- (void)userDefaultsDidChange:(NSNotification *)notification
{
    // Issue #441: NSUserDefaultsDidChangeNotification fires for every defaults
    // change, so detect a genuine Sync Panes transition by comparing against the
    // last observed value. On a real toggle, settle the panes (disable) or re-sync
    // them immediately (enable) so the new mode takes effect without requiring a
    // document reopen. Always refresh the cached value, even for unrelated changes.
    BOOL nowSync = self.preferences.editorSyncScrolling;
    if (nowSync != self.lastKnownSyncScrolling)
    {
        self.lastKnownSyncScrolling = nowSync;
        if (nowSync)
            [self handleSyncScrollingEnabled];
        else
            [self handleSyncScrollingDisabled];
    }

    MPRenderer *renderer = self.renderer;

    // Force update if we're switching from manual to auto, or renderer settings
    // changed.
    int rendererFlags = self.preferences.rendererFlags;
    if ((!self.preferences.markdownManualRender && self.manualRender)
            || renderer.rendererFlags != rendererFlags)
    {
        renderer.rendererFlags = rendererFlags;
        [renderer parseAndRenderLater];
    }
    else
    {
        [renderer parseIfPreferencesChanged];
        [renderer renderIfPreferencesChanged];
    }
}

// Issue #441: The user turned Sync Panes ON mid-session. Re-sync immediately,
// Editor-authoritative (the Preview moves to match the editor's current position),
// then return to the quiescent state so subsequent scrolls sync in either direction.
// Mirrors the editor-reveal sync in setSplitViewDividerLocation:, but forward.
- (void)handleSyncScrollingEnabled
{
    if (!self.renderer)
        return;                              // Headless / nib not yet loaded.
    if (_scrollOwner != MPScrollOwnerNeither)
        return;                              // Don't fight an in-progress live scroll.

    // Claiming editor ownership suppresses the synchronous previewBoundsDidChange:
    // fired by the bounds write inside syncScrollers (it is gated on == Preview).
    _scrollOwner = MPScrollOwnerEditor;
    [self updateHeaderLocations];
    [self syncScrollers];
    _scrollOwner = MPScrollOwnerNeither;
}

// Issue #441: The user turned Sync Panes OFF mid-session. Make the panes fully
// independent immediately, preserving their current positions (no jump). The bug
// was that a stale, editor-derived lastPreviewScrollTop — last written while sync
// was ON — kept getting restored on the full-reload completion path, yanking the
// Preview toward the editor each time the user typed. Resetting ownership prevents
// any lingering Editor ownership from suppressing the user's own preview scrolls,
// and recapturing the Preview's actual position makes the restore a visual no-op.
- (void)handleSyncScrollingDisabled
{
    // Unlike handleSyncScrollingEnabled, which defers when a live scroll owns the
    // panes, disabling resets ownership unconditionally: the goal is immediate
    // independence. If a preview drag is somehow in flight, didEndPreviewLiveScroll:
    // re-checks the (now false) preference before reverse-syncing, so this is safe.
    _scrollOwner = MPScrollOwnerNeither;
    if (self.preview.enclosingScrollView)
        self.lastPreviewScrollTop =
            NSMinY(self.preview.enclosingScrollView.contentView.bounds);
}

- (void)editorFrameDidChange:(NSNotification *)notification
{
    if (self.preferences.editorWidthLimited)
        [self adjustEditorInsets];
    // Commit 6 (gap 3): Coalesce header cache refresh after editor frame changes.
    // Covers editorWidthLimited toggle and other frame changes not captured above.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                selector:@selector(refreshHeaderCacheAfterResize) object:nil];
    [self performSelector:@selector(refreshHeaderCacheAfterResize)
               withObject:nil afterDelay:0];
}

- (void)willStartLiveScroll:(NSNotification *)notification
{
    [self updateHeaderLocations];
}

-(void)didEndLiveScroll:(NSNotification *)notification
{
    // No ownership change needed: editor live-scroll runs while scrollOwner == Neither,
    // and editorBoundsDidChange: handles syncing in that state.
}

// Issue #342: Preview live-scroll handlers for ownership model (Gap 1).

- (void)willStartPreviewLiveScroll:(NSNotification *)notification
{
    // Update header locations before claiming ownership so that
    // syncScrollersReverse (called at end of live-scroll) uses current positions.
    [self updateHeaderLocations];
    _scrollOwner = MPScrollOwnerPreview;
}

- (void)didEndPreviewLiveScroll:(NSNotification *)notification
{
    // Gap 4: Save lastPreviewScrollTop here (consolidated from the now-deleted
    // previewDidLiveScroll: observer, which was a second NSScrollViewDidEndLiveScroll
    // registration on the same object — fragile registration-order coupling).
    NSClipView *contentView = self.preview.enclosingScrollView.contentView;
    self.lastPreviewScrollTop = contentView.bounds.origin.y;

    // Perform one final reverse sync at scroll-end, then return to quiescent state.
    if (self.preferences.editorSyncScrolling)
        [self syncScrollersReverse];
    _scrollOwner = MPScrollOwnerNeither;
}

// Commit 6 (gaps 1+3): Shared handler for all layout-change triggers.
// Called after window edge resize, split-divider drag (coalesced), full-screen
// enter/exit, and editor frame changes (coalesced via performSelector:afterDelay:0).

- (void)refreshHeaderCacheAfterResize
{
    if (!self.renderer || !self.preferences.editorSyncScrolling)
        return;
    [self updateHeaderLocations];
    if (_scrollOwner == MPScrollOwnerNeither)
        [self syncScrollers];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    // Cancel any pending coalesced refresh; do the refresh immediately now.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                selector:@selector(refreshHeaderCacheAfterResize) object:nil];
    [self refreshHeaderCacheAfterResize];
}

- (void)windowDidChangeFullScreen:(NSNotification *)notification
{
    // Cancel any pending coalesced refresh; do the refresh immediately now.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                selector:@selector(refreshHeaderCacheAfterResize) object:nil];
    [self refreshHeaderCacheAfterResize];
}

- (void)editorBoundsDidChange:(NSNotification *)notification
{
    // Issue #342: Only sync in quiescent state. Editor ownership means the render
    // pipeline is active (typing); preview ownership means the user is live-scrolling
    // the preview. Both cases must not trigger forward sync here.
    if (_scrollOwner != MPScrollOwnerNeither)
        return;

    if (self.preferences.editorSyncScrolling)
    {
        [self syncScrollers];
    }
}

- (void)didRequestEditorReload:(NSNotification *)notification
{
    NSString *key =
        notification.userInfo[MPDidRequestEditorSetupNotificationKeyName];
    [self setupEditor:key];
}

- (void)didRequestPreviewReload:(NSNotification *)notification
{
    // Issue #318: Force CSS refresh from disk on explicit reload
    [self invalidateStyleCaches];
    [self render:nil];
}

- (void)previewBoundsDidChange:(NSNotification *)notification
{
    // Issue #342: Only trigger reverse sync when the user is explicitly scrolling
    // the preview. Editor ownership and Neither ownership both suppress this to
    // prevent deferred WebKit notifications (from DOM replacement window.scrollTo)
    // from causing the editor to jump.
    if (_scrollOwner != MPScrollOwnerPreview)
        return;

    if (self.preferences.editorSyncScrolling)
    {
        [self syncScrollersReverse];
    }
}


#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (object == self.editor)
    {
        if (!self.highlighter.isActive)
            return;
        id value = change[NSKeyValueChangeNewKey];
        NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(keyPath);
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:value forKey:preferenceKey];
    }
    else if (object == [NSUserDefaults standardUserDefaults])
    {
        // Document zoom is shared by every open window and drives both panes.
        if ([keyPath isEqualToString:@"documentZoomLevel"])
        {
            [self applyCurrentZoom];
            return;
        }
        if (self.highlighter.isActive)
            [self setupEditor:keyPath];
        [self redrawDivider];
    }
}


#pragma mark - IBAction

- (IBAction)copyHtml:(id)sender
{
    // Dis-select things in WebView so that it's more obvious we're NOT
    // respecting the selection range.
    [self.preview setSelectedDOMRange:nil affinity:NSSelectionAffinityUpstream];

    // Issue #16: Use performAfterRender: to ensure HTML is up-to-date
    // even when preview pane is hidden.
    __weak typeof(self) weakSelf = self;
    [self performAfterRender:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard writeObjects:@[strongSelf.renderer.currentHtml]];
    }];
}

- (IBAction)exportHtml:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"html"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    MPExportPanelAccessoryViewController *controller =
        [[MPExportPanelAccessoryViewController alloc] init];
    controller.stylesIncluded = (BOOL)self.preferences.htmlStyleName;
    controller.highlightingIncluded = self.preferences.htmlSyntaxHighlighting;
    panel.accessoryView = controller.view;

    NSWindow *w = self.windowForSheet;
    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton)
            return;
        BOOL styles = controller.stylesIncluded;
        BOOL highlighting = controller.highlightingIncluded;
        NSURL *url = panel.URL;

        // Issue #16: Ensure HTML is up-to-date before export
        __weak typeof(self) weakSelf = self;
        [self performAfterRender:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *html = [strongSelf.renderer HTMLForExportWithStyles:styles
                                                             highlighting:highlighting];
            [html writeToURL:url atomically:NO encoding:NSUTF8StringEncoding
                       error:NULL];
        }];
    }];
}

- (IBAction)exportPdf:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"pdf"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    NSWindow *w = nil;
    NSArray *windowControllers = self.windowControllers;
    if (windowControllers.count > 0)
        w = [windowControllers[0] window];

    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton)
            return;

        // Issue #16: printDocumentWithSettings: already handles render deferral
        NSDictionary *settings = @{
            NSPrintJobDisposition: NSPrintSaveJob,
            NSPrintJobSavingURL: panel.URL,
        };
        [self printDocumentWithSettings:settings showPrintPanel:NO delegate:nil
                       didPrintSelector:NULL contextInfo:NULL];
    }];
}

- (IBAction)convertToH1:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:1];
}

- (IBAction)convertToH2:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:2];
}

- (IBAction)convertToH3:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:3];
}

- (IBAction)convertToH4:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:4];
}

- (IBAction)convertToH5:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:5];
}

- (IBAction)convertToH6:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:6];
}

- (IBAction)convertToParagraph:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:0];
}

- (IBAction)toggleStrong:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"**" suffix:@"**"];
}

- (IBAction)toggleEmphasis:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"*" suffix:@"*"];
}

- (IBAction)toggleInlineCode:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"`" suffix:@"`"];
}

- (IBAction)toggleStrikethrough:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"~~" suffix:@"~~"];
}

- (IBAction)toggleUnderline:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"_" suffix:@"_"];
}

- (IBAction)toggleHighlight:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"==" suffix:@"=="];
}

- (IBAction)toggleComment:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"<!--" suffix:@"-->"];
}

- (IBAction)toggleLink:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"[" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

- (IBAction)toggleImage:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"![" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

/**
 * Issue #278: Compute how to insert a fixed 3-column Markdown table into
 * `content` at `selectedRange`.
 *
 * The table is always emitted as its own block, separated from surrounding
 * content by exactly one blank line above and below (Markdown requires a blank
 * line around a table for it to be recognized). When the selection is empty,
 * the insertion point is snapped to the end of the current line first, so a
 * table never splits a line and a *repeated* insert never lands inside a
 * previously inserted table cell (the nesting/corruption reported against
 * rc.1). When the selection is non-empty it is replaced, preserving the prior
 * "replace selection" behavior.
 *
 * Returns the string to insert; `outReplacementRange` receives the (possibly
 * snapped) range in `content` to replace; `outCaretLocation` receives the
 * absolute caret location, which lands inside the first body cell so the user
 * can start typing immediately.
 *
 * Pure function: no view, layout, or DOM dependencies, so it is unit-testable
 * headless.
 */
+ (NSString *)tableInsertionForContent:(NSString *)content
                         selectedRange:(NSRange)selectedRange
                      replacementRange:(NSRange *)outReplacementRange
                         caretLocation:(NSUInteger *)outCaretLocation
{
    static NSString *const core = @"| Column 1 | Column 2 | Column 3 |\n"
                                  @"| --- | --- | --- |\n"
                                  @"|  |  |  |";
    NSUInteger caretOffsetInCore = [core rangeOfString:@"|  |"].location + 2;

    if (content == nil)
        content = @"";
    NSUInteger length = content.length;

    // Defensively clamp the incoming range to the content bounds.
    NSUInteger start = selectedRange.location > length ? length
                                                       : selectedRange.location;
    NSUInteger end = NSMaxRange(selectedRange) > length ? length
                                                        : NSMaxRange(selectedRange);
    if (end < start)
        end = start;

    // Empty selection (a caret): if the caret sits in the middle of a line,
    // snap it to the end of that line so the table is emitted as its own block
    // and never lands inside an existing table cell (the repeated-insert
    // corruption). A caret already at the start of a line is left alone, so the
    // table is inserted there rather than after the line.
    if (start == end)
    {
        BOOL atLineStart = (start == 0)
                           || [content characterAtIndex:start - 1] == '\n';
        if (!atLineStart)
        {
            while (end < length && [content characterAtIndex:end] != '\n')
                end++;
            start = end;
        }
    }

    // Count blank-line padding that already exists around the insertion point so
    // we add exactly one blank line of separation on each side.
    NSUInteger leadingExisting = 0;
    for (NSUInteger i = start; i > 0 && [content characterAtIndex:i - 1] == '\n'; i--)
        leadingExisting++;
    NSUInteger trailingExisting = 0;
    for (NSUInteger i = end; i < length && [content characterAtIndex:i] == '\n'; i++)
        trailingExisting++;

    NSUInteger leadingNeeded = (start == 0 || leadingExisting >= 2)
                                   ? 0 : 2 - leadingExisting;
    NSUInteger trailingNeeded = (end == length) ? 1
                                : (trailingExisting >= 2 ? 0 : 2 - trailingExisting);

    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < leadingNeeded; i++)
        [result appendString:@"\n"];
    NSUInteger caretWithinResult = result.length + caretOffsetInCore;
    [result appendString:core];
    for (NSUInteger i = 0; i < trailingNeeded; i++)
        [result appendString:@"\n"];

    if (outReplacementRange)
        *outReplacementRange = NSMakeRange(start, end - start);
    if (outCaretLocation)
        *outCaretLocation = start + caretWithinResult;
    return result;
}

- (IBAction)insertTable:(id)sender
{
    NSString *content = self.editor.string ?: @"";
    NSRange replacementRange = NSMakeRange(0, 0);
    NSUInteger caretLocation = 0;
    NSString *inserted =
        [MPDocument tableInsertionForContent:content
                               selectedRange:self.editor.selectedRange
                            replacementRange:&replacementRange
                               caretLocation:&caretLocation];

    // Use the standard undoable mutation sequence rather than
    // insertText:replacementRange:. The latter is an NSTextInputClient callback
    // whose behavior depends on which pane is first responder, which is why the
    // toolbar button (whose target is the document) failed when the editor pane
    // had focus. shouldChangeTextInRange:/replaceCharactersInRange:/didChangeText
    // mutates the text storage directly regardless of first responder, registers
    // a single undo step, and fires NSTextDidChangeNotification so the
    // highlighter re-parses.
    if (![self.editor shouldChangeTextInRange:replacementRange
                            replacementString:inserted])
        return;
    [self.editor.textStorage replaceCharactersInRange:replacementRange
                                           withString:inserted];
    [self.editor didChangeText];
    self.editor.selectedRange = NSMakeRange(caretLocation, 0);
    [self.editor scrollRangeToVisible:self.editor.selectedRange];
}

- (IBAction)toggleOrderedList:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^[0-9]+ \\S" prefix:@"1. "];
}

- (IBAction)toggleUnorderedList:(id)sender
{
    NSString *marker = self.preferences.editorUnorderedListMarker;
    [self.editor toggleBlockWithPattern:@"^[\\*\\+-] \\S" prefix:marker];
}

- (IBAction)toggleBlockquote:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^> \\S" prefix:@"> "];
}

- (IBAction)indent:(id)sender
{
    NSString *padding = @"\t";
    if (self.preferences.editorConvertTabs)
        padding = @"    ";
    [self.editor indentSelectedLinesWithPadding:padding];
}

- (IBAction)unindent:(id)sender
{
    [self.editor unindentSelectedLines];
}

- (IBAction)insertNewParagraph:(id)sender
{
    NSRange range = self.editor.selectedRange;
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    NSString *content = self.editor.string;
    NSInteger newlineBefore = [content locationOfFirstNewlineBefore:location];
    NSUInteger newlineAfter =
        [content locationOfFirstNewlineAfter:location + length - 1];

    // If we are on an empty line, treat as normal return key; otherwise insert
    // two newlines.
    if (location == newlineBefore + 1 && location == newlineAfter)
        [self.editor insertNewline:self];
    else
        [self.editor insertText:@"\n\n"];
}

- (IBAction)setEditorOneQuarter:(id)sender
{
    [self setSplitViewDividerLocation:0.25];
}

- (IBAction)setEditorThreeQuarters:(id)sender
{
    [self setSplitViewDividerLocation:0.75];
}

- (IBAction)setEqualSplit:(id)sender
{
    [self setSplitViewDividerLocation:0.5];
}

- (IBAction)toggleToolbar:(id)sender
{
    [self.windowForSheet toggleToolbarShown:sender];
}

- (IBAction)togglePreviewPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:NO];
}

- (IBAction)toggleEditorPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:YES];
}

- (IBAction)toggleAutoSave:(id)sender
{
    self.preferences.editorAutoSave = !self.preferences.editorAutoSave;
    [self.preferences synchronize];
}

- (IBAction)toggleInvisibleCharacters:(id)sender
{
    self.preferences.editorShowsInvisibleCharacters =
        !self.preferences.editorShowsInvisibleCharacters;
}

- (IBAction)render:(id)sender
{
    [self.renderer parseAndRenderLater];
}


#pragma mark - Private

/**
 * Invalidates cached CSS styles and the WebView URL cache to force a full
 * HTML reload on the next render cycle. Called when the user explicitly
 * requests a style or theme reload (context menu or Settings).
 *
 * Related to GitHub issue #318.
 */
- (void)invalidateStyleCaches
{
    // Issue #318: Clear WebView's URL cache so edited CSS/JS files are
    // re-read from disk instead of served from the in-memory cache.
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    // Issue #318: Bump a cache-busting version stamp on the active style and
    // highlighting-theme CSS files. The legacy WebView serves CSS from its own
    // by-URL resource cache, which removeAllCachedResponses does not clear, so
    // a full reload of the same file:// URL still yields stale CSS. Stamping
    // the file paths gives the <link> tags a fresh "?t=" query (applied in
    // MPRenderer.render), which the WebView has not cached. This is the same
    // trick used for edited local images (issue #110), and it also forces a
    // refresh even when no file-watcher change event preceded the reload.
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *stylePath = MPStylePathForName(self.preferences.htmlStyleName);
    if (stylePath)
        [self.renderer setTimestamp:now forResourcePath:stylePath];
    NSString *themePath =
        MPHighlightingThemeURLForName(
            self.preferences.htmlHighlightingThemeName).path;
    if (themePath)
        [self.renderer setTimestamp:now forResourcePath:themePath];

    // Issue #318: Reset cached names so renderer:didProduceHTMLOutput:
    // sees a "change" (nil != currentPref) and takes the full HTML reload
    // path instead of body-only DOM replacement.
    self.currentStyleName = nil;
    self.currentHighlightingThemeName = nil;
}

/**
 * Defers an operation until after the WebView finishes rendering.
 * Issue #16: When preview is hidden, HTML/PDF export and print operations
 * would use stale content. This method queues the handler and triggers
 * a render if needed, executing the handler once rendering completes.
 *
 * If preview is visible (needsHtml = YES), the handler executes immediately.
 * If preview is hidden (needsHtml = NO), the handler is queued and render triggered.
 */
- (void)performAfterRender:(void (^)(void))handler
{
    if (!handler)
        return;

    // If preview is visible, HTML is already up-to-date. Execute immediately.
    if (self.needsHtml)
    {
        handler();
        return;
    }

    // Preview is hidden. Queue handler and trigger render.
    if (!self.renderCompletionHandlers)
        self.renderCompletionHandlers = [NSMutableArray array];

    [self.renderCompletionHandlers addObject:[handler copy]];

    // Only trigger render if this is the first queued handler
    // (subsequent handlers will be executed when the render completes)
    if (self.renderCompletionHandlers.count == 1)
        [self.renderer parseAndRenderNow];
}

/**
 * Invokes all queued render completion handlers and clears the queue.
 * Called after WebView finishes loading content.
 */
- (void)invokeRenderCompletionHandlers
{
    if (!self.renderCompletionHandlers || self.renderCompletionHandlers.count == 0)
        return;

    NSArray *handlers = [self.renderCompletionHandlers copy];
    [self.renderCompletionHandlers removeAllObjects];

    for (void (^handler)(void) in handlers)
    {
        handler();
    }
}

- (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane
{
    BOOL isVisible = forEditorPane ? self.editorVisible : self.previewVisible;
    BOOL editorOnRight = self.preferences.editorOnRight;

    float targetRatio = ((forEditorPane == editorOnRight) ? 1.0 : 0.0);

    if (isVisible)
    {
        // Issue #23: Don't hide if the other pane is not visible
        // (this would leave no visible panes)
        BOOL otherPaneVisible = forEditorPane ? self.previewVisible : self.editorVisible;
        if (!otherPaneVisible)
        {
            return;
        }

        CGFloat oldRatio = self.splitView.dividerLocation;
        if (oldRatio != 0.0 && oldRatio != 1.0)
        {
            // We don't want to save these values, since they are meaningless.
            // The user should be able to switch between 100% editor and 100%
            // preview without losing the old ratio.
            self.previousSplitRatio = oldRatio;
        }
        [self setSplitViewDividerLocation:targetRatio];
    }
    else
    {
        // We have an inconsistency here, let's just go back to 0.5,
        // otherwise nothing will happen
        if (self.previousSplitRatio < 0.0)
            self.previousSplitRatio = 0.5;

        [self setSplitViewDividerLocation:self.previousSplitRatio];
    }
}

- (void)applyEditorStartInPreviewModePreference
{
    if (!self.preferences.editorStartInPreviewMode || !self.editorVisible)
        return;

    CGFloat ratio = self.splitView.dividerLocation;
    if (ratio > 0.0 && ratio < 1.0)
    {
        self.previousSplitRatio = ratio;
    }
    else if (!self.previewVisible && self.previousSplitRatio < 0.0)
    {
        // An editor-only autosaved layout has no restorable split ratio, so
        // fall back to an even split when the user later restores the editor.
        self.previousSplitRatio = 0.5;
    }

    CGFloat targetRatio = self.preferences.editorOnRight ? 1.0 : 0.0;
    [self setSplitViewDividerLocation:targetRatio];
}

- (void)setupEditor:(NSString *)changedKey
{
    [self.highlighter deactivate];

    if (!changedKey || [changedKey isEqualToString:@"extensionFootnotes"]
            || [changedKey isEqualToString:@"htmlMathJax"]
            || [changedKey isEqualToString:@"htmlMathJaxInlineDollar"])
    {
        int extensions = pmh_EXT_NOTES;
        if (self.preferences.extensionFootnotes)
            extensions = pmh_EXT_NONE;
        if (self.preferences.htmlMathJax && self.preferences.htmlMathJaxInlineDollar)
            extensions |= pmh_EXT_MATH;
        self.highlighter.extensions = extensions;
    }

    if (!changedKey || [changedKey isEqualToString:@"editorHorizontalInset"]
            || [changedKey isEqualToString:@"editorVerticalInset"]
            || [changedKey isEqualToString:@"editorWidthLimited"]
            || [changedKey isEqualToString:@"editorMaximumWidth"])
    {
        [self adjustEditorInsets];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorBaseFontInfo"]
            || [changedKey isEqualToString:@"editorStyleName"]
            || [changedKey isEqualToString:@"editorLineSpacing"])
    {
        [self applyEditorFontAndParagraphStyle];
        self.editor.textColor = nil;
        self.editor.backgroundColor = [NSColor clearColor];
        self.highlighter.styles = nil;
        [self.highlighter readClearTextStylesFromTextView];

        NSString *themeName = [self.preferences.editorStyleName copy];
        if (themeName.length)
        {
            NSString *path = MPThemePathForName(themeName);
            NSString *themeString = MPReadFileOfPath(path);
            [self.highlighter applyStylesFromStylesheet:themeString
                                       withErrorHandler:
                ^(NSArray *errorMessages) {
                    self.preferences.editorStyleName = nil;
                }];
        }

        CALayer *layer = [CALayer layer];
        CGColorRef backgroundCGColor = self.editor.backgroundColor.CGColor;
        if (backgroundCGColor)
            layer.backgroundColor = backgroundCGColor;
        self.editorContainer.layer = layer;
    }
    
    if ([changedKey isEqualToString:@"editorBaseFontInfo"])
    {
        [self scaleWebview];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorShowWordCount"])
    {
        if (self.preferences.editorShowWordCount)
        {
            self.wordCountWidget.hidden = NO;
            self.editorPaddingBottom.constant = 35.0;
            [self updateWordCount];
        }
        else
        {
            self.wordCountWidget.hidden = YES;
            self.editorPaddingBottom.constant = 0.0;
            // Issue #452: Reset selection mode so re-enabling starts on totals.
            self.showingSelectionCount = NO;
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorScrollsPastEnd"])
    {
        self.editor.scrollsPastEnd = self.preferences.editorScrollsPastEnd;
        NSRect contentRect = self.editor.contentRect;
        NSSize minSize = self.editor.enclosingScrollView.contentSize;
        if (contentRect.size.height < minSize.height)
            contentRect.size.height = minSize.height;
        if (contentRect.size.width < minSize.width)
            contentRect.size.width = minSize.width;
        self.editor.frame = contentRect;
    }

    if (!changedKey || [changedKey isEqualToString:@"editorShowsInvisibleCharacters"])
    {
        self.editor.layoutManager.showsInvisibleCharacters =
            self.preferences.editorShowsInvisibleCharacters;
    }

    if (!changedKey)
    {
        NSClipView *contentView = self.editor.enclosingScrollView.contentView;
        contentView.postsBoundsChangedNotifications = YES;

        NSDictionary *keysAndDefaults = MPEditorKeysToObserve();
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in keysAndDefaults)
        {
            NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(key);
            id value = [defaults objectForKey:preferenceKey];
            value = value ? value : keysAndDefaults[key];
            [self.editor setValue:value forKey:key];
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorOnRight"])
    {
        BOOL editorOnRight = self.preferences.editorOnRight;
        NSArray *subviews = self.splitView.subviews;
        if ((!editorOnRight && subviews[0] == self.preview)
            || (editorOnRight && subviews[1] == self.preview))
        {
            [self.splitView swapViews];
            if (!self.previewVisible && self.previousSplitRatio >= 0.0)
                self.previousSplitRatio = 1.0 - self.previousSplitRatio;
            if (self.lastNonCollapsedRatio > 0.0
                    && self.lastNonCollapsedRatio < 1.0)
                self.lastNonCollapsedRatio = 1.0 - self.lastNonCollapsedRatio;

            // Need to queue this or the views won't be initialised correctly.
            // Don't really know why, but this works.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.splitView.needsLayout = YES;
            }];
        }
    }

    [self.highlighter activate];
    self.editor.automaticLinkDetectionEnabled = NO;
}

- (void)adjustEditorInsets
{
    CGFloat x = self.preferences.editorHorizontalInset;
    CGFloat y = self.preferences.editorVerticalInset;
    if (self.preferences.editorWidthLimited)
    {
        CGFloat editorWidth = self.editor.frame.size.width;
        CGFloat maxWidth = self.preferences.editorMaximumWidth;
        if (editorWidth > 2 * x + maxWidth)
            x = (editorWidth - maxWidth) * 0.45;
        // We tend to expect things in an editor to shift to left a bit.
        // Hence the 0.45 instead of 0.5 (which whould feel a bit too much).
    }
    self.editor.textContainerInset = NSMakeSize(x, y);
}

- (void)redrawDivider
{
    if (!self.editorVisible)
    {
        // If the editor is not visible, detect preview's background color via
        // DOM query and use it instead. This is more expensive; we should try
        // to avoid it.
        // TODO: Is it possible to cache this until the user switches the style?
        // Will need to take account of the user MODIFIES the style without
        // switching. Complicated. This will do for now.
        self.splitView.dividerColor = MPGetWebViewBackgroundColor(self.preview);
    }
    else if (!self.previewVisible)
    {
        // If the editor is visible, match its background color.
        self.splitView.dividerColor = self.editor.backgroundColor;
    }
    else
    {
        // If both sides are visible, draw a default "transparent" divider.
        // This works around the possibile problem of divider's color being too
        // similar to both the editor and preview and being obscured.
        self.splitView.dividerColor = nil;
    }
}

- (CGFloat)previewScale
{
    if (self.preferences.previewZoomRelativeToBaseFontSize)
    {
        CGFloat fontSize = self.preferences.editorBaseFontSize;
        if (fontSize > 0.0)
        {
            static const CGFloat defaultSize = 14.0;
            return (fontSize / defaultSize) * self.zoomMultiplier;
        }
    }
    return self.zoomMultiplier;
}

- (CGFloat)zoomMultiplier
{
    CGFloat level = self.preferences.documentZoomLevel;
    return level > 0.0 ? level : 1.0;
}

- (void)setZoomMultiplier:(CGFloat)zoomMultiplier
{
    self.preferences.documentZoomLevel =
        MIN(MAX(zoomMultiplier, kMPMinZoom), kMPMaxZoom);
}

- (void)scaleWebview
{
    if (!self.preview)
        return;

    CGFloat scale = [self previewScale];
    [self.preview setPageSizeMultiplier:(float)scale];
}

- (NSFont *)zoomedEditorFont
{
    NSFont *baseFont = self.preferences.editorBaseFont;
    if (!baseFont)
        return nil;
    CGFloat zoomedSize = baseFont.pointSize * self.zoomMultiplier;
    return [NSFont fontWithDescriptor:baseFont.fontDescriptor size:zoomedSize];
}

- (void)applyEditorFontAndParagraphStyle
{
    NSFont *font = [[self zoomedEditorFont] copy];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = self.preferences.editorLineSpacing;

    // Configure tab stops to match 4-space tab width (fixes #195)
    if (font)
    {
        NSDictionary *attrs = @{NSFontAttributeName: font};
        CGFloat spaceWidth = [@" " sizeWithAttributes:attrs].width;
        CGFloat tabInterval = spaceWidth * 4;

        NSMutableArray *tabStops = [NSMutableArray array];
        for (NSInteger i = 1; i <= 100; i++)
        {
            NSTextTab *tab = [[NSTextTab alloc]
                initWithTextAlignment:NSTextAlignmentLeft
                             location:tabInterval * i
                              options:@{}];
            [tabStops addObject:tab];
        }
        style.tabStops = tabStops;
    }

    self.editor.defaultParagraphStyle = [style copy];
    if (font)
        self.editor.font = font;
}

- (IBAction)zoomIn:(id)sender
{
    [self stepDocumentZoomDirection:+1];
}

- (IBAction)zoomOut:(id)sender
{
    [self stepDocumentZoomDirection:-1];
}

- (IBAction)resetZoom:(id)sender
{
    self.preferences.documentZoomLevel = 1.0;
}

- (void)applyCurrentZoom
{
    [self applyEditorFontAndParagraphStyle];
    [self scaleWebview];
}

/**
 * Updates cached positions of reference points (headers, standalone images) in both
 * editor and preview for scroll synchronization.
 *
 * HORIZONTAL RULE vs SETEXT HEADER DETECTION:
 *
 * This method must distinguish between:
 *   - Setext-style headers: Text lines underlined with dashes
 *   - Horizontal rules: Lines of 3+ matching characters (-, *, _)
 *
 * Examples:
 *   Setext header:        Text\n---     (dashes after content)
 *   Horizontal rule:      \n---         (dashes without content)
 *   Horizontal rule:      - - -         (3+ dashes with spaces)
 *   NOT an HR:            --            (only 2 dashes)
 *   NOT an HR:            -*-           (mixed characters)
 *
 * Edge cases handled:
 *   - Lines with 2 dashes (--) can be setext headers, NOT horizontal rules
 *   - Lines with 3+ dashes after content are setext headers
 *   - Lines with 3+ dashes without content are horizontal rules
 *   - Leading whitespace (0-3 spaces) allowed per CommonMark
 *   - Spaces between characters allowed (- - - is valid HR)
 *
 * CommonMark compatibility notes:
 *   - Follows CommonMark for horizontal rule detection (3+ characters)
 *   - Maintains MacDown's existing setext header behavior
 *   - Does not enforce strict CommonMark if it breaks existing documents
 *
 * Uses JavaScript to detect standalone images in the preview, matching the logic
 * in the editor's Markdown parsing. Images must be:
 * - Alone in a paragraph, OR
 * - Wrapped in a link that's alone in a paragraph, OR
 * - The only child of their parent element
 *
 * Called during live scrolling and when content changes.
 *
 * Related issue: #143 - Horizontal rule regex edge cases
 */
-(void) updateHeaderLocations
{
    // Load JavaScript from resource file for better maintainability
    static NSString *script = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"updateHeaderLocations" ofType:@"js"];
        if (scriptPath) {
            script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:NULL];
        }
    });

    // Preview side. Issue #436: the JS now returns {ys, kinds} instead of a bare array.
    // ys are document-absolute (window.scrollY + rect.top, Issue #342 Bug B); kinds tag
    // each reference point (0 = image, 1-6 = header level) so the two sequences can be
    // aligned rather than blindly cross-indexed by position.
    if (script) {
        JSValue *result = [self.preview.mainFrame.javaScriptContext evaluateScript:script];
        NSArray<NSNumber *> *ys = [result[@"ys"] toArray];
        NSArray<NSNumber *> *kinds = [result[@"kinds"] toArray];
        _webViewHeaderLocations = ys ?: @[];
        _webViewHeaderTypes = kinds ?: @[];
    } else {
        _webViewHeaderLocations = @[];
        _webViewHeaderTypes = @[];
    }

    // Editor side. Issue #436: which lines are reference points (and their kinds) is now
    // a pure function, +editorReferenceKindsForMarkdown:outLineNumbers:, so it can be unit
    // tested headless. Here we only translate those line numbers into vertical positions
    // via the layout manager. In headless tests self.editor is nil and the geometry
    // collapses to 0 (harmless — the classifier is exercised directly in unit tests).
    NSString *editorString = self.editor.string ?: @"";
    NSArray<NSNumber *> *lineNumbers = nil;
    _editorHeaderTypes = [MPDocument editorReferenceKindsForMarkdown:editorString
                                                      outLineNumbers:&lineNumbers];

    NSArray<NSString *> *documentLines = [editorString componentsSeparatedByString:@"\n"];
    NSUInteger lineCount = documentLines.count;
    NSLayoutManager *layoutManager = [self.editor layoutManager];
    NSTextContainer *textContainer = [self.editor textContainer];

    // Precompute the character offset at the start of each line so a line number maps to
    // its glyph range without rescanning the whole string.
    NSMutableArray<NSNumber *> *lineStartOffsets = [NSMutableArray arrayWithCapacity:lineCount];
    NSUInteger runningOffset = 0;
    for (NSString *line in documentLines) {
        [lineStartOffsets addObject:@(runningOffset)];
        runningOffset += line.length + 1;  // +1 for the '\n' separator
    }

    NSMutableArray<NSNumber *> *locations = [NSMutableArray arrayWithCapacity:lineNumbers.count];
    for (NSNumber *lineNumberObj in lineNumbers) {
        NSUInteger lineNumber = lineNumberObj.unsignedIntegerValue;
        if (lineNumber >= lineCount)
            continue;
        NSUInteger charLocation = lineStartOffsets[lineNumber].unsignedIntegerValue;
        NSUInteger lineLength = documentLines[lineNumber].length;
        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(charLocation, lineLength)
                                                   actualCharacterRange:nil];
        NSRect topRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:textContainer];
        [locations addObject:@(NSMidY(topRect))];
    }

    _editorHeaderLocations = [locations copy];

    // Issue #436 / Gap 5: Align the editor and preview reference-point sequences so
    // syncScrollers/syncScrollersReverse always cross-index matching points.
    [self validateHeaderLocationAlignment];
}

/**
 * Issue #436: Classifies the reference points (ATX/setext headers and standalone images)
 * in a markdown string, returning their kind codes (see MPReferenceKind) in document
 * order, with the matching source line numbers via outLineNumbers. This mirrors the DOM
 * detection in updateHeaderLocations.js so the editor and preview sequences agree:
 *
 *   - Headers inside fenced code blocks (``` or ~~~) are skipped — the DOM renders them
 *     as <pre><code>, not <hN>.
 *   - Setext headers are detected for both '===' (level 1) and '---' (level 2).
 *   - ATX headers with 7+ hashes are not headers (CommonMark §4.2; Hoedown emits no <hN>),
 *     so they are treated as ordinary paragraph text.
 *   - Standalone whole-line images (inline or reference syntax) are kind 0.
 *
 * Pure function: no view, layout, or DOM dependencies, so it is unit-testable headless.
 */
+ (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown
                                          outLineNumbers:(NSArray<NSNumber *> **)outLineNumbers
{
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    NSMutableArray<NSNumber *> *lineNumbers = [NSMutableArray array];

    if (markdown.length == 0) {
        if (outLineNumbers) *outLineNumbers = lineNumbers;
        return kinds;
    }

    static NSRegularExpression *dashRegex = nil;   // setext underline '---' (level 2)
    static NSRegularExpression *eqRegex = nil;     // setext underline '===' (level 1)
    static NSRegularExpression *atxRegex = nil;    // ATX header, 0-3 leading spaces
    static NSRegularExpression *imgRegex = nil;    // ![alt](url)
    static NSRegularExpression *imgRefRegex = nil; // ![alt][ref]
    static NSRegularExpression *hrRegex = nil;     // thematic break (-, *, _)
    static dispatch_once_t regexOnceToken;
    dispatch_once(&regexOnceToken, ^{
        // Setext underlines: 0-3 leading spaces and trailing whitespace are allowed
        // (CommonMark), matching how the preview DOM renders e.g. "Text\n   ---".
        dashRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ ]{0,3}([-]+)[ \\t]*$" options:0 error:NULL];
        eqRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ ]{0,3}([=]+)[ \\t]*$" options:0 error:NULL];
        // Capture the leading hashes (0-3 leading spaces allowed); a space must follow.
        atxRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ ]{0,3}(#+)\\s" options:0 error:NULL];
        imgRegex = [NSRegularExpression regularExpressionWithPattern:@"^!\\[[^\\]]*\\]\\([^)]*\\)$" options:0 error:NULL];
        imgRefRegex = [NSRegularExpression regularExpressionWithPattern:@"^!\\[[^\\]]*\\]\\[[^\\]]*\\]$" options:0 error:NULL];
        hrRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ ]{0,3}(([-][ ]*){3,}|([*][ ]*){3,}|([_][ ]*){3,})$" options:0 error:NULL];
    });

    NSArray<NSString *> *lines = [markdown componentsSeparatedByString:@"\n"];

    // Setext underlines attach to a *paragraph* line. previousLineHadContent is true only
    // after ordinary text — not after blanks, headers, HRs, images, or fence lines —
    // so e.g. "# H\n---" is an ATX header followed by an HR, not a setext header.
    BOOL previousLineHadContent = NO;

    // Fenced-code-block state. CommonMark: a fence opens with 3+ of ` or ~ (0-3 leading
    // spaces) and closes with a run of the same character at least as long, with nothing
    // but whitespace after it. A backtick fence's info string may not contain backticks.
    BOOL insideFence = NO;
    unichar fenceChar = 0;
    NSUInteger fenceLength = 0;

    for (NSUInteger lineNumber = 0; lineNumber < lines.count; lineNumber++) {
        NSString *line = lines[lineNumber];
        NSRange full = NSMakeRange(0, line.length);

        unichar markerChar = 0;
        NSUInteger markerLength = 0;
        BOOL hasTrailingContent = NO;
        BOOL isFenceMarker = MPScanFenceMarker(line, &markerChar, &markerLength, &hasTrailingContent);

        if (insideFence) {
            // Inside a fence: only a matching, long-enough, bare closing marker ends it.
            // Everything here (including the fence lines) is code, never a reference point.
            if (isFenceMarker && markerChar == fenceChar
                    && markerLength >= fenceLength && !hasTrailingContent) {
                insideFence = NO;
            }
            previousLineHadContent = NO;
            continue;
        }

        if (isFenceMarker) {
            // Opens a fence. The opening line itself is never a reference point.
            insideFence = YES;
            fenceChar = markerChar;
            fenceLength = markerLength;
            previousLineHadContent = NO;
            continue;
        }

        // ATX header? Capture the hash run; 7+ hashes is not a header (paragraph text).
        NSTextCheckingResult *atxMatch = [atxRegex firstMatchInString:line options:0 range:full];
        if (atxMatch) {
            NSUInteger hashCount = [atxMatch rangeAtIndex:1].length;
            if (hashCount >= 1 && hashCount <= 6) {
                [kinds addObject:@((NSInteger)hashCount)];
                [lineNumbers addObject:@(lineNumber)];
                previousLineHadContent = NO;
                continue;
            }
            // 7+ hashes: ordinary paragraph text, which can still anchor a setext header.
            previousLineHadContent = YES;
            continue;
        }

        // Setext underline (only valid directly under a paragraph line).
        if (previousLineHadContent
                && [eqRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            [kinds addObject:@(MPReferenceKindH1)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }
        if (previousLineHadContent
                && [dashRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            [kinds addObject:@(MPReferenceKindH2)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }

        // Standalone whole-line image.
        if ([imgRegex numberOfMatchesInString:line options:0 range:full] > 0
                || [imgRefRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            [kinds addObject:@(MPReferenceKindImage)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }

        // Thematic break: not a reference point, and not paragraph text either.
        if ([hrRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            previousLineHadContent = NO;
            continue;
        }

        // Blank line breaks any setext context.
        if ([[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
            previousLineHadContent = NO;
            continue;
        }

        // Anything else is ordinary paragraph text that can anchor a setext underline.
        previousLineHadContent = YES;
    }

    if (outLineNumbers) *outLineNumbers = lineNumbers;
    return kinds;
}

/**
 * Issue #436: Aligns the editor and preview reference-point sequences so they correspond
 * 1:1 by index, which is the invariant syncScrollers/syncScrollersReverse rely on.
 *
 * The two detectors (editor regex vs preview DOM) can disagree mid-document; a single
 * extra point on one side shifts every later index, which is the "synced only at the
 * start and end" bug. This computes the longest common subsequence of the two *kind*
 * sequences (matching on the coarse image-vs-header class, since the two sides legitimately
 * disagree on exact header level) and keeps only the matched points on each side. An
 * unmatched point is dropped from whichever side it appears on, so the remaining points
 * stay aligned regardless of where the divergence occurs.
 *
 * Fallback: if the type information is missing or inconsistent with the coordinate arrays
 * (e.g. callers/tests that set only the Y arrays), it degrades to the original behavior of
 * truncating both arrays to MIN count.
 *
 * Pure function: no view dependencies, so it is unit-testable headless.
 */
+ (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs
          editorTypes:(NSArray<NSNumber *> *)editorTypes
            previewYs:(NSArray<NSNumber *> *)previewYs
         previewTypes:(NSArray<NSNumber *> *)previewTypes
      alignedEditorYs:(NSArray<NSNumber *> **)outEditorYs
     alignedPreviewYs:(NSArray<NSNumber *> **)outPreviewYs
{
    NSUInteger editorCount = editorYs.count;
    NSUInteger previewCount = previewYs.count;

    // Fallback to MIN-count truncation when type tags are absent or inconsistent.
    if (editorTypes.count != editorCount || previewTypes.count != previewCount) {
        NSUInteger minCount = MIN(editorCount, previewCount);
        if (outEditorYs)
            *outEditorYs = [editorYs subarrayWithRange:NSMakeRange(0, minCount)];
        if (outPreviewYs)
            *outPreviewYs = [previewYs subarrayWithRange:NSMakeRange(0, minCount)];
        return;
    }

    // Coarse class for matching: images match images, any header matches any header.
    NSInteger (^classOf)(NSNumber *) = ^NSInteger(NSNumber *kind) {
        return kind.integerValue == MPReferenceKindImage ? 0 : 1;
    };

    // LCS over the coarse class sequences. dp[i][j] = LCS length of editor[i..] / preview[j..].
    NSUInteger m = editorCount, n = previewCount;
    NSUInteger **dp = calloc(m + 1, sizeof(NSUInteger *));
    for (NSUInteger i = 0; i <= m; i++)
        dp[i] = calloc(n + 1, sizeof(NSUInteger));

    for (NSInteger i = (NSInteger)m - 1; i >= 0; i--) {
        for (NSInteger j = (NSInteger)n - 1; j >= 0; j--) {
            if (classOf(editorTypes[i]) == classOf(previewTypes[j]))
                dp[i][j] = dp[i + 1][j + 1] + 1;
            else
                dp[i][j] = MAX(dp[i + 1][j], dp[i][j + 1]);
        }
    }

    NSMutableArray<NSNumber *> *alignedEditor = [NSMutableArray array];
    NSMutableArray<NSNumber *> *alignedPreview = [NSMutableArray array];
    NSUInteger i = 0, j = 0;
    while (i < m && j < n) {
        if (classOf(editorTypes[i]) == classOf(previewTypes[j])) {
            [alignedEditor addObject:editorYs[i]];
            [alignedPreview addObject:previewYs[j]];
            i++; j++;
        } else if (dp[i + 1][j] >= dp[i][j + 1]) {
            // Drop the editor point (no preview counterpart).
            i++;
        } else {
            // Drop the preview point (no editor counterpart).
            j++;
        }
    }

    for (NSUInteger k = 0; k <= m; k++)
        free(dp[k]);
    free(dp);

    if (outEditorYs) *outEditorYs = alignedEditor;
    if (outPreviewYs) *outPreviewYs = alignedPreview;
}

/**
 * Issue #436: Realigns _editorHeaderLocations and _webViewHeaderLocations using the kind
 * tags so syncScrollers/syncScrollersReverse cross-index matching reference points. See
 * +alignEditorYs:... for the algorithm; this just wires the instance state through it and
 * stores the aligned results back.
 */
- (void)validateHeaderLocationAlignment
{
    NSArray<NSNumber *> *alignedEditor = nil;
    NSArray<NSNumber *> *alignedPreview = nil;
    [MPDocument alignEditorYs:_editorHeaderLocations
                  editorTypes:_editorHeaderTypes
                    previewYs:_webViewHeaderLocations
                 previewTypes:_webViewHeaderTypes
              alignedEditorYs:&alignedEditor
             alignedPreviewYs:&alignedPreview];
#ifdef DEBUG
    if (alignedEditor.count != _editorHeaderLocations.count
            || alignedPreview.count != _webViewHeaderLocations.count) {
        NSLog(@"[ScrollSync] Realigned reference points: editor %lu->%lu, preview %lu->%lu",
              (unsigned long)_editorHeaderLocations.count, (unsigned long)alignedEditor.count,
              (unsigned long)_webViewHeaderLocations.count, (unsigned long)alignedPreview.count);
    }
#endif
    _editorHeaderLocations = alignedEditor;
    _webViewHeaderLocations = alignedPreview;
}

/**
 * Synchronizes preview pane scroll position with editor pane position.
 *
 * Algorithm:
 * 1. Find reference points (headers/images) before and after current editor position
 * 2. Calculate percentage scrolled between those reference points
 * 3. Apply same percentage between corresponding preview reference points
 * 4. Use "tapering" at document edges to center-align content mid-document but
 *    align to top/bottom at document boundaries
 *
 * The tapering ensures smooth transitions: when scrolling near the top or bottom of
 * the document, the adjustment factor gradually reduces to zero, preventing the
 * preview from being artificially centered when viewing document boundaries.
 */
- (void)syncScrollers
{
    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    CGFloat previewContentHeight = ceilf(NSHeight(self.preview.enclosingScrollView.documentView.bounds));
    CGFloat previewVisibleHeight = ceilf(NSHeight(self.preview.enclosingScrollView.contentView.bounds));
    NSInteger relativeHeaderIndex = -1; // -1 is start of document, before any other header
    CGFloat currY = NSMinY(self.editor.enclosingScrollView.contentView.bounds);
    CGFloat minY = 0;
    CGFloat maxY = 0;
    BOOL foundMaxY = NO;  // Gap 6: replace maxY==0 sentinel with explicit flag

    // Align documents at screen center for smooth sync, tapering to edges at document boundaries.
    // Taper values: 0 at document edges, 1.0 in the middle of the document.
    CGFloat topTaper = MAX(0, MIN(1.0, currY / editorVisibleHeight));
    CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0, (currY - editorContentHeight + 2 * editorVisibleHeight) / editorVisibleHeight));
    // Divide by 2 to center-align: shifts reference points by half the visible height
    CGFloat adjustmentForScroll = topTaper * bottomTaper * editorVisibleHeight / 2;

    // We start by splitting our document into lines, and then searching
    // line by line for headers or images.
    for (NSNumber *headerYNum in _editorHeaderLocations) {
        CGFloat headerY = [headerYNum floatValue];
        headerY -= adjustmentForScroll;

        if (headerY < currY)
        {
            // The header is before our current scroll position. the closest
            // of these will be our first reference node
            relativeHeaderIndex += 1;
            minY = headerY;
        } else if (!foundMaxY && headerY < editorContentHeight - editorVisibleHeight)
        {
            // Skip any headers that are within the last screen of the editor.
            // we'll interpolate to the end of the document in that case.
            maxY = headerY;
            foundMaxY = YES;  // Gap 6: mark that we found a real maxY
        }
    }

    // Usually, we'll be scrolling between two reference nodes, but toward the end
    // of the document we'll ignore nodes and reference the end of the document instead
    BOOL interpolateToEndOfDocument = NO;

    if (!foundMaxY)
    {
        // We only have a reference node before our current position,
        // but not after, so we'll use the end of the document.
        maxY = editorContentHeight - editorVisibleHeight + adjustmentForScroll;
        interpolateToEndOfDocument = YES;
    }

    // We are currently at currY offset, between minY and maxY, which represent
    // headers indexed by relativeHeaderIndex and relativeHeaderIndex+1.
    currY = MAX(0, currY - minY);
    maxY -= minY;
    minY -= minY;
    // Gap 7: guard against division by zero when two headers share the same
    // taper-adjusted y (maxY - minY == 0) or very short documents collapse all points.
    CGFloat percentScrolledBetweenHeaders = (maxY - minY < 0.001) ? 0 : MAX(0, MIN(1.0, currY / maxY));
    
    // Now that we know where the editor position is relative to two reference nodes,
    // we need to find the positions of those nodes in the HTML preview
    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = previewContentHeight - previewVisibleHeight;
    
    // Find the Y positions in the preview window that we're scrolling between
    if ([_webViewHeaderLocations count] > relativeHeaderIndex)
    {
        topHeaderY = floorf([_webViewHeaderLocations[relativeHeaderIndex] doubleValue]) - adjustmentForScroll;
    }
    
    if (!interpolateToEndOfDocument && [_webViewHeaderLocations count] > relativeHeaderIndex + 1)
    {
        bottomHeaderY = ceilf([_webViewHeaderLocations[relativeHeaderIndex + 1] doubleValue]) - adjustmentForScroll;
    }
    
    // Now we scroll percentScrolledBetweenHeaders percent between those two positions in the webview
    CGFloat previewY = topHeaderY + (bottomHeaderY - topHeaderY) * percentScrolledBetweenHeaders;
    NSRect contentBounds = self.preview.enclosingScrollView.contentView.bounds;
    contentBounds.origin.y = previewY;

    // Issue #342: No flag toggles needed — previewBoundsDidChange: is guarded
    // by scrollOwner != MPScrollOwnerPreview, which suppresses the synchronous
    // NSViewBoundsDidChangeNotification fired by this bounds assignment.
    self.preview.enclosingScrollView.contentView.bounds = contentBounds;

    // Save this scroll position so it persists across preview refreshes
    self.lastPreviewScrollTop = previewY;
}

/**
 * Synchronizes editor pane scroll position with preview pane position.
 *
 * This is the reverse of syncScrollers - when the user scrolls the preview,
 * this method scrolls the editor to the corresponding position.
 *
 * Algorithm:
 * 1. Find reference points (headers/images) before and after current preview position
 * 2. Calculate percentage scrolled between those reference points
 * 3. Apply same percentage between corresponding editor reference points
 * 4. Use "tapering" at document edges to center-align content mid-document but
 *    align to top/bottom at document boundaries
 */
- (void)syncScrollersReverse
{
    CGFloat previewContentHeight = ceilf(NSHeight(self.preview.enclosingScrollView.documentView.bounds));
    CGFloat previewVisibleHeight = ceilf(NSHeight(self.preview.enclosingScrollView.contentView.bounds));
    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    NSInteger relativeHeaderIndex = -1; // -1 is start of document, before any other header
    CGFloat currY = NSMinY(self.preview.enclosingScrollView.contentView.bounds);
    CGFloat minY = 0;
    CGFloat maxY = 0;
    BOOL foundMaxY = NO;  // Gap 6: replace maxY==0 sentinel with explicit flag

    // Align documents at screen center for smooth sync, tapering to edges at document boundaries.
    // Taper values: 0 at document edges, 1.0 in the middle of the document.
    CGFloat topTaper = MAX(0, MIN(1.0, currY / previewVisibleHeight));
    CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0, (currY - previewContentHeight + 2 * previewVisibleHeight) / previewVisibleHeight));
    // Divide by 2 to center-align: shifts reference points by half the visible height
    CGFloat adjustmentForScroll = topTaper * bottomTaper * previewVisibleHeight / 2;

    // Search through preview header locations to find reference points
    for (NSNumber *headerYNum in _webViewHeaderLocations) {
        CGFloat headerY = [headerYNum floatValue];
        headerY -= adjustmentForScroll;

        if (headerY < currY)
        {
            // The header is before our current scroll position. the closest
            // of these will be our first reference node
            relativeHeaderIndex += 1;
            minY = headerY;
        } else if (!foundMaxY && headerY < previewContentHeight - previewVisibleHeight)
        {
            // Skip any headers that are within the last screen of the preview.
            // we'll interpolate to the end of the document in that case.
            maxY = headerY;
            foundMaxY = YES;  // Gap 6: mark that we found a real maxY
        }
    }

    // Usually, we'll be scrolling between two reference nodes, but toward the end
    // of the document we'll ignore nodes and reference the end of the document instead
    BOOL interpolateToEndOfDocument = NO;

    if (!foundMaxY)
    {
        // We only have a reference node before our current position,
        // but not after, so we'll use the end of the document.
        maxY = previewContentHeight - previewVisibleHeight + adjustmentForScroll;
        interpolateToEndOfDocument = YES;
    }

    // We are currently at currY offset, between minY and maxY, which represent
    // headers indexed by relativeHeaderIndex and relativeHeaderIndex+1.
    currY = MAX(0, currY - minY);
    maxY -= minY;
    minY -= minY;
    // Gap 7: guard against division by zero when two headers share the same
    // taper-adjusted y (maxY - minY == 0) or very short documents collapse all points.
    CGFloat percentScrolledBetweenHeaders = (maxY - minY < 0.001) ? 0 : MAX(0, MIN(1.0, currY / maxY));

    // Now that we know where the preview position is relative to two reference nodes,
    // we need to find the positions of those nodes in the editor
    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = editorContentHeight - editorVisibleHeight;

    // Find the Y positions in the editor that we're scrolling between
    if ([_editorHeaderLocations count] > relativeHeaderIndex)
    {
        topHeaderY = floorf([_editorHeaderLocations[relativeHeaderIndex] doubleValue]) - adjustmentForScroll;
    }

    if (!interpolateToEndOfDocument && [_editorHeaderLocations count] > relativeHeaderIndex + 1)
    {
        bottomHeaderY = ceilf([_editorHeaderLocations[relativeHeaderIndex + 1] doubleValue]) - adjustmentForScroll;
    }

    // Now we scroll percentScrolledBetweenHeaders percent between those two positions in the editor
    CGFloat editorY = topHeaderY + (bottomHeaderY - topHeaderY) * percentScrolledBetweenHeaders;
    NSRect contentBounds = self.editor.enclosingScrollView.contentView.bounds;
    contentBounds.origin.y = editorY;

    // Issue #342: No flag toggles needed — editorBoundsDidChange: is guarded
    // by scrollOwner == MPScrollOwnerNeither, which suppresses the synchronous
    // NSViewBoundsDidChangeNotification fired by this bounds assignment
    // (scroll owner is Preview while this runs).
    self.editor.enclosingScrollView.contentView.bounds = contentBounds;
}

- (void)setSplitViewDividerLocation:(CGFloat)ratio
{
    BOOL wasPreviewVisible = self.previewVisible;
    BOOL wasEditorVisible = self.editorVisible;
    [self.splitView setDividerLocation:ratio];
    if (!wasPreviewVisible && self.previewVisible
            && !self.preferences.markdownManualRender)
        [self.renderer parseAndRenderNow];

    // Commit 7 (gap 2): When the editor pane becomes visible, reverse-sync from the
    // preview to the editor so the editor starts at the same position as the preview.
    // Temporary MPScrollOwnerPreview suppresses editorBoundsDidChange: during the sync.
    if (!wasEditorVisible && self.editorVisible
            && self.preferences.editorSyncScrolling
            && !self.preferences.markdownManualRender
            && _scrollOwner == MPScrollOwnerNeither)
    {
        _scrollOwner = MPScrollOwnerPreview;
        [self updateHeaderLocations];
        [self syncScrollersReverse];
        _scrollOwner = MPScrollOwnerNeither;
    }

    [self setupEditor:NSStringFromSelector(@selector(editorHorizontalInset))];
}

- (NSString *)presumedFileName
{
    if (self.fileURL)
        return self.fileURL.lastPathComponent.stringByDeletingPathExtension;

    NSString *title = nil;
    NSString *string = self.editor.string;
    if (self.preferences.htmlDetectFrontMatter)
    {
        id frontMatter = [string frontMatter:NULL];
        if ([frontMatter respondsToSelector:@selector(objectForKey:)])
            title = [[frontMatter objectForKey:@"title"] description];
    }
    if (title)
        return title;

    title = string.titleString;
    if (!title)
        return NSLocalizedString(@"Untitled", @"default filename if no title can be determined");

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"[/|:]"
                                                          options:0 error:NULL];
    });

    NSRange range = NSMakeRange(0, title.length);
    title = [regex stringByReplacingMatchesInString:title options:0 range:range
                                       withTemplate:@"-"];
    return title;
}

- (void)updateWordCount
{
    DOMDocument *domDoc = self.preview.mainFrame.DOMDocument;
    DOMNodeTextCount count = domDoc.textCount;

    self.totalWords = count.words;
    self.totalCharacters = count.characters;
    self.totalCharactersNoSpaces = count.characterWithoutSpaces;

    self.lastWordCountUpdate = [NSDate timeIntervalSinceReferenceDate];

    if (self.isPreviewReady)
        self.wordCountWidget.enabled = YES;
}

// Issue #294: Throttled word count update. Fires immediately if enough
// time has elapsed, otherwise schedules a trailing update so the final
// state is always captured after typing stops.
static const NSTimeInterval kWordCountThrottleInterval = 0.25;

- (void)scheduleWordCountUpdate
{
    if (!self.preferences.editorShowWordCount)
        return;

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateWordCount)
                                               object:nil];

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = now - self.lastWordCountUpdate;

    if (elapsed >= kWordCountThrottleInterval)
    {
        [self updateWordCount];
    }
    else
    {
        NSTimeInterval delay = kWordCountThrottleInterval - elapsed;
        [self performSelector:@selector(updateWordCount)
                   withObject:nil
                   afterDelay:delay];
    }
}

- (BOOL)isCurrentBaseUrl:(NSURL *)another
{
    NSString *mine = self.currentBaseUrl.absoluteBaseURLString;
    NSString *theirs = another.absoluteBaseURLString;
    return mine == theirs || [mine isEqualToString:theirs];
}


#define OPEN_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"Please check the path of your link is correct. Turn on \
“Automatically create link targets” If you want MacDown to \
create nonexistent link targets for you.", \
@"preview navigation error information")

#define AUTO_CREATE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"MacDown can’t create a file for the clicked link because \
the current file is not saved anywhere yet. Save the \
current file somewhere to enable this feature.", \
@"preview navigation error information")

#define AUTO_CREATE_SCOPE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"MacDown only auto-creates missing file links inside the current \
document folder. Save or create the target manually if you want \
to link outside that scope.", \
@"preview navigation error information")


- (BOOL)canAutomaticallyCreateLinkedFileAtURL:(NSURL *)url
{
    if (!url.isFileURL || !self.fileURL.isFileURL)
        return NO;

    // Fall back to the document file URL if a rendering base URL isn't set.
    NSURL *baseURL = self.currentBaseUrl ?: self.fileURL;
    return [MPURLSecurityPolicy url:url isWithinScopeOfBaseURL:baseURL];
}


- (void)openOrCreateFileForUrl:(NSURL *)url
{
    // Simply open the file if it is not local, or exists already.
    BOOL file = url.isFileURL;
    BOOL reachable = !file || [url checkResourceIsReachableAndReturnError:NULL];
    
    // If the file is local but doesn't exist, check if a file with
    // the .md extension exists.
    if (file && !reachable && [url.pathExtension isEqualToString:@""])
    {
        NSURL *markdownURL = [url URLByAppendingPathExtension:@"md"];
        if ([markdownURL checkResourceIsReachableAndReturnError:NULL])
        {
            reachable = YES;
            url = markdownURL;
        }
    }
    
    if (reachable)
    {
        if (file && [MPURLSecurityPolicy isExecutableOrAppBundleAtURL:url])
        {
            NSLog(@"MacDown: Blocked opening executable from Markdown link: %@", url);
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = NSLocalizedString(
                @"Blocked: Link target is an executable",
                @"security alert title for blocked executable link");
            alert.informativeText = [NSString stringWithFormat:
                NSLocalizedString(
                    @"The link points to an executable or application bundle "
                    "at:\n%@\n\nOpening executables from Markdown links is "
                    "not allowed for security reasons.",
                    @"security alert information for blocked executable link"),
                url.path];
            [alert runModal];
            return;
        }
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    // Show an error if the user doesn't want us to create it automatically.
    if (!self.preferences.createFileForLinkTarget)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"File not found at path:\n%@",
            @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template, url.path];
        alert.informativeText = OPEN_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
        return;
    }

    // We can only create a file if the current file is saved. (Why?)
    if (!self.fileURL)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@", @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template,
                             url.lastPathComponent];
        alert.informativeText = AUTO_CREATE_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
        return;
    }

    if (![self canAutomaticallyCreateLinkedFileAtURL:url])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        NSString *template = NSLocalizedString(
            @"Blocked file creation:\n%@",
            @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template, url.path];
        alert.informativeText = AUTO_CREATE_SCOPE_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
        return;
    }

    // Try to created the file.
    NSDocumentController *controller =
        [NSDocumentController sharedDocumentController];

    NSError *error = nil;
    id doc = [controller createNewEmptyDocumentForURL:url
                                              display:YES error:&error];
    if (!doc)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@",
            @"preview navigation error message");
        alert.messageText =
            [NSString stringWithFormat:template, url.lastPathComponent];
        template = NSLocalizedString(
            @"An error occurred while creating the file:\n%@",
            @"preview navigation error information");
        alert.informativeText =
            [NSString stringWithFormat:template, error.localizedDescription];
        [alert runModal];
    }
}


- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context
{
    if ([doc respondsToSelector:@selector(setPrinting:)])
        ((MPDocument *)doc).printing = NO;
    if (context)
    {
        NSInvocation *invocation = (__bridge NSInvocation *)context;
        if ([invocation isKindOfClass:[NSInvocation class]])
        {
            [invocation setArgument:&doc atIndex:0];
            [invocation setArgument:&ok atIndex:1];
            [invocation invoke];
        }
    }
}


#pragma mark - Interactive Checkbox Support (Issue #269)

/**
 * Handle the checkbox toggle URL from the preview.
 * URL format: x-macdown-checkbox://toggle/<index>
 */
- (void)handleCheckboxToggle:(NSURL *)url
{
    if (![url.host isEqualToString:@"toggle"])
        return;

    NSURLComponents *components =
        [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *token = nil;
    for (NSURLQueryItem *item in components.queryItems)
    {
        if ([item.name isEqualToString:@"token"])
        {
            token = item.value;
            break;
        }
    }
    if (!token.length
        || ![token isEqualToString:self.renderer.checkboxBridgeToken])
    {
        NSLog(@"MacDown: Ignored unauthorized checkbox toggle: %@", url);
        return;
    }

    NSString *path = url.path;
    if (path.length < 2)
        return;

    // Extract index from path (e.g., "/0" -> 0)
    NSInteger index = [[path substringFromIndex:1] integerValue];
    if (index < 0)
        return;

    NSString *newMarkdown = [MPDocument toggleCheckboxAtIndex:(NSUInteger)index
                                                   inMarkdown:self.editor.string];
    if (![newMarkdown isEqualToString:self.editor.string])
    {
        // Preserve cursor position
        NSRange selectedRange = self.editor.selectedRange;

        // Replace the editor content
        [self.editor.textStorage beginEditing];
        [self.editor.textStorage replaceCharactersInRange:NSMakeRange(0, self.editor.string.length)
                                               withString:newMarkdown];
        [self.editor.textStorage endEditing];

        // Issue #376: replaceCharactersInRange:withString: leaves the inserted
        // text carrying character 0's attributes (e.g. a leading heading's font
        // and color smeared across the whole document). The highlighter only
        // re-parses on NSTextDidChangeNotification, which this direct textStorage
        // edit deliberately does not fire ("Gap 10" below) — so re-highlight
        // explicitly, following -reloadFromLoadedString's programmatic-swap recipe.
        // (We intentionally skip that path's -readClearTextStylesFromTextView: a
        // checkbox toggle leaves the font, theme, and default color unchanged, so
        // the highlighter's clear baselines are still valid.)
        //
        // The full-range -clearHighlighting is load-bearing: -parseAndHighlightNow
        // ultimately calls -applyVisibleRangeHighlighting, which clears and restyles
        // only the on-screen range. Without a full-document clear first, the heading
        // smear would persist on any content scrolled off-screen until it next
        // re-entered the viewport.
        [self.highlighter clearHighlighting];
        [self.highlighter parseAndHighlightNow];

        // Gap 10: textStorage editing doesn't fire NSTextDidChangeNotification.
        // Mirror editorTextDidChange: — trigger render and claim ownership.
        if (self.needsHtml)
        {
            [self.renderer parseAndRenderLater];
            _scrollOwner = MPScrollOwnerEditor;
        }

        // Restore cursor position (adjust if needed)
        if (selectedRange.location <= newMarkdown.length)
        {
            self.editor.selectedRange = selectedRange;
        }
    }
}

/**
 * Toggle the checkbox at the specified index in the markdown source.
 * Unchecked checkboxes ([ ]) become checked ([x]), and vice versa.
 * Returns the modified markdown, or the original if index is out of bounds.
 *
 * IMPORTANT: Indices are assigned in depth-first order to match hoedown's
 * rendering behavior. Nested list items get lower indices than their parent.
 * Related to GitHub issue #269.
 */
+ (NSString *)toggleCheckboxAtIndex:(NSUInteger)index inMarkdown:(NSString *)markdown
{
    if (!markdown || markdown.length == 0)
        return markdown;

    // Regex pattern to match checkbox syntax: - [ ], - [x], - [X], * [ ], etc.
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"^([ \\t]*)[-*+][ \\t]+\\[([ xX])\\]|^([ \\t]*)\\d+\\.[ \\t]+\\[([ xX])\\]"
                             options:NSRegularExpressionAnchorsMatchLines
                               error:&error];

    if (error)
        return markdown;

    // We need to skip checkboxes inside code blocks.
    NSMutableIndexSet *codeBlockRanges = [NSMutableIndexSet indexSet];

    // Find fenced code blocks (``` or ~~~)
    NSRegularExpression *fencedCodeRegex = [NSRegularExpression
        regularExpressionWithPattern:@"^[ \\t]*(```|~~~).*?\\n[\\s\\S]*?^[ \\t]*\\1[ \\t]*$"
                             options:NSRegularExpressionAnchorsMatchLines
                               error:nil];
    NSArray *fencedMatches = [fencedCodeRegex matchesInString:markdown
                                                      options:0
                                                        range:NSMakeRange(0, markdown.length)];
    for (NSTextCheckingResult *match in fencedMatches)
    {
        [codeBlockRanges addIndexesInRange:match.range];
    }

    // Find all checkbox matches in document order
    NSArray *matches = [regex matchesInString:markdown
                                      options:0
                                        range:NSMakeRange(0, markdown.length)];

    // Build list of valid checkboxes with their indentation levels
    NSMutableArray *checkboxes = [NSMutableArray array];
    for (NSTextCheckingResult *match in matches)
    {
        // Skip if this match is inside a code block
        if ([codeBlockRanges containsIndex:match.range.location])
            continue;

        // Get indentation level (capture group 1 or 3)
        NSRange indentRange = [match rangeAtIndex:1];
        if (indentRange.location == NSNotFound)
            indentRange = [match rangeAtIndex:3];
        NSUInteger indentLevel = (indentRange.location != NSNotFound) ? indentRange.length : 0;

        // Get checkbox content range (capture group 2 or 4)
        NSRange contentRange = [match rangeAtIndex:2];
        if (contentRange.location == NSNotFound)
            contentRange = [match rangeAtIndex:4];

        if (contentRange.location != NSNotFound)
        {
            [checkboxes addObject:@{
                @"match": match,
                @"indent": @(indentLevel),
                @"contentRange": [NSValue valueWithRange:contentRange]
            }];
        }
    }

    if (checkboxes.count == 0)
        return markdown;

    // Compute depth-first order using a stack-based algorithm.
    // This matches hoedown's behavior where nested items are rendered before their parent.
    // Algorithm: For each checkbox, pop stack items with indent >= current indent, then push.
    NSMutableArray *stack = [NSMutableArray array];
    NSMutableArray *depthFirstOrder = [NSMutableArray array];

    for (NSUInteger i = 0; i < checkboxes.count; i++)
    {
        NSDictionary *current = checkboxes[i];
        NSUInteger currentIndent = [current[@"indent"] unsignedIntegerValue];

        // Pop items from stack that are NOT parents of this item
        while (stack.count > 0)
        {
            NSDictionary *top = stack.lastObject;
            NSUInteger topIndent = [top[@"indent"] unsignedIntegerValue];
            if (topIndent >= currentIndent)
            {
                [depthFirstOrder addObject:top];
                [stack removeLastObject];
            }
            else
            {
                break;
            }
        }

        [stack addObject:current];
    }

    // Pop remaining items from stack
    while (stack.count > 0)
    {
        [depthFirstOrder addObject:stack.lastObject];
        [stack removeLastObject];
    }

    // Check if index is valid
    if (index >= depthFirstOrder.count)
        return markdown;

    // Find the target checkbox in depth-first order
    NSDictionary *target = depthFirstOrder[index];
    NSRange checkboxContentRange = [target[@"contentRange"] rangeValue];

    NSString *currentState = [markdown substringWithRange:checkboxContentRange];
    NSString *newState;
    if ([currentState isEqualToString:@" "])
        newState = @"x";
    else
        newState = @" ";

    NSMutableString *result = [markdown mutableCopy];
    [result replaceCharactersInRange:checkboxContentRange withString:newState];
    return result;
}


#pragma mark - File Watching (Issue #290)

- (void)startFileWatching
{
    // Tear down any previously-armed watcher first, so an early return below
    // (nil URL, or a path that cannot be watched) can never leak a stale
    // watcher for an old session. Related to #478.
    [self stopFileWatching];

    if (!self.fileURL || !self.fileURL.isFileURL)
        return;

    if (![MPFileWatcher canWatchPath:self.fileURL.path])
        return;

    __weak MPDocument *weakSelf = self;
    self.fileWatcher = [[MPFileWatcher alloc]
        initWithPath:self.fileURL.path
             handler:^(NSString *path) {
                 [weakSelf handleExternalFileChange];
             }
       cancelHandler:^(NSString *path) {
                 // File was deleted or renamed (e.g. atomic save by external editor).
                 // Wait briefly for the rename to complete, then restart watching
                 // the new inode at the same path.
                 dispatch_after(
                     dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                     MPDocument *s = weakSelf;
                     if (!s) return;                                       // document closed
                     if (![s.fileURL.path isEqualToString:path]) return;  // Save As changed URL
                     if (s.fileWatcher.isWatching) return;                // already restarted
                     if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
                     [s startFileWatching];
                     [s handleExternalFileChange];
                 });
       }];

    // Initialize resource watcher set
    if (!self.resourceWatcherSet)
    {
        self.resourceWatcherSet = [[MPResourceWatcherSet alloc] init];
        self.resourceWatcherSet.delegate = self;
    }
}

- (void)stopFileWatching
{
    [self.fileWatcher stopWatching];
    self.fileWatcher = nil;
    [self.resourceWatcherSet stopAll];
}

- (void)handleExternalFileChange
{
    // Ignore if this was our own save
    if (self.isSelfSaving)
        return;

    // Verify the file actually changed by checking modification date
    NSDate *currentModDate = self.fileModificationDate;

    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:self.fileURL.path error:&error];
    if (error)
        return;

    NSDate *diskModDate = attrs[NSFileModificationDate];

    // If dates match (or disk is older), no real change
    if (currentModDate && diskModDate &&
        [diskModDate compare:currentModDate] != NSOrderedDescending)
    {
        return;
    }

    // File has been modified externally.
    // When autosave is off, always prompt instead of silently reloading,
    // so the user stays in control of what's in their editor.
    if ([self isDocumentEdited] || !self.preferences.editorAutoSave)
    {
        [self promptForReloadWithExternalChanges];
    }
    else
    {
        [self reloadFromDisk];
    }
}

- (void)promptForReloadWithExternalChanges
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(
        @"File Modified Externally",
        @"External file change alert title");
    alert.informativeText = NSLocalizedString(
        @"This file has been changed by another application. Do you want to discard your changes?",
        @"External file change alert message");

    [alert addButtonWithTitle:NSLocalizedString(@"Discard", @"Discard changes button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Keep", @"Keep local changes button")];

    NSWindow *window = self.windowForSheet;
    if (window)
    {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn)
            {
                [self reloadFromDisk];
            }
            // If "Keep" - do nothing, user keeps their changes
        }];
    }
    else
    {
        // Fallback to modal if no window (shouldn't happen)
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn)
        {
            [self reloadFromDisk];
        }
    }
}

- (void)reloadFromDisk
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL options:0 error:&error];
    if (error || !data)
        return;

    // Read the new content
    if (![self readFromData:data ofType:self.fileType error:&error])
        return;

    // Update fileModificationDate to reflect the reloaded content
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:self.fileURL.path error:nil];
    if (attrs[NSFileModificationDate])
        self.fileModificationDate = attrs[NSFileModificationDate];

    // Clear the dirty state since we just loaded fresh content
    [self updateChangeCount:NSChangeCleared];

    // Restart file watching (descriptor may have become stale)
    [self startFileWatching];
}


#pragma mark - Document zoom

/**
 * Re-apply preview page zoom after WebKit reloads its main frame.
 */
- (void)applyPreviewZoom
{
    [self scaleWebview];
}

/**
 * Step the shared document zoom by one preset in the requested direction.
 * @param direction +1 to zoom in, -1 to zoom out.
 *
 * If the current zoom matches a preset (within epsilon), step from that
 * preset. Otherwise snap to the nearest preset on the requested side:
 * zooming in snaps up to the smallest preset greater than the current
 * value; zooming out snaps down to the largest preset less than current.
 * Beeps when already at the bound.
 */
- (void)stepDocumentZoomDirection:(NSInteger)direction
{
    NSArray<NSNumber *> *levels = MPDocumentZoomLevels();
    CGFloat current = self.preferences.documentZoomLevel;
    if (current <= 0) current = 1.0;

    // Find index of nearest preset to the current zoom.
    NSUInteger nearestIdx = 0;
    CGFloat bestDiff = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < levels.count; i++)
    {
        CGFloat diff = fabs(levels[i].doubleValue - current);
        if (diff < bestDiff)
        {
            bestDiff = diff;
            nearestIdx = i;
        }
    }

    NSInteger targetIdx;
    const CGFloat eps = 1e-6;
    if (fabs(levels[nearestIdx].doubleValue - current) < eps)
    {
        targetIdx = (NSInteger)nearestIdx + direction;
    }
    else if (direction > 0)
    {
        // Snap up to the smallest preset > current.
        targetIdx = (NSInteger)nearestIdx;
        if (levels[nearestIdx].doubleValue < current)
            targetIdx++;
    }
    else
    {
        // Snap down to the largest preset < current.
        targetIdx = (NSInteger)nearestIdx;
        if (levels[nearestIdx].doubleValue > current)
            targetIdx--;
    }

    if (targetIdx < 0 || targetIdx >= (NSInteger)levels.count)
    {
        NSBeep();
        return;
    }
    self.preferences.documentZoomLevel = levels[(NSUInteger)targetIdx].doubleValue;
}

- (IBAction)selectDocumentZoom:(id)sender
{
    // Sender is an NSPopUpButton (toolbar) or NSMenuItem (future menu).
    // Both carry the target level as an NSNumber in representedObject.
    NSNumber *level = nil;
    if ([sender isKindOfClass:[NSMenuItem class]])
    {
        level = [(NSMenuItem *)sender representedObject];
    }
    else if ([sender isKindOfClass:[NSPopUpButton class]])
    {
        level = [[(NSPopUpButton *)sender selectedItem] representedObject];
    }
    if ([level isKindOfClass:[NSNumber class]])
    {
        self.preferences.documentZoomLevel = level.doubleValue;
    }
}

@end
