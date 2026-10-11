// Consume the real Quick Look wrapper and bundled CSS in its WKWebView engine.
// Only preference/asset lookup is synthetic, avoiding account data.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "../../MacDownCore/MPQuickLookRenderer.h"
#import "../../MacDownCore/MPQuickLookPreferences.h"
#import <hoedown/document.h>
@interface FixtureRenderer : MPQuickLookRenderer
@property(copy) NSString *fixtureCSS;
@end
@implementation FixtureRenderer
- (NSString *)embeddedStyles { return [NSString stringWithFormat:@"<style>%@</style>",self.fixtureCSS]; }
@end
@interface FixturePreferences : MPQuickLookPreferences
@end
@implementation FixturePreferences
// These contracts exercise the original unwrapped theme geometry.
- (BOOL)wrapCodeBlocks { return NO; }
- (int)extensionFlags { return HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE; }
- (int)rendererFlags { return 0; }
@end
@interface QuickLookThemeContract : NSObject <WKNavigationDelegate>
@property BOOL finished;
@property BOOL success;
@end
@implementation QuickLookThemeContract
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [webView evaluateJavaScript:@"JSON.stringify({background:getComputedStyle(document.querySelector('pre')).backgroundColor,border:getComputedStyle(document.querySelector('td')).borderTopStyle})" completionHandler:^(id result, NSError *error) {
        NSDictionary *values = result ? [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        self.success = !error && [values[@"background"] isEqual:@"rgb(246, 248, 250)"] && [values[@"border"] isEqual:@"solid"];
        fprintf(self.success ? stdout : stderr,"%s Quick Look theme tokens consumer: %s\n",self.success ? "PASS" : "FAIL",[values.description UTF8String]);
        self.finished = YES;
    }];
}

@end
int main(int argc,const char *argv[])
{
    @autoreleasepool {
        if(argc != 2) return 2;
        [NSApplication sharedApplication];
        NSString *css = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        if(!css) return 2;
        FixtureRenderer *renderer = [FixtureRenderer new];
        renderer.fixtureCSS = css;
        [renderer setValue:[FixturePreferences new] forKey:@"preferences"];
        NSString *html = [renderer renderMarkdown:@"```\ncode\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |"];
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
        configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:configuration];
        QuickLookThemeContract *contract = [QuickLookThemeContract new]; webView.navigationDelegate = contract;
        [webView loadHTMLString:html baseURL:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while(!contract.finished && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return contract.finished && contract.success ? 0 : 1;
    }
}
