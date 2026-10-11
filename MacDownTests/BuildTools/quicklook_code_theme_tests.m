// Actual shared Markdown callback consumed by script-disabled Quick Look WebKit.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "../../MacDownCore/MPQuickLookRenderer.h"
#import "../../MacDownCore/MPQuickLookPreferences.h"
#import <hoedown/document.h>
#import "../../MacDown/Code/Extension/hoedown_html_patch.h"
@interface CodeThemeRenderer : MPQuickLookRenderer
@property(copy) NSString *fixtureCSS;
@end
@implementation CodeThemeRenderer
- (NSString *)embeddedStyles { return [NSString stringWithFormat:@"<style>%@</style>",self.fixtureCSS]; }
@end
@interface CodeThemePreferences : MPQuickLookPreferences
@property int flags;
@end
@implementation CodeThemePreferences
// These contracts exercise the original unwrapped theme geometry.
- (BOOL)wrapCodeBlocks { return NO; }
- (int)extensionFlags { return HOEDOWN_EXT_FENCED_CODE; }
- (int)rendererFlags { return self.flags; }
@end
@interface CodeThemeContract : NSObject <WKNavigationDelegate>
@property BOOL finished;
@property BOOL success;
@property BOOL themed;
@property BOOL numbered;
@property(copy) NSString *plainBackground;
@property(copy) NSString *plainColor;
@end
@implementation CodeThemeContract
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [webView evaluateJavaScript:@"JSON.stringify(Array.prototype.map.call(document.querySelectorAll('pre'),function(p){var c=p.querySelector('code');return {pre:p.className,code:c.className,background:getComputedStyle(p).backgroundColor,color:getComputedStyle(c).color,information:p.getAttribute('data-information')};}))" completionHandler:^(id result,NSError *error){
        NSArray *rows=result?[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]:nil;
        self.success=!error&&rows.count==3;
        NSArray *languages=@[@"language-javascript",@"language-none",@"language-python"];
        for(NSUInteger i=0;i<MIN(rows.count,languages.count);i++) {
            NSDictionary *row=rows[i];
            NSArray *classes=[row[@"pre"] componentsSeparatedByString:@" "];
            self.success=self.success&&[classes containsObject:languages[i]]&&[row[@"code"] isEqual:languages[i]];
            self.success=self.success&&([classes containsObject:@"line-numbers"]==self.numbered);
            self.success=self.success&&[row[@"background"] isEqual:(self.themed?@"rgb(45, 45, 45)":self.plainBackground)];
            self.success=self.success&&[row[@"color"] isEqual:(self.themed?@"rgb(204, 204, 204)":self.plainColor)];
        }
        self.success=self.success&&[rows.lastObject[@"information"] isEqual:@"Custom"];
        fprintf(self.success?stdout:stderr,"%s shared PRE/Quick Look code theme: %s\n",self.success?"PASS":"FAIL",[result UTF8String]);
        self.finished=YES;
    }];
}
@end
int main(int argc,const char*argv[])
{
    @autoreleasepool {
        if(argc!=7)return 2;
        [NSApplication sharedApplication];
        NSString *style=[NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        NSString *theme=[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL];
        BOOL themed=atoi(argv[3]),numbered=atoi(argv[4]);if(!style||!theme)return 2;
        CodeThemeRenderer *renderer=[CodeThemeRenderer new];renderer.fixtureCSS=themed?[style stringByAppendingString:theme]:style;
        CodeThemePreferences *prefs=[CodeThemePreferences new];prefs.flags=HOEDOWN_HTML_BLOCKCODE_INFORMATION|(numbered?HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS:0);
        [renderer setValue:prefs forKey:@"preferences"];
        NSString *html=[renderer renderMarkdown:@"```javascript\nvar x=1;\n```\n\n```\nplain\n```\n\n```python:Custom\nprint(1)\n```"];
        WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=[WKWebsiteDataStore nonPersistentDataStore];config.defaultWebpagePreferences.allowsContentJavaScript=NO;
        WKWebView *view=[[WKWebView alloc]initWithFrame:NSMakeRect(0,0,800,600)configuration:config];
        CodeThemeContract *contract=[CodeThemeContract new];contract.themed=themed;contract.numbered=numbered;contract.plainBackground=@(argv[5]);contract.plainColor=@(argv[6]);view.navigationDelegate=contract;
        [view loadHTMLString:html baseURL:nil];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
        while(!contract.finished&&deadline.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return contract.finished&&contract.success?0:1;
    }
}
