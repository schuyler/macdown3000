#import <Foundation/Foundation.h>

// Public HTML structure contracts shared by the application and Quick Look tests.
NS_INLINE NSArray<NSDictionary *> *MPBlockquoteTestCases(void)
{
    NSMutableArray *cases = [@[
        @{@"name":@"empty citation", @"source":@">", @"counts":@{@"//blockquote":@1, @"//blockquote/*":@0}},
        @{@"name":@"marker without space", @"source":@">citation\n", @"counts":@{@"//blockquote/p[normalize-space(.)='citation']":@1}},
        @{@"name":@"indented citation markers", @"source":@" > first\n  > second\n   > third\n# Outside\n", @"counts":@{@"//blockquote":@1, @"//blockquote/p[normalize-space(.)='first second third']":@1, @"//h1[normalize-space(.)='Outside' and not(ancestor::blockquote)]":@1}},
        @{@"name":@"citation syntax in fenced code", @"source":@"```markdown\n> citation\n# literal heading\n```\n", @"counts":@{@"//blockquote":@0, @"//pre/code[contains(., '> citation') and contains(., '# literal heading')]":@1}},
        @{@"name":@"citation syntax in indented code", @"source":@"    > citation\n", @"counts":@{@"//blockquote":@0, @"//pre/code[contains(., '> citation')]":@1}},
        @{@"name":@"no final newline", @"source":@"> citation", @"counts":@{@"//blockquote/p[normalize-space(.)='citation']":@1}},
        @{@"name":@"explicit continuation", @"source":@"> first\n> second\n", @"counts":@{@"//blockquote/p[normalize-space(.)='first second']":@1}},
        @{@"name":@"lazy continuation", @"source":@"> first\nsecond\n", @"counts":@{@"//blockquote/p[normalize-space(.)='first second']":@1}},
        @{@"name":@"quoted paragraphs", @"source":@"> first\n>\n> second\n", @"counts":@{@"//blockquote":@1, @"//blockquote/p":@2}},
        @{@"name":@"paragraph after citation", @"source":@"> first\n\nsecond\n", @"counts":@{@"//blockquote/p[normalize-space(.)='first']":@1, @"//p[normalize-space(.)='second' and not(ancestor::blockquote)]":@1}},
        @{@"name":@"separate citations", @"source":@"> first\n\nbetween\n\n> second\n", @"counts":@{@"//blockquote":@2, @"//p[normalize-space(.)='between' and not(ancestor::blockquote)]":@1}},
        @{@"name":@"nested citations", @"source":@"> outer\n>\n> > inner\n", @"counts":@{@"//blockquote":@2, @"//blockquote/blockquote/p[normalize-space(.)='inner']":@1}},
        @{@"name":@"heading exits both citations", @"source":@"> outer\n>\n> > inner\n# Outside", @"counts":@{@"//blockquote":@2, @"//h1[normalize-space(.)='Outside' and not(ancestor::blockquote)]":@1}},
        @{@"name":@"heading stays in outer citation", @"source":@"> outer\n>\n> > inner\n> # Outer heading\n", @"counts":@{@"//blockquote":@2, @"//blockquote/h1[normalize-space(.)='Outer heading' and count(ancestor::blockquote)=1]":@1, @"//blockquote/blockquote/h1":@0}},
        @{@"name":@"quoted fenced code", @"source":@"> ```markdown\n> # literal heading\n> ```\n# Outside\n", @"counts":@{@"//blockquote//pre/code[contains(., '# literal heading')]":@1, @"//blockquote//h1":@0, @"//h1[normalize-space(.)='Outside' and not(ancestor::blockquote)]":@1}},
        @{@"name":@"quoted indented code", @"source":@">     # literal heading\n", @"counts":@{@"//blockquote//pre/code[contains(., '# literal heading')]":@1, @"//blockquote//h1":@0}},
        @{@"name":@"inline formatting", @"source":@"> **bold**, *italic*, [link](https://example.com), `code`\n", @"counts":@{@"//blockquote/p/strong[normalize-space(.)='bold']":@1, @"//blockquote/p/em[normalize-space(.)='italic']":@1, @"//blockquote/p/a[@href='https://example.com']":@1, @"//blockquote/p/code[normalize-space(.)='code']":@1}},
        @{@"name":@"quoted unordered list", @"source":@"> - first\n> - second\n", @"counts":@{@"//blockquote/ul/li":@2}},
        @{@"name":@"quoted ordered list", @"source":@"> 1. first\n> 2. second\n", @"counts":@{@"//blockquote/ol/li":@2}},
        @{@"name":@"quoted thematic break", @"source":@"> first\n>\n> ---\n", @"counts":@{@"//blockquote/hr":@1}},
        @{@"name":@"quoted setext heading", @"source":@"> Quoted\n> ======\n", @"counts":@{@"//blockquote/h1[normalize-space(.)='Quoted']":@1}},
        @{@"name":@"heading after lazy text", @"source":@"> first\ncontinued\n# Outside\n", @"counts":@{@"//blockquote/p[normalize-space(.)='first continued']":@1, @"//h1[normalize-space(.)='Outside' and not(ancestor::blockquote)]":@1}},
        @{@"name":@"citation after heading", @"source":@"# Before\n> citation\n# After\n", @"counts":@{@"//h1[not(ancestor::blockquote)]":@2, @"//blockquote/p[normalize-space(.)='citation']":@1}}
    ] mutableCopy];
    for (NSUInteger level = 1; level <= 6; level++) {
        NSString *hashes = [@"######" substringToIndex:level];
        NSString *quotedXPath = [NSString stringWithFormat:@"//blockquote/h%lu[normalize-space(.)='Quoted']", (unsigned long)level];
        NSString *outsideXPath = [NSString stringWithFormat:@"//h%lu[normalize-space(.)='Outside' and not(ancestor::blockquote)]", (unsigned long)level];
        [cases addObject:@{@"name":[NSString stringWithFormat:@"heading level %lu", (unsigned long)level],
            @"source":[NSString stringWithFormat:@"> citation\n> %@ Quoted\n%@ Outside", hashes, hashes],
            @"counts":@{@"//blockquote":@1, quotedXPath:@1, outsideXPath:@1}}];
    }
    return cases;
}

NS_INLINE NSString *MPBlockquoteSource(NSString *source, NSUInteger wrapper, BOOL CRLF)
{
    if (wrapper == 1) source = [NSString stringWithFormat:@"::: {.callout-important}\n## Callout title\n%@\n:::\n", source];
    if (wrapper == 2) source = [NSString stringWithFormat:@"::: {.callout-note collapse=\"true\"}\n## Callout title\n%@\n:::\n", source];
    return CRLF ? [source stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"] : source;
}

NS_INLINE NSXMLDocument *MPBlockquoteDOM(NSString *html, NSError **error)
{
    NSRange body = [html rangeOfString:@"<body>"];
    NSRange end = [html rangeOfString:@"</body>" options:NSBackwardsSearch];
    if (body.location != NSNotFound && end.location != NSNotFound && NSMaxRange(body) <= end.location)
        html = [html substringWithRange:NSMakeRange(NSMaxRange(body), end.location - NSMaxRange(body))];
    // Parse the generated body without HTML Tidy, which drops HTML5 callout tags.
    // These fixtures only use hr/br as HTML void elements.
    html = [html stringByReplacingOccurrencesOfString:@"<hr>" withString:@"<hr/>"];
    html = [html stringByReplacingOccurrencesOfString:@"<br>" withString:@"<br/>"];
    return [[NSXMLDocument alloc] initWithXMLString:[NSString stringWithFormat:@"<root>%@</root>", html]
        options:NSXMLNodeLoadExternalEntitiesNever error:error];
}

NS_INLINE NSArray<NSXMLNode *> *MPBlockquoteNodes(NSXMLDocument *DOM, NSString *xpath, NSError **error)
{
    return [DOM nodesForXPath:xpath error:error];
}
