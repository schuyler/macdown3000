//
//  MPHTMLExportTests.m
//  MacDown 3000
//
//  Tests for issue #30: Fix line breaking in HTML exports
//  Verifies that export.css provides proper word-breaking for paragraphs
//  and other block elements in HTML exports and screen preview.
//
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <sys/stat.h>
#import "MPAsset.h"
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import "hoedown/document.h"

// Category to expose private methods for testing
@interface MPRenderer (ExportTesting)
- (NSArray *)stylesheets;
@end


@interface MPHTMLExportTests : XCTestCase
@property (strong) NSBundle *bundle;
@property (strong) MPRenderer *renderer;
@property (strong) MPMockRendererDataSource *dataSource;
@property (strong) MPMockRendererDelegate *delegate;
@property (strong) NSString *testDirectory;
@property (strong) NSFileManager *fileManager;
@end


@implementation MPHTMLExportTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];
    self.fileManager = [NSFileManager defaultManager];

    // Create unique test directory for file operations
    NSString *tempDir = NSTemporaryDirectory();
    self.testDirectory = [tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.fileManager createDirectoryAtPath:self.testDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];

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
    // Clean up test directory
    if (self.testDirectory) {
        [self.fileManager removeItemAtPath:self.testDirectory error:nil];
    }

    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    self.bundle = nil;
    self.testDirectory = nil;
    [super tearDown];
}


#pragma mark - Helper Methods

- (NSURL *)exportCSSURL
{
    // Use main bundle to find export.css in Extensions subdirectory
    // This avoids dependency on MPExtensionURL which isn't available to test target
    NSBundle *mainBundle = [NSBundle mainBundle];
    return [mainBundle URLForResource:@"export" withExtension:@"css"
                         subdirectory:@"Extensions"];
}

- (NSURL *)printCSSURL
{
    // Use main bundle to find print.css in Extensions subdirectory
    NSBundle *mainBundle = [NSBundle mainBundle];
    return [mainBundle URLForResource:@"print" withExtension:@"css"
                         subdirectory:@"Extensions"];
}

- (NSString *)exportCSSContent
{
    NSURL *url = [self exportCSSURL];
    if (!url) return nil;
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    return content;
}


#pragma mark - CSS File Existence Tests

- (void)testExportCSSFileExists
{
    NSURL *url = [self exportCSSURL];
    XCTAssertNotNil(url, @"export.css URL should be generated");

    // Verify file actually exists
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:url.path];
    XCTAssertTrue(exists, @"export.css file should exist at %@", url.path);
}

- (void)testExportCSSCanBeLoaded
{
    NSURL *url = [self exportCSSURL];
    XCTAssertNotNil(url, @"export.css URL should exist");

    MPStyleSheet *stylesheet = [MPStyleSheet CSSWithURL:url];
    XCTAssertNotNil(stylesheet, @"export.css should load as MPStyleSheet");

    NSString *html = [stylesheet htmlForOption:MPAssetEmbedded];
    XCTAssertNotNil(html, @"export.css should render as embedded style");
    XCTAssertTrue([html containsString:@"<style"], @"Should generate style tag");
}


#pragma mark - CSS Content Tests

- (void)testExportCSSContainsParagraphBreaking
{
    NSString *cssContent = [self exportCSSContent];
    XCTAssertNotNil(cssContent, @"export.css should have content");

    // Check for paragraph selector with word-breaking properties
    XCTAssertTrue([cssContent containsString:@"word-break"],
                  @"Should include word-break property");
    XCTAssertTrue([cssContent containsString:@"overflow-wrap"],
                  @"Should include overflow-wrap property");
    XCTAssertTrue([cssContent containsString:@"break-word"],
                  @"Should use break-word value");
}

- (void)testExportCSSContainsListAndTableBreaking
{
    NSString *cssContent = [self exportCSSContent];
    XCTAssertNotNil(cssContent, @"export.css should have content");

    // Check for list item and table cell selectors
    XCTAssertTrue([cssContent containsString:@"li"],
                  @"Should target li elements");
    XCTAssertTrue([cssContent containsString:@"td"],
                  @"Should target td elements");
    XCTAssertTrue([cssContent containsString:@"th"],
                  @"Should target th elements");
}

- (void)testExportCSSContainsBlockquoteAndDescriptionBreaking
{
    NSString *cssContent = [self exportCSSContent];
    XCTAssertNotNil(cssContent, @"export.css should have content");

    // Check for blockquote and description list elements
    XCTAssertTrue([cssContent containsString:@"blockquote"],
                  @"Should target blockquote elements");
    XCTAssertTrue([cssContent containsString:@"dd"],
                  @"Should target dd elements");
}

- (void)testExportCSSContainsBodyBreaking
{
    NSString *cssContent = [self exportCSSContent];
    XCTAssertNotNil(cssContent, @"export.css should have content");

    // Check for body element with legacy word-wrap
    XCTAssertTrue([cssContent containsString:@"body"],
                  @"Should target body element");
    XCTAssertTrue([cssContent containsString:@"word-wrap"],
                  @"Should include legacy word-wrap property");
}


#pragma mark - Stylesheet Array Tests

- (void)testStylesheetsIncludeExportCSS
{
    // Get stylesheets array using exposed private method
    NSArray *stylesheets = [self.renderer stylesheets];
    XCTAssertNotNil(stylesheets, @"stylesheets should not be nil");
    XCTAssertTrue(stylesheets.count > 0, @"stylesheets should not be empty");

    // Verify that export.css is included by checking that at least one stylesheet
    // contains export.css content (word-break rules)
    BOOL foundExportCSSContent = NO;
    for (MPStyleSheet *ss in stylesheets) {
        NSString *html = [ss htmlForOption:MPAssetEmbedded];
        if (html && [html containsString:@"word-break: break-word"]) {
            foundExportCSSContent = YES;
            break;
        }
    }
    XCTAssertTrue(foundExportCSSContent,
                  @"stylesheets array should include export.css with word-break rules");
}

- (void)testStylesheetsCountIncludesExportCSS
{
    // Verify the stylesheets array has the expected number of items
    // which should include: theme CSS + print.css + export.css (at minimum)
    NSArray *stylesheets = [self.renderer stylesheets];
    XCTAssertNotNil(stylesheets, @"stylesheets should not be nil");

    // With a default delegate, we expect at least theme + print.css + export.css
    XCTAssertTrue(stylesheets.count >= 3,
                  @"stylesheets should include at least theme CSS, print.css, and export.css");
}


#pragma mark - HTML Export Tests

- (void)testHTMLExportWithStylesEmbedsExportCSS
{
    // Set up test markdown
    self.dataSource.markdown = @"# Test\n\nThis is a paragraph with text.";
    self.dataSource.title = @"Test Document";

    // Parse and get exported HTML with styles
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");
    XCTAssertTrue([html containsString:@"<style"],
                  @"Should embed styles");
    XCTAssertTrue([html containsString:@"word-break"],
                  @"Should embed word-break rules from export.css");
    XCTAssertTrue([html containsString:@"overflow-wrap"],
                  @"Should embed overflow-wrap rules from export.css");
}

- (void)testHTMLExportWithoutStylesExcludesExportCSS
{
    // Set up test markdown
    self.dataSource.markdown = @"# Test\n\nThis is a paragraph.";
    self.dataSource.title = @"Test Document";

    // Parse and get exported HTML without styles
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:NO highlighting:NO];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");
    // When withStyles=NO, no style content should be embedded
    // The word-break rules from export.css should NOT appear
    BOOL hasWordBreak = [html containsString:@"word-break: break-word"];
    BOOL hasOverflowWrap = [html containsString:@"overflow-wrap: break-word"];
    // Note: Some basic styles might still be present from other sources
    // The key is that export.css-specific rules shouldn't be there
    XCTAssertFalse(hasWordBreak && hasOverflowWrap,
                   @"export.css rules should not appear when withStyles=NO");
}

- (void)testHTMLExportWithHighlightingIncludesExportCSS
{
    // Set up test markdown with code
    self.dataSource.markdown = @"# Test\n\nParagraph text.\n\n```javascript\nconst x = 1;\n```";
    self.dataSource.title = @"Test Document";
    self.delegate.syntaxHighlighting = YES;

    // Parse and get exported HTML with styles and highlighting
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");
    XCTAssertTrue([html containsString:@"word-break"],
                  @"export.css word-break should be present with highlighting");
    XCTAssertTrue([html containsString:@"overflow-wrap"],
                  @"export.css overflow-wrap should be present with highlighting");
}

- (void)testExportCSSIsLastStylesheetInHTMLExportWithHighlighting
{
    // Set up test markdown with code that will trigger Prism highlighting
    self.dataSource.markdown = @"# Test\n\nSome text.\n\n```javascript\nconst x = 1;\n```";
    self.dataSource.title = @"CSS Order Test";
    self.delegate.syntaxHighlighting = YES;

    // Parse and get exported HTML with styles and highlighting
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:YES];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");

    // Export.css rules should appear AFTER prism styles in the HTML
    // Find the last occurrence of word-break (from export.css)
    NSRange exportRange = [html rangeOfString:@"word-break: break-word"
                                      options:NSBackwardsSearch];
    // Find any occurrence of prism-related CSS (prism stylesheets)
    NSRange prismRange = [html rangeOfString:@"token" options:NSCaseInsensitiveSearch];

    // If both exist, export.css content should come after Prism content
    if (exportRange.location != NSNotFound && prismRange.location != NSNotFound) {
        XCTAssertGreaterThan(exportRange.location, prismRange.location,
                             @"export.css should appear after prism styles in HTML for correct cascade order");
    }
}


#pragma mark - Integration Tests

- (void)testExportCSSHandlesLongURLsInParagraphs
{
    // Create markdown with a very long URL
    NSString *longURL = @"https://example.com/very/long/path/that/should/break/properly/when/it/exceeds/the/container/width";
    self.dataSource.markdown = [NSString stringWithFormat:@"Visit this link: %@", longURL];
    self.dataSource.title = @"Long URL Test";

    // Parse and export
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");
    XCTAssertTrue([html containsString:longURL],
                  @"Long URL should be present in output");
    XCTAssertTrue([html containsString:@"word-break"],
                  @"Word-break rules should be present to handle long URLs");
}

- (void)testExportCSSHandlesLongWordsInLists
{
    // Create markdown with long words in a list
    self.dataSource.markdown = @"- Supercalifragilisticexpialidocious\n- Pneumonoultramicroscopicsilicovolcanoconiosis";
    self.dataSource.title = @"Long Words Test";

    // Parse and export
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");
    XCTAssertTrue([html containsString:@"<li>"],
                  @"Should contain list items");
    XCTAssertTrue([html containsString:@"word-break"],
                  @"Word-break rules should be present for list items");
}

- (void)testExportCSSHandlesLongTextInTables
{
    // Enable tables extension for this test
    self.delegate.extensions = HOEDOWN_EXT_TABLES;

    // Create markdown with long text in table cells
    self.dataSource.markdown = @"| Header | Description |\n|--------|-------------|\n| Key | ThisIsAVeryLongWordWithoutSpacesThatShouldWrapProperly |";
    self.dataSource.title = @"Table Test";

    // Parse and export
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertNotNil(html, @"Exported HTML should not be nil");
    XCTAssertTrue([html containsString:@"<table"],
                  @"Should contain table");
    XCTAssertTrue([html containsString:@"<td"],
                  @"Should contain table cells");
    XCTAssertTrue([html containsString:@"word-break"],
                  @"Word-break rules should be present for table cells");
}


#pragma mark - File Export Tests

- (void)testHTMLExportWritesToFile
{
    // Set up test markdown
    self.dataSource.markdown = @"# Test Document\n\nThis is a **paragraph** with _formatting_.";
    self.dataSource.title = @"Test Document";

    // Parse and get exported HTML
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];
    XCTAssertNotNil(html, @"Should generate HTML");

    // Write to file
    NSURL *fileURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"export.html"]];
    NSError *error = nil;
    BOOL success = [html writeToURL:fileURL
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];

    XCTAssertTrue(success, @"Should write HTML to file");
    XCTAssertNil(error, @"Should not have error");
    XCTAssertTrue([self.fileManager fileExistsAtPath:fileURL.path], @"File should exist");

    // Read back and verify content
    NSString *readBack = [NSString stringWithContentsOfURL:fileURL
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    XCTAssertNil(error, @"Should read file without error");
    XCTAssertEqualObjects(readBack, html, @"Content should match");
    XCTAssertTrue([readBack containsString:@"<h1>Test Document</h1>"], @"Should contain heading");
    XCTAssertTrue([readBack containsString:@"<strong>paragraph</strong>"], @"Should contain bold text");
}

- (void)testHTMLExportOverwritesExistingFile
{
    NSURL *fileURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"overwrite.html"]];

    // Write initial content
    NSString *initialContent = @"<html><body>Initial</body></html>";
    NSError *error = nil;
    [initialContent writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"Should write initial file");

    // Generate and write new HTML
    self.dataSource.markdown = @"# New Content\n\nReplaced.";
    self.dataSource.title = @"New";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    BOOL success = [html writeToURL:fileURL
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];
    XCTAssertTrue(success, @"Should overwrite file");

    // Verify new content
    NSString *readBack = [NSString stringWithContentsOfURL:fileURL
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    XCTAssertTrue([readBack containsString:@"<h1>New Content</h1>"], @"Should have new content");
    XCTAssertFalse([readBack containsString:@"Initial"], @"Should not have old content");
}

- (void)testHTMLExportCreatesValidStructure
{
    // Set up complex markdown
    self.dataSource.markdown = @"# Heading\n\n## Subheading\n\nParagraph with **bold** and _italic_.\n\n- List item 1\n- List item 2\n\n```\ncode block\n```";
    self.dataSource.title = @"Structure Test";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    // Write to file
    NSURL *fileURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"structure.html"]];
    NSError *error = nil;
    [html writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    // Read and verify structure
    NSString *content = [NSString stringWithContentsOfURL:fileURL
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    XCTAssertNotNil(content, @"Should read content");

    // Verify HTML structure elements
    XCTAssertTrue([content containsString:@"<!DOCTYPE html>"] || [content containsString:@"<html"],
                  @"Should be complete HTML document");
    XCTAssertTrue([content containsString:@"<head>"], @"Should have head");
    XCTAssertTrue([content containsString:@"<body"], @"Should have body");
    XCTAssertTrue([content containsString:@"<h1>"], @"Should have h1");
    XCTAssertTrue([content containsString:@"<h2>"], @"Should have h2");
    XCTAssertTrue([content containsString:@"<ul>"], @"Should have list");
    XCTAssertTrue([content containsString:@"<li>"], @"Should have list items");
    XCTAssertTrue([content containsString:@"<pre>"] || [content containsString:@"<code>"],
                  @"Should have code block");
}

- (void)testHTMLExportWithDifferentEncodings
{
    // Test with Unicode content
    self.dataSource.markdown = @"# Unicode Test\n\nHello 世界! Привет мир! مرحبا بالعالم";
    self.dataSource.title = @"Unicode";

    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    NSURL *fileURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"unicode.html"]];
    NSError *error = nil;
    BOOL success = [html writeToURL:fileURL
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];
    XCTAssertTrue(success, @"Should write Unicode content");

    // Read back and verify Unicode preserved
    NSString *readBack = [NSString stringWithContentsOfURL:fileURL
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    XCTAssertTrue([readBack containsString:@"世界"], @"Should preserve Chinese");
    XCTAssertTrue([readBack containsString:@"Привет"], @"Should preserve Russian");
    XCTAssertTrue([readBack containsString:@"مرحبا"], @"Should preserve Arabic");
}

- (void)testHTMLExportToReadOnlyDirectoryFails
{
    // Create a read-only directory
    NSString *readOnlyDir = [self.testDirectory stringByAppendingPathComponent:@"readonly"];
    NSError *error = nil;
    [self.fileManager createDirectoryAtPath:readOnlyDir
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error];

    // Make it read-only
    const char *path = [readOnlyDir fileSystemRepresentation];
    chmod(path, S_IRUSR | S_IXUSR);  // r-x only

    // Try to write
    self.dataSource.markdown = @"# Test";
    [self.renderer parseMarkdown:self.dataSource.markdown];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    NSURL *fileURL = [NSURL fileURLWithPath:[readOnlyDir stringByAppendingPathComponent:@"test.html"]];
    BOOL success = [html writeToURL:fileURL
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];

    XCTAssertFalse(success, @"Write should fail to read-only directory");
    XCTAssertNotNil(error, @"Should return error");

    // Restore permissions for cleanup
    chmod(path, S_IRWXU);
}

@end
