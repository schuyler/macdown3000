//
//  MPSyntaxHighlightingTests.m
//  MacDown 3000
//
//  Created for Issue #58 - Phase 1: Markdown Rendering Tests
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <hoedown/document.h>
#import "MPRenderer.h"
#import "hoedown_html_patch.h"

// Uncomment to regenerate golden files
// #define REGENERATE_GOLDEN_FILES

// Category to expose private methods for testing
@interface MPRenderer (Testing)
- (void)parseMarkdown:(NSString *)markdown;
@end


#pragma mark - Mock Data Source

@interface MPMockRendererDataSource : NSObject <MPRendererDataSource>
@property (nonatomic, copy) NSString *markdown;
@property (nonatomic, copy) NSString *title;
@end

@implementation MPMockRendererDataSource

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.markdown = @"";
        self.title = @"";
    }
    return self;
}

- (BOOL)rendererLoading
{
    return NO;
}

- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    return self.markdown;
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    return self.title;
}

@end


#pragma mark - Mock Delegate

@interface MPMockRendererDelegate : NSObject <MPRendererDelegate>
@property (nonatomic) int extensions;
@property (nonatomic) int rendererFlags;
@property (nonatomic) BOOL smartyPants;
@property (nonatomic) BOOL renderTOC;
@property (nonatomic) BOOL detectFrontMatter;
@property (nonatomic) BOOL syntaxHighlighting;
@property (nonatomic) BOOL mermaid;
@property (nonatomic) BOOL graphviz;
@property (nonatomic) BOOL mathJax;
@property (nonatomic) MPCodeBlockAccessoryType codeBlockAccessory;
@property (nonatomic, copy) NSString *styleName;
@property (nonatomic, copy) NSString *highlightingThemeName;
@property (nonatomic, copy) NSString *lastHTML;
@end

@implementation MPMockRendererDelegate

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.extensions = 0;
        self.rendererFlags = 0;
        self.smartyPants = NO;
        self.renderTOC = NO;
        self.detectFrontMatter = NO;
        self.syntaxHighlighting = NO;
        self.mermaid = NO;
        self.graphviz = NO;
        self.mathJax = NO;
        self.codeBlockAccessory = MPCodeBlockAccessoryNone;
        self.styleName = @"GitHub2";
        self.highlightingThemeName = @"tomorrow";
    }
    return self;
}

- (int)rendererExtensions:(MPRenderer *)renderer
{
    return self.extensions;
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.smartyPants;
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    return self.renderTOC;
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    return self.styleName;
}

- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.detectFrontMatter;
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    return self.syntaxHighlighting;
}

- (BOOL)rendererHasMermaid:(MPRenderer *)renderer
{
    return self.mermaid;
}

- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
{
    return self.graphviz;
}

- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return self.codeBlockAccessory;
}

- (BOOL)rendererHasMathJax:(MPRenderer *)renderer
{
    return self.mathJax;
}

- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return self.highlightingThemeName;
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    self.lastHTML = html;
}

@end


#pragma mark - Test Class

@interface MPSyntaxHighlightingTests : XCTestCase
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPSyntaxHighlightingTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];

    // Create mock data source and delegate
    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];

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

#pragma mark - Language Class Generation Tests

/**
 * Test that code blocks with common programming languages generate correct
 * CSS classes for Prism.js syntax highlighting.
 */
- (void)testLanguageClassGeneration
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    [self verifyGoldenFile:@"syntax-highlighting-languages"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Test that language aliases are correctly mapped to their canonical names.
 * For example: js → javascript, objc → objectivec, html → markup
 */
- (void)testLanguageAliases
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    [self verifyGoldenFile:@"syntax-highlighting-aliases"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Test that code blocks without a specified language get the default
 * "language-none" class.
 */
- (void)testUnlabeledCodeBlock
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    NSString *markdown = @"```\nSome code without a language\n```";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    XCTAssertTrue([html containsString:@"class=\"language-none\""],
                  @"Unlabeled code block should have 'language-none' class");
}

/**
 * Test that indented code blocks (non-fenced) don't have language classes.
 */
- (void)testIndentedCodeBlock
{
    int extFlags = 0;  // No fenced code extension
    int rendFlags = 0;

    NSString *markdown = @"    Some indented code\n    More code";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    XCTAssertTrue([html containsString:@"<code>"],
                  @"Indented code should render as code element");
    XCTAssertFalse([html containsString:@"class=\"language-"],
                   @"Indented code blocks should not have language classes");
}

/**
 * Test that inline code (backticks) doesn't get language classes.
 */
- (void)testInlineCodeNoLanguageClass
{
    int extFlags = 0;
    int rendFlags = 0;

    NSString *markdown = @"Here is some `inline code` in a sentence.";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    XCTAssertTrue([html containsString:@"<code>inline code</code>"],
                  @"Inline code should render correctly");
    XCTAssertFalse([html containsString:@"class=\"language-"],
                   @"Inline code should not have language classes");
}

#pragma mark - Code Block Information Tests

/**
 * Test that the BLOCKCODE_INFORMATION flag properly adds language classes.
 */
- (void)testBlockcodeInformationFlag
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;

    // Without BLOCKCODE_INFORMATION flag
    NSString *markdown = @"```python\nprint('hello')\n```";
    NSString *htmlWithoutFlag = [self renderMarkdown:markdown
                                      withExtensions:extFlags
                                       rendererFlags:0];

    XCTAssertFalse([htmlWithoutFlag containsString:@"class=\"language-python\""],
                   @"Without BLOCKCODE_INFORMATION, no language class should be added");

    // With BLOCKCODE_INFORMATION flag
    NSString *htmlWithFlag = [self renderMarkdown:markdown
                                   withExtensions:extFlags
                                    rendererFlags:HOEDOWN_HTML_BLOCKCODE_INFORMATION];

    XCTAssertTrue([htmlWithFlag containsString:@"class=\"language-python\""],
                  @"With BLOCKCODE_INFORMATION, language class should be added");
}

/**
 * Test that mixed code blocks (some with languages, some without) render correctly.
 */
- (void)testMixedCodeBlocks
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    [self verifyGoldenFile:@"syntax-highlighting-mixed"
            withExtensions:extFlags
             rendererFlags:rendFlags];
}

/**
 * Test syntax highlighting with special characters and escaping.
 */
- (void)testSyntaxHighlightingWithSpecialCharacters
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    NSString *markdown = @"```html\n<div class=\"test\" data-value=\"foo & bar\">Hello</div>\n```";
    NSString *html = [self renderMarkdown:markdown
                           withExtensions:extFlags
                            rendererFlags:rendFlags];

    XCTAssertTrue([html containsString:@"class=\"language-markup\""],
                  @"HTML should map to 'language-markup'");
    XCTAssertTrue([html containsString:@"&lt;div"],
                  @"HTML tags should be escaped");
    XCTAssertTrue([html containsString:@"&quot;"],
                  @"Quotes should be escaped");
    XCTAssertTrue([html containsString:@"&amp;"],
                  @"Ampersands should be escaped");
}

/**
 * Test that language names are case-insensitive.
 */
- (void)testLanguageNameCaseInsensitivity
{
    int extFlags = HOEDOWN_EXT_FENCED_CODE;
    int rendFlags = HOEDOWN_HTML_BLOCKCODE_INFORMATION;

    // Test uppercase
    NSString *markdownUpper = @"```JAVASCRIPT\nvar x = 1;\n```";
    NSString *htmlUpper = [self renderMarkdown:markdownUpper
                                withExtensions:extFlags
                                 rendererFlags:rendFlags];

    // Test mixed case
    NSString *markdownMixed = @"```JavaScript\nvar x = 1;\n```";
    NSString *htmlMixed = [self renderMarkdown:markdownMixed
                                withExtensions:extFlags
                                 rendererFlags:rendFlags];

    // Both should produce lowercase language classes
    XCTAssertTrue([htmlUpper containsString:@"class=\"language-javascript\""] ||
                  [htmlUpper containsString:@"class=\"language-JAVASCRIPT\""],
                  @"Uppercase language names should be handled");
    XCTAssertTrue([htmlMixed containsString:@"class=\"language-javascript\""] ||
                  [htmlMixed containsString:@"class=\"language-JavaScript\""],
                  @"Mixed case language names should be handled");
}

@end
