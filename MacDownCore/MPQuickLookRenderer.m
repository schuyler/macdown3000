//
//  MPQuickLookRenderer.m
//  MacDownCore
//
//  Quick Look renderer facade for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import "MPQuickLookRenderer.h"
#import "MPQuickLookPreferences.h"
#import <hoedown/html.h>
#import <hoedown/document.h>
#import <hoedown/escape.h>

// Error domain for Quick Look renderer
NSString * const MPQuickLookRendererErrorDomain = @"MPQuickLookRendererErrorDomain";

// Constants
static NSString * const kMPPrismThemeDirectory = @"Prism/themes";
static size_t kMPRendererNestingLevel = SIZE_MAX;

// Renderer flags from hoedown_html_patch.h
static unsigned int HOEDOWN_HTML_BLOCKCODE_INFORMATION = (1 << 6);


#pragma mark - Private Helper Functions

/**
 * Get the bundle containing Quick Look resources.
 * This could be the main app bundle or the framework bundle.
 */
NS_INLINE NSBundle *MPQuickLookBundle(void)
{
    // Try framework bundle first (when running as part of MacDownCore.framework)
    NSBundle *bundle = [NSBundle bundleForClass:[MPQuickLookRenderer class]];

    // Fall back to main bundle
    if (!bundle) {
        bundle = [NSBundle mainBundle];
    }

    return bundle;
}

/**
 * Read file contents as a string.
 */
NS_INLINE NSString *MPReadFileContents(NSString *path)
{
    if (!path) return nil;

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error) {
        NSLog(@"[MPQuickLookRenderer] Failed to read file %@: %@", path, error);
        return nil;
    }
    return content;
}

/**
 * Get the path to a CSS style file.
 */
NS_INLINE NSString *MPStylePathForName(NSString *name)
{
    if (!name) return nil;

    // Add .css extension if not present
    if (![[name pathExtension] isEqualToString:@"css"]) {
        name = [name stringByAppendingPathExtension:@"css"];
    }

    // Look in Application Support first (user styles)
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *appSupportPath = [paths[0] stringByAppendingPathComponent:@"MacDown 3000/Styles"];
        NSString *stylePath = [appSupportPath stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:stylePath]) {
            return stylePath;
        }
    }

    // Fall back to bundle resources
    NSBundle *bundle = MPQuickLookBundle();
    NSString *bundlePath = [bundle pathForResource:[name stringByDeletingPathExtension]
                                            ofType:@"css"
                                       inDirectory:@"Styles"];
    return bundlePath;
}

/**
 * Get URL for Prism highlighting theme.
 * Checks Application Support directory first (user themes),
 * then falls back to bundle resources.
 */
NS_INLINE NSURL *MPHighlightingThemeURLForName(NSString *name)
{
    NSString *themeName = [NSString stringWithFormat:@"prism-%@", [name lowercaseString]];
    if ([[themeName pathExtension] isEqualToString:@"css"]) {
        themeName = [themeName stringByDeletingPathExtension];
    }
    NSString *fileName = [themeName stringByAppendingPathExtension:@"css"];

    NSFileManager *manager = [NSFileManager defaultManager];

    // Check Application Support first (user themes)
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *userThemePath = [paths[0]
            stringByAppendingPathComponent:
                [@"MacDown 3000" stringByAppendingPathComponent:
                    [kMPPrismThemeDirectory stringByAppendingPathComponent:
                        fileName]]];
        if ([manager fileExistsAtPath:userThemePath]) {
            return [NSURL fileURLWithPath:userThemePath];
        }
    }

    // Fall back to bundle resources
    NSBundle *bundle = MPQuickLookBundle();
    NSURL *url = [bundle URLForResource:themeName
                          withExtension:@"css"
                           subdirectory:kMPPrismThemeDirectory];

    // Fallback to default theme
    if (!url) {
        url = [bundle URLForResource:@"prism"
                       withExtension:@"css"
                        subdirectory:kMPPrismThemeDirectory];
    }

    return url;
}

/**
 * Preprocess markdown to work around Hoedown parser limitations.
 */
NS_INLINE NSString *MPPreprocessMarkdown(NSString *text)
{
    if (!text.length) return text;

    // Fenced code blocks after text (Issue #36)
    static NSRegularExpression *fenceRegex = nil;
    static dispatch_once_t fenceToken;
    dispatch_once(&fenceToken, ^{
        NSString *pattern = @"^(\\S.*)\\n(`{3,}|~{3,})(?=\\S|\\n.)";
        fenceRegex = [[NSRegularExpression alloc] initWithPattern:pattern
                                                          options:NSRegularExpressionAnchorsMatchLines
                                                            error:NULL];
    });

    NSString *result = text;
    result = [fenceRegex stringByReplacingMatchesInString:result
                                                  options:0
                                                    range:NSMakeRange(0, result.length)
                                             withTemplate:@"$1\n\n$2"];

    return result;
}

NS_INLINE NSString *MPQuickLookContentSecurityPolicy(void)
{
    return @"default-src 'none'; "
           @"base-uri 'none'; "
           @"form-action 'none'; "
           @"object-src 'none'; "
           @"frame-src 'none'; "
           @"connect-src 'none'; "
           @"img-src data: file:; "
           @"media-src data: file:; "
           @"font-src data: file:; "
           @"style-src 'unsafe-inline'; "
           @"script-src 'none'";
}


#pragma mark - Hoedown Renderer Callbacks

// Decode the UTF-8 codepoint starting at data[i] (i < size). Returns the
// number of bytes consumed (1-4) and stores the codepoint in *codepoint, or
// returns 0 if the sequence is malformed / truncated, in which case the
// caller should pass the raw byte through unchanged.
static size_t decode_utf8_codepoint(const uint8_t *data, size_t size, size_t i,
                                     uint32_t *codepoint)
{
    uint8_t c = data[i];
    size_t len;
    uint32_t cp;

    if ((c & 0x80) == 0x00)      { cp = c;        len = 1; }
    else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; len = 2; }
    else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; len = 3; }
    else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; len = 4; }
    else return 0;

    if (i + len > size)
        return 0;

    for (size_t k = 1; k < len; k++)
    {
        uint8_t cc = data[i + k];
        if ((cc & 0xC0) != 0x80)
            return 0;
        cp = (cp << 6) | (cc & 0x3F);
    }

    *codepoint = cp;
    return len;
}

// Encode a codepoint <= 0x7FF (used only for lowercased Latin-1 letters) as
// two UTF-8 bytes.
static void encode_utf8_2byte(uint32_t cp, uint8_t out[2])
{
    out[0] = (uint8_t)(0xC0 | (cp >> 6));
    out[1] = (uint8_t)(0x80 | (cp & 0x3F));
}

// Build a stable text-derived slug from a heading's HTML content, matching
// GitHub's heading-anchor slug algorithm (github-slugger semantics) so
// [text](#slug) links copied from GitHub-rendered Markdown keep working.
// Mirrors slugify() in MacDown/Code/Extension/hoedown_html_patch.c so the
// preview and Quick Look render identical heading ids.
// Strips HTML tags and skips HTML entities (&amp; / &lt; / &#39; ...), then
// trims leading/trailing whitespace from the heading text. ASCII letters are
// lowercased; digits, '_' and literal '-' are kept as-is; each remaining
// ASCII space/tab maps to exactly one hyphen (runs are NOT collapsed, e.g.
// "Foo --- Bar" -> "foo-----bar"); other ASCII punctuation is dropped.
// Non-ASCII text is decoded as UTF-8: Latin-1 uppercase letters
// (U+00C0-U+00DE, excluding the multiplication sign U+00D7) are lowercased
// and re-encoded; the Latin-1 punctuation/symbol block (U+00A1-U+00BF), the
// multiplication/division signs (U+00D7, U+00F7), and the General
// Punctuation block (U+2000-U+206F, which covers em/en dashes, curly quotes,
// ellipsis, ...) are dropped entirely; every other codepoint passes through
// unchanged as raw UTF-8 bytes (e.g. "Introducción" -> "introducción").
// Malformed UTF-8 bytes are passed through unchanged rather than dropped.
// Anchors keep their raw UTF-8 bytes (no percent-encoding): browsers match
// the URL fragment against the id literally, so encoding would break
// navigation.
static void mp_quicklook_slugify(hoedown_buffer *out, const hoedown_buffer *content)
{
    if (!content || !content->size)
        return;

    size_t start = 0, end = content->size;
    while (start < end && (content->data[start] == ' ' ||
                            content->data[start] == '\t' ||
                            content->data[start] == '\n' ||
                            content->data[start] == '\r'))
        start++;
    while (end > start && (content->data[end - 1] == ' ' ||
                            content->data[end - 1] == '\t' ||
                            content->data[end - 1] == '\n' ||
                            content->data[end - 1] == '\r'))
        end--;

    int in_tag = 0;

    for (size_t i = start; i < end; i++)
    {
        uint8_t c = content->data[i];

        if (in_tag)
        {
            if (c == '>') in_tag = 0;
            continue;
        }
        if (c == '<')
        {
            in_tag = 1;
            continue;
        }
        if (c == '&')
        {            // skip an HTML entity like &amp; / &lt; / &#39;
            while (i + 1 < end && content->data[i + 1] != ';')
                i++;
            i++;                    // consume the ';'
            continue;
        }

        if (c >= 0x80)
        {
            uint32_t cp;
            size_t len = decode_utf8_codepoint(content->data, end, i, &cp);

            if (len == 0)
            {
                // Malformed / truncated sequence: pass the raw byte through.
                hoedown_buffer_putc(out, c);
                continue;
            }

            if ((cp >= 0x00A1 && cp <= 0x00BF) || cp == 0x00D7 ||
                cp == 0x00F7 || (cp >= 0x2000 && cp <= 0x206F))
            {
                // Dropped punctuation/symbol codepoint: emit nothing.
            }
            else if (cp >= 0x00C0 && cp <= 0x00DE && cp != 0x00D7)
            {
                uint8_t enc[2];
                encode_utf8_2byte(cp + 0x20, enc);
                hoedown_buffer_put(out, enc, 2);
            }
            else
            {
                hoedown_buffer_put(out, content->data + i, len);
            }

            i += len - 1;
            continue;
        }

        if (c >= 'A' && c <= 'Z')
            c += 32;

        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            c == '_' || c == '-')
        {
            hoedown_buffer_putc(out, c);
        }
        else if (c == ' ' || c == '\t')
        {
            hoedown_buffer_putc(out, '-');
        }
    }
}

// hoedown_buffer_new() stores its argument as the buffer's growth "unit", and
// hoedown_buffer_grow() asserts that unit is non-zero. A size hint of 0 (an
// empty heading, e.g. a bare setext underline) therefore yields a buffer that
// aborts the process on first write. Clamp the hint so the buffer is always
// growable. Mirrors new_growable_buffer() in hoedown_html_patch.c. Issue #479.
static hoedown_buffer *mp_quicklook_new_growable_buffer(size_t size_hint)
{
    return hoedown_buffer_new(size_hint ? size_hint : 16);
}

// Emit headings with text-derived id attributes so anchor links work in
// Quick Look previews, matching the main MacDown preview behavior.
static void mp_quicklook_render_header(
    hoedown_buffer *ob, const hoedown_buffer *content, int level,
    const hoedown_renderer_data *data)
{
    (void)data;
    if (ob->size) hoedown_buffer_putc(ob, '\n');

    hoedown_buffer *slug =
        mp_quicklook_new_growable_buffer(content ? content->size : 16);
    mp_quicklook_slugify(slug, content);
    if (slug->size == 0)
        HOEDOWN_BUFPUTSL(slug, "section");

    hoedown_buffer_printf(ob, "<h%d id=\"", level);
    hoedown_buffer_put(ob, slug->data, slug->size);
    HOEDOWN_BUFPUTSL(ob, "\">");
    if (content) hoedown_buffer_put(ob, content->data, content->size);
    hoedown_buffer_printf(ob, "</h%d>\n", level);

    hoedown_buffer_free(slug);
}

/**
 * Custom blockcode renderer that adds Prism language classes without scripts.
 */
static void mp_quicklook_render_blockcode(
    hoedown_buffer *ob,
    const hoedown_buffer *text,
    const hoedown_buffer *lang,
    const hoedown_renderer_data *data)
{
    if (ob->size) hoedown_buffer_putc(ob, '\n');

    HOEDOWN_BUFPUTSL(ob, "<pre><code");

    if (lang && lang->size) {
        NSString *language = [[NSString alloc] initWithBytes:lang->data
                                                      length:lang->size
                                                    encoding:NSUTF8StringEncoding];

        // Add language class for Prism
        HOEDOWN_BUFPUTSL(ob, " class=\"language-");
        hoedown_buffer_put(ob, lang->data, lang->size);
        HOEDOWN_BUFPUTSL(ob, "\"");
    }

    HOEDOWN_BUFPUTSL(ob, ">");

    if (text) {
        hoedown_escape_html(ob, text->data, text->size, 0);
    }

    HOEDOWN_BUFPUTSL(ob, "</code></pre>\n");
}


@interface MPQuickLookRenderer ()
@property (nonatomic, strong) MPQuickLookPreferences *preferences;
@end


@implementation MPQuickLookRenderer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _preferences = [MPQuickLookPreferences sharedPreferences];
    }
    return self;
}

#pragma mark - Public Methods

- (NSString *)renderMarkdown:(NSString *)markdown
{
    if (!markdown) {
        return nil;
    }

    if (markdown.length == 0) {
        return [self wrapBodyInHTML:@""];
    }

    // Preprocess markdown
    NSString *preprocessed = MPPreprocessMarkdown(markdown);

    // Parse markdown to HTML body
    NSString *body = [self parseMarkdownToHTML:preprocessed];

    // Wrap in complete HTML document
    return [self wrapBodyInHTML:body];
}

- (NSString *)renderMarkdownFromURL:(NSURL *)url error:(NSError **)error
{
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:MPQuickLookRendererErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"URL is nil"}];
        }
        return nil;
    }

    NSError *readError = nil;
    NSString *markdown = [NSString stringWithContentsOfURL:url
                                                  encoding:NSUTF8StringEncoding
                                                     error:&readError];

    // Fall back to auto-detected encoding if UTF-8 fails (e.g. UTF-16 with BOM)
    if (!markdown) {
        readError = nil;
        markdown = [NSString stringWithContentsOfURL:url
                                        usedEncoding:NULL
                                               error:&readError];
    }

    // Last resort: ISO Latin-1 can decode any byte sequence, so it never fails.
    // This handles single-byte encodings that lack a BOM for auto-detection.
    if (!markdown) {
        readError = nil;
        markdown = [NSString stringWithContentsOfURL:url
                                            encoding:NSISOLatin1StringEncoding
                                               error:&readError];
    }

    if (!markdown) {
        if (error) {
            *error = readError;
        }
        return nil;
    }

    // Normalize Windows CRLF to LF (Issue #382)
    markdown = [markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];

    return [self renderMarkdown:markdown];
}

#pragma mark - Private Methods

- (NSString *)parseMarkdownToHTML:(NSString *)markdown
{
    int extensions = [self.preferences extensionFlags];
    int flags = [self.preferences rendererFlags];

    // Create HTML renderer
    hoedown_renderer *renderer = hoedown_html_renderer_new(flags, 0);

    // Preserve Prism language classes, but Quick Look never executes Prism JS.
    renderer->blockcode = mp_quicklook_render_blockcode;
    renderer->header = mp_quicklook_render_header;

    // Create document
    hoedown_document *document = hoedown_document_new(
        renderer, extensions, kMPRendererNestingLevel);

    // Render
    NSData *inputData = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    hoedown_buffer *ob = hoedown_buffer_new(64);
    hoedown_document_render(document, ob, inputData.bytes, inputData.length);

    NSString *result = @"";
    if (ob->size > 0) {
        result = [[NSString alloc] initWithBytes:ob->data
                                          length:ob->size
                                        encoding:NSUTF8StringEncoding];
    }

    // Cleanup
    hoedown_buffer_free(ob);
    hoedown_document_free(document);
    hoedown_html_renderer_free(renderer);

    return result ?: @"";
}

- (NSString *)wrapBodyInHTML:(NSString *)body
{
    NSMutableString *html = [NSMutableString string];

    // HTML header
    [html appendString:@"<!DOCTYPE html>\n"];
    [html appendString:@"<html>\n<head>\n"];
    [html appendString:@"<meta charset=\"utf-8\">\n"];
    [html appendString:@"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"];
    [html appendFormat:@"<meta http-equiv=\"Content-Security-Policy\" content=\"%@\">\n",
                       MPQuickLookContentSecurityPolicy()];

    // Embed CSS styles
    [html appendString:[self embeddedStyles]];

    [html appendString:@"</head>\n<body>\n"];

    // Body content
    [html appendString:body ?: @""];

    [html appendString:@"\n</body>\n</html>"];

    return html;
}

- (NSString *)embeddedStyles
{
    NSMutableString *styles = [NSMutableString string];

    // Main CSS style
    NSString *styleName = [self.preferences styleName];
    NSString *stylePath = MPStylePathForName(styleName);
    NSString *styleContent = MPReadFileContents(stylePath);

    if (styleContent.length > 0) {
        [styles appendString:@"<style type=\"text/css\">\n"];
        [styles appendString:styleContent];
        [styles appendString:@"\n</style>\n"];
    }

    // Prism theme CSS (if syntax highlighting enabled)
    if ([self.preferences syntaxHighlightingEnabled]) {
        NSString *themeName = [self.preferences highlightingThemeName];
        NSURL *themeURL = MPHighlightingThemeURLForName(themeName);
        NSString *themeContent = MPReadFileContents(themeURL.path);

        if (themeContent.length > 0) {
            [styles appendString:@"<style type=\"text/css\">\n"];
            [styles appendString:themeContent];
            [styles appendString:@"\n</style>\n"];
        }
    }

    return styles;
}
@end
