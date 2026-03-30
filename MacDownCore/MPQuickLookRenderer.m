//
//  MPQuickLookRenderer.m
//  MacDownCore
//
//  Quick Look renderer facade for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import "MPQuickLookRenderer.h"
#import "MPQuickLookPreferences.h"
#import <cmark-gfm/cmark-gfm.h>
#import <cmark-gfm/cmark-gfm-extension_api.h>
#import <cmark-gfm/cmark-gfm-core-extensions.h>

// Error domain for Quick Look renderer
NSString * const MPQuickLookRendererErrorDomain = @"MPQuickLookRendererErrorDomain";

// Constants
static NSString * const kMPPrismScriptDirectory = @"Prism/components";
static NSString * const kMPPrismThemeDirectory = @"Prism/themes";


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

    // Parse markdown to HTML body using cmark-gfm
    NSString *body = [self parseMarkdownToHTML:markdown];

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
    int options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE;

    // Register extensions once
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cmark_gfm_core_extensions_ensure_registered();
    });

    // Create parser
    cmark_parser *parser = cmark_parser_new(options);

    // Attach extensions based on preferences
    cmark_llist *extensions = NULL;
    cmark_mem *mem = cmark_get_default_mem_allocator();

    if ([self.preferences extensionTables]) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("table");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }
    if ([self.preferences extensionAutolink]) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("autolink");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }
    if ([self.preferences extensionStrikethrough]) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("strikethrough");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }

    // Parse
    NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_parser_feed(parser, data.bytes, data.length);
    cmark_node *document = cmark_parser_finish(parser);

    // Track languages from code blocks
    [self extractLanguagesFromDocument:document];

    // Render to HTML
    char *html_cstr = cmark_render_html(document, options, extensions);
    NSString *result = html_cstr ? [NSString stringWithUTF8String:html_cstr] : @"";

    // Free resources
    free(html_cstr);
    cmark_node_free(document);
    cmark_parser_free(parser);
    if (extensions)
        cmark_llist_free(mem, extensions);

    return result;
}

- (void)extractLanguagesFromDocument:(cmark_node *)document
{
    cmark_iter *iter = cmark_iter_new(document);
    cmark_event_type ev_type;
    while ((ev_type = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        cmark_node *node = cmark_iter_get_node(iter);
        if (cmark_node_get_type(node) == CMARK_NODE_CODE_BLOCK && ev_type == CMARK_EVENT_ENTER) {
            const char *fence_info = cmark_node_get_fence_info(node);
            if (fence_info && strlen(fence_info) > 0) {
                NSString *language = [NSString stringWithUTF8String:fence_info];
                // Take first word (language) if info string has additional text
                NSRange spaceRange = [language rangeOfString:@" "];
                if (spaceRange.location != NSNotFound)
                    language = [language substringToIndex:spaceRange.location];
                if (![self.detectedLanguages containsObject:language])
                    [self.detectedLanguages addObject:language];
            }
        }
    }
    cmark_iter_free(iter);
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
