//
//  MPRenderer.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 26/6.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPRenderer.h"
#import "../../../MacDownCore/MPReaderStyles.h"
#import <limits.h>
#import <hoedown/html.h>
#import <hoedown/document.h>
#import <HBHandlebars/HBHandlebars.h>
#import "hoedown_html_patch.h"
#import "NSJSONSerialization+File.h"
#import "NSString+Lookup.h"
#import "MPUtilities.h"
#import "MPAsset.h"
#import "MPPreferences.h"
#import "MPHTMLResourceURLs.h"
#import "../../../MacDownCore/MPMarkdownPreprocessor.h"

// Warning: If the version of MathJax is ever updated, please check the status
// of https://github.com/mathjax/MathJax/issues/548. If the fix has been merged
// in to MathJax, then the WebResourceLoadDelegate can be removed from MPDocument
// and MathJax.js can be removed from this project.
static NSString * const kMPMathJaxCDN =
    @"https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/MathJax.js"
    @"?config=TeX-AMS-MML_HTMLorMML";
static NSString * const kMPPrismScriptDirectory = @"Prism/components";
static NSString * const kMPPrismThemeDirectory = @"Prism/themes";
static NSString * const kMPPrismPluginDirectory = @"Prism/plugins";
static int kMPRendererTOCLevel = 6;  // h1 to h6.


NS_INLINE NSURL *MPExtensionURL(NSString *name, NSString *extension)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:name withExtension:extension
                           subdirectory:@"Extensions"];
    return url;
}

NS_INLINE NSURL *MPPrismPluginURL(NSString *name, NSString *extension)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *dirPath =
        [NSString stringWithFormat:@"%@/%@", kMPPrismPluginDirectory, name];

    NSString *filename = [NSString stringWithFormat:@"prism-%@.min", name];
    NSURL *url = [bundle URLForResource:filename withExtension:extension
                           subdirectory:dirPath];
    if (url)
        return url;

    filename = [NSString stringWithFormat:@"prism-%@", name];
    url = [bundle URLForResource:filename withExtension:extension
                    subdirectory:dirPath];
    return url;
}

NS_INLINE NSArray *MPPrismScriptURLsForLanguage(NSString *language)
{
    NSURL *baseUrl = nil;
    NSURL *extraUrl = nil;
    NSBundle *bundle = [NSBundle mainBundle];

    language = [language lowercaseString];
    NSString *baseFileName =
        [NSString stringWithFormat:@"prism-%@", language];
    NSString *extraFileName =
        [NSString stringWithFormat:@"prism-%@-extras", language];

    for (NSString *ext in @[@"min.js", @"js"])
    {
        if (!baseUrl)
        {
            baseUrl = [bundle URLForResource:baseFileName withExtension:ext
                                subdirectory:kMPPrismScriptDirectory];
        }
        if (!extraUrl)
        {
            extraUrl = [bundle URLForResource:extraFileName withExtension:ext
                                 subdirectory:kMPPrismScriptDirectory];
        }
    }

    NSMutableArray *urls = [NSMutableArray array];
    if (baseUrl)
        [urls addObject:baseUrl];
    if (extraUrl)
        [urls addObject:extraUrl];
    return urls;
}

NS_INLINE NSString *MPHTMLFromMarkdown(
    NSString *text, int flags, BOOL smartypants, NSString *frontMatter, NSUInteger sourceOffset,
    hoedown_renderer *htmlRenderer, hoedown_renderer *tocRenderer)
{
    // Preprocess markdown for Hoedown compatibility (Issues #254, #36, #37)
    NSString *source = text ?: @"";
    NSDictionary *preprocessed = MPPreprocessMarkdown(text, (flags & HOEDOWN_EXT_FENCED_CODE) != 0, sourceOffset);
    // Reuse the same callout grammar on the original snapshot. Compatibility
    // preprocessing inserts task markers/newlines and normalizes CRLF, so its
    // offsets cannot be published as source offsets. Associate proven pairs
    // in closing order; omit metadata if preprocessing changed that structure.
    NSArray *originalCallouts = MPPrepareCallouts(source)[@"callouts"];
    NSArray *renderedCallouts = preprocessed[@"callouts"];
    BOOL sameStructure = originalCallouts.count == renderedCallouts.count;
    for (NSUInteger i = 0; sameStructure && i < originalCallouts.count; i++) {
        NSDictionary *original = originalCallouts[i], *rendered = renderedCallouts[i];
        NSString *opening = original[@"sourceOpen"];
        if ([opening hasSuffix:@"\r"]) opening = [opening substringToIndex:opening.length-1];
        sameStructure = [opening isEqualToString:rendered[@"sourceOpen"]] &&
            [original[@"type"] isEqual:rendered[@"type"]] &&
            ((!original[@"collapse"] && !rendered[@"collapse"]) ||
             [original[@"collapse"] isEqual:rendered[@"collapse"]]);
    }
    if (sameStructure) {
        hoedown_html_renderer_state_extra *state =
            ((hoedown_html_renderer_state *)htmlRenderer->opaque)->opaque;
        NSDictionary *context = (__bridge NSDictionary *)state->owner;
        NSMutableArray *entries = context[@"calloutEntries"];
        NSString *fullSource = context[@"sourceMarkdown"];
        NSUInteger sourceLineOffset = sourceOffset ?
            [[fullSource substringToIndex:sourceOffset] componentsSeparatedByString:@"\n"].count-1 : 0;
        for (NSUInteger i = 0; i < originalCallouts.count; i++) {
            NSMutableDictionary *entry = [originalCallouts[i] mutableCopy];
            entry[@"token"] = renderedCallouts[i][@"token"];
            entry[@"start"] = @([entry[@"start"] unsignedIntegerValue]+sourceLineOffset);
            entry[@"end"] = @([entry[@"end"] unsignedIntegerValue]+sourceLineOffset);
            for (NSString *key in @[@"sourceOpenRange", @"sourceCloseRange", @"sourceContentRange"]) {
                NSRange range = [entry[key] rangeValue];
                range.location += sourceOffset;
                entry[key] = [NSValue valueWithRange:range];
            }
            [entries addObject:[entry copy]];
        }
    }
    text = preprocessed[@"text"];
    __attribute__((objc_precise_lifetime)) NSString *codeEscapeToken = preprocessed[@"codeEscapeToken"];
    hoedown_html_renderer_state_extra *extra =
        ((hoedown_html_renderer_state *)htmlRenderer->opaque)->opaque;
    extra->code_escape_token = codeEscapeToken.UTF8String;
    __attribute__((objc_precise_lifetime)) NSString *taskPrefix = preprocessed[@"taskPrefix"];
    extra->task_marker_prefix = taskPrefix.UTF8String;

    NSData *inputData = [text dataUsingEncoding:NSUTF8StringEncoding];
    hoedown_document *document = hoedown_document_new(
        htmlRenderer, flags, MPMarkdownMaximumNesting);
    hoedown_buffer *ob = hoedown_buffer_new(64);
    hoedown_document_render(document, ob, inputData.bytes, inputData.length);
    if (smartypants)
    {
        hoedown_buffer *ib = ob;
        ob = hoedown_buffer_new(64);
        hoedown_html_smartypants(ob, ib->data, ib->size);
        hoedown_buffer_free(ib);
    }
    NSString *result = [[NSString alloc] initWithBytes:ob->data length:ob->size
                                           encoding:NSUTF8StringEncoding] ?: @"";
    hoedown_document_free(document);
    hoedown_buffer_free(ob);

    if (tocRenderer)
    {
        document = hoedown_document_new(
            tocRenderer, flags, MPMarkdownMaximumNesting);
        ob = hoedown_buffer_new(64);
        hoedown_document_render(
            document, ob, inputData.bytes, inputData.length);
        NSString *toc = [[NSString alloc] initWithBytes:ob->data length:ob->size
                                            encoding:NSUTF8StringEncoding] ?: @"";

        static NSRegularExpression *tocRegex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *pattern = @"<p.*?>\\s*\\[TOC\\]\\s*</p>";
            NSRegularExpressionOptions ops = NSRegularExpressionCaseInsensitive;
            tocRegex = [[NSRegularExpression alloc] initWithPattern:pattern
                                                            options:ops
                                                              error:NULL];
        });
        NSRange replaceRange = NSMakeRange(0, result.length);
        result = [tocRegex stringByReplacingMatchesInString:result options:0
                                                      range:replaceRange
                                               withTemplate:[NSRegularExpression escapedTemplateForString:toc]];
        hoedown_document_free(document);
        hoedown_buffer_free(ob);
    }
    result = MPFinishCallouts(result, preprocessed[@"callouts"]);
    // Raw HTML can retain a recognized pair as literal delimiters. Publish
    // source ownership only for identities actually emitted by MPFinishCallouts;
    // its per-parse prefix was proven absent from the original source.
    NSMutableArray *entries = ((__bridge NSDictionary *)extra->owner)[@"calloutEntries"];
    NSIndexSet *unrendered = [entries indexesOfObjectsPassingTest:
        ^BOOL(NSDictionary *entry, NSUInteger index, BOOL *stop) {
            NSString *identity = [NSString stringWithFormat:@"data-macdown-callout-token=\"%@\"",entry[@"token"]];
            return [result rangeOfString:identity].location == NSNotFound;
        }];
    [entries removeObjectsAtIndexes:unrendered];
    if (frontMatter)
        result = [NSString stringWithFormat:@"%@\n%@", frontMatter, result];
    
    return MPRemoveTaskMarkers(result, taskPrefix);
}

NS_INLINE NSString *MPEscapeHTMLAttribute(NSString *value);
NS_INLINE NSString *MPEscapeHTMLText(NSString *value);
NS_INLINE NSString *MPPreviewContentSecurityPolicy(void);
NS_INLINE NSString *MPPreviewHeadTags(NSString *checkboxBridgeToken);

NS_INLINE NSString *MPGetHTML(
    NSString *title, NSString *headTags, NSString *body, NSArray *styles,
    MPAssetOption styleopt, NSArray *scripts, MPAssetOption scriptopt)
{
    NSMutableArray *styleTags = [NSMutableArray array];
    NSMutableArray *scriptTags = [NSMutableArray array];
    for (MPStyleSheet *style in styles)
    {
        NSString *s = [style htmlForOption:styleopt];
        if (s)
            [styleTags addObject:s];
    }
    for (MPScript *script in scripts)
    {
        NSString *s = [script htmlForOption:scriptopt];
        if (s)
            [scriptTags addObject:s];
    }

    MPPreferences *preferences = [MPPreferences sharedInstance];

    static NSString *f = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *url = [bundle URLForResource:preferences.htmlTemplateName
                              withExtension:@".handlebars"
                               subdirectory:@"Templates"];
        f = [NSString stringWithContentsOfURL:url
                                     encoding:NSUTF8StringEncoding error:NULL];
    });
    NSCAssert(f.length, @"Could not read template");

    NSString *titleTag = @"";
    if (title.length)
        titleTag = [NSString stringWithFormat:@"<title>%@</title>",
                    MPEscapeHTMLText(title)];

    NSDictionary *context = @{
        @"title": title ? title : @"",
        @"titleTag": titleTag ? titleTag : @"",
        @"headTags": headTags ? headTags : @"",
        @"styleTags": styleTags ? styleTags : @[],
        @"body": body ? body : @"",
        @"scriptTags": scriptTags ? scriptTags : @[],
    };
    NSString *html = [HBHandlebars renderTemplateString:f withContext:context
                                                  error:NULL];
    return html;
}

NS_INLINE BOOL MPAreNilableStringsEqual(NSString *s1, NSString *s2)
{
    // The == part takes care of cases where s1 and s2 are both nil.
    return ([s1 isEqualToString:s2] || s1 == s2);
}


@interface MPRenderer ()

@property (strong) NSMutableArray *currentLanguages;
@property (readonly) NSArray *baseStylesheets;
@property (readonly) NSArray *prismStylesheets;
@property (readonly) NSArray *prismScripts;
@property (readonly) NSArray *mathjaxScripts;
@property (readonly) NSArray *mermaidScripts;
@property (readonly) NSArray *graphvizScripts;
@property (readonly) NSArray *stylesheets;
@property (readonly) NSArray *scripts;
@property (copy) NSString *currentHtml;
@property (strong) NSOperationQueue *parseQueue;
@property int extensions;
@property BOOL smartypants;
@property BOOL TOC;
@property (copy) NSString *styleName;
@property BOOL frontMatter;
@property BOOL syntaxHighlighting;
@property BOOL wrapsCodeBlocks;
@property BOOL mermaid;
@property BOOL graphviz;
@property BOOL mathJax;
@property MPCodeBlockAccessoryType codeBlockAccesory;
@property BOOL lineNumbers;
@property BOOL manualRender;
@property NSUInteger renderGeneration;
@property (copy) NSString *highlightingThemeName;
@property (nonatomic, copy, readwrite) NSString *checkboxBridgeToken;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *checkboxSourceOffsets;
@property (nonatomic, copy, readwrite) NSString *checkboxSourceMarkdown;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *calloutSourceEntries;

// Issue #110: Cache-busting timestamps for local resources
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *resourceTimestamps;

@end


NS_INLINE void add_to_languages(
    NSString *lang, NSMutableArray *languages, NSDictionary *languageMap)
{
    // Move language to root of dependencies.
    NSUInteger index = [languages indexOfObject:lang];
    if (index != NSNotFound)
        [languages removeObjectAtIndex:index];
    [languages insertObject:lang atIndex:0];

    // Add dependencies of this language.
    id require = languageMap[lang][@"require"];
    if ([require isKindOfClass:[NSString class]])
    {
        add_to_languages(require, languages, languageMap);
    }
    else if ([require isKindOfClass:[NSArray class]])
    {
        for (NSString *lang in require)
            add_to_languages(lang, languages, languageMap);
    }
    else if (require)
    {
        NSLog(@"Unknown Prism langauge requirement "
              @"%@ dropped for unknown format", require);
    }
}


NS_INLINE hoedown_buffer *language_addition(
    const hoedown_buffer *language, void *owner)
{
    NSDictionary *context = (__bridge NSDictionary *)owner;
    NSMutableArray *languages = context[@"languages"];
    NSString *lang = [[NSString alloc] initWithBytes:language->data
                                              length:language->size
                                            encoding:NSUTF8StringEncoding];

    static NSDictionary *aliasMap = nil;
    static NSDictionary *languageMap = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *url = [bundle URLForResource:@"syntax_highlighting"
                              withExtension:@"json"];
        NSDictionary *info =
            [NSJSONSerialization JSONObjectWithFileAtURL:url options:0
                                                   error:NULL];

        aliasMap = info[@"aliases"];

        url = [bundle URLForResource:@"components" withExtension:@"js"
                        subdirectory:@"Prism"];
        NSString *code = [NSString stringWithContentsOfURL:url
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
        NSDictionary *comp = MPGetObjectFromJavaScript(code, @"components");
        languageMap = comp[@"languages"];
    });

    // Try to identify alias and point it to the "real" language name.
    hoedown_buffer *mapped = NULL;
    if ([aliasMap objectForKey:lang])
    {
        lang = [aliasMap objectForKey:lang];
        NSData *data = [lang dataUsingEncoding:NSUTF8StringEncoding];
        mapped = hoedown_buffer_new(64);
        hoedown_buffer_put(mapped, data.bytes, data.length);
    }

    // Walk dependencies to include all required scripts.
    add_to_languages(lang, languages, languageMap);
    
    return mapped;
}

NS_INLINE void checkbox_addition(size_t offset, void *owner)
{
    NSDictionary *context = (__bridge NSDictionary *)owner;
    [context[@"checkboxOffsets"] addObject:@(offset)];
}

NS_INLINE hoedown_renderer *MPCreateHTMLRenderer(int flags, int tocLevel, NSDictionary *context)
{
    hoedown_renderer *htmlRenderer = hoedown_html_renderer_new(
        flags, tocLevel);
    htmlRenderer->blockcode = hoedown_patch_render_blockcode;
    htmlRenderer->listitem = hoedown_patch_render_listitem;
    htmlRenderer->header = hoedown_patch_render_header;
    htmlRenderer->table_header = hoedown_patch_render_table_header;

    hoedown_html_renderer_state_extra *extra =
        hoedown_malloc(sizeof(hoedown_html_renderer_state_extra));
    extra->language_addition = language_addition;
    extra->owner = (__bridge void *)context;
    extra->checkbox_index = 0;
    extra->code_escape_token = NULL;
    extra->interactive_checkboxes = 1;
    extra->task_marker_prefix = NULL;
    extra->checkbox_addition = checkbox_addition;
    extra->heading_slug = MPUniqueHeadingSlug;

    ((hoedown_html_renderer_state *)htmlRenderer->opaque)->opaque = extra;
    return htmlRenderer;
}

NS_INLINE hoedown_renderer *MPCreateHTMLTOCRenderer(NSDictionary *context)
{
    hoedown_renderer *tocRenderer =
        hoedown_html_toc_renderer_new(kMPRendererTOCLevel);
    tocRenderer->header = hoedown_patch_render_toc_header;
    hoedown_html_renderer_state_extra *extra = calloc(1, sizeof(*extra));
    extra->owner = (__bridge void *)context;
    extra->heading_slug = MPUniqueHeadingSlug;
    ((hoedown_html_renderer_state *)tocRenderer->opaque)->opaque = extra;
    return tocRenderer;
}

NS_INLINE void MPFreeHTMLRenderer(hoedown_renderer *htmlRenderer)
{
    hoedown_html_renderer_state_extra *extra =
        ((hoedown_html_renderer_state *)htmlRenderer->opaque)->opaque;
    if (extra)
        free(extra);
    hoedown_html_renderer_free(htmlRenderer);
}

NS_INLINE NSString *MPEscapeHTMLAttribute(NSString *value)
{
    if (!value.length)
        return @"";

    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" withString:@"&#39;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

NS_INLINE NSString *MPEscapeHTMLText(NSString *value)
{
    if (!value.length)
        return @"";

    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;"
                                options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

NS_INLINE NSString *MPPreviewContentSecurityPolicy(void)
{
    // MathJax 2.x relies on eval/new Function during startup, and bundled
    // preview libraries inject inline styles while rendering annotated output.
    //
    // Issue #341: img-src and media-src must keep data:, file:, http: and
    // https: allowed. Dropping any scheme silently breaks image rendering for
    // that source — the <img> container still lays out, but the bits never
    // load. MPImageRenderingTests pins this contract; update it deliberately
    // if you tighten the policy.
    return @"default-src 'none'; "
           @"base-uri 'none'; "
           @"form-action 'none'; "
           @"object-src 'none'; "
           @"frame-src 'none'; "
           @"img-src data: file: http: https:; "
           @"media-src data: file: http: https:; "
           @"style-src 'self' 'unsafe-inline' file:; "
           @"font-src data: file:; "
           @"connect-src http: https:; "
           @"script-src 'self' file: https://cdnjs.cloudflare.com 'unsafe-eval'";
}

NS_INLINE NSString *MPPreviewHeadTags(NSString *checkboxBridgeToken)
{
    NSString *csp = MPEscapeHTMLAttribute(MPPreviewContentSecurityPolicy());
    NSString *checkboxToken = MPEscapeHTMLAttribute(checkboxBridgeToken);
    return [NSString stringWithFormat:
        @"<meta http-equiv=\"Content-Security-Policy\" content=\"%@\">\n"
         "<meta name=\"macdown-checkbox-token\" content=\"%@\">",
        csp, checkboxToken];
}


@implementation MPRenderer

+ (NSArray<NSNumber *> *)checkboxOffsetsForMarkdown:(NSString *)markdown
{
    MPRenderer *renderer = [[self alloc] init];
    NSDictionary *options = @{@"extensions": @(HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_TABLES |
        HOEDOWN_EXT_STRIKETHROUGH | HOEDOWN_EXT_AUTOLINK), @"smartypants": @NO,
        @"frontMatter": @NO, @"toc": @NO, @"flags": @(HOEDOWN_HTML_USE_TASK_LIST)};
    return [renderer parseResultForMarkdown:markdown options:options][@"checkboxOffsets"];
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.currentHtml = @"";
    self.currentLanguages = [NSMutableArray array];
    self.resourceTimestamps = [NSMutableDictionary dictionary];
    self.parseQueue = [[NSOperationQueue alloc] init];
    self.parseQueue.maxConcurrentOperationCount = 1; // Serial queue

    return self;
}

#pragma mark - Accessor

- (NSArray *)baseStylesheets
{
    NSString *defaultStyleName =
        MPStylePathForName([self.delegate rendererStyleName:self]);
    if (!defaultStyleName)
        return @[];
    NSURL *defaultStyle = [NSURL fileURLWithPath:defaultStyleName];
    NSMutableArray *stylesheets = [NSMutableArray array];
    [stylesheets addObject:[MPStyleSheet CSSWithURL:defaultStyle]];
    return stylesheets;
}

- (NSArray *)prismStylesheets
{
    NSString *name = [self.delegate rendererHighlightingThemeName:self];
    MPAsset *stylesheet =
        [MPStyleSheet CSSWithURL:MPHighlightingThemeURLForName(name)];

    NSMutableArray *stylesheets = [NSMutableArray arrayWithObject:stylesheet];

    if (self.rendererFlags & HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS)
    {
        NSURL *url = MPPrismPluginURL(@"line-numbers", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }
    if ([self.delegate rendererCodeBlockAccesory:self]
        == MPCodeBlockAccessoryLanguageName)
    {
        NSURL *url = MPPrismPluginURL(@"show-language", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }

    return stylesheets;
}

- (NSArray *)prismScripts
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:@"prism-core.min" withExtension:@"js"
                           subdirectory:kMPPrismScriptDirectory];
    MPAsset *script = [MPScript javaScriptWithURL:url];
    NSMutableArray *scripts = [NSMutableArray arrayWithObject:script];
    for (NSString *language in self.currentLanguages)
    {
        for (NSURL *url in MPPrismScriptURLsForLanguage(language))
            [scripts addObject:[MPScript javaScriptWithURL:url]];
    }

    if (self.rendererFlags & HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS)
    {
        NSURL *url = MPPrismPluginURL(@"line-numbers", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    if ([self.delegate rendererCodeBlockAccesory:self]
        == MPCodeBlockAccessoryLanguageName)
    {
        NSURL *url = MPPrismPluginURL(@"show-language", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    return scripts;
}

- (NSArray *)mathjaxScripts
{
    NSMutableArray *scripts = [NSMutableArray array];
    NSURL *url = [NSURL URLWithString:kMPMathJaxCDN];
    NSBundle *bundle = [NSBundle mainBundle];
    MPEmbeddedScript *script =
        [MPEmbeddedScript assetWithURL:[bundle URLForResource:@"init"
                                                withExtension:@"js"
                                                 subdirectory:@"MathJax"]
                               andType:kMPMathJaxConfigType];
    [scripts addObject:script];
    [scripts addObject:[MPScript javaScriptWithURL:url]];
    return scripts;
}

- (NSArray *)mermaidScripts
{
    // TODO
    NSMutableArray *scripts = [NSMutableArray array];

    {
        NSURL *url = MPExtensionURL(@"mermaid.min", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"mermaid.init", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    
    return scripts;
}

- (NSArray *)graphvizScripts
{
    // TODO
    NSMutableArray *scripts = [NSMutableArray array];

    {
        NSURL *url = MPExtensionURL(@"viz", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"viz.init", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    
    return scripts;
}

- (NSArray *)stylesheets
{
    id<MPRendererDelegate> delegate = self.delegate;

    NSMutableArray *stylesheets = [self.baseStylesheets mutableCopy];
    if ([delegate rendererHasSyntaxHighlighting:self])
    {
        [stylesheets addObjectsFromArray:self.prismStylesheets];
    }

    if ([delegate rendererCodeBlockAccesory:self] == MPCodeBlockAccessoryCustom)
    {
        NSURL *url = MPExtensionURL(@"show-information", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }

    // Load print.css to ensure it overrides theme defaults for PDF export
    NSURL *printURL = MPExtensionURL(@"print", @"css");
    [stylesheets addObject:[MPStyleSheet CSSWithURL:printURL]];

    // Load export.css last for paragraph text wrapping in HTML exports and preview
    NSURL *exportURL = MPExtensionURL(@"export", @"css");
    [stylesheets addObject:[MPStyleSheet CSSWithURL:exportURL]];

    return stylesheets;
}

- (NSArray *)scripts
{
    id<MPRendererDelegate> d = self.delegate;
    NSMutableArray *scripts = [NSMutableArray array];
    if (self.rendererFlags & HOEDOWN_HTML_USE_TASK_LIST)
    {
        NSURL *url = MPExtensionURL(@"tasklist", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"table-resize", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    if ([d rendererHasSyntaxHighlighting:self])
    {
        [scripts addObjectsFromArray:self.prismScripts];
    }
    // Mermaid and Graphviz render from the language-* class (always
    // emitted) via their own init scripts; they do not depend on Prism.
    // Keep them out of the syntax-highlighting gate so diagrams render
    // even when syntax highlighting is off (GitHub issue #533).
    if ([d rendererHasMermaid:self])
    {
        [scripts addObjectsFromArray:self.mermaidScripts];
    }
    if ([d rendererHasGraphviz:self])
    {
        [scripts addObjectsFromArray:self.graphvizScripts];
    }
    if ([d rendererHasMathJax:self])
        [scripts addObjectsFromArray:self.mathjaxScripts];
    return scripts;
}

#pragma mark - Public
    
// Readiness is polled on the main queue without blocking it. A new request
// invalidates old completion blocks, including those already dispatched.
- (void)renderWhenReadyUntil:(NSDate *)deadline generation:(NSUInteger)generation
{
    if (generation != self.renderGeneration)
        return;
    if (![self.dataSource rendererLoading] || deadline.timeIntervalSinceNow <= 0)
    {
        [self render];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf renderWhenReadyUntil:deadline generation:generation];
    });
}

- (void)parseAndRenderWithMaxDelay:(NSTimeInterval)maxDelay
{
    if (![NSThread isMainThread])
    {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf parseAndRenderWithMaxDelay:maxDelay];
        });
        return;
    }
    NSUInteger generation = ++self.renderGeneration;
    NSString *markdown = [[self.dataSource rendererMarkdown:self] copy];
    NSDictionary *options = [self parseOptions];
    [self.parseQueue cancelAllOperations];
    __weak typeof(self) weakSelf = self;
    NSBlockOperation *operation = [[NSBlockOperation alloc] init];
    __weak NSBlockOperation *weakOperation = operation;
    [operation addExecutionBlock:^{
        NSBlockOperation *runningOperation = weakOperation;
        MPRenderer *renderer = weakSelf;
        if (!renderer || runningOperation.cancelled)
            return;
        NSDictionary *result = [renderer parseResultForMarkdown:markdown options:options];
        if (runningOperation.cancelled)
            return;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(0, maxDelay)];
        dispatch_async(dispatch_get_main_queue(), ^{
            MPRenderer *currentRenderer = weakSelf;
            if (!currentRenderer || generation != currentRenderer.renderGeneration)
                return;
            [currentRenderer publishParseResult:result options:options];
            [currentRenderer renderWhenReadyUntil:deadline generation:generation];
        });
    }];
    [self.parseQueue addOperation:operation];
}

- (void)parseAndRenderNow
{
    [self parseAndRenderWithMaxDelay:0];
}

- (void)parseAndRenderLater
{
    [self parseAndRenderWithMaxDelay:0.5];
}

- (void)parseIfPreferencesChanged
{
    id<MPRendererDelegate> delegate = self.delegate;
    if ([delegate rendererExtensions:self] != self.extensions
            || [delegate rendererHasSmartyPants:self] != self.smartypants
            || [delegate rendererRendersTOC:self] != self.TOC
            || [delegate rendererDetectsFrontMatter:self] != self.frontMatter)
    {
        [self parseAndRenderNow];
    }
}

- (NSDictionary *)parseOptions
{
    id<MPRendererDelegate> delegate = self.delegate;
    return @{@"extensions": @([delegate rendererExtensions:self]),
             @"smartypants": @([delegate rendererHasSmartyPants:self]),
             @"frontMatter": @([delegate rendererDetectsFrontMatter:self]),
             @"toc": @([delegate rendererRendersTOC:self]),
             @"flags": @(self.rendererFlags)};
}

- (NSDictionary *)parseResultForMarkdown:(NSString *)markdown options:(NSDictionary *)options
{
    NSString *sourceMarkdown = markdown ?: @"";
    NSMutableArray *languages = [NSMutableArray array];
    NSMutableArray *checkboxOffsets = [NSMutableArray array];
    NSMutableArray *calloutEntries = [NSMutableArray array];
    __attribute__((objc_precise_lifetime)) NSDictionary *context = @{@"languages": languages, @"checkboxOffsets": checkboxOffsets,
        @"headingSlugs": [NSMutableDictionary dictionary], @"calloutEntries":calloutEntries,
        @"sourceMarkdown":sourceMarkdown};
    __attribute__((objc_precise_lifetime)) NSDictionary *tocContext = @{@"headingSlugs": [NSMutableDictionary dictionary]};
    NSUInteger sourceOffset = 0;
    if ([options[@"frontMatter"] boolValue])
    {
        NSUInteger offset = 0;
        [markdown frontMatter:&offset];
        markdown = [markdown substringFromIndex:offset];
        sourceOffset = offset;
    }
    BOOL hasTOC = [options[@"toc"] boolValue];
    hoedown_renderer *htmlRenderer = MPCreateHTMLRenderer(
        [options[@"flags"] intValue], hasTOC ? kMPRendererTOCLevel : 0, context);
    hoedown_renderer *tocRenderer = hasTOC ? MPCreateHTMLTOCRenderer(tocContext) : NULL;
    NSString *html = MPHTMLFromMarkdown(markdown, [options[@"extensions"] intValue],
        [options[@"smartypants"] boolValue], nil, sourceOffset, htmlRenderer, tocRenderer);
    if (tocRenderer)
        MPFreeHTMLRenderer(tocRenderer);
    MPFreeHTMLRenderer(htmlRenderer);
    return @{@"html": html ?: @"", @"languages": [languages copy],
             @"checkboxOffsets": [checkboxOffsets copy], @"sourceMarkdown": sourceMarkdown,
             @"calloutEntries": [calloutEntries copy],
             @"checkboxToken": NSUUID.UUID.UUIDString};
}

- (NSString *)HTMLForMarkdownSnapshot:(NSString *)markdown
{
    NSDictionary *result = [self parseResultForMarkdown:markdown options:[self parseOptions]];
    NSString *html = result[@"html"];
    // Snapshot HTML is the semantic oracle for source transactions. Its own
    // per-parse transport identities vary on every parse and must not enter
    // that comparison. Keep authored attributes and the published live page
    // intact; only these proven, newly generated identities are removed.
    for (NSDictionary *entry in result[@"calloutEntries"]) {
        NSString *attribute = [NSString stringWithFormat:@" data-macdown-callout-token=\"%@\"",entry[@"token"]];
        html = [html stringByReplacingOccurrencesOfString:attribute withString:@""];
    }
    return html;
}

- (NSArray<NSDictionary *> *)calloutSourceEntriesForMarkdownSnapshot:(NSString *)markdown
{
    return [self parseResultForMarkdown:markdown options:[self parseOptions]][@"calloutEntries"];
}

- (void)publishParseResult:(NSDictionary *)result options:(NSDictionary *)options
{
    self.currentHtml = result[@"html"];
    self.checkboxSourceOffsets = result[@"checkboxOffsets"];
    self.checkboxSourceMarkdown = result[@"sourceMarkdown"];
    self.calloutSourceEntries = result[@"calloutEntries"];
    self.checkboxBridgeToken = result[@"checkboxToken"];
    self.currentLanguages = [result[@"languages"] mutableCopy];
    self.extensions = [options[@"extensions"] intValue];
    self.smartypants = [options[@"smartypants"] boolValue];
    self.TOC = [options[@"toc"] boolValue];
    self.frontMatter = [options[@"frontMatter"] boolValue];
}

// Synchronous entry used by headless callers; asynchronous requests use the
// same pure parse pipeline and publish their snapshots on the main queue.
- (void)parseMarkdown:(NSString *)markdown
{
    ++self.renderGeneration;
    [self.parseQueue cancelAllOperations];
    NSDictionary *options = [self parseOptions];
    [self publishParseResult:[self parseResultForMarkdown:markdown options:options]
                    options:options];
}

- (BOOL)delegateWrapsCodeBlocks
{
    return [self.delegate respondsToSelector:@selector(rendererWrapsCodeBlocks:)] &&
        [self.delegate rendererWrapsCodeBlocks:self];
}

- (void)renderIfPreferencesChanged
{
    BOOL changed = NO;
    id<MPRendererDelegate> d = self.delegate;
    if ([self delegateWrapsCodeBlocks] != self.wrapsCodeBlocks)
        changed = YES;
    else if ([d rendererHasSyntaxHighlighting:self] != self.syntaxHighlighting)
        changed = YES;
    else if ([d rendererHasMermaid:self] != self.mermaid)
        changed = YES;
    else if ([d rendererHasGraphviz:self] != self.graphviz)
        changed = YES;
    else if ([d rendererHasMathJax:self] != self.mathJax)
        changed = YES;
    else if (!MPAreNilableStringsEqual(
            [d rendererHighlightingThemeName:self], self.highlightingThemeName))
        changed = YES;
    else if (!MPAreNilableStringsEqual(
            [d rendererStyleName:self], self.styleName))
        changed = YES;
    else if ([d rendererCodeBlockAccesory:self] != self.codeBlockAccesory)
        changed = YES;

    if (changed)
        [self render];
}

- (void)render
{
    id<MPRendererDelegate> delegate = self.delegate;

    NSString *body = self.currentHtml;
    NSString *previewBody = body ?: @"";

    NSString *title = [self.dataSource rendererHTMLTitle:self];
    if (!self.checkboxBridgeToken.length)
        self.checkboxBridgeToken = NSUUID.UUID.UUIDString;
    NSString *headTags = [MPPreviewHeadTags(self.checkboxBridgeToken) stringByAppendingString:MPTaskListStyleTag()];
    if ([self delegateWrapsCodeBlocks])
        headTags = [headTags stringByAppendingString:MPCodeWrappingStyleTag()];
    NSString *html = MPGetHTML(
        title, headTags, previewBody,
        self.stylesheets, MPAssetFullLink,
        self.scripts, MPAssetFullLink);

    // Issue #110 / #318: Apply cache-busting version stamps to local resource
    // URLs. Run this over the full document — not just the <body> — so that
    // edited style/theme CSS <link> tags in <head> also get a fresh URL that
    // the legacy WebView cannot serve from its by-URL resource cache. Only
    // paths with a recorded timestamp are stamped; bundled CSS and other
    // untracked resources pass through unchanged.
    if (self.resourceTimestamps.count > 0)
    {
        NSURL *baseURL = nil;
        if ([delegate respondsToSelector:@selector(rendererBaseURL:)])
            baseURL = [delegate rendererBaseURL:self];
        if (baseURL)
            html = MPApplyCacheBusting(html, self.resourceTimestamps, baseURL);
    }

    [delegate renderer:self didProduceHTMLOutput:html];

    self.styleName = [delegate rendererStyleName:self];
    self.syntaxHighlighting = [delegate rendererHasSyntaxHighlighting:self];
    self.wrapsCodeBlocks = [self delegateWrapsCodeBlocks];
    self.mermaid = [delegate rendererHasMermaid:self];
    self.graphviz = [delegate rendererHasGraphviz:self];
    self.mathJax = [delegate rendererHasMathJax:self];
    self.highlightingThemeName = [delegate rendererHighlightingThemeName:self];
    self.codeBlockAccesory = [delegate rendererCodeBlockAccesory:self];
}

#pragma mark - Resource Cache-Busting (Issue #110)

- (void)setTimestamp:(NSTimeInterval)timestamp forResourcePath:(NSString *)path
{
    if (path)
        self.resourceTimestamps[path] = @(timestamp);
}

- (void)clearResourceTimestamps
{
    [self.resourceTimestamps removeAllObjects];
}

- (NSString *)HTMLForExportWithStyles:(BOOL)withStyles
                         highlighting:(BOOL)withHighlighting
{
    MPAssetOption stylesOption = MPAssetNone;
    MPAssetOption scriptsOption = MPAssetNone;
    NSMutableArray *styles = [NSMutableArray array];
    NSMutableArray *scripts = [NSMutableArray array];

    if (withStyles)
    {
        stylesOption = MPAssetEmbedded;
        [styles addObjectsFromArray:self.baseStylesheets];
    }
    if (withHighlighting)
    {
        stylesOption = MPAssetEmbedded;
        scriptsOption = MPAssetEmbedded;
        [styles addObjectsFromArray:self.prismStylesheets];
        [scripts addObjectsFromArray:self.prismScripts];
    }
    // Mermaid and Graphviz render from the language-* class (always
    // emitted) via their own init scripts; they do not depend on Prism.
    // Keep them out of the highlighting gate so diagrams export even
    // when syntax highlighting is off (GitHub issue #541).
    if ([self.delegate rendererHasMermaid:self])
    {
        scriptsOption = MPAssetEmbedded;
        [scripts addObjectsFromArray:self.mermaidScripts];
    }
    if ([self.delegate rendererHasGraphviz:self])
    {
        scriptsOption = MPAssetEmbedded;
        [scripts addObjectsFromArray:self.graphvizScripts];
    }
    if ([self.delegate rendererHasMathJax:self])
    {
        scriptsOption = MPAssetEmbedded;
        [scripts addObjectsFromArray:self.mathjaxScripts];
    }

    // Add export.css LAST for paragraph text wrapping in HTML exports
    // Must be after all other stylesheets to ensure proper cascade order
    if (withStyles)
    {
        NSURL *exportURL = MPExtensionURL(@"export", @"css");
        [styles addObject:[MPStyleSheet CSSWithURL:exportURL]];
    }

    NSString *title = [self.dataSource rendererHTMLTitle:self];
    if (!title)
        title = @"";
    NSString *html = MPGetHTML(
        title, [MPTaskListStyleTag() stringByAppendingString:
            withStyles && [self delegateWrapsCodeBlocks] ? MPCodeWrappingStyleTag() : @""],
        self.currentHtml, styles, stylesOption, scripts,
        scriptsOption);
    return html;
}

@end
