//
//  MPQuickLookRenderer.m
//  MacDownCore
//
//  Quick Look renderer facade for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import "MPQuickLookRenderer.h"
#import "MPQuickLookPreferences.h"
#import <cmark-gfm/mdmark.h>

// Error domain for Quick Look renderer
NSString * const MPQuickLookRendererErrorDomain = @"MPQuickLookRendererErrorDomain";

// Constants
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

    // Parse markdown to HTML body. The hoedown-era preprocessing
    // workarounds are unnecessary with cmark-gfm (issue #77); CRLF
    // normalization happens in renderMarkdownFromURL:error:.
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
    // Renders through the shared mdmark (cmark-gfm) pipeline so Quick Look
    // previews and the app preview share one parser (issue #77). Quick Look
    // passes no language callback: Prism never runs here, so fence classes
    // keep their raw language token. Heading ids come out identical to the
    // app preview's (same slugify), keeping anchor links working.
    mdmark_options options = {0};
    options.extensions = [self.preferences extensionFlags];
    options.html_flags = [self.preferences rendererFlags];

    mdmark_reset_checkbox_index();

    NSData *inputData = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    char *rendered = mdmark_render_html(
        inputData.bytes, inputData.length, &options);
    NSString *result =
        [NSString stringWithUTF8String:rendered ? rendered : ""];
    free(rendered);

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
