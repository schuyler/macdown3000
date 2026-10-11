#import <Foundation/Foundation.h>
#import "../../MacDownCore/MPQuickLookRenderer.h"
#import "../../MacDownCore/MPQuickLookPreferences.h"
#import "../../MacDownCore/MPMarkdownPreprocessor.h"
#import "../MPBlockquoteTestCases.h"
static void check(BOOL condition, NSString *message) { if (!condition) { fprintf(stderr,"%s\n",message.UTF8String); exit(1); } }
int main(void) { @autoreleasepool {
    MPQuickLookRenderer *renderer = [[MPQuickLookRenderer alloc] init];
    NSString *stableSource = @"::: {.callout-note}\n## Title\nBody\n:::\n\n<span data-macdown-callout-token=\"authored\">Literal</span>";
    NSString *stableHTML = [renderer renderMarkdown:stableSource];
    check([stableHTML isEqual:[renderer renderMarkdown:stableSource]], @"Quick Look must not publish random preview bridge identities");
    check([stableHTML containsString:@"data-macdown-callout-token=\"authored\""], @"Authored attributes must remain intact");
    NSString *quoteHeading = [renderer renderMarkdown:@"::: {.callout-important}\n## Titre TEST du callout\n> citation dans callout\n# titre dans callout\n\nencore test\n:::"];
    NSRange quoteEnd = [quoteHeading rangeOfString:@"</blockquote>"];
    NSRange bodyHeading = [quoteHeading rangeOfString:@">titre dans callout</h1>"];
    NSRange calloutEnd = [quoteHeading rangeOfString:@"</aside>"];
    check(quoteEnd.location != NSNotFound && bodyHeading.location != NSNotFound &&
          calloutEnd.location != NSNotFound && NSMaxRange(quoteEnd) < bodyHeading.location &&
          NSMaxRange(bodyHeading) < calloutEnd.location,
          @"An unquoted heading must follow the citation while remaining inside the callout");
    NSString *explicitQuote = [renderer renderMarkdown:@"> citation\n> # quoted title\n"];
    check([explicitQuote rangeOfString:@">quoted title</h1>"].location <
          [explicitQuote rangeOfString:@"</blockquote>"].location,
          @"An explicitly quoted heading must remain in the citation");
    NSString *lazyQuote = [renderer renderMarkdown:@"> citation\ncontinued text\n"];
    check([lazyQuote containsString:@"<p>citation\ncontinued text</p>"],
          @"Ordinary lazy paragraph continuation must remain quoted");
    NSUInteger quoteScenarios = 0;
    for (NSDictionary *testCase in MPBlockquoteTestCases()) {
        for (NSUInteger wrapper = 0; wrapper < 3; wrapper++) {
            for (NSNumber *CRLF in @[@NO, @YES]) {
                NSString *context = [NSString stringWithFormat:@"%@ / wrapper=%lu / CRLF=%@", testCase[@"name"], (unsigned long)wrapper, CRLF];
                NSString *html = [renderer renderMarkdown:MPBlockquoteSource(testCase[@"source"], wrapper, CRLF.boolValue)];
                NSError *error = nil;
                NSXMLDocument *DOM = MPBlockquoteDOM(html, &error);
                check(DOM != nil, [context stringByAppendingFormat:@": invalid HTML: %@", error]);
                for (NSString *xpath in testCase[@"counts"]) {
                    NSArray *nodes = MPBlockquoteNodes(DOM, xpath, &error);
                    check(nodes != nil && nodes.count == [testCase[@"counts"][xpath] unsignedIntegerValue],
                          [context stringByAppendingFormat:@": XPath %@ expected %@, got %lu (%@)\n%@", xpath, testCase[@"counts"][xpath], (unsigned long)nodes.count, error, DOM.XMLString]);
                }
                if (wrapper) {
                    NSString *container = wrapper == 1 ? @"//aside" : @"//details";
                    check(MPBlockquoteNodes(DOM, [container stringByAppendingString:@"//blockquote"], NULL).count ==
                          MPBlockquoteNodes(DOM, @"//blockquote", NULL).count,
                          [context stringByAppendingString:@": citation escaped its callout"]);
                }
                quoteScenarios++;
            }
        }
    }
    printf("PASS Quick Look citation matrix: %lu scenarios\n", (unsigned long)quoteScenarios);
    for (NSString *type in @[@"note",@"tip",@"warning",@"important",@"caution"]) {
        NSString *html = [renderer renderMarkdown:[NSString stringWithFormat:@"::: {.callout-%@}\n## A **title**\n\nA *body* with [link](https://example.com).\n:::",type]];
        check([html containsString:[@"mp-callout-" stringByAppendingString:type]], @"Missing callout type");
        check([html containsString:@"<strong>title</strong>"] && [html containsString:@"<em>body</em>"], @"Contents must use Markdown renderer");
        check(![html containsString:@"macdowncallout"], @"Opaque markers leaked");
    }
    NSString *nested = [renderer renderMarkdown:@"::: {.callout-note collapse=\"true\"}\n## Outer\n\n::: {.callout-tip collapse=false}\nInner\n:::\n\nAfter inner\n:::"];
    check([nested containsString:@"<details class=\"mp-callout mp-callout-note\">"], @"Collapsed callout must start closed");
    check([nested containsString:@"<details class=\"mp-callout mp-callout-tip\" open>"], @"Expanded callout must start open");
    check(![nested containsString:@"macdowncallout"], @"Nested markers leaked");
    for (NSString *literal in @[@"```markdown\n::: {.callout-note}\nCode\n:::\n```",@"~~~markdown\n::: {.callout-note}\nCode\n:::\n~~~",@"    ::: {.callout-note}\n    Code\n    :::",@"::: {.callout-note}\nUnclosed",@"::: {.callout-note title=\"unsupported\"}\nText\n:::",@"::: {.callout-unknown}\nText\n:::",@"<pre>\n::: {.callout-note}\nText\n:::\n</pre>",@"`\n::: {.callout-note}\nInline\n:::\n`"])
        { NSString *html = [renderer renderMarkdown:literal];
        check(![html containsString:@"class=\"mp-callout"], @"Literal or unsupported syntax was changed");
        check(![html containsString:@"macdowncallout"], @"Literal marker leaked"); }
    // Inline spans are collected before indented ranges. Literal protection
    // must remain correct when those groups overlap or are out of source order.
    NSString *mixed = [renderer renderMarkdown:@"    ::: {.callout-note}\n    Indented `code`\n    :::\n\n`\n::: {.callout-tip}\nInline\n:::\n`\n\n::: {.callout-warning}\nVisible\n:::"];
    check([mixed containsString:@"class=\"mp-callout mp-callout-warning\""] &&
          ![mixed containsString:@"class=\"mp-callout mp-callout-note\""] &&
          ![mixed containsString:@"class=\"mp-callout mp-callout-tip\""],
          @"Mixed literal ranges must protect code without suppressing real callouts");
    NSDictionary *prepared = MPPreprocessMarkdown(@"::: {.callout-note}\n\n- [ ] task\n:::\n",YES,10);
    NSString *marked = prepared[@"text"];
    NSString *offset = [prepared[@"taskPrefix"] stringByAppendingString:@"34Z"];
    check([marked containsString:offset], @"Checkbox source offset changed by callout insertion");
    puts("Quarto callouts: five types, Markdown contents, nesting, collapse, literal protection, unsupported syntax, source offsets passed");
} return 0; }
