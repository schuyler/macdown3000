//
//  PreviewViewController.m
//  MacDownQuickLook
//
//  Quick Look preview extension for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import "PreviewViewController.h"
#import <WebKit/WebKit.h>
#import "MPQuickLookRenderer.h"

@interface PreviewViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) MPQuickLookRenderer *renderer;
@property (nonatomic, copy) void (^pendingHandler)(NSError * _Nullable);
// Allows tests to substitute a synchronous WKWebView without starting the XPC web content process.
@property (nonatomic, copy) WKWebView *(^webViewFactory)(WKWebViewConfiguration *config, NSRect frame);
@end


@implementation PreviewViewController

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _renderer = [[MPQuickLookRenderer alloc] init];
    }
    return self;
}

- (void)loadView
{
    // Create web view configuration
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    if (@available(macOS 11.0, *)) {
        config.defaultWebpagePreferences.allowsContentJavaScript = NO;
    } else {
        config.preferences.javaScriptEnabled = NO;
    }

    // Create web view with a meaningful initial size
    NSRect frame = NSMakeRect(0, 0, 800, 600);
    WKWebView *(^factory)(WKWebViewConfiguration *, NSRect) = self.webViewFactory;
    self.webView = factory
        ? factory(config, frame)
        : [[WKWebView alloc] initWithFrame:frame configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Set as the view
    self.view = self.webView;
    self.preferredContentSize = frame.size;
}

#pragma mark - QLPreviewingController

- (void)preparePreviewOfFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError * _Nullable))handler
{
    // Render markdown to HTML
    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:url error:&error];

    if (error || !html) {
        if (handler) {
            handler(error ?: [NSError errorWithDomain:@"MPQuickLookError"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to render markdown"}]);
        }
        return;
    }

    // Store the handler. It will be called from -webView:didFinishNavigation:
    // instead of synchronously, so Quick Look snapshots a rendered page rather
    // than a blank WKWebView. Use nil baseURL because the extension sandbox
    // only grants access to the specific file URL, not its parent directory.
    self.pendingHandler = handler;
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)preparePreviewOfSearchableItemWithIdentifier:(NSString *)identifier
                                    queryString:(NSString *)queryString
                              completionHandler:(void (^)(NSError * _Nullable))handler
{
    // Not implementing searchable item preview
    if (handler) {
        handler([NSError errorWithDomain:@"MPQuickLookError"
                                    code:2
                                userInfo:@{NSLocalizedDescriptionKey: @"Searchable item preview not supported"}]);
    }
}

#pragma mark - WKNavigationDelegate

- (void)dealloc
{
    if (_pendingHandler) {
        void (^h)(NSError * _Nullable) = _pendingHandler;
        _pendingHandler = nil;
        h([NSError errorWithDomain:@"MPQuickLookError"
                              code:3
                          userInfo:@{NSLocalizedDescriptionKey: @"Preview was cancelled"}]);
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (self.pendingHandler) {
        void (^h)(NSError * _Nullable) = self.pendingHandler;
        self.pendingHandler = nil;
        h(nil);
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    if (self.pendingHandler) {
        void (^h)(NSError * _Nullable) = self.pendingHandler;
        self.pendingHandler = nil;
        h(error);
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    if (self.pendingHandler) {
        void (^h)(NSError * _Nullable) = self.pendingHandler;
        self.pendingHandler = nil;
        h(error);
    }
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;

    // `loadHTMLString:` may produce `about:` or `data:` navigations for the rendered
    // document and embedded data URI assets. The CSP still blocks script execution.
    if ([scheme isEqualToString:@"about"] || [scheme isEqualToString:@"data"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    decisionHandler(WKNavigationActionPolicyCancel);
}

@end
