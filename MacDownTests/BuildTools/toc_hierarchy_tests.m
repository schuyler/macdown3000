// Consume real patched Hoedown output using the preview's legacy WebKit DOM consumer.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <hoedown/html.h>
#import <hoedown/document.h>
#import "../../MacDown/Code/Extension/hoedown_html_patch.h"
@interface TOCContract : NSObject <WebFrameLoadDelegate>
@property BOOL finished;
@property BOOL success;
@end
@implementation TOCContract
- (void)webView:(WebView *)webView didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != webView.mainFrame) return;
    NSString *result = [webView stringByEvaluatingJavaScriptFromString:
        @"JSON.stringify({outside:document.querySelectorAll('body > li').length,links:document.querySelectorAll('ul.toc a').length,roots:document.querySelectorAll('ul.toc > li > a').length,resolved:Array.prototype.every.call(document.querySelectorAll('ul.toc a'),function(a){return !!document.getElementById(a.getAttribute('href').slice(1))}),nested:document.querySelectorAll('ul.toc > li > ul > li > a').length})"];
    NSDictionary *values = [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    self.success = [values[@"outside"] integerValue] == 0 && [values[@"links"] integerValue] == 4
        && [values[@"resolved"] boolValue] && [values[@"roots"] integerValue] == 2 && [values[@"nested"] integerValue] == 2;
    fprintf(self.success ? stdout : stderr,"%s TOC heading hierarchy consumer: %s\n",self.success ? "PASS" : "FAIL",result.UTF8String);
    self.finished = YES;
}
@end
static NSString *render(BOOL toc)
{
    const char *markdown = "### First\n\n#### Child\n\n# Higher\n\n## New child\n";
    hoedown_renderer *renderer = toc ? hoedown_html_toc_renderer_new(6) : hoedown_html_renderer_new(0,0);
    renderer->header = toc ? hoedown_patch_render_toc_header : hoedown_patch_render_header;
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
        (void)argc; (void)argv;
        [NSApplication sharedApplication];
        NSString *html = [NSString stringWithFormat:@"<html><body>%@%@</body></html>",render(YES),render(NO)];
        WebView *webView = [[WebView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
        TOCContract *contract = [TOCContract new]; webView.frameLoadDelegate = contract;
        [webView.mainFrame loadHTMLString:html baseURL:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while(!contract.finished && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return contract.finished && contract.success ? 0 : 1;
    }
}
