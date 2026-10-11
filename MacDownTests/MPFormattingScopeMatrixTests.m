#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPEditorView.h"
#import "MPRenderer.h"
#import "MPPreferences.h"

@interface MPPreferences (ScopeMatrix)
- (int)rendererFlags;
@end
@interface MPRenderer (ScopeMatrix)
- (void)parseMarkdown:(NSString *)markdown;
@end
@interface MPDocument (ScopeMatrix)
@property (weak) MPEditorView *editor;
@property (strong) MPRenderer *renderer;
@property (copy) NSString *previewEditSource;
@property (copy) NSString *previewEditToken;
@property (copy) NSArray<NSDictionary *> *previewEditRanges;
- (BOOL)applyPreviewEditPayload:(NSDictionary *)payload;
- (BOOL)formatSourceInlineAction:(NSString *)action value:(NSString *)value;
- (void)convertSelectionToBlock:(NSString *)value;
- (IBAction)toggleStrong:(id)sender;
- (IBAction)toggleEmphasis:(id)sender;
- (IBAction)toggleUnderline:(id)sender;
- (IBAction)toggleStrikethrough:(id)sender;
- (IBAction)toggleInlineCode:(id)sender;
- (IBAction)convertToH1:(id)sender;
- (IBAction)convertToParagraph:(id)sender;
- (IBAction)toggleBlockquote:(id)sender;
@end

// Keep parsing and source validation real, but do not queue Web rendering for
// headless fixtures. Otherwise thousands of completed matrix transactions leave
// asynchronous publications pending ahead of the real WebView integration suite.
@interface MPScopeRenderer : MPRenderer
@end
@implementation MPScopeRenderer
- (void)parseAndRenderNow
{
    [self parseMarkdown:[self.dataSource rendererMarkdown:self] ?: @""];
}
- (void)parseAndRenderLater { [self parseAndRenderNow]; }
@end

// These tests use the real parser, source validator and document transaction.
// The fixture supplies literal DOM/source mappings and synchronous scheduling.
@interface MPScopeFixture : NSObject
@property (strong) MPDocument *document;
@property (strong) MPEditorView *editor;
@property (strong) MPRenderer *renderer;
- (instancetype)initWithSource:(NSString *)source;
- (BOOL)apply:(NSString *)action value:(NSString *)value text:(NSString *)text;
- (BOOL)applyContainer:(NSString *)value texts:(NSArray<NSString *> *)texts;
@end
@implementation MPScopeFixture
- (instancetype)initWithSource:(NSString *)source
{
    if ((self=[super init])) {
        _document=[MPDocument new];
        _editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
        _renderer=[MPScopeRenderer new];
        _document.editor=_editor; _document.renderer=_renderer;
        _renderer.delegate=(id<MPRendererDelegate>)_document;
        _renderer.dataSource=(id<MPRendererDataSource>)_document;
        _renderer.rendererFlags=_document.preferences.rendererFlags;
        _editor.delegate=(id<NSTextViewDelegate>)_document;
        _editor.allowsUndo=YES;
        _editor.string=source;
        [_document.undoManager removeAllActions];
    }
    return self;
}
- (BOOL)apply:(NSString *)action value:(NSString *)value text:(NSString *)text
{
    NSString *source=self.editor.string;
    NSRange range=[source rangeOfString:text];
    if (range.location==NSNotFound) return NO;
    self.renderer.rendererFlags=self.document.preferences.rendererFlags;
    [self.renderer parseMarkdown:source];
    NSMutableDictionary *entry=[@{@"location":@(range.location),@"length":@(range.length),@"text":text} mutableCopy];
    // Detect the paired source fence containing the selected literal run.
    // Production can generate an unlabelled or longer backtick fence; do not
    // assume the original fixture's ```text opener survives a conversion.
    NSRegularExpression *opening=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}(`{3,}|~{3,})([^\\r\\n]*)$" options:0 error:NULL];
    NSUInteger cursor=0,openStart=NSNotFound,contentStart=0;
    NSString *marker=nil;
    while (cursor<source.length) {
        NSUInteger lineStart,lineEnd,contentsEnd;
        [source getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(cursor,0)];
        NSString *line=[source substringWithRange:NSMakeRange(lineStart,contentsEnd-lineStart)];
        if (!marker) {
            NSTextCheckingResult *match=[opening firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
            if (match) {
                marker=[line substringWithRange:[match rangeAtIndex:1]];
                openStart=lineStart; contentStart=lineEnd;
            }
        } else {
            NSString *pattern=[NSString stringWithFormat:@"^ {0,3}%C{%lu,}[ \\t]*$",[marker characterAtIndex:0],(unsigned long)marker.length];
            NSRegularExpression *closing=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
            if ([closing firstMatchInString:line options:0 range:NSMakeRange(0,line.length)]) {
                if (range.location>=contentStart && NSMaxRange(range)<=lineStart) {
                    NSMutableArray *boundaries=[NSMutableArray array];
                    for (NSUInteger i=0;i<=text.length;i++) [boundaries addObject:@(range.location+i)];
                    entry[@"displayText"]=text; entry[@"sourceBoundaries"]=boundaries;
                    entry[@"codeBlockRange"]=[NSValue valueWithRange:NSMakeRange(openStart,lineEnd-openStart)];
                    entry[@"codeContentRange"]=[NSValue valueWithRange:NSMakeRange(contentStart,lineStart-contentStart)];
                    break;
                }
                marker=nil;
            }
        }
        cursor=lineEnd;
    }
    self.document.previewEditSource=source;
    self.document.previewEditToken=self.renderer.checkboxBridgeToken;
    self.document.previewEditRanges=@[entry];
    NSMutableDictionary *payload=[@{@"token":self.document.previewEditToken,@"id":@0,@"start":@0,@"end":@(text.length),@"text":text,@"action":action} mutableCopy];
    // These matrices explicitly exercise retyping the enclosing container.
    payload[@"containerIntent"]=@"container";
    if (value) payload[@"value"]=value;
    return [self.document applyPreviewEditPayload:payload];
}
- (BOOL)applyContainer:(NSString *)value texts:(NSArray<NSString *> *)texts
{
    NSString *source=self.editor.string;
    self.renderer.rendererFlags=self.document.preferences.rendererFlags;
    [self.renderer parseMarkdown:source];
    NSMutableArray *mapping=[NSMutableArray array],*runs=[NSMutableArray array];
    NSMutableString *visible=[NSMutableString string];
    NSUInteger cursor=0;
    for (NSString *text in texts) {
        NSRange range=[source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(cursor,source.length-cursor)];
        if (range.location==NSNotFound) return NO;
        if (mapping.count) for (NSUInteger i=cursor;i<range.location;i++) {
            unichar c=[source characterAtIndex:i];
            if (c=='\n' || c=='\r') [visible appendFormat:@"%C",c];
        }
        [visible appendString:text];
        [runs addObject:@{@"id":@(mapping.count),@"start":@0,@"end":@(text.length)}];
        [mapping addObject:@{@"location":@(range.location),@"length":@(range.length),@"text":text}];
        cursor=NSMaxRange(range);
    }
    self.document.previewEditSource=source; self.document.previewEditRanges=mapping;
    self.document.previewEditToken=self.renderer.checkboxBridgeToken;
    NSMutableDictionary *payload=[runs.firstObject mutableCopy];
    payload[@"runs"]=runs; payload[@"text"]=visible; payload[@"action"]=@"block";
    payload[@"value"]=value; payload[@"token"]=self.document.previewEditToken;
    payload[@"containerIntent"]=@"container";
    return [self.document applyPreviewEditPayload:payload];
}
- (void)dealloc { self.editor.delegate=nil; [self.document close]; }
@end

@interface MPFormattingScopeMatrixTests : XCTestCase
@property (copy) NSDictionary *oldPreferences;
@end
@implementation MPFormattingScopeMatrixTests
- (void)setUp
{
    [super setUp];
    MPPreferences *p=[MPPreferences sharedInstance];
    NSArray *keys=@[@"extensionIntraEmphasis",@"extensionUnderline",@"extensionStrikethough",@"extensionFencedCode",@"extensionSmartyPants",@"htmlTaskList",@"htmlMathJax",@"htmlHardWrap",@"extensionTables",@"extensionFootnotes",@"extensionAutolink",@"extensionSuperscript",@"extensionHighlight"];
    NSMutableDictionary *old=[NSMutableDictionary dictionary];
    for (NSString *key in keys) { old[key]=[p valueForKey:key]; [p setValue:@YES forKey:key]; }
    p.extensionSmartyPants=NO; p.htmlHardWrap=NO;
    // Math is exercised in its own dataset. Enabling it for every ordinary
    // fixture also reloads unrelated application previews with MathJax and
    // leaves expensive WebKit work pending ahead of the real menu tests.
    p.htmlMathJax=NO;
    self.oldPreferences=old;
}
- (void)tearDown
{
    MPPreferences *p=[MPPreferences sharedInstance];
    for (NSString *key in self.oldPreferences) [p setValue:self.oldPreferences[key] forKey:key];
    // AppKit defers text-view and undo cleanup to the main run loop. Drain
    // work enqueued by this synchronous dataset before the next WebView test
    // starts measuring its load; do not substitute a sleep or relax its checks.
    XCTestExpectation *drained=[self expectationWithDescription:@"Headless fixture main-queue cleanup"];
    dispatch_async(dispatch_get_main_queue(),^{[drained fulfill];});
    [self waitForExpectations:@[drained] timeout:30];
    [super tearDown];
}
- (void)testMultilineBoldSurvivesEveryListConversion
{
    NSString *body=@"**sdxerfe\nezrfvzer\ntrzevzer**\nzvzre\nrzev ze\nvzzrefvd";
    for (NSString *target in @[@"unordered",@"ordered",@"tasks"]) {
        NSString *source=[NSString stringWithFormat:@"Before neighbour.\n\n%@\n\nAfter neighbour.\n",body];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        f.editor.selectedRange=[source rangeOfString:body];
        [f.document convertSelectionToBlock:target];
        NSXMLDocument *DOM=[self DOM:f context:target];
        NSArray *items=[DOM nodesForXPath:@"//li" error:NULL];
        XCTAssertEqual(items.count,6u,@"%@",target);
        for (NSUInteger i=0;i<items.count;i++) {
            NSArray *strong=[items[i] nodesForXPath:@".//strong" error:NULL];
            XCTAssertEqual(strong.count,i<3?1u:0u,@"%@ item %lu",target,(unsigned long)i);
            XCTAssertFalse([((NSXMLNode *)items[i]).stringValue containsString:@"**"],@"%@",target);
        }
        NSArray *labels=@[@"**sdxerfe**",@"**ezrfvzer**",@"**trzevzer**",@"zvzre",@"rzev ze",@"vzzrefvd"];
        NSMutableArray *expected=[NSMutableArray array];
        for(NSUInteger i=0;i<labels.count;i++) {
            NSString *prefix=[target isEqual:@"ordered"]?[NSString stringWithFormat:@"%lu. ",(unsigned long)i+1]:[target isEqual:@"tasks"]?@"- [ ] ":@"- ";
            [expected addObject:[prefix stringByAppendingString:labels[i]]];
        }
        XCTAssertTrue([f.editor.string containsString:[expected componentsJoinedByString:@"\n"]],@"%@",target);
        NSString *converted=f.editor.string;
        [f.document.undoManager undo]; XCTAssertEqualObjects(f.editor.string,source);
        [f.document.undoManager redo]; XCTAssertEqualObjects(f.editor.string,converted);
    }
}

- (void)testMultilineStylesListMatrixPreservesAllCharactersAndUndo
{
    NSArray *markers=@[@"**",@"*",@"_",@"~~"];
    NSArray *tags=@[@"strong",@"em",@"u",@"del"];
    for(NSNumber *intra in @[@NO,@YES]) for(NSUInteger mask=1;mask<16;mask++) {
        [MPPreferences sharedInstance].extensionIntraEmphasis=intra.boolValue;
        NSMutableString *opening=[NSMutableString string],*closing=[NSMutableString string];
        for(NSUInteger bit=0;bit<4;bit++) if(mask&(1u<<bit)) [opening appendString:markers[bit]];
        for(NSUInteger bit=4;bit;bit--) if(mask&(1u<<(bit-1))) [closing appendString:markers[bit-1]];
        for(NSString *ending in @[@"\n",@"\r\n",@"\r"]) for(NSString *target in @[@"unordered",@"ordered",@"tasks"])
        for(NSNumber *preview in @[@NO,@YES]) {
            NSString *body=[NSString stringWithFormat:@"%@first%@second%@third%@%@plain",opening,ending,ending,closing,ending];
            NSString *source=[NSString stringWithFormat:@"Before neighbour.%@%@%@%@%@After neighbour.%@",ending,ending,body,ending,ending,ending];
            MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
            NSString *context=[NSString stringWithFormat:@"mask=%lu intra=%@ target=%@ preview=%@ ending=%@",(unsigned long)mask,intra,target,preview,[ending debugDescription]];
            NSXMLDocument *before=[self DOM:f context:context];
            if(preview.boolValue) XCTAssertTrue(([f applyContainer:target texts:@[@"first",@"second",@"third",@"plain"]]),@"%@",context);
            else {f.editor.selectedRange=[source rangeOfString:body];[f.document convertSelectionToBlock:target];}
            NSXMLDocument *DOM=[self DOM:f context:context];
            XCTAssertEqual([DOM nodesForXPath:@"//li" error:NULL].count,4u,@"%@",context);
            for(NSUInteger bit=0;bit<4;bit++) for(NSString *word in @[@"first",@"second",@"third",@"plain"]) {
                NSString *path=[NSString stringWithFormat:@"//%@[contains(.,'%@')]",tags[bit],word];
                XCTAssertEqual([DOM nodesForXPath:path error:NULL].count,[before nodesForXPath:path error:NULL].count,@"%@ %@",context,word);
            }
            XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:@"**"].count,[before.rootElement.stringValue componentsSeparatedByString:@"**"].count,@"%@ — literal markers remain literal",context);
            [self assertMarkdownSource:f.editor.string context:context];
            NSString *result=f.editor.string;
            [f.document.undoManager undo];XCTAssertEqualObjects(f.editor.string,source,@"%@",context);
            [f.document.undoManager redo];XCTAssertEqualObjects(f.editor.string,result,@"%@",context);
        }
    }
}

- (void)testPartialMultilineListConversionPreservesNeighboursLinksAndContainers
{
    for(NSString *container in @[@"none",@"callout-note",@"toggle"]) for(NSString *target in @[@"unordered",@"ordered",@"tasks"])
    for(NSString *selected in @[@"second",@"first\nsecond\nthird"]) {
        NSString *body=@"**first\nsecond\nthird**\nplain [link](https://example.org) `literal` \\*stars\\*\n";
        NSString *source=[self sourceForContainer:container body:body];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        f.editor.selectedRange=[source rangeOfString:selected];
        [f.document convertSelectionToBlock:target];
        NSXMLDocument *DOM=[self DOM:f context:target];
        XCTAssertEqual([DOM nodesForXPath:@"//li" error:NULL].count,[selected isEqual:@"second"]?1u:3u,@"%@ %@ %@ => %@",container,target,selected,f.editor.string);
        for(NSString *word in @[@"first",@"second",@"third"]) {
            NSString *path=[NSString stringWithFormat:@"//strong[contains(.,'%@')]",word];
            XCTAssertEqual([DOM nodesForXPath:path error:NULL].count,1u,@"%@ %@ %@",container,target,word);
        }
        XCTAssertTrue([f.editor.string containsString:@"[link](https://example.org) `literal` \\*stars\\*"]);
        XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"]);
        XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"]);
        NSString *result=f.editor.string;
        [f.document.undoManager undo];XCTAssertEqualObjects(f.editor.string,source);
        [f.document.undoManager redo];XCTAssertEqualObjects(f.editor.string,result);
    }
}

- (NSArray *)blocks { return @[@"paragraph",@"h1",@"h2",@"h3",@"h4",@"h5",@"h6",@"unordered",@"ordered",@"tasks",@"quote"]; }
- (NSArray *)containers { return @[@"none",@"callout-note",@"callout-tip",@"callout-warning",@"callout-important",@"callout-caution",@"toggle",@"toggle-h1",@"toggle-h2",@"toggle-h3",@"toggle-h4"]; }
- (NSArray *)styles { return @[@"bold",@"italic",@"underline",@"strike",@"link",@"code"]; }
- (NSString *)sourceForContainer:(NSString *)container body:(NSString *)body
{
    NSString *content=body;
    if (![container isEqual:@"none"]) {
        NSString *kind=[container hasPrefix:@"callout-"] ? [container substringFromIndex:8] : @"note";
        NSString *collapse=[container hasPrefix:@"toggle"] ? @" collapse=\"true\"" : @"";
        NSUInteger level=[container hasPrefix:@"toggle-h"] ? [[container substringFromIndex:8] integerValue] : 2;
        content=[NSString stringWithFormat:@"::: {.callout-%@%@}\n%@ Custom title\n%@:::\n",kind,collapse,[@"######" substringToIndex:level],body];
    }
    return [NSString stringWithFormat:@"Before neighbour.\n\n%@\nAfter neighbour.\n",content];
}
- (NSXMLDocument *)DOM:(MPScopeFixture *)f context:(NSString *)context
{
    NSString *HTML=[f.renderer HTMLForMarkdownSnapshot:f.editor.string];
    NSRegularExpression *inputs=[NSRegularExpression regularExpressionWithPattern:@"<input([^>]*)>" options:0 error:NULL];
    NSString *XML=[inputs stringByReplacingMatchesInString:HTML options:0 range:NSMakeRange(0,HTML.length) withTemplate:@"<input$1 />"];
    NSError *error=nil;
    NSXMLDocument *DOM=[[NSXMLDocument alloc] initWithXMLString:[NSString stringWithFormat:@"<root>%@</root>",XML] options:NSXMLNodeLoadExternalEntitiesNever error:&error];
    XCTAssertNotNil(DOM,@"%@ — %@; %@",context,error,HTML);
    return DOM;
}
- (void)assertMarkdownSource:(NSString *)source context:(NSString *)context
{
    // The controlled hyperlink may legitimately use Markdown's angle-delimited
    // destination: [label](<https://example.org/target>). Permit this exact URL
    // only in its destination position; authored HTML such as <u> stays forbidden.
    NSString *withoutKnownDestination=[source stringByReplacingOccurrencesOfString:@"](<https://example.org/target>)" withString:@"](https://example.org/target)"];
    XCTAssertFalse([withoutKnownDestination containsString:@"<"],@"%@ — no HTML in Markdown source: %@",context,source);
}
- (void)assertFixture:(MPScopeFixture *)f block:(NSString *)block container:(NSString *)container mask:(NSUInteger)mask context:(NSString *)context
{
    XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"],@"%@",context);
    XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"],@"%@",context);
    [self assertMarkdownSource:f.editor.string context:context];
    NSXMLDocument *DOM=[self DOM:f context:context];
    XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:@"Needle"].count,2u,@"%@ — one occurrence",context);
    NSString *path;
    if ([block hasPrefix:@"h"]) path=[NSString stringWithFormat:@"//%@",block];
    else path=@{@"paragraph":@"//p",@"unordered":@"//ul/li",@"ordered":@"//ol/li",@"tasks":@"//li[@class='task-list-item']",@"quote":@"//blockquote",@"code-block":@"//pre/code"}[block];
    NSArray *nodes=[DOM nodesForXPath:[path stringByAppendingString:@"[contains(.,'Needle')]"] error:NULL];
    XCTAssertEqual(nodes.count,1u,@"%@ — content type %@",context,block);
    NSArray *wrappers=[DOM nodesForXPath:@"//aside | //details" error:NULL];
    XCTAssertEqual(wrappers.count,[container isEqual:@"none"] ? 0u : 1u,@"%@ — one container category",context);
    if (![container isEqual:@"none"]) {
        NSXMLNode *wrapper=wrappers.firstObject;
        XCTAssertTrue([wrapper.stringValue containsString:@"Custom title"],@"%@ — preserve title",context);
        XCTAssertTrue([wrapper.stringValue containsString:@"Needle"],@"%@ — keep selected block inside container",context);
        if ([container hasPrefix:@"toggle"]) XCTAssertEqualObjects(wrapper.name,@"details",@"%@",context);
        else {
            XCTAssertEqualObjects(wrapper.name,@"aside",@"%@",context);
            NSString *kind=[container substringFromIndex:8];
            XCTAssertTrue([[(NSXMLElement *)wrapper attributeForName:@"class"].stringValue containsString:[@"mp-callout-" stringByAppendingString:kind]],@"%@",context);
        }
    }
    NSDictionary *tags=@{@"bold":@"strong",@"italic":@"em",@"underline":@"u",@"strike":@"del",@"link":@"a",@"code":@"code"};
    for (NSUInteger i=0;i<self.styles.count;i++) {
        NSString *style=self.styles[i];
        NSString *stylePath=[style isEqual:@"code"] ? @"//code[not(parent::pre)][contains(.,'Needle')]" : [NSString stringWithFormat:@"//%@[contains(.,'Needle')]",tags[style]];
        NSArray *styled=[DOM nodesForXPath:stylePath error:NULL];
        XCTAssertEqual(styled.count,(mask & (1u<<i)) ? 1u : 0u,@"%@ — style %@",context,style);
        if ((mask & (1u<<i)) && [style isEqual:@"link"]) XCTAssertEqualObjects([(NSXMLElement *)styled.firstObject attributeForName:@"href"].stringValue,@"https://example.org/target",@"%@",context);
    }
}
- (void)applyStyles:(NSUInteger)mask fixture:(MPScopeFixture *)f reverse:(BOOL)reverse context:(NSString *)context
{
    NSArray *actions=reverse ? self.styles.reverseObjectEnumerator.allObjects : self.styles;
    for (NSString *action in actions) {
        NSUInteger i=[self.styles indexOfObject:action];
        if (mask & (1u<<i)) XCTAssertTrue([f apply:action value:[action isEqual:@"link"] ? @"https://example.org/target" : nil text:@"Needle"],@"%@ — %@",context,action);
    }
}
- (void)testNormalTextClearsAll32RequestedStyleCombinations
{
    for(NSUInteger subset=0;subset<32;subset++) for(NSNumber *mode in @[@0,@1,@2]) {
        NSUInteger mask=(subset & 15)|((subset & 16)<<1);
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:@"# Lead Needle tail.\n"];
        [self applyStyles:mask fixture:f reverse:NO context:@"normal text"];
        NSRange word=[f.editor.string rangeOfString:@"Needle"];
        f.editor.selectedRange=mode.intValue==0 ? NSMakeRange(0,f.editor.string.length) :
            (mode.intValue==1 ? word : NSMakeRange(word.location+2,0));
        [f.document resetToNormalText:nil];
        XCTAssertEqualObjects(f.editor.string,@"Lead Needle tail.\n",@"subset=%lu mode=%@",(unsigned long)subset,mode);
    }
}
- (void)testEveryInlineSubsetComposesWithEveryContentBlockAndContainer
{
    // 64 inline subsets × 11 content types × 11 containers = 7,744 final states.
    // A custom existing title distinguishes body formatting from title replacement.
    NSUInteger exercised=0;
    for (NSString *container in self.containers) for (NSString *block in self.blocks) for (NSUInteger mask=0;mask<64;mask++) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"%@ / %@ / styles=%lu",container,block,(unsigned long)mask];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"Lead Needle tail.\n"]];
        XCTAssertTrue([f apply:@"block" value:block text:@"Needle"],@"%@",context);
        [self applyStyles:mask fixture:f reverse:NO context:context];
        [self assertFixture:f block:block container:container mask:mask context:context];
        exercised++;
    }
    XCTAssertEqual(exercised,7744u);
}
- (void)testEveryContentTransitionRetainsEveryContainerAndAllInlineStyles
{
    // 11 × 11 × 11 = 1,331 transitions; all six styles are cumulative.
    NSUInteger exercised=0;
    for (NSString *container in self.containers) for (NSString *from in self.blocks) for (NSString *to in self.blocks) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"%@: %@ → %@",container,from,to];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"Lead Needle tail.\n"]];
        XCTAssertTrue([f apply:@"block" value:from text:@"Needle"],@"%@",context);
        [self applyStyles:63 fixture:f reverse:YES context:context];
        XCTAssertTrue([f apply:@"block" value:to text:@"Needle"],@"%@",context);
        [self assertFixture:f block:to container:container mask:63 context:context];
        exercised++;
    }
    XCTAssertEqual(exercised,1331u);
}

- (void)testEveryToggleFromEveryInlineSubsetRetainsTheOtherStylesAndContainer
{
    // Link replaces a destination rather than toggling a style. Exercise each
    // of the five actual toggles from all 64 states, including linked states.
    NSUInteger exercised=0;
    for (NSString *container in self.containers) for (NSUInteger mask=0;mask<64;mask++)
        for (NSNumber *index in @[@0,@1,@2,@3,@5]) @autoreleasepool {
            NSString *action=self.styles[index.unsignedIntegerValue];
            NSString *context=[NSString stringWithFormat:@"%@ / mask=%lu / toggle %@",container,(unsigned long)mask,action];
            MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"# Lead Needle tail.\n"]];
            [self applyStyles:mask fixture:f reverse:NO context:context];
            XCTAssertTrue([f apply:action value:nil text:@"Needle"],@"%@",context);
            [self assertFixture:f block:@"h1" container:container mask:mask^(1u<<index.unsignedIntegerValue) context:context];
            // Reapplying must remove only the requested style or restore it;
            // another style, hyperlink, heading or envelope must survive.
            XCTAssertTrue([f apply:action value:nil text:@"Needle"],@"%@ — second toggle",context);
            [self assertFixture:f block:@"h1" container:container mask:mask context:context];
            exercised+=2;
        }
    XCTAssertEqual(exercised,7040u);
}
- (void)testEveryContainerReplacementAndRemovalRetainsAllContentTypesAndInlineStyles
{
    // 11 × 11 × 11 = 1,331 replacement/unwrap transitions.
    NSUInteger exercised=0;
    for (NSString *from in self.containers) for (NSString *to in self.containers) for (NSString *block in self.blocks) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"%@ → %@ / %@",from,to,block];
        // For an absent container, a separate paragraph must not be captured.
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:from body:@"Lead Needle tail.\n"]];
        XCTAssertTrue([f apply:@"block" value:block text:@"Needle"],@"%@",context);
        [self applyStyles:63 fixture:f reverse:NO context:context];
        XCTAssertTrue([f apply:@"block" value:[to isEqual:@"none"] ? @"no-container" : to text:@"Needle"],@"%@",context);
        NSXMLDocument *DOM=[self DOM:f context:context];
        NSArray *wrappers=[DOM nodesForXPath:@"//aside | //details" error:NULL];
        XCTAssertEqual(wrappers.count,[to isEqual:@"none"] ? 0u : 1u,@"%@ — replace instead of nest",context);
        XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:@"Needle"].count,2u,@"%@",context);
        if (![from isEqual:@"none"]) XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:@"Custom title"].count,2u,@"%@ — keep authored title",context);
        XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"],@"%@",context);
        XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"],@"%@",context);
        // Creating or replacing an envelope always retains the body type.
        {
            NSString *tag=[block hasPrefix:@"h"] ? block : @{@"paragraph":@"p",@"unordered":@"li",@"ordered":@"li",@"tasks":@"li",@"quote":@"blockquote"}[block];
            XCTAssertEqual(([DOM nodesForXPath:[NSString stringWithFormat:@"//%@[contains(.,'Needle')]",tag] error:NULL].count),1u,@"%@ — keep content type",context);
        }
        for (NSString *tag in @[@"strong",@"em",@"u",@"del",@"a",@"code"]) XCTAssertEqual(([DOM nodesForXPath:[NSString stringWithFormat:@"//%@[contains(.,'Needle')]",tag] error:NULL].count),1u,@"%@ — keep %@",context,tag);
        exercised++;
    }
    XCTAssertEqual(exercised,1331u);
}
- (void)permutations:(NSArray *)remaining prefix:(NSArray *)prefix into:(NSMutableArray *)result
{
    if (!remaining.count) { [result addObject:prefix]; return; }
    for (NSUInteger i=0;i<remaining.count;i++) {
        NSMutableArray *rest=remaining.mutableCopy; [rest removeObjectAtIndex:i];
        [self permutations:rest prefix:[prefix arrayByAddingObject:remaining[i]] into:result];
    }
}
- (void)testAllSixInlineStyleOrdersProduceTheSameSemanticComposition
{
    // 6! = 720 orders. Syntax marker ordering may vary; semantics may not.
    NSMutableArray *orders=[NSMutableArray array];
    [self permutations:self.styles prefix:@[] into:orders];
    XCTAssertEqual(orders.count,720u);
    for (NSArray *order in orders) @autoreleasepool {
        NSString *context=[order componentsJoinedByString:@" → "];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"callout-note" body:@"# Lead Needle tail.\n"]];
        for (NSString *action in order) XCTAssertTrue([f apply:action value:[action isEqual:@"link"] ? @"https://example.org/target" : nil text:@"Needle"],@"%@",context);
        [self assertFixture:f block:@"h1" container:@"callout-note" mask:63 context:context];
    }
}
- (void)testContainerOnPartialSelectionEncompassesWholeSoftWrappedParagraph
{
    for (NSString *container in self.containers) {
        if ([container isEqual:@"none"]) continue;
        NSString *paragraph=@"Lead Needle tail.\nSame paragraph continuation.\n";
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"none" body:paragraph]];
        XCTAssertTrue([f apply:@"block" value:container text:@"Needle"],@"%@",container);
        NSXMLDocument *DOM=[self DOM:f context:container];
        NSArray *containers=[DOM nodesForXPath:@"//aside | //details" error:NULL];
        XCTAssertEqual(containers.count,1u,@"%@",container);
        NSString *visible=[containers.firstObject stringValue];
        XCTAssertTrue([visible containsString:@"Lead Needle tail."],@"%@ — whole first line",container);
        XCTAssertTrue([visible containsString:@"Same paragraph continuation."],@"%@ — same paragraph",container);
        XCTAssertFalse([visible containsString:@"Before neighbour."],@"%@",container);
        XCTAssertFalse([visible containsString:@"After neighbour."],@"%@",container);
        [self assertMarkdownSource:f.editor.string context:container];
    }
}
- (void)testEveryContainerEncompassesAllSelectedContentBlocksAndNoNeighbours
{
    for (NSString *container in self.containers) {
        if ([container isEqual:@"none"]) continue;
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"none" body:@"First Needle tail.\n\nSecond chosen tail.\n"]];
        XCTAssertTrue(([f applyContainer:container texts:@[@"Needle",@"Second chosen"]]),@"%@",container);
        NSXMLDocument *DOM=[self DOM:f context:container];
        NSArray *wrappers=[DOM nodesForXPath:@"//aside | //details" error:NULL];
        XCTAssertEqual(wrappers.count,1u,@"%@",container);
        NSString *visible=[wrappers.firstObject stringValue];
        XCTAssertTrue([visible containsString:@"First Needle tail."],@"%@ — first complete paragraph",container);
        XCTAssertTrue([visible containsString:@"Second chosen tail."],@"%@ — last complete paragraph",container);
        XCTAssertFalse([visible containsString:@"Before neighbour."],@"%@",container);
        XCTAssertFalse([visible containsString:@"After neighbour."],@"%@",container);
    }
}
- (void)testChangingInnerContainerRetainsOuterContainerAndEveryUnselectedSibling
{
    for (NSString *container in self.containers) @autoreleasepool {
        NSString *source=@"Before neighbour.\n\n::: {.callout-warning}\n## Outer title\nOuter before.\n\n::: {.callout-note collapse=\"true\"}\n## Inner custom title\nLead Needle tail.\n:::\n\nOuter after.\n:::\n\nAfter neighbour.\n";
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        XCTAssertTrue([f apply:@"block" value:[container isEqual:@"none"] ? @"no-container" : container text:@"Needle"],@"%@",container);
        NSXMLDocument *DOM=[self DOM:f context:container];
        XCTAssertEqual([DOM nodesForXPath:@"//aside[contains(@class,'mp-callout-warning')]" error:NULL].count,[container isEqual:@"callout-warning"] ? 2u : 1u,@"%@ — outer envelope",container);
        XCTAssertEqual([DOM nodesForXPath:@"//aside | //details" error:NULL].count,[container isEqual:@"none"] ? 1u : 2u,@"%@ — only innermost changed",container);
        for (NSString *text in @[@"Outer title",@"Outer before.",@"Inner custom title",@"Lead Needle tail.",@"Outer after."]) XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:text].count,2u,@"%@ — preserve %@",container,text);
    }
}
- (void)testEveryFencedCodeContainerCanReturnToEveryContentTypeAndRejectsInlineChangesAtomically
{
    NSUInteger conversions=0,refusals=0;
    for (NSString *container in self.containers) {
        for (NSString *action in self.styles) @autoreleasepool {
            NSString *source=[self sourceForContainer:container body:@"```text\nLead Needle tail.\n```\n"];
            MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
            NSRange selected=[source rangeOfString:@"Needle"]; f.editor.selectedRange=selected;
            XCTAssertFalse([f apply:action value:[action isEqual:@"link"] ? @"https://example.org/target" : nil text:@"Needle"],@"%@ / %@",container,action);
            XCTAssertEqualObjects(f.editor.string,source,@"%@ / %@ — atomic refusal",container,action);
            XCTAssertTrue(NSEqualRanges(f.editor.selectedRange,selected),@"%@ / %@ — retain source selection",container,action);
            refusals++;
        }
        for (NSString *block in self.blocks) @autoreleasepool {
            MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"```text\nLead Needle tail.\n```\n"]];
            NSString *context=[NSString stringWithFormat:@"fenced code → %@ in %@",block,container];
            XCTAssertTrue([f apply:@"block" value:block text:@"Needle"],@"%@",context);
            [self assertFixture:f block:block container:container mask:0 context:context];
            XCTAssertFalse([f.editor.string containsString:@"```"],@"%@ — remove fences",context);
            conversions++;
        }
    }
    XCTAssertEqual(conversions,121u); XCTAssertEqual(refusals,66u);
}
- (void)testEveryContentTypeCanBecomeLiteralCodeInsideEveryContainerAndBackToParagraph
{
    NSUInteger exercised=0;
    for (NSString *container in self.containers) for (NSString *block in self.blocks) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"%@ / %@ → literal code → paragraph",container,block];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"Lead Needle tail.\n"]];
        XCTAssertTrue([f apply:@"block" value:block text:@"Needle"],@"%@",context);
        XCTAssertTrue([f apply:@"block" value:@"code-block" text:@"Needle"],@"%@",context);
        [self assertFixture:f block:@"code-block" container:container mask:0 context:context];
        NSXMLDocument *DOM=[self DOM:f context:context];
        // The renderer omits the source newline immediately before the closing fence.
        XCTAssertEqualObjects([[[DOM nodesForXPath:@"//pre/code" error:NULL] firstObject] stringValue],@"Lead Needle tail.",@"%@ — remove old structural prefix",context);
        XCTAssertTrue([f apply:@"block" value:@"paragraph" text:@"Needle"],@"%@",context);
        [self assertFixture:f block:@"paragraph" container:container mask:0 context:context];
        exercised++;
    }
    XCTAssertEqual(exercised,121u);
}
- (void)testMathBlockGenerationPreservesEveryContainerAndOutsideContent
{
    [MPPreferences sharedInstance].htmlMathJax=YES;
    // Math source is not a literal editable DOM run. Generation is covered;
    // inline formatting of the rendered equation is deliberately unavailable.
    NSUInteger exercised=0;
    for (NSString *container in self.containers) for (NSString *block in self.blocks) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"%@ / %@ → math",container,block];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"Lead Needle tail.\n"]];
        XCTAssertTrue([f apply:@"block" value:block text:@"Needle"],@"%@",context);
        XCTAssertTrue([f apply:@"block" value:@"math-block" text:@"Needle"],@"%@",context);
        XCTAssertEqual([f.editor.string componentsSeparatedByString:@"$$"].count,3u,@"%@ — one math block",context);
        XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"],@"%@",context);
        XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"],@"%@",context);
        XCTAssertEqual([f.editor.string componentsSeparatedByString:@"Needle"].count,2u,@"%@",context);
        if (![container isEqual:@"none"]) {
            XCTAssertEqual([f.editor.string componentsSeparatedByString:@":::"].count,3u,@"%@ — retain envelope",context);
            XCTAssertTrue([f.editor.string containsString:@"Custom title"],@"%@",context);
        }
        exercised++;
    }
    XCTAssertEqual(exercised,121u);
}
- (void)testEachScopeIsOneUndoableTransactionAndRedoRestoresItsResult
{
    NSArray *commands=@[@[@"bold",@""],@[@"block",@"h1"],@[@"block",@"callout-tip"],@[@"block",@"no-container"]];
    for (NSArray *command in commands) @autoreleasepool {
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"callout-note" body:@"Lead Needle tail.\n"]];
        NSString *before=f.editor.string.copy;
        NSUndoManager *undo=f.document.undoManager;
        XCTAssertNotNil(undo);
        undo.groupsByEvent=NO;
        [undo beginUndoGrouping];
        XCTAssertTrue([f apply:command[0] value:[command[1] length] ? command[1] : nil text:@"Needle"],@"%@",command);
        [undo endUndoGrouping];
        NSString *after=f.editor.string.copy;
        XCTAssertNotEqualObjects(after,before,@"%@",command);
        XCTAssertTrue(undo.canUndo,@"%@",command);
        [undo undo];
        XCTAssertEqualObjects(f.editor.string,before,@"%@ — one undo restores all affected source",command);
        XCTAssertTrue(undo.canRedo,@"%@",command);
        [undo redo];
        XCTAssertEqualObjects(f.editor.string,after,@"%@ — redo",command);
    }
}
- (void)testForgedAndStaleRequestsAreAtomicInsideEveryContainer
{
    for (NSString *container in self.containers) @autoreleasepool {
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"Lead Needle tail.\n"]];
        XCTAssertTrue([f apply:@"bold" value:nil text:@"Needle"],@"%@",container);
        NSString *source=f.editor.string.copy;
        NSRange selected=f.editor.selectedRange;
        // apply left the previous source mapping stale after its real transaction.
        NSDictionary *stale=@{@"token":f.document.previewEditToken,@"id":@0,@"start":@0,@"end":@6,@"text":@"Needle",@"action":@"block",@"value":@"h1"};
        XCTAssertFalse([f.document applyPreviewEditPayload:stale],@"%@ — stale mapping",container);
        NSMutableDictionary *forged=stale.mutableCopy; forged[@"token"]=@"forged";
        XCTAssertFalse([f.document applyPreviewEditPayload:forged],@"%@ — forged token",container);
        XCTAssertEqualObjects(f.editor.string,source,@"%@",container);
        XCTAssertTrue(NSEqualRanges(f.editor.selectedRange,selected),@"%@",container);
    }
}
- (void)applyNativeStyle:(NSString *)action fixture:(MPScopeFixture *)f
{
    if ([action isEqual:@"bold"]) [f.document toggleStrong:nil];
    else if ([action isEqual:@"italic"]) [f.document toggleEmphasis:nil];
    else if ([action isEqual:@"underline"]) [f.document toggleUnderline:nil];
    else if ([action isEqual:@"strike"]) [f.document toggleStrikethrough:nil];
    else if ([action isEqual:@"code"]) [f.document toggleInlineCode:nil];
    // URL entry itself opens a modal; use the same validated native adapter
    // after supplying the URL to keep business tests deterministic.
    else XCTAssertTrue([f.document formatSourceInlineAction:action value:@"https://example.org/target"]);
}
- (void)testNativeMixedBoldAndPlainSelectionAppliesBoldToAllSelectedCharacters
{
    MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"callout-note" body:@"# Lead plain **Needle** tail.\n"]];
    NSRange selected=[f.editor.string rangeOfString:@"plain **Needle** tail"];
    f.editor.selectedRange=selected;
    [f.document toggleStrong:nil];
    NSXMLDocument *DOM=[self DOM:f context:@"native mixed source selection"];
    NSArray *strong=[DOM nodesForXPath:@"//h1/strong[contains(.,'Needle')]" error:NULL];
    XCTAssertEqual(strong.count,1u);
    XCTAssertEqualObjects([strong.firstObject stringValue],@"plain Needle tail");
    XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"]);
    XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"]);
    XCTAssertEqual([DOM nodesForXPath:@"//aside[contains(@class,'mp-callout-note')]//h1" error:NULL].count,1u);
    [self assertMarkdownSource:f.editor.string context:@"native mixed source selection"];
}
- (void)testEveryNativeInlineSubsetPreservesHeadingContainerAndNeighbours
{
    NSUInteger exercised=0;
    for (NSString *container in self.containers) for (NSUInteger mask=0;mask<64;mask++) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"native source / %@ / styles=%lu",container,(unsigned long)mask];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"# Lead Needle tail.\n"]];
        for (NSUInteger i=0;i<self.styles.count;i++) if (mask & (1u<<i)) {
            f.editor.selectedRange=[f.editor.string rangeOfString:@"Needle"];
            [self applyNativeStyle:self.styles[i] fixture:f];
        }
        [self assertFixture:f block:@"h1" container:container mask:mask context:context];
        exercised++;
    }
    XCTAssertEqual(exercised,704u);
}
- (void)testNativeSelectionsIncludingMarkdownDelimitersKeepExistingStyles
{
    NSArray *cases=@[
        @[@"**Needle**",@"italic",@3],
        @[@"_Needle_",@"bold",@5],
        @[@"~~Needle~~",@"bold",@9],
        @[@"`Needle`",@"bold",@33],
        @[@"[Needle](https://example.org/target)",@"bold",@17]
    ];
    for (NSArray *scenario in cases) @autoreleasepool {
        NSString *body=[NSString stringWithFormat:@"# Lead %@ tail.\n",scenario[0]];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"callout-tip" body:body]];
        f.editor.selectedRange=[f.editor.string rangeOfString:scenario[0]];
        [self applyNativeStyle:scenario[1] fixture:f];
        [self assertFixture:f block:@"h1" container:@"callout-tip" mask:[scenario[2] unsignedIntegerValue] context:[scenario description]];
    }
}
- (void)testNativeFencedCodeRefusesEveryInlineOptionWithoutSourceSelectionOrUndoMutation
{
    for (NSString *container in self.containers) for (NSString *action in self.styles) @autoreleasepool {
        NSString *source=[self sourceForContainer:container body:@"```text\nLead Needle tail.\n```\n"];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        NSRange selected=[source rangeOfString:@"Needle"]; f.editor.selectedRange=selected;
        BOOL hadUndo=f.document.undoManager.canUndo;
        XCTAssertFalse([f.document formatSourceInlineAction:action value:[action isEqual:@"link"] ? @"https://example.org/target" : nil],@"%@ / %@",container,action);
        XCTAssertEqualObjects(f.editor.string,source,@"%@ / %@",container,action);
        XCTAssertTrue(NSEqualRanges(f.editor.selectedRange,selected),@"%@ / %@",container,action);
        XCTAssertEqual(f.document.undoManager.canUndo,hadUndo,@"%@ / %@ — no undo entry",container,action);
    }
}
- (void)testEveryNativeInlineOptionIsOneUndoableTransaction
{
    for (NSString *action in self.styles) @autoreleasepool {
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"toggle" body:@"# Lead Needle tail.\n"]];
        NSString *before=f.editor.string.copy;
        f.editor.selectedRange=[before rangeOfString:@"Needle"];
        NSUndoManager *undo=f.document.undoManager; undo.groupsByEvent=NO;
        [undo beginUndoGrouping];
        [self applyNativeStyle:action fixture:f];
        [undo endUndoGrouping];
        NSString *after=f.editor.string.copy;
        XCTAssertNotEqualObjects(after,before,@"%@",action);
        XCTAssertTrue(undo.canUndo,@"%@",action); [undo undo];
        XCTAssertEqualObjects(f.editor.string,before,@"%@ — undo",action);
        XCTAssertTrue(undo.canRedo,@"%@",action); [undo redo];
        XCTAssertEqualObjects(f.editor.string,after,@"%@ — redo",action);
    }
}
- (void)testNativeCaretHeadingAndQuoteConversionsRetainContainerAndConvertBackToParagraph
{
    for (NSString *container in self.containers) for (NSString *block in @[@"h1",@"quote"]) @autoreleasepool {
        NSString *context=[NSString stringWithFormat:@"native caret / %@ / %@",container,block];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:container body:@"Lead Needle tail.\n"]];
        NSRange word=[f.editor.string rangeOfString:@"Needle"];
        f.editor.selectedRange=NSMakeRange(word.location+2,0);
        if ([block isEqual:@"h1"]) [f.document convertToH1:nil];
        else [f.document toggleBlockquote:nil];
        [self assertFixture:f block:block container:container mask:0 context:context];
        word=[f.editor.string rangeOfString:@"Needle"];
        f.editor.selectedRange=NSMakeRange(word.location+2,0);
        [f.document convertToParagraph:nil];
        [self assertFixture:f block:@"paragraph" container:container mask:0 context:context];
    }
}
- (void)testNativeCaretContainerWrapsEntireSoftWrappedParagraph
{
    MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"none" body:@"Lead Needle tail.\nSame paragraph continuation.\n"]];
    NSRange word=[f.editor.string rangeOfString:@"Needle"];
    f.editor.selectedRange=NSMakeRange(word.location+2,0);
    [f.document convertSelectionToBlock:@"callout-note"];
    NSXMLDocument *DOM=[self DOM:f context:@"native caret paragraph enclosure"];
    NSArray *wrappers=[DOM nodesForXPath:@"//aside[contains(@class,'mp-callout-note')]" error:NULL];
    XCTAssertEqual(wrappers.count,1u);
    NSString *visible=[wrappers.firstObject stringValue];
    XCTAssertTrue([visible containsString:@"Lead Needle tail."]);
    XCTAssertTrue([visible containsString:@"Same paragraph continuation."]);
    XCTAssertFalse([visible containsString:@"Before neighbour."]);
    XCTAssertFalse([visible containsString:@"After neighbour."]);
}

- (void)testNestedRenderingMatrixForAllSupportedBlockFamilies
{
    NSMutableArray<NSArray<NSString *> *> *blocks=[NSMutableArray arrayWithArray:@[
        @[@"Needle paragraph.\nContinuation.\n",@"./p[contains(.,'Needle')]"],
        @[@"Title Needle\n============\n",@"./h1"],
        @[@"Title Needle\n------------\n",@"./h2"],
        @[@"> Needle\n> continuation\n",@"./blockquote/p"],
        @[@"> > > Needle\n",@"./blockquote/blockquote/blockquote/p"],
        @[@"- Needle\n    1. Child\n        - [x] Grandchild\n",@"./ul/li/ol/li/ul/li/input"],
        @[@"1. Needle\n    - Child\n        1. Grandchild\n",@"./ol/li/ul/li/ol/li"],
        @[@"- [ ] Needle\n    - [x] Child\n",@"./ul/li/ul/li/input"],
        @[@"> - Needle\n>     - Child\n",@"./blockquote/ul/li/ul/li"],
        @[@"- Needle\n\n    > Quote\n    > > Nested\n",@"./ul/li/blockquote/blockquote"],
        @[@"```jsx\nNeedle\n::: {.callout-tip}\n<aside>\n```\n",@".//pre/code[contains(.,'<aside>')]",@"Needle\n::: {.callout-tip}\n<aside>"],
        @[@"~~~~text\nNeedle\n```\n~~~~\n",@".//pre/code",@"Needle\n```"],
        @[@"    Needle indented code\n    second line\n",@".//pre/code",@"Needle indented code\nsecond line"],
        @[@"| Needle | Column |\n| --- | --- |\n| Cell | Value |\n",@"./table/tbody/tr/td"],
        @[@"Needle **bold** *italic* _underlined_ ~~strike~~ `inline` [link](https://example.org)\n",@"./p[strong and em and u and del and code and a]",@"Needle bold italic underlined strike inline link"],
        @[@"Needle ![image](image.png)\n",@"./p/img[@alt='image']"],
        @[@"Needle\n\n---\n\nAfter rule\n",@"./hr"],
        @[@"Needle  \nHard break\n",@"./p/br"],
        @[@"::: {.callout-tip}\n## Nested title\n\nNeedle\n:::\n",@"./aside/div[contains(@class,'mp-callout-body')]/p"],
        @[@"::: {.callout-note collapse=\"false\"}\n### Nested title\n\nNeedle\n:::\n",@"./details[@open]/div/p"],
        @[@"Needle\n\n- Child\n\n    ```text\n    message\n    ```\n",@"./ul/li//pre/code"],
        @[@"Needle[^note]\n",@"./p/sup/a"],
        @[@"Needle https://example.org\n",@"./p/a[@href='https://example.org']"],
        @[@"Needle ==highlight== x^2\n",@"./p[mark and sup]"],
        @[@"Needle **Été 👩🏽‍💻 é** \\*literal\\*\n",@"./p/strong",@"Été 👩🏽‍💻 é"],
        @[@"> ## Needle\n>\n> | Column | Value |\n> | --- | --- |\n> | Cell | Other |\n",@"./blockquote[ h2 and table ]"],
        @[@"Needle [reference][target]\n\n[target]: https://example.org/target\n",@"./p/a[@href='https://example.org/target']"],
        @[@"```mermaid\ngraph TD\nNeedle --> Child\n```\n",@".//pre/code[contains(@class,'language-mermaid')]"],
        @[@"```dot\ndigraph { Needle -> Child }\n```\n",@".//pre/code[contains(@class,'language-dot')]"],
        @[@"::: {.callout-warning}\n## Nested title\n\n- Child\n\n    ::: {.callout-tip}\n    ### Deep title\n\n    Needle\n    :::\n\n:::\n",@"./aside/div[contains(@class,'mp-callout-body')]/ul/li/aside/div[contains(@class,'mp-callout-body')]/p"]
    ]];
    for (NSUInteger level=1;level<=6;level++) [blocks addObject:@[[NSString stringWithFormat:@"%@ Needle\n",[@"######" substringToIndex:level]],[NSString stringWithFormat:@"./h%lu",(unsigned long)level]]];
    MPScopeFixture *oracle=[[MPScopeFixture alloc] initWithSource:@"Oracle"];
    MPRenderer *renderer=oracle.renderer;
    for (NSString *newline in @[@"\n",@"\r\n"]) for (NSString *marker in @[@"-",@"1.",@"- [ ]",@"- [x]"])
    for (NSString *indentUnit in @[@"    ",@"\t"]) for (NSUInteger depth=1;depth<=4;depth++) for (NSString *container in self.containers) {
        if ([container isEqualToString:@"none"]) continue;
        for (NSArray<NSString *> *block in blocks) @autoreleasepool {
            NSString *context=[NSString stringWithFormat:@"%@ / indent=%@ / depth=%lu / %@ / %@ / %@",marker,indentUnit,(unsigned long)depth,container,block[1],newline.length==2?@"CRLF":@"LF"];
            NSMutableString *source=[NSMutableString string];
            for (NSUInteger i=0;i<depth;i++) [source appendFormat:@"%@%@ Owner %lu\n",[@"" stringByPaddingToLength:i*indentUnit.length withString:indentUnit startingAtIndex:0],marker,(unsigned long)i];
            NSString *margin=[@"" stringByPaddingToLength:depth*indentUnit.length withString:indentUnit startingAtIndex:0];
            NSString *type=[container hasPrefix:@"callout-"] ? [container substringFromIndex:8] : @"note";
            NSString *collapse=[container hasPrefix:@"toggle"] ? @" collapse=\"true\"" : @"";
            [source appendFormat:@"\n%@::: {.callout-%@%@}\n%@## Outer title\n\n",margin,type,collapse,margin];
            for (NSString *line in [block[0] componentsSeparatedByString:@"\n"]) [source appendFormat:@"%@%@\n",margin,line];
            [source appendFormat:@"%@:::\n\n%@ After inside owner.\n\n%@%@ Neighbor\n",margin,margin,[@"" stringByPaddingToLength:(depth-1)*indentUnit.length withString:indentUnit startingAtIndex:0],marker];
            if ([block[0] containsString:@"[^note]"]) [source appendString:@"\n[^note]: Footnote text\n"];
            NSString *HTML=[renderer HTMLForMarkdownSnapshot:[source stringByReplacingOccurrencesOfString:@"\n" withString:newline]];
            NSRegularExpression *voidTags=[NSRegularExpression regularExpressionWithPattern:@"<(input|img|br|hr)([^>]*?)(?<!/)>" options:0 error:NULL];
            NSString *XML=[voidTags stringByReplacingMatchesInString:HTML options:0 range:NSMakeRange(0,HTML.length) withTemplate:@"<$1$2 />"];
            // HTML boolean attributes are valid browser markup; normalize
            // their syntax only for the strict XML structure assertions.
            NSRegularExpression *checked=[NSRegularExpression regularExpressionWithPattern:@"(<input\\b[^>]*?)\\schecked(?=\\s|/?>)" options:0 error:NULL];
            XML=[checked stringByReplacingMatchesInString:XML options:0 range:NSMakeRange(0,XML.length) withTemplate:@"$1 checked=\"checked\""];
            NSRegularExpression *open=[NSRegularExpression regularExpressionWithPattern:@"(<details\\b[^>]*?)\\sopen(?=\\s|>)" options:0 error:NULL];
            XML=[open stringByReplacingMatchesInString:XML options:0 range:NSMakeRange(0,XML.length) withTemplate:@"$1 open=\"open\""];
            XML=[XML stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@"&#160;"];
            NSError *parseError=nil;
            NSXMLDocument *DOM=[[NSXMLDocument alloc] initWithXMLString:[NSString stringWithFormat:@"<root>%@</root>",XML] options:NSXMLNodeLoadExternalEntitiesNever|NSXMLNodePromoteSignificantWhitespace error:&parseError];
            if (!DOM) { XCTFail(@"%@ produces well formed container HTML: %@; %@",context,parseError,HTML); return; }
            NSArray *outer=[DOM nodesForXPath:@"//*[self::aside or self::details][div[contains(@class,'mp-callout-title')]/h2='Outer title' or summary/h2='Outer title']" error:NULL];
            XCTAssertEqual(outer.count,1u,@"%@",context);
            NSXMLNode *wrapper=outer.firstObject;
            XCTAssertEqual([wrapper nodesForXPath:@"ancestor::li" error:NULL].count,depth,@"%@ preserves its list ownership",context);
            NSXMLNode *body=[[wrapper nodesForXPath:@"./div[contains(@class,'mp-callout-body')]" error:NULL] firstObject];
            NSArray *contentNodes=[body nodesForXPath:block[1] error:NULL];
            XCTAssertGreaterThan(contentNodes.count,0u,@"%@ preserves block structure",context);
            if (block.count>2) XCTAssertEqualObjects([contentNodes.firstObject stringValue],block[2],@"%@ preserves exact content bytes",context);
            XCTAssertTrue([body.stringValue containsString:@"Needle"],@"%@ preserves selected content",context);
            XCTAssertFalse([body.stringValue containsString:@"After inside owner."],@"%@ excludes subsequent prose",context);
            XCTAssertFalse([wrapper.stringValue containsString:@"Neighbor"],@"%@ excludes sibling items",context);
            XCTAssertFalse([DOM.rootElement.stringValue containsString:@"macdowncallout"],@"%@ consumes transport markers",context);
            if ([DOM nodesForXPath:@"//li[normalize-space(.)='Neighbor']" error:NULL].count!=1) { XCTFail(@"%@ preserves sibling: %@",context,HTML); return; }
        }
    }
}

- (void)testNativeNestedContainerPreservesMarginForEveryTypeAndLineEnding
{
    for (NSString *margin in @[@"        ",@"\t\t"]) for (NSString *newline in @[@"\n",@"\r\n"]) for (NSString *type in self.containers) {
        if ([type isEqualToString:@"none"]) continue;
        NSString *source=[[NSString stringWithFormat:@"- Parent\n    - Action\n\n%@Needle paragraph.\n\n    - Next\n",margin] stringByReplacingOccurrencesOfString:@"\n" withString:newline];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        f.editor.selectedRange=NSMakeRange([source rangeOfString:@"Needle"].location+2,0);
        [f.document convertSelectionToBlock:type];
        NSXMLDocument *DOM=[self DOM:f context:@"native nested container"];
        XCTAssertEqual([DOM nodesForXPath:@"/root/ul/li/ul/li/aside | /root/ul/li/ul/li/details" error:NULL].count,1u,@"%@",type);
        XCTAssertTrue([f.editor.string containsString:[[margin stringByAppendingString:@"::: {.callout-"] stringByAppendingString:[type hasPrefix:@"callout-"] ? [type substringFromIndex:8] : @"note"]]);
        XCTAssertEqualObjects([[[DOM nodesForXPath:@"/root/ul/li/ul/li" error:NULL] lastObject] stringValue],@"Next");
        [f.document.undoManager undo];
        XCTAssertEqualObjects(f.editor.string,source);
    }
}

- (void)testNestedSetextAndUntitledContainersKeepOneIndentedTitle
{
    for (NSString *margin in @[@"        ",@"\t\t"]) for (NSString *title in @[@"        Custom title\n        ------------\n",@"",@"        ## Custom title\n"]) {
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[NSString stringWithFormat:@"- Parent\n    - Action\n\n%@::: {.callout-note}\n%@\n        Needle paragraph.\n        :::\n\n    - Next\n",margin,title]];
        XCTAssertTrue([f apply:@"block" value:@"toggle-h4" text:@"Needle"]);
        NSXMLDocument *DOM=[self DOM:f context:@"nested title transformation"];
        XCTAssertEqual([DOM nodesForXPath:@"//li/details/summary/h4" error:NULL].count,1u);
        XCTAssertFalse([f.editor.string containsString:@"\n#### "]);
        XCTAssertEqual([DOM nodesForXPath:@"//details//h2" error:NULL].count,0u);
        if (title.length) XCTAssertEqualObjects([[[DOM nodesForXPath:@"//details/summary/h4" error:NULL] firstObject] stringValue],@"Custom title");
    }
}

- (void)testUntitledCalloutBecomesToggleHeadingWithLocalizedDefaultTitleAndPreservedBody
{
    MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:@"Before neighbour.\n\n::: {.callout-note}\nLead Needle tail.\n:::\n\nAfter neighbour.\n"];
    XCTAssertTrue([f apply:@"block" value:@"toggle-h1" text:@"Needle"]);
    NSXMLDocument *DOM=[self DOM:f context:@"untitled callout → toggle heading"];
    NSArray *titles=[DOM nodesForXPath:@"//details/summary/h1" error:NULL];
    XCTAssertEqual(titles.count,1u);
    NSString *expected=[NSBundle.mainBundle localizedStringForKey:@"PreviewToggleTitle" value:@"Prerequisites" table:nil];
    XCTAssertEqualObjects([titles.firstObject stringValue],expected);
    XCTAssertTrue([[[DOM nodesForXPath:@"//details/div[contains(@class,'mp-callout-body')]" error:NULL] firstObject].stringValue containsString:@"Lead Needle tail."]);
    XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"]);
    XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"]);
}
- (void)testRemovingAdjacentContainerKeepsThreeParagraphsForLFCRLFAndEOF
{
    for (NSString *newline in @[@"\n",@"\r\n"]) for (NSNumber *terminalNewline in @[@NO,@YES]) {
        NSString *source=[@[@"Before neighbour.",@"::: {.callout-note}",@"Lead Needle tail.",@":::",@"After neighbour."] componentsJoinedByString:newline];
        if (terminalNewline.boolValue) source=[source stringByAppendingString:newline];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        XCTAssertTrue([f apply:@"block" value:@"no-container" text:@"Needle"],@"newline=%@ EOF=%@",newline,terminalNewline);
        NSXMLDocument *DOM=[self DOM:f context:@"adjacent paragraphs after unwrap"];
        NSArray *paragraphs=[DOM nodesForXPath:@"//p" error:NULL];
        XCTAssertEqual(paragraphs.count,3u);
        NSArray *texts=@[@"Before neighbour.",@"Lead Needle tail.",@"After neighbour."];
        for (NSUInteger i=0;i<MIN(paragraphs.count,texts.count);i++) XCTAssertEqualObjects([paragraphs[i] stringValue],texts[i]);
        XCTAssertEqual([DOM nodesForXPath:@"//aside | //details" error:NULL].count,0u);
        XCTAssertFalse([f.editor.string containsString:@":::"]);
    }
}
- (void)testContainerSelectionInMiddleOfThreeHundredLineParagraphEncompassesWholeParagraph
{
    NSMutableString *body=[NSMutableString string];
    for (NSUInteger i=0;i<300;i++) [body appendFormat:@"Line %03lu %@ tail.\n",(unsigned long)i,i==150 ? @"Needle" : @"plain"];
    MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:[self sourceForContainer:@"none" body:body]];
    XCTAssertTrue([f apply:@"block" value:@"callout-caution" text:@"Needle"]);
    NSXMLDocument *DOM=[self DOM:f context:@"300 physical lines, one logical paragraph"];
    NSArray *wrappers=[DOM nodesForXPath:@"//aside[contains(@class,'mp-callout-caution')]" error:NULL];
    XCTAssertEqual(wrappers.count,1u);
    NSString *visible=[wrappers.firstObject stringValue];
    for (NSUInteger i=0;i<300;i++) {
        NSString *line=[NSString stringWithFormat:@"Line %03lu %@ tail.",(unsigned long)i,i==150 ? @"Needle" : @"plain"];
        XCTAssertTrue([visible containsString:line],@"missing paragraph line %lu",(unsigned long)i);
    }
    XCTAssertEqual([DOM nodesForXPath:@"//aside//p" error:NULL].count,1u);
    XCTAssertFalse([visible containsString:@"Before neighbour."]);
    XCTAssertFalse([visible containsString:@"After neighbour."]);
}
- (void)testNativeCaretInHeadingLookingCodeConvertsWholeFenceOrRefusesAtomically
{
    for (NSString *target in @[@"paragraph",@"h1",@"quote"]) {
        NSString *source=[self sourceForContainer:@"callout-note" body:@"```text\n# Needle\nparagraph content\n```\n"];
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        NSRange word=[source rangeOfString:@"Needle"];
        NSRange selected=NSMakeRange(word.location+2,0); f.editor.selectedRange=selected;
        [f.document convertSelectionToBlock:target];
        if ([f.editor.string isEqual:source]) {
            XCTAssertTrue(NSEqualRanges(f.editor.selectedRange,selected),@"%@ — atomic refusal",target);
            continue;
        }
        XCTAssertFalse([f.editor.string containsString:@"```"],@"%@ — whole fence converted",target);
        XCTAssertTrue([f.editor.string containsString:@"# Needle"],@"%@ — literal hash must survive; %@",target,f.editor.string);
        NSXMLDocument *DOM=[self DOM:f context:[NSString stringWithFormat:@"native fenced literal heading → %@",target]];
        XCTAssertTrue([DOM.rootElement.stringValue containsString:@"# Needle"],@"%@ — hash is visible content, not a heading marker",target);
        XCTAssertTrue([f.editor.string hasPrefix:@"Before neighbour.\n\n"],@"%@",target);
        XCTAssertTrue([f.editor.string hasSuffix:@"\nAfter neighbour.\n"],@"%@",target);
        XCTAssertTrue([f.editor.string containsString:@"paragraph content"],@"%@ — second code line",target);
        XCTAssertTrue([f.editor.string containsString:@"Custom title"],@"%@ — retain container title",target);
        XCTAssertEqual([f.editor.string componentsSeparatedByString:@":::"].count,3u,@"%@ — retain container envelope",target);
    }
}

- (void)testEveryInlineStyleAcrossSetextHeadingAndParagraphPreservesMetadataAndUndo
{
    NSDictionary *tags=@{@"bold":@"strong",@"italic":@"em",@"underline":@"u",@"strike":@"del",@"link":@"a",@"code":@"code"};
    for (NSString *action in self.styles) @autoreleasepool {
        NSString *source=@"Before neighbour.\n\nfirst\n====\n\nsecond\n\nAfter neighbour.\n";
        MPScopeFixture *f=[[MPScopeFixture alloc] initWithSource:source];
        f.renderer.rendererFlags=f.document.preferences.rendererFlags;
        [f.renderer parseMarkdown:source];
        NSRange first=[source rangeOfString:@"first"],second=[source rangeOfString:@"second"];
        f.document.previewEditRanges=@[
            @{@"location":@(first.location),@"length":@(first.length),@"text":@"first"},
            @{@"location":@(second.location),@"length":@(second.length),@"text":@"second"}
        ];
        f.document.previewEditSource=source; f.document.previewEditToken=f.renderer.checkboxBridgeToken;
        NSMutableDictionary *payload=[@{
            @"token":f.document.previewEditToken,@"id":@0,@"start":@0,@"end":@5,
            @"runs":@[@{@"id":@0,@"start":@0,@"end":@5},@{@"id":@1,@"start":@0,@"end":@6}],
            @"text":@"first\n\n\nsecond",@"action":action
        } mutableCopy];
        if ([action isEqual:@"link"]) payload[@"value"]=@"https://example.org/target";
        NSUndoManager *undo=f.document.undoManager; undo.groupsByEvent=NO;
        [undo beginUndoGrouping];
        XCTAssertTrue([f.document applyPreviewEditPayload:payload],@"%@ — proven cross-heading selection",action);
        [undo endUndoGrouping];
        NSString *after=f.editor.string.copy;
        XCTAssertTrue([after containsString:@"\n====\n"],@"%@ — Setext metadata intact",action);
        XCTAssertTrue([after hasPrefix:@"Before neighbour.\n\n"],@"%@",action);
        XCTAssertTrue([after hasSuffix:@"\nAfter neighbour.\n"],@"%@",action);
        [self assertMarkdownSource:after context:action];
        NSXMLDocument *DOM=[self DOM:f context:action];
        NSString *headingPath=[NSString stringWithFormat:@"//h1/%@[.='first']",tags[action]];
        NSString *paragraphPath=[NSString stringWithFormat:@"//p/%@[.='second']",tags[action]];
        XCTAssertEqual([DOM nodesForXPath:headingPath error:NULL].count,1u,@"%@ — heading text formatted",action);
        XCTAssertEqual([DOM nodesForXPath:paragraphPath error:NULL].count,1u,@"%@ — paragraph text formatted",action);
        XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:@"first"].count,2u,@"%@",action);
        XCTAssertEqual([DOM.rootElement.stringValue componentsSeparatedByString:@"second"].count,2u,@"%@",action);
        if ([action isEqual:@"link"]) for (NSXMLElement *link in [DOM nodesForXPath:@"//a" error:NULL]) XCTAssertEqualObjects([link attributeForName:@"href"].stringValue,@"https://example.org/target");
        XCTAssertTrue(undo.canUndo,@"%@",action); [undo undo];
        XCTAssertEqualObjects(f.editor.string,source,@"%@ — undo source",action);
        NSXMLDocument *restored=[self DOM:f context:action];
        XCTAssertEqualObjects([[[restored nodesForXPath:@"//h1" error:NULL] firstObject] stringValue],@"first",@"%@ — undo heading",action);
        XCTAssertEqual([restored nodesForXPath:@"//p[.='second']" error:NULL].count,1u,@"%@ — undo paragraph",action);
        XCTAssertEqual([restored nodesForXPath:@"//strong | //em | //u | //del | //a | //code" error:NULL].count,0u,@"%@ — undo removes style",action);
        XCTAssertTrue(undo.canRedo,@"%@",action); [undo redo];
        XCTAssertEqualObjects(f.editor.string,after,@"%@ — redo source",action);
        NSXMLDocument *redone=[self DOM:f context:action];
        XCTAssertEqual([redone nodesForXPath:headingPath error:NULL].count,1u,@"%@ — redo heading",action);
        XCTAssertEqual([redone nodesForXPath:paragraphPath error:NULL].count,1u,@"%@ — redo paragraph",action);
    }
}

@end
