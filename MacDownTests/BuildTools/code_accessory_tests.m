// Consume real patched Hoedown output using the preview's legacy WebKit CSS engine.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <hoedown/html.h>
#import <hoedown/document.h>
#import "../../MacDown/Code/Extension/hoedown_html_patch.h"
@interface AccessoryContract : NSObject <WebFrameLoadDelegate>
@property BOOL finished;
@property BOOL success;
@end
@implementation AccessoryContract
- (void)webView:(WebView *)webView didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != webView.mainFrame) return;
    NSString *result = [webView stringByEvaluatingJavaScriptFromString:
        @"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('pre'),function(p){return [getComputedStyle(p).position,getComputedStyle(p,'::before').content]}))"];
    NSArray *values = [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    self.success = values.count == 3 && [values[0][0] isEqual:@"relative"] && [values[1][0] isEqual:@"relative"]
        && [values[0][1] isEqual:@"\"Custom\""] && [values[1][1] isEqual:@"\"Custom\""]
        && ([values[2][1] isEqual:@"none"] || [values[2][1] isEqual:@"normal"]);
    fprintf(self.success ? stdout : stderr,"%s custom code accessory consumer: %s\n",self.success ? "PASS" : "FAIL",result.UTF8String);
    self.finished = YES;
}
@end
static NSString *render(int flags)
{
    const char *markdown = "```python:Custom\nprint(1)\n```\n";
    hoedown_renderer *renderer = hoedown_html_renderer_new(flags,0);
    renderer->blockcode = hoedown_patch_render_blockcode;
    hoedown_document *document = hoedown_document_new(renderer,HOEDOWN_EXT_FENCED_CODE,128);
    hoedown_buffer *output = hoedown_buffer_new(64);
    hoedown_document_render(document,output,(const uint8_t *)markdown,strlen(markdown));
    NSString *html = [[NSString alloc] initWithBytes:output->data length:output->size encoding:NSUTF8StringEncoding];
    hoedown_buffer_free(output); hoedown_document_free(document); hoedown_html_renderer_free(renderer);
    return html;
}
int main(int argc,const char *argv[])
{
    @autoreleasepool {
        if(argc != 2) return 2;
        [NSApplication sharedApplication];
        NSString *css = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        if(!css) return 2;
        NSString *html = [NSString stringWithFormat:@"<html><head><style>%@</style></head><body>%@%@%@</body></html>",css,
            render(HOEDOWN_HTML_BLOCKCODE_INFORMATION),render(HOEDOWN_HTML_BLOCKCODE_INFORMATION|HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS),render(0)];
        WebView *webView = [[WebView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
        AccessoryContract *contract = [AccessoryContract new]; webView.frameLoadDelegate = contract;
        [webView.mainFrame loadHTMLString:html baseURL:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while(!contract.finished && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return contract.finished && contract.success ? 0 : 1;
    }
}
