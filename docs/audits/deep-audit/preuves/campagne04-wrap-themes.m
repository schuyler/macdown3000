#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "/Users/zydon/Sites/MacDown/MacDownCore/MPReaderStyles.h"
int main(int argc,const char **argv) {@autoreleasepool {
 [NSApplication sharedApplication];
 NSString *root=@"/Users/zydon/Sites/MacDown/MacDown/Resources";
 NSString *styles=[root stringByAppendingPathComponent:@"Styles"];
 NSString *themes=[root stringByAppendingPathComponent:@"CommunityPrismThemes"];
 NSString *base=[NSString stringWithContentsOfFile:[styles stringByAppendingPathComponent:@"GitHub2.css"] encoding:NSUTF8StringEncoding error:NULL];
 NSString *cb=[NSString stringWithContentsOfFile:[themes stringByAppendingPathComponent:@"prism-cb.css"] encoding:NSUTF8StringEncoding error:NULL];
 NSUInteger count=0,failures=0;
 for(NSString *directory in @[themes,styles]) for(NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL]) {
 if(![file.pathExtension isEqual:@"css"])continue;
 NSString *css=[NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:NULL];
 if(!css)return 2;
 NSString *code=[@"x" stringByPaddingToLength:500 withString:@"x" startingAtIndex:0];
 NSString *html=[NSString stringWithFormat:@"<html data-color-mode='light' data-light-theme='light'><head>%@<style>%@</style><style>%@</style></head><body><pre class='language-bash'><code class='language-bash'>%@</code></pre></body></html>",MPCodeWrappingStyleTag(),[directory isEqual:styles]?css:base,[directory isEqual:styles]?cb:css,code];
 WebView *web=[[WebView alloc]initWithFrame:NSMakeRect(0,0,240,300)];
 [web.mainFrame loadHTMLString:html baseURL:nil];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while((!web.mainFrame.DOMDocument.body || web.isLoading)&&deadline.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 NSString *result=[web stringByEvaluatingJavaScriptFromString:@"JSON.stringify({pre:document.querySelector('pre').scrollWidth-document.querySelector('pre').clientWidth,body:document.body.scrollWidth-document.body.clientWidth,text:document.querySelector('code').textContent.length,height:document.querySelector('code').getBoundingClientRect().height})"];
 NSDictionary *metrics=[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
 BOOL okay=metrics && [metrics[@"text"]intValue]==500 && [metrics[@"pre"]doubleValue]<=1 && [metrics[@"body"]doubleValue]<=1;
 printf("%s %s %s\n",okay?"PASS":"FAIL",file.UTF8String,result.UTF8String);if(!okay)failures++;count++;[web close];
 }
 printf("cases=%lu failures=%lu\n",count,failures);return failures?1:0;
}}
