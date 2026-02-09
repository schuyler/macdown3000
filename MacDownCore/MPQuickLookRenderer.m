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

// Error domain for Quick Look renderer
NSString * const MPQuickLookRendererErrorDomain = @"MPQuickLookRendererErrorDomain";

// Constants
static NSString * const kMPPrismScriptDirectory = @"Prism/components";
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
 */
NS_INLINE NSURL *MPHighlightingThemeURLForName(NSString *name)
{
    NSString *themeName = [NSString stringWithFormat:@"prism-%@", [name lowercaseString]];
    if ([[themeName pathExtension] isEqualToString:@"css"]) {
        themeName = [themeName stringByDeletingPathExtension];
    }

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


#pragma mark - Hoedown Renderer Callbacks

// Extra state for language tracking
typedef struct {
    void *owner;
    NSMutableArray *languages;
} MPQuickLookRendererState;

/**
 * Custom blockcode renderer that tracks languages for Prism.
 */
static void mp_quicklook_render_blockcode(
    hoedown_buffer *ob,
    const hoedown_buffer *text,
    const hoedown_buffer *lang,
    const hoedown_renderer_data *data)
{
    hoedown_html_renderer_state *state = data->opaque;
    MPQuickLookRendererState *extra = state->opaque;

    if (ob->size) hoedown_buffer_putc(ob, '\n');

    HOEDOWN_BUFPUTSL(ob, "<pre><code");

    if (lang && lang->size) {
        NSString *language = [[NSString alloc] initWithBytes:lang->data
                                                      length:lang->size
                                                    encoding:NSUTF8StringEncoding];

        // Track language for Prism script inclusion
        if (extra && extra->languages && language.length > 0) {
            if (![extra->languages containsObject:language]) {
                [extra->languages addObject:language];
            }
        }

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
@property (nonatomic, strong) NSMutableArray *detectedLanguages;
@end


@implementation MPQuickLookRenderer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _preferences = [MPQuickLookPreferences sharedPreferences];
        _detectedLanguages = [NSMutableArray array];
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

    // Clear detected languages
    [self.detectedLanguages removeAllObjects];

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

    if (readError) {
        if (error) {
            *error = readError;
        }
        return nil;
    }

    return [self renderMarkdown:markdown];
}

#pragma mark - Private Methods

- (NSString *)parseMarkdownToHTML:(NSString *)markdown
{
    int extensions = [self.preferences extensionFlags];
    int flags = [self.preferences rendererFlags];

    // Create HTML renderer
    hoedown_renderer *renderer = hoedown_html_renderer_new(flags, 0);

    // Set up custom blockcode handler for language tracking
    renderer->blockcode = mp_quicklook_render_blockcode;

    // Set up extra state for language tracking
    MPQuickLookRendererState extra;
    extra.owner = (__bridge void *)self;
    extra.languages = self.detectedLanguages;
    ((hoedown_html_renderer_state *)renderer->opaque)->opaque = &extra;

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

    // Embed CSS styles
    [html appendString:[self embeddedStyles]];

    [html appendString:@"</head>\n<body>\n"];

    // Body content
    [html appendString:body ?: @""];

    // Embed scripts (Prism for syntax highlighting)
    if ([self.preferences syntaxHighlightingEnabled] && self.detectedLanguages.count > 0) {
        [html appendString:[self embeddedScripts]];
    }

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

- (NSString *)embeddedScripts
{
    NSMutableString *scripts = [NSMutableString string];
    NSBundle *bundle = MPQuickLookBundle();

    // Prism core
    NSURL *coreURL = [bundle URLForResource:@"prism-core.min"
                              withExtension:@"js"
                               subdirectory:kMPPrismScriptDirectory];
    if (!coreURL) {
        coreURL = [bundle URLForResource:@"prism-core"
                           withExtension:@"js"
                            subdirectory:kMPPrismScriptDirectory];
    }

    NSString *coreContent = MPReadFileContents(coreURL.path);
    if (coreContent.length > 0) {
        [scripts appendString:@"<script type=\"text/javascript\">\n"];
        [scripts appendString:coreContent];
        [scripts appendString:@"\n</script>\n"];
    }

    // Language-specific Prism components
    for (NSString *language in self.detectedLanguages) {
        NSString *langFile = [NSString stringWithFormat:@"prism-%@.min", [language lowercaseString]];
        NSURL *langURL = [bundle URLForResource:langFile
                                  withExtension:@"js"
                                   subdirectory:kMPPrismScriptDirectory];
        if (!langURL) {
            langFile = [NSString stringWithFormat:@"prism-%@", [language lowercaseString]];
            langURL = [bundle URLForResource:langFile
                               withExtension:@"js"
                                subdirectory:kMPPrismScriptDirectory];
        }

        NSString *langContent = MPReadFileContents(langURL.path);
        if (langContent.length > 0) {
            [scripts appendString:@"<script type=\"text/javascript\">\n"];
            [scripts appendString:langContent];
            [scripts appendString:@"\n</script>\n"];
        }
    }

    return scripts;
}

@end
