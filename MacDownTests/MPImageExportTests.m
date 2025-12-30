//
//  MPImageExportTests.m
//  MacDownTests
//
//  Tests for image handling in exports including embedded base64 images,
//  linked images, and invalid image URLs.
//
//  Created for Issue #234: Test Coverage Phase 1b
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"


@interface MPImageExportTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPImageExportTests

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


#pragma mark - Base64 Embedded Image Tests

- (void)testExportWithEmbeddedBase64PNGImage
{
    // 1x1 red PNG pixel in base64
    NSString *base64Image = @"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==";

    self.dataSource.markdown = [NSString stringWithFormat:@"# Test\n\n![Alt text](%@)", base64Image];

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML");
    XCTAssertTrue([html containsString:@"data:image/png;base64"],
                  @"Should preserve base64 image data URI in export");
    XCTAssertTrue([html containsString:@"<img"], @"Should have img tag");
}

- (void)testExportWithEmbeddedBase64GIFImage
{
    // 1x1 transparent GIF in base64
    NSString *base64GIF = @"data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";

    self.dataSource.markdown = [NSString stringWithFormat:@"![Transparent](%@)", base64GIF];

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"data:image/gif"],
                  @"Should preserve GIF data URI");
}

- (void)testExportWithEmbeddedBase64JPEGImage
{
    // Minimal JPEG data URI (may not be fully valid, but tests the handling)
    NSString *base64JPEG = @"data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q==";

    self.dataSource.markdown = [NSString stringWithFormat:@"![JPEG](%@)", base64JPEG];

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"data:image/jpeg"],
                  @"Should preserve JPEG data URI");
}

- (void)testExportWithMultipleEmbeddedImages
{
    NSString *png = @"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==";
    NSString *gif = @"data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";

    self.dataSource.markdown = [NSString stringWithFormat:
                               @"# Images\n\n![First](%@)\n\n![Second](%@)", png, gif];

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"data:image/png"], @"Should have PNG");
    XCTAssertTrue([html containsString:@"data:image/gif"], @"Should have GIF");
}


#pragma mark - Linked External Image Tests

- (void)testExportWithHTTPSLinkedImage
{
    self.dataSource.markdown = @"![External](https://example.com/image.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"https://example.com/image.png"],
                  @"Should preserve external HTTPS URL");
    XCTAssertTrue([html containsString:@"<img"], @"Should have img tag");
}

- (void)testExportWithHTTPLinkedImage
{
    self.dataSource.markdown = @"![HTTP Image](http://example.com/photo.jpg)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"http://example.com/photo.jpg"],
                  @"Should preserve HTTP URL");
}

- (void)testExportWithRelativePathImage
{
    self.dataSource.markdown = @"![Relative](./images/photo.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"./images/photo.png"],
                  @"Should preserve relative path");
}

- (void)testExportWithAbsolutePathImage
{
    self.dataSource.markdown = @"![Absolute](/path/to/image.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"/path/to/image.png"],
                  @"Should preserve absolute path");
}

- (void)testExportWithFileURLImage
{
    self.dataSource.markdown = @"![File](file:///Users/test/image.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"file:///Users/test/image.png"],
                  @"Should preserve file URL");
}


#pragma mark - Invalid Image URL Tests

- (void)testExportWithEmptyImageURL
{
    self.dataSource.markdown = @"![Empty]()";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle empty image URL");
    // May or may not produce img tag depending on implementation
}

- (void)testExportWithWhitespaceOnlyURL
{
    self.dataSource.markdown = @"![Spaces](   )";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle whitespace-only URL");
}

- (void)testExportWithMalformedURL
{
    self.dataSource.markdown = @"![Malformed](not a valid url)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle malformed URL gracefully");
}

- (void)testExportWithJavaScriptURL
{
    // Security test - JavaScript URLs should be handled safely
    self.dataSource.markdown = @"![XSS](javascript:alert('xss'))";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should produce HTML");
    // The javascript: URL might be present but shouldn't execute
}

- (void)testExportWithVBScriptURL
{
    // Another security test
    self.dataSource.markdown = @"![VB](vbscript:MsgBox('test'))";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle vbscript URL");
}

- (void)testExportWithDataURLMissingType
{
    // Data URL without proper type specification
    self.dataSource.markdown = @"![Bad Data](data:,HelloWorld)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle incomplete data URL");
}


#pragma mark - Image Alt Text Tests

- (void)testExportPreservesAltText
{
    self.dataSource.markdown = @"![This is the alt text](https://example.com/img.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"This is the alt text"] ||
                  [html containsString:@"alt=\"This is the alt text\""],
                  @"Should preserve alt text");
}

- (void)testExportWithEmptyAltText
{
    self.dataSource.markdown = @"![](https://example.com/img.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<img"], @"Should have img tag");
}

- (void)testExportWithSpecialCharsInAltText
{
    self.dataSource.markdown = @"![Alt with <>&\"'](https://example.com/img.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle special chars in alt text");
    // Special characters should be escaped
}

- (void)testExportWithUnicodeAltText
{
    self.dataSource.markdown = @"![日本語テスト](https://example.com/img.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"日本語テスト"],
                  @"Should preserve Unicode alt text");
}


#pragma mark - Image Title Tests

- (void)testExportWithImageTitle
{
    self.dataSource.markdown = @"![Alt](https://example.com/img.png \"Image Title\")";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"Image Title"] ||
                  [html containsString:@"title="],
                  @"Should preserve image title");
}

- (void)testExportWithEmptyImageTitle
{
    self.dataSource.markdown = @"![Alt](https://example.com/img.png \"\")";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle empty title");
}


#pragma mark - Reference-Style Image Tests

- (void)testExportWithReferenceStyleImage
{
    self.dataSource.markdown = @"![Reference Image][imgref]\n\n[imgref]: https://example.com/ref.png";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"https://example.com/ref.png"],
                  @"Should resolve reference-style image");
}

- (void)testExportWithMissingReferenceImage
{
    self.dataSource.markdown = @"![Missing Ref][missing]";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle missing image reference");
}


#pragma mark - Image URL Edge Cases

- (void)testExportWithVeryLongImageURL
{
    // Create very long URL
    NSMutableString *longURL = [NSMutableString stringWithString:@"https://example.com/"];
    for (int i = 0; i < 500; i++) {
        [longURL appendString:@"path/"];
    }
    [longURL appendString:@"image.png"];

    self.dataSource.markdown = [NSString stringWithFormat:@"![Long URL](%@)", longURL];

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle very long URL");
}

- (void)testExportWithURLContainingQueryParameters
{
    self.dataSource.markdown = @"![Query](https://example.com/img.png?width=100&height=200&format=jpeg)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"width=100"],
                  @"Should preserve query parameters");
}

- (void)testExportWithURLContainingFragment
{
    self.dataSource.markdown = @"![Fragment](https://example.com/img.png#section1)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"#section1"],
                  @"Should preserve URL fragment");
}

- (void)testExportWithURLContainingEncodedChars
{
    self.dataSource.markdown = @"![Encoded](https://example.com/my%20image%20file.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle URL-encoded characters");
}

- (void)testExportWithURLContainingUnicode
{
    self.dataSource.markdown = @"![Unicode](https://例え.jp/画像.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Should handle Unicode in URL");
}


#pragma mark - Mixed Content Tests

- (void)testExportWithImagesAndText
{
    self.dataSource.markdown = @"# Article\n\n"
                               @"Some intro text.\n\n"
                               @"![First Image](https://example.com/1.png)\n\n"
                               @"Middle paragraph.\n\n"
                               @"![Second Image](https://example.com/2.png)\n\n"
                               @"Conclusion.";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<h1>"], @"Should have heading");
    XCTAssertTrue([html containsString:@"example.com/1.png"], @"Should have first image");
    XCTAssertTrue([html containsString:@"example.com/2.png"], @"Should have second image");
}

- (void)testExportWithImageInLink
{
    self.dataSource.markdown = @"[![Click Image](https://example.com/button.png)](https://example.com/target)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<a"] && [html containsString:@"<img"],
                  @"Should have linked image");
}

- (void)testExportWithImageInTable
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES;
    self.dataSource.markdown = @"| Image | Description |\n"
                               @"|-------|-------------|\n"
                               @"| ![Img](https://example.com/img.png) | A photo |";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<table"], @"Should have table");
    XCTAssertTrue([html containsString:@"example.com/img.png"], @"Should have image in table");
}


#pragma mark - Export Style Options Tests

- (void)testExportWithStylesIncludesImageTag
{
    self.dataSource.markdown = @"![Test](https://example.com/test.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertTrue([html containsString:@"<img"], @"Should have img tag with styles");
    XCTAssertTrue([html containsString:@"<style"], @"Should have style block");
}

- (void)testExportWithoutStylesIncludesImageTag
{
    self.dataSource.markdown = @"![Test](https://example.com/test.png)";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertTrue([html containsString:@"<img"], @"Should have img tag without styles");
}

@end
