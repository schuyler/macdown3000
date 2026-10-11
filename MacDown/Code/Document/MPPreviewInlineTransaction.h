#import <Foundation/Foundation.h>

// Pure source-backed inline transactions. The HTML parser is an oracle: its
// text must have a unique monotonic provenance in the original source, and the
// complete candidate must preserve every rendered character and other style.
// Nothing from the live WebView is converted back into Markdown.
enum { MPPIBold = 1, MPPIItalic = 2, MPPIUnderline = 4, MPPIStrike = 8, MPPICode = 16 };

static BOOL MPPICollect(NSXMLNode *node, NSUInteger mask, NSMutableString *text,
                        NSMutableArray<NSNumber *> *styles, BOOL strict)
{
    if (node.kind == NSXMLTextKind) {
        NSString *part = node.stringValue ?: @"";
        [text appendString:part];
        for (NSUInteger i=0; i<part.length; i++) [styles addObject:@(mask)];
        return YES;
    }
    if (node.kind != NSXMLElementKind) return YES;
    NSString *tag = node.name.lowercaseString;
    if ([tag isEqualToString:@"strong"] || [tag isEqualToString:@"b"]) mask |= MPPIBold;
    else if ([tag isEqualToString:@"em"] || [tag isEqualToString:@"i"]) mask |= MPPIItalic;
    else if ([tag isEqualToString:@"u"]) mask |= MPPIUnderline;
    else if ([tag isEqualToString:@"del"] || [tag isEqualToString:@"s"] || [tag isEqualToString:@"strike"]) mask |= MPPIStrike;
    else if ([tag isEqualToString:@"code"]) mask |= MPPICode;
    else if (strict && ![@[@"p",@"body",@"html",@"span",@"a"] containsObject:tag]) return NO;
    // Preserve structural boundaries in document verification: changing an
    // inline style must not silently create a heading, a list or a code block.
    if (!strict) [text appendFormat:@"\uE000%@\uE001",tag];
    for (NSXMLNode *child in node.children) if (!MPPICollect(child,mask,text,styles,strict)) return NO;
    if (!strict) [text appendFormat:@"\uE002%@\uE003",tag];
    return YES;
}

static NSXMLDocument *MPPIParseHTML(NSString *html)
{
    if(!html) return nil;
    // Generated task checkboxes are HTML void elements. Close them for XML
    // parsing so adding an inline wrapper cannot change tidy's whitespace or
    // move surrounding callout elements during fingerprint verification.
    if([html rangeOfString:@"<input"].location!=NSNotFound) {
        static NSRegularExpression *inputs;
        static dispatch_once_t once;
        dispatch_once(&once,^{inputs=[NSRegularExpression regularExpressionWithPattern:@"<input\\b([^>]*?)(?<!/)>" options:0 error:NULL];});
        html=[inputs stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0,html.length) withTemplate:@"<input$1 />"];
    }
    NSString *wrapped=[NSString stringWithFormat:@"<html><body>%@</body></html>",html];
    // Hoedown's ordinary paragraphs are valid XML. Parse them without HTML
    // tidy first: libxml HTML recovery can collapse a literal soft newline
    // inside an emphasis node into a space, destroying source provenance.
    NSXMLDocument *document=[[NSXMLDocument alloc] initWithXMLString:wrapped
        options:NSXMLNodePromoteSignificantWhitespace | NSXMLNodeLoadExternalEntitiesNever error:NULL];
    if(!document) document=[[NSXMLDocument alloc] initWithXMLString:wrapped
        options:NSXMLDocumentTidyHTML | NSXMLNodePromoteSignificantWhitespace | NSXMLNodeLoadExternalEntitiesNever error:NULL];
    return document;
}

static NSDictionary *MPPIInlineOracle(NSString *html)
{
    if (!html) return nil;
    NSXMLDocument *document=MPPIParseHTML(html);
    NSArray *paragraphs = [document nodesForXPath:@"//body/p" error:NULL];
    NSArray *bodyChildren = [document nodesForXPath:@"//body/*" error:NULL];
    if (paragraphs.count != 1 || bodyChildren.count != 1) return nil;
    NSMutableString *text = [NSMutableString string];
    NSMutableArray *styles = [NSMutableArray array];
    if (!MPPICollect(paragraphs.firstObject,0,text,styles,YES)) return nil;
    // libxml's HTML tidy mode can attach the renderer's trailing newline to
    // the paragraph text node. It has no source character in the inline body.
    while([text hasSuffix:@"\n"] || [text hasSuffix:@"\r"]) {[text deleteCharactersInRange:NSMakeRange(text.length-1,1)];[styles removeLastObject];}
    return @{@"text":text,@"styles":styles};
}

// A paragraph must map uniquely to source characters. Only parser-recognized
// inline syntax may be skipped; every other source character must be consumed.
// Distinct successful paths are rejected instead of guessing at an occurrence.
static NSArray<NSNumber *> *MPPIProvenance(NSString *source, NSString *text)
{
    if (source.length > 20000 || text.length > 20000) return nil;
    NSMutableDictionary<NSNumber *, NSDictionary *> *states = [@{@0:@{@"count":@1}} mutableCopy];
    NSMutableArray *paths=[NSMutableArray array];
    NSCharacterSet *escapable = [NSCharacterSet characterSetWithCharactersInString:@"\\`*_{}[]()#+-.!|<>&~=^\"$"];
    for (NSUInteger i=0;i<source.length;i++) {
        NSMutableDictionary *next = [NSMutableDictionary dictionary];
        unichar character = [source characterAtIndex:i];
        BOOL syntax = character=='*' || character=='_' || character=='~' || character=='`' ||
            (character=='\\' && i+1<source.length && [escapable characterIsMember:[source characterAtIndex:i+1]]);
        for (NSNumber *key in states) {
            NSUInteger j=key.unsignedIntegerValue;
            NSDictionary *state=states[key];
            if (syntax) {
                NSDictionary *old=next[key];
                NSUInteger count=MIN((NSUInteger)2,[state[@"count"] unsignedIntegerValue]+[old[@"count"] unsignedIntegerValue]);
                NSMutableDictionary *item=[state mutableCopy]; item[@"count"]=@(count); next[key]=item;
            }
            if (j<text.length && character==[text characterAtIndex:j]) {
                NSNumber *target=@(j+1); NSDictionary *old=next[target];
                NSUInteger count=MIN((NSUInteger)2,[state[@"count"] unsignedIntegerValue]+[old[@"count"] unsignedIntegerValue]);
                NSMutableDictionary *path=[@{@"offset":@(i)} mutableCopy];
                if(state[@"tail"]) path[@"previous"]=state[@"tail"];
                // Bound adversarial delimiter ambiguity as well as line size:
                // a long run of literal markers must not allocate millions of
                // possible provenance paths while the main thread is editing.
                if(paths.count>=100000) return nil;
                [paths addObject:path];
                NSDictionary *item=@{@"count":@(count),@"tail":@(paths.count-1)};
                next[target]=item;
            }
        }
        if (!next.count || next.count>1024) return nil;
        states=next;
    }
    NSDictionary *final=states[@(text.length)];
    if ([final[@"count"] unsignedIntegerValue]!=1) return nil;
    NSMutableArray *result=[NSMutableArray array];
    for(NSNumber *tail=final[@"tail"];tail;) {NSDictionary *path=paths[tail.unsignedIntegerValue];[result addObject:path[@"offset"]];tail=path[@"previous"];}

    return [[result reverseObjectEnumerator] allObjects];
}

static NSString *MPPIMarker(NSUInteger mask, BOOL underscoreBold)
{
    switch(mask) { case MPPIBold:return underscoreBold?@"__":@"**"; case MPPIItalic:return @"*"; case MPPIUnderline:return @"_"; case MPPIStrike:return @"~~"; }
    return @"";
}

static NSDictionary *MPPISerialize(NSString *text, NSArray<NSNumber *> *styles,
                                   NSArray<NSNumber *> *order, NSRange selected, BOOL underscoreBold, NSArray *links,
                                   NSString *(^escape)(NSString *))
{
    NSMutableString *output=[NSMutableString string];
    NSMutableArray *stack=[NSMutableArray array];
    NSMutableArray *locations=[NSMutableArray array];
    NSMutableArray *ends=[NSMutableArray array];
    NSUInteger longest=0,run=0;
    for(NSUInteger i=0;i<text.length;i++) {run=[text characterAtIndex:i]=='`'?run+1:0;longest=MAX(longest,run);}
    NSString *codeFence=[@"" stringByPaddingToLength:MAX((NSUInteger)1,longest+1) withString:@"`" startingAtIndex:0];
    NSMutableArray *ownerForPosition=[NSMutableArray arrayWithCapacity:text.length],*outsideForLink=[NSMutableArray arrayWithCapacity:links.count];
    for(NSUInteger i=0;i<text.length;i++) [ownerForPosition addObject:@(-1)];
    for(NSUInteger index=0;index<links.count;index++) {
        NSRange owned=[links[index][@"visible"] rangeValue];NSUInteger common=MPPIBold|MPPIItalic|MPPIUnderline|MPPIStrike;
        for(NSUInteger i=owned.location;i<NSMaxRange(owned);i++) {common&=[styles[i] unsignedIntegerValue];ownerForPosition[i]=@(index);}
        [outsideForLink addObject:@(common)];
    }
    NSCharacterSet *whitespace=NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSUInteger whitespaceEnd=0, whitespaceMask=0;
    for (NSUInteger i=0;i<text.length;i++) {
        NSUInteger mask=[styles[i] unsignedIntegerValue];
        // Leading/trailing whitespace cannot sit directly inside delimiters.
        // Whitespace between two characters with a common style keeps it.
        if ([whitespace characterIsMember:[text characterAtIndex:i]]) {
            // Resolve each whitespace run once, including its neighboring
            // styles. Long spaces must not rescan the entire run per character.
            if(i>=whitespaceEnd) {
                NSUInteger left=i;
                whitespaceEnd=i;
                while(whitespaceEnd<text.length && [whitespace characterIsMember:[text characterAtIndex:whitespaceEnd]]) whitespaceEnd++;
                whitespaceMask=left && whitespaceEnd<text.length ? [styles[left-1] unsignedIntegerValue]&[styles[whitespaceEnd] unsignedIntegerValue] : 0;
                // Hoedown trims whitespace at code-span edges. A space between
                // differently styled code runs remains ordinary separating text.
                if(left && whitespaceEnd<text.length && ![styles[left-1] isEqual:styles[whitespaceEnd]]) whitespaceMask&=~MPPICode;
            }
            mask&=whitespaceMask;

        }
        NSMutableArray *desired=[NSMutableArray array];
        NSInteger owner=[ownerForPosition[i] integerValue]; NSUInteger outside=owner>=0?[outsideForLink[owner] unsignedIntegerValue]:0;
        if(owner>=0) {
            for(NSNumber *style in order) if(mask&outside&style.unsignedIntegerValue) [desired addObject:style];
            [desired addObject:@(-(owner+1))];
            for(NSNumber *style in order) if(mask&~outside&style.unsignedIntegerValue) [desired addObject:style];
        } else for(NSNumber *style in order) if(mask&style.unsignedIntegerValue) [desired addObject:style];
        NSUInteger common=0;
        while(common<stack.count && common<desired.count && [stack[common] isEqual:desired[common]]) common++;
        for(NSUInteger j=stack.count;j>common;j--) {
            NSInteger entry=[stack[j-1] integerValue];
            [output appendString:entry<0?links[-entry-1][@"closing"]:(entry==MPPICode?codeFence:MPPIMarker(entry,underscoreBold))];
        }
        for(NSUInteger j=common;j<desired.count;j++) {
            NSInteger entry=[desired[j] integerValue];
            [output appendString:entry<0?@"[":(entry==MPPICode?codeFence:MPPIMarker(entry,underscoreBold))];
        }
        stack=desired;
        [locations addObject:@(output.length)];
        BOOL surrogate=CFStringIsSurrogateHighCharacter([text characterAtIndex:i]) && i+1<text.length && CFStringIsSurrogateLowCharacter([text characterAtIndex:i+1]);
        if(surrogate) {
            if(![styles[i] isEqual:styles[i+1]]) return nil;
            NSString *rawCharacter=[text substringWithRange:NSMakeRange(i,2)]; NSString *escaped=(mask&MPPICode)?rawCharacter:escape(rawCharacter);
            NSUInteger start=output.length; [output appendString:escaped];
            [ends addObject:@(start+escaped.length-1)];
            [locations addObject:@(start+escaped.length-1)]; [ends addObject:@(output.length)]; i++;
        } else { [output appendString:(mask&MPPICode)?[text substringWithRange:NSMakeRange(i,1)]:escape([text substringWithRange:NSMakeRange(i,1)])]; [ends addObject:@(output.length)]; }

    }
    for(NSUInteger j=stack.count;j;j--) {
        NSInteger entry=[stack[j-1] integerValue];
        [output appendString:entry<0?links[-entry-1][@"closing"]:(entry==MPPICode?codeFence:MPPIMarker(entry,underscoreBold))];
    }
    NSUInteger start=[locations[selected.location] unsignedIntegerValue];
    NSUInteger last=NSMaxRange(selected)-1;
    NSUInteger end=[ends[last] unsignedIntegerValue];
    return @{@"replacement":output,@"selection":[NSValue valueWithRange:NSMakeRange(start,end-start)]};
}


static void MPPIFingerprintNode(NSXMLNode *node, NSUInteger mask, NSMutableArray *tokens)
{
    NSMutableDictionary *linkAttributes=nil;
    for(NSXMLNode *parent=node.parent;parent;parent=parent.parent) if([parent.name.lowercaseString isEqualToString:@"a"]) {
        linkAttributes=[NSMutableDictionary dictionary];
        for(NSXMLNode *attribute in [(NSXMLElement *)parent attributes]) linkAttributes[attribute.name]=attribute.stringValue ?: @"";
        break;
    }
    if(node.kind==NSXMLTextKind) {
        NSString *text=node.stringValue ?: @"";
        for(NSUInteger i=0;i<text.length;i++) {
            unichar c=[text characterAtIndex:i];
            // Ignore renderer/tidy line-ending artifacts outside code. Block
            // structure and all ordinary spaces remain part of verification.
            if((c=='\n' || c=='\r') && ![node.parent.name.lowercaseString isEqualToString:@"code"] && ![node.parent.name.lowercaseString isEqualToString:@"pre"]) continue;
            NSUInteger effective=[NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:c]?0:mask;
            NSMutableDictionary *token=[@{@"text":[text substringWithRange:NSMakeRange(i,1)],@"mask":@(effective)} mutableCopy];
            if(linkAttributes) token[@"link"]=linkAttributes;
            [tokens addObject:token];
        }
        return;
    }
    if(node.kind!=NSXMLElementKind) return;
    NSString *tag=node.name.lowercaseString;
    BOOL style=YES;
    if([@[@"strong",@"b"] containsObject:tag]) mask|=MPPIBold;
    else if([@[@"em",@"i"] containsObject:tag]) mask|=MPPIItalic;
    else if([tag isEqualToString:@"u"]) mask|=MPPIUnderline;
    else if([@[@"del",@"s",@"strike"] containsObject:tag]) mask|=MPPIStrike;
    else if([tag isEqualToString:@"code"] && ![node.parent.name.lowercaseString isEqualToString:@"pre"]) mask|=MPPICode;
    else if([tag isEqualToString:@"a"]) style=YES;
    else style=NO;
    // These legacy wrappers may be removed, never created by serialization.
    if([tag isEqualToString:@"span"] && [(NSXMLElement *)node attributeForName:@"style"]) style=YES;
    NSMutableDictionary *attributes=[NSMutableDictionary dictionary];
    for(NSXMLNode *attribute in [(NSXMLElement *)node attributes]) attributes[attribute.name]=attribute.stringValue ?: @"";
    if(!style) {
        NSMutableDictionary *opening=[@{@"open":tag,@"attributes":attributes} mutableCopy];if(linkAttributes) opening[@"link"]=linkAttributes;[tokens addObject:opening];
    }
    for(NSXMLNode *child in node.children) MPPIFingerprintNode(child,mask,tokens);
    if(!style) [tokens addObject:@{@"close":tag}];
}

static NSArray *MPPIFingerprint(NSString *html)
{
    if(!html) return nil;
    NSXMLDocument *document=MPPIParseHTML(html);
    NSXMLNode *body=[[document nodesForXPath:@"//body" error:NULL] firstObject];
    if(!body) return nil;
    NSMutableArray *tokens=[NSMutableArray array]; MPPIFingerprintNode(body,0,tokens); return tokens;
}

static NSArray<NSString *> *MPPILegacyColorOpenings(void)
{
    static NSArray *tags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tags=@[
        @"<span style=\"color:#b42318\">",@"<span style=\"color:#b54708\">",@"<span style=\"color:#067647\">",@"<span style=\"color:#175cd3\">",@"<span style=\"color:#6938ef\">",
        @"<span style=\"background-color:#fef08a;color:#111\">",@"<span style=\"background-color:#bbf7d0;color:#111\">",@"<span style=\"background-color:#bfdbfe;color:#111\">",@"<span style=\"background-color:#fbcfe8;color:#111\">"];
    });
    return tags;
}

static NSString *MPPIWithoutLegacyTags(NSString *body, NSMutableArray *positions)
{
    NSMutableString *result=[NSMutableString string];
    NSMutableArray *tags=[@[@"<u>",@"</u>",@"</span>"] mutableCopy];
    [tags addObjectsFromArray:MPPILegacyColorOpenings()];
    for(NSUInteger i=0;i<body.length;) {
        NSUInteger skip=0;
        for(NSString *tag in tags) if(i+tag.length<=body.length && [[body substringWithRange:NSMakeRange(i,tag.length)] isEqualToString:tag]) {skip=tag.length;break;}
        if(skip) {i+=skip;continue;}
        [positions addObject:@(i)]; [result appendFormat:@"%C",[body characterAtIndex:i++]];
    }
    return result;
}


// Preserve source-backed links, code and legacy colors as opaque atoms when
// they lie outside the selection. They are put back byte-for-byte, and the
// final full-document parser check verifies their structure and attributes.
static NSString *MPPIMaskOpaque(NSString *body, NSRange selection, NSUInteger base, NSString *action,
                                NSMutableArray *positions, NSMutableDictionary *opaque, NSMutableArray *links)
{
    NSMutableArray *colorOpenings=[NSMutableArray array];
    for(NSString *opening in MPPILegacyColorOpenings())
        [colorOpenings addObject:[NSRegularExpression escapedPatternForString:opening]];
    NSString *pattern=[NSString stringWithFormat:
        @"(`+)([^`\\n]*?)\\1|(?:%@)(?:(?!<span\\b|</span>)[\\s\\S])*</span>|!?\\[(?:\\\\.|[^\\]\\n])*\\]\\((?:\\\\.|[^)\\n])*\\)",
        [colorOpenings componentsJoinedByString:@"|"]];
    NSRegularExpression *expression=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSArray *matches=[expression matchesInString:body options:0 range:NSMakeRange(0,body.length)];
    NSRegularExpression *legacyOpening=[NSRegularExpression regularExpressionWithPattern:
        [colorOpenings componentsJoinedByString:@"|"] options:0 error:NULL];
    // The shallow atom grammar cannot prove ownership of nested colors or a
    // color inside a link being rewritten. Refuse these cases before removing
    // legacy tags; an untouched opaque link/code atom remains safe verbatim.
    for (NSTextCheckingResult *opening in [legacyOpening matchesInString:body options:0 range:NSMakeRange(0,body.length)]) {
        BOOL protected = NO;
        for (NSTextCheckingResult *match in matches) {
            if (opening.range.location < match.range.location || NSMaxRange(opening.range) > NSMaxRange(match.range)) continue;
            BOOL opaqueOutside = !NSIntersectionRange(NSMakeRange(base+match.range.location,match.range.length),selection).length;
            protected = [body characterAtIndex:match.range.location]=='<' || opaqueOutside;
            break;
        }
        if (!protected) return nil;
    }
    NSMutableString *result=[NSMutableString string]; NSUInteger cursor=0;
    for(NSTextCheckingResult *match in matches) {
        NSRange range=match.range;
        if(NSIntersectionRange(NSMakeRange(base+range.location,range.length),selection).length) {
            if([body characterAtIndex:range.location]=='`') continue;
            if([body characterAtIndex:range.location]=='<') {
                NSString *raw=[body substringWithRange:range];
                NSUInteger contentStart=base+range.location+NSMaxRange([raw rangeOfString:@">"]);
                NSUInteger contentEnd=base+NSMaxRange(range)-@"</span>".length;
                // Color has no Markdown-only representation. Do not silently
                // remove it from unselected characters or while adding a style.
                // Explicit clear can remove a complete legacy colored passage.
                if(![action isEqualToString:@"clear"] || selection.location>contentStart || NSMaxRange(selection)<contentEnd) return nil;
                continue;
            }
            if([body characterAtIndex:range.location]!='[') return nil;
            NSString *raw=[body substringWithRange:range]; NSRange divider=[raw rangeOfString:@"](" options:NSBackwardsSearch];
            if(divider.location==NSNotFound || divider.location<1) return nil;
            for(NSUInteger i=cursor;i<range.location;i++) {[result appendFormat:@"%C",[body characterAtIndex:i]];[positions addObject:@(i)];}
            NSUInteger labelStart=range.location+1,labelLength=divider.location-1;
            [links addObject:@{@"source":[NSValue valueWithRange:NSMakeRange(base+labelStart,labelLength)],@"closing":[raw substringFromIndex:divider.location]}];
            for(NSUInteger i=labelStart;i<labelStart+labelLength;i++) {[result appendFormat:@"%C",[body characterAtIndex:i]];[positions addObject:@(i)];}
            cursor=NSMaxRange(range);continue;
        }
        for(NSUInteger i=cursor;i<range.location;i++) {[result appendFormat:@"%C",[body characterAtIndex:i]];[positions addObject:@(i)];}
        NSString *key=[NSString stringWithFormat:@"\uE100%@\uE101",[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
        // UUID atoms contain only ordinary literal characters, so the parser
        // cannot reinterpret their contents as inline Markdown.
        if([body containsString:key]) return nil;
        opaque[key]=[body substringWithRange:range];
        [result appendString:key];
        for(NSUInteger i=0;i<key.length;i++) [positions addObject:@(range.location)];
        cursor=NSMaxRange(range);
    }
    for(NSUInteger i=cursor;i<body.length;i++) {[result appendFormat:@"%C",[body characterAtIndex:i]];[positions addObject:@(i)];}
    return result;
}

// List items are independent inline parsing contexts. Close/reopen styles at
// soft line breaks before introducing list prefixes. Keep authored bytes (and
// opaque links/images/code) verbatim, and accept only an identical full DOM
// fingerprint. The returned boundary map feeds the existing atomic transaction.
static NSDictionary *MPPIBalanceSoftLines(NSString *raw, NSString *(^render)(NSString *))
{
    NSUInteger firstEnd;
    [raw getLineStart:NULL end:&firstEnd contentsEnd:NULL forRange:NSMakeRange(0,0)];
    if(firstEnd==raw.length || [raw rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*_~`"]].location==NSNotFound) return @{};
    if (raw.length>20000) return nil;
    NSMutableString *canonical=[NSMutableString string];
    NSMutableArray *rawOffsets=[NSMutableArray array];
    for (NSUInteger i=0;i<raw.length;i++) {
        [rawOffsets addObject:@(i)];
        unichar c=[raw characterAtIndex:i];
        [canonical appendFormat:@"%C",c=='\r'?'\n':c];
        if(c=='\r' && i+1<raw.length && [raw characterAtIndex:i+1]=='\n') i++;
    }
    while([canonical hasSuffix:@"\n"]) {[canonical deleteCharactersInRange:NSMakeRange(canonical.length-1,1)];[rawOffsets removeLastObject];}
    NSMutableArray *proxyOffsets=[NSMutableArray array],*links=[NSMutableArray array];
    NSMutableDictionary *opaque=[NSMutableDictionary dictionary];
    NSString *proxy=MPPIMaskOpaque(canonical,NSMakeRange(0,0),0,@"preserve",proxyOffsets,opaque,links);
    if(!proxy) return nil;
    NSDictionary *oracle=MPPIInlineOracle(render(proxy));
    if(!oracle) return @{};
    NSString *text=oracle[@"text"]; NSArray *styles=oracle[@"styles"];
    NSMutableArray *breaks=[NSMutableArray array];
    for(NSUInteger i=0;i<text.length;i++) if([text characterAtIndex:i]=='\n' && [styles[i] unsignedIntegerValue]) {
        NSUInteger left=i,right=i+1;
        while(left && [NSCharacterSet.whitespaceCharacterSet characterIsMember:[text characterAtIndex:left-1]]) left--;
        while(right<text.length && [NSCharacterSet.whitespaceCharacterSet characterIsMember:[text characterAtIndex:right]]) right++;
        NSUInteger mask=[styles[i] unsignedIntegerValue];
        if(!left || right>=text.length || (mask&MPPICode)) return nil;
        [breaks addObject:@{@"newline":@(i),@"mask":@(mask)}];
    }
    if(!breaks.count) return @{};
    NSArray *provenance=MPPIProvenance(proxy,text);
    if(!provenance) return nil;
    NSArray *original=MPPIFingerprint(render(raw));
    if(!original) return nil;
    NSArray *bits=@[@(MPPIBold),@(MPPIItalic),@(MPPIUnderline),@(MPPIStrike)];
    // All nesting orders are tried; the actual parser, rather than a delimiter
    // regex, proves which closure sequence preserves the original formatting.
    for(NSNumber *a in bits) for(NSNumber *b in bits) for(NSNumber *c in bits) for(NSNumber *d in bits) {
        NSArray *order=@[a,b,c,d]; if([NSSet setWithArray:order].count!=4) continue;
        for(NSUInteger underscore=0;underscore<2;underscore++) {
            NSMutableDictionary *insertions=[NSMutableDictionary dictionary];
            BOOL valid=YES;
            for(NSDictionary *lineBreak in breaks) {
                NSUInteger newline=[lineBreak[@"newline"] unsignedIntegerValue];
                NSUInteger proxyOffset=[provenance[newline] unsignedIntegerValue];
                NSUInteger canonicalOffset=[proxyOffsets[proxyOffset] unsignedIntegerValue];
                NSUInteger close=[rawOffsets[canonicalOffset] unsignedIntegerValue];
                NSUInteger open=close+1;
                if([raw characterAtIndex:close]=='\r' && open<raw.length && [raw characterAtIndex:open]=='\n') open++;
                while(close && ([raw characterAtIndex:close-1]==' ' || [raw characterAtIndex:close-1]=='\t')) close--;
                while(open<raw.length && ([raw characterAtIndex:open]==' ' || [raw characterAtIndex:open]=='\t')) open++;
                NSMutableString *opening=[NSMutableString string],*closing=[NSMutableString string];
                NSUInteger mask=[lineBreak[@"mask"] unsignedIntegerValue];
                for(NSNumber *bit in order) if(mask&bit.unsignedIntegerValue) [opening appendString:MPPIMarker(bit.unsignedIntegerValue,underscore==1)];
                for(NSNumber *bit in order.reverseObjectEnumerator) if(mask&bit.unsignedIntegerValue) [closing appendString:MPPIMarker(bit.unsignedIntegerValue,underscore==1)];
                if(insertions[@(close)] || insertions[@(open)]) {valid=NO;break;}
                insertions[@(close)]=closing;insertions[@(open)]=opening;
            }
            if(!valid) continue;
            NSMutableString *candidate=[NSMutableString string];NSMutableArray *positions=[NSMutableArray array];
            for(NSUInteger i=0;i<=raw.length;i++) {
                [candidate appendString:insertions[@(i)] ?: @""];
                [positions addObject:@(candidate.length)];
                if(i<raw.length) [candidate appendFormat:@"%C",[raw characterAtIndex:i]];
            }
            if([MPPIFingerprint(render(candidate)) isEqual:original]) return @{@"replacement":candidate,@"positions":positions};
        }
    }
    return nil;
}

static NSURL *MPPIValidatedLinkURL(NSString *value)
{
    if (![value isKindOfClass:NSString.class] ||
        [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"<>\\\"\r\n"]].location!=NSNotFound) return nil;
    NSURL *url=[NSURL URLWithString:value];
    return [@[@"http",@"https",@"mailto"] containsObject:url.scheme.lowercaseString] ? url : nil;
}

static NSDictionary *MPPreviewInlineSingleChange(NSString *source, NSRange selection, NSString *action,
                                          NSString *value, NSString *(^render)(NSString *),
                                          NSString *(^escape)(NSString *), NSString *mode)
{
    NSDictionary *bits=@{@"bold":@(MPPIBold),@"italic":@(MPPIItalic),@"underline":@(MPPIUnderline),@"strike":@(MPPIStrike),@"code":@(MPPICode)};
    BOOL clear=[action isEqualToString:@"clear"]; BOOL linkAction=[action isEqualToString:@"link"];
    NSNumber *requested=bits[action];
    if((!clear && !requested && !linkAction) || !selection.length || selection.location>source.length || selection.length>source.length-selection.location || !render || !escape) return nil;
    NSURL *newURL=linkAction ? MPPIValidatedLinkURL(value) : nil;
    if(linkAction && !newURL) return nil;
    NSRange line=[source lineRangeForRange:selection];
    NSString *raw=[source substringWithRange:line];
    NSString *ending=@"";
    if([raw hasSuffix:@"\r\n"]) {ending=@"\r\n";raw=[raw substringToIndex:raw.length-2];}
    else if([raw hasSuffix:@"\n"] || [raw hasSuffix:@"\r"]) {ending=[raw substringFromIndex:raw.length-1];raw=[raw substringToIndex:raw.length-1];}
    NSString *linePrefix=@"(?:(?:#{1,6}[ \\t]+)|(?:[-+*][ \\t]+(?:\\[[ xX]\\][ \\t]+)?)|(?:[0-9]+[.)][ \\t]+))";
    // A quoted line can have several quote levels and then a heading/list
    // prefix. Preserve all structural syntax outside the inline text oracle.
    NSString *prefixPattern=[NSString stringWithFormat:@"^ {0,3}(?:(?:>[ \\t]?)+(?:%@)?|%@)",linePrefix,linePrefix];
    NSRegularExpression *prefixExpression=[NSRegularExpression regularExpressionWithPattern:prefixPattern options:0 error:NULL];
    NSTextCheckingResult *prefixMatch=[prefixExpression firstMatchInString:raw options:0 range:NSMakeRange(0,raw.length)];
    NSUInteger prefixLength=prefixMatch?prefixMatch.range.length:0;
    NSString *prefix=[raw substringToIndex:prefixLength]; NSString *body=[raw substringFromIndex:prefixLength];
    // Refuse before rendering or allocating a style entry per character.
    if(body.length>20000) return nil;
    NSMutableArray *opaquePositions=[NSMutableArray array]; NSMutableDictionary *opaque=[NSMutableDictionary dictionary]; NSMutableArray *links=[NSMutableArray array];
    NSString *proxy=MPPIMaskOpaque(body,selection,line.location+prefixLength,action,opaquePositions,opaque,links);
    if(!proxy) return nil;
    NSDictionary *oracle=MPPIInlineOracle(render(proxy));
    NSString *text=oracle[@"text"]; NSArray *original=oracle[@"styles"];
    if(!text.length || text.length!=original.count) return nil;
    NSMutableArray *sourcePositions=[NSMutableArray array];
    NSString *filtered=MPPIWithoutLegacyTags(proxy,sourcePositions);
    NSArray *filteredMapping=MPPIProvenance(filtered,text); if(!filteredMapping) return nil;
    NSMutableArray *mapping=[NSMutableArray array];
    for(NSNumber *offset in filteredMapping) [mapping addObject:@(line.location+prefixLength+[opaquePositions[[sourcePositions[offset.unsignedIntegerValue] unsignedIntegerValue]] unsignedIntegerValue])];
    for(NSUInteger index=0;index<links.count;index++) {
        NSMutableDictionary *link=[links[index] mutableCopy]; NSRange owned=[link[@"source"] rangeValue];
        NSUInteger start=NSNotFound,end=NSNotFound;
        for(NSUInteger i=0;i<mapping.count;i++) {NSUInteger position=[mapping[i] unsignedIntegerValue];if(position>=owned.location && position<NSMaxRange(owned)) {if(start==NSNotFound) start=i;end=i;}}
        if(start==NSNotFound) return nil;
        link[@"visible"]=[NSValue valueWithRange:NSMakeRange(start,end-start+1)];links[index]=link;
    }
    NSUInteger first=NSNotFound,last=NSNotFound;
    for(NSUInteger i=0;i<mapping.count;i++) {
        NSUInteger position=[mapping[i] unsignedIntegerValue];
        if(position>=selection.location && position<NSMaxRange(selection)) {if(first==NSNotFound) first=i;last=i;}
    }
    if(first==NSNotFound) return nil;
    // Selected source boundaries must coincide with the literal mapped text,
    // optionally encompassing emphasis markers only in the interior.
    if(!mode && ([mapping[first] unsignedIntegerValue]!=selection.location || [mapping[last] unsignedIntegerValue]+1!=NSMaxRange(selection))) return nil;
    NSRange visible=NSMakeRange(first,last-first+1);
    NSMutableArray *expected=[original mutableCopy];
    NSUInteger bit=requested.unsignedIntegerValue; BOOL all=YES;
    for(NSUInteger i=first;i<=last;i++) {
        // Markdown code spans trim edge whitespace. Varying emphasis inside a
        // selection therefore requires separate code spans around the letters.
        // Those separators do not prevent the next Code click from toggling off.
        if(bit==MPPICode && [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[text characterAtIndex:i]]) continue;
        if(!([original[i] unsignedIntegerValue]&bit)) all=NO;
    }
    for(NSUInteger i=first;i<=last;i++) {
        NSUInteger mask=[original[i] unsignedIntegerValue]; BOOL remove=all; if([mode isEqualToString:@"add"]) remove=NO; if([mode isEqualToString:@"remove"]) remove=YES; expected[i]=@(linkAction?mask:(clear?0:(remove?mask&~bit:mask|bit)));
    }
    NSDictionary *newLinkAttributes=nil;
    if(linkAction) {
        NSMutableArray *updated=[NSMutableArray array];
        for(NSDictionary *link in links) {
            NSRange owned=[link[@"visible"] rangeValue];
            if(!NSIntersectionRange(owned,visible).length) {[updated addObject:link];continue;}
            if(owned.location<visible.location) {NSMutableDictionary *part=[link mutableCopy];part[@"visible"]=[NSValue valueWithRange:NSMakeRange(owned.location,visible.location-owned.location)];[updated addObject:part];}
            if(NSMaxRange(owned)>NSMaxRange(visible)) {NSMutableDictionary *part=[link mutableCopy];part[@"visible"]=[NSValue valueWithRange:NSMakeRange(NSMaxRange(visible),NSMaxRange(owned)-NSMaxRange(visible))];[updated addObject:part];}
        }
        NSString *closing=[NSString stringWithFormat:@"](<%@>)",newURL.absoluteString];
        [updated addObject:@{@"visible":[NSValue valueWithRange:visible],@"closing":closing}]; links=updated;
        NSArray *probe=MPPIFingerprint(render([@"[x" stringByAppendingString:closing]));
        for(NSDictionary *token in probe) if(token[@"link"]) {newLinkAttributes=token[@"link"];break;}
        if(!newLinkAttributes) return nil;
    }
    NSArray *before=MPPIFingerprint(render(source)); if(!before) return nil;
    NSArray *orders=@[@[@1,@2,@4,@8,@16],@[@2,@1,@4,@8,@16],@[@4,@1,@2,@8,@16],@[@8,@1,@2,@4,@16],@[@1,@4,@8,@2,@16],@[@2,@4,@8,@1,@16],@[@4,@8,@2,@1,@16],@[@8,@4,@2,@1,@16]];
    for(NSUInteger spelling=0;spelling<2;spelling++) for(NSUInteger variant=0;variant<2;variant++) for(NSArray *order in orders) {
        NSString *(^inlineEscape)(NSString *)=spelling?escape:^NSString *(NSString *part) {
            NSMutableString *escaped=[NSMutableString string];
            NSCharacterSet *syntax=[NSCharacterSet characterSetWithCharactersInString:@"\\`*_~[]<>!&^$"];
            for(NSUInteger i=0;i<part.length;i++) {unichar c=[part characterAtIndex:i];if([syntax characterIsMember:c]) [escaped appendString:@"\\"];[escaped appendFormat:@"%C",c];}
            return escaped;
        };
        NSDictionary *serialization=MPPISerialize(text,expected,order,visible,variant==1,links,inlineEscape);
        NSString *newBody=serialization[@"replacement"];
        NSDictionary *newOracle=MPPIInlineOracle(render(newBody));
        if(![newOracle[@"text"] isEqualToString:text]) continue;
        NSArray *actual=newOracle[@"styles"]; BOOL matches=actual.count==expected.count;
        for(NSUInteger i=0;matches && i<expected.count;i++) if(![NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[text characterAtIndex:i]] && ![actual[i] isEqual:expected[i]]) matches=NO;
        if(!matches) continue;
        NSRange retained=[serialization[@"selection"] rangeValue];
        // Replace from the end so source positions before each atom stay valid.
        NSMutableString *restored=[newBody mutableCopy];
        NSMutableArray *atoms=[NSMutableArray array];
        for(NSString *key in opaque) {
            NSRange atom=[newBody rangeOfString:key options:NSLiteralSearch];
            if(atom.location==NSNotFound || [newBody rangeOfString:key options:NSLiteralSearch range:NSMakeRange(NSMaxRange(atom),newBody.length-NSMaxRange(atom))].location!=NSNotFound) { matches=NO;break; }
            [atoms addObject:@{@"range":[NSValue valueWithRange:atom],@"raw":opaque[key]}];
        }
        if(!matches) continue;
        [atoms sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {NSUInteger x=[a[@"range"] rangeValue].location,y=[b[@"range"] rangeValue].location;return x>y?NSOrderedAscending:x<y?NSOrderedDescending:NSOrderedSame;}];
        for(NSDictionary *atom in atoms) {
            NSRange atomRange=[atom[@"range"] rangeValue]; NSString *rawAtom=atom[@"raw"];
            if(NSIntersectionRange(atomRange,retained).length) {matches=NO;break;}
            if(NSMaxRange(atomRange)<=retained.location) retained.location=retained.location-atomRange.length+rawAtom.length;
            [restored replaceCharactersInRange:atomRange withString:rawAtom];
        }
        if(!matches) continue;
        NSString *replacement=[NSString stringWithFormat:@"%@%@%@",prefix,restored,ending];
        NSString *candidate=[source stringByReplacingCharactersInRange:line withString:replacement];
        NSArray *after=MPPIFingerprint(render(candidate)); if(after.count!=before.count) continue;
        // Locate only the selected literal run. Every other semantic token,
        // including neighboring link destinations and code, must stay equal.
        NSString *selectedText=[text substringWithRange:visible];
        NSMutableString *comparable=[NSMutableString string]; NSMutableArray *selectedOffsets=[NSMutableArray array];
        for(NSUInteger i=0;i<selectedText.length;i++) {
            unichar character=[selectedText characterAtIndex:i];
            if(character=='\r' || character=='\n') continue;
            [comparable appendFormat:@"%C",character];[selectedOffsets addObject:@(i)];
        }
        NSMutableArray *literalIndices=[NSMutableArray array];
        for(NSUInteger i=0;i<before.count;i++) if(before[i][@"text"]) [literalIndices addObject:@(i)];
        BOOL verified=NO;
        for(NSUInteger start=0;start+comparable.length<=literalIndices.count && !verified;start++) {
            BOOL found=YES;
            for(NSUInteger i=0;found && i<comparable.length;i++) {
                NSUInteger offset=[selectedOffsets[i] unsignedIntegerValue];
                NSDictionary *token=before[[literalIndices[start+i] unsignedIntegerValue]];
                NSUInteger mask=[NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[comparable characterAtIndex:i]]?0:[original[first+offset] unsignedIntegerValue];
                found=[token[@"text"] isEqualToString:[comparable substringWithRange:NSMakeRange(i,1)]] && [token[@"mask"] unsignedIntegerValue]==mask;
            }
            if(!found) continue;
            NSMutableDictionary *allowed=[NSMutableDictionary dictionary];
            for(NSUInteger i=0;i<comparable.length;i++) allowed[literalIndices[start+i]]=selectedOffsets[i];
            verified=YES;
            for(NSUInteger i=0;verified && i<before.count;i++) {
                NSNumber *allowedOffset=allowed[@(i)];
                if(allowedOffset) {
                    NSUInteger offset=allowedOffset.unsignedIntegerValue;
                    NSUInteger mask=[NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[selectedText characterAtIndex:offset]]?0:[expected[first+offset] unsignedIntegerValue];
                    NSMutableDictionary *required=[before[i] mutableCopy];required[@"mask"]=@(mask);
                    if(linkAction) required[@"link"]=newLinkAttributes;
                    verified=[after[i] isEqual:required];
                } else verified=[before[i] isEqual:after[i]];
            }
        }
        if(!verified) continue;
        retained.location+=prefix.length;
        return @{@"range":[NSValue valueWithRange:line],@"replacement":replacement,@"selection":[NSValue valueWithRange:retained],@"text":[text substringWithRange:visible],@"active":@(all)};
    }
    return nil;
}


// A rendered selection crossing a Setext heading and its next block includes
// the underline in its contiguous source envelope. It is structural syntax,
// not selected text. Only the complete parser can authorize skipping it.
static BOOL MPPIIsHeadingUnderline(NSString *source, NSRange line, NSString *(^render)(NSString *))
{
    if (!line.location) return NO;
    NSString *raw=[source substringWithRange:line];
    NSRegularExpression *underline=[NSRegularExpression regularExpressionWithPattern:@"\\A {0,3}(?:=+|-+)[ \\t]*(?:\\r?\\n)?\\z" options:0 error:NULL];
    if (![underline firstMatchInString:raw options:0 range:NSMakeRange(0,raw.length)]) return NO;
    NSRange previous=[source lineRangeForRange:NSMakeRange(line.location-1,0)];
    NSRange pair=NSMakeRange(previous.location,NSMaxRange(line)-previous.location);
    NSXMLDocument *pairDOM=MPPIParseHTML(render([source substringWithRange:pair]));
    NSArray *roots=[pairDOM nodesForXPath:@"//body/*" error:NULL];
    NSXMLNode *root=roots.firstObject;
    if (roots.count!=1 || ![@[@"h1",@"h2"] containsObject:root.name.lowercaseString]) return NO;
    NSUInteger end;
    [source getLineStart:NULL end:NULL contentsEnd:&end forRange:NSMakeRange(line.location-1,0)];
    NSString *marker=[@"macdownSetextProbe" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *HTML=render([source stringByReplacingCharactersInRange:NSMakeRange(end,0) withString:marker]);
    NSXMLDocument *DOM=MPPIParseHTML(HTML);
    NSString *path=[NSString stringWithFormat:@"//h1[contains(string(.),'%@')]|//h2[contains(string(.),'%@')]",marker,marker];
    if ([DOM nodesForXPath:path error:NULL].count!=1) return NO;
    // The probe changes the generated heading slug. Pair parsing establishes
    // the underline, and the full-source probe establishes its real context;
    // comparing IDs derived from the marked title would reject valid Setext.
    return YES;
}

static NSDictionary *MPPreviewInlineChange(NSString *source, NSRange selection, NSString *action,
                                          NSString *value, NSString *(^render)(NSString *),
                                          NSString *(^escape)(NSString *))
{
    if(!selection.length || selection.location>source.length || selection.length>source.length-selection.location || !render || !escape) return nil;
    NSRange region=[source lineRangeForRange:selection];
    NSString *raw=[source substringWithRange:region];
    NSString *withoutEnding=raw;
    while([withoutEnding hasSuffix:@"\n"] || [withoutEnding hasSuffix:@"\r"]) withoutEnding=[withoutEnding substringToIndex:withoutEnding.length-1];
    // A soft-wrapped paragraph can contain emphasis spanning physical lines.
    // Parse that complete source region as one paragraph before considering
    // independent block transactions. The oracle rejects multiple blocks.
    NSDictionary *paragraph=MPPreviewInlineSingleChange(source,selection,action,value,render,escape,nil);
    if(paragraph) return paragraph;
    if([withoutEnding rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound) return nil;
    NSMutableArray *items=[NSMutableArray array]; NSMutableArray *texts=[NSMutableArray array]; BOOL all=YES;
    NSUInteger cursor=region.location; NSCharacterSet *whitespace=NSCharacterSet.whitespaceAndNewlineCharacterSet;
    while(cursor<NSMaxRange(region)) {
        if(items.count>=128) return nil;
        NSRange line=[source lineRangeForRange:NSMakeRange(cursor,0)];
        NSRange selected=NSIntersectionRange(line,selection);
        while(selected.length && [whitespace characterIsMember:[source characterAtIndex:selected.location]]) {selected.location++;selected.length--;}
        while(selected.length && [whitespace characterIsMember:[source characterAtIndex:NSMaxRange(selected)-1]]) selected.length--;
        if(selected.length) {
            NSDictionary *change=MPPreviewInlineSingleChange(source,selected,action,value,render,escape,@"auto");
            if(!change) {
                if (MPPIIsHeadingUnderline(source,line,render)) {cursor=NSMaxRange(line);continue;}
                // A blank quoted separator belongs to the selected region but
                // has no inline characters to style. Prove that it renders no
                // text; the final fingerprint still preserves its block shape.
                NSString *rawLine=[source substringWithRange:line];
                BOOL quoteOnly=[rawLine rangeOfString:@"\\A {0,3}(?:>[ \\t]?)+[ \\t\\r\\n]*\\z" options:NSRegularExpressionSearch].location!=NSNotFound;
                if(quoteOnly) {
                    NSArray *tokens=MPPIFingerprint(render(rawLine));
                    BOOL noText=tokens!=nil;
                    for(NSDictionary *token in tokens) if(token[@"text"]) {noText=NO;break;}
                    if(noText) {[texts addObject:@""];cursor=NSMaxRange(line);continue;}
                }
                return nil;
            }
            [items addObject:@{@"selected":[NSValue valueWithRange:selected],@"change":change}];
            [texts addObject:change[@"text"]];all=all && [change[@"active"] boolValue];
        } else [texts addObject:@""];
        cursor=NSMaxRange(line);
    }
    if(!items.count) return nil;
    NSArray *before=MPPIFingerprint(render(source)); if(!before) return nil;
    NSMutableArray *expected=[before mutableCopy]; NSMutableArray *changes=[NSMutableArray array];
    for(NSDictionary *item in items) {
        NSRange selected=[item[@"selected"] rangeValue];
        NSDictionary *change=MPPreviewInlineSingleChange(source,selected,action,value,render,escape,all?@"remove":@"add");
        if(!change) return nil;
        NSString *individual=[source stringByReplacingCharactersInRange:[change[@"range"] rangeValue] withString:change[@"replacement"]];
        NSArray *after=MPPIFingerprint(render(individual)); if(after.count!=before.count) return nil;
        for(NSUInteger i=0;i<before.count;i++) if(![before[i] isEqual:after[i]]) {
            if(![expected[i] isEqual:before[i]] && ![expected[i] isEqual:after[i]]) return nil;
            expected[i]=after[i];
        }
        [changes addObject:change];
    }
    NSMutableString *candidate=[source mutableCopy];
    for(NSDictionary *change in changes.reverseObjectEnumerator)
        [candidate replaceCharactersInRange:[change[@"range"] rangeValue] withString:change[@"replacement"]];
    if(![MPPIFingerprint(render(candidate)) isEqual:expected]) return nil;
    NSInteger delta=(NSInteger)candidate.length-(NSInteger)source.length;
    NSString *replacement=[candidate substringWithRange:NSMakeRange(region.location,(NSUInteger)((NSInteger)region.length+delta))];
    NSDictionary *first=changes.firstObject,*last=changes.lastObject;
    NSRange firstLine=[first[@"range"] rangeValue],lastLine=[last[@"range"] rangeValue];
    NSRange firstSelected=[first[@"selection"] rangeValue],lastSelected=[last[@"selection"] rangeValue];
    NSUInteger start=firstLine.location-region.location+firstSelected.location;
    NSInteger beforeLast=0;
    for(NSUInteger i=0;i+1<changes.count;i++) beforeLast+=(NSInteger)[changes[i][@"replacement"] length]-(NSInteger)[changes[i][@"range"] rangeValue].length;
    NSUInteger end=(NSUInteger)((NSInteger)(lastLine.location-region.location+NSMaxRange(lastSelected))+beforeLast);
    return @{@"range":[NSValue valueWithRange:region],@"replacement":replacement,
        @"selection":[NSValue valueWithRange:NSMakeRange(start,end-start)],@"text":[texts componentsJoinedByString:@"\n"]};
}
