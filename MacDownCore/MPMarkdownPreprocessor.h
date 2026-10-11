// Shared Markdown compatibility rules for the application and Quick Look.
#import <Foundation/Foundation.h>
#import <hoedown/buffer.h>

// Both HTML and TOC renderers reserve final ids in document order. Keep the
// registry local to one parse, including naturally suffixed headings.
NS_INLINE hoedown_buffer *MPUniqueHeadingSlug(const hoedown_buffer *slug, void *owner)
{
    NSDictionary *context = (__bridge NSDictionary *)owner;
    NSMutableDictionary<NSString *, NSNumber *> *used = context[@"headingSlugs"];
    NSString *base = [[NSString alloc] initWithBytes:slug->data length:slug->size encoding:NSUTF8StringEncoding];
    if (!used || !base) return NULL;
    NSString *candidate = base;
    NSUInteger suffix = used[base].unsignedIntegerValue;
    while (used[candidate]) {
        candidate = [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)++suffix];
    }
    used[base] = @(suffix);
    used[candidate] = @0;
    NSData *bytes = [candidate dataUsingEncoding:NSUTF8StringEncoding];
    hoedown_buffer *result = hoedown_buffer_new(MAX((size_t)1, bytes.length));
    hoedown_buffer_put(result, bytes.bytes, bytes.length);
    return result;
}

// Bound recursive Markdown nesting for interactive previews and Quick Look.
static const size_t MPMarkdownMaximumNesting = 128;

// Compatibility substitutions must never change literal inline or indented
// code. Hoedown closes a code span at the next run containing its opener's
// number of backticks; use that same boundary before applying prose rules.
NS_INLINE NSArray<NSValue *> *MPMarkdownLiteralRanges(NSString *text)
{
    NSMutableArray *ranges = [NSMutableArray array];
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([text characterAtIndex:i] != '`') continue;
        NSUInteger backslashes = 0;
        while (i > backslashes && [text characterAtIndex:i - backslashes - 1] == '\\') backslashes++;
        if (backslashes % 2) continue;
        NSUInteger width = 1;
        while (i + width < text.length && [text characterAtIndex:i + width] == '`') width++;
        NSString *delimiter = [text substringWithRange:NSMakeRange(i, width)];
        NSRange close = [text rangeOfString:delimiter options:0
            range:NSMakeRange(i + width, text.length - i - width)];
        if (close.location != NSNotFound) {
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(i, NSMaxRange(close) - i)]];
            i = NSMaxRange(close) - 1;
        } else i += width - 1;
    }
    NSRegularExpression *indented = [NSRegularExpression regularExpressionWithPattern:
        @"^(?:\\t| {4}).*" options:NSRegularExpressionAnchorsMatchLines error:NULL];
    for (NSTextCheckingResult *match in [indented matchesInString:text options:0 range:NSMakeRange(0, text.length)])
        [ranges addObject:[NSValue valueWithRange:match.range]];
    return ranges;
}

NS_INLINE NSString *MPReplaceMarkdownProse(NSString *text, NSRegularExpression *expression, NSString *replacement)
{
    NSArray<NSValue *> *literals = MPMarkdownLiteralRanges(text);
    NSMutableString *result = [text mutableCopy];
    NSArray *matches = [expression matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        BOOL literal = NO;
        for (NSValue *value in literals) {
            if (NSIntersectionRange(match.range, value.rangeValue).length) { literal = YES; break; }
        }
        if (!literal) [result replaceCharactersInRange:match.range withString:
            [expression replacementStringForResult:match inString:text offset:0 template:replacement]];
    }
    return result;
}

NS_INLINE NSString *MPPreprocessProse(NSString *text)
{
    static NSRegularExpression *lists, *shortcuts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lists = [NSRegularExpression regularExpressionWithPattern:
            @"^(?![ \\t]*[-*+][ \\t])(?![ \\t]*\\d+\\.[ \\t])(.+)\\n([-*+]|\\d+\\.)[ \\t]"
            options:NSRegularExpressionAnchorsMatchLines error:NULL];
        shortcuts = [NSRegularExpression regularExpressionWithPattern:
            @"(?<!\\])\\[([^\\]]+)\\](\\s+)(?=\\[)" options:0 error:NULL];
    });
    text = MPReplaceMarkdownProse(text, lists, @"$1\n\n$2 ");
    return MPReplaceMarkdownProse(text, shortcuts, @"[$1][]$2");
}

NS_INLINE NSUInteger MPMarkdownQuoteDepth(NSString *line, NSUInteger *contentStart)
{
    NSUInteger offset = 0, depth = 0;
    while (offset < line.length) {
        NSUInteger prefix = offset;
        for (NSUInteger spaces = 0; spaces < 3 && offset < line.length && [line characterAtIndex:offset] == ' '; spaces++) offset++;
        if (offset >= line.length || [line characterAtIndex:offset] != '>') {
            offset = prefix;
            break;
        }
        offset++; depth++;
        if (offset < line.length && [line characterAtIndex:offset] == ' ') offset++;
    }
    if (contentStart) *contentStart = offset;
    return depth;
}

// Default titles are inserted into Markdown source, using the app's selected
// localization. Missing translations have human-readable English defaults.
NS_INLINE NSString *MPPreviewDefaultCalloutTitle(NSString *type, BOOL collapsible)
{
    if (collapsible) return [NSBundle.mainBundle localizedStringForKey:@"PreviewToggleTitle"
        value:@"Prerequisites" table:nil];
    static NSDictionary<NSString *, NSArray<NSString *> *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{
            @"note": @[@"PreviewCalloutTitleNote", @"Note"],
            @"tip": @[@"PreviewCalloutTitleTip", @"Tip"],
            @"warning": @[@"PreviewCalloutTitleWarning", @"Warning"],
            @"important": @[@"PreviewCalloutTitleImportant", @"Important"],
            @"caution": @[@"PreviewCalloutTitleCaution", @"Caution"]
        };
    });
    NSArray<NSString *> *entry = type.length ? titles[type] : nil;
    return entry ? [NSBundle.mainBundle localizedStringForKey:entry[0] value:entry[1] table:nil] : nil;
}

// A deliberately small Quarto subset. Unknown attributes and incomplete divs
// remain source text. Opaque markers let the existing Markdown renderer parse
// callout contents, rather than introducing another Markdown implementation.
// Source ranges identify physical delimiter lines in this exact input; callers
// must not apply ranges from a transformed/preprocessed input to original text.
// An indented callout is a container only when a preceding list item owns
// that indentation. Standalone indented examples retain code semantics.
// Markdown tabs advance to four-column stops. Physical source ranges and
// prefixes retain their original bytes; only nesting comparisons use columns.
NS_INLINE NSUInteger MPMarkdownPrefixColumns(NSString *prefix)
{
    NSUInteger columns=0;
    for (NSUInteger i=0;i<prefix.length;i++)
        columns += [prefix characterAtIndex:i]=='\t' ? 4-columns%4 : 1;
    return columns;
}

NS_INLINE BOOL MPCalloutHasListOwner(NSArray<NSString *> *lines, NSUInteger index, NSUInteger indentation)
{
    NSRegularExpression *item=[NSRegularExpression regularExpressionWithPattern:@"^([ \\t]*)(?:[-+*]|[0-9]+[.)])([ \\t]+)" options:0 error:NULL];
    while (index) {
        NSString *line=lines[--index];
        if (![line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) continue;
        NSUInteger width=0;while(width<line.length && ([line characterAtIndex:width]==' ' || [line characterAtIndex:width]=='\t')) width++;
        if (MPMarkdownPrefixColumns([line substringToIndex:width])>=indentation) continue;
        NSTextCheckingResult *match=[item firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        if (!match) return NO;
        NSUInteger contentColumn=MPMarkdownPrefixColumns([line substringToIndex:NSMaxRange(match.range)]);
        return contentColumn<=indentation && indentation-contentColumn<4;
    }
    return NO;
}

NS_INLINE NSDictionary *MPPrepareCallouts(NSString *text)
{
    if (![text containsString:@":::"]) return @{@"text":text, @"callouts":@[]};
    NSString *prefix;
    do { prefix = [@"macdowncallout" stringByAppendingString:NSUUID.UUID.UUIDString]; }
    while ([text containsString:prefix]);
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray *output = [lines mutableCopy], *stack = [NSMutableArray array], *pairs = [NSMutableArray array];
    NSRegularExpression *opening = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \\t]*(:{3,})[ \\t]*\\{(.*)\\}[ \\t]*$" options:0 error:NULL];
    NSRegularExpression *supported = [NSRegularExpression regularExpressionWithPattern:
        @"^\\.callout-(note|tip|warning|important|caution)(?:[ \\t]+collapse=(?:\\\"(true|false)\\\"|'(true|false)'|(true|false)))?[ \\t]*$" options:0 error:NULL];
    NSRegularExpression *closing = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*:{3,}[ \\t]*$" options:0 error:NULL];
    NSRegularExpression *code = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \\t]*(?:>[ \\t]*)*(?:(?:[-*+]|\\d+[.)])[ \\t]+)?(`{3,}|~{3,})(.*)$" options:0 error:NULL];
    NSString *fence = nil;
    // Literal spans and indented-code ranges can overlap and arrive in two
    // separate groups. Order them once and advance monotonically with lines.
    NSArray<NSValue *> *literals = [MPMarkdownLiteralRanges(text)
        sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
            NSUInteger left = a.rangeValue.location, right = b.rangeValue.location;
            return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame;
        }];
    NSUInteger offset = 0, literalIndex = 0;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *rawLine = lines[i];
        // Rendering normalizes CRLF first; provenance must still refer to the
        // original UTF-16 source, including each physical line ending.
        NSString *line = [rawLine hasSuffix:@"\r"] ? [rawLine substringToIndex:rawLine.length - 1] : rawLine;
        NSUInteger lineStart = offset;
        NSUInteger lineEnd = offset + rawLine.length + (i + 1 < lines.count ? 1 : 0);
        NSTextCheckingResult *cm = [code firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        NSString *run = cm ? [line substringWithRange:[cm rangeAtIndex:1]] : nil;
        if (fence) {
            if (run && [run characterAtIndex:0] == [fence characterAtIndex:0] && run.length >= fence.length &&
                ![[line substringWithRange:[cm rangeAtIndex:2]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) fence = nil;
            offset = lineEnd; continue;
        }
        if (run) { fence = run; offset = lineEnd; continue; }
        while (literalIndex < literals.count &&
               NSMaxRange(literals[literalIndex].rangeValue) <= offset) literalIndex++;
        BOOL literal = literalIndex < literals.count &&
            NSIntersectionRange(NSMakeRange(offset,line.length), literals[literalIndex].rangeValue).length > 0;
        offset = lineEnd;
        NSUInteger indentation=0;
        while (indentation<line.length && ([line characterAtIndex:indentation]==' ' || [line characterAtIndex:indentation]=='\t')) indentation++;
        NSString *indent=[line substringToIndex:indentation];
        NSUInteger columns=MPMarkdownPrefixColumns(indent);
        NSTextCheckingResult *match = [opening firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        BOOL listContainer=match && columns>=4 && MPCalloutHasListOwner(lines,i,columns);
        BOOL containerClose=stack.count && (MPMarkdownPrefixColumns(stack.lastObject[@"indent"])==columns ||
            (columns<4 && MPMarkdownPrefixColumns(stack.lastObject[@"indent"])<4)) &&
            [closing firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
        if (literal && !(columns>=4 && (listContainer || containerClose))) continue;
        if (match && (columns<4 || listContainer)) {
            NSString *attributes = [line substringWithRange:[match rangeAtIndex:2]];
            NSTextCheckingResult *valid = [supported firstMatchInString:attributes options:0 range:NSMakeRange(0,attributes.length)];
            NSMutableDictionary *entry = [@{@"start":@(i), @"indent":indent,
                @"sourceOpenRange":[NSValue valueWithRange:NSMakeRange(lineStart,lineEnd-lineStart)]} mutableCopy];
            if (valid) {
                entry[@"type"] = [attributes substringWithRange:[valid rangeAtIndex:1]];
                for (NSUInteger n = 2; n <= 4; n++) if ([valid rangeAtIndex:n].location != NSNotFound)
                    entry[@"collapse"] = [attributes substringWithRange:[valid rangeAtIndex:n]];
            }
            [stack addObject:entry];
        } else if (containerClose) {
            NSMutableDictionary *entry = stack.lastObject; [stack removeLastObject];
            if (!entry[@"type"]) continue;
            NSString *token = [prefix stringByAppendingFormat:@"%lu",(unsigned long)pairs.count];
            entry[@"token"] = token;
            entry[@"end"] = @(i);
            entry[@"sourceCloseRange"] = [NSValue valueWithRange:NSMakeRange(lineStart,lineEnd-lineStart)];
            NSUInteger contentStart = NSMaxRange([entry[@"sourceOpenRange"] rangeValue]);
            entry[@"sourceContentRange"] = [NSValue valueWithRange:NSMakeRange(contentStart,lineStart-contentStart)];
            entry[@"sourceOpen"] = lines[[entry[@"start"] unsignedIntegerValue]];
            output[[entry[@"start"] unsignedIntegerValue]] = [NSString stringWithFormat:@"\n%@%@OPEN\n",entry[@"indent"],token];
            output[i] = [NSString stringWithFormat:@"\n%@%@CLOSE\n",indent,token];
            [pairs addObject:entry];
        }
    }
    return @{@"text":[output componentsJoinedByString:@"\n"], @"callouts":pairs};
}

NS_INLINE NSString *MPFinishCallouts(NSString *html, NSArray<NSDictionary *> *callouts)
{
    BOOL rendered = NO;
    for (NSDictionary *entry in callouts) {
        NSString *open = [NSString stringWithFormat:@"<p>%@OPEN</p>",entry[@"token"]];
        NSString *close = [NSString stringWithFormat:@"<p>%@CLOSE</p>",entry[@"token"]];
        NSRange start = [html rangeOfString:open];
        if (start.location == NSNotFound) continue;
        NSRange end = [html rangeOfString:close options:0 range:NSMakeRange(NSMaxRange(start),html.length-NSMaxRange(start))];
        if (end.location == NSNotFound) continue;
        NSString *body = [html substringWithRange:NSMakeRange(NSMaxRange(start),end.location-NSMaxRange(start))];
        NSString *title = [entry[@"type"] capitalizedString];
        NSRegularExpression *heading = [NSRegularExpression regularExpressionWithPattern:@"^\\s*<h([1-6])(?:\\s[^>]*)?>(.*?)</h\\1>" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
        NSTextCheckingResult *match = [heading firstMatchInString:body options:0 range:NSMakeRange(0,body.length)];
        if (match) { title = [[body substringWithRange:match.range] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; body = [body substringFromIndex:NSMaxRange(match.range)]; }
        NSString *replacement;
        if (entry[@"collapse"]) replacement = [NSString stringWithFormat:@"<details class=\"mp-callout mp-callout-%@\" data-macdown-callout-token=\"%@\"%@><summary>%@</summary><div class=\"mp-callout-body\">%@</div></details>",entry[@"type"],entry[@"token"],[entry[@"collapse"] isEqual:@"false"] ? @" open" : @"",title,body];
        else replacement = [NSString stringWithFormat:@"<aside class=\"mp-callout mp-callout-%@\" data-macdown-callout-token=\"%@\"><div class=\"mp-callout-title\">%@</div><div class=\"mp-callout-body\">%@</div></aside>",entry[@"type"],entry[@"token"],title,body];
        html = [html stringByReplacingCharactersInRange:NSMakeRange(start.location,NSMaxRange(end)-start.location) withString:replacement];
        rendered = YES;
    }
    // Hoedown may keep a marker inside a raw HTML block instead of making a
    // paragraph. Restore original delimiters there; never leave marker text.
    for (NSDictionary *entry in callouts) {
        NSString *source = entry[@"sourceOpen"];
        source = [[source stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
        source = [source stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
        html = [html stringByReplacingOccurrencesOfString:[entry[@"token"] stringByAppendingString:@"OPEN"] withString:source];
        html = [html stringByReplacingOccurrencesOfString:[entry[@"token"] stringByAppendingString:@"CLOSE"] withString:@":::"];
    }
    if (!rendered) return html;
    // Callout and disclosure headings keep the stylesheet's heading sizes;
    // reset only the spacing and borders within their title surfaces.
    return [
        @"<style>.mp-callout{border:1px solid #8886;border-left:4px solid #4385be;border-radius:12px;margin:1em 0}"
        @".mp-callout-tip{border-left-color:#23865a}"
        @".mp-callout-warning,.mp-callout-caution{border-left-color:#ba7818}"
        @".mp-callout-important{border-left-color:#bc3945}"
        @".mp-callout-title,.mp-callout>summary{font-weight:bold;padding:.5em .8em}"
        @".mp-callout>summary{cursor:pointer;position:relative;display:block;list-style:none;padding-left:2em}"
        @".mp-callout>summary::-webkit-details-marker{display:none}"
        @".mp-callout>summary::marker{content:\"\"}"
        @".mp-callout>summary::before{content:\"\";position:absolute;left:.8em;top:50%;width:.8em;height:.8em;background:currentColor;clip-path:polygon(25% 10%,75% 50%,25% 90%);transform:translateY(-50%) rotate(0deg);transform-origin:center;transition:transform .18s ease;pointer-events:none}"
        @".mp-callout[open]>summary::before{transform:translateY(-50%) rotate(90deg)}"
        @".mp-callout-title>h1,.mp-callout-title>h2,.mp-callout-title>h3,.mp-callout-title>h4,.mp-callout-title>h5,.mp-callout-title>h6,.mp-callout>summary>h1,.mp-callout>summary>h2,.mp-callout>summary>h3,.mp-callout>summary>h4,.mp-callout>summary>h5,.mp-callout>summary>h6{display:inline;line-height:inherit;margin:0;border:0}"
        @".mp-callout>summary>h1,.mp-callout>summary>h2,.mp-callout>summary>h3,.mp-callout>summary>h4,.mp-callout>summary>h5,.mp-callout>summary>h6{display:block;line-height:1.25}"
        @".mp-callout-body{padding:0 .8em .5em}"
        @".mp-callout-body>:last-child{margin-bottom:0}"
        @"@media(prefers-reduced-motion:reduce){.mp-callout>summary::before{transition:none}}"
        @"@media print{.mp-callout>summary::before{transform:translateY(-50%) rotate(90deg);transition:none}"
        @"details.mp-callout::details-content{content-visibility:visible!important}"
        @"details.mp-callout:not([open])>.mp-callout-body{display:block!important}"
        @"}"
        @"</style>\n"
        stringByAppendingString:html];
}

// Hoedown extracts reference definitions before parsing fenced code. Protect
// only those definitions with a per-parse marker, removed by the blockcode
// callback before escaping. Unlike a zero-width character, this cannot alter
// copied code or remove a character already present in the source.
NS_INLINE NSDictionary<NSString *, NSString *> *MPPreprocessMarkdown(NSString *text, BOOL fencedCodeEnabled, NSUInteger sourceOffset)
{
    text = text ?: @"";
    NSString *taskPrefix;
    do { taskPrefix = [NSString stringWithFormat:@"macdown-task-%@Z", NSUUID.UUID.UUIDString]; }
    while ([text containsString:taskPrefix]);
    NSRegularExpression *tasks = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \t]*(?:>[ \t]*)*(?:[-*+]|\\d+[.)])[ \t]+\\[([ xX])\\]"
        options:NSRegularExpressionAnchorsMatchLines error:NULL];
    NSMutableString *marked = [text mutableCopy];
    NSArray *matches = [tasks matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSUInteger offset = sourceOffset + [match rangeAtIndex:1].location;
        [marked insertString:[NSString stringWithFormat:@"%@%luZ", taskPrefix, (unsigned long)offset]
                     atIndex:NSMaxRange(match.range)];
    }
    text = [marked stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    if (!fencedCodeEnabled) {
        NSMutableDictionary *prepared = [MPPrepareCallouts(MPPreprocessProse(text)) mutableCopy];
        prepared[@"codeEscapeToken"] = @""; prepared[@"taskPrefix"] = taskPrefix;
        return prepared;
    }
    NSString *marker;
    do { marker = [NSString stringWithFormat:@"macdown-code-%@", NSUUID.UUID.UUIDString]; }
    while ([text containsString:marker]);
    static NSRegularExpression *fencePattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fencePattern = [NSRegularExpression regularExpressionWithPattern:
            @"^[ \\t]*(?:>[ \\t]*)*(?:(?:[-*+]|\\d+[.)])[ \\t]+)?(`{3,}|~{3,})(.*)$" options:0 error:NULL];
    });
    NSMutableString *result = [NSMutableString string];
    NSMutableString *prose = [NSMutableString string];
    NSString *fence = nil;
    NSUInteger fenceQuoteDepth = 0;
    NSUInteger fenceIndent = 0;
    BOOL fenceInList = NO;
    BOOL listContext = NO;
    NSRegularExpression *listPattern = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \\t]*(?:>[ \\t]*)*(?:[-*+]|\\d+[.)])[ \\t]+" options:0 error:NULL];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = lines[index];
        BOOL newline = index + 1 < lines.count;
        NSUInteger contentStart = 0;
        NSUInteger quoteDepth = MPMarkdownQuoteDepth(line, &contentStart);
        BOOL blank = ![[line substringFromIndex:contentStart]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length;
        if (fence && blank && newline) {
            NSString *next = lines[index + 1];
            NSUInteger nextStart = 0;
            NSUInteger nextDepth = MPMarkdownQuoteDepth(next, &nextStart);
            BOOL nextBlank = ![[next substringFromIndex:nextStart]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length;
            BOOL quoteEnded = fenceQuoteDepth && quoteDepth < fenceQuoteDepth && nextDepth < fenceQuoteDepth && !nextBlank;
            BOOL listEnded = fenceInList && next.length && [next characterAtIndex:0] != ' ' && [next characterAtIndex:0] != '\t';
            if (quoteEnded || listEnded) {
                // Hoedown closes the enclosing container here even when its
                // code fence was never explicitly closed.
                fence = nil;
                listContext = NO;
            }
        }
        NSTextCheckingResult *match = [fencePattern firstMatchInString:line options:0
            range:NSMakeRange(0, line.length)];
        NSString *candidate = match ? [line substringWithRange:[match rangeAtIndex:1]] : nil;
        NSString *suffix = match ? [line substringWithRange:[match rangeAtIndex:2]] : nil;
        BOOL listLine = [listPattern firstMatchInString:line options:0 range:NSMakeRange(0, line.length)] != nil;
        if (listLine) listContext = YES;
        BOOL unindented = line.length && [line characterAtIndex:0] != ' ' && [line characterAtIndex:0] != '\t';
        BOOL containerFence = match && ([match rangeAtIndex:1].location <= 3 ||
            [[line substringToIndex:[match rangeAtIndex:1].location] containsString:@">"] || listContext);
        if (!fence && !listLine && unindented && !candidate) listContext = NO;
        if (!fence && candidate && containerFence &&
            ![suffix containsString:[candidate substringToIndex:3]]) {
            [result appendString:MPPreprocessProse(prose)];
            if (prose.length && ![prose hasSuffix:@"\n\n"]) [result appendString:@"\n"];
            [prose setString:@""];
            fence = candidate;
            fenceQuoteDepth = quoteDepth;
            fenceInList = listContext && (listLine ||
                ([match rangeAtIndex:1].location > 0 && !quoteDepth));
            NSUInteger column = [match rangeAtIndex:1].location - contentStart;
            fenceIndent = fenceInList ? (listLine ? 0 : (column > 4 ? column - 4 : 0)) : column;
            [result appendString:line];
        } else if (fence) {
            NSUInteger column = match ? [match rangeAtIndex:1].location - contentStart : NSNotFound;
            NSUInteger indent = fenceInList && column != NSNotFound ? (column > 4 ? column - 4 : 0) : column;
            if ([candidate isEqualToString:fence] && indent == fenceIndent &&
                ![suffix stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) {
                fence = nil;
                [result appendString:line];
            } else {
                NSString *protected = [line stringByReplacingOccurrencesOfString:@"]:"
                    withString:[NSString stringWithFormat:@"]%@:", marker]];
                [result appendString:protected];
            }
        } else {
            [prose appendString:line];
            if (newline) [prose appendString:@"\n"];
            continue;
        }
        if (newline) [result appendString:@"\n"];
    }
    [result appendString:MPPreprocessProse(prose)];
    NSMutableDictionary *prepared = [MPPrepareCallouts(result) mutableCopy];
    prepared[@"codeEscapeToken"] = marker; prepared[@"taskPrefix"] = taskPrefix;
    return prepared;
}

NS_INLINE NSString *MPRemoveTaskMarkers(NSString *html, NSString *taskPrefix)
{
    if (!taskPrefix.length) return html;
    NSRegularExpression *markers = [NSRegularExpression regularExpressionWithPattern:
        [[NSRegularExpression escapedPatternForString:taskPrefix] stringByAppendingString:@"[0-9]+Z"]
        options:0 error:NULL];
    return [markers stringByReplacingMatchesInString:html options:0
        range:NSMakeRange(0, html.length) withTemplate:@""];
}
