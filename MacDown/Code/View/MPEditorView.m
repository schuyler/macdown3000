//
//  MPEditorView.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPEditorView.h"
#import "NSPasteboard+Types.h"
#import "FileURLInlining.h"
#import <CoreServices/CoreServices.h>


static NSString * const kMPMarkdownPasteboardType = @"net.daringfireball.markdown";


NS_INLINE BOOL MPAreRectsEqual(NSRect r1, NSRect r2)
{
    return (r1.origin.x == r2.origin.x && r1.origin.y == r2.origin.y
            && r1.size.width == r2.size.width
            && r1.size.height == r2.size.height);
}


@interface MPEditorView ()

@property NSRect contentRect;
@property CGFloat trailingHeight;

@end


@implementation MPEditorView

#pragma mark - Accessors

@synthesize contentRect = _contentRect;
@synthesize scrollsPastEnd = _scrollsPastEnd;

- (BOOL)scrollsPastEnd
{
    @synchronized(self) {
        return _scrollsPastEnd;
    }
}

- (void)awakeFromNib {
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    // Set accessibility identifier for XCUITest
    [self setAccessibilityIdentifier:@"editor-text-view"];
    [super awakeFromNib];
}

/** Handles dropped files by inlining images and inserting other content.
 *
 * Processes all supported image files and inserts them
 * as Markdown image syntax with data URLs. For non-image files, textClipping
 * content is extracted and inserted, while other files have their paths inserted.
 * Uses insertText:replacementRange: to ensure the operation is undoable.
 */
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    // Only handle specially on copy operations (Option+drag)
    // Regular drags fall back to default behavior (insert file path)
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
    if (!(sourceDragMask & NSDragOperationCopy)) {
        return [super performDragOperation:sender];
    }

    NSPasteboard *pboard = [sender draggingPasteboard];
    // Get all URLs from pasteboard
    NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];

    // Collect all content to insert
    NSArray<NSString*> *contentParts = [FileURLInlining inlineFromIterable:urls];
    if(! contentParts) return [super performDragOperation:sender];

    // Insert all content at cursor position (undoable)
    NSRange selectedRange = self.selectedRange;
    NSString *combinedContent = [contentParts componentsJoinedByString:@"\n"];
    [self insertText:combinedContent replacementRange:selectedRange];

    return YES;
}


- (void)setScrollsPastEnd:(BOOL)scrollsPastEnd
{
    @synchronized(self) {
        _scrollsPastEnd = scrollsPastEnd;
        if (scrollsPastEnd)
        {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self updateContentGeometry];
            }];
        }
        else
        {
            // Clears contentRect to fallback to self.frame.
            self.contentRect = NSZeroRect;
        }
    }
}

- (NSRect)contentRect
{
    @synchronized(self) {
        if (MPAreRectsEqual(_contentRect, NSZeroRect))
            return self.frame;
        return _contentRect;
    }
}

- (void)setContentRect:(NSRect)rect
{
    @synchronized(self) {
        _contentRect = rect;
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    if (self.scrollsPastEnd)
    {
        CGFloat ch = self.contentRect.size.height;
        CGFloat eh = self.enclosingScrollView.contentSize.height;
        CGFloat offset = ch < eh ? ch : eh;
        offset -= self.trailingHeight + 2 * self.textContainerInset.height;
        if (offset > 0)
            newSize.height += offset;
    }
    [super setFrameSize:newSize];
}

/** Overriden to perform extra operation on initial text setup.
 *
 * When we first launch the editor, -didChangeText will *not* be called, so we
 * override this to perform required resizing. The -updateContentRect is wrapped
 * inside an NSOperation to be invoked later since the layout manager will not
 * be invoked when the text is first set.
 *
 * @see didChangeText
 * @see updateContentRect
 */
- (void)setString:(NSString *)string
{
    [super setString:string];
    if (self.scrollsPastEnd)
    {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self updateContentGeometry];
        }];
    }
}


#pragma mark - Overrides

/** Overriden to perform extra operation on text change.
 *
 * Updates content height, and invoke the resizing method to apply it.
 *
 * @see updateContentRect
 */
- (void)didChangeText
{
    [super didChangeText];
    if (self.scrollsPastEnd)
        [self updateContentGeometry];
}

/** Overridden to advertise markdown UTType support for pasteboard operations.
 */
- (NSArray<NSPasteboardType> *)writablePasteboardTypes
{
    NSMutableArray *types = [[super writablePasteboardTypes] mutableCopy];
    if (![types containsObject:kMPMarkdownPasteboardType])
        [types addObject:kMPMarkdownPasteboardType];
    return types;
}

/** Overridden to include markdown UTType when copying to pasteboard.
 *
 * Adds net.daringfireball.markdown type to the pasteboard alongside standard
 * types, improving interoperability with Markdown-aware applications.
 * This method is called by both copy: and cut: operations.
 */
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray<NSPasteboardType> *)types
{
    // Let superclass handle standard types (plain text, RTF, etc.)
    BOOL success = [super writeSelectionToPasteboard:pboard types:types];

    // Add markdown type if requested (without clearing existing pasteboard data)
    if (success && [types containsObject:kMPMarkdownPasteboardType])
    {
        NSString *selectedText = [[self string] substringWithRange:[self selectedRange]];
        NSData *markdownData = [selectedText dataUsingEncoding:NSUTF8StringEncoding];
        [pboard addTypes:@[kMPMarkdownPasteboardType] owner:nil];
        [pboard setData:markdownData forType:kMPMarkdownPasteboardType];
    }

    return success;
}

/** Overridden to linkify selected text when pasting a URL.
 *
 * When text is selected and an http(s) URL is pasted, wraps the selected text
 * in a Markdown link format: [selected text](pasted url)
 */
- (void)paste:(id)sender
{
    NSRange selectedRange = self.selectedRange;

    // Only linkify if text is selected
    if (selectedRange.length == 0)
    {
        [super paste:sender];
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSURL *pastedURL = [pasteboard URLForType:NSPasteboardTypeString];

    // Only linkify if pasted content is a valid URL
    if (!pastedURL)
    {
        [super paste:sender];
        return;
    }

    // Only linkify for http and https schemes (not file://)
    NSString *scheme = pastedURL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
    {
        [super paste:sender];
        return;
    }

    // Wrap selected text as markdown link
    NSString *selectedText = [self.string substringWithRange:selectedRange];
    NSString *markdownLink = [NSString stringWithFormat:@"[%@](%@)",
                              selectedText, pastedURL.absoluteString];

    [self insertText:markdownLink replacementRange:selectedRange];
}


#pragma mark - Private

- (void)updateContentGeometry
{
    static NSCharacterSet *visibleCharacterSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        visibleCharacterSet = ws.invertedSet;
    });

    NSString *content = self.string;
    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    NSRect r = [manager usedRectForTextContainer:container];

    NSRange lastRange = [content rangeOfCharacterFromSet:visibleCharacterSet
                                                 options:NSBackwardsSearch];
    NSRect junkRect = r;
    if (lastRange.location != NSNotFound)
    {
        NSUInteger contentLength = content.length;
        NSUInteger firstJunkLocation = lastRange.location + lastRange.length;
        NSRange junkRange = NSMakeRange(firstJunkLocation,
                                        contentLength - firstJunkLocation);
        junkRect = [manager boundingRectForGlyphRange:junkRange
                                      inTextContainer:container];
    }
    self.trailingHeight = junkRect.size.height;

    NSSize inset = self.textContainerInset;
    r.size.width += 2 * inset.width;
    r.size.height += 2 * inset.height;
    self.contentRect = r;

    [self setFrameSize:self.frame.size];    // Force size update.
}

#pragma mark - Text Substitution Overrides (Issue #263)

/**
 * Override getters and setters to use app preferences instead of NSTextView's internal state.
 *
 * NSTextView initializes these properties from system-wide settings (System Preferences
 * → Keyboard → Text) and resets them during view lifecycle events (becoming first
 * responder, window loading). By overriding both getters and setters to use NSUserDefaults,
 * we ensure our app's preferences are always respected.
 *
 * The setters must also be overridden because KVO captures the "new" value by calling
 * the getter after the setter runs. If only the getter is overridden, KVO would see
 * the old value (from NSUserDefaults) instead of the new value being set.
 */

- (BOOL)isAutomaticDashSubstitutionEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorAutomaticDashSubstitutionEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setAutomaticDashSubstitutionEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorAutomaticDashSubstitutionEnabled"];
}

- (BOOL)isAutomaticDataDetectionEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorAutomaticDataDetectionEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setAutomaticDataDetectionEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorAutomaticDataDetectionEnabled"];
}

- (BOOL)isAutomaticQuoteSubstitutionEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorAutomaticQuoteSubstitutionEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorAutomaticQuoteSubstitutionEnabled"];
}

- (BOOL)isAutomaticSpellingCorrectionEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorAutomaticSpellingCorrectionEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorAutomaticSpellingCorrectionEnabled"];
}

- (BOOL)isAutomaticTextReplacementEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorAutomaticTextReplacementEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setAutomaticTextReplacementEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorAutomaticTextReplacementEnabled"];
}

- (BOOL)isContinuousSpellCheckingEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorContinuousSpellCheckingEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setContinuousSpellCheckingEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorContinuousSpellCheckingEnabled"];
}

- (BOOL)isGrammarCheckingEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorGrammarCheckingEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setGrammarCheckingEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorGrammarCheckingEnabled"];
}

- (BOOL)smartInsertDeleteEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorSmartInsertDeleteEnabled";
    if ([defaults objectForKey:key] != nil)
        return [defaults boolForKey:key];
    return NO;
}

- (void)setSmartInsertDeleteEnabled:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"editorSmartInsertDeleteEnabled"];
}

- (NSTextCheckingTypes)enabledTextCheckingTypes
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"editorEnabledTextCheckingTypes";
    if ([defaults objectForKey:key] != nil)
        return [defaults integerForKey:key];
    return NSTextCheckingAllTypes;
}

- (void)setEnabledTextCheckingTypes:(NSTextCheckingTypes)checkingTypes
{
    [[NSUserDefaults standardUserDefaults] setInteger:checkingTypes forKey:@"editorEnabledTextCheckingTypes"];
}

@end
