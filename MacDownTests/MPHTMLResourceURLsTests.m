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

- (void)testDirectoryBaseURL
{
    // Unsaved documents use a directory URL as base
    NSURL *dirURL = [NSURL fileURLWithPath:@"/Users/test/docs" isDirectory:YES];
    NSString *html = @"<img src=\"photo.png\">";
    NSSet *paths = MPLocalFilePathsInHTML(html, dirURL);
    XCTAssertTrue([paths containsObject:@"/Users/test/docs/photo.png"]);
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

#pragma mark - MPApplyCacheBusting on stylesheet <link> (Issue #318)

- (void)testCacheBustStampsRelativeStylesheetLink
{
    // The legacy WebView serves CSS from its cache keyed by file URL; a version
    // stamp on the <link> href is what forces a fresh load after an edit.
    NSString *html = @"<link rel=\"stylesheet\" href=\"style.css\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/style.css": @(1000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"style.css?t=1000"],
                  @"Stylesheet <link> href should receive a cache-busting stamp");
}

- (void)testCacheBustStampsAbsoluteFileURLStylesheetLink
{
    // The preview emits style/theme links as absolute file:// URLs.
    NSString *html =
        @"<link rel=\"stylesheet\" href=\"file:///Users/test/docs/GitHub2.css\">";
    NSDictionary *timestamps =
        @{@"/Users/test/docs/GitHub2.css": @(1750000000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"GitHub2.css?t=1750000000"],
                  @"Absolute file:// stylesheet link should be cache-busted");
}

- (void)testCacheBustReplacesExistingStylesheetTimestamp
{
    NSString *html = @"<link rel=\"stylesheet\" href=\"theme.css?t=500\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/theme.css": @(1000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"theme.css?t=1000"]);
    XCTAssertFalse([result containsString:@"t=500"],
                   @"Stale stylesheet timestamp should be replaced, not appended");
}

- (void)testCacheBustOnlyStampsTrackedStylesheet
{
    // Only the edited style is tracked; bundled CSS (no timestamp) is left alone.
    NSString *html = @"<link rel=\"stylesheet\" href=\"GitHub2.css\">"
                     @"<link rel=\"stylesheet\" href=\"print.css\">";
    NSDictionary *timestamps = @{@"/Users/test/docs/GitHub2.css": @(1000.0)};
    NSString *result = MPApplyCacheBusting(html, timestamps, self.baseURL);
    XCTAssertTrue([result containsString:@"GitHub2.css?t=1000"]);
    XCTAssertTrue([result containsString:@"href=\"print.css\""],
                  @"Untracked stylesheets must remain unchanged");
}

- (void)testEncodedResourcesResolveWithoutDoubleEncodingOrFragment {
    NSSet *paths = MPLocalFilePathsInHTML(@"<img src = 'my%20photo.png#frame'>", self.baseURL);
    XCTAssertEqualObjects(paths, [NSSet setWithObject:@"/Users/test/docs/my photo.png"]);
}

- (void)testOnlyLocalSchemesAndRealResourceAttributesAreWatched {
    NSString *html = @"<img src='HTTPS://host/image.png'><img src='//host/image.png'><img data-src='lazy.png'>";
    XCTAssertEqual(MPLocalFilePathsInHTML(html, self.baseURL).count, 0u);
}

- (void)testCacheBustingPreservesOtherQueryItemsAndSVGFragment {
    NSString *html = @"<img src='icons.svg?variant=dark&amp;t=old#logo'>";
    NSString *result = MPApplyCacheBusting(html, @{@"/Users/test/docs/icons.svg": @1234}, self.baseURL);
    XCTAssertTrue([result containsString:@"variant=dark&amp;t=1234#logo"]);
}

- (void)testCacheBustingPreservesEncodedQuotesAndAttributeBoundaries {
    for (NSString *quote in @[@"'", @"\""]) {
        for (NSString *tag in @[@"img", @"link"]) {
            NSString *attribute = [tag isEqualToString:@"img"] ? @"src" : @"href";
            NSString *html = [NSString stringWithFormat:
                @"<%@ %@=%@image.png?name=a&#39;b&amp;keep=c&amp;t=old#logo%@ alt='preserved'/>",
                tag, attribute, quote, quote];
            NSString *result = MPApplyCacheBusting(html,
                @{@"/Users/test/docs/image.png": @1234}, self.baseURL);
            NSError *error = nil;
            NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:result
                options:NSXMLNodeLoadExternalEntitiesNever error:&error];
            XCTAssertNotNil(document, @"%@", error);
            NSXMLElement *element = document.rootElement;
            XCTAssertEqualObjects([element attributeForName:attribute].stringValue,
                @"image.png?name=a'b&keep=c&t=1234#logo");
            XCTAssertEqualObjects([element attributeForName:@"alt"].stringValue, @"preserved");
            XCTAssertEqual(element.attributes.count, 2u);
        }
    }
}

- (void)testResourceURLMayContainTheOtherAttributeQuote {
    NSString *html = @"<img src=\"John's%20photo.png\" alt='preserved'/>";
    NSSet *paths = MPLocalFilePathsInHTML(html, self.baseURL);
    XCTAssertEqualObjects(paths, [NSSet setWithObject:@"/Users/test/docs/John's photo.png"]);
    NSString *result = MPApplyCacheBusting(html,
        @{@"/Users/test/docs/John's photo.png": @1234}, self.baseURL);
    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:result
        options:NSXMLNodeLoadExternalEntitiesNever error:&error];
    XCTAssertNotNil(document, @"%@", error);
    XCTAssertEqualObjects([document.rootElement attributeForName:@"src"].stringValue,
        @"John's%20photo.png?t=1234");
    XCTAssertEqualObjects([document.rootElement attributeForName:@"alt"].stringValue, @"preserved");
}

- (void)testEmptyResourceAttributesDoNotWatchOrRewriteTheBaseDirectory {
    NSString *html = @"<img src=''><link href=\"\"/>";
    XCTAssertEqual(MPLocalFilePathsInHTML(html, self.baseURL).count, 0u);
    XCTAssertEqualObjects(MPApplyCacheBusting(html,
        @{@"/Users/test/docs": @1234}, self.baseURL), html);
}

@end
