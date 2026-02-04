//
//  MPQuickLookRendererTests.m
//  MacDown 3000
//
//  Tests for the Quick Look renderer facade (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
// Import from MacDownCore (add MacDownCore to header search paths in Xcode)
#import "MPQuickLookRenderer.h"
#import "MPQuickLookPreferences.h"


#pragma mark - Mock Preferences for Testing

@interface MPQuickLookMockPreferences : NSObject

@property (nonatomic, copy) NSString *styleName;
@property (nonatomic, copy) NSString *highlightingThemeName;
@property (nonatomic) BOOL extensionTables;
@property (nonatomic) BOOL extensionFencedCode;
@property (nonatomic) BOOL extensionAutolink;
@property (nonatomic) BOOL extensionStrikethrough;
@property (nonatomic) BOOL syntaxHighlighting;

@end

@implementation MPQuickLookMockPreferences

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Default values matching MacDown defaults
        self.styleName = @"GitHub2";
        self.highlightingThemeName = @"tomorrow";
        self.extensionTables = YES;
        self.extensionFencedCode = YES;
        self.extensionAutolink = YES;
        self.extensionStrikethrough = YES;
        self.syntaxHighlighting = YES;
    }
    return self;
}

// Quick Look always returns NO for these heavy features
- (BOOL)mathJaxEnabled { return NO; }
- (BOOL)mermaidEnabled { return NO; }
- (BOOL)graphvizEnabled { return NO; }

@end


#pragma mark - Test Class

@interface MPQuickLookRendererTests : XCTestCase

@property (nonatomic, strong) MPQuickLookRenderer *renderer;
@property (nonatomic, strong) MPQuickLookMockPreferences *mockPreferences;
@property (nonatomic, strong) NSBundle *bundle;

@end


@implementation MPQuickLookRendererTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];
    self.mockPreferences = [[MPQuickLookMockPreferences alloc] init];
    self.renderer = [[MPQuickLookRenderer alloc] init];
}

- (void)tearDown
{
    self.renderer = nil;
    self.mockPreferences = nil;
    self.bundle = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

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
    return content;
}


#pragma mark - Initialization Tests

- (void)testInitializerCreatesValidInstance
{
    MPQuickLookRenderer *renderer = [[MPQuickLookRenderer alloc] init];
    XCTAssertNotNil(renderer, @"Should create a valid renderer instance");
}


#pragma mark - Basic Rendering Tests

- (void)testRenderSimpleMarkdown
{
    NSString *markdown = @"# Hello World\n\nThis is a paragraph.";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertNotNil(html, @"Should return non-nil HTML");
    XCTAssertTrue([html containsString:@"<h1>"],
                  @"Should render heading as <h1>");
    XCTAssertTrue([html containsString:@"Hello World"],
                  @"Should include heading text");
    XCTAssertTrue([html containsString:@"<p>"],
                  @"Should render paragraph as <p>");
}

- (void)testRenderReturnsCompleteHTMLDocument
{
    NSString *markdown = @"# Test";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertNotNil(html, @"Should return non-nil HTML");
    XCTAssertTrue([html containsString:@"<html"],
                  @"Should include <html> tag");
    XCTAssertTrue([html containsString:@"<head>"],
                  @"Should include <head> tag");
    XCTAssertTrue([html containsString:@"<body>"],
                  @"Should include <body> tag");
    XCTAssertTrue([html containsString:@"</html>"],
                  @"Should include closing </html> tag");
}

- (void)testRenderIncludesCSSStyles
{
    NSString *markdown = @"# Test";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertNotNil(html, @"Should return non-nil HTML");
    XCTAssertTrue([html containsString:@"<style"],
                  @"Should include embedded CSS styles");
}

- (void)testRenderMarkdownFromURL
{
    // Create a temporary file with markdown content
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test_url.md"];
    NSString *markdown = @"# Test from URL\n\nContent here.";

    // Register cleanup first for robustness
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];

    NSError *error = nil;
    [markdown writeToFile:tempFile
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:&error];
    XCTAssertNil(error, @"Should write temp file successfully");

    NSURL *fileURL = [NSURL fileURLWithPath:tempFile];
    NSString *html = [self.renderer renderMarkdownFromURL:fileURL error:&error];

    XCTAssertNil(error, @"Should not error when rendering from URL");
    XCTAssertNotNil(html, @"Should return HTML from URL");
    XCTAssertTrue([html containsString:@"Test from URL"],
                  @"Should include content from file");
}


#pragma mark - Extension Configuration Tests

- (void)testExtensionTablesEnabled
{
    NSString *markdown = @"| Header 1 | Header 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertTrue([html containsString:@"<table"],
                  @"Should render tables when extension enabled");
    XCTAssertTrue([html containsString:@"<th>"],
                  @"Should render table headers");
}

- (void)testExtensionFencedCodeEnabled
{
    NSString *markdown = @"```\ncode block\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertTrue([html containsString:@"<pre>"],
                  @"Should render fenced code blocks");
    XCTAssertTrue([html containsString:@"<code"],
                  @"Should include code element");
}

- (void)testExtensionStrikethroughEnabled
{
    NSString *markdown = @"~~deleted text~~";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertTrue([html containsString:@"<del>"] || [html containsString:@"<s>"],
                  @"Should render strikethrough");
    XCTAssertTrue([html containsString:@"deleted text"],
                  @"Should include strikethrough content");
}

- (void)testExtensionAutolinkEnabled
{
    NSString *markdown = @"Visit https://example.com for more info.";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertTrue([html containsString:@"<a "],
                  @"Should auto-link URLs");
    XCTAssertTrue([html containsString:@"href=\"https://example.com\""],
                  @"Should include URL in href");
}


#pragma mark - Syntax Highlighting Tests (Prism)

- (void)testPrismSyntaxHighlightingEnabled
{
    NSString *markdown = @"```python\nprint('hello')\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertTrue([html containsString:@"language-python"],
                  @"Should add language-python class for Prism");
}

- (void)testPrismScriptsIncluded
{
    NSString *markdown = @"```javascript\nconsole.log('test');\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertTrue([html containsString:@"prism"],
                  @"Should include Prism scripts for syntax highlighting");
}

- (void)testLanguageAliasesMapped
{
    // Test that common aliases map to correct Prism language names
    NSString *markdown = @"```js\nvar x = 1;\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    // 'js' should map to 'javascript'
    XCTAssertTrue([html containsString:@"language-javascript"] ||
                  [html containsString:@"language-js"],
                  @"Should handle language aliases");
}


#pragma mark - CSS Styling Tests

- (void)testUsesConfiguredStyle
{
    // The renderer should use the style from preferences
    NSString *markdown = @"# Test";
    NSString *html = [self.renderer renderMarkdown:markdown];

    // Should contain embedded CSS (style content varies by theme)
    XCTAssertTrue([html containsString:@"<style"],
                  @"Should embed CSS styles");
}

- (void)testStyleEmbeddedNotLinked
{
    NSString *markdown = @"# Test";
    NSString *html = [self.renderer renderMarkdown:markdown];

    // Quick Look requires all assets to be embedded, not linked
    XCTAssertFalse([html containsString:@"<link rel=\"stylesheet\""],
                   @"Should embed styles, not link to external files");
}


#pragma mark - Feature Exclusion Tests (Critical for Issue #284)

- (void)testMathJaxNotIncluded
{
    NSString *markdown = @"# Test\n\n$x^2 + y^2 = z^2$";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertFalse([html containsString:@"MathJax"],
                   @"Should NOT include MathJax scripts");
    XCTAssertFalse([html containsString:@"mathjax"],
                   @"Should NOT include mathjax references");
}

- (void)testMermaidNotIncluded
{
    NSString *markdown = @"```mermaid\ngraph TD\n  A --> B\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertFalse([html containsString:@"mermaid.min.js"],
                   @"Should NOT include Mermaid scripts");
}

- (void)testGraphvizNotIncluded
{
    NSString *markdown = @"```dot\ndigraph G {\n  A -> B\n}\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertFalse([html containsString:@"viz.js"],
                   @"Should NOT include Graphviz scripts");
    XCTAssertFalse([html containsString:@"graphviz"],
                   @"Should NOT include graphviz references");
}

- (void)testMathJaxDelimitersRenderedAsText
{
    NSString *markdown = @"The formula $x^2$ should appear as text.";
    NSString *html = [self.renderer renderMarkdown:markdown];

    // Without MathJax, the $ delimiters should be in the output
    XCTAssertTrue([html containsString:@"$x^2$"] ||
                  [html containsString:@"$"],
                  @"Math delimiters should appear as literal text");
}

- (void)testMermaidCodeBlocksRenderedAsCode
{
    NSString *markdown = @"```mermaid\ngraph TD\n  A --> B\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    // Should render as a code block, not a diagram
    XCTAssertTrue([html containsString:@"<pre>"] || [html containsString:@"<code"],
                  @"Mermaid blocks should render as code, not diagrams");
}


#pragma mark - Edge Case Tests

- (void)testRenderNilMarkdown
{
    NSString *html = [self.renderer renderMarkdown:nil];

    // Should handle nil gracefully (return empty HTML or nil)
    XCTAssertTrue(html == nil || [html length] == 0 ||
                  ([html containsString:@"<html"] && [html containsString:@"<body>"]),
                  @"Nil markdown should be handled gracefully");
}

- (void)testRenderEmptyMarkdown
{
    NSString *html = [self.renderer renderMarkdown:@""];

    // Should return valid HTML structure even for empty input
    XCTAssertNotNil(html, @"Empty markdown should produce non-nil output");
}

- (void)testRenderWhitespaceOnlyMarkdown
{
    NSString *html = [self.renderer renderMarkdown:@"   \n\n   \t\t\n"];

    XCTAssertNotNil(html, @"Whitespace-only markdown should not crash");
}

- (void)testRenderUnicodeContent
{
    NSString *markdown = @"# Unicode Test\n\n"
                         @"Chinese: 中文测试\n"
                         @"Japanese: 日本語テスト\n"
                         @"Korean: 한국어 테스트\n"
                         @"Emoji: 😀🎉🚀\n"
                         @"Arabic: مرحبا\n"
                         @"Russian: Привет";

    NSString *html = [self.renderer renderMarkdown:markdown];

    XCTAssertNotNil(html, @"Unicode content should render");
    XCTAssertTrue([html containsString:@"中文测试"],
                  @"Should preserve Chinese characters");
    XCTAssertTrue([html containsString:@"😀"],
                  @"Should preserve emoji");
}

- (void)testRenderMalformedMarkdown
{
    // Unclosed code block
    NSString *markdown1 = @"# Header\n```python\ncode without closing fence";
    NSString *html1 = [self.renderer renderMarkdown:markdown1];
    XCTAssertNotNil(html1, @"Unclosed code block should not crash");

    // Unclosed emphasis
    NSString *markdown2 = @"**Bold without closing";
    NSString *html2 = [self.renderer renderMarkdown:markdown2];
    XCTAssertNotNil(html2, @"Unclosed emphasis should not crash");
}

- (void)testRenderVeryLargeMarkdown
{
    // Generate a large markdown document
    NSMutableString *largeMarkdown = [NSMutableString string];
    for (int i = 0; i < 5000; i++) {
        [largeMarkdown appendFormat:@"Line %d with some text content.\n", i];
    }

    NSDate *start = [NSDate date];
    NSString *html = [self.renderer renderMarkdown:largeMarkdown];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];

    XCTAssertNotNil(html, @"Large document should render");
    XCTAssertTrue(elapsed < 5.0,
                  @"Large document should render within 5 seconds, took %f", elapsed);
}


#pragma mark - Security Tests

- (void)testScriptTagsInCodeBlocksAreEscaped
{
    NSString *markdown = @"```html\n<script>alert('xss')</script>\n```";
    NSString *html = [self.renderer renderMarkdown:markdown];

    // Script tags inside code blocks should be escaped
    XCTAssertFalse([html containsString:@"<script>alert"],
                   @"Script tags in code should be escaped");
    XCTAssertTrue([html containsString:@"&lt;script"] ||
                  [html containsString:@"<code"],
                  @"Code block should be present with escaped content");
}


#pragma mark - File Extension Tests

- (void)testRendersMdExtension
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test_ext.md"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];

    [@"# Test" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:[NSURL fileURLWithPath:tempFile] error:&error];

    XCTAssertNil(error, @"Should render .md files");
    XCTAssertNotNil(html, @"Should produce HTML for .md files");
}

- (void)testRendersMarkdownExtension
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test.markdown"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];

    [@"# Test" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:[NSURL fileURLWithPath:tempFile] error:&error];

    XCTAssertNil(error, @"Should render .markdown files");
    XCTAssertNotNil(html, @"Should produce HTML for .markdown files");
}

- (void)testRendersMdownExtension
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test.mdown"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];

    [@"# Test" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:[NSURL fileURLWithPath:tempFile] error:&error];

    XCTAssertNil(error, @"Should render .mdown files");
    XCTAssertNotNil(html, @"Should produce HTML for .mdown files");
}

- (void)testRendersMkdExtension
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test.mkd"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];

    [@"# Test" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:[NSURL fileURLWithPath:tempFile] error:&error];

    XCTAssertNil(error, @"Should render .mkd files");
    XCTAssertNotNil(html, @"Should produce HTML for .mkd files");
}

- (void)testRendersMkdnExtension
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:@"test.mkdn"];
    [self addTeardownBlock:^{
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    }];

    [@"# Test" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:[NSURL fileURLWithPath:tempFile] error:&error];

    XCTAssertNil(error, @"Should render .mkdn files");
    XCTAssertNotNil(html, @"Should produce HTML for .mkdn files");
}


#pragma mark - Error Handling Tests

- (void)testRenderMarkdownFromURLWithNonexistentFile
{
    NSURL *badURL = [NSURL fileURLWithPath:@"/nonexistent/path/to/file.md"];
    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:badURL error:&error];

    XCTAssertNil(html, @"Should return nil for nonexistent file");
    XCTAssertNotNil(error, @"Should populate error for nonexistent file");
}

- (void)testRenderMarkdownFromURLWithNilURL
{
    NSError *error = nil;
    NSString *html = [self.renderer renderMarkdownFromURL:nil error:&error];

    XCTAssertNil(html, @"Should return nil for nil URL");
    XCTAssertNotNil(error, @"Should populate error for nil URL");
}

@end
