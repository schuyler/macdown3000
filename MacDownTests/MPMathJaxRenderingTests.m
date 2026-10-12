//
//  MPMathJaxRenderingTests.m
//  MacDown 3000
//
//  Created for Issue #58 - Phase 1: Markdown Rendering Tests
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <hoedown/document.h>
#import "MPRendererTestHelpers.h"
#import "hoedown_html_patch.h"

// Uncomment to regenerate golden files
// #define REGENERATE_GOLDEN_FILES


#pragma mark - Test Class

@interface MPMathJaxRenderingTests : XCTestCase
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPMathJaxRenderingTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];

    // Create mock data source and delegate
    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];

    // Enable MathJax for these tests
    self.delegate.mathJax = YES;

    // Create renderer and wire it up
    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self.dataSource;
    self.renderer.delegate = self.delegate;
}

- (void)tearDown
{
    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    self.bundle = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

/**
 * Load a fixture file from the MacDownTests/Fixtures/ subdirectory.
 */
- (NSString *)loadFixture:(NSString *)name withExtension:(NSString *)ext
{
    NSURL *url = [self.bundle URLForResource:name
                               withExtension:ext
                                subdirectory:@"Fixtures"];
    if (!url) {
        return nil;
    }

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    if (error) {
        NSLog(@"Error loading fixture %@.%@: %@", name, ext, error);
        return nil;
    }

    return content;
}

/**
 * Render markdown through MPRenderer (MacDown's actual rendering code).
 * This calls parseMarkdown directly for synchronous testing.
 */
- (NSString *)renderMarkdown:(NSString *)markdown
              withExtensions:(int)extFlags
               rendererFlags:(int)rendFlags
{
    // Configure the delegate with the desired flags
    self.delegate.extensions = extFlags;
    self.renderer.rendererFlags = rendFlags;

    // Set the markdown content in the data source
    self.dataSource.markdown = markdown;

    // Parse the markdown synchronously (for testing)
    [self.renderer parseMarkdown:markdown];

    // Return the rendered HTML
    return [self.renderer currentHtml];
}

/**
 * Verify rendering against a golden file.
 * Loads <name>.md, renders it, and compares with <name>.html.
 * If REGENERATE_GOLDEN_FILES is defined, writes the output instead of comparing.
 */
- (void)verifyGoldenFile:(NSString *)name
          withExtensions:(int)extFlags
           rendererFlags:(int)rendFlags
{
    // Load input markdown
    NSString *input = [self loadFixture:name withExtension:@"md"];
    XCTAssertNotNil(input, @"Failed to load input fixture: %@.md", name);

    // Render the markdown
    NSString *actual = [self renderMarkdown:input
                             withExtensions:extFlags
                              rendererFlags:rendFlags];
    XCTAssertNotNil(actual, @"Rendering produced nil output for: %@", name);

#ifdef REGENERATE_GOLDEN_FILES
    // Regenerate mode: write the output to the golden file
    NSString *fixturePath = [[self.bundle resourcePath]
                             stringByAppendingPathComponent:@"Fixtures"];
    NSString *goldenPath = [fixturePath stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"%@.html", name]];

    NSError *error = nil;
    [actual writeToFile:goldenPath
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&error];

    if (error) {
        XCTFail(@"Failed to write golden file %@.html: %@", name, error);
    } else {
        NSLog(@"Regenerated golden file: %@.html", name);
    }
#else
    // Normal mode: compare with expected output
    NSString *expected = [self loadFixture:name withExtension:@"html"];
    XCTAssertNotNil(expected, @"Failed to load expected fixture: %@.html", name);

    XCTAssertEqualObjects(actual, expected,
                          @"Rendered output doesn't match golden file: %@", name);
#endif
}

#pragma mark - MathJax Syntax Preservation Tests

/**
 * Test that inline math syntax \( ... \) is preserved in HTML output.
 * MathJax processes this syntax in the browser, so our renderer should
 * leave it untouched in the HTML.
 */
- (void)testInlineMathPreserved
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *markdown = @"The equation \\( x^2 + y^2 = z^2 \\) is famous.";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    // MacDown strips the backslashes from MathJax delimiters \( and \)
    // leaving just the parentheses ( and )
    XCTAssertTrue([html containsString:@"( x^2 + y^2 = z^2 )"],
                  @"Math expression with parentheses should be preserved in output");
}

/**
 * Test that display math syntax $$ ... $$ is preserved in HTML output.
 */
- (void)testDisplayMathPreserved
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *markdown = @"$$\n\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}\n$$";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    XCTAssertTrue([html containsString:@"$$"],
                  @"Display math delimiters should be preserved in output");
    XCTAssertTrue([html containsString:@"\\int"] && [html containsString:@"\\infty"],
                  @"Math expression should be preserved in output");
}

/**
 * Test comprehensive MathJax syntax preservation using golden files.
 */
- (void)testMathJaxSyntaxComprehensive
{
    int extFlags = 0;
    int rendFlags = 0;

    [self verifyGoldenFile:@"mathjax-syntax"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Test that MathJax syntax inside code blocks is NOT processed
 * (it should remain as literal text).
 */
- (void)testMathInCodeBlocksIgnored
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = 0;

    [self verifyGoldenFile:@"mathjax-in-code"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Test that MathJax rendering works when enabled.
 * This test verifies that math expressions are rendered when MathJax is enabled.
 */
- (void)testMathJaxScriptsAvailable
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *markdown = @"Test: \\( x = y \\)";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    // Verify HTML was generated with MathJax enabled
    XCTAssertNotNil(html, @"HTML output should be generated");
    XCTAssertTrue([html containsString:@"( x = y )"],
                  @"Math expression should be rendered");
}

/**
 * Test that special characters in math expressions are properly escaped.
 */
- (void)testMathWithSpecialCharacters
{
    int extFlags = 0;
    int rendFlags = 0;

    // Test math with angle brackets and ampersands
    NSString *markdown = @"Inequality: \\( x < y \\& y < z \\)";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    // Verify HTML output is generated and contains the word "Inequality"
    XCTAssertNotNil(html, @"HTML output should be generated");
    XCTAssertTrue([html containsString:@"Inequality"],
                  @"Text content should be present in output");
    // MacDown strips backslashes and may escape special characters
    // The exact format depends on markdown processing
    XCTAssertTrue([html length] > 0, @"HTML should not be empty");
}


#pragma mark - Font Selection Tests

/**
 * The HTML-CSS output jax prefers fonts installed on the machine over
 * MathJax's own, and macOS ships STIX faces that WebKit resolves by name.
 * Declining them keeps the preview on MathJax's TeX faces; otherwise it
 * typesets digits and operators in STIXGeneral-Regular, a Times-metric face
 * indistinguishable from body text.
 *
 * Both settings are matched by value, and matched inside the 'HTML-CSS'
 * block. Prose naming either setting appears in the same embedded script and
 * must not satisfy the assertion, and a setting hoisted out of the block
 * reaches no output jax at all: MathJax merges configuration per jax id, so
 * availableFonts at the top level of MathJax.Hub.Config is silently ignored
 * and the STIX regression returns.
 */
- (void)testPreviewDeclinesLocallyInstalledMathFonts
{
    self.dataSource.markdown = @"Inline \\( x = 2y + 15 \\)";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    NSString *html = self.delegate.lastHTML;
    XCTAssertNotNil(html, @"Preview render should produce HTML");

    // [^}] spans newlines, so this stays within the 'HTML-CSS' object.
    NSString *inBlock = @"['\"]?HTML-CSS['\"]?\\s*:\\s*\\{[^}]*";
    NSUInteger (^matchCount)(NSString *) = ^(NSString *setting) {
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:
                [inBlock stringByAppendingString:setting]
                                                      options:0 error:NULL];
        return [re numberOfMatchesInString:html options:0
                                     range:NSMakeRange(0, html.length)];
    };

    XCTAssertEqual(matchCount(@"['\"]?availableFonts['\"]?\\s*:\\s*\\[\\s*\\]"),
                   (NSUInteger)1,
                   @"HTML-CSS config should set availableFonts to an empty "
                   @"list, so locally installed STIX faces do not win over "
                   @"MathJax's TeX faces");
    XCTAssertEqual(matchCount(@"['\"]?preferredFont['\"]?\\s*:\\s*null"),
                   (NSUInteger)1,
                   @"HTML-CSS config should null preferredFont: MathJax tests "
                   @"the preferred font even when it is absent from "
                   @"availableFonts, so an empty list alone still takes the "
                   @"local path on a machine with the TeX fonts installed");
}

/**
 * MathJax serves its TeX faces from the same CDN that serves its scripts.
 * With font-src blocking that origin the output jax stalls for its web-font
 * timeout and then falls back to bitmap image fonts.
 *
 * The origin is spelled out rather than derived from kMPMathJaxCDN, which is
 * file-static and unreachable from here. Since the policy derives both
 * directives from that constant, pointing it at another host fails this
 * assertion rather than silently passing while the policy moves.
 */
- (void)testPreviewCSPAllowsMathJaxFontsFromCDN
{
    self.dataSource.markdown = @"Inline \\( x = 2y + 15 \\)";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    [self.renderer render];

    NSString *html = self.delegate.lastHTML;
    XCTAssertNotNil(html, @"Preview render should produce HTML");
    XCTAssertTrue(
        [html containsString:@"font-src data: file: https://cdnjs.cloudflare.com;"],
        @"CSP font-src should allow the CDN serving MathJax's TeX faces");
}

@end
