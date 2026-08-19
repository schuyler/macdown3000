//
//  MPMathJaxLocalFontsTests.m
//  MacDown 3000
//
//  MathJax's HTML-CSS output jax renders in vector web fonts, but when those
//  fonts are fetched from the CDN at render time and the fetch times out it
//  falls back to bitmap image fonts that pixelate on zoom. The app bundles the
//  TeX woff fonts and the resource-load delegate serves them (and the MathJax
//  loader) from the bundle. These tests pin that redirect and the bundled set.
//

#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "MPDocument.h"

// The WebResourceLoadDelegate method under test (implemented in MPDocument.m).
@interface MPDocument (LocalFontsTesting)
- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource;
@end

// Must match kMPMathJaxCDN's origin and version directory in MPRenderer.m.
static NSString * const kMPTestCDNBase =
    @"https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/";


@interface MPMathJaxLocalFontsTests : XCTestCase
@property (strong) MPDocument *document;
@end


@implementation MPMathJaxLocalFontsTests

- (void)setUp
{
    [super setUp];
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    self.document = nil;
    [super tearDown];
}

/// Runs a CDN request (base + suffix) through the real delegate and returns the
/// URL it decides to load.
- (NSURL *)resolvedURLForSuffix:(NSString *)suffix
{
    NSURL *url = [NSURL URLWithString:
                  [kMPTestCDNBase stringByAppendingString:suffix]];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLRequest *out = [self.document webView:nil resource:nil
                               willSendRequest:req redirectResponse:nil
                                fromDataSource:nil];
    return out.URL;
}

- (void)testWoffFontRedirectsToBundleWithoutQuery
{
    NSURL *result = [self resolvedURLForSuffix:
        @"fonts/HTML-CSS/TeX/woff/MathJax_Main-Regular.woff?V=2.7.3"];

    XCTAssertTrue(result.isFileURL,
                  @"A bundled woff font should be served from the bundle");
    XCTAssertNil(result.query,
                 @"The local font URL must carry no query, or file: may not "
                 @"resolve and the load falls back to image fonts");
    XCTAssertTrue([result.path hasSuffix:
        @"/MathJax/fonts/HTML-CSS/TeX/woff/MathJax_Main-Regular.woff"],
        @"Should map to the bundled font path, got %@", result.path);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:result.path],
                  @"The redirected font must actually exist in the bundle");
}

- (void)testUnbundledResourcePassesThroughToCDN
{
    // jax.js is not bundled, so the delegate must leave the request on the CDN.
    NSURL *result = [self resolvedURLForSuffix:
        @"jax/output/HTML-CSS/jax.js?V=2.7.3"];

    XCTAssertFalse(result.isFileURL,
                   @"An un-bundled resource must not be redirected locally");
    XCTAssertEqualObjects(result.host, @"cdnjs.cloudflare.com");
    XCTAssertTrue([result.path hasSuffix:@"jax/output/HTML-CSS/jax.js"]);
}

- (void)testMathJaxLoaderStillRedirectsWithConfigQuery
{
    // Regression guard for the behaviour the generalised redirect replaces.
    NSURL *result = [self resolvedURLForSuffix:
        @"MathJax.js?config=TeX-AMS-MML_HTMLorMML"];

    XCTAssertTrue(result.isFileURL,
                  @"MathJax.js should be served from the bundle");
    XCTAssertTrue([result.path hasSuffix:@"/MathJax/MathJax.js"],
                  @"Should map to the bundled loader, got %@", result.path);
    XCTAssertEqualObjects(result.query, @"config=TeX-AMS-MML_HTMLorMML",
                          @"MathJax.js must keep its config query");
}

- (void)testFullTeXWoffSetIsBundled
{
    // Authoritative list of the MathJax 2.7.3 HTML-CSS TeX woff files, copied
    // from the upstream distribution. It is intentionally NOT enumerated from
    // the bundle's own contents: a list read back from what was dropped could
    // never fail on an incomplete drop. A missing family (e.g. AMS) would let a
    // document's glyphs fetch remotely and pixelate on a timeout.
    NSArray<NSString *> *expected = @[
        @"MathJax_AMS-Regular",
        @"MathJax_Caligraphic-Bold",
        @"MathJax_Caligraphic-Regular",
        @"MathJax_Fraktur-Bold",
        @"MathJax_Fraktur-Regular",
        @"MathJax_Main-Bold",
        @"MathJax_Main-Italic",
        @"MathJax_Main-Regular",
        @"MathJax_Math-BoldItalic",
        @"MathJax_Math-Italic",
        @"MathJax_Math-Regular",
        @"MathJax_SansSerif-Bold",
        @"MathJax_SansSerif-Italic",
        @"MathJax_SansSerif-Regular",
        @"MathJax_Script-Regular",
        @"MathJax_Size1-Regular",
        @"MathJax_Size2-Regular",
        @"MathJax_Size3-Regular",
        @"MathJax_Size4-Regular",
        @"MathJax_Typewriter-Regular",
        @"MathJax_Vector-Bold",
        @"MathJax_Vector-Regular",
    ];

    NSURL *woffDir = [[NSBundle mainBundle].resourceURL
        URLByAppendingPathComponent:@"MathJax/fonts/HTML-CSS/TeX/woff"];

    for (NSString *name in expected)
    {
        NSURL *font = [woffDir URLByAppendingPathComponent:
                       [name stringByAppendingPathExtension:@"woff"]];
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:font.path],
                      @"missing bundled TeX font: %@.woff", name);
    }
    XCTAssertEqual(expected.count, 22u,
                   @"The 2.7.3 TeX woff set has 22 files");
}

@end
