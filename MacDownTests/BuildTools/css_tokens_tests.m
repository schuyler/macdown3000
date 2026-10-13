// Consume the generated standalone stylesheet with the actual bundled template
// and WebKit CSS engine. No remote assets or user preferences are used.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface CSSContract : NSObject <WKNavigationDelegate>
@property BOOL finished;
@property BOOL success;
@end

@implementation CSSContract
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    NSString *script = @"JSON.stringify({"
        "margin:getComputedStyle(document.querySelector('p')).marginBottom,"
        "padding:getComputedStyle(document.querySelector('pre')).paddingTop,"
        "background:getComputedStyle(document.querySelector('pre')).backgroundColor,"
        "border:getComputedStyle(document.querySelector('td')).borderTopStyle})";
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        NSDictionary *values = result ? [NSJSONSerialization JSONObjectWithData:
            [result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        self.success = !error && [values[@"margin"] doubleValue] > 0
            && [values[@"padding"] doubleValue] > 0
            && ![values[@"background"] isEqual:@"rgba(0, 0, 0, 0)"]
            && [values[@"border"] isEqual:@"solid"];
        fprintf(self.success ? stdout : stderr, "%s CSS computed consumer: %s\n",
            self.success ? "PASS" : "FAIL", [values.description UTF8String]);
        self.finished = YES;
    }];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    fprintf(stderr, "FAIL navigation: %s\n", error.description.UTF8String);
    self.finished = YES;
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 3) return 2;
        [NSApplication sharedApplication];
        NSError *error = nil;
        NSString *css = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:&error];
        NSString *html = [NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:&error];
        if (!css || !html) return 2;
        html = [html stringByReplacingOccurrencesOfString:@"{{#each styleTags }}\n{{{ this }}}\n{{/each }}"
                                              withString:[NSString stringWithFormat:@"<style>%@</style>", css]];
        html = [html stringByReplacingOccurrencesOfString:@"{{#each scriptTags }}\n{{{ this }}}\n{{/each }}" withString:@""];
        html = [html stringByReplacingOccurrencesOfString:@"{{{ titleTag }}}" withString:@""];
        html = [html stringByReplacingOccurrencesOfString:@"{{{ headTags }}}" withString:@""];
        html = [html stringByReplacingOccurrencesOfString:@"{{{ body }}}" withString:
            @"<p>first paragraph</p><p>second paragraph</p><pre><code>source</code></pre><table><tr><td>cell</td></tr></table>"];
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];
        CSSContract *contract = [CSSContract new];
        webView.navigationDelegate = contract;
        [webView loadHTMLString:html baseURL:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        while (!contract.finished && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:
                [NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!contract.finished) fprintf(stderr, "FAIL WebKit timeout\n");
        return contract.finished && contract.success ? 0 : 1;
    }
}
