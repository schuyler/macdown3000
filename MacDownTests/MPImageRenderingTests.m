//
//  MPImageRenderingTests.m
//  MacDownTests
//
//  Regression coverage for GitHub issue #341: "Loss of all image rendering
//  in preview." Images that container-render (correct size/border) but never
//  load their bits are the symptom of something in the render pipeline
//  dropping or blocking the image source.
//
//  Nothing in MacDown's current code blocks image subresources, and these
//  tests are tripwires that keep it that way: they pin the end-to-end image
//  contract of the preview HTML so a future change (e.g. tightening the
//  Content-Security-Policy the way preview-hardening work did, or rewriting
//  the resource-load path) fails loudly in CI instead of silently breaking
//  image rendering for every source at once.
//
//  These are pipeline-level tests; they cannot catch a failure that lives in
//  the deprecated legacy WebView itself (the likely real-world trigger of
//  #341). See the PR's manual testing plan for verifying the live WebView.
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import <cmark-gfm/mdmark.h>


@interface MPImageRenderingTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPImageRenderingTests

- (void)setUp
{
    [super setUp];

    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];

    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self.dataSource;
    self.renderer.delegate = self.delegate;
}

- (void)tearDown
{
    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    [super tearDown];
}

// Renders the given markdown through the live preview path and returns the
// full preview HTML (including head/CSP) captured by the mock delegate.
- (NSString *)previewHTMLForMarkdown:(NSString *)markdown
{
    self.dataSource.markdown = markdown;
    [self.renderer parseMarkdown:markdown];
    [self.renderer render];
    return self.delegate.lastHTML;
}


#pragma mark - Image src is preserved end-to-end across all sources

- (void)testPreviewPreservesHTTPSImageSource
{
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](https://example.com/photo.png)"];

    XCTAssertNotNil(html, @"Preview render should produce HTML");
    XCTAssertTrue([html containsString:@"<img"],
                  @"Preview HTML should contain an image element");
    XCTAssertTrue([html containsString:@"https://example.com/photo.png"],
                  @"Preview HTML must preserve the https image source");
}

- (void)testPreviewPreservesHTTPImageSource
{
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](http://example.com/photo.png)"];

    XCTAssertTrue([html containsString:@"http://example.com/photo.png"],
                  @"Preview HTML must preserve the http image source");
}

- (void)testPreviewPreservesLocalFileImageSource
{
    // Relative local path, as written for a sidecar image next to the document.
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](images/photo.png)"];

    XCTAssertTrue([html containsString:@"images/photo.png"],
                  @"Preview HTML must preserve the local file image source");
}

- (void)testPreviewPreservesAbsoluteFileURLImageSource
{
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](file:///tmp/photo.png)"];

    XCTAssertTrue([html containsString:@"file:///tmp/photo.png"],
                  @"Preview HTML must preserve the file:// image source");
}

- (void)testPreviewPreservesDataURIImageSource
{
    // A 1x1 transparent PNG as a data URI.
    NSString *dataURI = @"data:image/png;base64,"
        @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
    NSString *markdown =
        [NSString stringWithFormat:@"![alt](%@)", dataURI];

    NSString *html = [self previewHTMLForMarkdown:markdown];

    XCTAssertTrue([html containsString:@"data:image/png;base64,"],
                  @"Preview HTML must preserve the data URI image source");
}


#pragma mark - CSP must keep every image scheme allowed (#341 tripwire)

- (void)testPreviewCSPAllowsAllImageSchemes
{
    NSString *html = [self previewHTMLForMarkdown:@"# Heading"];

    XCTAssertTrue([html containsString:@"Content-Security-Policy"],
                  @"Preview HTML should include a CSP meta tag");
    // Issue #341: if any of these schemes is dropped from img-src, images
    // from that source silently stop rendering even though the <img>
    // container still lays out. Keep all four allowed.
    XCTAssertTrue([html containsString:@"img-src data: file: http: https:"],
                  @"CSP img-src must allow data:, file:, http:, and https: images");
}

- (void)testPreviewCSPAllowsAllMediaSchemes
{
    NSString *html = [self previewHTMLForMarkdown:@"# Heading"];

    // The same loss-of-rendering risk applies to <video>/<audio>/<source>.
    XCTAssertTrue([html containsString:@"media-src data: file: http: https:"],
                  @"CSP media-src must allow data:, file:, http:, and https: media");
}

@end
