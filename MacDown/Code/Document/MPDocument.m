//
//  MPDocument.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPDocument.h"
#import <WebKit/WebKit.h>
#import <CommonCrypto/CommonDigest.h>
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
#import "MPPreviewInlineTransaction.h"
#import "../../../MacDownCore/MPMarkdownPreprocessor.h"
#import "MPURLSecurityPolicy.h"
#import "MPFolderSidebarViewController.h"
#import "MPSidebarSplitView.h"
#import "MPSidebarSyncCoordinator.h"
#import <JavaScriptCore/JavaScriptCore.h>
// Issue #504: PDF export post-processing (clickable internal anchor links).
#import <PDFKit/PDFKit.h>
#import "MPPDFAnchorInjector.h"

// Compare original bytes, before CRLF normalization, without retaining a second
// copy of the document. Chunking avoids truncating NSData.length to CC_LONG.
static NSData *MPDocumentContentFingerprint(NSData *data)
{
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    const unsigned char *bytes = data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        CC_LONG count = (CC_LONG)MIN(data.length - offset, (NSUInteger)(1024 * 1024));
        CC_SHA256_Update(&context, bytes + offset, count);
        offset += count;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static NSString *MPNormalizePreviewSelectionText(NSString *text)
{
    NSString *normalized=[[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSRegularExpression *newlines=[NSRegularExpression regularExpressionWithPattern:@"\n+" options:0 error:NULL];
    return [newlines stringByReplacingMatchesInString:normalized options:0 range:NSMakeRange(0,normalized.length) withTemplate:@"\n"];
}

// Keep Markdown delimiter flanking intact: probe markers belong inside the
// literal's edge whitespace, not between that whitespace and adjacent syntax.
static NSString *MPPreviewMarkedLiteral(NSString *text,NSString *marker)
{
    NSCharacterSet *content=[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n\f\v"].invertedSet;
    NSRange first=[text rangeOfCharacterFromSet:content];
    if (first.location==NSNotFound) return [NSString stringWithFormat:@"%@%@%@",marker,text,marker];
    NSRange last=[text rangeOfCharacterFromSet:content options:NSBackwardsSearch];
    NSUInteger end=NSMaxRange(last);
    return [NSString stringWithFormat:@"%@%@%@%@%@",[text substringToIndex:first.location],marker,
        [text substringWithRange:NSMakeRange(first.location,end-first.location)],marker,[text substringFromIndex:end]];
}

static NSString *MPPreviewSourceSeparators(NSString *source,NSUInteger start,NSUInteger end)
{
    NSMutableString *separators=[NSMutableString string];
    for (NSUInteger i=start;i<end;i++) {
        unichar character=[source characterAtIndex:i];
        if (character=='\n' || character=='\r') [separators appendFormat:@"%C",character];
    }
    return separators;
}

// One source grammar owns the separator after a Markdown task checkbox.
static NSRange MPPreviewTaskSeparatorRange(NSString *source,NSUInteger position)
{
    if(position>source.length) return NSMakeRange(NSNotFound,0);
    NSRange line=[source lineRangeForRange:NSMakeRange(position,0)];
    NSString *raw=[source substringWithRange:line];
    static NSRegularExpression *task;
    static dispatch_once_t once;
    dispatch_once(&once,^{task=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}(?:>[ \\t]?)*[-+*][ \\t]+\\[[ xX]\\]([ \\t]+)" options:0 error:NULL];});
    NSTextCheckingResult *prefix=[task firstMatchInString:raw options:0 range:NSMakeRange(0,raw.length)];
    if(!prefix) return NSMakeRange(NSNotFound,0);
    NSRange separator=[prefix rangeAtIndex:1];separator.location+=line.location;return separator;
}

static NSString * const kMPDefaultAutosaveName = @"Untitled";

// Issue #543: Window over which vnode write notifications for the document's
// own file are collapsed into a single reload decision. External editors
// commonly write a file in several chunks, and each write arrives separately.
static const NSTimeInterval kMPExternalChangeCoalesceInterval = 0.25;

// CSSOM changes do not appear in outerHTML; include stylesheet rules in the
// print snapshot so asynchronous page scripts cannot silently change a pass.
static NSString * const kMPPDFSnapshotJS = @"(function(){var sheets=[];for(var i=0;i<document.styleSheets.length;i++){var sheet=document.styleSheets[i];try{sheets.push(Array.prototype.map.call(sheet.cssRules,function(r){return r.cssText}).join('\\n'));}catch(e){sheets.push(null);}}return JSON.stringify([document.documentElement.outerHTML,sheets]);})()";

static NSString * const kMPPreparePDFAnchorsJS = @"(function(args) {\n"
    "  var session = {links:[], headings:[], attributes:[], markers:[], rules:[], generated:[]};\n"
    "  function restore() {\n"
    "    for (var i = session.generated.length - 1; i >= 0; i--) {\n"
    "      var item = session.generated[i], rules = item.parent.cssRules;\n"
    "      for (var j = rules.length - 1; j >= 0; j--)\n"
    "        if (rules[j] === item.rule) { item.parent.deleteRule(j); break; }\n"
    "    }\n"
    "    for (var i = session.rules.length - 1; i >= 0; i--)\n"
    "      session.rules[i].rule.selectorText = session.rules[i].value;\n"
    "    for (var i = session.markers.length - 1; i >= 0; i--) {\n"
    "      var marker = session.markers[i];\n"
    "      if (marker.parentNode) marker.parentNode.removeChild(marker);\n"
    "    }\n"
    "    for (var i = session.attributes.length - 1; i >= 0; i--) {\n"
    "      var item = session.attributes[i];\n"
    "      if (item.value === null) item.node.removeAttribute(item.name);\n"
    "      else item.node.setAttribute(item.name, item.value);\n"
    "    }\n"
    "    delete window[args.key];\n"
    "  }\n"
    "  session.restore = restore;\n"
    "  window[args.key] = session;\n"
    "  try {\n"
    "    var links = document.querySelectorAll('a[href^=\"#\"]');\n"
    "    var headings = document.querySelectorAll('h1[id],h2[id],h3[id],h4[id],h5[id],h6[id]');\n"
    "    var nodes = Array.prototype.slice.call(document.querySelectorAll('*'));\n"
    "    var rules = [], affected = [], originalHrefs = [];\n"
    "    var attribute = 'data-macdown-pdf-' + args.key.toLowerCase();\n"
    "    function affect(node) {\n"
    "      if (nodes.indexOf(node) !== -1 && affected.indexOf(node) === -1) affected.push(node);\n"
    "    }\n"
    "    // Split selector lists without splitting commas inside functions/attributes.\n"
    "    function selectors(text) {\n"
    "      var result = [], start = 0, depth = 0, quote = '';\n"
    "      for (var i = 0; i < text.length; i++) {\n"
    "        var c = text.charAt(i);\n"
    "        if (c === '\\\\') { i++; continue; }\n"
    "        if (quote) { if (c === quote) quote = ''; continue; }\n"
    "        if (c === '\"' || c === \"'\") { quote = c; continue; }\n"
    "        if (c === '(' || c === '[') depth++;\n"
    "        else if (c === ')' || c === ']') depth--;\n"
    "        else if (c === ',' && depth === 0) { result.push(text.slice(start, i).trim()); start = i + 1; }\n"
    "      }\n"
    "      result.push(text.slice(start).trim()); return result;\n"
    "    }\n"
    "    function collect(parent) {\n"
    "      var list = parent.cssRules;\n"
    "      for (var i = 0; i < list.length; i++) {\n"
    "        var rule = list[i];\n"
    "        if (rule.type === 1) {\n"
    "          var parts = selectors(rule.selectorText), components = [];\n"
    "          for (var j = 0; j < parts.length; j++) {\n"
    "            var pseudo = parts[j].match(/(::?(?:before|after|first-letter|first-line|selection|marker))$/i);\n"
    "            var tail = pseudo ? pseudo[0] : '', base = parts[j].slice(0, parts[j].length - tail.length);\n"
    "            components.push({base:base, tail:tail, before:Array.prototype.slice.call(document.querySelectorAll(base))});\n"
    "          }\n"
    "          rules.push({rule:rule, parent:parent, components:components});\n"
    "        } else if (rule.type === 3 && rule.styleSheet) collect(rule.styleSheet);\n"
    "        else if (rule.cssRules) collect(rule);\n"
    "      }\n"
    "    }\n"
    "    for (var i = 0; i < document.styleSheets.length; i++) collect(document.styleSheets[i]);\n"
    "    for (var i = 0; i < links.length; i++) {\n"
    "      var link = links[i], href = link.getAttribute('href'), target = href.slice(1);\n"
    "      if (!target) continue;\n"
    "      try { target = decodeURIComponent(target); } catch (e) {}\n"
    "      originalHrefs.push({node:link, href:href}); affect(link);\n"
    "      session.attributes.push({node:link, name:'href', value:href});\n"
    "      link.setAttribute('href', args.prefix + 'link/' + session.links.length);\n"
    "      session.links.push(target);\n"
    "    }\n"
    "    for (var i = 0; i < headings.length; i++) {\n"
    "      var heading = headings[i];\n"
    "      if (!heading.id) continue;\n"
    "      var marker = document.createElement('a');\n"
    "      marker.setAttribute('href', args.prefix + 'heading/' + session.headings.length);\n"
    "      marker.setAttribute('aria-hidden', 'true');\n"
    "      marker.setAttribute(attribute, 'marker');\n"
    "      marker.setAttribute('style', 'all:initial!important;position:absolute!important;left:auto!important;top:auto!important;width:1px!important;height:1px!important;display:block!important;border:0!important;padding:0!important;margin:0!important;background:transparent!important;pointer-events:none!important;');\n"
    "      session.markers.push(marker);\n"
    "      heading.insertBefore(marker, heading.firstChild);\n"
    "      session.headings.push(heading.id);\n"
    "    }\n"
    "    for (var i = 0; i < rules.length; i++) {\n"
    "      var components = rules[i].components;\n"
    "      for (var j = 0; j < components.length; j++) {\n"
    "        var component = components[j], before = component.before;\n"
    "        var after = Array.prototype.slice.call(document.querySelectorAll(component.base));\n"
    "        for (var k = 0; k < before.length; k++) if (after.indexOf(before[k]) === -1) affect(before[k]);\n"
    "        for (var k = 0; k < after.length; k++) if (before.indexOf(after[k]) === -1) affect(after[k]);\n"
    "      }\n"
    "    }\n"
    "    for (var i = 0; i < affected.length; i++) {\n"
    "      session.attributes.push({node:affected[i], name:attribute, value:affected[i].getAttribute(attribute)});\n"
    "      affected[i].setAttribute(attribute, String(i));\n"
    "    }\n"
    "    // Copy original selector membership, not computed pixel styles. The :where\n"
    "    // identity adds zero specificity; :is retains each original selector's\n"
    "    // specificity. Raw %, calc(), var(), media scopes and cascade order survive.\n"
    "    function preserveHref(text, href) {\n"
    "      var result = '', quote = '';\n"
    "      for (var i = 0; i < text.length; i++) {\n"
    "        var c = text.charAt(i);\n"
    "        if (c === '\\\\') { result += c + text.charAt(++i); continue; }\n"
    "        if (quote) { result += c; if (c === quote) quote = ''; continue; }\n"
    "        if (c === '\"' || c === \"'\") { quote = c; result += c; continue; }\n"
    "        var match = text.slice(i).match(/^attr\\(\\s*href\\s*\\)/i);\n"
    "        if (match) { result += JSON.stringify(href).replace(/\\\\n/g, '\\\\a ').replace(/\\\\r/g, '\\\\d '); i += match[0].length - 1; }\n"
    "        else result += c;\n"
    "      }\n"
    "      return result;\n"
    "    }\n"
    "    for (var i = 0; i < rules.length; i++) {\n"
    "      var item = rules[i], rule = item.rule, components = item.components, excluded = [];\n"
    "      var originalStyle = rule.style.cssText;\n"
    "      session.rules.push({rule:rule, value:rule.selectorText});\n"
    "      for (var j = 0; j < components.length; j++) {\n"
    "        var component = components[j];\n"
    "        excluded.push(component.base + ':not(:where([' + attribute + ']))' + component.tail);\n"
    "      }\n"
    "      rule.selectorText = excluded.join(',');\n"
    "      var index = 0;\n"
    "      while (item.parent.cssRules[index] !== rule) index++;\n"
    "      for (var j = 0; j < components.length; j++) {\n"
    "        var component = components[j];\n"
    "        for (var k = 0; k < component.before.length; k++) {\n"
    "          var node = component.before[k], id = affected.indexOf(node);\n"
    "          if (id === -1) continue;\n"
    "          var identity = '[' + attribute + '=\"' + id + '\"]';\n"
    "          var selector = ':is(' + component.base + ',:where(' + identity + ')):where(' + identity + ')' + component.tail;\n"
    "          var style = originalStyle;\n"
    "          for (var h = 0; h < originalHrefs.length; h++)\n"
    "            if (originalHrefs[h].node === node) style = preserveHref(style, originalHrefs[h].href);\n"
    "          item.parent.insertRule(selector + '{' + style + '}', ++index);\n"
    "          session.generated.push({parent:item.parent, rule:item.parent.cssRules[index]});\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "    return {links:session.links, headings:session.headings};\n"
    "  } catch (error) { restore(); throw error; }\n"
    "})\n";

static const CGFloat kMPMinZoom = 0.5;
static const CGFloat kMPMaxZoom = 3.0;

// The native renderer provides the only identities eligible for restoration.
// Authored <details>, even with the same callout classes, retain their own source
// defaults. Run this before typesetting and scroll geometry on either load path.
static NSString * const MPPreviewRestoreCalloutStateJavaScript =
    @"(function(){var states=window.__macdownCalloutStates;delete window.__macdownCalloutStates;"
    @"if(!states)return;var nodes=document.getElementsByTagName('details');"
    @"for(var i=0;i<nodes.length;i++){var token=nodes[i].getAttribute('data-macdown-callout-token');"
    @"if(token&&Object.prototype.hasOwnProperty.call(states,token))nodes[i].open=Boolean(states[token]);}})()";

static NSRange MPPreviewRemapCalloutOpening(NSDictionary *entry, NSString *before,
    NSString *after, NSUInteger prefix, NSUInteger suffix)
{
    NSRange opening = [entry[@"sourceOpenRange"] rangeValue];
    NSRange closing = [entry[@"sourceCloseRange"] rangeValue];
    if (!opening.length || opening.location > before.length ||
        opening.length > before.length - opening.location ||
        closing.location > before.length || closing.length > before.length - closing.location ||
        closing.location < NSMaxRange(opening)) return NSMakeRange(NSNotFound,0);
    if (NSMaxRange(opening) <= prefix) return opening;
    if (opening.location >= before.length - suffix) {
        opening.location = after.length - (before.length - opening.location);
        return opening;
    }
    // Removing an outer wrapper changes two distant delimiters. A nested
    // callout inside that edited span can still be identified by its entire
    // unchanged source, but only when that source has one possible occurrence.
    NSString *unchanged = [before substringWithRange:
        NSMakeRange(opening.location,NSMaxRange(closing)-opening.location)];
    NSRange match = [after rangeOfString:unchanged];
    if (match.location == NSNotFound) return NSMakeRange(NSNotFound,0);
    NSRange another = [after rangeOfString:unchanged options:0
        range:NSMakeRange(match.location+1,after.length-match.location-1)];
    if (another.location != NSNotFound) return NSMakeRange(NSNotFound,0);
    return NSMakeRange(match.location,opening.length);
}

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
            @"editorShowReadingProgress",
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


// The template emits Prism language components at the end of the body.
// Comparing only the head can retain a page that has no required grammar.
static NSString *MPPreviewResourceHTML(NSString *html)
{
    if (!html.length) return nil;
    NSRange end = [html rangeOfString:@"</head>"];
    if (end.location == NSNotFound) return nil;
    NSMutableString *resources = [[html substringToIndex:NSMaxRange(end)]
                                 mutableCopy];
    static NSRegularExpression *scripts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        scripts = [NSRegularExpression regularExpressionWithPattern:
            @"<script\\b[^>]*>.*?</script>"
            options:NSRegularExpressionCaseInsensitive |
                    NSRegularExpressionDotMatchesLineSeparators error:NULL];
    });
    for (NSTextCheckingResult *match in [scripts matchesInString:html
             options:0 range:NSMakeRange(0, html.length)])
        [resources appendString:[html substringWithRange:match.range]];
    return resources;
}

// The search field's field editor would otherwise consume Cmd-G/Cmd-F itself.
@interface MPPreviewFindPanel : NSPanel
@property (copy) void (^findActionHandler)(NSTextFinderAction);
@end

@implementation MPPreviewFindPanel
- (void)sendEvent:(NSEvent *)event
{
    // NSSearchField's field editor consumes Escape before the responder chain.
    if (event.type == NSEventTypeKeyDown && event.keyCode == 53)
        [self cancelOperation:nil];
    else
        [super sendEvent:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    NSEventModifierFlags flags = event.modifierFlags &
        NSEventModifierFlagDeviceIndependentFlagsMask;
    if ((flags & NSEventModifierFlagCommand) &&
        !(flags & (NSEventModifierFlagOption | NSEventModifierFlagControl)))
    {
        NSString *key = event.charactersIgnoringModifiers.lowercaseString;
        NSTextFinderAction action;
        if ([key isEqualToString:@"g"])
            action = flags & NSEventModifierFlagShift ?
                NSTextFinderActionPreviousMatch : NSTextFinderActionNextMatch;
        else if ([key isEqualToString:@"f"])
            action = NSTextFinderActionShowFindInterface;
        else if ([key isEqualToString:@"e"])
            action = NSTextFinderActionSetSearchString;
        else
            return [super performKeyEquivalent:event];
        if (self.findActionHandler) self.findActionHandler(action);
        return YES;
    }
    return [super performKeyEquivalent:event];
}
- (void)cancelOperation:(id)sender { [self orderOut:sender]; }
@end

@interface MPDocument ()
    <NSSplitViewDelegate, NSTextViewDelegate,
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
     WebEditingDelegate, WebFrameLoadDelegate, WebPolicyDelegate, WebResourceLoadDelegate, WebUIDelegate,
#endif
     MPAutosaving, MPRendererDataSource, MPRendererDelegate, MPResourceWatcherSetDelegate,
     MPFolderSidebarDelegate>
+ (NSString *)tableInsertionForContent:(NSString *)content selectedRange:(NSRange)selectedRange columns:(NSUInteger)columns rows:(NSUInteger)rows replacementRange:(NSRange *)replacement caretLocation:(NSUInteger *)caret;

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
//
// Density fix (long header-sparse sections drift out of sync): paragraphs and list
// items are also tracked as reference points, so no span between two reference points
// is ever very long, bounding the linear-interpolation error between them.
typedef NS_ENUM(NSInteger, MPReferenceKind) {
    MPReferenceKindImage     = 0,
    MPReferenceKindH1        = 1,
    MPReferenceKindH2        = 2,
    MPReferenceKindH3        = 3,
    MPReferenceKindH4        = 4,
    MPReferenceKindH5        = 5,
    MPReferenceKindH6        = 6,
    MPReferenceKindParagraph = 7,
    MPReferenceKindListItem  = 8,
};

@property (weak) IBOutlet NSToolbar *toolbar;
@property (weak) IBOutlet MPDocumentSplitView *splitView;
@property (weak) IBOutlet NSView *editorContainer;
// unsafe_unretained here (unlike every sibling IBOutlet above, all `weak`)
// dates back to the original 2014 project setup, predating this codebase's
// adoption of `weak` IBOutlets, and was never updated. A raw, non-zeroing
// pointer means that if the underlying MPEditorView is ever deallocated
// and recreated (e.g. during window/layout churn), `editor` keeps pointing
// at freed memory -- any later message to it (toggleForMarkupPrefix:suffix:,
// .selectedRange, .string, ...) is then a dangling-pointer access, i.e.
// EXC_BAD_ACCESS. `weak` makes the pointer nil itself out instead of
// dangling, turning a crash into a safe no-op.
@property (weak) IBOutlet MPEditorView *editor;
@property (weak) IBOutlet NSLayoutConstraint *editorPaddingBottom;
@property (weak) IBOutlet WebView *preview;
@property (strong) MPPreviewFindPanel *previewFindPanel;
@property (strong) NSSearchField *previewFindField;
@property (copy) NSArray<NSDictionary *> *previewEditRanges;
@property (copy) NSArray<NSDictionary *> *previewScrollCodeLines;
@property BOOL sourceScrollLocations;
@property (copy) NSString *previewEditSource;
@property (copy) NSString *previewEditToken;
@property BOOL previewFormattingProbe;
@property (copy) NSString *previewFormattingProbeSource;
@property (copy) NSDictionary *previewSelectionToRestore;
@property (strong) NSMutableArray<NSDictionary *> *previewQueuedFormatting;
@property (copy) NSArray<NSDictionary *> *currentPreviewCallouts;
@property (copy) NSString *currentPreviewCalloutSource;
@property (copy) NSDictionary<NSString *, NSNumber *> *pendingPreviewCalloutStates;
@property BOOL resetPreviewCalloutStates;
@property (weak) IBOutlet NSPopUpButton *wordCountWidget;
@property (strong) NSTextField *readingProgressLabel;
@property (strong) NSArray<NSLayoutConstraint *> *readingProgressConstraints;
@property (weak) NSView *readingProgressDocumentView;
@property BOOL readingProgressFromPreview;
@property BOOL readingProgressUpdatePending;
@property (strong) id readingProgressScrollMonitor;
@property (strong) IBOutlet MPToolbarController *toolbarController;
@property (copy, nonatomic) NSString *autosaveName;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (strong) MPRenderer *renderer;
@property CGFloat previousSplitRatio;
@property CGFloat lastNonCollapsedRatio;
@property BOOL manualRender;
@property BOOL printing;
// Issue #504: Single-slot stash so the shared print-completion callback
// (-document:didPrint:context:) knows whether this completion was a
// save-to-PDF export (-exportPdf:) and, if so, which file to post-process
// with clickable internal anchor links. Mirrors the `printing` BOOL
// stash/clear convention above: set right before printing is dispatched,
// always cleared once the callback fires.
@property (strong) NSURL *pdfExportURL;
@property BOOL pdfExportPending;
@property (strong) NSURL *pdfExportTemporaryURL;
@property (strong) NSURL *pdfExportMetadataURL;
@property (copy) NSPrintInfo *pdfExportPrintInfo;
@property (strong) WebView *pdfExportOriginalPreview;
@property (strong) JSContext *pdfExportOriginalContext;
@property (copy) NSString *pdfExportDOMSnapshot;
@property NSUInteger pdfExportGeneration;
@property (copy) NSDictionary *pdfExportAnchorSession;
@property (strong) JSContext *pdfExportJSContext;
@property (strong) WebView *pdfExportPreview;
@property (copy) NSString *pdfExportMediaStyle;
@property (strong) NSError *pdfExportError;
@property BOOL isPreviewReady;
@property BOOL documentClosed;
@property NSUInteger fileWatchGeneration;
@property NSUInteger saveGeneration;
@property NSUInteger previewRenderGeneration;
@property BOOL awaitingRequestedRender;
@property (copy) NSString *currentPreviewResourceHTML;
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
@property (copy) NSData *diskContentFingerprint;
@property (copy) NSData *pendingDiskFingerprint;
@property BOOL collectingDiskFingerprint;

// Issue #543: State for collapsing bursts of external-change notifications.
// externalChangeCoalescePending is set while a debounced decision is in flight;
// externalChangePromptVisible is set while the keep/discard sheet is on screen,
// so later notifications are dropped rather than queued behind it. The interval
// and the presenter are injection seams, so tests can exercise this without
// real timing or a real modal session.
@property (nonatomic) BOOL externalChangeCoalescePending;
@property (nonatomic) BOOL resourceRenderPending;
@property (nonatomic) BOOL externalChangePromptVisible;
@property (nonatomic) NSTimeInterval externalChangeCoalesceInterval;
@property (nonatomic, copy) void (^externalChangePromptPresenter)(void (^)(BOOL));

// Issue #543: The scroll restore in -reloadFromLoadedString is deferred to a
// later main-queue turn, so a second reload can start before the first's
// restore runs. This generation counter lets a superseded restore no-op rather
// than snap the viewport back to a stale rect, mirroring mathJaxRenderGeneration.
@property (nonatomic) NSUInteger externalReloadScrollGeneration;

// Issue #371: Injection seam so tests can simulate a non-local save
// destination without a real network mount. Defaults to
// +[MPFileWatcher pathIsOnLocalVolume:].
@property (nonatomic, copy) BOOL (^volumeLocalityChecker)(NSString *path);

// Issue #320: Block-based observer token for main-thread-safe defaults notification
@property (strong) id userDefaultsObserverToken;

// Issue #110: Watch local resources for cache-busting
@property (strong) MPResourceWatcherSet *resourceWatcherSet;

// Folder-workspace sidebar support
@property (nonatomic, strong) MPFolderSidebarViewController *sidebarController;
@property (nonatomic, strong) MPSidebarSplitView *outerSplitView;

// Completion handlers for deferred operations when preview is hidden (issue #16)
@property (strong) NSMutableArray<void (^)(void)> *renderCompletionHandlers;

// Store file content in initializer until nib is loaded.
@property (copy) NSString *loadedString;

@property CGFloat zoomMultiplier;

- (void)scaleWebview;
- (void)syncScrollers;
- (void)syncScrollersToCursor;
- (void)syncScrollersReverse;
- (void)syncSourceScrollersReverse:(BOOL)reverse;
- (void)updateHeaderLocations;
- (BOOL)updateSourceScrollLocations;
- (NSArray<NSDictionary *> *)scrollCodeLinesForSource:(NSString *)source context:(JSContext *)context;
- (void)validateHeaderLocationAlignment;
// Issue #436: Pure helpers — no view/DOM dependencies, so they are unit-testable headless.
+ (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown
                                          outLineNumbers:(NSArray<NSNumber *> **)outLineNumbers;
// Pure geometry helper for -syncScrollersToCursor — see its declaration further
// down for full documentation. Declared here too so unit tests (via a category)
// can call it directly with concrete numbers.
+ (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY
           editorContentHeight:(CGFloat)editorContentHeight
           editorVisibleHeight:(CGFloat)editorVisibleHeight
           editorScrollOffsetY:(CGFloat)editorScrollOffsetY
          previewContentHeight:(CGFloat)previewContentHeight
          previewVisibleHeight:(CGFloat)previewVisibleHeight
        editorHeaderLocations:(NSArray<NSNumber *> *)editorHeaderLocations
       webViewHeaderLocations:(NSArray<NSNumber *> *)webViewHeaderLocations;
+ (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs
          editorTypes:(NSArray<NSNumber *> *)editorTypes
            previewYs:(NSArray<NSNumber *> *)previewYs
         previewTypes:(NSArray<NSNumber *> *)previewTypes
      alignedEditorYs:(NSArray<NSNumber *> **)outEditorYs
     alignedPreviewYs:(NSArray<NSNumber *> **)outPreviewYs;
- (BOOL)performAfterRender:(void (^)(void))handler;
- (void)invokeRenderCompletionHandlers;
- (void)finishPreviewRender;
- (void)preparePreviewCalloutStatesForRenderer:(MPRenderer *)renderer;
- (void)restorePreviewCalloutStates;
+ (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context;
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
- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection;
- (void)applyPreviewZoom;
- (BOOL)performPreviewFormattingAction:(NSString *)action value:(NSString *)value;
- (BOOL)queuePendingPreviewFormattingPayload:(NSDictionary *)payload;
- (void)stepDocumentZoomDirection:(NSInteger)direction;
// Fix #4: Extracted from -windowControllerDidLoadNib:/-close so a headless
// test can register/unregister the shared-preference (zoom) KVO observer
// without needing a loaded nib.
- (void)registerSharedPreferenceObservers;
- (void)unregisterSharedPreferenceObservers;
// Commit 8 (gap 9): MathJax generation counter accessor (used by tests via category)
- (NSUInteger)mathJaxRenderGeneration;
// Issue #504: PDF export post-processing (clickable internal anchor links).
- (BOOL)preparePDFAnchorSession;
- (void)restorePDFAnchorSession;
- (void)postProcessExportedPDFAtURL:(NSURL *)url;

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
    NSUInteger generation = doc.previewRenderGeneration;
    __weak MPDocument *weakObj = doc;
    return ^{
        // Gap 8: weak→strong dance to avoid repeated weakObj dereferences and
        // to ensure the object is not released mid-block.
        __strong MPDocument *strongObj = weakObj;
        if (!strongObj || strongObj.documentClosed || strongObj.previewRenderGeneration != generation) return;

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
        [strongObj finishPreviewRender];
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
    return self.editor ? self.editor.string : self.loadedString;
}

- (void)setMarkdown:(NSString *)markdown
{
    MPEditorView *editor = self.editor;
    if (!editor) {
        // Initial/background content remains available until the nib loads.
        self.loadedString = markdown;
        return;
    }
    NSString *content = markdown ?: @"";
    NSString *previous = [editor.string copy];
    if ([previous isEqualToString:content]) return;

    NSUndoManager *undo = self.undoManager;
    BOOL registersUndo = undo.isUndoRegistrationEnabled;
    BOOL startsGroup = registersUndo && !undo.isUndoing && !undo.isRedoing;
    if (startsGroup) [undo beginUndoGrouping];
    @try {
        if (registersUndo) [[undo prepareWithInvocationTarget:self] setMarkdown:previous];
        // A scripting property is literal content, so bypass the interactive
        // shouldChangeText delegate's matching-character autocompletion.
        editor.string = content;
        self.loadedString = nil;
        [editor didChangeText];
        // NSDocument tracks registered groups and undo/redo itself. Incrementing
        // here as well would leave the document dirty after undo to its baseline.
        if (!registersUndo) [self updateChangeCount:NSChangeDone];
    } @finally {
        if (startsGroup) [undo endUndoGrouping];
    }
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

    // Issue #543: Tests shorten this so coalescing can be exercised quickly.
    _externalChangeCoalesceInterval = kMPExternalChangeCoalesceInterval;

    return self;
}

- (NSString *)windowNibName
{
    return @"MPDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib:controller];
    [self installFolderSidebarForController:controller];

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

    [self registerSharedPreferenceObservers];
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
        if (self.documentClosed) return;
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

// Fix #4: Extracted from -windowControllerDidLoadNib: so a headless test can
// register the shared-preference (zoom) KVO observer directly, without a
// loaded nib. Touches only the standardUserDefaults singleton -- no nib
// outlets involved.
- (void)registerSharedPreferenceObservers
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in MPEditorPreferencesToObserve())
    {
        [defaults addObserver:self forKeyPath:key
                      options:NSKeyValueObservingOptionNew context:NULL];
    }
}

// Fix #4: Extracted from -close (see -registerSharedPreferenceObservers).
- (void)unregisterSharedPreferenceObservers
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in MPEditorPreferencesToObserve())
        [defaults removeObserver:self forKeyPath:key];
}

// Issue #543: A reload can shorten the file out from under the caret, so both
// ends of the previous selection have to be pulled back inside the new text.
+ (NSRange)selectionRange:(NSRange)range clampedToLength:(NSUInteger)length
{
    if (range.location == NSNotFound)
        return NSMakeRange(0, 0);
    if (range.location > length)
        range.location = length;
    if (range.length > length - range.location)
        range.length = length - range.location;
    return range;
}

#pragma mark - Folder sidebar

// Canonicalise on the way in, so one folder is one workspace however it was
// reached. `macdown /tmp/proj` and File > Open Folder... on the same directory
// otherwise produce file:///tmp/proj/ and file:///private/tmp/proj/, which the
// sync coordinator would treat as two unrelated workspaces -- silently, since
// everything except sync canonicalises already.
- (void)setWorkspaceRootURL:(NSURL *)workspaceRootURL
{
    _workspaceRootURL =
        [workspaceRootURL.URLByResolvingSymlinksInPath copy] ?: [workspaceRootURL copy];
}

- (void)installFolderSidebarForController:(NSWindowController *)controller
{
    if (!self.workspaceRootURL)
        return;

    NSWindow *window = controller.window;
    NSView *content = window.contentView;
    MPDocumentSplitView *inner = self.splitView;
    if (!inner || inner.superview != content)
        return;   // unexpected hierarchy; skip rather than corrupt the window

    self.sidebarController =
        [[MPFolderSidebarViewController alloc] initWithRootURL:self.workspaceRootURL];
    self.sidebarController.sidebarDelegate = self;

    MPSidebarSplitView *outer =
        [[MPSidebarSplitView alloc] initWithFrame:content.bounds];
    outer.vertical = YES;
    outer.dividerStyle = NSSplitViewDividerStyleThin;
    outer.delegate = self.sidebarController;          // NOT MPDocument
    // No autosaveName: width persistence + cross-tab sync is owned by
    // MPSidebarSyncCoordinator; a shared NSSplitView autosave would fight it.
    outer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [inner removeFromSuperview];

    NSView *sidebarView = self.sidebarController.view;
    // Start at this workspace's shared width so this tab matches its siblings.
    CGFloat startWidth = [[MPSidebarSyncCoordinator sharedCoordinator]
        sidebarWidthForRoot:self.workspaceRootURL];

    [outer addSubview:sidebarView];                   // index 0 = leading sidebar
    [outer addSubview:inner];                         // index 1 = editor/preview

    // The sidebar is pinned to a fixed width by the delegate's
    // -splitView:resizeSubviewsWithOldSize: (holding priorities don't pin during
    // an autoresize — NSSplitView falls back to proportional resizing).
    outer.frame = content.bounds;
    [content addSubview:outer];
    self.outerSplitView = outer;
    [outer adjustSubviews];
    [outer setPosition:startWidth ofDividerAtIndex:0];

    // Match this workspace's visibility (a new tab opened while the sidebar was
    // hidden in its sibling tabs should also start hidden).
    if (![[MPSidebarSyncCoordinator sharedCoordinator]
              sidebarVisibleForRoot:self.workspaceRootURL])
        [self hideSidebarPane];

    // Live sync across tabs. Width is reported only on a genuine divider drag
    // (see -outerSplitDidResize:), so opening a tab or resizing the window never
    // nudges the shared width. Observers are removed in -close (removeObserver:self).
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(outerSplitDidResize:)
               name:NSSplitViewDidResizeSubviewsNotification object:outer];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(sidebarSyncDidChange:)
               name:MPSidebarSyncDidChangeNotification object:nil];
}

// Propagate a width change ONLY when it comes from the user dragging the
// divider. The same notification also fires for programmatic -setPosition:,
// window resizing, and tab insertion; those must not broadcast (that reset the
// shared width every time a tab opened). MPSidebarSplitView knows when it is
// inside a divider-drag tracking loop, which -[NSApp currentEvent] cannot
// reliably tell apart from a layout-triggered resize.
- (void)outerSplitDidResize:(NSNotification *)note
{
    if (!self.outerSplitView.isDraggingDivider)
        return;
    NSView *sidebarView = self.sidebarController.view;
    if (sidebarView.superview != self.outerSplitView)
        return;
    CGFloat w = NSWidth(sidebarView.frame);
    if (w > 0)
        [[MPSidebarSyncCoordinator sharedCoordinator]
            setSidebarWidth:w forRoot:self.workspaceRootURL source:self];
}

// Whether the sidebar is actually on screen. The pane can be absent (hidden via
// ⌘\, which removes it so no divider is drawn) or present but collapsed to zero
// width by a divider drag; both read as not visible.
- (BOOL)isSidebarVisible
{
    NSView *sidebarView = self.sidebarController.view;
    if (!self.outerSplitView || sidebarView.superview != self.outerSplitView)
        return NO;
    return ![self.outerSplitView isSubviewCollapsed:sidebarView];
}

- (void)showSidebarPane
{
    NSSplitView *outer = self.outerSplitView;
    NSView *sidebarView = self.sidebarController.view;
    if (!outer)
        return;
    // The coordinator is the single source of truth for this workspace's
    // width; it is the only one that sees this tab's own divider drags, which
    // -sidebarSyncDidChange: skips because it ignores its own broadcasts.
    CGFloat w = [[MPSidebarSyncCoordinator sharedCoordinator]
        sidebarWidthForRoot:self.workspaceRootURL];
    if (sidebarView.superview == outer)
    {
        // Present but dragged shut: reopen it at the workspace's width. A
        // collapsed pane is left hidden by AppKit, and it can also be re-added
        // in that state, so clear it here rather than rely on -setPosition:.
        if ([outer isSubviewCollapsed:sidebarView] || sidebarView.hidden)
        {
            sidebarView.hidden = NO;
            [outer setPosition:w ofDividerAtIndex:0];
        }
        return;
    }
    sidebarView.hidden = NO;
    [outer addSubview:sidebarView positioned:NSWindowBelow relativeTo:self.splitView];
    [outer adjustSubviews];
    [outer setPosition:w ofDividerAtIndex:0];
}

- (void)hideSidebarPane
{
    NSSplitView *outer = self.outerSplitView;
    NSView *sidebarView = self.sidebarController.view;
    if (!outer || sidebarView.superview != outer)
        return;
    [sidebarView removeFromSuperview];          // removing the pane draws no divider
    [outer adjustSubviews];
}

- (IBAction)toggleFolderSidebar:(id)sender
{
    if (!self.sidebarController || !self.outerSplitView)
        return;
    BOOL shown = self.isSidebarVisible;
    if (shown)
        [self hideSidebarPane];
    else
        [self showSidebarPane];
    // Broadcast so the other tabs of THIS workspace match.
    [[MPSidebarSyncCoordinator sharedCoordinator]
        setSidebarVisible:!shown forRoot:self.workspaceRootURL source:self];
}

// Another tab of the SAME workspace changed the shared width/visibility: match
// it here. Changes from a window open on a different folder are ignored — those
// are independent workspaces that happen to share the process.
- (void)sidebarSyncDidChange:(NSNotification *)note
{
    if (note.object == self)
        return;                                  // ignore our own change
    NSString *kind = note.userInfo[MPSidebarSyncKindKey];
    NSURL *root = note.userInfo[MPSidebarSyncRootKey];
    if (![root.absoluteString isEqualToString:self.workspaceRootURL.absoluteString])
        return;                                  // a different workspace

    MPSidebarSyncCoordinator *coord = [MPSidebarSyncCoordinator sharedCoordinator];
    if ([kind isEqualToString:MPSidebarSyncKindWidth])
    {
        CGFloat width = [coord sidebarWidthForRoot:self.workspaceRootURL];
        if (self.sidebarController.view.superview == self.outerSplitView)
            [self.outerSplitView setPosition:width ofDividerAtIndex:0];
    }
    else if ([kind isEqualToString:MPSidebarSyncKindVisible])
    {
        if ([coord sidebarVisibleForRoot:self.workspaceRootURL])
            [self showSidebarPane];
        else
            [self hideSidebarPane];
    }
}

+ (MPDocument *)openDocumentForFileURL:(NSURL *)url
{
    NSDocument *doc =
        [[NSDocumentController sharedDocumentController] documentForURL:url];
    return [doc isKindOfClass:[MPDocument class]] ? (MPDocument *)doc : nil;
}

// What to show the user when opening a sidebar file produced no document.
// Returns nil when there is nothing worth reporting. Split out from the
// presentation so it can be tested without putting a modal alert on screen.
+ (NSError *)sidebarOpenErrorForError:(NSError *)error URL:(NSURL *)url
{
    // The user cancelling (e.g. at an authentication prompt) is not a failure.
    if ([error.domain isEqualToString:NSCocoaErrorDomain]
        && error.code == NSUserCancelledError)
    {
        return nil;
    }
    if (error)
        return error;

    // No document and no error: synthesise one rather than fail silently.
    NSString *fmt = NSLocalizedString(@"The file “%@” could not be opened.",
                                      @"Sidebar file open failure");
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] =
        [NSString stringWithFormat:fmt, url.lastPathComponent ?: @""];
    if (url)
        info[NSURLErrorKey] = url;
    return [NSError errorWithDomain:NSCocoaErrorDomain
                               code:NSFileReadUnknownError userInfo:info];
}

- (void)presentSidebarOpenError:(NSError *)error forURL:(NSURL *)url
{
    NSError *toShow = [MPDocument sidebarOpenErrorForError:error URL:url];
    if (toShow)
        [self presentError:toShow];
}

- (void)folderSidebar:(MPFolderSidebarViewController *)sidebar
   didActivateFileURL:(NSURL *)url
{
    // 1. Already open? Just raise that tab. The highlight belongs in the tab
    //    that displays the file, which is the one being raised — not this one,
    //    which goes on showing whatever it had.
    MPDocument *existing = [MPDocument openDocumentForFileURL:url];
    if (existing)
    {
        [existing showWindows];
        [existing.sidebarController selectFileURL:url];
        return;
    }

    // 2. Open without display so we can set the workspace root before the
    //    nib loads (so the new tab gets its own sidebar), then tab it in.
    NSWindow *hostWindow = self.windowControllers.firstObject.window;
    NSURL *root = self.workspaceRootURL;
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [c openDocumentWithContentsOfURL:url display:NO
                  completionHandler:^(NSDocument *opened, BOOL wasOpen, NSError *err) {
        if (wasOpen)
        {
            // Its nib has already loaded, so setting workspaceRootURL now would
            // be ignored while still overwriting the root it syncs against.
            [opened showWindows];
            if ([opened isKindOfClass:[MPDocument class]])
                [((MPDocument *)opened).sidebarController selectFileURL:url];
            return;
        }
        if (![opened isKindOfClass:[MPDocument class]])
        {
            // display:NO opts out of NSDocumentController's automatic error
            // alert, so a file that was deleted or is unreadable would fail
            // silently — report it ourselves.
            [self presentSidebarOpenError:err forURL:url];
            return;
        }
        MPDocument *mp = (MPDocument *)opened;
        mp.workspaceRootURL = root;
        if (mp.windowControllers.count == 0)
            [mp makeWindowControllers];
        NSWindow *newWindow = mp.windowControllers.firstObject.window;
        if (hostWindow && newWindow && newWindow != hostWindow)
            [hostWindow addTabbedWindow:newWindow ordered:NSWindowAbove];
        [mp showWindows];
        [mp.sidebarController selectFileURL:url];
    }];
}

// Shared by three paths: the initial document open, a manual Revert, and an
// external-change reload (silent or post-Discard). The selection/scroll
// preservation below therefore affects all three — a change made here for one
// caller changes the behaviour of the others too.
- (void)reloadFromLoadedString
{
    if (self.editor && self.renderer && self.highlighter)
    {
        if (self.loadedString)
        {
            // Issue #543: Assigning the editor's whole string moves the
            // insertion point back to the top of the document. That was easy
            // to live with while reloads were rare, but an external change now
            // reloads silently whenever there is nothing unsaved to lose, so
            // the caret and scroll position are captured and put back. The
            // selection is restored before the scroll because -setSelectedRange:
            // does not scroll to reveal the selection, so the order is safe.
            NSRange previousSelection = self.editor.selectedRange;
            NSScrollView *scrollView = self.editor.enclosingScrollView;
            NSRect previousVisibleRect =
                scrollView ? self.editor.visibleRect : NSZeroRect;

            self.editor.string = self.loadedString;
            self.loadedString = nil;
            [self.highlighter clearHighlighting];
            [self.highlighter readClearTextStylesFromTextView];

            self.editor.selectedRange =
                [MPDocument selectionRange:previousSelection
                           clampedToLength:self.editor.string.length];
            if (scrollView)
            {
                // -[MPEditorView setString:] enqueues a content-geometry
                // update when Scrolls Past End is on, which would resize the
                // scrollable area out from under an immediate scroll. Going
                // through the main queue puts this after that block.
                //
                // Because the restore is deferred, a second reload can start
                // before this block runs; bump a generation and let a
                // superseded block bail rather than snap back to a stale rect.
                self.externalReloadScrollGeneration++;
                NSUInteger expectedGeneration = self.externalReloadScrollGeneration;
                MPEditorView *editor = self.editor;
                __weak MPDocument *weakSelf = self;
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    MPDocument *strongSelf = weakSelf;
                    if (!strongSelf ||
                        strongSelf.externalReloadScrollGeneration != expectedGeneration)
                        return;
                    [editor scrollRectToVisible:previousVisibleRect];
                }];
            }
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
    self.previewFindPanel.findActionHandler = nil;
    [self.previewFindPanel.parentWindow removeChildWindow:self.previewFindPanel];
    [self.previewFindPanel close];
    self.previewFindField = nil;
    self.previewFindPanel = nil;
    self.documentClosed = YES;
    self.previewEditRanges = nil;
    self.previewEditSource = nil;
    self.previewEditToken = nil;
    self.previewSelectionToRestore = nil;
    self.previewQueuedFormatting = nil;
    self.currentPreviewCallouts = nil;
    self.currentPreviewCalloutSource = nil;
    self.pendingPreviewCalloutStates = nil;
    if (self.readingProgressScrollMonitor) {
        [NSEvent removeMonitor:self.readingProgressScrollMonitor];
        self.readingProgressScrollMonitor = nil;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(updateReadingProgress) object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self
        name:NSViewFrameDidChangeNotification object:self.readingProgressDocumentView];
    [self.readingProgressLabel removeFromSuperview];
    self.readingProgressLabel = nil;
    self.readingProgressConstraints = nil;
    [self stopFileWatching];
    [self.renderCompletionHandlers removeAllObjects];
    if (!self.printing) {
        self.pdfExportPending = NO;
        self.pdfExportURL = nil;
    }
    self.renderer.delegate = nil;
    self.renderer.dataSource = nil;
    self.preview.editingDelegate = nil;
    self.preview.resourceLoadDelegate = nil;
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
        [self.sidebarController stopWatching];

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

        [self unregisterSharedPreferenceObservers];
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
    if ([self previewDraft]) return YES;
    // Prevent save dialog on an unnamed, empty document. The file will still
    // show as modified (because it is), but no save dialog will be presented
    // when the user closes it.
    if (!self.presentedItemURL && !self.markdown.length)
        return NO;
    return [super isDocumentEdited];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
             error:(NSError *__autoreleasing *)outError
{
    // Commit the draft against its original source before normalizing the file.
    // A refused draft must leave both the source and save bookkeeping intact.
    if (![self flushPreviewEditorForSaveWithError:outError]) return NO;

    // Issue #290: Mark that we're saving to avoid triggering reload
    self.isSelfSaving = YES;
    NSUInteger saveGeneration = ++self.saveGeneration;

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

    self.pendingDiskFingerprint = nil;
    self.collectingDiskFingerprint = YES;
    BOOL result;
    @try {
        result = [super writeToURL:url ofType:typeName error:outError];
    } @finally {
        self.collectingDiskFingerprint = NO;
    }
    if (result && [url isEqual:self.fileURL])
        self.diskContentFingerprint = self.pendingDiskFingerprint;

    // Issue #290: Clear save flag after a short delay to ensure
    // the file watcher doesn't trigger (events may be coalesced)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.saveGeneration == saveGeneration)
            self.isSelfSaving = NO;
    });

    // If URL changed (Save As), restart watching the new file
    if (result && (!previousURL || ![url isEqual:previousURL]))
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            // URL was updated by super, restart watching the new file
            [self startFileWatching];

            // A new path also appeared on disk. Folder sidebars watch with
            // kFSEventStreamCreateFlagIgnoreSelf (so ordinary re-saves don't
            // cause a reload storm), which also means they never see files WE
            // create — tell them directly.
            //
            // The test is on the document's own URL, not on `url`: a safe save
            // hands -writeToURL: a path inside an NSItemReplacementDirectory
            // and swaps it into place afterwards, so `url` is never the file
            // the user ends up with. By the time this block runs NSDocument has
            // updated fileURL, so a change against previousURL means a first
            // save or a Save As — the cases that add a path to the tree.
            NSURL *saved = self.fileURL;
            if (saved && ![saved isEqual:previousURL])
            {
                [[MPSidebarSyncCoordinator sharedCoordinator]
                    notifyFileSavedAtURL:saved source:self];
            }
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
    NSData *previousFingerprint = self.diskContentFingerprint;
    BOOL result;
    if ([self shouldBypassSafeSaveForURL:url])
    {
        result = [self writeToURL:url ofType:typeName
                forSaveOperation:saveOperation
             originalContentsURL:self.fileURL error:outError];
    }
    else
        result = [super writeSafelyToURL:url ofType:typeName
                       forSaveOperation:saveOperation error:outError];
    // A recovery autosave is not a write to the original file. Publish the
    // exact serialized snapshot only after the complete safe save succeeds.
    self.diskContentFingerprint = result && saveOperation != NSAutosaveElsewhereOperation
        ? self.pendingDiskFingerprint : previousFingerprint;
    return result;
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

- (BOOL)flushPreviewEditorForSaveWithError:(NSError **)outError
{
    __block BOOL flushed = YES;
    if (NSThread.isMainThread) flushed = [self flushPreviewEditor];
    else dispatch_sync(dispatch_get_main_queue(), ^{ flushed = [self flushPreviewEditor]; });
    if (!flushed) {
        if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
            userInfo:@{NSLocalizedDescriptionKey:@"La modification dans l’aperçu ne peut pas être appliquée. Copiez le texte ou appuyez sur Échap pour l’annuler."}];
        return NO;
    }
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    if (![self flushPreviewEditorForSaveWithError:outError]) return nil;
    NSString *content = self.editor ? self.editor.string : (self.loadedString ?: @"");
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (data && self.collectingDiskFingerprint)
        self.pendingDiskFingerprint = MPDocumentContentFingerprint(data);
    return data;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName
               error:(NSError **)outError
{
    NSString *content = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (!content)
    {
        if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInapplicableStringEncodingError
            userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"The document is not valid UTF-8 text.", @"Invalid Markdown encoding")}];
        return NO;
    }

    self.diskContentFingerprint = MPDocumentContentFingerprint(data);

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

    if (self.pdfExportURL) {
        self.pdfExportPrintInfo = info;
        self.pdfExportOriginalPreview = self.preview;
        self.pdfExportOriginalContext = self.preview.mainFrame.javaScriptContext;
        self.pdfExportGeneration = self.previewRenderGeneration;
        self.pdfExportDOMSnapshot = [[self.pdfExportOriginalContext
            evaluateScript:kMPPDFSnapshotJS] toString];
    }
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

    NSInvocation *invocation = [MPDocument printCompletionForDelegate:printDelegate
                                                             selector:printSelector
                                                              context:context];
    BOOL accepted = [self performAfterRender:^{
        self.printing = YES;
        [super printDocumentWithSettings:settings
                          showPrintPanel:showPanel delegate:self
                        didPrintSelector:@selector(document:didPrint:context:)
                             contextInfo:invocation ? (__bridge_retained void *)invocation : NULL];
    }];
    if (!accepted)
        [self document:self didPrint:NO context:invocation ? (__bridge_retained void *)invocation : NULL];
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
    else if (action == @selector(toggleFolderSidebar:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        BOOL hasWorkspace = (self.workspaceRootURL != nil);
        BOOL shown = hasWorkspace && self.isSidebarVisible;
        it.title = shown
            ? NSLocalizedString(@"Hide Sidebar", @"View menu item")
            : NSLocalizedString(@"Show Sidebar", @"View menu item");
        return hasWorkspace;
    }
    return result;
}


#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    [self redrawDivider];
    self.editor.editable = self.editorVisible;
    [self setupReadingProgress];
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

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)textView
{
    return self.undoManager;
}

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
    if (self.preferences.editorCompleteMatchingCharacters && !selectedRange.length)
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
        [manager boundingRectForGlyphRange:[manager glyphRangeForCharacterRange:NSMakeRange(location, 1) actualCharacterRange:NULL]
                           inTextContainer:container];
    NSRect currentRect =
        [manager boundingRectForGlyphRange:[manager glyphRangeForCharacterRange:NSMakeRange(cur, 1) actualCharacterRange:NULL]
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
    if (frame != sender.mainFrame || self.documentClosed) return;
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
    if (frame != sender.mainFrame || self.documentClosed) return;
    [self restorePreviewCalloutStates];
    [self applyPreviewZoom];
    if (!self.preferences.htmlMathJax)
        [[NSOperationQueue mainQueue] addOperationWithBlock:MPGetPreviewLoadingCompletionHandler(self)];
}

- (void)finishPreviewRender
{
    if (self.documentClosed) return;
    self.isPreviewReady = YES;
    [self installPreviewEditor];
    [self observeReadingProgressDocumentView];
    [self scheduleReadingProgressUpdate];
    self.alreadyRenderingInWeb = NO;
    if (self.preferences.editorShowWordCount) [self updateWordCount];
    if (self.renderToWebPending)
    {
        self.renderToWebPending = NO;
        [self.renderer parseAndRenderNow];
        return;
    }
    if (!self.awaitingRequestedRender) [self invokeRenderCompletionHandlers];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error
       forFrame:(WebFrame *)frame
{
    if (frame != sender.mainFrame || self.documentClosed || error.code == NSURLErrorCancelled) return;
    self.alreadyRenderingInWeb = NO;
    [self.renderCompletionHandlers removeAllObjects];
    if (!self.printing) {
        self.pdfExportPending = NO;
        self.pdfExportURL = nil;
    }
    self.awaitingRequestedRender = NO;
    self.renderToWebPending = NO;
    NSWindow *window = sender.window;
    if (window.isFlushWindowDisabled) [window enableFlushWindow];
    if (error.code != NSURLErrorCancelled) [self presentError:error];
}



#pragma mark - WebPolicyDelegate

- (void)webView:(WebView *)webView
                decidePolicyForNavigationAction:(NSDictionary *)information
        request:(NSURLRequest *)request frame:(WebFrame *)frame
                decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL *url = request.URL;

    if ([url.scheme isEqualToString:@"x-macdown-preview"]) {
        [listener ignore];
        if (webView == self.preview && frame == webView.mainFrame) [self handlePreviewEdit:url];
        return;
    }

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

- (void)webViewDidChangeSelection:(NSNotification *)notification
{
    if (self.documentClosed || notification.object != self.preview ||
        ![self previewHasFindFocus] || !self.preview.selectedDOMRange.toString.length)
        return;
    NSRange selection = self.editor.selectedRange;
    if (selection.length)
        self.editor.selectedRange = NSMakeRange(selection.location, 0);
}

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

- (BOOL)previewHasFindFocus
{
    if (NSApp.keyWindow == self.previewFindPanel && self.previewFindPanel)
        return YES;
    NSResponder *responder = self.preview.window.firstResponder;
    return [responder isKindOfClass:NSView.class] &&
        [(NSView *)responder isDescendantOf:self.preview];
}

- (BOOL)validateDocumentFindAction:(NSMenuItem *)item
{
    if (![self previewHasFindFocus])
    {
        NSMenuItem *native = [item copy];
        native.action = @selector(performFindPanelAction:);
        id target = [NSApp targetForAction:native.action to:nil from:native];
        if ([target respondsToSelector:@selector(validateUserInterfaceItem:)])
            return [target validateUserInterfaceItem:native];
        return target != nil;
    }
    if (item.tag == NSTextFinderActionShowFindInterface) return YES;
    if (item.tag == NSTextFinderActionSetSearchString)
        return self.preview.selectedDOMRange.toString.length > 0;
    if (item.tag == NSTextFinderActionNextMatch ||
        item.tag == NSTextFinderActionPreviousMatch)
        return [[NSPasteboard pasteboardWithName:NSPasteboardNameFind]
                stringForType:NSPasteboardTypeString].length > 0;
    return NO;
}

- (IBAction)performDocumentFindAction:(id)sender
{
    if ([self previewHasFindFocus])
        [self performPreviewFindAction:[sender tag]];
    else
        [NSApp sendAction:@selector(performFindPanelAction:) to:nil from:sender];
}

- (void)performPreviewFindAction:(NSTextFinderAction)action
{
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    if (action == NSTextFinderActionSetSearchString)
    {
        NSString *selection = self.preview.selectedDOMRange.toString;
        if (selection.length)
        {
            [pasteboard clearContents];
            [pasteboard setString:selection forType:NSPasteboardTypeString];
            self.previewFindField.stringValue = selection;
        }
        return;
    }
    if (action == NSTextFinderActionNextMatch ||
        action == NSTextFinderActionPreviousMatch)
    {
        NSString *query = [pasteboard stringForType:NSPasteboardTypeString];
        if (query.length && ![self.preview searchFor:query
            direction:action == NSTextFinderActionNextMatch
            caseSensitive:NO wrap:YES]) NSBeep();
        return;
    }
    if (action != NSTextFinderActionShowFindInterface) return;
    if (!self.previewFindPanel)
    {
        MPPreviewFindPanel *panel = [[MPPreviewFindPanel alloc]
            initWithContentRect:NSMakeRect(0,0,380,76)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                      NSWindowStyleMaskUtilityWindow
            backing:NSBackingStoreBuffered defer:NO];
        panel.releasedWhenClosed = NO;
        panel.title = NSLocalizedString(@"Find in Preview", @"Preview search panel title");
        panel.hidesOnDeactivate = YES;
        NSSearchField *field = [[NSSearchField alloc] initWithFrame:NSZeroRect];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.accessibilityIdentifier = @"preview-find-field";
        field.target = self;
        field.action = @selector(findPreviewText:);
        field.sendsWholeSearchString = YES;
        NSSegmentedControl *buttons = [NSSegmentedControl
            segmentedControlWithLabels:@[@"‹", @"›"]
            trackingMode:NSSegmentSwitchTrackingMomentary target:self
            action:@selector(findPreviewAdjacent:)];
        buttons.translatesAutoresizingMaskIntoConstraints = NO;
        [buttons setToolTip:NSLocalizedString(@"Find Previous", @"Search backwards")
                 forSegment:0];
        [buttons setToolTip:NSLocalizedString(@"Find Next", @"Search forwards")
                 forSegment:1];
        [panel.contentView addSubview:field];
        [panel.contentView addSubview:buttons];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:12],
            [field.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-12],
            [field.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:12],
            [buttons.trailingAnchor constraintEqualToAnchor:field.trailingAnchor],
            [buttons.topAnchor constraintEqualToAnchor:field.bottomAnchor constant:6],
        ]];
        __weak MPDocument *weakSelf = self;
        panel.findActionHandler = ^(NSTextFinderAction requested) {
            [weakSelf performPreviewFindAction:requested];
        };
        [self.windowForSheet addChildWindow:panel ordered:NSWindowAbove];
        self.previewFindPanel = panel;
        self.previewFindField = field;
        [panel center];
    }
    self.previewFindField.stringValue =
        [pasteboard stringForType:NSPasteboardTypeString] ?: @"";
    [self.previewFindPanel makeKeyAndOrderFront:nil];
    [self.previewFindPanel makeFirstResponder:self.previewFindField];
}

- (void)findPreviewText:(NSSearchField *)field
{
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    [pasteboard clearContents];
    [pasteboard setString:field.stringValue forType:NSPasteboardTypeString];
    [self performPreviewFindAction:NSTextFinderActionNextMatch];
}

- (void)findPreviewAdjacent:(NSSegmentedControl *)sender
{
    [self performPreviewFindAction:sender.selectedSegment == 0 ?
        NSTextFinderActionPreviousMatch : NSTextFinderActionNextMatch];
}

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

- (void)preparePreviewCalloutStatesForRenderer:(MPRenderer *)renderer
{
    if (self.resetPreviewCalloutStates || !self.currentPreviewCallouts.count ||
        !renderer.calloutSourceEntries.count || !self.isPreviewReady) {
        self.pendingPreviewCalloutStates = @{};
        self.currentPreviewCallouts = renderer.calloutSourceEntries;
        self.currentPreviewCalloutSource = renderer.checkboxSourceMarkdown;
        self.resetPreviewCalloutStates = NO;
        return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *oldStates = [NSMutableDictionary dictionary];
    {
        NSMutableSet *owned = [NSMutableSet set], *duplicates = [NSMutableSet set];
        for (NSDictionary *entry in self.currentPreviewCallouts) [owned addObject:entry[@"token"]];
        DOMNodeList *nodes = [self.preview.mainFrame.DOMDocument getElementsByTagName:@"details"];
        for (NSUInteger i = 0; i < nodes.length; i++) {
            DOMElement *element = (DOMElement *)[nodes item:(unsigned)i];
            NSString *token = [element getAttribute:@"data-macdown-callout-token"];
            if (![owned containsObject:token]) continue;
            if (oldStates[token]) [duplicates addObject:token];
            oldStates[token] = @([element hasAttribute:@"open"]);
        }
        for (NSString *token in duplicates) [oldStates removeObjectForKey:token];
    }
    NSString *before = self.currentPreviewCalloutSource ?: @"";
    NSString *after = renderer.checkboxSourceMarkdown ?: @"";
    NSUInteger prefix = 0, suffix = 0, common = MIN(before.length,after.length);
    while (prefix < common && [before characterAtIndex:prefix] == [after characterAtIndex:prefix]) prefix++;
    while (suffix < common-prefix &&
           [before characterAtIndex:before.length-suffix-1] == [after characterAtIndex:after.length-suffix-1]) suffix++;
    NSMutableDictionary<NSValue *, NSDictionary *> *newOpenings = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in renderer.calloutSourceEntries)
        newOpenings[entry[@"sourceOpenRange"]] = entry;
    NSMutableDictionary *restored = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in self.currentPreviewCallouts) {
        NSNumber *state = oldStates[entry[@"token"]];
        if (!state) continue;
        NSRange mapped = MPPreviewRemapCalloutOpening(entry,before,after,prefix,suffix);
        if (mapped.location == NSNotFound || mapped.location > after.length ||
            mapped.length > after.length-mapped.location) continue;
        NSDictionary *target = newOpenings[[NSValue valueWithRange:mapped]];
        NSRange oldOpening = [entry[@"sourceOpenRange"] rangeValue];
        if (target && [[before substringWithRange:oldOpening]
            isEqualToString:[after substringWithRange:mapped]]) restored[target[@"token"]] = state;
    }
    self.pendingPreviewCalloutStates = restored;
    self.currentPreviewCallouts = renderer.calloutSourceEntries;
    self.currentPreviewCalloutSource = after;
    self.resetPreviewCalloutStates = NO;
}

- (void)restorePreviewCalloutStates
{
    if (!self.pendingPreviewCalloutStates) return;
    JSContext *context = self.preview.mainFrame.javaScriptContext;
    context[@"window"][@"__macdownCalloutStates"] = self.pendingPreviewCalloutStates;
    [context evaluateScript:MPPreviewRestoreCalloutStateJavaScript];
    self.pendingPreviewCalloutStates = nil;
}

- (void)reloadPreview:(id)sender
{
    // Explicit Reload returns each callout to its source collapse preference.
    // Consume this only when a render can actually replace the current page.
    self.resetPreviewCalloutStates = YES;
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

- (BOOL)rendererWrapsCodeBlocks:(MPRenderer *)renderer
{
    return self.preferences.htmlWrapCodeBlocks;
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
    if (self.documentClosed) return;
    if ([self previewDraft]) { self.renderToWebPending = YES; return; }
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

    if (self.printing) {
        self.renderToWebPending = YES;
        return;
    }

    [self preparePreviewCalloutStatesForRenderer:renderer];
    self.awaitingRequestedRender = NO;
    self.previewRenderGeneration++;
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
    NSString *resources = MPPreviewResourceHTML(html);
    NSString *resourcesForComparison = [resources stringByReplacingOccurrencesOfString:
        [NSString stringWithFormat:@"<meta name=\"macdown-checkbox-token\" content=\"%@\">", renderer.checkboxBridgeToken]
        withString:@"<meta name=\"macdown-checkbox-token\" content=\"\">"];
    BOOL scriptsChanged = !MPAreNilableStringsEqual(self.currentPreviewResourceHTML, resourcesForComparison);
    BOOL stylesChanged = !MPAreNilableStringsEqual(self.currentStyleName, newStyleName) ||
                         !MPAreNilableStringsEqual(self.currentHighlightingThemeName, newHighlightingTheme);

    // Try DOM replacement to preserve scroll position.
    // MathJax re-typesetting is handled via MathJax.Hub.Queue, which serializes
    // the async typesetting correctly. Scroll is restored after typesetting completes.
    // Skip DOM replacement if styles changed, since <head> CSS links need updating.
    // Related to issue #325.
    // A navigation can replace the loaded page while the publication cache
    // still describes our last Markdown preview. Never reuse that foreign head.
    NSURL *loadedURL = self.preview.mainFrame.dataSource.request.URL;
    if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl]
        && [loadedURL isEqual:baseUrl] && resourcesForComparison
        && !stylesChanged && !scriptsChanged
        && !self.preferences.htmlMermaid && !self.preferences.htmlGraphviz)
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
                context[@"window"][@"__macdownTempCheckboxToken"] = renderer.checkboxBridgeToken;
                context[@"window"][@"__macdownCalloutStates"] = self.pendingPreviewCalloutStates ?: @{};

                NSString *updateScript = [NSString stringWithFormat:
                    @"(function(){"
                    @"  var scrollY = %.0f;"
                    @"  var html = window.__macdownTempHtml;"
                    @"  delete window.__macdownTempHtml;"
                    @"  var tokenMeta=document.querySelector('meta[name=\"macdown-checkbox-token\"]');"
                    @"  if(tokenMeta){tokenMeta.content=window.__macdownTempCheckboxToken;}"
                    @"  delete window.__macdownTempCheckboxToken;"
                    @"  var body = document.body;"
                    @"  var ui=window.macdownPreviewEditor&&typeof window.macdownPreviewEditor.elements==='function'&&window.macdownPreviewEditor.elements();"
                    @"  var panel=ui&&ui.panel,editStyle=ui&&ui.style;"
                    @"  if(panel)panel.remove();if(editStyle)editStyle.remove();"
                    @"  body.innerHTML = html;"
                    @"  %@;"
                    @"  if(editStyle)body.appendChild(editStyle);if(panel)body.appendChild(panel);"
                    @"  if(window.Prism&&typeof Prism.highlightAll==='function'){Prism.highlightAll();}"
                    @"  if(typeof window.macdownInitTaskList==='function'){window.macdownInitTaskList();}"
                    @"  if(typeof window.macdownInitTableResize==='function'){window.macdownInitTableResize();}"
                    @"  if(window.MathJax&&MathJax.Hub&&typeof MathJax.Hub.Queue==='function'){"
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
                    scrollBefore, MPPreviewRestoreCalloutStateJavaScript];

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
                        [strongSelf finishPreviewRender];
                    } forKey:@"DOMReplacementDone"];
                    [self.preview.windowScriptObject setValue:listener
                                                      forKey:@"MathJaxListener"];
                }

                [context evaluateScript:updateScript];
                self.pendingPreviewCalloutStates = nil;

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
                    [self finishPreviewRender];
                }

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
    self.currentPreviewResourceHTML = resourcesForComparison;
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
    if (self.documentClosed || set != self.resourceWatcherSet)
        return;
    [self.renderer setTimestamp:[[NSDate date] timeIntervalSince1970]
               forResourcePath:path];
    if (self.resourceRenderPending)
        return;
    self.resourceRenderPending = YES;
    // Adding a watcher reports its initial state synchronously during rendering.
    // Coalesce those callbacks after the current HTML publication completes.
    __weak MPDocument *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        MPDocument *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        strongSelf.resourceRenderPending = NO;
        if (!strongSelf.documentClosed)
            [strongSelf.renderer render];
    });
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
    BOOL previewFocused = [self previewHasFindFocus];
    if (!self.documentClosed && notification.object == self.editor) {
        if (previewFocused && self.editor.selectedRange.length) {
            // Source replacements also change NSTextView's selection. While
            // the preview owns focus, keep its selection and only a source caret.
            self.editor.selectedRange = NSMakeRange(self.editor.selectedRange.location, 0);
            return;
        }
        NSResponder *responder = self.editor.window.firstResponder;
        if ([responder isKindOfClass:NSView.class] &&
            [(NSView *)responder isDescendantOf:self.editor]) {
            // Switching to the source cancels both the visible DOM selection
            // and any pending restoration/formatting for the previous passage.
            self.previewSelectionToRestore = nil;
            self.previewQueuedFormatting = nil;
            [self.preview.mainFrame.javaScriptContext evaluateScript:
                @"window.macdownPreviewEditor && window.macdownPreviewEditor.clearSelection()"];
        }
    }
    if (!previewFocused) self.readingProgressFromPreview = NO;
    [self scheduleReadingProgressUpdate];
    // When Sync Panes is on, moving the cursor (click or arrow keys) refines the
    // preview's scroll position to follow it, on top of the usual viewport-based
    // sync. Runs independently of the word-count display preference below, since
    // it is unrelated to that gate.
    if (!previewFocused && self.preferences.editorSyncScrolling && _scrollOwner == MPScrollOwnerNeither)
    {
        [self syncScrollersToCursor];
    }

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
    [self scheduleReadingProgressUpdate];
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
    self.readingProgressFromPreview = NO;
    [self scheduleReadingProgressUpdate];
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
    self.readingProgressFromPreview = YES;
    [self scheduleReadingProgressUpdate];
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
    [self scheduleReadingProgressUpdate];
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
    [self scheduleReadingProgressUpdate];
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
    [self scheduleReadingProgressUpdate];
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


// Geometry only, coalesced to at most one update per 50 ms; no Markdown parse.
- (void)scheduleReadingProgressUpdate
{
    if (self.documentClosed || !self.preferences.editorShowReadingProgress ||
        self.readingProgressUpdatePending) return;
    self.readingProgressUpdatePending = YES;
    [self performSelector:@selector(updateReadingProgress) withObject:nil afterDelay:0.05
                  inModes:@[NSRunLoopCommonModes]];
}

- (void)observeReadingProgressDocumentView
{
    NSView *view = self.preview.mainFrame.frameView.documentView;
    if (view == self.readingProgressDocumentView) return;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (self.readingProgressDocumentView)
        [center removeObserver:self name:NSViewFrameDidChangeNotification
                        object:self.readingProgressDocumentView];
    self.readingProgressDocumentView = view;
    if (view) {
        view.postsFrameChangedNotifications = YES;
        [center addObserver:self selector:@selector(readingProgressDocumentDidChange:)
            name:NSViewFrameDidChangeNotification object:view];
    }
}

- (void)readingProgressDocumentDidChange:(NSNotification *)notification
{
    [self scheduleReadingProgressUpdate];
}

- (void)setupReadingProgress
{
    NSView *container = self.windowForSheet.contentView;
    if (!container || self.documentClosed) return;
    if (!self.preferences.editorShowReadingProgress && self.readingProgressScrollMonitor) {
        [NSEvent removeMonitor:self.readingProgressScrollMonitor];
        self.readingProgressScrollMonitor = nil;
    } else if (self.preferences.editorShowReadingProgress && !self.readingProgressScrollMonitor) {
        // Mouse wheels can have no gesture phase and produce no live-scroll
        // notification, especially when the pane is already at an edge.
        __weak MPDocument *weakSelf = self;
        self.readingProgressScrollMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
            handler:^NSEvent *(NSEvent *event) {
                MPDocument *document = weakSelf;
                NSView *content = document.windowForSheet.contentView;
                if (!document || document.documentClosed || event.window != document.windowForSheet || !content)
                    return event;
                NSView *hit = [content hitTest:[content convertPoint:event.locationInWindow fromView:nil]];
                if ([hit isDescendantOf:document.preview]) document.readingProgressFromPreview = YES;
                else if ([hit isDescendantOf:document.editor.enclosingScrollView]) document.readingProgressFromPreview = NO;
                else return event;
                [document scheduleReadingProgressUpdate];
                return event;
            }];
    }
    if (!self.readingProgressLabel) {
        NSTextField *label = [NSTextField labelWithString:@"100%"];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        label.textColor = NSColor.secondaryLabelColor;
        label.accessibilityIdentifier = @"reading-progress";
        label.toolTip = NSLocalizedString(@"Position in the document", nil);
        [container addSubview:label];
        self.readingProgressLabel = label;
    }
    self.readingProgressLabel.hidden = !self.preferences.editorShowReadingProgress;
    [NSLayoutConstraint deactivateConstraints:self.readingProgressConstraints ?: @[]];
    if (self.editorVisible && self.preferences.editorShowWordCount && self.wordCountWidget) {
        self.readingProgressConstraints = @[
            [self.readingProgressLabel.leadingAnchor constraintEqualToAnchor:self.wordCountWidget.trailingAnchor constant:10],
            [self.readingProgressLabel.centerYAnchor constraintEqualToAnchor:self.wordCountWidget.centerYAnchor],
        ];
    } else {
        self.readingProgressConstraints = @[
            [self.readingProgressLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
            [self.readingProgressLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
        ];
    }
    [NSLayoutConstraint activateConstraints:self.readingProgressConstraints];
    [self updateReadingProgress];
}

- (void)updateReadingProgress
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(updateReadingProgress) object:nil];
    self.readingProgressUpdatePending = NO;
    if (self.documentClosed || !self.preferences.editorShowReadingProgress) return;
    BOOL fromPreview = !self.editorVisible ||
        (self.previewVisible && self.readingProgressFromPreview);
    NSScrollView *scroll = fromPreview ? self.preview.enclosingScrollView :
        self.editor.enclosingScrollView;
    if (!scroll.documentView) return;
    NSRect visible = scroll.documentVisibleRect;
    NSRect bounds = scroll.documentView.bounds;
    CGFloat distance = NSHeight(bounds) - NSHeight(visible);
    CGFloat offset = scroll.documentView.isFlipped ? NSMinY(visible)-NSMinY(bounds) :
        NSMaxY(bounds)-NSMaxY(visible);
    CGFloat ratio = distance > 0 ? offset/distance : 1;
    if (!isfinite(ratio)) ratio = 1;
    NSInteger percent = lround(MAX(0, MIN(1, ratio))*100);
    self.readingProgressLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)percent];
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
    controller.stylesIncluded = self.preferences.htmlStyleName != nil;
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
            NSError *error = nil;
            if (![html writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error])
                [strongSelf presentError:error];
        }];
    }];
}

- (IBAction)exportPdf:(id)sender
{
    // Issue #504: The single-slot stash can only hold one in-flight export's
    // destination URL. If it is already set, a previous export's save panel
    // or print/write hasn't completed yet (document:didPrint:context: clears
    // it in @finally); starting a second export here would clobber the stash
    // and corrupt both exports' post-processing. Make it a safe no-op.
    if (self.pdfExportPending || self.pdfExportURL)
        return;
    self.pdfExportPending = YES;

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"pdf"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    NSWindow *w = nil;
    NSArray *windowControllers = self.windowControllers;
    if (windowControllers.count > 0)
        w = [windowControllers[0] window];

    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton || self.documentClosed)
        {
            self.pdfExportPending = NO;
            return;
        }

        // Issue #504: Stash the destination URL so -document:didPrint:context:
        // knows this print completion is a save-to-PDF export and which file
        // to post-process with clickable internal anchor links.
        self.pdfExportURL = panel.URL;
        self.pdfExportError = nil;
        self.pdfExportTemporaryURL = [panel.URL.URLByDeletingLastPathComponent
            URLByAppendingPathComponent:[NSString stringWithFormat:@".macdown-print-%@.pdf", NSUUID.UUID.UUIDString]];

        // Issue #16: printDocumentWithSettings: already handles render deferral
        NSDictionary *settings = @{
            NSPrintJobDisposition: NSPrintSaveJob,
            NSPrintJobSavingURL: self.pdfExportTemporaryURL,
        };
        [self printDocumentWithSettings:settings showPrintPanel:NO delegate:nil
                       didPrintSelector:NULL contextInfo:NULL];
    }];
}

// Native print annotations transport identities through CSS layout and pagination.
- (BOOL)preparePDFAnchorSession
{
    if (self.pdfExportAnchorSession) return YES;
    self.pdfExportPreview = self.preview;
    self.pdfExportMediaStyle = self.preview.mediaStyle;
    self.preview.mediaStyle = @"print";
    self.pdfExportJSContext = self.preview.mainFrame.javaScriptContext;
    NSString *identifier = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSDictionary *args = @{@"key": [@"__macdownPDF" stringByAppendingString:identifier],
        @"prefix": [NSString stringWithFormat:@"https://macdown-pdf.invalid/%@/", identifier]};
    NSData *JSON = [NSJSONSerialization dataWithJSONObject:args options:0 error:NULL];
    NSString *argument = [[NSString alloc] initWithData:JSON encoding:NSUTF8StringEncoding];
    JSContext *context = self.pdfExportJSContext;
    context.exception = nil;
    JSValue *result = [context evaluateScript:[NSString stringWithFormat:@"%@(%@)", kMPPreparePDFAnchorsJS, argument]];
    NSArray *links = [result[@"links"] toArray], *headings = [result[@"headings"] toArray];
    if (!context || context.exception || ![links isKindOfClass:NSArray.class] || ![headings isKindOfClass:NSArray.class]) {
        self.pdfExportError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
            userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Could not prepare PDF links.", nil)}];
        [self restorePDFAnchorSession];
        return NO;
    }
    self.pdfExportAnchorSession = @{@"key": args[@"key"], @"prefix": args[@"prefix"],
        @"links": links, @"headings": headings};
    return YES;
}

- (void)restorePDFAnchorSession
{
    NSString *key = self.pdfExportAnchorSession[@"key"];
    if (key.length && self.pdfExportJSContext) {
        NSData *JSON = [NSJSONSerialization dataWithJSONObject:@[key] options:0 error:NULL];
        NSString *argument = [[NSString alloc] initWithData:JSON encoding:NSUTF8StringEncoding];
        [self.pdfExportJSContext evaluateScript:[NSString stringWithFormat:
            @"(function(a){var s=window[a[0]];if(s)s.restore();})(%@)", argument]];
    }
    if (self.pdfExportPreview) self.pdfExportPreview.mediaStyle = self.pdfExportMediaStyle;
    self.pdfExportAnchorSession = nil;
    self.pdfExportJSContext = nil;
    self.pdfExportPreview = nil;
    self.pdfExportMediaStyle = nil;
}

// The original carries the exact printed appearance. A second private print
// supplies native annotation identities, preserving CSS layout through CSSOM.
- (BOOL)PDFExportSnapshotIsCurrent
{
    return !self.documentClosed && self.preview == self.pdfExportOriginalPreview
        && self.preview.mainFrame.javaScriptContext == self.pdfExportOriginalContext
        && self.previewRenderGeneration == self.pdfExportGeneration
        && [self.pdfExportDOMSnapshot isEqualToString:[[self.pdfExportOriginalContext
            evaluateScript:kMPPDFSnapshotJS] toString]];
}

- (void)publishPDFDocument:(PDFDocument *)document atURL:(NSURL *)url
{
    NSData *data = document.dataRepresentation;
    NSError *error = nil;
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error])
        self.pdfExportError = error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
}

- (void)postProcessExportedPDFAtURL:(NSURL *)url
{
    PDFDocument *original = [[PDFDocument alloc] initWithURL:self.pdfExportTemporaryURL];
    if (!original || ![self PDFExportSnapshotIsCurrent]) {
        self.pdfExportError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
            userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"The preview changed during PDF export.", nil)}];
        return;
    }
    BOOL hasAnchors = [[self.pdfExportOriginalContext evaluateScript:
        @"!!document.querySelector('a[href^=\"#\"]:not([href=\"#\"])')"] toBool];
    if (!hasAnchors) {
        [self publishPDFDocument:original atURL:url];
        return;
    }
    self.pdfExportMetadataURL = [self.pdfExportTemporaryURL.URLByDeletingLastPathComponent
        URLByAppendingPathComponent:[NSString stringWithFormat:@".macdown-anchors-%@.pdf", NSUUID.UUID.UUIDString]];
    NSDictionary *session = nil;
    BOOL printed = NO;
    BOOL metadataUnchanged = NO;
    @try {
        if (![self preparePDFAnchorSession]) return;
        session = self.pdfExportAnchorSession;
        NSString *preparedSnapshot = [[self.pdfExportOriginalContext evaluateScript:kMPPDFSnapshotJS] toString];
        NSPrintInfo *info = [self.pdfExportPrintInfo copy];
        info.dictionary[NSPrintJobSavingURL] = self.pdfExportMetadataURL;
        NSPrintOperation *operation = [self.preview.mainFrame.frameView printOperationWithPrintInfo:info];
        operation.showsPrintPanel = NO;
        operation.showsProgressPanel = NO;
        printed = [operation runOperation];
        metadataUnchanged = [preparedSnapshot isEqualToString:
            [[self.pdfExportOriginalContext evaluateScript:kMPPDFSnapshotJS] toString]];
    } @finally {
        [self restorePDFAnchorSession];
    }
    PDFDocument *metadata = printed ? [[PDFDocument alloc] initWithURL:self.pdfExportMetadataURL] : nil;
    if (!metadata || !metadataUnchanged || ![self PDFExportSnapshotIsCurrent]) {
        self.pdfExportError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
            userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"The preview changed during PDF export.", nil)}];
        return;
    }
    NSError *error = nil;
    [MPPDFAnchorInjector resolveNativeLinksInDocument:original metadataDocument:metadata
        markerPrefix:session[@"prefix"] linkTargets:session[@"links"] headingSlugs:session[@"headings"] error:&error];
    if (error) { self.pdfExportError = error; return; }
    [self publishPDFDocument:original atURL:url];
}

- (IBAction)convertToH1:(id)sender
{
    [self convertSelectionToBlock:@"h1"];
}

- (IBAction)convertToH2:(id)sender
{
    [self convertSelectionToBlock:@"h2"];
}

- (IBAction)convertToH3:(id)sender
{
    [self convertSelectionToBlock:@"h3"];
}

- (IBAction)convertToH4:(id)sender
{
    [self convertSelectionToBlock:@"h4"];
}

- (IBAction)convertToH5:(id)sender
{
    [self convertSelectionToBlock:@"h5"];
}

- (IBAction)convertToH6:(id)sender
{
    [self convertSelectionToBlock:@"h6"];
}

- (IBAction)convertToParagraph:(id)sender
{
    [self convertSelectionToBlock:@"paragraph"];
}

- (IBAction)resetToNormalText:(id)sender
{
    if ([self performPreviewFormattingAction:@"block" value:@"paragraph"]) {
        [self performPreviewFormattingAction:@"clear" value:nil];
        return;
    }
    if (self.documentClosed || self.printing || [self previewDraft]) return;
    NSRange selection=self.editor.selectedRange;
    if (selection.location>self.editor.string.length) return;
    if (!selection.length) self.editor.selectedRange=[self.editor.string lineRangeForRange:selection];
    [self convertSelectionToBlock:@"paragraph"];
    if (self.editor.selectedRange.length && ![self formatSourceInlineAction:@"clear" value:nil]) NSBeep();
}

// Native source selections and rendered selections share the same proven
// inline transaction. An empty source caret is an explicit syntax insertion,
// never a fallback when a selected passage cannot be represented safely.
- (BOOL)formatSourceInlineAction:(NSString *)action value:(NSString *)value
{
    if (self.documentClosed || self.printing || [self previewDraft]) return NO;
    NSString *source=self.editor.string ?: @"";
    NSRange selection=self.editor.selectedRange;
    if (selection.location>source.length || selection.length>source.length-selection.location) return NO;
    if ([action isEqualToString:@"strike"] && !self.preferences.extensionStrikethough) return NO;
    if (!selection.length) {
        NSDictionary *markers=@{@"bold":@"**",@"italic":@"*",@"underline":@"_",@"strike":@"~~",@"code":@"`"};
        NSString *marker=markers[action];
        if (!marker) return NO;
        if ([action isEqualToString:@"underline"]) self.preferences.extensionUnderline=YES;
        [self.editor toggleForMarkupPrefix:marker suffix:marker];
        return YES;
    }
    BOOL oldIntra=self.preferences.extensionIntraEmphasis, oldUnderline=self.preferences.extensionUnderline;
    self.preferences.extensionIntraEmphasis=YES;
    if ([action isEqualToString:@"underline"]) self.preferences.extensionUnderline=YES;
    MPRenderer *snapshot=[MPRenderer new]; snapshot.delegate=(id<MPRendererDelegate>)self;
    snapshot.rendererFlags=self.preferences.rendererFlags;
    NSString *(^render)(NSString *)=^NSString *(NSString *markdown){return [snapshot HTMLForMarkdownSnapshot:markdown];};
    NSString *(^escape)(NSString *)=^NSString *(NSString *text){return [self escapePreviewPlainText:text];};
    NSDictionary *change=MPPreviewInlineChange(source,selection,action,value,render,escape);
    if (!change) change=MPPreviewInlineSingleChange(source,selection,action,value,render,escape,@"auto");
    if (change && [self replacePreviewRange:[change[@"range"] rangeValue] withString:change[@"replacement"]
        preservingSelection:selection restoringRange:[change[@"selection"] rangeValue]]) {
        // Source focus notifications can clear preview restoration during the
        // replacement. The transaction owns the exact inline selection, so
        // restore it directly instead of depending on that transient DOM state.
        NSRange replacementRange=[change[@"range"] rangeValue];
        NSRange retained=[change[@"selection"] rangeValue];
        self.editor.selectedRange=NSMakeRange(replacementRange.location+retained.location,retained.length);
        self.previewSelectionToRestore=nil;
        return YES;
    }
    self.preferences.extensionIntraEmphasis=oldIntra; self.preferences.extensionUnderline=oldUnderline;
    return NO;
}

- (IBAction)toggleStrong:(id)sender
{
    if ([self performPreviewFormattingAction:@"bold" value:nil]) return;
    if (![self formatSourceInlineAction:@"bold" value:nil]) NSBeep();
}

- (IBAction)toggleEmphasis:(id)sender
{
    if ([self performPreviewFormattingAction:@"italic" value:nil]) return;
    if (![self formatSourceInlineAction:@"italic" value:nil]) NSBeep();
}

- (IBAction)toggleInlineCode:(id)sender
{
    if ([self performPreviewFormattingAction:@"code" value:nil]) return;
    if (![self formatSourceInlineAction:@"code" value:nil]) NSBeep();
}

- (IBAction)toggleStrikethrough:(id)sender
{
    if ([self performPreviewFormattingAction:@"strike" value:nil]) return;
    if (![self formatSourceInlineAction:@"strike" value:nil]) NSBeep();
}

- (IBAction)toggleUnderline:(id)sender
{
    if ([self performPreviewFormattingAction:@"underline" value:nil]) return;
    // The explicit underline action opts into the renderer's Markdown syntax.
    if (![self formatSourceInlineAction:@"underline" value:nil]) NSBeep();
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
    if (self.documentClosed || self.printing) return;
    BOOL previewFocused=[self previewHasFindFocus];
    NSString *source=self.editor.string.copy;
    NSRange selection=self.editor.selectedRange;
    if (previewFocused) {
        JSValue *function=self.preview.mainFrame.javaScriptContext[@"window"][@"macdownPreviewEditor"][@"selectionPayload"];
        NSDictionary *payload=[[function callWithArguments:@[@"link",NSNull.null]] toDictionary];
        NSDictionary *verified=[self verifiedPreviewSelection:payload];
        if (!verified || verified[@"codeBlockRange"]) {NSBeep();return;}
    }
    NSAlert *alert=[NSAlert new];
    alert.messageText=NSLocalizedString(@"Link",@"");
    alert.informativeText=NSLocalizedString(@"Link address (https://…)",@"");
    [alert addButtonWithTitle:NSLocalizedString(@"Apply",@"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,360,24)];
    field.stringValue=@"https://"; alert.accessoryView=field;
    alert.window.initialFirstResponder=field;
    if ([alert runModal]!=NSAlertFirstButtonReturn || ![source isEqualToString:self.editor.string]) return;
    NSString *value=field.stringValue;
    if (previewFocused) {
        if ([self previewHasFindFocus]) [self performPreviewFormattingAction:@"link" value:value];
        return;
    }
    if (!NSEqualRanges(selection,self.editor.selectedRange)) return;
    if (!selection.length) {
        NSURL *url=MPPIValidatedLinkURL(value);
        if (!url) {NSBeep();return;}
        [self.editor toggleForMarkupPrefix:@"[" suffix:[NSString stringWithFormat:@"](<%@>)",url.absoluteString]];
    } else if (![self formatSourceInlineAction:@"link" value:value]) NSBeep();
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
    return [self tableInsertionForContent:content selectedRange:selectedRange columns:3 rows:2
                        replacementRange:outReplacementRange caretLocation:outCaretLocation];
}

+ (NSString *)tableInsertionForContent:(NSString *)content selectedRange:(NSRange)selectedRange
                               columns:(NSUInteger)columns rows:(NSUInteger)rows
                      replacementRange:(NSRange *)outReplacementRange caretLocation:(NSUInteger *)outCaretLocation
{
    if (columns<1 || columns>8 || rows<1 || rows>8) return nil;
    NSMutableString *core=[NSMutableString stringWithString:@"|"];
    NSString *headingFormat=NSLocalizedString(@"Column %lu", @"Default Markdown table heading; %lu is the column number.");
    for (NSUInteger column=1;column<=columns;column++) {
        NSString *heading=[NSString stringWithFormat:headingFormat,(unsigned long)column];
        [core appendFormat:@" %@ |",heading];
    }
    [core appendString:@"\n|"];
    for (NSUInteger column=0;column<columns;column++) [core appendString:@" :---: |"];
    NSUInteger caretOffsetInCore=2;
    for (NSUInteger row=1;row<rows;row++) {
        [core appendString:@"\n|"];
        if (row==1) caretOffsetInCore=core.length+1;
        for (NSUInteger column=0;column<columns;column++) [core appendString:@"  |"];
    }

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
    [self insertTableWithColumns:3 rows:2];
}

- (void)insertTableWithColumns:(NSUInteger)columns rows:(NSUInteger)rows
{
    if (self.documentClosed || self.printing || [self previewDraft]) return;
    NSString *content = self.editor.string ?: @"";
    NSRange replacementRange = NSMakeRange(0, 0);
    NSUInteger caretLocation = 0;
    NSString *inserted =
        [MPDocument tableInsertionForContent:content
                               selectedRange:self.editor.selectedRange columns:columns rows:rows
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
    if (!inserted || ![self.editor shouldChangeTextInRange:replacementRange
                            replacementString:inserted])
        return;
    [self.editor.textStorage replaceCharactersInRange:replacementRange
                                           withString:inserted];
    [self.editor didChangeText];
    self.editor.selectedRange = NSMakeRange(caretLocation, 0);
    [self.editor scrollRangeToVisible:self.editor.selectedRange];
}

// The native source adapter must prove code context in the complete document,
// rather than interpreting a literal code line as an isolated Markdown title.
// Empty metadata means prose; nil means an opaque/unrepresentable code edit.
- (NSDictionary *)sourceCodeMetadataForSelection:(NSRange)selection source:(NSString *)source renderer:(MPRenderer *)renderer
{
    NSString *begin=[NSString stringWithFormat:@"\uE000%@\uE001",NSUUID.UUID.UUIDString];
    NSString *finish=[NSString stringWithFormat:@"\uE002%@\uE003",NSUUID.UUID.UUIDString];
    NSMutableString *probe=[source mutableCopy];
    [probe insertString:finish atIndex:NSMaxRange(selection)];
    [probe insertString:begin atIndex:selection.location];
    NSString *HTML=[renderer HTMLForMarkdownSnapshot:probe];
    NSXMLDocument *DOM=MPPIParseHTML(HTML);
    if (!DOM) return nil;
    NSString *either=[NSString stringWithFormat:@"//pre[contains(string(.),'%@') or contains(string(.),'%@')]",begin,finish];
    NSArray *marked=[DOM nodesForXPath:either error:NULL];
    if (!marked.count) return @{};
    NSString *both=[NSString stringWithFormat:@"//pre/code[contains(string(.),'%@') and contains(string(.),'%@')]",begin,finish];
    NSArray *codes=[DOM nodesForXPath:both error:NULL];
    if (marked.count!=1 || codes.count!=1 || !self.preferences.extensionFencedCode ||
        [[codes.firstObject nodesForXPath:@"ancestor::blockquote|ancestor::li" error:NULL] count]) return nil;
    NSString *withoutMarkers=[[HTML stringByReplacingOccurrencesOfString:begin withString:@""]
        stringByReplacingOccurrencesOfString:finish withString:@""];
    NSArray *original=MPPIFingerprint([renderer HTMLForMarkdownSnapshot:source]);
    if (!original || ![MPPIFingerprint(withoutMarkers) isEqual:original]) return nil;
    NSUInteger opening=NSNotFound,contentStart=0,fenceWidth=0;
    unichar fenceCharacter=0;
    BOOL linear=NO;
    for (NSUInteger offset=0;offset<source.length;) {
        NSUInteger start,end,contentsEnd;
        [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
        NSString *line=[source substringWithRange:NSMakeRange(start,contentsEnd-start)];
        unichar marker=0; NSUInteger width=0; BOOL trailing=NO;
        BOOL fence=MPScanFenceMarker(line,&marker,&width,&trailing);
        offset=end;
        if (opening==NSNotFound) {
            if (fence) {
                opening=start;contentStart=end;fenceWidth=width;fenceCharacter=marker;
                linear=line.length && [line characterAtIndex:0]==marker;
            }
            continue;
        }
        if (!fence || marker!=fenceCharacter || width<fenceWidth || trailing) continue;
        NSRange block=NSMakeRange(opening,end-opening),content=NSMakeRange(contentStart,start-contentStart);
        opening=NSNotFound;
        if (selection.location<content.location || NSMaxRange(selection)>NSMaxRange(content)) continue;
        if (!linear) return nil;
        // Prove this physical fence pair owns the selected CODE, including
        // all unselected literal body text, before exposing its source ranges.
        NSString *literal=[source substringWithRange:content];
        NSString *normalized=[[literal stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
            stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
        if (![normalized hasSuffix:@"\n"]) return nil;
        normalized=[normalized substringToIndex:normalized.length-1];
        NSString *rendered=[[codes.firstObject stringValue] stringByReplacingOccurrencesOfString:begin withString:@""];
        rendered=[rendered stringByReplacingOccurrencesOfString:finish withString:@""];
        if (![rendered isEqualToString:normalized]) return nil;
        return @{@"codeBlockRange":[NSValue valueWithRange:block],@"codeContentRange":[NSValue valueWithRange:content]};
    }
    return nil;
}

- (void)convertSelectionToBlock:(NSString *)value
{
    if ([self performPreviewFormattingAction:@"block" value:value]) return;
    if (self.documentClosed || self.printing || [self previewDraft]) { NSBeep(); return; }
    NSString *source=self.editor.string ?: @"";
    NSRange selection=self.editor.selectedRange;
    if (selection.location>source.length || selection.length>source.length-selection.location) return;
    NSRange lines=[source lineRangeForRange:selection];
    NSMutableArray *runs=[NSMutableArray array];
    for (NSUInteger offset=lines.location;offset<NSMaxRange(lines);) {
        NSUInteger start,end,contentsEnd;
        [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
        NSRange contents=NSMakeRange(start,contentsEnd-start);
        NSRange run=selection.length ? NSIntersectionRange(selection,contents) : contents;
        if (run.length) [runs addObject:[NSValue valueWithRange:run]];
        offset=end;
    }
    if (!runs.count) [runs addObject:[NSValue valueWithRange:selection]];
    NSMutableDictionary *verified=[@{@"range":[NSValue valueWithRange:selection],@"runs":runs,@"text":[source substringWithRange:selection]} mutableCopy];
    // Parse a separate snapshot; source edits must not invalidate the identities
    // and mappings still published in the visible preview.
    MPRenderer *snapshot=[MPRenderer new];
    snapshot.delegate=(id<MPRendererDelegate>)self;
    snapshot.rendererFlags=self.preferences.rendererFlags;
    NSDictionary *codeMetadata=[self sourceCodeMetadataForSelection:selection source:source renderer:snapshot];
    if (!codeMetadata) { NSBeep(); return; }
    [verified addEntriesFromDictionary:codeMetadata];
    NSArray *callouts=[snapshot calloutSourceEntriesForMarkdownSnapshot:source];
    if (![self applyBlockFormattingValue:value selection:verified callouts:callouts renderer:snapshot]) { NSBeep(); return; }
    NSDictionary *restored=self.previewSelectionToRestore;
    if (restored) self.editor.selectedRange=NSMakeRange([restored[@"location"] unsignedIntegerValue],[restored[@"length"] unsignedIntegerValue]);
    self.previewSelectionToRestore=nil;
}

- (IBAction)toggleOrderedList:(id)sender
{
    [self convertSelectionToBlock:@"ordered"];
}

- (IBAction)toggleUnorderedList:(id)sender
{
    [self convertSelectionToBlock:@"unordered"];
}

- (IBAction)toggleTaskList:(id)sender
{
    [self convertSelectionToBlock:@"tasks"];
}

- (IBAction)convertToCodeBlock:(id)sender
{
    [self convertSelectionToBlock:@"code-block"];
}

- (IBAction)toggleBlockquote:(id)sender
{
    [self convertSelectionToBlock:@"quote"];
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
        // NSMakeRange(NSNotFound, 0) is Apple's documented sentinel for
        // -insertText:replacementRange: meaning "use the current selection,
        // or the marked (IME composition) range if there is one" -- the
        // same behavior the deprecated 1-arg -insertText: had.
        [self.editor insertText:@"\n\n"
               replacementRange:NSMakeRange(NSNotFound, 0)];
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
    self.currentPreviewResourceHTML = nil;
}

/**
 * Defers an operation until after the WebView finishes rendering.
 * Issue #16: When preview is hidden, HTML/PDF export and print operations
 * would use stale content. This method queues the handler and triggers
 * a render if needed, executing the handler once rendering completes.
 *
 * Visibility does not imply freshness: always request a render and await completion.
 */
- (BOOL)performAfterRender:(void (^)(void))handler
{
    if (!handler || self.documentClosed || ![self flushPreviewEditor]) return NO;

    if (!self.renderCompletionHandlers)
        self.renderCompletionHandlers = [NSMutableArray array];

    [self.renderCompletionHandlers addObject:[handler copy]];

    // Only trigger render if this is the first queued handler
    // (subsequent handlers will be executed when the render completes)
    if (self.renderCompletionHandlers.count == 1)
    {
        self.awaitingRequestedRender = YES;
        [self.renderer parseAndRenderNow];
    }
    return YES;
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
        int extensions = pmh_EXT_NONE;
        if (self.preferences.extensionFootnotes)
            extensions |= pmh_EXT_NOTES;
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
            self.editorPaddingBottom.constant = self.preferences.editorShowReadingProgress ? 35.0 : 0.0;
            // Issue #452: Reset selection mode so re-enabling starts on totals.
            self.showingSelectionCount = NO;
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorShowReadingProgress"] ||
        [changedKey isEqualToString:@"editorShowWordCount"])
    {
        self.editorPaddingBottom.constant =
            (self.preferences.editorShowWordCount || self.preferences.editorShowReadingProgress) ? 35.0 : 0.0;
        [self setupReadingProgress];
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
    JSValue *editor=self.preview.mainFrame.javaScriptContext[@"window"][@"macdownPreviewEditor"];
    if (editor && !editor.isUndefined && !editor.isNull) {
        JSValue *update=editor[@"setPreviewScale"];
        if (update && !update.isUndefined && !update.isNull)
            [update callWithArguments:@[@(scale)]];
    }
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
    self.zoomMultiplier = 1.0;
}

- (void)applyCurrentZoom
{
    // Highlighting stores the base font and builds theme fonts from it. Refresh
    // both caches through the font setup path before the next edit can reapply
    // the previous zoom. That path also updates the preview scale.
    [self setupEditor:@"editorBaseFontInfo"];
}

// A single batched parser probe ties every visible fenced-code line, including
// nested lists/quotes, to its physical source occurrence. Editing permissions
// remain independent: this mapping is used only for scroll geometry.
- (NSArray<NSDictionary *> *)scrollCodeLinesForSource:(NSString *)source context:(JSContext *)context
{
    NSRegularExpression *fence=[NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(?:>[ \\t]*)*(?:[-+*][ \\t]+|[0-9]+[.)][ \\t]+)?(`{3,}|~{3,})(.*)$" options:0 error:NULL];
    NSString *prefix=[@"MPSCROLL" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSMutableString *marked=[source mutableCopy];
    NSMutableArray<NSNumber *> *positions=[NSMutableArray array];
    NSUInteger width=0; unichar character=0;
    for (NSUInteger offset=0;offset<source.length;) {
        NSUInteger start,end,contentsEnd;
        [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
        NSString *line=[source substringWithRange:NSMakeRange(start,contentsEnd-start)];
        NSTextCheckingResult *match=[fence firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        offset=end;
        if (match) {
            NSString *marker=[line substringWithRange:[match rangeAtIndex:1]];
            NSString *trailing=[line substringWithRange:[match rangeAtIndex:2]];
            if (!width) {width=marker.length;character=[marker characterAtIndex:0];continue;}
            if ([marker characterAtIndex:0]==character && marker.length>=width &&
                ![trailing stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) {width=0;continue;}
        }
        if (width && [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length)
            [positions addObject:@(contentsEnd)];
    }
    if (!positions.count) return @[];
    for (NSNumber *position in positions.reverseObjectEnumerator)
        [marked insertString:[NSString stringWithFormat:@"%@%@END",prefix,position] atIndex:position.unsignedIntegerValue];
    context[@"__mpScrollProbeHTML"]=[self.renderer HTMLForMarkdownSnapshot:marked];
    context[@"__mpScrollProbePrefix"]=prefix;
    NSArray *lines=[[context evaluateScript:@"(function(){var d=new DOMParser().parseFromString(__mpScrollProbeHTML,'text/html'),codes=Array.from(d.querySelectorAll('pre>code')),live=Array.from(document.querySelectorAll('pre>code')),result=[],pattern=new RegExp(__mpScrollProbePrefix+'([0-9]+)END','g');if(codes.length!==live.length)return [];for(var i=0;i<codes.length;i++){var text=codes[i].textContent,plain='',cursor=0,m,entries=[];pattern.lastIndex=0;while(m=pattern.exec(text)){plain+=text.substring(cursor,m.index);var start=plain.lastIndexOf('\\n')+1;entries.push({code:i,end:Number(m[1]),start:start,text:plain.substring(start)});cursor=pattern.lastIndex;}plain+=text.substring(cursor);if(plain!==live[i].textContent)return [];result=result.concat(entries);}return result;})()"] toArray];
    [context evaluateScript:@"delete __mpScrollProbeHTML;delete __mpScrollProbePrefix;"];
    NSMutableArray *result=[NSMutableArray array];
    for (NSDictionary *line in lines) {
        NSString *text=line[@"text"];
        NSUInteger end=[line[@"end"] unsignedIntegerValue];
        if (!text.length || end>source.length || text.length>end ||
            ![[source substringWithRange:NSMakeRange(end-text.length,text.length)] isEqualToString:text]) continue;
        [result addObject:@{@"code":line[@"code"],@"start":line[@"start"],@"location":@(end-text.length),@"length":@(text.length)}];
    }
    return result;
}

- (BOOL)updateSourceScrollLocations
{
    if (![self.previewEditSource isEqualToString:self.editor.string] ||
        ![self.previewEditToken isEqualToString:self.renderer.checkboxBridgeToken]) return NO;
    NSLayoutManager *layout=self.editor.layoutManager;
    NSTextContainer *container=self.editor.textContainer;
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *runs=[NSMutableArray array];
    for (NSUInteger i=0;i<self.previewEditRanges.count;i++) {
        NSDictionary *entry=self.previewEditRanges[i];
        if (entry[@"codeBlockRange"]) continue;
        NSMutableDictionary *run=[@{@"id":@(i),@"location":entry[@"location"],@"length":entry[@"length"]} mutableCopy];
        if (entry[@"sourceBoundaries"]) run[@"sourceBoundaries"]=entry[@"sourceBoundaries"];
        [runs addObject:run];
    }
    [runs addObjectsFromArray:self.previewScrollCodeLines ?: @[]];
    [runs sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"location"] compare:b[@"location"]];}];
    NSMutableArray *probes=[NSMutableArray array];
    for (NSDictionary *run in runs) {
        NSRange range=NSMakeRange([run[@"location"] unsignedIntegerValue],[run[@"length"] unsignedIntegerValue]);
        if (!range.length || NSMaxRange(range)>self.editor.string.length) continue;
        NSRange glyphs=[layout glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        [layout enumerateLineFragmentsForGlyphRange:glyphs usingBlock:^(NSRect rect,NSRect used,NSTextContainer *textContainer,NSRange lineGlyphs,BOOL *stop){
            NSRange chars=[layout characterRangeForGlyphRange:NSIntersectionRange(glyphs,lineGlyphs) actualGlyphRange:NULL];
            NSUInteger location=MAX(range.location,chars.location);
            if (location>=NSMaxRange(range)) return;
            NSMutableDictionary *probe=[run mutableCopy];
            NSUInteger offset=location-range.location+[run[@"start"] unsignedIntegerValue];
            NSArray<NSNumber *> *boundaries=run[@"sourceBoundaries"];
            if (boundaries) {
                if (boundaries.count<2) return;
                // Decoded entities and escaped punctuation occupy fewer DOM
                // characters than source characters. Use the proven boundary map.
                NSUInteger low=0,high=boundaries.count;
                while (low<high) {
                    NSUInteger middle=low+(high-low)/2;
                    if (boundaries[middle].unsignedIntegerValue<location) low=middle+1;else high=middle;
                }
                if (low>=boundaries.count-1) return;
                offset=low;
            }
            [probe removeObjectForKey:@"sourceBoundaries"];
            probe[@"offset"]=@(offset);
            probe[@"editorY"]=@(NSMidY(rect)+self.editor.textContainerOrigin.y);
            [probes addObject:probe];
        }];
    }
    JSContext *context=self.preview.mainFrame.javaScriptContext;
    JSValue *bridge=context[@"window"][@"macdownPreviewEditor"];
    if (!bridge.isObject) return NO;
    JSValue *positions=[bridge invokeMethod:@"scrollPositions" withArguments:@[probes]];
    NSArray *ys=positions.isArray ? positions.toArray : nil;
    if (ys.count!=probes.count) return NO;
    NSMutableArray *editorYs=[NSMutableArray array],*previewYs=[NSMutableArray array];
    CGFloat lastEditor=-CGFLOAT_MAX,lastPreview=-CGFLOAT_MAX;
    CGFloat scale=self.preview.pageSizeMultiplier;
    for (NSUInteger i=0;i<ys.count;i++) {
        if (![ys[i] isKindOfClass:NSNumber.class]) continue;
        CGFloat e=[probes[i][@"editorY"] doubleValue],p=[ys[i] doubleValue]*scale;
        if (!isfinite(e) || !isfinite(p) || e<lastEditor || p<lastPreview) continue;
        // Keep one bijective anchor for a visual row. Multiple inline leaves
        // and unequal wrapping must not produce zero-width interpolation spans.
        if (e-lastEditor<0.5 || p-lastPreview<0.5) continue;
        [editorYs addObject:@(e)];[previewYs addObject:@(p)];lastEditor=e;lastPreview=p;
    }
    if (editorYs.count<2) return NO;
    _editorHeaderLocations=editorYs;_webViewHeaderLocations=previewYs;
    self.sourceScrollLocations=YES;
    return YES;
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
    if ([self updateSourceScrollLocations]) return;
    self.sourceScrollLocations = NO;
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
 * Issue #436: Classifies the reference points (ATX/setext headers, standalone images,
 * paragraphs, and list items) in a markdown string, returning their kind codes (see
 * MPReferenceKind) in document order, with the matching source line numbers via
 * outLineNumbers. This mirrors the DOM detection in updateHeaderLocations.js so the
 * editor and preview sequences agree:
 *
 *   - Headers inside fenced code blocks (``` or ~~~) are skipped — the DOM renders them
 *     as <pre><code>, not <hN>.
 *   - Setext headers are detected for both '===' (level 1) and '---' (level 2).
 *   - ATX headers with 7+ hashes are not headers (CommonMark §4.2; Hoedown emits no <hN>),
 *     so they are treated as ordinary paragraph text.
 *   - Standalone whole-line images (inline or reference syntax) are kind 0.
 *   - List item marker lines (unordered: '-'/'*'/'+'; ordered: digits followed by '.'
 *     or ')') are kind 8, one reference point per marker line — continuation lines of
 *     a multi-line list item are not additional reference points.
 *   - The first line of each paragraph (a maximal run of non-blank, non-header,
 *     non-list-item, non-HR, non-fence lines) is kind 7 — one reference point per
 *     rendered <p>, matching how Hoedown collapses a contiguous run of text lines into
 *     a single paragraph. A text line immediately followed by a setext underline is
 *     NOT also emitted as a paragraph, since it becomes a header instead; committing
 *     it is deferred via pendingParagraphLine until the following line is examined.
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
    static NSRegularExpression *ulRegex = nil;     // unordered list item marker
    static NSRegularExpression *olRegex = nil;     // ordered list item marker
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
        // Bullet marker + required space + content.
        ulRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ ]{0,3}[-*+][ \\t]+\\S" options:0 error:NULL];
        // Number (1-9 digits) + '.' or ')' + required space + content.
        olRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ ]{0,3}[0-9]{1,9}[.)][ \\t]+\\S" options:0 error:NULL];
    });

    NSArray<NSString *> *lines = [markdown componentsSeparatedByString:@"\n"];

    // Setext underlines attach to a *paragraph* line. previousLineHadContent is true only
    // after ordinary text — not after blanks, headers, HRs, images, list items, or fence
    // lines — so e.g. "# H\n---" is an ATX header followed by an HR, not a setext header.
    BOOL previousLineHadContent = NO;

    // The most recently seen paragraph-start line, not yet committed as a reference
    // point: since a text line immediately followed by a setext underline becomes a
    // header (not a paragraph), committing a candidate paragraph start is deferred
    // until the following line is known not to be a setext underline for it.
    __block BOOL hasPendingParagraphLine = NO;
    __block NSUInteger pendingParagraphLine = 0;

    // Once a list-item marker line is seen, subsequent non-blank lines are treated as
    // continuation lines of that same item (not a new paragraph) until a blank line (or
    // another marker/header/image/HR/fence) ends the run. This keeps a multi-line list
    // item from spawning a spurious paragraph reference point for its continuation text.
    BOOL insideListItemContinuation = NO;

    // Fenced-code-block state. CommonMark: a fence opens with 3+ of ` or ~ (0-3 leading
    // spaces) and closes with a run of the same character at least as long, with nothing
    // but whitespace after it. A backtick fence's info string may not contain backticks.
    BOOL insideFence = NO;
    unichar fenceChar = 0;
    NSUInteger fenceLength = 0;

    // Commits any pending (tentative) paragraph-start line as a real reference point.
    // Called whenever the next line turns out NOT to be a setext underline for it.
    void (^commitPendingParagraph)(void) = ^{
        if (hasPendingParagraphLine) {
            [kinds addObject:@(MPReferenceKindParagraph)];
            [lineNumbers addObject:@(pendingParagraphLine)];
            hasPendingParagraphLine = NO;
        }
    };

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
            commitPendingParagraph();
            insideListItemContinuation = NO;
            if (isFenceMarker && markerChar == fenceChar
                    && markerLength >= fenceLength && !hasTrailingContent) {
                insideFence = NO;
            }
            previousLineHadContent = NO;
            continue;
        }

        if (isFenceMarker) {
            // Opens a fence. The opening line itself is never a reference point.
            commitPendingParagraph();
            insideListItemContinuation = NO;
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
                commitPendingParagraph();
                insideListItemContinuation = NO;
                [kinds addObject:@((NSInteger)hashCount)];
                [lineNumbers addObject:@(lineNumber)];
                previousLineHadContent = NO;
                continue;
            }
            // 7+ hashes: ordinary paragraph text, which can still anchor a setext header.
            if (!hasPendingParagraphLine && !previousLineHadContent) {
                hasPendingParagraphLine = YES;
                pendingParagraphLine = lineNumber;
            }
            previousLineHadContent = YES;
            continue;
        }

        // Setext underline (only valid directly under a paragraph line). The pending
        // paragraph line (if any) is the line this underline attaches to; it becomes a
        // header instead of a paragraph, so drop the pending candidate without committing.
        if (previousLineHadContent
                && [eqRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            hasPendingParagraphLine = NO;
            insideListItemContinuation = NO;
            [kinds addObject:@(MPReferenceKindH1)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }
        if (previousLineHadContent
                && [dashRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            hasPendingParagraphLine = NO;
            insideListItemContinuation = NO;
            [kinds addObject:@(MPReferenceKindH2)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }

        // Standalone whole-line image.
        if ([imgRegex numberOfMatchesInString:line options:0 range:full] > 0
                || [imgRefRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            commitPendingParagraph();
            insideListItemContinuation = NO;
            [kinds addObject:@(MPReferenceKindImage)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }

        // Thematic break: not a reference point, and not paragraph text either.
        if ([hrRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            commitPendingParagraph();
            insideListItemContinuation = NO;
            previousLineHadContent = NO;
            continue;
        }

        // Blank line breaks any setext context, any paragraph run, and any list-item
        // continuation run.
        if ([[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
            commitPendingParagraph();
            insideListItemContinuation = NO;
            previousLineHadContent = NO;
            continue;
        }

        // List item marker line: takes precedence over both paragraph and setext-header
        // eligibility (CommonMark does not allow a setext heading to consume a list-item
        // line). One reference point per marker line; continuation lines of the same item
        // are ordinary text lines that don't match the marker pattern, so they fall
        // through below and are tracked via insideListItemContinuation instead.
        if ([ulRegex numberOfMatchesInString:line options:0 range:full] > 0
                || [olRegex numberOfMatchesInString:line options:0 range:full] > 0) {
            commitPendingParagraph();
            insideListItemContinuation = YES;
            [kinds addObject:@(MPReferenceKindListItem)];
            [lineNumbers addObject:@(lineNumber)];
            previousLineHadContent = NO;
            continue;
        }

        // A continuation line of the immediately preceding list item (e.g. an indented
        // wrapped line) is not a separate reference point and does not start a new
        // paragraph run.
        if (insideListItemContinuation) {
            previousLineHadContent = YES;
            continue;
        }

        // Ordinary paragraph text that can anchor a setext underline. Only the FIRST
        // line of a paragraph run becomes a tentative reference point; continuation
        // lines (previousLineHadContent already YES) do not add another one.
        if (!hasPendingParagraphLine && !previousLineHadContent) {
            hasPendingParagraphLine = YES;
            pendingParagraphLine = lineNumber;
        }
        previousLineHadContent = YES;
    }

    // End of document: any still-pending paragraph line was never followed by a setext
    // underline, so commit it now.
    commitPendingParagraph();

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
 * sequences (matching on a coarse class — image, any header level, paragraph, or list
 * item, since the two sides legitimately disagree on exact header level but must never
 * cross-match a paragraph against a header, or a list item against either) and keeps
 * only the matched points on each side. An unmatched point is dropped from whichever
 * side it appears on, so the remaining points stay aligned regardless of where the
 * divergence occurs.
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

    // Coarse class for matching: images match images, any header matches any header,
    // paragraphs match only paragraphs, and list items match only list items — each
    // gets its own class so the LCS never cross-matches, e.g., a paragraph against a
    // header just because the coarser image-vs-everything-else split would have allowed it.
    NSInteger (^classOf)(NSNumber *) = ^NSInteger(NSNumber *kind) {
        NSInteger k = kind.integerValue;
        if (k == MPReferenceKindImage) return 0;
        if (k == MPReferenceKindParagraph) return 2;
        if (k == MPReferenceKindListItem) return 3;
        return 1; // any header level h1-h6
    };

    NSUInteger m = editorCount, n = previewCount;
    NSMutableArray<NSNumber *> *alignedEditor = [NSMutableArray array];
    NSMutableArray<NSNumber *> *alignedPreview = [NSMutableArray array];

    // Most edits preserve the type sequence. Avoid building a quadratic matrix.
    BOOL identical = m == n;
    for (NSUInteger k = 0; identical && k < m; k++)
        identical = classOf(editorTypes[k]) == classOf(previewTypes[k]);
    if (identical)
    {
        if (outEditorYs) *outEditorYs = [editorYs copy];
        if (outPreviewYs) *outPreviewYs = [previewYs copy];
        return;
    }

    // Bound main-thread work and memory (at most 8 MiB). For larger documents,
    // retain monotonic, class-compatible anchors with a linear greedy fallback.
    const NSUInteger maxCells = 1024 * 1024;
    NSUInteger *dp = NULL;
    if (m < maxCells && n < maxCells && (m + 1) <= maxCells / (n + 1))
        dp = calloc((m + 1) * (n + 1), sizeof(NSUInteger));
    if (dp)
    {
        NSUInteger stride = n + 1;
        for (NSUInteger ii = m; ii > 0; ii--)
            for (NSUInteger jj = n; jj > 0; jj--)
            {
                NSUInteger i = ii - 1, j = jj - 1;
                dp[i * stride + j] = classOf(editorTypes[i]) == classOf(previewTypes[j]) ?
                    dp[(i + 1) * stride + j + 1] + 1 :
                    MAX(dp[(i + 1) * stride + j], dp[i * stride + j + 1]);
            }
        NSUInteger i = 0, j = 0;
        while (i < m && j < n)
        {
            if (classOf(editorTypes[i]) == classOf(previewTypes[j]))
            {
                [alignedEditor addObject:editorYs[i++]];
                [alignedPreview addObject:previewYs[j++]];
            }
            else if (dp[(i + 1) * stride + j] >= dp[i * stride + j + 1]) i++;
            else j++;
        }
        free(dp);
    }
    else
    {
        NSMutableArray<NSMutableArray<NSNumber *> *> *positions = [NSMutableArray array];
        for (NSUInteger k = 0; k < 4; k++) [positions addObject:[NSMutableArray array]];
        for (NSUInteger j = 0; j < n; j++) [positions[classOf(previewTypes[j])] addObject:@(j)];
        NSUInteger cursors[4] = {0};
        NSUInteger nextPreview = 0;
        for (NSUInteger i = 0; i < m; i++)
        {
            NSUInteger kind = (NSUInteger)classOf(editorTypes[i]);
            NSArray<NSNumber *> *candidates = positions[kind];
            while (cursors[kind] < candidates.count && candidates[cursors[kind]].unsignedIntegerValue < nextPreview)
                cursors[kind]++;
            if (cursors[kind] == candidates.count) continue;
            NSUInteger j = candidates[cursors[kind]++].unsignedIntegerValue;
            [alignedEditor addObject:editorYs[i]];
            [alignedPreview addObject:previewYs[j]];
            nextPreview = j + 1;
        }
    }

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

// Both directions interpolate the same strictly monotonic pairs, including
// viewport endpoints. This makes changing scroll ownership reversible rather
// than applying two different tapering corrections to the same content.
+ (CGFloat)scrollOffset:(CGFloat)offset sourceHeight:(CGFloat)sourceHeight sourceVisible:(CGFloat)sourceVisible
          targetHeight:(CGFloat)targetHeight targetVisible:(CGFloat)targetVisible
             sourceYs:(NSArray<NSNumber *> *)sourceYs targetYs:(NSArray<NSNumber *> *)targetYs
{
    CGFloat sourceMax=MAX(0,sourceHeight-sourceVisible),targetMax=MAX(0,targetHeight-targetVisible);
    if (sourceMax<=0 || offset<=0) return 0;
    if (offset>=sourceMax) return targetMax;
    CGFloat lowSource=0,lowTarget=0;
    NSUInteger count=MIN(sourceYs.count,targetYs.count);
    for (NSUInteger i=0;i<count;i++) {
        CGFloat s=[sourceYs[i] doubleValue]-sourceVisible/2,t=[targetYs[i] doubleValue]-targetVisible/2;
        if (s<=lowSource || t<=lowTarget || s>=sourceMax || t>=targetMax) continue;
        if (s>=offset) return lowTarget+(t-lowTarget)*(offset-lowSource)/(s-lowSource);
        lowSource=s;lowTarget=t;
    }
    return lowTarget+(targetMax-lowTarget)*(offset-lowSource)/(sourceMax-lowSource);
}

- (void)syncSourceScrollersReverse:(BOOL)reverse
{
    NSScrollView *source=reverse ? self.preview.enclosingScrollView : self.editor.enclosingScrollView;
    NSScrollView *target=reverse ? self.editor.enclosingScrollView : self.preview.enclosingScrollView;
    if (!source || !target || NSHeight(source.contentView.bounds)<=0 || NSHeight(target.contentView.bounds)<=0) return;
    CGFloat y=[MPDocument scrollOffset:NSMinY(source.contentView.bounds)
        sourceHeight:NSHeight(source.documentView.bounds) sourceVisible:NSHeight(source.contentView.bounds)
        targetHeight:NSHeight(target.documentView.bounds) targetVisible:NSHeight(target.contentView.bounds)
        sourceYs:reverse ? _webViewHeaderLocations : _editorHeaderLocations
        targetYs:reverse ? _editorHeaderLocations : _webViewHeaderLocations];
    NSRect bounds=target.contentView.bounds;bounds.origin.y=y;target.contentView.bounds=bounds;
    if (!reverse) self.lastPreviewScrollTop=y;
}

/**
 * Synchronizes preview pane scroll position with editor pane position.
 *
 * Algorithm:
 * 1. Find reference points (headers/images/paragraphs/list items) before and after current editor position
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
    if (self.sourceScrollLocations) {
        [self syncSourceScrollersReverse:NO];return;
    }
    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    CGFloat previewContentHeight = ceilf(NSHeight(self.preview.enclosingScrollView.documentView.bounds));
    CGFloat previewVisibleHeight = ceilf(NSHeight(self.preview.enclosingScrollView.contentView.bounds));
    if (editorVisibleHeight <= 0 || previewVisibleHeight <= 0) return;
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
    if (relativeHeaderIndex >= 0 && [_webViewHeaderLocations count] > (NSUInteger)relativeHeaderIndex)
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
    previewY = MAX(0, MIN(previewY, MAX(0, NSHeight(self.preview.enclosingScrollView.documentView.bounds) - NSHeight(contentBounds))));
    contentBounds.origin.y = previewY;

    // Issue #342: No flag toggles needed — previewBoundsDidChange: is guarded
    // by scrollOwner != MPScrollOwnerPreview, which suppresses the synchronous
    // NSViewBoundsDidChangeNotification fired by this bounds assignment.
    self.preview.enclosingScrollView.contentView.bounds = contentBounds;

    // Save this scroll position so it persists across preview refreshes
    self.lastPreviewScrollTop = previewY;
}

/**
 * Synchronizes preview pane scroll position with the editor's cursor position,
 * aligning the corresponding preview content to the same on-screen row as the
 * cursor (rather than centering the viewport, as -syncScrollers does).
 *
 * Algorithm:
 * 1. Find the reference points (headers/images/paragraphs/list items) before and after the cursor's
 *    absolute position in the editor's full document.
 * 2. Calculate what percentage of the way the cursor is between those points.
 * 3. Apply that percentage between the corresponding preview reference points
 *    to find the absolute preview Y that corresponds to the cursor's line.
 * 4. Scroll the preview so that Y lands at the same distance from the top of
 *    the preview pane as the cursor currently sits from the top of the editor
 *    pane, so the two lines land on the same screen row.
 */
- (void)syncScrollersToCursor
{
    if (!self.editor)
        return;                              // Headless / nib not yet loaded.
    if (!self.editorVisible)
        return;                              // Cursor position is meaningless when hidden.

    NSRange selection = self.editor.selectedRange;
    NSUInteger cursorLocation = MIN(selection.location, self.editor.string.length);

    // Ask the layout manager for the line fragment containing the cursor's glyph, then
    // take its origin — this is the reliable way to get a cursor's vertical position;
    // boundingRectForGlyphRange: with a zero-length range returns a degenerate empty
    // rect and cannot be used to locate the cursor.
    NSLayoutManager *cursorLayoutManager = [self.editor layoutManager];
    NSTextContainer *cursorTextContainer = [self.editor textContainer];
    NSUInteger cursorGlyphIndex =
        [cursorLayoutManager glyphIndexForCharacterAtIndex:cursorLocation];
    NSRange lineGlyphRange;
    NSRect cursorRect;
    if (cursorGlyphIndex < cursorLayoutManager.numberOfGlyphs)
    {
        cursorRect = [cursorLayoutManager lineFragmentRectForGlyphAtIndex:cursorGlyphIndex
                                                            effectiveRange:&lineGlyphRange];
    }
    else
    {
        // Cursor is at the very end of the document, past the last glyph: use the
        // extra line fragment rect, which NSLayoutManager always keeps up to date
        // for the position just after the last character.
        cursorRect = [cursorLayoutManager extraLineFragmentRect];
    }

    CGFloat previewY = [MPDocument previewYForCursorY:NSMidY(cursorRect)
                                   editorContentHeight:ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds))
                                   editorVisibleHeight:ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds))
                                   editorScrollOffsetY:NSMinY(self.editor.enclosingScrollView.contentView.bounds)
                                  previewContentHeight:ceilf(NSHeight(self.preview.enclosingScrollView.documentView.bounds))
                                  previewVisibleHeight:ceilf(NSHeight(self.preview.enclosingScrollView.contentView.bounds))
                                   editorHeaderLocations:_editorHeaderLocations
                                  webViewHeaderLocations:_webViewHeaderLocations];

    NSRect contentBounds = self.preview.enclosingScrollView.contentView.bounds;
    previewY = MAX(0, MIN(previewY, MAX(0, NSHeight(self.preview.enclosingScrollView.documentView.bounds) - NSHeight(contentBounds))));
    contentBounds.origin.y = previewY;

    // Issue #342: No flag toggles needed — previewBoundsDidChange: is guarded
    // by scrollOwner != MPScrollOwnerPreview, which suppresses the synchronous
    // NSViewBoundsDidChangeNotification fired by this bounds assignment.
    self.preview.enclosingScrollView.contentView.bounds = contentBounds;

    // Save this scroll position so it persists across preview refreshes
    self.lastPreviewScrollTop = previewY;
}

/**
 * Pure geometry helper for -syncScrollersToCursor, extracted so its math can be
 * unit-tested with concrete numbers instead of live NSTextView/WebView geometry.
 *
 * Given the cursor's absolute Y position in the editor's full document, finds the
 * corresponding absolute Y in the preview's full document (via the same
 * reference-point bracketing/interpolation -syncScrollers uses), then converts the
 * cursor's position within the editor's *visible viewport* to a FRACTION of that
 * viewport's height, and applies that fraction against the preview's viewport
 * height. The fraction (not a raw pixel offset) is what carries over correctly
 * between the two panes, since they render at different scales (different fonts,
 * line heights, and pane widths mean a given pixel offset represents a different
 * amount of visual content in each).
 */
+ (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY
           editorContentHeight:(CGFloat)editorContentHeight
           editorVisibleHeight:(CGFloat)editorVisibleHeight
           editorScrollOffsetY:(CGFloat)editorScrollOffsetY
          previewContentHeight:(CGFloat)previewContentHeight
          previewVisibleHeight:(CGFloat)previewVisibleHeight
        editorHeaderLocations:(NSArray<NSNumber *> *)editorHeaderLocations
       webViewHeaderLocations:(NSArray<NSNumber *> *)webViewHeaderLocations
{
    NSInteger relativeHeaderIndex = -1; // -1 is start of document, before any other header
    CGFloat minY = 0;
    CGFloat maxY = 0;
    BOOL foundMaxY = NO;

    // Bracket the cursor's absolute document position between the nearest reference
    // points (headers/images/paragraphs/list items), with no viewport-centering taper: unlike -syncScrollers,
    // we want the corresponding preview row to land at an exact screen position, not a
    // centered one.
    for (NSNumber *headerYNum in editorHeaderLocations) {
        CGFloat headerY = [headerYNum floatValue];

        if (headerY < cursorDocumentY)
        {
            relativeHeaderIndex += 1;
            minY = headerY;
        } else if (!foundMaxY)
        {
            maxY = headerY;
            foundMaxY = YES;
        }
    }

    if (!foundMaxY)
    {
        // No reference point after the cursor: interpolate to the end of the document.
        maxY = editorContentHeight;
    }

    CGFloat cursorOffsetFromMin = MAX(0, cursorDocumentY - minY);
    CGFloat spanY = maxY - minY;
    CGFloat percentBetweenHeaders = (spanY < 0.001) ? 0 : MAX(0, MIN(1.0, cursorOffsetFromMin / spanY));

    // Find the Y positions in the preview window that we're interpolating between.
    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = previewContentHeight;

    if (relativeHeaderIndex >= 0 && [webViewHeaderLocations count] > (NSUInteger)relativeHeaderIndex)
    {
        topHeaderY = floorf([webViewHeaderLocations[relativeHeaderIndex] doubleValue]);
    }

    if (!foundMaxY)
    {
        bottomHeaderY = previewContentHeight;
    }
    else if ([webViewHeaderLocations count] > relativeHeaderIndex + 1)
    {
        bottomHeaderY = ceilf([webViewHeaderLocations[relativeHeaderIndex + 1] doubleValue]);
    }

    // The absolute preview Y that corresponds to the cursor's line.
    CGFloat matchingPreviewY = topHeaderY + (bottomHeaderY - topHeaderY) * percentBetweenHeaders;

    // The cursor's position within the editor's visible viewport, as a fraction of
    // that viewport's height.
    CGFloat cursorFractionFromEditorTop = editorVisibleHeight < 0.001 ? 0 :
        MAX(0, MIN(1.0, (cursorDocumentY - editorScrollOffsetY) / editorVisibleHeight));

    CGFloat previewY = matchingPreviewY - cursorFractionFromEditorTop * previewVisibleHeight;
    previewY = MAX(0, MIN(previewY, previewContentHeight - previewVisibleHeight));
    return previewY;
}

/**
 * Synchronizes editor pane scroll position with preview pane position.
 *
 * This is the reverse of syncScrollers - when the user scrolls the preview,
 * this method scrolls the editor to the corresponding position.
 *
 * Algorithm:
 * 1. Find reference points (headers/images/paragraphs/list items) before and after current preview position
 * 2. Calculate percentage scrolled between those reference points
 * 3. Apply same percentage between corresponding editor reference points
 * 4. Use "tapering" at document edges to center-align content mid-document but
 *    align to top/bottom at document boundaries
 */
- (void)syncScrollersReverse
{
    if (self.sourceScrollLocations) {
        [self syncSourceScrollersReverse:YES];return;
    }
    CGFloat previewContentHeight = ceilf(NSHeight(self.preview.enclosingScrollView.documentView.bounds));
    CGFloat previewVisibleHeight = ceilf(NSHeight(self.preview.enclosingScrollView.contentView.bounds));
    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    if (editorVisibleHeight <= 0 || previewVisibleHeight <= 0) return;
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
    if (relativeHeaderIndex >= 0 && [_editorHeaderLocations count] > (NSUInteger)relativeHeaderIndex)
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
    editorY = MAX(0, MIN(editorY, MAX(0, editorContentHeight - editorVisibleHeight)));
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
    [self setupReadingProgress];
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


// NSDocument's completion convention is (document, success, context), after self/_cmd.
+ (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context
{
    if (!delegate || !selector) return nil;
    NSMethodSignature *signature = [delegate methodSignatureForSelector:selector];
    NSParameterAssert(signature && signature.numberOfArguments == 5);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = delegate;
    invocation.selector = selector;
    NSDocument *document = nil;
    BOOL success = NO;
    [invocation setArgument:&document atIndex:2];
    [invocation setArgument:&success atIndex:3];
    [invocation setArgument:&context atIndex:4];
    [invocation retainArguments];
    return invocation;
}

- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context
{
    // Issue #504: If this print completion was a save-to-PDF export, post-
    // process the exported file to inject clickable internal anchor links.
    // Gate on the stash, NOT on `context`: a normal Cmd-P print also has nil
    // context, but never sets pdfExportURL, so it is correctly excluded here.
    // Both private prints must succeed before atomic publication.
    MPDocument *mpDoc = (MPDocument *)doc;
    if (mpDoc.pdfExportURL)
    {
        NSURL *exportURL = mpDoc.pdfExportURL;
        @try {
            if (ok)
                [mpDoc postProcessExportedPDFAtURL:exportURL];
        } @catch (NSException *exception) {
            mpDoc.pdfExportError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"PDF export failed."}];
        } @finally {
            [mpDoc restorePDFAnchorSession];
            if (mpDoc.pdfExportTemporaryURL)
                [[NSFileManager defaultManager] removeItemAtURL:mpDoc.pdfExportTemporaryURL error:NULL];
            if (mpDoc.pdfExportMetadataURL)
                [[NSFileManager defaultManager] removeItemAtURL:mpDoc.pdfExportMetadataURL error:NULL];
            mpDoc.pdfExportTemporaryURL = nil;
            mpDoc.pdfExportMetadataURL = nil;
            mpDoc.pdfExportPrintInfo = nil;
            mpDoc.pdfExportOriginalPreview = nil;
            mpDoc.pdfExportOriginalContext = nil;
            mpDoc.pdfExportDOMSnapshot = nil;
            mpDoc.pdfExportURL = nil;
            mpDoc.pdfExportPending = NO;
        }
        if (mpDoc.pdfExportError) {
            ok = NO;
            [mpDoc presentError:mpDoc.pdfExportError];
            mpDoc.pdfExportError = nil;
        }
    }

    if ([doc respondsToSelector:@selector(setPrinting:)]) {
        mpDoc.printing = NO;
        // Keep the print snapshot stable, then publish the latest source even
        // when printing was cancelled. Completion consumers await that load.
        if (!mpDoc.documentClosed && mpDoc.renderToWebPending && !mpDoc.alreadyRenderingInWeb) {
            mpDoc.renderToWebPending = NO;
            [mpDoc.renderer parseAndRenderNow];
        }
    }
    if (context)
    {
        NSInvocation *invocation = (__bridge_transfer NSInvocation *)context;
        if ([invocation isKindOfClass:[NSInvocation class]])
        {
            [invocation setArgument:&doc atIndex:2];
            [invocation setArgument:&ok atIndex:3];
            [invocation invoke];
        }
    }
}


#pragma mark - Source-backed preview editing

- (NSDictionary *)previewDraft
{
    if (!NSThread.isMainThread || self.documentClosed || !self.previewEditToken) return nil;
    JSValue *value = [self.preview.mainFrame.javaScriptContext evaluateScript:
        @"window.macdownPreviewEditor ? window.macdownPreviewEditor.draft() : null"];
    id draft = value.isNull || value.isUndefined ? nil : [value toObject];
    return [draft isKindOfClass:NSDictionary.class] ? draft : nil;
}

- (BOOL)flushPreviewEditor
{
    NSDictionary *draft = [self previewDraft];
    if (!draft) return YES;
    if (![self applyPreviewEditPayload:draft]) {
        NSBeep();
        [self.preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownPreviewEditor.showError()"];
        return NO;
    }
    [self.preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownPreviewEditor.finish()"];
    return YES;
}

- (void)saveDocument:(id)sender
{
    if ([self flushPreviewEditor]) [super saveDocument:sender];
}

- (void)saveDocumentAs:(id)sender
{
    if ([self flushPreviewEditor]) [super saveDocumentAs:sender];
}

- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)contextInfo
{
    if ([self flushPreviewEditor])
        [super canCloseDocumentWithDelegate:delegate shouldCloseSelector:selector contextInfo:contextInfo];
    else {
        void (*callback)(id, SEL, NSDocument *, BOOL, void *) = (void *)[delegate methodForSelector:selector];
        if (callback) callback(delegate, selector, self, NO, contextInfo);
    }
}

- (void)installPreviewEditor
{
    if (self.printing || self.documentClosed || !self.renderer ||
        ![self.editor.string isEqualToString:self.renderer.checkboxSourceMarkdown]) return;
    JSContext *context = self.preview.mainFrame.javaScriptContext;
    if (!context || ![self.preview.mainFrame.dataSource.request.URL isEqual:self.currentBaseUrl]) return;
    if ([self.previewEditToken isEqualToString:self.renderer.checkboxBridgeToken] &&
        [[context evaluateScript:@"Boolean(window.macdownPreviewEditor&&typeof window.macdownPreviewEditor.elements==='function'&&window.macdownPreviewEditor.elements().spans.some(function(n){return n.isConnected;}))"] toBool]) return;
    NSString *token = [[context evaluateScript:@"(function(){var m=document.querySelector('meta[name=\"macdown-checkbox-token\"]');return m?m.content:'';})()"] toString];
    if (![token isEqualToString:self.renderer.checkboxBridgeToken]) return;
    // Collect prose and inline code; fenced code is proven separately below.
    // Exclude generated diagrams, navigation and controls from both mappings.
    // Markdown continuation prefixes are absent from the rendered text. Split
    // quoted soft breaks into physical leaves before proving each source run.
    // The live DOM and every parser probe must use exactly the same traversal.
    // Bound the split plan before mutating the DOM, including newline-only leaves.
    NSString *proseTraversal =
        @"function proseNodes(d,owned){var originals=[],plans=[],cuts=0,w=d.createTreeWalker(d.body,NodeFilter.SHOW_TEXT,null,false),n;"
         "function eligible(n){var p=n.parentElement;return p&&!owned.some(function(e){return e.contains(n);})&&!p.closest('script,style,pre,nav,textarea,button,select,svg,math,.MathJax,.MathJax_Display');}"
         "while((n=w.nextNode())){if(!eligible(n))continue;if(originals.length>=4000)return [];originals.push(n);if(!n.parentElement.closest('blockquote')){plans.push([]);continue;}var positions=[],re=/[\\r\\n]+/g,m;while((m=re.exec(n.nodeValue))){[m.index,m.index+m[0].length].forEach(function(i){if(i>0&&i<n.length)positions.push(i);});if(cuts+positions.length>4000)return [];}cuts+=positions.length;plans.push(positions);}"
         "originals.forEach(function(n,i){plans[i].reverse().forEach(function(position){n.splitText(position);});});"
         "var a=[];w=d.createTreeWalker(d.body,NodeFilter.SHOW_TEXT,null,false);while((n=w.nextNode())){var p=n.parentElement;if(!eligible(n)||(!n.nodeValue.trim()&&(!p.closest('p,h1,h2,h3,h4,h5,h6,li,summary')||/[\\r\\n]/.test(n.nodeValue))))continue;if(a.length>=2000)return [];a.push(n);}return a;}";
    NSString *scan = [NSString stringWithFormat:@"(function(){%@var ui=window.macdownPreviewEditor&&typeof window.macdownPreviewEditor.elements==='function'&&window.macdownPreviewEditor.elements(),owned=ui?[ui.panel,ui.style].concat(ui.spans).filter(function(e){return e&&e.isConnected;}):[],a=proseNodes(document,owned);window.__macdownPreviewEditNodes=a;return JSON.stringify(a.map(function(n){return n.nodeValue;}));})()",proseTraversal];
    NSString *json = [[context evaluateScript:scan] toString];
    NSArray *texts = json ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                                   options:0 error:NULL] : nil;
    if (![texts isKindOfClass:NSArray.class]) return;
    NSString *source = self.editor.string;
    NSDictionary *restore = self.previewSelectionToRestore;
    if (restore && ![restore[@"source"] isEqualToString:source]) {
        restore = nil; self.previewSelectionToRestore = nil; self.previewQueuedFormatting = nil;
    }
    NSRange restoreRange = restore ? NSMakeRange([restore[@"location"] unsignedIntegerValue],[restore[@"length"] unsignedIntegerValue]) : NSMakeRange(NSNotFound,0);
    NSString *selectionProbe = [NSString stringWithFormat:@"(function(){%@var d=new DOMParser().parseFromString(window.__mpSelectionProbeHTML,'text/html'),a=proseNodes(d,[]),old=window.__macdownPreviewEditNodes,found=-1,marked=window.__mpSelectionMarkedText;if(a.length!==old.length)return -1;for(var i=0;i<a.length;i++){if(a[i].parentElement.tagName!==old[i].parentElement.tagName)return -1;if(a[i].nodeValue===marked&&old[i].nodeValue===window.__mpSelectionOriginalText){if(found!==-1)return -1;found=i;}else if(a[i].nodeValue!==old[i].nodeValue)return -1;}return found;})()",proseTraversal];
    NSInteger anchoredNode = -1;
    if (restore && NSMaxRange(restoreRange)<=source.length && [[source substringWithRange:restoreRange] isEqualToString:restore[@"text"]]) {
        // A selected word may now be a separate styled node, repeated elsewhere.
        // Prove its exact occurrence by comparing the complete ordered text DOM
        // against a single source-range probe, without relaxing other mappings.
        NSString *marker = [NSString stringWithFormat:@"\uE000%@\uE001",NSUUID.UUID.UUIDString];
        NSString *probe = [source stringByReplacingCharactersInRange:restoreRange withString:MPPreviewMarkedLiteral(restore[@"text"],marker)];
        context[@"window"][@"__mpSelectionProbeHTML"] = [self.renderer HTMLForMarkdownSnapshot:probe];
        context[@"window"][@"__mpSelectionMarkedText"] = MPPreviewMarkedLiteral(restore[@"text"],marker);
        context[@"window"][@"__mpSelectionOriginalText"] = restore[@"text"];
        JSValue *value = [context evaluateScript:selectionProbe];
        if (value.isNumber) anchoredNode = value.toInt32;
        [context evaluateScript:@"delete window.__mpSelectionProbeHTML;delete window.__mpSelectionMarkedText;delete window.__mpSelectionOriginalText;"];
    }
    NSMutableArray *mapping = [NSMutableArray array], *nodes = [NSMutableArray array];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    // Bound full-document probes across all repeated literals, not only per
    // word: a large document must not trigger thousands of synchronous parses.
    __block NSUInteger remainingOccurrenceProbes = 128;
    [texts enumerateObjectsUsingBlock:^(NSString *text, NSUInteger node, BOOL *stop) {
        if (![text isKindOfClass:NSString.class] || !text.length ||
            ![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return;
        id cached = cache[text];
        NSRange range = NSMakeRange(NSNotFound, 0);
        if ([cached isKindOfClass:NSDictionary.class]) {
            NSValue *value=cached[@(node)]; if (value) range=value.rangeValue;
        } else if (cached) range = [cached rangeValue];
        else {
            range = [source rangeOfString:text options:NSLiteralSearch];
            BOOL repeated = range.location != NSNotFound && [source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(range.location+1,source.length-range.location-1)].location != NSNotFound;
            if (repeated && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
                // Literal repetition is not source ambiguity when a parser probe
                // identifies one exact text node in the complete ordered DOM.
                NSMutableArray *candidates=[NSMutableArray array];
                NSUInteger cursor=0;
                while (cursor<source.length && candidates.count<=64) {
                    NSRange candidate=[source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(cursor,source.length-cursor)];
                    if (candidate.location==NSNotFound) break;
                    [candidates addObject:[NSValue valueWithRange:candidate]];cursor=candidate.location+1;
                }
                NSMutableDictionary *resolved=[NSMutableDictionary dictionary];
                NSMutableSet *ambiguous=[NSMutableSet set];
                if (candidates.count<=64 && candidates.count<=remainingOccurrenceProbes) for (NSValue *candidateValue in candidates) {
                    remainingOccurrenceProbes--;
                    NSRange candidate=candidateValue.rangeValue;
                    NSString *marker=[NSString stringWithFormat:@"\uE000%@\uE001",NSUUID.UUID.UUIDString];
                    NSString *probeSource=[source stringByReplacingCharactersInRange:candidate withString:MPPreviewMarkedLiteral(text,marker)];
                    context[@"window"][@"__mpSelectionProbeHTML"]=[self.renderer HTMLForMarkdownSnapshot:probeSource];
                    context[@"window"][@"__mpSelectionMarkedText"]=MPPreviewMarkedLiteral(text,marker);
                    context[@"window"][@"__mpSelectionOriginalText"]=text;
                    JSValue *value=[context evaluateScript:selectionProbe];
                    if (!value.isNumber || value.toInt32<0) continue;
                    NSNumber *matched=@(value.toInt32);
                    if (resolved[matched]) { [resolved removeObjectForKey:matched];[ambiguous addObject:matched]; }
                    else if (![ambiguous containsObject:matched]) resolved[matched]=candidateValue;
                }
                [context evaluateScript:@"delete window.__mpSelectionProbeHTML;delete window.__mpSelectionMarkedText;delete window.__mpSelectionOriginalText;"];
                cache[text]=resolved;
                NSValue *value=resolved[@(node)];range=value?value.rangeValue:NSMakeRange(NSNotFound,0);
            } else {
                if (repeated) range=NSMakeRange(NSNotFound,0);
                cache[text]=[NSValue valueWithRange:range];
            }
        }
        BOOL restoredAnchor = (NSInteger)node == anchoredNode && [text isEqualToString:restore[@"text"]];
        BOOL anchored=restoredAnchor || [cache[text] isKindOfClass:NSDictionary.class];
        if (restoredAnchor) range = restoreRange;
        if (range.location == NSNotFound) return;
        NSUInteger index = mapping.count;
        [mapping addObject:@{@"location":@(range.location), @"length":@(range.length), @"text":text, @"index":@(index)}];
        [nodes addObject:@{@"node":@(node), @"id":@(index), @"text":text, @"anchored":@(anchored)}];
    }];
    NSString *taskSeparatorJSON=[[context evaluateScript:@"JSON.stringify(window.__macdownPreviewEditNodes.map(function(n){var p=n.previousSibling;return Boolean(n.parentElement.matches('li.task-list-item')&&p&&p.nodeType===1&&p.matches('input[type=checkbox]'));}))"] toString];
    NSArray *taskSeparators=taskSeparatorJSON ? [NSJSONSerialization JSONObjectWithData:[taskSeparatorJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    // Whitespace between styled runs is selectable too. Its source occurrence
    // is bounded by the two proven neighboring literals, never a global search.
    for (NSUInteger node=1;node+1<texts.count;node++) {
        NSString *text=texts[node];
        if (![text isKindOfClass:NSString.class] || !text.length || [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) continue;
        NSDictionary *previous=nil,*next=nil;
        BOOL alreadyMapped=NO;
        for (NSDictionary *item in nodes) {
            if ([item[@"node"] unsignedIntegerValue]==node) alreadyMapped=YES;
            if ([item[@"node"] unsignedIntegerValue]==node-1) previous=mapping[[item[@"id"] unsignedIntegerValue]];
            if ([item[@"node"] unsignedIntegerValue]==node+1) next=mapping[[item[@"id"] unsignedIntegerValue]];
        }
        if (alreadyMapped || !next) continue;
        // The separator after a generated checkbox has no preceding literal
        // in its LI. Prove ownership through that checkbox, the source task
        // prefix and the existing doubled-whitespace DOM probe.
        if (node<taskSeparators.count && [taskSeparators[node] boolValue]) {
            NSUInteger nextStart=[next[@"location"] unsignedIntegerValue];
            NSRange separator=MPPreviewTaskSeparatorRange(source,nextStart);
            if(separator.location!=NSNotFound) {
                if(NSMaxRange(separator)<=nextStart && [[source substringWithRange:separator] isEqualToString:text]) {
                    NSUInteger index=mapping.count;
                    [mapping addObject:@{@"location":@(separator.location),@"length":@(separator.length),@"text":text,@"index":@(index)}];
                    [nodes addObject:@{@"node":@(node),@"id":@(index),@"text":text,@"anchored":@NO,@"bounded":@YES,@"before":next[@"index"],@"after":next[@"index"]}];
                    continue;
                }
            }
        }
        if (!previous) continue;
        NSUInteger start=[previous[@"location"] unsignedIntegerValue]+[previous[@"length"] unsignedIntegerValue],end=[next[@"location"] unsignedIntegerValue];
        if (start>end || end>source.length) continue;
        NSRange found=[source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(start,end-start)];
        if (found.location==NSNotFound || [source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(NSMaxRange(found),end-NSMaxRange(found))].location!=NSNotFound) continue;
        NSUInteger index=mapping.count;
        [mapping addObject:@{@"location":@(found.location),@"length":@(found.length),@"text":text,@"index":@(index)}];
        [nodes addObject:@{@"node":@(node),@"id":@(index),@"text":text,@"anchored":@NO,@"bounded":@YES,@"before":previous[@"index"],@"after":next[@"index"]}];
    }
    // Prove that the literal source range renders as this text node. A unique
    // substring alone could point into a URL, HTML attribute or front matter.
    // Batch probes through the same parser, without changing its live snapshot.
    NSMutableString *probeSource = [source mutableCopy];
    NSString *probe = [NSString stringWithFormat:@"\uE000%@",NSUUID.UUID.UUIDString];
    NSArray *ordered = [mapping sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"location"] compare:a[@"location"]];
    }];
    NSUInteger boundary = source.length;
    NSMutableSet *probed = [NSMutableSet set];
    for (NSDictionary *item in ordered) {
        NSRange range = NSMakeRange([item[@"location"] unsignedIntegerValue], [item[@"length"] unsignedIntegerValue]);
        if (NSMaxRange(range) > boundary) continue;
        NSUInteger index = [item[@"index"] unsignedIntegerValue];
        NSString *marker = [NSString stringWithFormat:@"%@-%lu\uE001",probe,(unsigned long)index];
        // Doubling bounded whitespace preserves delimiter flanking while proving
        // that this physical range, rather than an HTML attribute, owns the leaf.
        NSString *marked=[nodes[index][@"bounded"] boolValue]
            ? [item[@"text"] stringByAppendingString:item[@"text"]]
            : MPPreviewMarkedLiteral(item[@"text"],marker);
        [probeSource replaceCharactersInRange:range withString:marked];
        NSMutableDictionary *node=[nodes[index] mutableCopy];node[@"probeText"]=marked;nodes[index]=node;
        [probed addObject:@(index)]; boundary = range.location;
    }
    context[@"window"][@"__mpProbeHTML"] = [self.renderer HTMLForMarkdownSnapshot:probeSource];
    context[@"window"][@"__mpProbeNodes"] = nodes;
    NSString *verification = [NSString stringWithFormat:@"(function(){%@var d=new DOMParser().parseFromString(window.__mpProbeHTML,'text/html'),values=new Set(),counts=new Map();var probeNodes=proseNodes(d,[]);probeNodes.forEach(function(n){values.add(JSON.stringify([n.nodeValue,n.parentElement.tagName]));});window.__macdownPreviewEditNodes.forEach(function(n){counts.set(n.nodeValue,(counts.get(n.nodeValue)||0)+1);});return JSON.stringify(window.__mpProbeNodes.map(function(item){var original=window.__macdownPreviewEditNodes[item.node];if(item.bounded){var adjacent=probeNodes[item.node];return probeNodes.length===window.__macdownPreviewEditNodes.length&&adjacent&&adjacent.nodeValue===item.probeText&&adjacent.parentElement.tagName===original.parentElement.tagName;}return counts.get(item.text)===1&&values.has(JSON.stringify([item.probeText,original.parentElement.tagName]));}));})()",proseTraversal];
    NSString *verifiedJSON = [[context evaluateScript:verification] toString];
    NSArray *verified = verifiedJSON ? [NSJSONSerialization JSONObjectWithData:[verifiedJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    [context evaluateScript:@"delete window.__mpProbeHTML;delete window.__mpProbeNodes;"];
    NSMutableArray *validMapping = [NSMutableArray array], *validNodes = [NSMutableArray array];
    if ([verified isKindOfClass:NSArray.class] && verified.count == nodes.count) {
        for (NSUInteger i=0;i<nodes.count;i++) {
            if (![nodes[i][@"anchored"] boolValue] && (![probed containsObject:@(i)] || ![verified[i] boolValue])) continue;
            if ([nodes[i][@"bounded"] boolValue] && (![verified[[nodes[i][@"before"] unsignedIntegerValue]] boolValue] || ![verified[[nodes[i][@"after"] unsignedIntegerValue]] boolValue])) continue;
            NSMutableDictionary *node = [nodes[i] mutableCopy]; node[@"id"] = @(validMapping.count);
            [validMapping addObject:mapping[i]]; [validNodes addObject:node];
        }
    }
    // Prism splits a fenced block into token leaves. Prove the complete CODE
    // container through the renderer first, then translate its UTF-16 leaves
    // to the original physical source; token markup is never reverse-parsed.
    NSString *codeJSON = [[context evaluateScript:@"(function(){var a=window.__macdownPreviewEditNodes;return JSON.stringify(Array.from(document.querySelectorAll('pre>code')).map(function(code){var leaves=[],w=document.createTreeWalker(code,NodeFilter.SHOW_TEXT,null,false),n,offset=0;while(n=w.nextNode()){if(!n.nodeValue.length)continue;leaves.push({node:n,text:n.nodeValue,start:offset});offset+=n.nodeValue.length;}if(code.closest('blockquote,li')||a.length+leaves.length>2000)return {text:code.textContent,leaves:[]};return {text:code.textContent,leaves:leaves.map(function(leaf){var index=a.length;a.push(leaf.node);return {node:index,text:leaf.text,start:leaf.start};})};}));})()"] toString];
    NSArray *codeContainers = codeJSON ? [NSJSONSerialization JSONObjectWithData:[codeJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    if (self.preferences.extensionFencedCode && [codeContainers isKindOfClass:NSArray.class] && codeContainers.count) {
        NSUInteger openingStart=NSNotFound, contentStart=0, fenceWidth=0;
        unichar fenceCharacter=0;
        NSMutableSet *mappedCodeContainers=[NSMutableSet set];
        for (NSUInteger offset=0;offset<source.length;) {
            NSUInteger start,end,contentsEnd;
            [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
            NSString *line=[source substringWithRange:NSMakeRange(start,contentsEnd-start)];
            unichar marker=0;NSUInteger width=0;BOOL trailing=NO;
            BOOL fence=MPScanFenceMarker(line,&marker,&width,&trailing);
            offset=end;
            if (openingStart==NSNotFound) {
                // Container/indented fences need non-linear source mapping and
                // stay outside this literal fenced-block editing contract.
                if (fence && line.length && [line characterAtIndex:0]==marker) {
                    openingStart=start;contentStart=end;fenceCharacter=marker;fenceWidth=width;
                }
                continue;
            }
            if (!fence || marker!=fenceCharacter || width<fenceWidth || trailing) continue;
            NSRange blockRange=NSMakeRange(openingStart,end-openingStart);
            NSRange contentRange=NSMakeRange(contentStart,start-contentStart);
            openingStart=NSNotFound;
            if (!contentRange.length || !remainingOccurrenceProbes) continue;
            NSString *content=[source substringWithRange:contentRange];
            NSString *normalized=[[content stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
            if (![normalized hasSuffix:@"\n"]) continue;
            // Hoedown omits the physical newline immediately before the
            // closing fence from CODE text. Internal blank lines stay literal.
            normalized=[normalized substringToIndex:normalized.length-1];
            NSUInteger endingWidth=[content hasSuffix:@"\r\n"] ? 2 : 1;
            NSUInteger lastEnding=NSMaxRange(contentRange)-endingWidth;
            NSString *probeMarker=[NSString stringWithFormat:@"\uE000%@\uE001",NSUUID.UUID.UUIDString];
            NSMutableString *probeMarkdown=[source mutableCopy];
            [probeMarkdown insertString:probeMarker atIndex:lastEnding];
            [probeMarkdown insertString:probeMarker atIndex:contentStart];
            remainingOccurrenceProbes--;
            context[@"window"][@"__mpCodeProbeHTML"]=[self.renderer HTMLForMarkdownSnapshot:probeMarkdown];
            context[@"window"][@"__mpCodeProbeMarker"]=probeMarker;
            context[@"window"][@"__mpCodeOriginal"]=codeContainers;
            JSValue *found=[context evaluateScript:@"(function(){var d=new DOMParser().parseFromString(window.__mpCodeProbeHTML,'text/html'),codes=Array.from(d.querySelectorAll('pre>code')),old=window.__mpCodeOriginal,m=window.__mpCodeProbeMarker,found=-1;if(codes.length!==old.length)return -1;for(var i=0;i<codes.length;i++){var text=old[i].text,marked=m+text+m;if(codes[i].textContent===marked){if(found!==-1)return -1;found=i;}else if(codes[i].textContent!==text)return -1;}return found;})()"];
            [context evaluateScript:@"delete window.__mpCodeProbeHTML;delete window.__mpCodeProbeMarker;delete window.__mpCodeOriginal;"];
            if (!found.isNumber || found.toInt32<0 || (NSUInteger)found.toInt32>=codeContainers.count) continue;
            NSNumber *containerIndex=@(found.toInt32);
            NSDictionary *container=codeContainers[containerIndex.unsignedIntegerValue];
            if ([mappedCodeContainers containsObject:containerIndex] || ![container[@"text"] isEqualToString:normalized] || ![container[@"leaves"] count]) continue;
            // Each displayed UTF-16 boundary maps monotonically through CRLF.
            // The extra terminal boundary is needed for a selection ending at
            // the final character, and emoji retain their two source units.
            NSMutableArray<NSNumber *> *boundaries=[NSMutableArray arrayWithObject:@(contentStart)];
            for (NSUInteger position=contentStart;position<lastEnding;position++) {
                if ([source characterAtIndex:position]=='\r' && position+1<lastEnding && [source characterAtIndex:position+1]=='\n') position++;
                [boundaries addObject:@(position+1)];
            }
            BOOL valid=boundaries.count==normalized.length+1;
            NSMutableArray *codeMappings=[NSMutableArray array], *codeNodes=[NSMutableArray array];
            for (NSDictionary *leaf in container[@"leaves"]) {
                NSUInteger leafStart=[leaf[@"start"] unsignedIntegerValue],leafLength=[leaf[@"text"] length];
                if (!valid || leafStart>normalized.length || leafLength>normalized.length-leafStart) { valid=NO;break; }
                NSRange original=NSMakeRange(boundaries[leafStart].unsignedIntegerValue,boundaries[leafStart+leafLength].unsignedIntegerValue-boundaries[leafStart].unsignedIntegerValue);
                // Source ranges containing CRLF have a different length than
                // DOM leaves; retain an explicit boundary map for validation.
                NSArray *leafBoundaries=[boundaries subarrayWithRange:NSMakeRange(leafStart,leafLength+1)];
                [codeMappings addObject:@{@"location":@(original.location),@"length":@(original.length),@"text":[source substringWithRange:original],@"displayText":leaf[@"text"],@"sourceBoundaries":leafBoundaries,
                    @"codeBlockRange":[NSValue valueWithRange:blockRange],@"codeContentRange":[NSValue valueWithRange:contentRange]}];
                [codeNodes addObject:@{@"node":leaf[@"node"],@"id":@(validMapping.count+codeNodes.count),@"text":leaf[@"text"]}];
            }
            if (valid) {
                [validMapping addObjectsFromArray:codeMappings];[validNodes addObjectsFromArray:codeNodes];
                [mappedCodeContainers addObject:containerIndex];
            }
        }
    }
    // Appended code leaves must join prose in actual DOM order, so selections
    // and continuation restoration remain monotonic across both kinds.
    NSString *orderJSON=[[context evaluateScript:@"(function(){var a=window.__macdownPreviewEditNodes,order=a.map(function(n,i){return i;});order.sort(function(i,j){return a[i]===a[j]?0:(a[i].compareDocumentPosition(a[j])&4)?-1:1;});var ranks=[];order.forEach(function(index,rank){ranks[index]=rank;});return JSON.stringify(ranks);})()"] toString];
    NSArray *DOMRanks=orderJSON ? [NSJSONSerialization JSONObjectWithData:[orderJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    if (![DOMRanks isKindOfClass:NSArray.class]) return;
    for (NSDictionary *node in validNodes)
        if ([node[@"node"] unsignedIntegerValue]>=DOMRanks.count) return;
    NSMutableArray *indices=[NSMutableArray array];
    for (NSUInteger i=0;i<validNodes.count;i++) [indices addObject:@(i)];
    [indices sortUsingComparator:^NSComparisonResult(NSNumber *a,NSNumber *b){
        NSNumber *left=validNodes[a.unsignedIntegerValue][@"node"],*right=validNodes[b.unsignedIntegerValue][@"node"];
        return [DOMRanks[left.unsignedIntegerValue] compare:DOMRanks[right.unsignedIntegerValue]];
    }];
    mapping=[NSMutableArray array];nodes=[NSMutableArray array];
    for (NSNumber *index in indices) {
        [mapping addObject:validMapping[index.unsignedIntegerValue]];
        NSMutableDictionary *node=[validNodes[index.unsignedIntegerValue] mutableCopy];node[@"id"]=@(nodes.count);[nodes addObject:node];
    }
    self.previewEditRanges = mapping;
    self.previewEditSource = source;
    self.previewEditToken = token;
    self.previewScrollCodeLines = [self scrollCodeLinesForSource:source context:context];
    NSMutableDictionary *configuration = [@{@"nodes":nodes, @"token":token, @"math":@(self.preferences.htmlMathJax), @"strike":@(self.preferences.extensionStrikethough), @"tasks":@(self.preferences.htmlTaskList), @"fenced":@(self.preferences.extensionFencedCode)} mutableCopy];
    NSMutableDictionary *calloutTitles=[NSMutableDictionary dictionary];
    for (NSString *type in @[@"note",@"tip",@"warning",@"important",@"caution"])
        calloutTitles[type]=MPPreviewDefaultCalloutTitle(type,NO);
    configuration[@"calloutTitles"]=calloutTitles;
    configuration[@"previewScale"]=@([self previewScale]);
    configuration[@"originalHTML"]=[self.renderer currentHtml] ?: @"";
    if (restore) {
        NSMutableArray *runs = [NSMutableArray array];
        NSMutableString *visible = [NSMutableString string];
        for (NSUInteger i=0; i<mapping.count; i++) {
            NSDictionary *item = mapping[i];
            NSRange mapped = NSMakeRange([item[@"location"] unsignedIntegerValue],[item[@"length"] unsignedIntegerValue]);
            NSRange intersection = NSIntersectionRange(mapped,restoreRange);
            if (!intersection.length) continue;
            NSArray<NSNumber *> *boundaries=item[@"sourceBoundaries"];
            NSUInteger start=boundaries ? [boundaries indexOfObject:@(intersection.location)] : intersection.location-mapped.location;
            NSUInteger end=boundaries ? [boundaries indexOfObject:@(NSMaxRange(intersection))] : NSMaxRange(intersection)-mapped.location;
            if (start==NSNotFound || end==NSNotFound) continue;
            [runs addObject:@{@"id":@(i),@"start":@(start),@"end":@(end)}];
            if (visible.length && runs.count>1) {
                NSDictionary *previous=mapping[[runs[runs.count-2][@"id"] unsignedIntegerValue]];
                NSUInteger previousIndex=[runs[runs.count-2][@"end"] unsignedIntegerValue];
                NSArray<NSNumber *> *previousBoundaries=previous[@"sourceBoundaries"];
                NSUInteger previousEnd=previousBoundaries ? previousBoundaries[previousIndex].unsignedIntegerValue : [previous[@"location"] unsignedIntegerValue]+previousIndex;
                [visible appendString:MPPreviewSourceSeparators(source,previousEnd,intersection.location)];
            }
            [visible appendString:[source substringWithRange:intersection]];
        }
        if (runs.count) {
            NSMutableDictionary *selection = [runs.firstObject mutableCopy];
            selection[@"runs"] = runs; selection[@"text"] = visible;
            configuration[@"selection"] = selection;
        }
    }
    self.previewSelectionToRestore = nil;
    context[@"window"][@"__macdownPreviewEditConfig"] = configuration;
    __weak MPDocument *weakDocument = self;
    context[@"window"][@"__macdownPreviewEditConfig"][@"formattingHTML"] = ^id(NSDictionary *payload) {
        return [weakDocument previewFormattingHTMLForPayload:payload] ?: NSNull.null;
    };
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"preview-edit" withExtension:@"js" subdirectory:@"Extensions"];
    NSString *script = scriptURL ? [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (script.length) [context evaluateScript:script];
    if (self.previewQueuedFormatting.count) {
        NSDictionary *next = self.previewQueuedFormatting.firstObject;
        [self.previewQueuedFormatting removeObjectAtIndex:0];
        if (configuration[@"selection"] && [self previewHasFindFocus]) {
            [self performPreviewFormattingAction:next[@"action"] value:next[@"value"]];
            if (!self.previewSelectionToRestore) self.previewQueuedFormatting = nil;
        } else self.previewQueuedFormatting = nil;
    }
}

- (NSString *)escapePreviewPlainText:(NSString *)text
{
    // A visual edit must not become executable HTML or new Markdown syntax.
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *markup = [NSCharacterSet characterSetWithCharactersInString:@"\\`*_{}[]()#+-.!|<>&~=^\"$"];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ([markup characterIsMember:c]) [result appendString:@"\\"];
        [result appendFormat:@"%C",c];
    }
    return result;
}

- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement
{
    return [self replacePreviewRange:range withString:replacement preservingSelection:NSMakeRange(NSNotFound,0)];
}

- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection
{
    return [self replacePreviewRange:range withString:replacement preservingSelection:selection restoringRange:NSMakeRange(NSNotFound,0)];
}

- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection restoringRange:(NSRange)restoring
{
    if (self.previewFormattingProbe) {
        NSString *source = self.editor.string;
        if (range.location > source.length || range.length > source.length-range.location) return NO;
        self.previewFormattingProbeSource = [source stringByReplacingCharactersInRange:range withString:replacement];
        return YES;
    }
    if (![self.editor shouldChangeTextInRange:range replacementString:replacement]) return NO;
    NSString *source = self.editor.string;
    NSString *text = selection.location != NSNotFound ? [source substringWithRange:selection] : nil;
    // Track the same occurrence within the replacement, rather than searching
    // the entire document or persisting a DOM node from the obsolete render.
    NSUInteger occurrence = 0, cursor = range.location;
    while (text.length && cursor < selection.location) {
        NSRange found = [source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(cursor,NSMaxRange(range)-cursor)];
        if (found.location == NSNotFound || found.location >= selection.location) break;
        occurrence++; cursor = found.location+1;
    }
    NSRange target = NSMakeRange(NSNotFound,0);
    cursor = 0;
    for (NSUInteger i=0; text.length && i<=occurrence && cursor<=replacement.length; i++) {
        target = [replacement rangeOfString:text options:NSLiteralSearch range:NSMakeRange(cursor,replacement.length-cursor)];
        if (target.location == NSNotFound) break;
        cursor = target.location+1;
    }
    if (restoring.location != NSNotFound) target = restoring;
    if (target.location != NSNotFound && NSMaxRange(target) > replacement.length) return NO;
    [self.editor.textStorage replaceCharactersInRange:range withString:replacement];
    if (target.location != NSNotFound) text = [replacement substringWithRange:target];
    self.previewSelectionToRestore = target.location == NSNotFound ? nil :
        @{@"source":self.editor.string.copy,@"location":@(range.location+target.location),@"length":@(target.length),@"text":text,@"beforeLocation":@(selection.location),@"beforeLength":@(selection.length)};
    if (self.previewSelectionToRestore) {
        [self.preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownPreviewEditor && window.macdownPreviewEditor.prepareForRender()"];
    }
    [self.editor didChangeText];
    // Source selection notifications can cancel the pending DOM restoration.
    // Apply the proven native range directly so the next toolbar action keeps
    // formatting the content rather than selecting its generated delimiters.
    self.editor.selectedRange = target.location != NSNotFound
        ? NSMakeRange(range.location+target.location,target.length)
        : NSMakeRange(range.location,replacement.length);
    [self.renderer parseAndRenderNow];
    return YES;
}

// A DOM selection is a sequence of independently proven literal source runs.
// Never trust display styles or a source range supplied by page JavaScript.
- (NSDictionary *)verifiedPreviewSelection:(NSDictionary *)payload
{
    id submitted = payload[@"runs"];
    NSArray *runs = submitted ?: @[@{@"id":payload[@"id"] ?: NSNull.null,@"start":payload[@"start"] ?: NSNull.null,@"end":payload[@"end"] ?: NSNull.null}];
    if (![runs isKindOfClass:NSArray.class] || !runs.count || runs.count > self.previewEditRanges.count) return nil;
    NSMutableString *visible = [NSMutableString string];
    NSMutableArray *ranges = [NSMutableArray array];
    NSString *source = self.previewEditSource;
    NSUInteger previousEnd = 0;
    NSMutableSet *seen = [NSMutableSet set];
    NSValue *codeBlockRange=nil,*codeContentRange=nil;
    BOOL containsProse=NO;
    for (id run in runs) {
        if (![run isKindOfClass:NSDictionary.class]) return nil;
        NSNumber *identifier=run[@"id"], *start=run[@"start"], *end=run[@"end"];
        for (id number in @[identifier ?: NSNull.null,start ?: NSNull.null,end ?: NSNull.null]) {
            if (![number isKindOfClass:NSNumber.class] || !isfinite([number doubleValue]) || [number doubleValue]<0 || floor([number doubleValue])!=[number doubleValue]) return nil;
        }
        if (identifier.doubleValue>=self.previewEditRanges.count || [seen containsObject:identifier]) return nil;
        [seen addObject:identifier];
        NSDictionary *entry=self.previewEditRanges[identifier.unsignedIntegerValue];
        NSRange mapped=NSMakeRange([entry[@"location"] unsignedIntegerValue],[entry[@"length"] unsignedIntegerValue]);
        NSArray<NSNumber *> *boundaries=entry[@"sourceBoundaries"];
        if (boundaries && (![boundaries isKindOfClass:NSArray.class] || ![entry[@"displayText"] isKindOfClass:NSString.class])) return nil;
        NSUInteger displayLength=boundaries ? [entry[@"displayText"] length] : mapped.length;
        if (mapped.location>source.length || mapped.length>source.length-mapped.location ||
            ![[source substringWithRange:mapped] isEqualToString:entry[@"text"]] || start.doubleValue>=end.doubleValue || end.doubleValue>displayLength) return nil;
        if (boundaries && boundaries.count!=displayLength+1) return nil;
        NSUInteger selectedStart=boundaries ? boundaries[start.unsignedIntegerValue].unsignedIntegerValue : mapped.location+start.unsignedIntegerValue;
        NSUInteger selectedEnd=boundaries ? boundaries[end.unsignedIntegerValue].unsignedIntegerValue : mapped.location+end.unsignedIntegerValue;
        if (selectedStart<mapped.location || selectedEnd>NSMaxRange(mapped) || selectedEnd<=selectedStart) return nil;
        NSRange selected=NSMakeRange(selectedStart,selectedEnd-selectedStart);
        NSValue *block=entry[@"codeBlockRange"];
        if (block) {
            if (![block isKindOfClass:NSValue.class] || ![entry[@"codeContentRange"] isKindOfClass:NSValue.class] || !boundaries) return nil;
            NSRange whole=block.rangeValue,content=[entry[@"codeContentRange"] rangeValue];
            if (whole.location>source.length || whole.length>source.length-whole.location ||
                content.location<whole.location || content.location>NSMaxRange(whole) || content.length>NSMaxRange(whole)-content.location ||
                selected.location<content.location || NSMaxRange(selected)>NSMaxRange(content)) return nil;
            if (containsProse || (codeBlockRange && ![codeBlockRange isEqual:block])) return nil;
            codeBlockRange=block;codeContentRange=entry[@"codeContentRange"];
        } else {
            if (codeBlockRange || boundaries) return nil;
            containsProse=YES;
        }
        if (ranges.count && selected.location<previousEnd) return nil;
        for (NSNumber *boundary in @[@(selected.location),@(NSMaxRange(selected))]) {
            NSUInteger position=boundary.unsignedIntegerValue;
            if (position>0 && position<source.length && CFStringIsSurrogateLowCharacter([source characterAtIndex:position]) && CFStringIsSurrogateHighCharacter([source characterAtIndex:position-1])) return nil;
        }
        if (ranges.count) [visible appendString:MPPreviewSourceSeparators(source,previousEnd,selected.location)];
        previousEnd=NSMaxRange(selected);
        [visible appendString:[source substringWithRange:selected]];
        [ranges addObject:[NSValue valueWithRange:selected]];
    }
    NSString *(^normalizeText)(NSString *)=^NSString *(NSString *text){
        if ([payload[@"action"] isEqual:@"table-align"]) return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
        return codeBlockRange ? [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"] : MPNormalizePreviewSelectionText(text);
    };
    if (submitted && (![payload[@"text"] isKindOfClass:NSString.class] || ![normalizeText(payload[@"text"]) isEqualToString:normalizeText(visible)])) return nil;
    if (!codeBlockRange && ranges.count==1 && [visible containsString:@"\n\n"]) return nil;
    NSRange first=[ranges.firstObject rangeValue],last=[ranges.lastObject rangeValue];
    NSRange total=NSMakeRange(first.location,NSMaxRange(last)-first.location);
    // Every proven run touched by this contiguous selection must be present.
    for (NSUInteger i=0;i<self.previewEditRanges.count;i++) {
        NSDictionary *entry=self.previewEditRanges[i];
        NSRange mapped=NSMakeRange([entry[@"location"] unsignedIntegerValue],[entry[@"length"] unsignedIntegerValue]);
        if (NSIntersectionRange(mapped,total).length && ![seen containsObject:@(i)]) return nil;
    }
    NSMutableDictionary *verified=[@{@"range":[NSValue valueWithRange:total],@"text":visible,@"runs":ranges} mutableCopy];
    if (codeBlockRange) {
        verified[@"codeBlockRange"]=codeBlockRange;verified[@"codeContentRange"]=codeContentRange;
    } else if(self.preferences.htmlTaskList) {
        // DOM/source verification above includes checkbox separator spaces.
        // The inline transaction styles label characters, not list syntax.
        // Exclude only the proven source task-prefix overlap for that comparison.
        NSMutableString *inlineText=[NSMutableString string];NSUInteger previous=0;
        for(NSValue *item in ranges) {
            NSRange selected=item.rangeValue;
            if(previous) [inlineText appendString:MPPreviewSourceSeparators(source,previous,selected.location)];
            previous=NSMaxRange(selected);
            NSRange separator=MPPreviewTaskSeparatorRange(source,selected.location);
            NSRange syntax=separator.location==NSNotFound ? NSMakeRange(0,0) : NSIntersectionRange(selected,separator);
            NSString *literal=[source substringWithRange:selected];
            if(syntax.length) literal=[literal stringByReplacingCharactersInRange:NSMakeRange(syntax.location-selected.location,syntax.length) withString:@""];
            [inlineText appendString:literal];
        }
        verified[@"inlineText"]=inlineText;
    }
    return verified;
}

// One block conversion engine serves verified preview selections and native
// source selections. Adapters supply ranges and parser-owned callout metadata.
// Container scope is independent of content-block scope. A parser-owned
// envelope is replaced as a whole, while its title/body remain source bytes.
- (NSArray<NSDictionary *> *)previewHeadingEditsInRange:(NSRange)content level:(NSUInteger)level source:(NSString *)source renderer:(MPRenderer *)renderer
{
    NSString *body=[source substringWithRange:content];
    NSXMLDocument *bodyDOM=MPPIParseHTML([renderer HTMLForMarkdownSnapshot:body]);
    NSXMLNode *firstRoot=[[bodyDOM nodesForXPath:@"//body/*" error:NULL] firstObject];
    if (![@[@"h1",@"h2",@"h3",@"h4",@"h5",@"h6"] containsObject:firstRoot.name.lowercaseString]) return @[];
    NSRegularExpression *ATX=[NSRegularExpression regularExpressionWithPattern:@"\\A(?:[ \t]*\r?\n)* {0,3}(#{1,6})(?!#)" options:0 error:NULL];
    NSTextCheckingResult *match=[ATX firstMatchInString:body options:0 range:NSMakeRange(0,body.length)];
    NSString *marks=[@"######" substringToIndex:level];
    if (match) {
        NSRange range=[match rangeAtIndex:1]; range.location+=content.location;
        return @[@{@"range":[NSValue valueWithRange:range],@"replacement":marks}];
    }
    NSUInteger start=content.location;
    while (start<NSMaxRange(content)) {
        NSUInteger end,contentsEnd;
        [source getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(start,0)];
        NSString *line=[source substringWithRange:NSMakeRange(start,contentsEnd-start)];
        if ([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) break;
        start=end;
    }
    if (start>=NSMaxRange(content)) return @[];
    NSRange first=[source lineRangeForRange:NSMakeRange(start,0)];
    if (NSMaxRange(first)>=NSMaxRange(content)) return @[];
    NSRange next=[source lineRangeForRange:NSMakeRange(NSMaxRange(first),0)];
    if (NSMaxRange(next)>NSMaxRange(content)) return @[];
    NSRange pair=NSMakeRange(start,NSMaxRange(next)-start);
    NSXMLDocument *DOM=MPPIParseHTML([renderer HTMLForMarkdownSnapshot:[source substringWithRange:pair]]);
    NSArray *roots=[DOM nodesForXPath:@"//body/*" error:NULL];
    NSXMLNode *root=roots.firstObject;
    if (roots.count!=1 || ![@[@"h1",@"h2"] containsObject:root.name.lowercaseString]) return @[];
    return @[@{@"range":[NSValue valueWithRange:NSMakeRange(start,0)],@"replacement":[marks stringByAppendingString:@" "]},
        @{@"range":[NSValue valueWithRange:next],@"replacement":@""}];
}

- (BOOL)commitPreviewStructuralEdits:(NSArray<NSDictionary *> *)edits selection:(NSRange)selection
{
    NSString *original=self.editor.string ?: @"", *result=original;
    NSRange restored=selection;
    NSArray *ordered=[edits sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        return [@([b[@"range"] rangeValue].location) compare:@([a[@"range"] rangeValue].location)];
    }];
    NSUInteger previous=original.length;
    for (NSDictionary *edit in ordered) {
        NSRange range=[edit[@"range"] rangeValue]; NSString *replacement=edit[@"replacement"];
        if (range.location>previous || range.length>previous-range.location || !replacement) return NO;
        previous=range.location;
        NSUInteger (^translate)(NSUInteger)=^NSUInteger(NSUInteger offset) {
            if (offset<range.location) return offset;
            if (offset>=NSMaxRange(range)) return offset-range.length+replacement.length;
            return range.location+MIN(offset-range.location,replacement.length);
        };
        NSUInteger start=translate(restored.location), end=translate(NSMaxRange(restored));
        restored=NSMakeRange(start,end-start);
        result=[result stringByReplacingCharactersInRange:range withString:replacement];
    }
    if ([result isEqualToString:original]) return YES;
    NSUInteger start=0, common=MIN(original.length,result.length);
    while (start<common && [original characterAtIndex:start]==[result characterAtIndex:start]) start++;
    start=MIN(start,MIN(selection.location,restored.location));
    NSUInteger oldEnd=original.length, newEnd=result.length;
    while (oldEnd>MAX(start,NSMaxRange(selection)) && newEnd>MAX(start,NSMaxRange(restored)) &&
        [original characterAtIndex:oldEnd-1]==[result characterAtIndex:newEnd-1]) {oldEnd--;newEnd--;}
    return [self replacePreviewRange:NSMakeRange(start,oldEnd-start)
        withString:[result substringWithRange:NSMakeRange(start,newEnd-start)]
        preservingSelection:selection restoringRange:NSMakeRange(restored.location-start,restored.length)];
}

// Extend only when the complete renderer proves both boundaries belong to
// the same paragraph and removing the provenance markers restores its exact
// semantic fingerprint. Blank lines/other blocks/opaque Markdown stay outside.
- (NSRange)previewParagraphRange:(NSRange)selection source:(NSString *)source renderer:(MPRenderer *)renderer
{
    NSRange region=[source lineRangeForRange:selection];
    NSString *begin=[NSString stringWithFormat:@"\uE000%@\uE001",NSUUID.UUID.UUIDString];
    NSString *finish=[NSString stringWithFormat:@"\uE002%@\uE003",NSUUID.UUID.UUIDString];
    NSArray *original=MPPIFingerprint([renderer HTMLForMarkdownSnapshot:source]);
    BOOL (^sameParagraph)(NSRange)=^BOOL(NSRange candidate) {
        NSUInteger contentsEnd;
        if (!candidate.length) return NO;
        [source getLineStart:NULL end:NULL contentsEnd:&contentsEnd forRange:NSMakeRange(NSMaxRange(candidate)-1,1)];
        if (contentsEnd<candidate.location) return NO;
        NSString *probe=[source stringByReplacingCharactersInRange:NSMakeRange(contentsEnd,0) withString:finish];
        probe=[probe stringByReplacingCharactersInRange:NSMakeRange(candidate.location,0) withString:begin];
        NSString *HTML=[renderer HTMLForMarkdownSnapshot:probe];
        NSXMLDocument *DOM=MPPIParseHTML(HTML);
        NSString *path=[NSString stringWithFormat:@"//p[contains(string(.),'%@') and contains(string(.),'%@')]",begin,finish];
        if ([DOM nodesForXPath:path error:NULL].count!=1) return NO;
        HTML=[[HTML stringByReplacingOccurrencesOfString:begin withString:@""] stringByReplacingOccurrencesOfString:finish withString:@""];
        return original && [MPPIFingerprint(HTML) isEqual:original];
    };
    if (!sameParagraph(region)) return region;
    // Collect physical boundaries once, then prove the farthest boundary with
    // binary search. A boundary beyond the current paragraph cannot contain
    // both provenance atoms in that same P. This avoids a silent line cap and
    // hundreds of complete-document parses for a long soft-wrapped paragraph.
    NSMutableArray<NSValue *> *candidates=[NSMutableArray array];
    NSRange expanded=region;
    while (expanded.location) {
        NSRange previous=[source lineRangeForRange:NSMakeRange(expanded.location-1,0)];
        if (![[source substringWithRange:previous] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) break;
        expanded=NSMakeRange(previous.location,NSMaxRange(region)-previous.location);
        [candidates addObject:[NSValue valueWithRange:expanded]];
    }
    NSUInteger lower=0,upper=candidates.count;
    while (lower<upper) {
        NSUInteger middle=lower+(upper-lower)/2;
        if (sameParagraph(candidates[middle].rangeValue)) lower=middle+1;
        else upper=middle;
    }
    if (lower) region=candidates[lower-1].rangeValue;
    [candidates removeAllObjects]; expanded=region;
    while (NSMaxRange(expanded)<source.length) {
        NSRange next=[source lineRangeForRange:NSMakeRange(NSMaxRange(expanded),0)];
        if (!next.length || ![[source substringWithRange:next] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) break;
        expanded=NSMakeRange(region.location,NSMaxRange(next)-region.location);
        [candidates addObject:[NSValue valueWithRange:expanded]];
    }
    lower=0; upper=candidates.count;
    while (lower<upper) {
        NSUInteger middle=lower+(upper-lower)/2;
        if (sameParagraph(candidates[middle].rangeValue)) lower=middle+1;
        else upper=middle;
    }
    if (lower) region=candidates[lower-1].rangeValue;
    return region;
}

- (BOOL)applyContainerFormattingValue:(NSString *)value selection:(NSDictionary *)verified callouts:(NSArray<NSDictionary *> *)callouts renderer:(MPRenderer *)renderer
{
    BOOL removing=[value isEqualToString:@"no-container"];
    BOOL toggle=[value isEqualToString:@"toggle"] || [@[@"toggle-h1",@"toggle-h2",@"toggle-h3",@"toggle-h4"] containsObject:value];
    NSString *type=[value isEqualToString:@"callout"] || toggle ? @"note" : [value hasPrefix:@"callout-"] ? [value substringFromIndex:8] : nil;
    if (!removing && !MPPreviewDefaultCalloutTitle(type,toggle)) return NO;
    NSString *source=self.editor.string ?: @"";
    NSRange selection=[verified[@"range"] rangeValue];
    if (selection.location>source.length || selection.length>source.length-selection.location) return NO;
    NSDictionary *container=nil;
    for (NSDictionary *candidate in callouts) {
        NSRange content=[candidate[@"sourceContentRange"] rangeValue];
        if (selection.location>=content.location && NSMaxRange(selection)<=NSMaxRange(content) &&
            (!container || content.length<[container[@"sourceContentRange"] rangeValue].length)) container=candidate;
    }
    NSMutableArray *edits=[NSMutableArray array];
    if (container) {
        NSRange opening=[container[@"sourceOpenRange"] rangeValue],closing=[container[@"sourceCloseRange"] rangeValue];
        if (NSMaxRange(closing)>source.length || NSMaxRange(opening)>closing.location) return NO;
        if (removing) {
            NSString *newline=[source containsString:@"\r\n"] ? @"\r\n" : @"\n";
            // The preprocessor makes callout delimiters block boundaries even
            // without authored blank lines. Retain those boundaries on unwrap.
            NSString *before=@"", *after=@"";
            if (opening.location) {
                NSRange previous=[source lineRangeForRange:NSMakeRange(opening.location-1,0)];
                if ([[source substringWithRange:previous] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) before=newline;
            }
            if (NSMaxRange(closing)<source.length) {
                NSRange next=[source lineRangeForRange:NSMakeRange(NSMaxRange(closing),0)];
                if ([[source substringWithRange:next] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) after=newline;
            }
            [edits addObject:@{@"range":[NSValue valueWithRange:opening],@"replacement":before}];
            [edits addObject:@{@"range":[NSValue valueWithRange:closing],@"replacement":after}];
        } else {
            NSUInteger contentsEnd;
            [source getLineStart:NULL end:NULL contentsEnd:&contentsEnd forRange:opening];
            NSString *ending=[source substringWithRange:NSMakeRange(contentsEnd,NSMaxRange(opening)-contentsEnd)];
            NSString *old=[source substringWithRange:NSMakeRange(opening.location,contentsEnd-opening.location)];
            NSUInteger colon=[old rangeOfString:@":"].location, count=0;
            if (colon==NSNotFound) return NO;
            while (colon+count<old.length && [old characterAtIndex:colon+count]==':') count++;
            NSString *prefix=[old substringToIndex:colon+count];
            NSString *collapse=toggle ? ([container[@"collapse"] isEqualToString:@"false"] ? @" collapse=\"false\"" : @" collapse=\"true\"") : @"";
            NSString *newOpen=[NSString stringWithFormat:@"%@ {.callout-%@%@}%@",prefix,type,collapse,ending];
            [edits addObject:@{@"range":[NSValue valueWithRange:opening],@"replacement":newOpen}];
            if ([value hasPrefix:@"toggle-h"]) {
                NSUInteger level=[[value substringFromIndex:8] integerValue];
                NSRange content=[container[@"sourceContentRange"] rangeValue];
                NSArray *titleEdits=[self previewHeadingEditsInRange:content level:level source:source renderer:renderer];
                if (titleEdits.count) [edits addObjectsFromArray:titleEdits];
                else {
                    NSString *heading=[[@"######" substringToIndex:level] stringByAppendingString:@" "];
                    NSString *newline=ending.length ? ending : @"\n";
                    NSString *title=[NSString stringWithFormat:@"%@%@%@",heading,MPPreviewDefaultCalloutTitle(type,YES),newline];
                    [edits addObject:@{@"range":[NSValue valueWithRange:NSMakeRange(content.location,0)],@"replacement":title}];
                }
            }
        }
        return [self commitPreviewStructuralEdits:edits selection:selection];
    }
    if (removing) return YES;
    NSRange region=verified[@"codeBlockRange"] ? [verified[@"codeBlockRange"] rangeValue] : [self previewParagraphRange:selection source:source renderer:renderer];
    for (NSDictionary *candidate in callouts) {
        NSRange opening=[candidate[@"sourceOpenRange"] rangeValue],closing=[candidate[@"sourceCloseRange"] rangeValue];
        NSRange envelope=NSMakeRange(opening.location,NSMaxRange(closing)-opening.location);
        // A mixed selection straddling an existing envelope is ambiguous:
        // refuse atomically instead of adding another container category.
        if (NSIntersectionRange(region,envelope).length) return NO;
    }
    NSString *body=[source substringWithRange:region];
    if ([body containsString:@":::"]) return NO;
    NSString *newline=[body containsString:@"\r\n"] ? @"\r\n" : @"\n";
    // The envelope owns its generated title. An authored heading in the
    // selected body remains a content heading, even when the new disclosure
    // requests another title level; the two scopes must never overwrite it.
    NSUInteger level=[value hasPrefix:@"toggle-h"] ? [[value substringFromIndex:8] integerValue] : 2;
    NSString *title=[NSString stringWithFormat:@"%@ %@%@",[@"######" substringToIndex:level],MPPreviewDefaultCalloutTitle(type,toggle),newline];
    NSString *opening=[NSString stringWithFormat:@"%@::: {.callout-%@%@}%@%@",newline,type,toggle ? @" collapse=\"true\"" : @"",newline,title];
    NSString *closing=[NSString stringWithFormat:@"%@:::%@",[body hasSuffix:newline] ? @"" : newline,newline];
    NSRange relativeSelection=NSMakeRange(selection.location-region.location,selection.length);
    NSRange relative=NSMakeRange(opening.length+relativeSelection.location,relativeSelection.length);
    NSString *replacement=[NSString stringWithFormat:@"%@%@%@",opening,body,closing];
    return [self replacePreviewRange:region withString:replacement preservingSelection:[verified[@"range"] rangeValue] restoringRange:relative];
}

- (BOOL)applyBlockFormattingValue:(NSString *)value selection:(NSDictionary *)verified callouts:(NSArray<NSDictionary *> *)callouts renderer:(MPRenderer *)renderer
{
    if ([value isEqualToString:@"no-container"] || [value hasPrefix:@"callout-"] ||
        [value isEqualToString:@"callout"] || [value hasPrefix:@"toggle"])
        return [self applyContainerFormattingValue:value selection:verified callouts:callouts renderer:renderer];
    NSString *source=self.editor.string ?: @"";
    NSRange range=[verified[@"range"] rangeValue],selectedRange=range;
    if (!value.length || ([value isEqualToString:@"tasks"] && !self.preferences.htmlTaskList) ||
        ([value isEqualToString:@"code-block"] && !self.preferences.extensionFencedCode)) return NO;
    if (range.length==0 && [@[@"unordered",@"ordered",@"tasks",@"quote",@"h1",@"h2",@"h3",@"h4",@"h5",@"h6"] containsObject:value]) {
        NSUInteger start,end;
        [source getLineStart:&start end:NULL contentsEnd:&end forRange:range];
        if (![[source substringWithRange:NSMakeRange(start,end-start)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) {
            NSString *prefix=[value isEqualToString:@"ordered"] ? @"1. " : [value isEqualToString:@"tasks"] ? @"- [ ] " : [value isEqualToString:@"quote"] ? @"> " : [value hasPrefix:@"h"] ? [[@"######" substringToIndex:[[value substringFromIndex:1] integerValue]] stringByAppendingString:@" "] : @"- ";
            return [self replacePreviewRange:NSMakeRange(start,end-start) withString:prefix
                preservingSelection:range restoringRange:NSMakeRange(prefix.length,0)];
        }
    }
    NSString *originalSource = source;
    NSRange originalSelection = selectedRange;
    NSMutableArray *structuralEdits = [NSMutableArray array];
    NSValue *codeBlock = verified[@"codeBlockRange"], *codeContent = verified[@"codeContentRange"];
    if (codeBlock) {
        if (!codeContent || [value isEqualToString:@"code-block"]) return codeContent != nil;
        NSRange block = codeBlock.rangeValue, content = codeContent.rangeValue;
        if (NSMaxRange(block)>source.length || content.location<block.location || NSMaxRange(content)>NSMaxRange(block)) return NO;
        // Code is literal text. Escape its entire body before exposing it
        // to Markdown, including unselected lines, so HTML and markers
        // cannot acquire meaning during the conversion.
        NSString *literal = [source substringWithRange:content];
        NSMutableString *escaped = [NSMutableString string];
        NSMutableArray *positions = [NSMutableArray arrayWithObject:@0];
        NSUInteger indentationEnd=0;
        for (NSUInteger i=0;i<literal.length;i++) {
            NSString *character=[literal substringWithRange:NSMakeRange(i,1)];
            // Four leading ASCII spaces (or a tab) would recreate an
            // indented code block. Nonbreaking spaces preserve the
            // visible indentation as plain Unicode Markdown text.
            BOOL lineStart=i==0 || [literal characterAtIndex:i-1]=='\n' || [literal characterAtIndex:i-1]=='\r';
            if (lineStart) {
                NSUInteger end=i;
                BOOL tab=NO;
                while (end<literal.length && ([literal characterAtIndex:end]==' ' || [literal characterAtIndex:end]=='\t')) {
                    tab|=[literal characterAtIndex:end]=='\t'; end++;
                }
                indentationEnd=tab || end-i>=4 ? end : i;
            }
            BOOL indented=i<indentationEnd;
            // A literal ::: must not become a callout delimiter after
            // exposing the code body to the surrounding Markdown parser.
            NSString *plain=indented ? ([character isEqualToString:@"\t"] ? @"\u00a0\u00a0\u00a0\u00a0" : @"\u00a0")
                : [character isEqualToString:@":"] ? @"\\:" : [self escapePreviewPlainText:character];
            [escaped appendString:plain];
            [positions addObject:@(escaped.length)];
        }
        [structuralEdits addObject:@{@"range":codeBlock,@"replacement":escaped,
            @"content":codeContent,@"positions":positions}];
    }
    if (!codeBlock && [@[@"unordered",@"ordered",@"tasks"] containsObject:value]) {
        NSMutableSet *paragraphs=[NSMutableSet set];
        for (NSValue *run in verified[@"runs"]) {
            NSRange lines=[source lineRangeForRange:run.rangeValue];
            NSUInteger cursor=lines.location;
            while(cursor<NSMaxRange(lines)) {
                NSRange line=[source lineRangeForRange:NSMakeRange(cursor,0)];
                NSRange paragraph=[self previewParagraphRange:line source:source renderer:renderer];
                // Boundary probes can alter delimiter flanking when intra-word
                // emphasis is disabled. Expand an ordinary inline paragraph
                // through the unmodified parser instead; balancing below must
                // still preserve the full document fingerprint before any edit.
                if (MPPIInlineOracle([renderer HTMLForMarkdownSnapshot:[source substringWithRange:paragraph]])) {
                    for(NSUInteger direction=0;direction<2;direction++) {
                        while(direction==0 ? paragraph.location>0 : NSMaxRange(paragraph)<source.length) {
                            NSUInteger neighbour=direction==0 ? paragraph.location-1 : NSMaxRange(paragraph);
                            NSRange adjacent=[source lineRangeForRange:NSMakeRange(neighbour,0)];
                            if(![[source substringWithRange:adjacent] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) break;
                            NSRange candidate=NSUnionRange(paragraph,adjacent);
                            if(candidate.length>20000 || !MPPIInlineOracle([renderer HTMLForMarkdownSnapshot:[source substringWithRange:candidate]])) break;
                            paragraph=candidate;
                        }
                    }
                }
                NSValue *key=[NSValue valueWithRange:paragraph];
                if(![paragraphs containsObject:key]) {
                    [paragraphs addObject:key];
                    NSDictionary *balanced=MPPIBalanceSoftLines([source substringWithRange:paragraph],^NSString *(NSString *markdown) {
                        return [renderer HTMLForMarkdownSnapshot:markdown];
                    });
                    if(!balanced) return NO;
                    if(balanced[@"replacement"]) {
                        NSString *candidate=[source stringByReplacingCharactersInRange:paragraph withString:balanced[@"replacement"]];
                        if(![MPPIFingerprint([renderer HTMLForMarkdownSnapshot:candidate]) isEqual:MPPIFingerprint([renderer HTMLForMarkdownSnapshot:source])]) return NO;
                        [structuralEdits addObject:@{@"range":key,@"content":key,@"replacement":balanced[@"replacement"],@"positions":balanced[@"positions"]}];
                    }
                }
                cursor=MAX(NSMaxRange(line),NSMaxRange(paragraph));
            }
        }
    }
    [structuralEdits sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        return [@([b[@"range"] rangeValue].location) compare:@([a[@"range"] rangeValue].location)];
    }];
    NSMutableArray *workingRuns = [verified[@"runs"] mutableCopy];
    NSUInteger previousEditStart=source.length;
    for (NSDictionary *edit in structuralEdits) {
        NSRange removed=[edit[@"range"] rangeValue];
        NSString *replacement=edit[@"replacement"];
        if (NSMaxRange(removed)>previousEditStart) return NO;
        previousEditStart=removed.location;
        NSUInteger (^translate)(NSUInteger)=^NSUInteger(NSUInteger position) {
            if (position<=removed.location) return position;
            if (position>=NSMaxRange(removed)) return position-removed.length+replacement.length;
            if (!edit[@"positions"]) return removed.location;
            NSRange content=[edit[@"content"] rangeValue];
            NSUInteger offset=MIN(position>content.location ? position-content.location : 0,content.length);
            return removed.location+[edit[@"positions"][offset] unsignedIntegerValue];
        };
        NSUInteger selectionStart=translate(selectedRange.location);
        NSUInteger selectionEnd=translate(NSMaxRange(selectedRange));
        selectedRange=NSMakeRange(selectionStart,selectionEnd-selectionStart);
        for (NSUInteger i=0;i<workingRuns.count;i++) {
            NSRange run=[workingRuns[i] rangeValue];
            NSUInteger start=translate(run.location),end=translate(NSMaxRange(run));
            workingRuns[i]=[NSValue valueWithRange:NSMakeRange(start,end-start)];
        }
        source=[source stringByReplacingCharactersInRange:removed withString:replacement];
    }
    if (structuralEdits.count) {
        NSRange first=[workingRuns.firstObject rangeValue],last=[workingRuns.lastObject rangeValue];
        range=NSMakeRange(first.location,NSMaxRange(last)-first.location);
        NSMutableDictionary *updated=[verified mutableCopy]; updated[@"runs"]=workingRuns;
        verified=updated;
    }
    NSRange lineRange = [source lineRangeForRange:range];
    NSMutableArray<NSMutableDictionary *> *sourceLines = [NSMutableArray array];
    NSRegularExpression *setext = [NSRegularExpression regularExpressionWithPattern:@"^(?:=+|-+)[ ]*$" options:0 error:NULL];
    NSRegularExpression *singleParagraph = [NSRegularExpression regularExpressionWithPattern:@"^\\s*<p>.*?</p>\\s*$" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
    NSRegularExpression *singleHeading = [NSRegularExpression regularExpressionWithPattern:@"^\\s*<h[12]\\b[^>]*>.*?</h[12]>\\s*$" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
    NSUInteger offset = lineRange.location;
    while (offset < NSMaxRange(lineRange)) {
        NSUInteger start, end, contentsEnd;
        [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
        NSRange contents = NSMakeRange(start,contentsEnd-start);
        BOOL selectedLine = NO;
        for (NSValue *run in verified[@"runs"])
            if (NSIntersectionRange(contents,run.rangeValue).length) { selectedLine = YES; break; }
        [sourceLines addObject:[@{@"range":[NSValue valueWithRange:NSMakeRange(start,end-start)],
            @"contents":[NSValue valueWithRange:contents],@"text":[source substringWithRange:contents],
            @"ending":[source substringWithRange:NSMakeRange(contentsEnd,end-contentsEnd)],
            @"selected":@(selectedLine)} mutableCopy]];
        offset = end;
    }
    // A Setext title's visible text does not include its next source line.
    // Consume that line only when the real renderer proves that the pair
    // is one heading, so an unrelated thematic break is never removed.
    if (offset < source.length && [sourceLines.lastObject[@"selected"] boolValue]) {
        NSUInteger start, end, contentsEnd;
        [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
        NSString *text = [source substringWithRange:NSMakeRange(start,contentsEnd-start)];
        NSDictionary *previous = sourceLines.lastObject;
        if ([setext firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]) {
            NSRange pair = NSMakeRange([previous[@"range"] rangeValue].location,end-[previous[@"range"] rangeValue].location);
            NSString *HTML = [renderer HTMLForMarkdownSnapshot:[source substringWithRange:pair]];
            NSString *beforeHTML=[renderer HTMLForMarkdownSnapshot:previous[@"text"]];
            if ([singleParagraph firstMatchInString:beforeHTML options:0 range:NSMakeRange(0,beforeHTML.length)] &&
                [singleHeading firstMatchInString:HTML options:0 range:NSMakeRange(0,HTML.length)]) {
                [sourceLines addObject:[@{@"range":[NSValue valueWithRange:NSMakeRange(start,end-start)],
                    @"contents":[NSValue valueWithRange:NSMakeRange(start,contentsEnd-start)],@"text":text,
                    @"ending":[source substringWithRange:NSMakeRange(contentsEnd,end-contentsEnd)],
                    @"selected":@NO,@"setext":@YES} mutableCopy]];
                lineRange.length = end-lineRange.location;
            }
        }
    }
    NSMutableString *blockBody = [NSMutableString string];
    NSUInteger blockStart=NSNotFound, blockEnd=NSNotFound;
    for (NSUInteger i=0;i<sourceLines.count;i++) {
        NSMutableDictionary *line = sourceLines[i];
        if (i && ![line[@"setext"] boolValue] && [sourceLines[i-1][@"selected"] boolValue] &&
            [setext firstMatchInString:line[@"text"] options:0 range:NSMakeRange(0,[line[@"text"] length])]) {
            NSRange before = [sourceLines[i-1][@"range"] rangeValue], current = [line[@"range"] rangeValue];
            NSString *HTML = [renderer HTMLForMarkdownSnapshot:[source substringWithRange:NSMakeRange(before.location,NSMaxRange(current)-before.location)]];
            NSString *beforeHTML=[renderer HTMLForMarkdownSnapshot:sourceLines[i-1][@"text"]];
            if ([singleParagraph firstMatchInString:beforeHTML options:0 range:NSMakeRange(0,beforeHTML.length)] &&
                [singleHeading firstMatchInString:HTML options:0 range:NSMakeRange(0,HTML.length)]) line[@"setext"] = @YES;
        }
        if ([line[@"setext"] boolValue] && i)
            sourceLines[i-1][@"consumedSetextEnd"]=@(NSMaxRange([line[@"range"] rangeValue]));
        if (![line[@"setext"] boolValue]) {
            NSRange original=[line[@"range"] rangeValue];
            if (selectedRange.location>=original.location && selectedRange.location<NSMaxRange(original))
                blockStart=blockBody.length+selectedRange.location-original.location;
            if (NSMaxRange(selectedRange)>original.location && NSMaxRange(selectedRange)<=NSMaxRange(original))
                blockEnd=blockBody.length+NSMaxRange(selectedRange)-original.location;
            [blockBody appendString:line[@"text"]]; [blockBody appendString:line[@"ending"]];
        }
    }
    NSString *body = blockBody;
    NSString *newline = @"";
    if (body.length) {
        NSUInteger contentsEnd;
        [body getLineStart:NULL end:NULL contentsEnd:&contentsEnd forRange:NSMakeRange(body.length-1,1)];
        newline = [body substringFromIndex:contentsEnd];
        body = [body substringToIndex:contentsEnd];
    }
    NSDictionary *prefixes = @{@"paragraph":@"", @"h1":@"# ", @"h2":@"## ", @"h3":@"### ", @"h4":@"#### ", @"h5":@"##### ", @"h6":@"###### ",
        @"unordered":@"- ", @"ordered":@"1. ", @"tasks":@"- [ ] ", @"quote":@"> "};
    NSString *prefix = [value isEqualToString:@"code-block"] ? @"" : prefixes[value];
    NSRange restoredSelection = blockStart!=NSNotFound && blockEnd!=NSNotFound && blockEnd>=blockStart
        ? NSMakeRange(blockStart,blockEnd-blockStart) : NSMakeRange(NSNotFound,0);
    void (^normalizeTaskSpacing)(NSXMLDocument *) = ^(NSXMLDocument *DOM) {
        // The renderer leaves the Markdown separator after its generated
        // checkbox. It is syntax spacing, not a character of the label.
        for (NSXMLNode *input in [DOM nodesForXPath:@"//li[@class='task-list-item']/input[@type='checkbox']" error:NULL]) {
            NSXMLNode *sibling=input.nextSibling;
            if (sibling.kind!=NSXMLTextKind) continue;
            NSString *text=sibling.stringValue;
            NSUInteger offset=0;
            while (offset<text.length && ([text characterAtIndex:offset]==' ' || [text characterAtIndex:offset]=='\t')) offset++;
            if (offset) sibling.stringValue=[text substringFromIndex:offset];
        }
    };
    if (prefix != nil) {
        NSString *taskMarker = self.preferences.htmlTaskList ? @"(?:\\[[ xX]\\][ \\t]+)?" : @"";
        NSString *markerPattern = [NSString stringWithFormat:@"^ {0,3}(?:#{1,6}[ \\t]+|>[ \\t]?|[-+*][ \\t]+%@|[0-9]+\\.[ \\t]+)",taskMarker];
        NSRegularExpression *markers = [NSRegularExpression regularExpressionWithPattern:markerPattern options:0 error:NULL];
        NSRegularExpression *headingHTML = [NSRegularExpression regularExpressionWithPattern:@"^\\s*<h[1-6]\\b[^>]*>(.*?)</h[1-6]>\\s*$" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
        NSMutableString *processed = [NSMutableString string];
        NSUInteger restoredStart = NSNotFound, restoredEnd = NSNotFound;
        NSUInteger orderedItemNumber = 0;
        BOOL codeSelectionProven=YES;
        for (NSDictionary *line in sourceLines) {
            if ([line[@"setext"] boolValue]) continue;
            NSString *text = line[@"text"];
            NSUInteger outputStart = processed.length, removedPrefix = 0, addedPrefix = 0, literalEscape = NSNotFound;
            NSString *outputText = text;
            NSArray<NSNumber *> *codePositions=nil;
            // A contiguous visual selection can cross blank separators,
            // comments and images that have no selected text. Convert only
            // source lines touched by an independently proven text run.
            if ([line[@"selected"] boolValue] && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
                NSString *linePrefix = [value isEqualToString:@"ordered"]
                    ? [NSString stringWithFormat:@"%lu. ",(unsigned long)++orderedItemNumber] : prefix;
                addedPrefix=linePrefix.length;
                NSString *plain = text;
                NSString *originalHTML = [renderer HTMLForMarkdownSnapshot:text];
                NSXMLDocument *originalDOM = MPPIParseHTML(originalHTML);
                normalizeTaskSpacing(originalDOM);
                NSArray *roots = [originalDOM nodesForXPath:@"//body/*" error:NULL];
                if (roots.count!=1) return NO;
                NSXMLNode *content = roots.firstObject;
                NSRegularExpression *quoteMarker = [NSRegularExpression regularExpressionWithPattern:@"^ {0,3}>[ \\t]?" options:0 error:NULL];
                NSRegularExpression *ATX = [NSRegularExpression regularExpressionWithPattern:@"^ {0,3}#{1,6}[ \\t]+" options:0 error:NULL];
                // Descend through the ORIGINAL block hierarchy. Once a
                // heading/paragraph is reached, a literal prefix in its
                // inline content must not be interpreted as another block.
                while (YES) {
                    NSString *tag=content.name.lowercaseString;
                    BOOL quote=[tag isEqualToString:@"blockquote"], list=[@[@"ul",@"ol"] containsObject:tag];
                    BOOL isHeading=[@[@"h1",@"h2",@"h3",@"h4",@"h5",@"h6"] containsObject:tag];
                    if (!quote && !list && !isHeading) break;
                    NSRegularExpression *expression=quote ? quoteMarker : isHeading ? ATX : markers;
                    NSTextCheckingResult *marker=[expression firstMatchInString:plain options:0 range:NSMakeRange(0,plain.length)];
                    if (!marker) break;
                    removedPrefix+=marker.range.length;
                    plain=[plain substringFromIndex:marker.range.length];
                    if (isHeading) break;
                    NSArray *children=[content nodesForXPath:@"./*" error:NULL];
                    if (children.count!=1) return NO;
                    content=children.firstObject;
                    if (list) {
                        if (![content.name.lowercaseString isEqualToString:@"li"]) return NO;
                        NSArray *blocks=[content nodesForXPath:@"./p|./blockquote|./ul|./ol|./h1|./h2|./h3|./h4|./h5|./h6" error:NULL];
                        if (blocks.count==1) content=blocks.firstObject; else break;
                    }
                }
                originalHTML=content.XMLString;
                NSTextCheckingResult *heading=[headingHTML firstMatchInString:originalHTML options:0 range:NSMakeRange(0,originalHTML.length)];
                if (heading) {
                    NSUInteger end=plain.length;
                    while (end && [plain characterAtIndex:end-1]=='#') end--;
                    while (end && [plain characterAtIndex:end-1]==' ') end--;
                    NSString *candidate=[plain substringToIndex:end];
                    NSString *HTML=[renderer HTMLForMarkdownSnapshot:[@"###### " stringByAppendingString:candidate]];
                    NSTextCheckingResult *probe=[headingHTML firstMatchInString:HTML options:0 range:NSMakeRange(0,HTML.length)];
                    if (probe && [[HTML substringWithRange:[probe rangeAtIndex:1]] isEqualToString:[originalHTML substringWithRange:[heading rangeAtIndex:1]]]) plain=candidate;
                }
                NSString *expectedText=[content.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
                NSString *expectedTag=[value hasPrefix:@"h"] ? value : ([value isEqualToString:@"paragraph"] || [value isEqualToString:@"code-block"]) ? @"p" : [value isEqualToString:@"quote"] ? @"blockquote" : [value isEqualToString:@"ordered"] ? @"ol" : @"ul";
                // A code block displays literal rendered content. Do not
                // carry inline Markdown or prose-only protective escapes
                // into the new fenced body.
                BOOL codeTarget=[value isEqualToString:@"code-block"];
                if (codeTarget) {
                    // Text extraction cannot preserve images or embedded
                    // controls. Reject the whole transaction before losing
                    // any non-text content; generated task checkboxes are
                    // the only controls removed with their list syntax.
                    NSArray *nonText=[content nodesForXPath:@".//img|.//svg|.//math|.//iframe|.//object|.//video|.//audio|.//canvas|.//script|.//style|.//textarea|.//select|.//input[not(@type='checkbox' and parent::li[@class='task-list-item'])]" error:NULL];
                    if (nonText.count) return NO;
                    codePositions=MPPIProvenance(plain,expectedText);
                    if (!codePositions) codeSelectionProven=NO;
                    plain=expectedText;
                }
                BOOL proved=codeTarget;
                for (NSUInteger attempt=0;!proved && attempt<2;attempt++) {
                    NSString *candidate=[linePrefix stringByAppendingString:plain];
                    NSXMLDocument *DOM=MPPIParseHTML([renderer HTMLForMarkdownSnapshot:candidate]);
                    normalizeTaskSpacing(DOM);
                    NSArray<NSXMLNode *> *elements=[DOM nodesForXPath:@"//body/*" error:NULL];
                    NSXMLNode *body=[[DOM nodesForXPath:@"//body" error:NULL] firstObject];
                    NSString *actualText=[body.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
                    if (elements.count==1 && [elements.firstObject.name.lowercaseString isEqualToString:expectedTag] && [actualText isEqualToString:expectedText]) { proved=YES; break; }
                    if (attempt) break;
                    NSRegularExpression *literalMarker=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}(?:(>)|([#*+-])(?:[ \\t]|$)|[0-9]+(\\.)(?:[ \\t]|$)|(`{3,}|~{3,}))" options:0 error:NULL];
                    NSTextCheckingResult *literal=[literalMarker firstMatchInString:plain options:0 range:NSMakeRange(0,plain.length)];
                    if (!literal) break;
                    NSRange punctuation=NSMakeRange(NSNotFound,0);
                    for (NSUInteger group=1;group<literal.numberOfRanges;group++) if ([literal rangeAtIndex:group].location!=NSNotFound) { punctuation=[literal rangeAtIndex:group]; break; }
                    if (punctuation.location==NSNotFound) break;
                    literalEscape=punctuation.location;
                    plain=[plain stringByReplacingCharactersInRange:NSMakeRange(punctuation.location,0) withString:@"\\"];
                }
                if (!proved) return NO;
                outputText = [linePrefix stringByAppendingString:plain];
                [processed appendString:outputText];
                // Look past consumed Setext metadata: the first remaining
                // neighbor must not turn the requested paragraph into a heading.
                NSRange originalLine = [line[@"range"] rangeValue];
                NSNumber *consumedEnd=line[@"consumedSetextEnd"];
                NSUInteger nextOffset=consumedEnd ? consumedEnd.unsignedIntegerValue : NSMaxRange(originalLine);
                if (!prefix.length && (heading || consumedEnd) && nextOffset<source.length) {
                    NSUInteger nextStart, nextEnd, nextContentsEnd;
                    [source getLineStart:&nextStart end:&nextEnd contentsEnd:&nextContentsEnd forRange:NSMakeRange(nextOffset,0)];
                    NSString *nextText = [source substringWithRange:NSMakeRange(nextStart,nextContentsEnd-nextStart)];
                    if ([setext firstMatchInString:nextText options:0 range:NSMakeRange(0,nextText.length)]) {
                        [processed appendString:line[@"ending"]];
                    }
                }
            } else {
                if ([value isEqualToString:@"code-block"] && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) {
                    NSRegularExpression *emptyQuote=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}(?:>[ \t]?)+[ \t]*$" options:0 error:NULL];
                    if ([emptyQuote firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]) {
                        NSXMLDocument *DOM=MPPIParseHTML([renderer HTMLForMarkdownSnapshot:text]);
                        NSArray<NSXMLNode *> *roots=[DOM nodesForXPath:@"//body/*" error:NULL];
                        NSXMLNode *body=[[DOM nodesForXPath:@"//body" error:NULL] firstObject];
                        BOOL empty=body && ![body.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
                        if (!empty || (roots.count && (roots.count!=1 || ![roots.firstObject.name.lowercaseString isEqualToString:@"blockquote"]))) return NO;
                        outputText=@"";
                    } else return NO; // No selected rendered text proves this source line.
                }
                [processed appendString:outputText];
            }
            // Carry exact source endpoints through each line's prefix and
            // suffix edits. Searching the old union text cannot work when
            // another selected paragraph gained markup inside that union.
            NSRange original = [line[@"range"] rangeValue];
            NSUInteger positions[] = {selectedRange.location,NSMaxRange(selectedRange)};
            for (NSUInteger boundary=0;boundary<2;boundary++) {
                NSUInteger position = positions[boundary];
                BOOL belongs = selectedRange.length == 0
                    ? position>=original.location && position<=NSMaxRange(original)
                    : (boundary == 0 ? position>=original.location && position<NSMaxRange(original)
                       : position>original.location && position<=NSMaxRange(original));
                if (!belongs) continue;
                NSUInteger relative = position-original.location, mapped;
                if (relative>text.length) mapped = outputText.length+relative-text.length;
                else {
                    NSUInteger plainPosition=MIN(relative>removedPrefix ? relative-removedPrefix : 0,outputText.length-addedPrefix-(literalEscape!=NSNotFound ? 1 : 0));
                    if (codePositions) {
                        NSUInteger raw=relative>removedPrefix ? relative-removedPrefix : 0;
                        plainPosition=0;
                        for (NSNumber *position in codePositions) {
                            if (position.unsignedIntegerValue>=raw) break;
                            plainPosition++;
                        }
                    }
                    mapped=addedPrefix+plainPosition+(literalEscape!=NSNotFound && plainPosition>=literalEscape ? 1 : 0);
                }
                if (boundary==0) restoredStart=outputStart+mapped; else restoredEnd=outputStart+mapped;
            }
            [processed appendString:line[@"ending"]];
        }
        if (restoredStart!=NSNotFound && restoredEnd!=NSNotFound && restoredEnd>=restoredStart)
            restoredSelection=NSMakeRange(restoredStart,restoredEnd-restoredStart);
        body = newline.length && [processed hasSuffix:newline] ? [processed substringToIndex:processed.length-newline.length] : processed;
        if ([value isEqualToString:@"code-block"] && !codeSelectionProven) {
            NSString *visible=verified[@"text"];
            NSRange occurrence=[body rangeOfString:visible options:NSLiteralSearch];
            BOOL unique=occurrence.location!=NSNotFound &&
                [body rangeOfString:visible options:NSLiteralSearch range:NSMakeRange(occurrence.location+1,body.length-occurrence.location-1)].location==NSNotFound;
            restoredSelection=unique ? occurrence : NSMakeRange(NSNotFound,0);
        }
    }
    if ([value isEqualToString:@"code-block"]) {
        NSUInteger longest = 0, run = 0;
        for (NSUInteger i=0;i<body.length;i++) { run=[body characterAtIndex:i]=='`'?run+1:0;longest=MAX(longest,run); }
        NSString *fence = [@"" stringByPaddingToLength:MAX((NSUInteger)3,longest+1) withString:@"`" startingAtIndex:0];
        NSString *ending=newline.length ? newline : [source containsString:@"\r\n"] ? @"\r\n" : @"\n";
        NSCharacterSet *whitespace=NSCharacterSet.whitespaceAndNewlineCharacterSet;
        BOOL blankBefore=NO,blankAfter=NO;
        if (lineRange.location) {
            NSRange previous=[source lineRangeForRange:NSMakeRange(lineRange.location-1,0)];
            blankBefore=![[source substringWithRange:previous] stringByTrimmingCharactersInSet:whitespace].length;
        }
        if (NSMaxRange(lineRange)<source.length) {
            NSRange next=[source lineRangeForRange:NSMakeRange(NSMaxRange(lineRange),0)];
            blankAfter=![[source substringWithRange:next] stringByTrimmingCharactersInSet:whitespace].length;
        }
        // Separators survive when a fence is removed. Reuse those physical
        // blank lines instead of growing the document on each conversion.
        NSString *before=blankBefore ? @"" : ending,*after=blankAfter ? @"" : ending;
        if (restoredSelection.location!=NSNotFound) restoredSelection.location+=before.length+fence.length+ending.length;
        body = [NSString stringWithFormat:@"%@%@%@%@%@%@%@%@",before,fence,ending,body,ending,fence,ending,after];
        newline=@""; // Both fence terminators and separators are already present.
    } else if ([value isEqualToString:@"math-block"]) {
        restoredSelection=NSMakeRange(NSNotFound,0); // Generated math is not mapped for editing.
        if (!self.preferences.htmlMathJax || [body containsString:@"$$"]) return NO;
        body = [NSString stringWithFormat:@"\n$$\n%@\n$$\n",body];
    } else if (prefix == nil) return NO;
    if (newline.length) body = [body stringByAppendingString:newline];
    NSString *result=[source stringByReplacingCharactersInRange:lineRange withString:body];
    if (!codeBlock && [@[@"unordered",@"ordered",@"tasks"] containsObject:value]) {
        NSArray *(^inlineFingerprint)(NSString *)=^NSArray *(NSString *markdown) {
            NSXMLDocument *DOM=MPPIParseHTML([renderer HTMLForMarkdownSnapshot:markdown]);
            normalizeTaskSpacing(DOM);
            NSXMLNode *body=[[DOM nodesForXPath:@"//body" error:NULL] firstObject];
            if(!body) return nil;
            NSMutableArray *tokens=[NSMutableArray array],*characters=[NSMutableArray array];
            MPPIFingerprintNode(body,0,tokens);
            for(NSDictionary *token in tokens) if(token[@"text"]) [characters addObject:token];
            return characters;
        };
        NSArray *before=inlineFingerprint(originalSource);
        if(!before || ![before isEqual:inlineFingerprint(result)]) return NO;
    }
    if (!structuralEdits.count)
        return [self replacePreviewRange:lineRange withString:body preservingSelection:selectedRange restoringRange:restoredSelection];
    // Commit the structural unwrap and formatting as one native edit. A
    // minimal contiguous envelope retains all neighboring source bytes.
    NSUInteger start=0,common=MIN(originalSource.length,result.length);
    while (start<common && [originalSource characterAtIndex:start]==[result characterAtIndex:start]) start++;
    NSRange finalSelection=restoredSelection.location==NSNotFound ? restoredSelection
        : NSMakeRange(lineRange.location+restoredSelection.location,restoredSelection.length);
    start=MIN(start,originalSelection.location);
    if (finalSelection.location!=NSNotFound) start=MIN(start,finalSelection.location);
    NSUInteger oldEnd=originalSource.length,newEnd=result.length;
    while (oldEnd>MAX(start,NSMaxRange(originalSelection)) &&
        newEnd>MAX(start,finalSelection.location==NSNotFound ? start : NSMaxRange(finalSelection)) &&
        [originalSource characterAtIndex:oldEnd-1]==[result characterAtIndex:newEnd-1]) { oldEnd--;newEnd--; }
    NSRange replacementRange=NSMakeRange(start,oldEnd-start);
    NSRange restoration=finalSelection.location==NSNotFound ? finalSelection
        : NSMakeRange(finalSelection.location-start,finalSelection.length);
    return [self replacePreviewRange:replacementRange withString:[result substringWithRange:NSMakeRange(start,newEnd-start)]
        preservingSelection:originalSelection restoringRange:restoration];
}

// The selected DOM leaves are source-proven by verifiedPreviewSelection. Column
// indices come from those leaves, never from an index supplied by the page.
// A parser round trip proves that changing a candidate separator affects only
// the requested columns of that exact table, including nested containers.
- (BOOL)alignPreviewTable:(NSDictionary *)payload selection:(NSDictionary *)verified value:(NSString *)alignment
{
    if (![@[@"left",@"center",@"right"] containsObject:alignment]) return NO;
    JSContext *context=self.preview.mainFrame.javaScriptContext;
    NSArray *runs=payload[@"runs"] ?: @[payload];
    NSMutableArray *ids=[NSMutableArray array];
    for (NSDictionary *run in runs) [ids addObject:run[@"id"]];
    context[@"__mpTableIDs"]=ids;
    NSDictionary *table=[[context evaluateScript:@"(function(){var cells=__mpTableIDs.map(function(id){var n=macdownPreviewEditor.elements().spans.find(function(span){return span._mpID===id;});return n&&n.closest('td,th');}),t=cells[0]&&cells[0].closest('table');if(!t||cells.some(function(c){return !c||c.closest('table')!==t;}))return null;return {index:Array.from(document.querySelectorAll('table')).indexOf(t),columns:Array.from(new Set(cells.map(function(c){return c.cellIndex;}))),width:t.rows[0].cells.length};})()"] toDictionary];
    if (!table || ![table[@"columns"] count]) return NO;
    context[@"__mpTableTarget"]=table;
    context[@"__mpTableOriginalHTML"]=[self.renderer HTMLForMarkdownSnapshot:self.editor.string];
    // Use an alternate alignment for the proof even if the requested alignment
    // is already active: an unchanged DOM cannot identify a source separator.
    NSString *probeAlignment=[[context evaluateScript:@"(function(){var d=new DOMParser().parseFromString(__mpTableOriginalHTML,'text/html'),t=d.querySelectorAll('table')[__mpTableTarget.index];return t&&__mpTableTarget.columns.every(function(c){return Array.from(t.rows).every(function(r){return r.cells[c]&&r.cells[c].style.textAlign==='center';});})?'right':'center';})()"] toString];
    NSString *proof=@"(function(){var a=new DOMParser().parseFromString(__mpTableOriginalHTML,'text/html'),b=new DOMParser().parseFromString(__mpTableCandidateHTML,'text/html'),ta=a.querySelectorAll('table')[__mpTableTarget.index],tb=b.querySelectorAll('table')[__mpTableTarget.index];if(!ta||!tb||ta.rows.length!==tb.rows.length)return false;for(var i=0;i<ta.rows.length;i++){if(ta.rows[i].cells.length!==__mpTableTarget.width||tb.rows[i].cells.length!==__mpTableTarget.width)return false;for(var j=0;j<__mpTableTarget.columns.length;j++){var c=__mpTableTarget.columns[j],x=ta.rows[i].cells[c],y=tb.rows[i].cells[c];if(!x||!y||y.style.textAlign!==__mpTableProbeAlignment)return false;[x,y].forEach(function(cell){cell.style.removeProperty('text-align');if(!cell.getAttribute('style'))cell.removeAttribute('style');});}}return a.body.innerHTML===b.body.innerHTML;})()";
    context[@"__mpTableProbeAlignment"]=probeAlignment;
    NSString *source=self.editor.string;
    NSRange selection=[verified[@"range"] rangeValue];
    NSUInteger selectionLineEnd=NSMaxRange([source lineRangeForRange:NSMakeRange(NSMaxRange(selection),0)]);
    NSUInteger scanEnd=selectionLineEnd<source.length ? NSMaxRange([source lineRangeForRange:NSMakeRange(selectionLineEnd,0)]) : source.length;
    NSRegularExpression *prefix=[NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(?:>[ \\t]*)*" options:0 error:NULL];
    NSRegularExpression *token=[NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(:?-+:?)[ \\t]*$" options:0 error:NULL];
    NSMutableArray *candidates=[NSMutableArray array];
    [source enumerateSubstringsInRange:NSMakeRange(0,scanEnd) options:NSStringEnumerationByLines usingBlock:^(NSString *line, NSRange lineRange, NSRange enclosingRange, BOOL *stop){
        NSUInteger start=[prefix firstMatchInString:line options:0 range:NSMakeRange(0,line.length)].range.length;
        NSString *body=[line substringFromIndex:start];
        NSArray *parts=[body componentsSeparatedByString:@"|"];
        NSMutableArray *ranges=[NSMutableArray array];NSUInteger offset=start;
        for (NSUInteger i=0;i<parts.count;i++) {
            NSString *part=parts[i];
            BOOL edge=(i==0 || i==parts.count-1) && ![part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length;
            if (!edge) {
                NSTextCheckingResult *match=[token firstMatchInString:part options:0 range:NSMakeRange(0,part.length)];
                if (!match) return;
                NSRange range=[match rangeAtIndex:1];range.location+=lineRange.location+offset;
                [ranges addObject:[NSValue valueWithRange:range]];
            }
            offset+=part.length+1;
        }
        if (ranges.count==[table[@"width"] unsignedIntegerValue]) [candidates addObject:ranges];
    }];
    NSArray *columns=[table[@"columns"] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger probes=0;
    for (NSArray *ranges in candidates.reverseObjectEnumerator) {
        if (++probes>64) break;
        NSMutableString *(^change)(NSString *)=^NSMutableString *(NSString *value){
            NSMutableString *result=[source mutableCopy];
            for (NSNumber *column in columns.reverseObjectEnumerator) {
                NSRange range=[ranges[column.unsignedIntegerValue] rangeValue];
                NSString *dashes=[[source substringWithRange:range] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
                while (dashes.length<3) dashes=[dashes stringByAppendingString:@"-"];
                NSString *replacement=[NSString stringWithFormat:@"%@%@%@",[value isEqual:@"right"]?@"":@":",dashes,[value isEqual:@"left"]?@"":@":"];
                [result replaceCharactersInRange:range withString:replacement];
            }
            return result;
        };
        context[@"__mpTableCandidateHTML"]=[self.renderer HTMLForMarkdownSnapshot:change(probeAlignment)];
        if (![[context evaluateScript:proof] toBool]) continue;
        NSString *result=change(alignment);
        if ([result isEqual:source]) return YES;
        // Replace one envelope and retain the exact selected source occurrence.
        NSRange first=[ranges.firstObject rangeValue],last=[ranges.lastObject rangeValue];
        NSUInteger start=MIN(first.location,selection.location),end=MAX(NSMaxRange(last),NSMaxRange(selection));
        NSInteger delta=(NSInteger)result.length-(NSInteger)source.length;
        NSUInteger selectedStart=selection.location+(NSMaxRange(last)<=selection.location ? delta : 0);
        NSRange envelope=NSMakeRange(start,end-start);
        NSRange restored=NSMakeRange(selectedStart-start,selection.length);
        return [self replacePreviewRange:envelope withString:[result substringWithRange:NSMakeRange(start,envelope.length+delta)] preservingSelection:selection restoringRange:restored];
    }
    return NO;
}

- (NSString *)previewFormattingHTMLForPayload:(NSDictionary *)payload
{
    // Reuse the committed transaction's validation and conversion. Capture its
    // proposed source before any text-storage, undo, selection or render changes.
    if (self.previewFormattingProbe || ![payload isKindOfClass:NSDictionary.class] ||
        ![@[@"block", @"math"] containsObject:payload[@"action"]]) return nil;
    self.previewFormattingProbe = YES;
    self.previewFormattingProbeSource = self.editor.string;
    @try {
        if (![self applyPreviewEditPayload:payload]) return nil;
        return [self.renderer HTMLForMarkdownSnapshot:self.previewFormattingProbeSource];
    } @finally {
        self.previewFormattingProbe = NO;
        self.previewFormattingProbeSource = nil;
    }
}

- (BOOL)applyPreviewEditPayload:(NSDictionary *)payload
{
    if (![payload isKindOfClass:NSDictionary.class] || self.documentClosed || self.printing ||
        ![payload[@"token"] isKindOfClass:NSString.class] ||
        ![payload[@"token"] isEqualToString:self.previewEditToken] ||
        ![self.previewEditToken isEqualToString:self.renderer.checkboxBridgeToken] ||
        ![self.previewEditSource isEqualToString:self.editor.string]) return NO;
    NSNumber *identifier = payload[@"id"];
    if (![identifier isKindOfClass:NSNumber.class] || !isfinite(identifier.doubleValue) ||
        identifier.doubleValue < 0 || floor(identifier.doubleValue) != identifier.doubleValue ||
        identifier.doubleValue >= self.previewEditRanges.count) return NO;
    NSDictionary *entry = self.previewEditRanges[identifier.unsignedIntegerValue];
    NSRange range = NSMakeRange([entry[@"location"] unsignedIntegerValue], [entry[@"length"] unsignedIntegerValue]);
    NSString *source = self.editor.string;
    if (range.location > source.length || range.length > source.length-range.location ||
        ![[source substringWithRange:range] isEqualToString:entry[@"text"]]) return NO;
    NSString *action = payload[@"action"];
    if (![action isKindOfClass:NSString.class]) return NO;
    if (entry[@"codeBlockRange"] && ![action isEqualToString:@"block"]) return NO;
    if ([action isEqualToString:@"replace"]) {
        NSString *text = payload[@"text"];
        if (![text isKindOfClass:NSString.class] || text.length > 100000 ||
            ![text dataUsingEncoding:NSUTF8StringEncoding] ||
            [text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) return NO;
        NSMutableCharacterSet *controls = [NSCharacterSet.controlCharacterSet mutableCopy];
        [controls removeCharactersInString:@"\t"];
        if ([text rangeOfCharacterFromSet:controls].location != NSNotFound) return NO;
        return [self replacePreviewRange:range withString:[self escapePreviewPlainText:text]];
    }
    NSDictionary *verified = [self verifiedPreviewSelection:payload];
    if (!verified || (verified[@"codeBlockRange"] && ![action isEqualToString:@"block"])) return NO;
    range = [verified[@"range"] rangeValue];
    NSString *selected = [source substringWithRange:range];
    NSRange selectedRange = range;
    NSString *value = payload[@"value"];
    if (value && ![value isKindOfClass:NSString.class]) return NO;
    if ([action isEqualToString:@"table-align"])
        return [self alignPreviewTable:payload selection:verified value:value];
    if ([action isEqualToString:@"block"])
        return [self applyBlockFormattingValue:value selection:verified callouts:self.renderer.calloutSourceEntries renderer:self.renderer];
    if ([action isEqualToString:@"strike"] && !self.preferences.extensionStrikethough) return NO;
    BOOL emphasis = [@[@"bold",@"italic",@"underline",@"strike"] containsObject:action];
    if (emphasis || [@[@"clear",@"code",@"link"] containsObject:action]) {
        NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        while (range.length && [spaces characterIsMember:[source characterAtIndex:range.location]]) { range.location++; range.length--; }
        while (range.length && [spaces characterIsMember:[source characterAtIndex:NSMaxRange(range)-1]]) range.length--;
        if (!range.length) return NO;
        selectedRange = range;
        BOOL oldIntra = self.preferences.extensionIntraEmphasis;
        BOOL oldUnderline = self.preferences.extensionUnderline;
        self.preferences.extensionIntraEmphasis = YES;
        if ([action isEqualToString:@"underline"]) self.preferences.extensionUnderline = YES;
        NSDictionary *change = MPPreviewInlineChange(source,range,action,value,
            ^NSString *(NSString *markdown){return [self.renderer HTMLForMarkdownSnapshot:markdown];},
            ^NSString *(NSString *text){return [self escapePreviewPlainText:text];});
        BOOL valid = change && [MPNormalizePreviewSelectionText(change[@"text"]) isEqualToString:MPNormalizePreviewSelectionText([(verified[@"inlineText"] ?: verified[@"text"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])];
        if (valid && [self replacePreviewRange:[change[@"range"] rangeValue] withString:change[@"replacement"] preservingSelection:selectedRange restoringRange:[change[@"selection"] rangeValue]]) return YES;
        self.preferences.extensionIntraEmphasis = oldIntra;
        self.preferences.extensionUnderline = oldUnderline;
        return NO;
    }
    // Math retains its source delimiter operation; all ordinary inline
    // styles, code and links use the single source-backed transaction above.
    if (![action isEqualToString:@"math"] || !self.preferences.htmlMathJax || [verified[@"runs"] count]!=1) return NO;
    NSString *before = @"\\(", *after = @"\\)";
    if (range.location >= before.length && source.length-NSMaxRange(range) >= after.length &&
        [[source substringWithRange:NSMakeRange(range.location-before.length,before.length)] isEqualToString:before] &&
        [[source substringWithRange:NSMakeRange(NSMaxRange(range),after.length)] isEqualToString:after]) {
        range = NSMakeRange(range.location-before.length, range.length+before.length+after.length);
        return [self replacePreviewRange:range withString:selected preservingSelection:selectedRange];
    }
    return [self replacePreviewRange:range withString:[NSString stringWithFormat:@"%@%@%@",before,selected,after] preservingSelection:selectedRange];
}

// Both native buttons and popup bridge requests continue through one queue.
// The pending source is newer than the visible DOM, so validate the old DOM's
// token and proven selection before replaying only formatting commands.
- (BOOL)queuePendingPreviewFormattingPayload:(NSDictionary *)payload
{
    if (![payload isKindOfClass:NSDictionary.class]) return NO;
    NSString *action = payload[@"action"], *value = payload[@"value"];
    if (self.documentClosed || self.printing ||
        ![payload[@"token"] isKindOfClass:NSString.class] ||
        ![payload[@"token"] isEqualToString:self.previewEditToken] ||
        ![action isKindOfClass:NSString.class] ||
        ![@[@"block",@"bold",@"italic",@"underline",@"strike",@"clear",@"code",@"link",@"math",@"table-align"] containsObject:action] ||
        (value && ![value isKindOfClass:NSString.class])) return NO;
    if (self.previewSelectionToRestore && [self.previewSelectionToRestore[@"source"] isEqualToString:self.editor.string]) {
        // If the user selected another run in the still-visible old DOM,
        // cancel the continuation instead of formatting the previous passage.
        NSDictionary *verified = [self verifiedPreviewSelection:payload];
        if (!verified) {
            self.previewSelectionToRestore = nil; self.previewQueuedFormatting = nil;
            return YES;
        }
        NSRange current = [verified[@"range"] rangeValue];
        NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        NSString *old = self.previewEditSource;
        while (current.length && [spaces characterIsMember:[old characterAtIndex:current.location]]) { current.location++; current.length--; }
        while (current.length && [spaces characterIsMember:[old characterAtIndex:NSMaxRange(current)-1]]) current.length--;
        if (current.location != [self.previewSelectionToRestore[@"beforeLocation"] unsignedIntegerValue] || current.length != [self.previewSelectionToRestore[@"beforeLength"] unsignedIntegerValue]) {
            self.previewSelectionToRestore = nil; self.previewQueuedFormatting = nil;
            return YES;
        }
        if (!self.previewQueuedFormatting) self.previewQueuedFormatting = [NSMutableArray array];
        NSMutableDictionary *request = [@{@"action":action} mutableCopy];
        if (value) request[@"value"] = value;
        [self.previewQueuedFormatting addObject:request];
        return YES;
    }
    return NO;
}

// A toolbar click retains the preview's first responder. Consume its verified
// selection through the same transaction as the floating panel; never fall back
// to the editor's unrelated insertion point when that selection is unsupported.
- (BOOL)performPreviewFormattingAction:(NSString *)action value:(NSString *)value
{
    if (![self previewHasFindFocus]) return NO;
    JSContext *context = self.preview.mainFrame.javaScriptContext;
    JSValue *function = context[@"window"][@"macdownPreviewEditor"][@"selectionPayload"];
    NSDictionary *payload = [[function callWithArguments:@[action, value ?: NSNull.null]] toDictionary];
    if ([self queuePendingPreviewFormattingPayload:payload]) return YES;
    if ([self applyPreviewEditPayload:payload])
        [context evaluateScript:@"window.macdownPreviewEditor.finish()"];
    else {
        NSBeep();
        [context evaluateScript:@"window.macdownPreviewEditor && window.macdownPreviewEditor.showFormattingError()"];
    }
    return YES;
}

- (void)handlePreviewEdit:(NSURL *)url
{
    NSString *json = [self queryItemsByNameForURL:url][@"payload"];
    if (![url.host isEqualToString:@"edit"] || json.length > 200000) return;
    NSDictionary *payload = json ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    if (![payload isKindOfClass:NSDictionary.class]) { NSBeep(); return; }
    if ([payload[@"action"] isEqual:@"refresh"] && [payload[@"token"] isEqual:self.previewEditToken] && ![self previewDraft]) {
        [self.renderer parseAndRenderNow]; return;
    }
    if ([self queuePendingPreviewFormattingPayload:payload]) return;
    if ([self applyPreviewEditPayload:payload]) {
        [self.preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownPreviewEditor.finish()"];
    } else {
        NSBeep();
        // Keep a rejected draft visible for recovery; never silently discard it.
        if (![self previewDraft]) [self.preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownPreviewEditor.showFormattingError()"];
        else [self.preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownPreviewEditor.showError()"];
    }
}


#pragma mark - Interactive Checkbox Support (Issue #269)

- (NSDictionary<NSString *, NSString *> *)queryItemsByNameForURL:(NSURL *)url
{
    NSURLComponents *components =
        [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems)
    {
        if (item.name.length && item.value)
            items[item.name] = item.value;
    }
    return items;
}

/**
 * Handle the checkbox toggle URL from the preview.
 * URL format: x-macdown-checkbox://toggle/<index>
 */
- (void)handleCheckboxToggle:(NSURL *)url
{
    if (![url.host isEqualToString:@"toggle"])
        return;

    NSString *token = [self queryItemsByNameForURL:url][@"token"];
    if (!token.length
        || ![token isEqualToString:self.renderer.checkboxBridgeToken])
    {
        NSLog(@"MacDown: Ignored unauthorized checkbox toggle: %@", url);
        return;
    }

    NSString *path = url.path;
    if (path.length < 2 || ![path hasPrefix:@"/"]) return;
    NSString *digits = [path substringFromIndex:1];
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < digits.length; i++)
    {
        unichar c = [digits characterAtIndex:i];
        if (c < '0' || c > '9' || index > (NSUIntegerMax - (c - '0')) / 10) return;
        index = index * 10 + c - '0';
    }
    NSString *markdown = self.editor.string;
    if (![markdown isEqualToString:self.renderer.checkboxSourceMarkdown] ||
        index >= self.renderer.checkboxSourceOffsets.count) return;
    NSUInteger offset = self.renderer.checkboxSourceOffsets[index].unsignedIntegerValue;
    if (offset < 1 || offset >= markdown.length - 1 ||
        [markdown characterAtIndex:offset - 1] != '[' ||
        [markdown characterAtIndex:offset + 1] != ']') return;
    unichar state = [markdown characterAtIndex:offset];
    if (state != ' ' && state != 'x' && state != 'X') return;
    NSString *replacement = state == ' ' ? @"x" : @" ";
    NSRange range = NSMakeRange(offset, 1);
    NSRange selection = self.editor.selectedRange;
    if (![self.editor shouldChangeTextInRange:range replacementString:replacement]) return;
    [self.editor.textStorage replaceCharactersInRange:range withString:replacement];
    [self.editor didChangeText];
    self.editor.selectedRange = selection;
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
    if (!markdown.length) return markdown;
    NSArray<NSNumber *> *offsets = [MPRenderer checkboxOffsetsForMarkdown:markdown];
    if (index >= offsets.count) return markdown;
    NSUInteger offset = offsets[index].unsignedIntegerValue;
    if (offset >= markdown.length) return markdown;
    unichar state = [markdown characterAtIndex:offset];
    if (state != ' ' && state != 'x' && state != 'X') return markdown;
    NSMutableString *result = [markdown mutableCopy];
    [result replaceCharactersInRange:NSMakeRange(offset, 1) withString:state == ' ' ? @"x" : @" "];
    return result;
}


#pragma mark - File Watching (Issue #290)

- (void)startFileWatching
{
    // Tear down any previously-armed watcher first, so an early return below
    // (nil URL, or a path that cannot be watched) can never leak a stale
    // watcher for an old session. Related to #478.
    [self stopFileWatching];

    if (self.documentClosed || !self.fileURL || !self.fileURL.isFileURL)
        return;

    if (![MPFileWatcher canWatchPath:self.fileURL.path])
        return;

    NSUInteger generation = self.fileWatchGeneration;
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
                     if (!s || s.documentClosed || s.fileWatchGeneration != generation) return;
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
    self.fileWatchGeneration++;
    self.externalChangeCoalescePending = NO;
    [self.fileWatcher stopWatching];
    self.fileWatcher = nil;
    [self.resourceWatcherSet stopAll];
}

// Entry point from the file watcher. Everything here is about deciding whether
// a notification deserves a decision at all; the decision itself lives in
// -processExternalFileChange.
- (void)handleExternalFileChange
{
    // Ignore if this was our own save
    if (self.documentClosed || self.isSelfSaving)
        return;

    // Issue #543: While the keep/discard sheet is up, drop further
    // notifications rather than letting them pile up behind it. Nothing is
    // lost by doing so: "Discard" reads the file at the moment it is clicked,
    // so it already reflects every write that landed while the sheet was open.
    if (self.externalChangePromptVisible)
        return;

    // Issue #543: Collapse a burst of write notifications into one decision,
    // so a chunked external save produces a single dialog (or a single silent
    // reload) instead of one per chunk. This is a leading-edge throttle, not a
    // resetting debounce: the window opens on the first notification and fires
    // once the interval elapses; later notifications inside it are dropped but
    // do not extend it. A writer whose chunks are spaced further apart than the
    // interval can therefore still produce more than one decision, which is an
    // accepted trade-off for keeping ordinary fast local saves to one decision.
    if (self.externalChangeCoalescePending)
        return;
    self.externalChangeCoalescePending = YES;

    NSUInteger generation = self.fileWatchGeneration;
    __weak MPDocument *weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(self.externalChangeCoalesceInterval * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            MPDocument *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.documentClosed || strongSelf.fileWatchGeneration != generation)
                return;
            strongSelf.externalChangeCoalescePending = NO;
            [strongSelf processExternalFileChange];
        });
}

- (void)processExternalFileChange
{
    // Re-checked here as well as on the way in: the coalescing window can
    // straddle the start of one of our own saves.
    if (self.documentClosed || self.isSelfSaving)
        return;

    if (self.documentClosed || !self.fileURL || !self.fileURL.isFileURL)
        return;

    // Verify the file actually changed by checking modification date
    NSDate *currentModDate = self.fileModificationDate;

    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:self.fileURL.path error:&error];
    if (error)
        return;

    NSDate *diskModDate = attrs[NSFileModificationDate];

    // Backup restores can preserve or decrease the timestamp. With the same
    // date, compare against the bytes actually read/saved, not the dirty editor.
    if (currentModDate && diskModDate &&
        [diskModDate compare:currentModDate] == NSOrderedSame)
    {
        if (!self.diskContentFingerprint) return;
        NSData *diskData = [NSData dataWithContentsOfURL:self.fileURL
                                              options:0 error:&error];
        if (!diskData || [MPDocumentContentFingerprint(diskData)
                         isEqual:self.diskContentFingerprint]) return;
    }

    // File has been modified externally.
    if ([self shouldPromptBeforeReloadingExternalChanges])
    {
        [self promptForReloadWithExternalChanges];
    }
    else
    {
        [self reloadFromDisk];
    }
}

// Issue #543: The dialog exists to protect unsaved work, so it is only worth
// showing when there is unsaved work to protect. It used to fire whenever Auto
// Save was off as well, which meant anyone who keeps Auto Save off was asked to
// confirm every external change even on a pristine document — nothing was at
// stake and the only available answer was "Discard".
- (BOOL)shouldPromptBeforeReloadingExternalChanges
{
    return [self isDocumentEdited];
}

- (void)promptForReloadWithExternalChanges
{
    // Issue #543: AppKit queues sheets rather than collapsing them, so without
    // this guard a document could accumulate a stack of identical dialogs.
    if (self.externalChangePromptVisible)
        return;
    self.externalChangePromptVisible = YES;

    NSURL *promptURL = self.fileURL;
    __weak MPDocument *weakSelf = self;
    void (^completion)(BOOL) = ^(BOOL shouldReload) {
        MPDocument *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        strongSelf.externalChangePromptVisible = NO;
        if (shouldReload && !strongSelf.documentClosed && [strongSelf.fileURL isEqual:promptURL])
            [strongSelf reloadFromDisk];
    };

    // Tests substitute a presenter so the surrounding logic can be exercised
    // without entering a real modal session.
    if (self.externalChangePromptPresenter)
    {
        self.externalChangePromptPresenter(completion);
        return;
    }

    [self presentExternalChangeAlertWithCompletion:completion];
}

- (void)presentExternalChangeAlertWithCompletion:(void (^)(BOOL shouldReload))completion
{
    // A process with no window has nobody to answer a prompt, so a modal session
    // here would block the main thread for good. Answer it as "Keep": the one
    // response that cannot lose unsaved work.
    NSWindow *window = self.windowForSheet;
    if (!window)
    {
        completion(NO);
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(
        @"File Modified Externally",
        @"External file change alert title");
    alert.informativeText = NSLocalizedString(
        @"This file has been changed by another application. Do you want to discard your changes?",
        @"External file change alert message");

    [alert addButtonWithTitle:NSLocalizedString(@"Discard", @"Discard changes button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Keep", @"Keep local changes button")];

    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        // "Keep" reports NO, and the caller then leaves the editor alone.
        completion(response == NSAlertFirstButtonReturn);
    }];
}

- (void)reloadFromDisk
{
    if (self.documentClosed) return;
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:self.fileURL.path error:nil];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL options:0 error:&error];
    if (error || !data)
        return;

    // Read the new content
    if (![self readFromData:data ofType:self.fileType error:&error])
        return;

    // Update fileModificationDate to reflect the reloaded content
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
        self.zoomMultiplier = level.doubleValue;
    }
}

@end
