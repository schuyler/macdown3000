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


static NSString * const kMPMarkdownInteropPasteboardType = @"app.macdown.markdown-interop";



static NSUInteger MPInlineCodeDelimiterAfterLine(NSString *line, NSUInteger delimiter)
{
    for (NSUInteger i=0;i<line.length;i++) if ([line characterAtIndex:i]=='`') {
        NSUInteger escapes=0;while(i>escapes && [line characterAtIndex:i-escapes-1]=='\\') escapes++;
        if (escapes%2) continue;
        NSUInteger width=1;while(i+width<line.length && [line characterAtIndex:i+width]=='`') width++;
        if (!delimiter) delimiter=width;else if (width==delimiter) delimiter=0;
        i+=width-1;
    }
    return delimiter;
}

// Notion's Markdown clipboard uses standalone HTML aside delimiters. Convert
// paired containers only; fenced examples and malformed HTML stay literal.
static NSString *MPConvertPastedAsides(NSString *text)
{
    if ([text rangeOfString:@"<aside>" options:NSCaseInsensitiveSearch].location==NSNotFound) return text;
    NSArray<NSString *> *lines=[text componentsSeparatedByString:@"\n"];
    NSMutableArray *output=lines.mutableCopy,*stack=[NSMutableArray array],*pairs=[NSMutableArray array];
    NSRegularExpression *code=[NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(?:>[ \\t]*)*(?:(?:[-+*]|[0-9]+[.)])[ \\t]+)?(`{3,}|~{3,})(.*)$" options:0 error:NULL];
    NSString *fence=nil;
    NSUInteger inlineDelimiter=0;
    for (NSUInteger i=0;i<lines.count;i++) {
        NSString *line=lines[i];
        NSTextCheckingResult *match=[code firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        NSString *run=match ? [line substringWithRange:[match rangeAtIndex:1]] : nil;
        if (fence) {
            if (run && [run characterAtIndex:0]==[fence characterAtIndex:0] && run.length>=fence.length &&
                ![[line substringWithRange:[match rangeAtIndex:2]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) fence=nil;
            continue;
        }
        if (inlineDelimiter) {inlineDelimiter=MPInlineCodeDelimiterAfterLine(line,inlineDelimiter);continue;}
        if (run) {fence=run;continue;}
        inlineDelimiter=MPInlineCodeDelimiterAfterLine(line,0);
        NSString *trimmed=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
        if ([trimmed isEqualToString:@"<aside>"]) [stack addObject:@(i)];
        else if ([trimmed isEqualToString:@"</aside>"]) {
            if (!stack.count) return text;
            [pairs addObject:@{@"start":stack.lastObject,@"end":@(i)}];[stack removeLastObject];
        }
    }
    if (stack.count || !pairs.count) return text;
    // A standalone copied container can carry indentation from its former
    // list in Notion. Remove the common margin, retaining relative indentation.
    NSUInteger first=0,last=lines.count;
    while (first<last && ![lines[first] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) first++;
    while (last>first && ![lines[last-1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) last--;
    NSDictionary *outer=pairs.lastObject;
    NSString *margin=@"";
    if ([outer[@"start"] unsignedIntegerValue]==first && [outer[@"end"] unsignedIntegerValue]+1==last) {
        NSString *line=lines[first];
        NSUInteger width=0;while(width<line.length && ([line characterAtIndex:width]==' ' || [line characterAtIndex:width]=='\t')) width++;
        margin=[line substringToIndex:width];
        for (NSString *candidate in lines) if ([candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length && ![candidate hasPrefix:margin]) {margin=@"";break;}
    }
    for (NSUInteger i=0;i<output.count;i++) if (margin.length && [output[i] hasPrefix:margin]) output[i]=[output[i] substringFromIndex:margin.length];
    for (NSDictionary *pair in pairs) {
        NSUInteger start=[pair[@"start"] unsignedIntegerValue],end=[pair[@"end"] unsignedIntegerValue];
        NSString *line=output[start];
        NSUInteger width=0;while(width<line.length && ([line characterAtIndex:width]==' ' || [line characterAtIndex:width]=='\t')) width++;
        NSString *indent=[line substringToIndex:width],*ending=[line hasSuffix:@"\r"] ? @"\r" : @"";
        NSString *type=@"note";
        for (NSUInteger i=start+1;i<end;i++) {
            NSString *content=[lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!content.length) continue;
            if ([content isEqualToString:@"💡"]) type=@"tip";
            else if ([content isEqualToString:@"⚠️"] || [content isEqualToString:@"⚠"]) type=@"warning";
            break;
        }
        output[start]=[NSString stringWithFormat:@"%@::: {.callout-%@}%@",indent,type,ending];
        output[end]=[NSString stringWithFormat:@"%@:::%@",indent,[output[end] hasSuffix:@"\r"] ? @"\r" : @""];
    }
    return [output componentsJoinedByString:@"\n"];
}

static BOOL MPPasteIsInsideCode(NSString *source, NSUInteger location)
{
    NSString *prefix=[source substringToIndex:MIN(location,source.length)];
    NSRegularExpression *code=[NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(?:>[ \\t]*)*(?:(?:[-+*]|[0-9]+[.)])[ \\t]+)?(`{3,}|~{3,})(.*)$" options:0 error:NULL];
    NSString *fence=nil;
    NSUInteger inlineDelimiter=0;
    for (NSString *line in [prefix componentsSeparatedByString:@"\n"]) {
        if (!fence && inlineDelimiter) {inlineDelimiter=MPInlineCodeDelimiterAfterLine(line,inlineDelimiter);continue;}
        NSTextCheckingResult *match=[code firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        if (!match) {if (!fence) inlineDelimiter=MPInlineCodeDelimiterAfterLine(line,0);continue;}
        NSString *run=[line substringWithRange:[match rangeAtIndex:1]];
        if (!fence) fence=run;
        else if ([run characterAtIndex:0]==[fence characterAtIndex:0] && run.length>=fence.length &&
            ![[line substringWithRange:[match rangeAtIndex:2]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) fence=nil;
    }
    if (fence || inlineDelimiter) return YES;
    NSString *line=[prefix componentsSeparatedByString:@"\n"].lastObject;
    NSUInteger indentation=0;
    while (indentation<line.length && ([line characterAtIndex:indentation]==' ' || [line characterAtIndex:indentation]=='\t')) indentation++;
    if (indentation>=4 || [line hasPrefix:@"\t"]) {
        NSArray *lines=[prefix componentsSeparatedByString:@"\n"];
        BOOL inList=NO;
        NSRegularExpression *item=[NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(?:[-+*]|[0-9]+[.)])[ \\t]+" options:0 error:NULL];
        for (NSInteger i=(NSInteger)lines.count-2;i>=0;i--) {
            NSString *previous=lines[i];
            if (![previous stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) continue;
            NSUInteger width=0;while(width<previous.length && ([previous characterAtIndex:width]==' ' || [previous characterAtIndex:width]=='\t')) width++;
            if (width>=indentation) continue;
            NSTextCheckingResult *match=[item firstMatchInString:previous options:0 range:NSMakeRange(0,previous.length)];
            inList=match && NSMaxRange(match.range)<=indentation && indentation-NSMaxRange(match.range)<4;break;
        }
        if (!inList) return YES;
    }
    return MPInlineCodeDelimiterAfterLine(line,0)!=0;
}


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

/** Overridden to advertise a Markdown interop UTType for pasteboard operations.
 */
- (NSArray<NSPasteboardType> *)writablePasteboardTypes
{
    NSMutableArray *types = [[super writablePasteboardTypes] mutableCopy];
    if (![types containsObject:kMPMarkdownInteropPasteboardType])
        [types addObject:kMPMarkdownInteropPasteboardType];
    return types;
}

/** Overridden to include a Markdown interop UTType when copying to pasteboard.
 *
 * Adds app.macdown.markdown-interop to the pasteboard alongside standard
 * types, improving interoperability with Markdown-aware applications. This
 * type declares no filename extension, unlike net.daringfireball.markdown,
 * which caused apps like Messages to treat copied text as a file attachment
 * (issue #571). This method is called by both copy: and cut: operations.
 */
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray<NSPasteboardType> *)types
{
    // Let superclass handle standard types (plain text, RTF, etc.)
    BOOL success = [super writeSelectionToPasteboard:pboard types:types];

    // Add markdown interop type if requested (without clearing existing pasteboard data)
    if (success && [types containsObject:kMPMarkdownInteropPasteboardType])
    {
        NSString *selectedText = [[self string] substringWithRange:[self selectedRange]];
        NSData *markdownData = [selectedText dataUsingEncoding:NSUTF8StringEncoding];
        [pboard addTypes:@[kMPMarkdownInteropPasteboardType] owner:nil];
        [pboard setData:markdownData forType:kMPMarkdownInteropPasteboardType];
    }

    return success;
}

// AppKit's generic ingestion path can bypass the type-specific override.
// Share one insertion operation between all native paste entry points.
- (BOOL)insertConvertedAsideFromPasteboard:(NSPasteboard *)pasteboard
{
    if (![pasteboard.types containsObject:kMPMarkdownInteropPasteboardType]) {
        NSString *original=[pasteboard stringForType:NSPasteboardTypeString];
        if (!original || [original rangeOfString:@"<aside>" options:NSCaseInsensitiveSearch].location==NSNotFound ||
            MPPasteIsInsideCode(self.string,self.selectedRange.location)) return NO;
        NSString *converted=MPConvertPastedAsides(original);
        if (converted && ![converted isEqualToString:original]) {
            NSRange selection=self.selectedRange;
            NSUInteger start;
            [self.string getLineStart:&start end:NULL contentsEnd:NULL forRange:NSMakeRange(selection.location,0)];
            NSString *before=[self.string substringWithRange:NSMakeRange(start,selection.location-start)];
            if ([before stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length)
                converted=[@"\n\n" stringByAppendingString:converted];
            else if (before.length) {
                // The first line already follows the insertion point's margin;
                // carry that margin to every subsequent pasted physical line.
                converted=[converted stringByReplacingOccurrencesOfString:@"\n" withString:[@"\n" stringByAppendingString:before]];
            }
            NSUInteger selectionEnd=NSMaxRange(selection),contentsEnd;
            [self.string getLineStart:NULL end:NULL contentsEnd:&contentsEnd forRange:NSMakeRange(selectionEnd,0)];
            NSString *after=[self.string substringWithRange:NSMakeRange(selectionEnd,contentsEnd-selectionEnd)];
            if ([after stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length)
                converted=[converted stringByAppendingString:@"\n\n"];
            [self insertText:converted replacementRange:selection];
            return YES;
        }
    }
    return NO;
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pasteboard
{
    if ([self insertConvertedAsideFromPasteboard:pasteboard]) return YES;
    return [super readSelectionFromPasteboard:pasteboard];
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pasteboard type:(NSPasteboardType)type
{
    if ([type isEqualToString:NSPasteboardTypeString] && [self insertConvertedAsideFromPasteboard:pasteboard]) return YES;
    return [super readSelectionFromPasteboard:pasteboard type:type];
}

- (void)pasteAsPlainText:(id)sender
{
    if ([self insertConvertedAsideFromPasteboard:NSPasteboard.generalPasteboard]) return;
    [super pasteAsPlainText:sender];
}

/** Overridden to linkify selected text when pasting a URL.
 *
 * When text is selected and an http(s) URL is pasted, wraps the selected text
 * in a Markdown link format: [selected text](pasted url)
 */
- (void)paste:(id)sender
{
    if ([self insertConvertedAsideFromPasteboard:NSPasteboard.generalPasteboard]) return;
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
    selectedText = [selectedText stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    selectedText = [selectedText stringByReplacingOccurrencesOfString:@"[" withString:@"\\["];
    selectedText = [selectedText stringByReplacingOccurrencesOfString:@"]" withString:@"\\]"];
    NSString *destination = [pastedURL.absoluteString stringByReplacingOccurrencesOfString:@"(" withString:@"%28"];
    destination = [destination stringByReplacingOccurrencesOfString:@")" withString:@"%29"];
    NSString *markdownLink = [NSString stringWithFormat:@"[%@](%@)",
                              selectedText, destination];

    [self insertText:markdownLink replacementRange:selectedRange];
}


#pragma mark - Private

- (void)updateContentGeometry
{
    // A deferred update may outlive the preference that scheduled it. Keep the
    // disabled mode's contentRect fallback intact when that update runs later.
    if (!self.scrollsPastEnd)
        return;

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
        NSRange junkGlyphRange = [manager glyphRangeForCharacterRange:junkRange
                                                   actualCharacterRange:NULL];
        junkRect = [manager boundingRectForGlyphRange:junkGlyphRange
                                      inTextContainer:container];
    }
    self.trailingHeight = junkRect.size.height;

    NSSize inset = self.textContainerInset;
    r.size.width += 2 * inset.width;
    r.size.height += 2 * inset.height;
    self.contentRect = r;

    // Rebuild the natural height from content and viewport. self.frame already
    // includes the past-end padding added by setFrameSize:, so using it again
    // would accumulate that padding on every content update.
    NSSize size = self.frame.size;
    size.height = MAX(r.size.height, self.enclosingScrollView.contentSize.height);
    [self setFrameSize:size];
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
