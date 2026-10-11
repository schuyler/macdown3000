#import <Foundation/Foundation.h>
#import <hoedown/html.h>
#import <hoedown/document.h>
#import "../../MacDown/Code/Document/MPPreviewInlineTransaction.h"

static NSString *Render(NSString *source)
{
    hoedown_renderer *renderer=hoedown_html_renderer_new(0,0);
    hoedown_document *document=hoedown_document_new(renderer,HOEDOWN_EXT_STRIKETHROUGH|HOEDOWN_EXT_UNDERLINE,128);
    hoedown_buffer *output=hoedown_buffer_new(64);
    NSData *data=[source dataUsingEncoding:NSUTF8StringEncoding];
    hoedown_document_render(document,output,data.bytes,data.length);
    NSString *html=[[NSString alloc] initWithBytes:output->data length:output->size encoding:NSUTF8StringEncoding];
    hoedown_buffer_free(output);hoedown_document_free(document);hoedown_html_renderer_free(renderer); return html;
}
static NSString *Escape(NSString *text)
{
    NSMutableString *result=[NSMutableString string];
    NSCharacterSet *markup=[NSCharacterSet characterSetWithCharactersInString:@"\\`*_{}[]()#+-.!|<>&~=^\"$"];
    for(NSUInteger i=0;i<text.length;i++) {unichar c=[text characterAtIndex:i];if([markup characterIsMember:c]) [result appendString:@"\\"];[result appendFormat:@"%C",c];}
    return result;
}
static NSUInteger failures;
static void Check(NSString *source, NSString *selection, NSString *action, NSString *expectedText, BOOL accepted)
{
    NSRange range=[source rangeOfString:selection];
    NSDictionary *change=MPPreviewInlineChange(source,range,action,[action isEqualToString:@"link"]?@"https://new.example/a(b)":nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
    BOOL success=(change!=nil)==accepted && (!accepted || [change[@"text"] isEqualToString:expectedText]);
    NSString *updated=change?[source stringByReplacingCharactersInRange:[change[@"range"] rangeValue] withString:change[@"replacement"]]:nil;
    fprintf(success?stdout:stderr,"%s %s / %s / %s => %s\n",success?"PASS":"FAIL",source.UTF8String,selection.UTF8String,action.UTF8String,updated.UTF8String ?: "refused");
    if(!success) failures++;
}
int main(void)
{
    @autoreleasepool {
        __block NSUInteger oversizedRenderCalls=0;
        NSString *oversized=[@"" stringByPaddingToLength:20001 withString:@"x" startingAtIndex:0];
        NSDictionary *oversizedChange=MPPreviewInlineChange(oversized,NSMakeRange(0,1),@"bold",nil,^NSString *(NSString *s){oversizedRenderCalls++;return Render(s);},^NSString *(NSString *s){return Escape(s);});
        BOOL bounded=!oversizedChange && oversizedRenderCalls==0;
        fprintf(bounded?stdout:stderr,"%s oversized paragraph refused before rendering\n",bounded?"PASS":"FAIL");
        if(!bounded) failures++;
        NSString *longSpaces=[@"" stringByPaddingToLength:12000 withString:@" " startingAtIndex:0];
        NSString *spacedText=[NSString stringWithFormat:@"a%@b",longSpaces];
        NSDictionary *spacedChange=MPPreviewInlineChange(spacedText,NSMakeRange(0,spacedText.length),@"bold",nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
        BOOL spacesPreserved=[spacedChange[@"replacement"] isEqualToString:[NSString stringWithFormat:@"**%@**",spacedText]] && [spacedChange[@"text"] isEqualToString:spacedText];
        fprintf(spacesPreserved?stdout:stderr,"%s long whitespace run preserves text and full selection formatting\n",spacesPreserved?"PASS":"FAIL");
        if(!spacesPreserved) failures++;
        NSString *legacyNeighbor=@"<span style=\"color:#175cd3\">outside</span> selected";
        NSDictionary *legacyNeighborChange=MPPreviewInlineChange(legacyNeighbor,[legacyNeighbor rangeOfString:@"selected"],@"bold",nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
        BOOL preserved=[legacyNeighborChange[@"replacement"] isEqualToString:@"<span style=\"color:#175cd3\">outside</span> **selected**"];
        fprintf(preserved?stdout:stderr,"%s neighboring legacy color remains unchanged\n",preserved?"PASS":"FAIL");
        if(!preserved) failures++;
        Check(@"<span style=\"color:#175cd3\">outside selected</span>",@"selected",@"clear",nil,NO);
        Check(@"<span style=\"color:#175cd3\">selected</span> outside",@"selected",@"clear",@"selected",YES);
        for(NSString *opening in MPPILegacyColorOpenings()) {
            NSString *source=[NSString stringWithFormat:@"%@neighbor</span> selected",opening];
            NSDictionary *change=MPPreviewInlineChange(source,[source rangeOfString:@"selected"],@"underline",nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
            NSString *expected=[NSString stringWithFormat:@"%@neighbor</span> _selected_",opening];
            BOOL intact=[change[@"replacement"] isEqualToString:expected];
            fprintf(intact?stdout:stderr,"%s legacy palette neighbor %s\n",intact?"PASS":"FAIL",opening.UTF8String);
            if(!intact) failures++;
        }
        Check(@"<span style=\"color:#175cd3\">selected</span> outside",@"selected",@"bold",nil,NO);
        Check(@"<span style=\"color:#175cd3\">selected</span> <span style=\"color:#067647\">neighbor</span>",@"selected",@"clear",@"selected",YES);
        Check(@"<span style=\"color:#175cd3\">outside <span style=\"color:#067647\">nested</span></span> selected",@"selected",@"bold",nil,NO);
        Check(@"[<span style=\"color:#175cd3\">colored</span> selected](https://example.com)",@"selected",@"bold",nil,NO);
        NSString *opaqueNested=@"[<span style=\"color:#175cd3\">outside <span style=\"color:#067647\">nested</span></span>](https://example.com) selected";
        NSDictionary *opaqueNestedChange=MPPreviewInlineChange(opaqueNested,[opaqueNested rangeOfString:@"selected"],@"bold",nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
        BOOL opaqueNestedPreserved=[opaqueNestedChange[@"replacement"] isEqualToString:[opaqueNested stringByReplacingOccurrencesOfString:@" selected" withString:@" **selected**"]];
        fprintf(opaqueNestedPreserved?stdout:stderr,"%s nested legacy colors in untouched link remain unchanged\n",opaqueNestedPreserved?"PASS":"FAIL");
        if(!opaqueNestedPreserved) failures++;
        Check(@"test **mot** selection",@"test **mot",@"bold",@"test mot",YES);
        Check(@"test **mot** selection",@"st **mo",@"bold",@"st mo",YES);
        Check(@"test **mot** selection",@"ot** selection",@"bold",@"ot selection",YES);
        Check(@"test **mot** selection",@"mot",@"bold",@"mot",YES);
        Check(@"test **mot** selection",@"o",@"bold",@"o",YES);
        Check(@"test **mot** selection",@"test **mot",@"italic",@"test mot",YES);
        Check(@"test **mot** selection",@"test **mot",@"underline",@"test mot",YES);
        Check(@"test **mot** selection",@"test **mot",@"strike",@"test mot",YES);
        Check(@"test **mot** selection",@"test **mot",@"clear",@"test mot",YES);
        Check(@"**a** **b**",@"a** **b",@"bold",@"a b",YES);
        Check(@"***_test_*** avec test",@"test",@"italic",@"test",YES);
        Check(@"<u>word</u> suffix",@"word",@"clear",@"word",YES);
        Check(@"## test **mot** selection\n\nother **bold**",@"test **mot",@"bold",@"test mot",YES);
        Check(@"test **mot** [link](https://example.com) `code`",@"test **mot",@"bold",@"test mot",YES);
        Check(@"[link](https://example.com) test **mot**",@"test **mot",@"bold",@"test mot",YES);
        Check(@"test **mot** selection",@"mot** sel",@"bold",@"mot sel",YES);
        Check(@"😀 **mot** test",@"😀 **mot",@"bold",@"😀 mot",YES);
        Check(@"café **mot** test",@"fé **mot",@"underline",@"fé mot",YES);
        Check(@"test **mot** selection",@"test **mot",@"code",@"test mot",YES);
        Check(@"test `mot` selection",@"mot",@"code",@"mot",YES);
        Check(@"test `mot` selection",@"o",@"code",@"o",YES);
        Check(@"test `mot` selection",@"test `mot",@"bold",@"test mot",YES);
        Check(@"first\n\nsecond",@"first\n\nsecond",@"bold",@"first\n\nsecond",YES);
        Check(@"first\nsecond",@"first\nsecond",@"bold",@"first\nsecond",YES);
        Check(@"**first**\n\nsecond",@"first**\n\nsecond",@"bold",@"first\n\nsecond",YES);
        Check(@"**first**\n\n**second**",@"first**\n\n**second",@"bold",@"first\n\nsecond",YES);
        Check(@"# first\n\n## second",@"first\n\n## second",@"bold",@"first\n\nsecond",YES);
        Check(@"- first\n- second",@"first\n- second",@"bold",@"first\nsecond",YES);
        Check(@"test **mot**\n\nplain **bold** tail",@"test **mot**\n\nplain **bold",@"italic",@"test mot\n\nplain bold",YES);
        Check(@"[link](https://example.com)",@"link",@"bold",@"link",YES);
        Check(@"[link](https://example.com)",@"in",@"bold",@"in",YES);
        Check(@"test [**mot**](https://example.com) selection",@"test [**mot",@"underline",@"test mot",YES);
        Check(@"test [**mot**](https://example.com) selection",@"test [**mot",@"bold",@"test mot",YES);
        Check(@"test [**mot**](https://example.com) selection",@"ot**](https://example.com) selection",@"bold",@"ot selection",YES);
        Check(@"test **mot** selection",@"test **mot",@"link",@"test mot",YES);
        Check(@"[link](https://old.example)",@"in",@"link",@"in",YES);
        Check(@"test [**mot**](https://old.example) selection",@"test [**mot",@"link",@"test mot",YES);
        Check(@"[link](https://old.example \"title\")",@"in",@"bold",@"in",YES);
        Check(@"Editable phrase é 日本語.",@"Editable",@"bold",@"Editable",YES);
        NSDictionary *punctuation=MPPreviewInlineChange(@"Editable phrase é 日本語.",NSMakeRange(0,8),@"bold",nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
        if(![punctuation[@"replacement"] isEqualToString:@"**Editable** phrase é 日本語."]) failures++;
        Check(@"**first\nsecond**",@"first\nsecond",@"bold",@"first\nsecond",YES);
        Check(@"**first\nsecond**",@"irst\nsecon",@"italic",@"irst\nsecon",YES);
        Check(@"plain **bold\ncontinued** tail",@"plain **bold\ncontinued",@"underline",@"plain bold\ncontinued",YES);
        Check(@"**first**\nsecond",@"first**\nsecond",@"bold",@"first\nsecond",YES);
        Check(@"first\n**second**",@"first\n**second",@"bold",@"first\nsecond",YES);
        Check(@"plain **bold\ncontinued** tail",@"plain **bold\ncontinued",@"clear",@"plain bold\ncontinued",YES);
        Check(@"`test` **`mot`** selection",@"test` **`mot",@"code",@"test mot",YES);
        NSString *mixedCode=@"`test` **`mot`** selection";
        NSDictionary *removedCode=MPPreviewInlineChange(mixedCode,[mixedCode rangeOfString:@"test` **`mot"],@"code",nil,^NSString *(NSString *s){return Render(s);},^NSString *(NSString *s){return Escape(s);});
        if(![removedCode[@"replacement"] isEqualToString:@"test **mot** selection"]) failures++;
        for (NSString *action in @[@"bold",@"italic",@"underline",@"strike",@"code",@"link"])
            Check(@"first\n====\n\nsecond\n",@"first\n====\n\nsecond",action,@"first\n\nsecond",YES);
        // A rule after an ATX heading is not Setext metadata and must not be
        // silently swallowed by a selection spanning the two blocks.
        Check(@"# first\n---\n\nsecond\n",@"first\n---\n\nsecond",@"bold",nil,NO);
        return failures?1:0;
    }
}
