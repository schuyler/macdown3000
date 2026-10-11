// Measure the bundled styles in the application's real legacy WebKit engine.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        NSURL *directory = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        NSArray *files = [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil
                             options:0 error:NULL];
        NSUInteger styles = 0, failures = 0;
        for (NSURL *file in files) {
            if (![file.pathExtension isEqualToString:@"css"]) continue;
            NSString *css = [NSString stringWithContentsOfURL:file
                            encoding:NSUTF8StringEncoding error:NULL];
            if (!css) return 2;
            NSMutableString *html = [NSMutableString stringWithFormat:
                @"<html><head><style>%@</style></head><body>", css];
            for (NSUInteger level = 1; level <= 6; level++)
                [html appendFormat:@"<h%lu>Lorem ipsum dolor sit amet, "
                    "consectetur adipiscing elit, sed do eiusmod tempor "
                    "incididunt ut labore et dolore magna aliqua.</h%lu>",
                    (unsigned long)level, (unsigned long)level];
            [html appendString:@"</body></html>"];
            WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,400,600)];
            [web.mainFrame loadHTMLString:html baseURL:nil];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while ((!web.mainFrame.DOMDocument.body || web.isLoading) &&
                   deadline.timeIntervalSinceNow > 0)
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
            NSString *json = [[web.mainFrame.javaScriptContext evaluateScript:
                @"JSON.stringify(Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6'),"
                 "h=>{let s=getComputedStyle(h);return {tag:h.tagName,"
                 "font:parseFloat(s.fontSize),line:parseFloat(s.lineHeight),"
                 "height:h.getBoundingClientRect().height};}))"] toString];
            NSArray *metrics = [NSJSONSerialization JSONObjectWithData:
                [json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            if (metrics.count != 6) return 2;
            for (NSDictionary *metric in metrics) {
                double font = [metric[@"font"] doubleValue];
                double line = [metric[@"line"] doubleValue];
                BOOL readable = font > 0 && line >= font * 1.1;
                printf("%s %s %s font=%.2f line=%.2f\n",
                    readable ? "PASS" : "FAIL", file.lastPathComponent.UTF8String,
                    [metric[@"tag"] UTF8String], font, line);
                if (!readable) failures++;
            }
            styles++;
            [web close];
        }
        printf("styles=%lu failures=%lu\n", (unsigned long)styles,
               (unsigned long)failures);
        return styles == 48 && failures == 0 ? 0 : 1;
    }
}
