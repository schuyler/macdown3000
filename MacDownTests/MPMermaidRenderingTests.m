//
//  MPMermaidRenderingTests.m
//  MacDown 3000
//
//  Tests for Mermaid diagram rendering HTML output.
//  Note: Actual SVG rendering happens in JavaScript; these tests verify
//  the HTML structure that enables rendering. See issue #194 for
//  Puppeteer-based browser rendering tests.
//
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <hoedown/document.h>
#import "MPRendererTestHelpers.h"

@interface MPMermaidRenderingTests : XCTestCase
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPMermaidRenderingTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];

    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];
    self.delegate.mermaid = YES;
    self.delegate.extensions = HOEDOWN_EXT_FENCED_CODE;

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

- (NSString *)renderMarkdown:(NSString *)markdown
{
    self.dataSource.markdown = markdown;
    [self.renderer parseMarkdown:markdown];
    return [self.renderer currentHtml];
}

#pragma mark - HTML Structure Tests

- (void)testMermaidCodeBlockPreservesClass
{
    NSString *md = @"```mermaid\ngraph TD\n    A-->B\n```";
    NSString *html = [self renderMarkdown:md];

    XCTAssertTrue([html containsString:@"language-mermaid"],
                  @"Should preserve mermaid language class for JS to find");
}

- (void)testMermaidCodeBlockPreservesSource
{
    NSString *md = @"```mermaid\ngraph TD\n    A-->B\n```";
    NSString *html = [self renderMarkdown:md];

    XCTAssertTrue([html containsString:@"A--&gt;B"] || [html containsString:@"A-->B"],
                  @"Should preserve diagram source (possibly HTML-escaped)");
}

- (void)testMermaidScriptsIncludedInExport
{
    NSString *md = @"```mermaid\ngraph TD\n    A-->B\n```";
    self.dataSource.markdown = md;
    self.dataSource.title = @"Test";

    [self.renderer parseMarkdown:md];
    NSString *html = [self.renderer HTMLForExportWithStyles:YES highlighting:NO];

    XCTAssertTrue([html containsString:@"mermaid"],
                  @"Export should include mermaid scripts");
}

- (void)testMultipleMermaidBlocksPreserved
{
    NSString *md = @"```mermaid\ngraph TD\n    A-->B\n```\n\n"
                   @"```mermaid\nsequenceDiagram\n    Alice->>Bob: Hi\n```";
    NSString *html = [self renderMarkdown:md];

    // Count occurrences of language-mermaid
    NSUInteger count = 0;
    NSRange searchRange = NSMakeRange(0, html.length);
    NSRange foundRange;
    while ((foundRange = [html rangeOfString:@"language-mermaid"
                                     options:0
                                       range:searchRange]).location != NSNotFound) {
        count++;
        searchRange.location = foundRange.location + foundRange.length;
        searchRange.length = html.length - searchRange.location;
    }

    XCTAssertEqual(count, 2, @"Both mermaid blocks should be preserved");
}

#pragma mark - Error Handling Tests

- (void)testMalformedMermaidSyntaxDoesNotCrash
{
    NSString *md = @"```mermaid\ninvalid { syntax [[\n```";

    XCTAssertNoThrow([self renderMarkdown:md],
                     @"Invalid Mermaid syntax should not crash renderer");
}

- (void)testEmptyMermaidBlockDoesNotCrash
{
    NSString *md = @"```mermaid\n```";

    XCTAssertNoThrow([self renderMarkdown:md],
                     @"Empty Mermaid block should not crash renderer");
}

- (void)testMermaidWithSpecialCharacters
{
    NSString *md = @"```mermaid\ngraph TD\n    A[\"Node <with> special & chars\"]-->B\n```";
    NSString *html = [self renderMarkdown:md];

    XCTAssertNotNil(html, @"Should handle special characters in diagram");
    XCTAssertTrue(html.length > 0, @"Should produce non-empty output");
}

- (void)testMermaidWithUnicode
{
    NSString *md = @"```mermaid\ngraph TD\n    A[\"日本語\"]-->B[\"emoji 🎉\"]\n```";

    XCTAssertNoThrow([self renderMarkdown:md],
                     @"Unicode in Mermaid should not crash renderer");
}

#pragma mark - Mermaid Disabled Tests

- (void)testMermaidDisabledPreservesCodeBlock
{
    self.delegate.mermaid = NO;

    NSString *md = @"```mermaid\ngraph TD\n    A-->B\n```";
    NSString *html = [self renderMarkdown:md];

    // Should still have the code block, just won't be processed by Mermaid JS
    XCTAssertTrue([html containsString:@"language-mermaid"],
                  @"Code block should be preserved even when Mermaid is disabled");
}

@end
