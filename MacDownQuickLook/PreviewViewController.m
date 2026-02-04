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
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Set as the view
    self.view = self.webView;
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

    // Load HTML in web view
    [self.webView loadHTMLString:html baseURL:url.URLByDeletingLastPathComponent];

    // Signal completion
    if (handler) {
        handler(nil);
    }
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

@end
