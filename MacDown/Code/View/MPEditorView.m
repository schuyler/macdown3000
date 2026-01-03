//
//  MPEditorView.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPEditorView.h"
#import "NSPasteboard+Types.h"
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
    [super awakeFromNib];
}

/** Handles dropped files by inlining images and inserting other content.
 *
 * Processes all supported image files (JPEG, PNG, GIF, WebP) and inserts them
 * as Markdown image syntax with data URLs. For non-image files, textClipping
 * content is extracted and inserted, while other files have their paths inserted.
 * Uses insertText:replacementRange: to ensure the operation is undoable.
 */
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];

    // Check if pasteboard contains file URLs
    if (![pboard.types containsObject:NSPasteboardTypeFileURL]) {
        return [super performDragOperation:sender];
    }

    // Only handle specially on copy operations (Option+drag)
    // Regular drags fall back to default behavior (insert file path)
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
    if (!(sourceDragMask & NSDragOperationCopy)) {
        return [super performDragOperation:sender];
    }

    // Get all URLs from pasteboard
    NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];

    // Collect all content to insert
    NSMutableArray *contentParts = [NSMutableArray array];

    for (NSURL *url in urls) {
        if (![url isFileURL]) continue;

        // Check if it's a supported image
        NSString *uti = [self imageUTIForFilePath:url.path];
        if (uti) {
            NSString *mimeType = [self mimeTypeForUTI:uti];
            if (!mimeType) continue;

            // Load file data
            NSError *error;
            NSData *fileData = [NSData dataWithContentsOfFile:url.path
                                                      options:NSDataReadingMappedIfSafe
                                                        error:&error];
            if (!fileData) continue;

            // Convert to base64 and create markdown image
            NSString *base64String = [fileData base64EncodedStringWithOptions:0];
            NSString *markdown = [NSString stringWithFormat:@"![](data:%@;base64,%@)",
                                  mimeType, base64String];
            [contentParts addObject:markdown];
        }
        // Check if it's a textClipping
        else if ([self isTextClippingAtPath:url.path]) {
            NSString *clippingContent = [self textContentFromClipping:url];
            if (clippingContent) {
                [contentParts addObject:clippingContent];
            }
        }
        // For other files, insert the file path
        else {
            [contentParts addObject:url.path];
        }
    }

    // If no content was extracted, fall back to default behavior
    if (contentParts.count == 0) {
        return [super performDragOperation:sender];
    }

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

/** Returns the supported image UTI for a file path, or nil if unsupported.
 *
 * Checks if the file's UTI conforms to one of the supported image types:
 * JPEG, PNG, GIF, or WebP.
 *
 * @param filePath The path to the file
 * @return The matching supported UTI string, or nil if not a supported image
 */
- (NSString *)imageUTIForFilePath:(NSString *)filePath
{
    NSArray *supportedUTIs = @[@"public.jpeg", @"public.png",
                               @"com.compuserve.gif", @"public.webp"];

    // Get UTI from file extension
    NSString *extension = [filePath pathExtension];
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        (__bridge CFStringRef)extension,
        NULL);

    if (!fileUTI) return nil;

    NSString *uti = (__bridge_transfer NSString *)fileUTI;

    // Check if the UTI conforms to any of our supported types
    for (NSString *supportedUTI in supportedUTIs) {
        if (UTTypeConformsTo((__bridge CFStringRef)uti,
                             (__bridge CFStringRef)supportedUTI)) {
            return supportedUTI;
        }
    }

    return nil;
}

/** Maps a UTI to its corresponding MIME type for data URLs.
 *
 * @param uti The Uniform Type Identifier
 * @return The MIME type string, or nil if not supported
 */
- (NSString *)mimeTypeForUTI:(NSString *)uti
{
    NSDictionary *mapping = @{
        @"public.jpeg": @"image/jpeg",
        @"public.png": @"image/png",
        @"com.compuserve.gif": @"image/gif",
        @"public.webp": @"image/webp"
    };
    return mapping[uti];
}

/** Returns whether the file at the given path is a textClipping file.
 *
 * TextClipping files are created by macOS when dragging text to Finder.
 * They have the UTI com.apple.finder.textclipping.
 *
 * @param filePath The path to the file
 * @return YES if the file is a textClipping, NO otherwise
 */
- (BOOL)isTextClippingAtPath:(NSString *)filePath
{
    NSString *extension = [filePath pathExtension];
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        (__bridge CFStringRef)extension,
        NULL);

    if (!fileUTI) return NO;

    BOOL isTextClipping = UTTypeConformsTo(fileUTI,
        CFSTR("com.apple.finder.textclipping"));
    CFRelease(fileUTI);

    return isTextClipping;
}

/** Reads the text content from a textClipping file.
 *
 * TextClipping files store their content as a binary plist. This method
 * extracts the UTF-8 or UTF-16 text content from the file.
 *
 * @param url The file URL of the textClipping
 * @return The text content, or nil if it could not be read
 */
- (NSString *)textContentFromClipping:(NSURL *)url
{
    NSError *error;
    NSData *fileData = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!fileData) return nil;

    // Try to read as binary plist
    NSDictionary *plist = [NSPropertyListSerialization
        propertyListWithData:fileData
        options:NSPropertyListImmutable
        format:NULL
        error:&error];

    if (![plist isKindOfClass:[NSDictionary class]]) return nil;

    // Try UTF-8 text first
    NSData *textData = plist[@"public.utf8-plain-text"];
    if (textData) {
        return [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
    }

    // Fall back to UTF-16 text
    textData = plist[@"public.utf16-plain-text"];
    if (textData) {
        return [[NSString alloc] initWithData:textData encoding:NSUTF16StringEncoding];
    }

    return nil;
}

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

@end
