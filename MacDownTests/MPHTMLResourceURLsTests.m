//
//  MPHTMLResourceURLsTests.m
//  MacDownTests
//
//  Tests for MPLocalFilePathsInHTML and MPApplyCacheBusting.
//  Related to GitHub issue #110.
//

#import <XCTest/XCTest.h>
#import "MPHTMLResourceURLs.h"

@interface MPHTMLResourceURLsTests : XCTestCase
@property (strong) NSURL *baseURL;
@end

@implementation MPHTMLResourceURLsTests

- (void)setUp
{
    [super setUp];
    self.baseURL = [NSURL fileURLWithPath:@"/Users/test/docs/readme.md"];
}

#pragma mark - MPLocalFilePathsInHTML

- (void)testExtractsImgSrc
{
    NSString *html = @"<img src=\"photo.png\" alt=\"test\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/photo.png"]);
}

- (void)testExtractsImgSrcSubdirectory
{
    NSString *html = @"<img src=\"images/photo.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/images/photo.png"]);
}

- (void)testExtractsAbsoluteFilePath
{
    NSString *html = @"<img src=\"/tmp/image.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/tmp/image.png"]);
}

- (void)testExtractsVideoSrc
{
    NSString *html = @"<video src=\"clip.mp4\"></video>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/clip.mp4"]);
}

- (void)testExtractsAudioSrc
{
    NSString *html = @"<audio src=\"sound.mp3\"></audio>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/sound.mp3"]);
}

- (void)testExtractsSourceSrc
{
    NSString *html = @"<video><source src=\"clip.webm\"></video>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/clip.webm"]);
}

- (void)testExtractsIframeSrc
{
    NSString *html = @"<iframe src=\"embed.html\"></iframe>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/embed.html"]);
}

- (void)testExtractsLinkHref
{
    NSString *html = @"<link href=\"style.css\" rel=\"stylesheet\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/style.css"]);
}

- (void)testSkipsHttpUrls
{
    NSString *html = @"<img src=\"https://example.com/image.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testSkipsHttpUrls2
{
    NSString *html = @"<img src=\"http://example.com/image.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testSkipsDataUrls
{
    NSString *html = @"<img src=\"data:image/png;base64,abc123\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testSkipsAnchorHref
{
    NSString *html = @"<a href=\"other.md\">link</a>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testSkipsScriptSrc
{
    // We only watch resource elements, not scripts
    NSString *html = @"<script src=\"app.js\"></script>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testMultipleResources
{
    NSString *html = @"<img src=\"a.png\"><img src=\"b.jpg\"><video src=\"c.mp4\"></video>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 3u);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/a.png"]);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/b.jpg"]);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/c.mp4"]);
}

- (void)testDeduplicatesSameResource
{
    NSString *html = @"<img src=\"photo.png\"><img src=\"photo.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqual(paths.count, 1u);
}

- (void)testNilHtmlReturnsEmptySet
{
    NSSet *paths = MPLocalFilePathsInHTML(nil, self.baseURL);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testNilBaseURLReturnsEmptySet
{
    NSString *html = @"<img src=\"photo.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, nil);
    XCTAssertEqual(paths.count, 0u);
}

- (void)testSingleQuotedAttributes
{
    NSString *html = @"<img src='photo.png'>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/photo.png"]);
}

- (void)testFileProtocolUrl
{
    NSString *html = @"<img src=\"file:///tmp/photo.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/tmp/photo.png"]);
}

- (void)testDotDotRelativePath
{
    NSString *html = @"<img src=\"../images/photo.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/images/photo.png"]);
}

#pragma mark - MPApplyCacheBusting

- (void)testCacheBustAppendTimestamp
{
    NSString *html = @"<img src=\"photo.png\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/photo.png": @(1000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"photo.png?t=1000"]);
}

- (void)testCacheBustPreservesUnchangedUrls
{
    NSString *html = @"<img src=\"a.png\"><img src=\"b.png\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/a.png": @(1000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"a.png?t=1000"]);
    // b.png should be unchanged
    XCTAssertTrue([result containsString:@"src=\"b.png\""]);
}

- (void)testCacheBustReplacesExistingTimestamp
{
    NSString *html = @"<img src=\"photo.png?t=500\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/photo.png": @(1000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"photo.png?t=1000"]);
    XCTAssertFalse([result containsString:@"t=500"]);
}

- (void)testCacheBustNilTimestampsReturnsOriginal
{
    NSString *html = @"<img src=\"photo.png\">";
    NSString *result = MPApplyCacheBusting(html, nil, self.baseURL);
    XCTAssertEqualObjects(result, html);
}

- (void)testCacheBustEmptyTimestampsReturnsOriginal
{
    NSString *html = @"<img src=\"photo.png\">";
    NSString *result = MPApplyCacheBusting(html, @{}, self.baseURL);
    XCTAssertEqualObjects(result, html);
}

- (void)testCacheBustWorksWithSubdirectoryPaths
{
    NSString *html = @"<img src=\"images/photo.png\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/images/photo.png": @(2000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"images/photo.png?t=2000"]);
}

@end
