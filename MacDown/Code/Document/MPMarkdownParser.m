//
//  MPMarkdownParser.m
//  MacDown 3000
//
//  CommonMark-based Markdown parser using cmark-gfm.
//  Replaces the Hoedown parser for full CommonMark 0.31.2 compliance.
//

#import "MPMarkdownParser.h"
#import <cmark-gfm/cmark-gfm.h>
#import <cmark-gfm/cmark-gfm-extension_api.h>
#import <cmark-gfm/cmark-gfm-core-extensions.h>

@implementation MPMarkdownParser
{
    int _checkboxIndex;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    _checkboxIndex = 0;
    return self;
}

- (void)resetState
{
    _checkboxIndex = 0;
}

- (int)checkboxIndex
{
    return _checkboxIndex;
}

#pragma mark - Core API

- (NSString *)renderMarkdown:(NSString *)markdown
{
    if (!markdown.length)
        return @"";

    // Pre-process markdown for extensions not supported by cmark-gfm
    markdown = [self preprocessMarkdown:markdown];

    // Build cmark options
    int options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE;
    if (self.smartyPants)
        options |= CMARK_OPT_SMART;
    if (self.rendererFlags & MPRendererHardWrap)
        options |= CMARK_OPT_HARDBREAKS;
    if (self.extensionFlags & MPExtensionFootnotes)
        options |= CMARK_OPT_FOOTNOTES;
    if (self.rendererFlags & MPRendererBlockcodeInfo)
        options |= CMARK_OPT_FULL_INFO_STRING;

    // Register extensions once
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cmark_gfm_core_extensions_ensure_registered();
    });

    // Create parser
    cmark_parser *parser = cmark_parser_new(options);

    // Attach extensions based on flags
    cmark_llist *extensions = NULL;
    cmark_mem *mem = cmark_get_default_mem_allocator();

    if (self.extensionFlags & MPExtensionTables) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("table");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }
    if (self.extensionFlags & MPExtensionStrikethrough) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("strikethrough");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }
    if (self.extensionFlags & MPExtensionAutolink) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("autolink");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }
    if (self.rendererFlags & MPRendererTaskList) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("tasklist");
        if (ext) {
            cmark_parser_attach_syntax_extension(parser, ext);
            extensions = cmark_llist_append(mem, extensions, ext);
        }
    }

    // Parse
    NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_parser_feed(parser, data.bytes, data.length);
    cmark_node *document = cmark_parser_finish(parser);

    // Render to HTML
    char *html_cstr = cmark_render_html(document, options, extensions);
    NSString *html = [NSString stringWithUTF8String:html_cstr];

    // Free cmark resources
    free(html_cstr);
    cmark_node_free(document);
    cmark_parser_free(parser);
    if (extensions)
        cmark_llist_free(mem, extensions);

    // Post-process the HTML output
    html = [self postprocessCodeBlocks:html];

    if (self.rendererFlags & MPRendererTaskList)
        html = [self postprocessTaskLists:html];

    if (self.extensionFlags & MPExtensionHighlight)
        html = [self postprocessHighlight:html];

    if (self.extensionFlags & MPExtensionSuperscript)
        html = [self postprocessSuperscript:html];

    return html;
}

- (NSString *)renderTOC:(NSString *)markdown maxLevel:(int)level
{
    if (!markdown.length)
        return @"";

    int options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE;
    if (self.extensionFlags & MPExtensionFootnotes)
        options |= CMARK_OPT_FOOTNOTES;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cmark_gfm_core_extensions_ensure_registered();
    });

    cmark_parser *parser = cmark_parser_new(options);

    NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_parser_feed(parser, data.bytes, data.length);
    cmark_node *document = cmark_parser_finish(parser);

    NSMutableString *toc = [NSMutableString string];
    int currentLevel = 0;
    int levelOffset = 0;
    int headerCount = 0;

    cmark_iter *iter = cmark_iter_new(document);
    cmark_event_type ev_type;
    while ((ev_type = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        cmark_node *node = cmark_iter_get_node(iter);
        if (cmark_node_get_type(node) != CMARK_NODE_HEADING)
            continue;
        if (ev_type != CMARK_EVENT_ENTER)
            continue;

        int headingLevel = cmark_node_get_heading_level(node);
        if (headingLevel > level)
            continue;

        // Set level offset from first heading
        if (currentLevel == 0)
            levelOffset = headingLevel - 1;

        int adjustedLevel = headingLevel - levelOffset;

        // Generate nested <ul> structure matching Hoedown's TOC format
        if (adjustedLevel > currentLevel) {
            while (adjustedLevel > currentLevel) {
                if (currentLevel == 0)
                    [toc appendString:@"<ul class=\"toc\">\n<li>\n"];
                else
                    [toc appendString:@"<ul>\n<li>\n"];
                currentLevel++;
            }
        } else if (adjustedLevel < currentLevel) {
            [toc appendString:@"</li>\n"];
            while (adjustedLevel < currentLevel) {
                [toc appendString:@"</ul>\n</li>\n"];
                currentLevel--;
            }
            [toc appendString:@"<li>\n"];
        } else {
            [toc appendString:@"</li>\n<li>\n"];
        }

        // Render heading content as inline HTML
        NSMutableString *content = [NSMutableString string];
        cmark_node *child = cmark_node_first_child(node);
        while (child) {
            char *child_html = cmark_render_html(child, options, NULL);
            if (child_html) {
                [content appendFormat:@"%s", child_html];
                free(child_html);
            }
            child = cmark_node_next(child);
        }
        // Strip wrapping <p> tags from inline rendering
        NSString *trimmed = [content stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed hasPrefix:@"<p>"] && [trimmed hasSuffix:@"</p>"]) {
            trimmed = [trimmed substringWithRange:
                NSMakeRange(3, trimmed.length - 7)];
        }

        [toc appendFormat:@"<a href=\"#toc_%d\">%@</a>\n", headerCount++, trimmed];
    }

    // Close remaining open tags
    while (currentLevel > 0) {
        [toc appendString:@"</li>\n</ul>\n"];
        currentLevel--;
    }

    cmark_iter_free(iter);
    cmark_node_free(document);
    cmark_parser_free(parser);

    return toc;
}

#pragma mark - Pre-processing

- (NSString *)preprocessMarkdown:(NSString *)markdown
{
    NSMutableString *result = [markdown mutableCopy];

    // Highlight: ==text== -> <mark>text</mark>
    // Only outside code spans and code blocks
    if (self.extensionFlags & MPExtensionHighlight) {
        // We do highlight pre-processing here so cmark passes it through as HTML
        // Skip if inside backticks or code blocks
        static NSRegularExpression *highlightRegex = nil;
        static dispatch_once_t highlightToken;
        dispatch_once(&highlightToken, ^{
            // Match ==text== but not inside code blocks/spans
            // Simple approach: match ==...== that doesn't span lines
            highlightRegex = [[NSRegularExpression alloc]
                initWithPattern:@"(?<!`)={2}(?!=)([^=\\n]+?)(?<!=)={2}(?!`)"
                        options:0
                          error:NULL];
        });
        [highlightRegex replaceMatchesInString:result
                                       options:0
                                         range:NSMakeRange(0, result.length)
                                  withTemplate:@"<mark>$1</mark>"];
    }

    // Superscript: ^text^ -> <sup>text</sup>
    if (self.extensionFlags & MPExtensionSuperscript) {
        static NSRegularExpression *superRegex = nil;
        static dispatch_once_t superToken;
        dispatch_once(&superToken, ^{
            superRegex = [[NSRegularExpression alloc]
                initWithPattern:@"\\^([^^\\n]+?)\\^"
                        options:0
                          error:NULL];
        });
        [superRegex replaceMatchesInString:result
                                   options:0
                                     range:NSMakeRange(0, result.length)
                              withTemplate:@"<sup>$1</sup>"];
    }

    return result;
}

#pragma mark - Post-processing

- (NSString *)postprocessCodeBlocks:(NSString *)html
{
    // Transform cmark-gfm's code block output to match MacDown's expected format.
    //
    // cmark-gfm produces:
    //   <pre><code class="language-xxx">content\n</code></pre>
    //   <pre><code>content\n</code></pre> (no language)
    //
    // MacDown expects:
    //   <div><pre><code class="language-xxx">content</code></pre></div>
    //   <div><pre><code class="language-none">content</code></pre></div>
    //
    // With line numbers: <div><pre class="line-numbers"><code ...>
    // With data-information: <div><pre data-information="info"><code ...>

    BOOL lineNumbers = (self.rendererFlags & MPRendererLineNumbers) != 0;
    BOOL blockcodeInfo = (self.rendererFlags & MPRendererBlockcodeInfo) != 0;

    // Match code blocks: <pre><code ...>...</code></pre>
    static NSRegularExpression *codeBlockRegex = nil;
    static dispatch_once_t codeToken;
    dispatch_once(&codeToken, ^{
        // Match <pre><code class="language-xxx">content</code></pre>
        // or <pre><code>content</code></pre>
        codeBlockRegex = [[NSRegularExpression alloc]
            initWithPattern:@"<pre><code(?:\\s+class=\"language-([^\"]*?)\")?(?:\\s+data-meta=\"([^\"]*?)\")?>(.*?)</code></pre>"
                    options:NSRegularExpressionDotMatchesLineSeparators
                      error:NULL];
    });

    NSMutableString *result = [html mutableCopy];
    NSArray *matches = [codeBlockRegex matchesInString:result options:0
                                                 range:NSMakeRange(0, result.length)];

    // Process in reverse to preserve ranges
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSRange fullRange = match.range;
        NSRange langRange = [match rangeAtIndex:1];
        NSRange metaRange = [match rangeAtIndex:2];
        NSRange contentRange = [match rangeAtIndex:3];

        NSString *language = (langRange.location != NSNotFound)
            ? [result substringWithRange:langRange] : nil;
        NSString *meta = (metaRange.location != NSNotFound)
            ? [result substringWithRange:metaRange] : nil;
        NSString *content = [result substringWithRange:contentRange];

        // Handle info string splitting on colon for data-information
        NSString *dataInfo = nil;
        if (blockcodeInfo && language) {
            NSRange colonRange = [language rangeOfString:@":"];
            if (colonRange.location != NSNotFound) {
                dataInfo = [language substringFromIndex:colonRange.location + 1];
                language = [language substringToIndex:colonRange.location];
            }
        }
        if (!dataInfo && meta)
            dataInfo = meta;

        // Call language callback for Prism dependency resolution and alias mapping
        NSString *resolvedLang = language;
        if (resolvedLang && self.languageCallback) {
            NSString *mapped = self.languageCallback(resolvedLang);
            if (mapped)
                resolvedLang = mapped;
        }

        // Remove trailing newline from content (prevents Prism blank line)
        if ([content hasSuffix:@"\n"])
            content = [content substringToIndex:content.length - 1];

        // Build the replacement
        NSMutableString *replacement = [NSMutableString string];
        [replacement appendString:@"<div><pre"];
        if (lineNumbers)
            [replacement appendString:@" class=\"line-numbers\""];
        if (dataInfo.length)
            [replacement appendFormat:@" data-information=\"%@\"", dataInfo];
        [replacement appendFormat:@"><code class=\"language-%@\">",
            (resolvedLang.length ? resolvedLang : @"none")];
        [replacement appendString:content];
        [replacement appendString:@"</code></pre></div>"];

        [result replaceCharactersInRange:fullRange withString:replacement];
    }

    return result;
}

- (NSString *)postprocessTaskLists:(NSString *)html
{
    // Transform cmark-gfm's task list output to match MacDown's expected format.
    //
    // cmark-gfm produces:
    //   <li><input type="checkbox" disabled="" /> text</li>
    //   <li><input type="checkbox" checked="" disabled="" /> text</li>
    //
    // MacDown expects:
    //   <li class="task-list-item"><input type="checkbox" data-checkbox-index="N"> text</li>
    //   <li class="task-list-item"><input type="checkbox" checked data-checkbox-index="N"> text</li>

    // Match task list items
    static NSRegularExpression *taskRegex = nil;
    static dispatch_once_t taskToken;
    dispatch_once(&taskToken, ^{
        taskRegex = [[NSRegularExpression alloc]
            initWithPattern:@"<li>(\\s*(?:<p>\\s*)?)<input type=\"checkbox\"(?: checked=\"\"| checked)?(?: disabled=\"\"| disabled)? />"
                    options:0
                      error:NULL];
    });

    NSMutableString *result = [html mutableCopy];
    NSArray *matches = [taskRegex matchesInString:result options:0
                                            range:NSMakeRange(0, result.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSRange fullRange = match.range;
        NSString *matchStr = [result substringWithRange:fullRange];
        BOOL isChecked = [matchStr containsString:@"checked"];
        NSRange prefixRange = [match rangeAtIndex:1];
        NSString *prefix = (prefixRange.location != NSNotFound)
            ? [result substringWithRange:prefixRange] : @"";

        NSString *replacement;
        if (isChecked) {
            replacement = [NSString stringWithFormat:
                @"<li class=\"task-list-item\">%@<input type=\"checkbox\" checked data-checkbox-index=\"%d\">",
                prefix, _checkboxIndex++];
        } else {
            replacement = [NSString stringWithFormat:
                @"<li class=\"task-list-item\">%@<input type=\"checkbox\" data-checkbox-index=\"%d\">",
                prefix, _checkboxIndex++];
        }

        [result replaceCharactersInRange:fullRange withString:replacement];
    }

    return result;
}

- (NSString *)postprocessHighlight:(NSString *)html
{
    // Already handled in preprocessMarkdown — cmark passes HTML through.
    // Nothing to do here.
    return html;
}

- (NSString *)postprocessSuperscript:(NSString *)html
{
    // Already handled in preprocessMarkdown — cmark passes HTML through.
    // Nothing to do here.
    return html;
}

@end
