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

    // Create web view
    NSRect frame = NSMakeRect(0, 0, 800, 600);
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
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

    // Load HTML in web view. Use nil baseURL: the extension sandbox only grants access
    // to the specific file URL, not its parent directory. The completion handler is
    // deferred until didFinishNavigation: so Quick Look snapshots a rendered page.
    self.pendingHandler = handler;
    [self.webView loadHTMLString:html baseURL:nil];
}

#pragma mark - WKNavigationDelegate

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

#pragma mark - QLPreviewingController (searchable items)

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

@end
