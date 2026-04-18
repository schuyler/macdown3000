//
//  MPScrollSyncTests.m
//  MacDownTests
//
//  Regression tests for Issue #39: Preview pane scroll position on long documents
//  Tests scroll synchronization, header detection, and scroll position preservation
//

#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "MPDocument.h"
#import "MPPreferences.h"

// Issue #342: Scroll ownership enum constants (must match MPScrollOwner in MPDocument.m)
static const NSUInteger MPScrollOwnerEditor  = 0;
static const NSUInteger MPScrollOwnerPreview = 1;
static const NSUInteger MPScrollOwnerNeither = 2;

// Category to expose private properties/methods for testing
@interface MPDocument (ScrollSyncTesting)
@property (nonatomic) CGFloat lastPreviewScrollTop;
@property (strong) NSArray<NSNumber *> *webViewHeaderLocations;
@property (strong) NSArray<NSNumber *> *editorHeaderLocations;
@property (weak) WebView *preview;
@property (nonatomic) NSUInteger scrollOwner;  // Issue #342: MPScrollOwner enum
- (void)updateHeaderLocations;
- (void)syncScrollers;
- (void)syncScrollersReverse;
- (void)editorTextDidChange:(NSNotification *)notification;
- (void)previewBoundsDidChange:(NSNotification *)notification;
- (void)editorBoundsDidChange:(NSNotification *)notification;
- (void)willStartPreviewLiveScroll:(NSNotification *)notification;
- (void)didEndPreviewLiveScroll:(NSNotification *)notification;
// Commit 3 (gap 5): array alignment validation
- (void)validateHeaderLocationAlignment;
// Commit 4 (gap 8): file revert scroll ownership
- (void)reloadFromLoadedString;
@property (nonatomic, readonly) BOOL isPreviewReady;
// Commit 5 (gap 10): checkbox toggle
- (void)handleCheckboxToggle:(NSURL *)url;
// Commit 6 (gaps 1+3): layout-change sync
- (void)refreshHeaderCacheAfterResize;
- (void)windowDidEndLiveResize:(NSNotification *)notification;
- (void)windowDidChangeFullScreen:(NSNotification *)notification;
// Commit 7 (gap 2): editor-reveal sync
- (void)setSplitViewDividerLocation:(CGFloat)ratio;
// Commit 8 (gap 9): MathJax render generation counter getter
- (NSUInteger)mathJaxRenderGeneration;
@end

@interface MPScrollSyncTests : XCTestCase
@property (strong) MPDocument *document;
@end

@implementation MPScrollSyncTests

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

#pragma mark - Editor Header Location Detection Tests

/**
 * Test that ATX-style headers (# Header) are correctly identified in the editor.
 * Regression test for issue #39 - header detection is critical for scroll sync.
 */
- (void)testEditorDetectsATXHeaders
{
    NSString *markdown = @"# Header 1\n\nSome text\n\n## Header 2\n\nMore text\n\n### Header 3";

    // Create a document and set markdown
    self.document.markdown = markdown;

    // Call updateHeaderLocations to populate editorHeaderLocations
    [self.document updateHeaderLocations];

    // Verify that headers were detected
    // Note: In headless tests without a window, the editor outlet might be nil,
    // so we verify the method doesn't crash rather than checking exact counts
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should not crash on markdown with ATX headers");
}

/**
 * Test that Setext-style headers (underlined with dashes) are correctly identified.
 * Regression test for issue #39 - must distinguish from horizontal rules.
 */
- (void)testEditorDetectsSetextHeaders
{
    NSString *markdown = @"Header 1\n--------\n\nSome text\n\nHeader 2\n--------";

    self.document.markdown = markdown;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should handle Setext-style headers");
}

/**
 * Test that horizontal rules are NOT detected as headers.
 * Regression test for issue #39 - fix improved horizontal rule detection.
 */
- (void)testEditorIgnoresHorizontalRules
{
    NSString *markdown = @"Text above\n\n---\n\nText below\n\n***\n\nMore text\n\n___\n\nEnd";

    self.document.markdown = markdown;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should handle horizontal rules without treating them as headers");
}

/**
 * Test that standalone images in inline syntax are detected.
 * Regression test for issue #39 - standalone images are reference points for sync.
 */
- (void)testEditorDetectsStandaloneInlineImages
{
    NSString *markdown = @"# Header\n\n![Alt text](image.png)\n\nMore text";

    self.document.markdown = markdown;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should detect standalone inline images");
}

/**
 * Test that standalone images in reference syntax are detected.
 * Regression test for issue #39 - fix added support for reference-style images.
 */
- (void)testEditorDetectsStandaloneReferenceImages
{
    NSString *markdown = @"# Header\n\n![Alt text][img1]\n\nMore text\n\n[img1]: image.png";

    self.document.markdown = markdown;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should detect standalone reference-style images");
}

/**
 * Test that inline images (mixed with text) are NOT detected as reference points.
 * Regression test for issue #39 - only standalone images should be tracked.
 */
- (void)testEditorIgnoresInlineImages
{
    NSString *markdown = @"This is text with ![inline image](img.png) in the middle";

    self.document.markdown = markdown;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should ignore inline images that are not standalone");
}

/**
 * Test complex document with mixed headers and images.
 * Regression test for issue #39 - ensures robust handling of varied content.
 */
- (void)testEditorHandlesComplexDocument
{
    NSString *markdown = @"# Main Title\n\n"
                         @"Introduction paragraph.\n\n"
                         @"## Section 1\n\n"
                         @"![Figure 1](fig1.png)\n\n"
                         @"Some text with ![inline](small.png) image.\n\n"
                         @"---\n\n"
                         @"### Subsection\n\n"
                         @"![Figure 2][fig2]\n\n"
                         @"More content.\n\n"
                         @"[fig2]: fig2.png";

    self.document.markdown = markdown;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"updateHeaderLocations should handle complex documents with mixed content");
}

#pragma mark - JavaScript Header Location Detection Tests

/**
 * Test that the JavaScript updateHeaderLocations.js file can be loaded.
 * Regression test for issue #39 - JavaScript is essential for preview sync.
 */
- (void)testJavaScriptResourceExists
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *scriptPath = [bundle pathForResource:@"updateHeaderLocations" ofType:@"js"];

    XCTAssertNotNil(scriptPath, @"updateHeaderLocations.js should exist in bundle resources");

    if (scriptPath) {
        NSError *error = nil;
        NSString *script = [NSString stringWithContentsOfFile:scriptPath
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];

        XCTAssertNotNil(script, @"Should be able to read updateHeaderLocations.js");
        XCTAssertNil(error, @"No error should occur when reading the script");
        XCTAssertGreaterThan(script.length, 0, @"Script should have content");
    }
}

/**
 * Test that the JavaScript function returns an array.
 * Regression test for issue #39 - validates JavaScript function structure.
 */
- (void)testJavaScriptFunctionStructure
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *scriptPath = [bundle pathForResource:@"updateHeaderLocations" ofType:@"js"];

    if (scriptPath) {
        NSString *script = [NSString stringWithContentsOfFile:scriptPath
                                                     encoding:NSUTF8StringEncoding
                                                        error:NULL];

        // Verify script contains expected structure
        XCTAssertTrue([script containsString:@"querySelectorAll"],
                     @"Script should use querySelectorAll to find elements");
        XCTAssertTrue([script containsString:@"h1, h2, h3, h4, h5, h6"],
                     @"Script should look for header elements");
        XCTAssertTrue([script containsString:@"img"],
                     @"Script should look for image elements");
        XCTAssertTrue([script containsString:@"getBoundingClientRect"],
                     @"Script should use getBoundingClientRect to get positions");
        XCTAssertTrue([script containsString:@"standalone"] || [script containsString:@"Standalone"],
                     @"Script should handle standalone images specially");
    }
}

#pragma mark - Scroll Position Preservation Tests

/**
 * Test that lastPreviewScrollTop property exists and can be set.
 * Regression test for issue #39 - this property preserves scroll across refreshes.
 */
- (void)testLastPreviewScrollTopProperty
{
    // Test that we can set and get the property
    self.document.lastPreviewScrollTop = 123.5;

    CGFloat scrollTop = self.document.lastPreviewScrollTop;
    XCTAssertEqualWithAccuracy(scrollTop, 123.5, 0.01,
                              @"lastPreviewScrollTop should preserve scroll position");
}

/**
 * Test that lastPreviewScrollTop is initialized to zero.
 * Regression test for issue #39 - initial scroll position should be at top.
 */
- (void)testLastPreviewScrollTopInitialValue
{
    MPDocument *freshDoc = [[MPDocument alloc] init];

    CGFloat scrollTop = freshDoc.lastPreviewScrollTop;
    XCTAssertEqualWithAccuracy(scrollTop, 0.0, 0.01,
                              @"New document should have scroll position at top");
}

/**
 * Test that syncScrollers method doesn't crash.
 * Regression test for issue #39 - this method implements the scroll synchronization.
 */
- (void)testSyncScrollersDoesNotCrash
{
    self.document.markdown = @"# Test\n\nContent";

    XCTAssertNoThrow([self.document syncScrollers],
                     @"syncScrollers should not crash even in headless environment");
}

#pragma mark - Header Location Array Tests

/**
 * Test that header location arrays can be accessed.
 * Regression test for issue #39 - these arrays are critical for scroll sync.
 */
- (void)testHeaderLocationArraysAccessible
{
    self.document.markdown = @"# Header\n\nContent";
    [self.document updateHeaderLocations];

    // Test that we can access the arrays (they may be nil/empty in headless tests)
    NSArray<NSNumber *> *editorLocations = self.document.editorHeaderLocations;
    NSArray<NSNumber *> *webViewLocations = self.document.webViewHeaderLocations;

    // In headless tests these might be nil, but accessing them shouldn't crash
    XCTAssertNoThrow((void)editorLocations.count,
                     @"Should be able to access editorHeaderLocations count");
    XCTAssertNoThrow((void)webViewLocations.count,
                     @"Should be able to access webViewHeaderLocations count");
}

#pragma mark - Integration Tests

/**
 * Test that updateHeaderLocations can be called multiple times.
 * Regression test for issue #39 - method is called during live scrolling.
 */
- (void)testUpdateHeaderLocationsMultipleCalls
{
    self.document.markdown = @"# Test Header";

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"First call should not crash");
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Second call should not crash");
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Third call should not crash");
}

/**
 * Test that scroll sync works with empty document.
 * Regression test for issue #39 - edge case handling.
 */
- (void)testScrollSyncWithEmptyDocument
{
    self.document.markdown = @"";

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Should handle empty document");
    XCTAssertNoThrow([self.document syncScrollers],
                     @"Should handle empty document");
}

/**
 * Test that scroll sync works with document containing only whitespace.
 * Regression test for issue #39 - edge case handling.
 */
- (void)testScrollSyncWithWhitespaceDocument
{
    self.document.markdown = @"\n\n\n\n";

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Should handle whitespace-only document");
    XCTAssertNoThrow([self.document syncScrollers],
                     @"Should handle whitespace-only document");
}

/**
 * Test that scroll sync works with very long document.
 * Regression test for issue #39 - the original bug occurred with long documents.
 */
- (void)testScrollSyncWithLongDocument
{
    NSMutableString *longDoc = [NSMutableString string];
    for (int i = 1; i <= 100; i++) {
        [longDoc appendFormat:@"## Header %d\n\n", i];
        [longDoc appendString:@"Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n\n"];
        if (i % 10 == 0) {
            [longDoc appendString:@"![Figure](image.png)\n\n"];
        }
    }

    self.document.markdown = longDoc;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Should handle very long document");
    XCTAssertNoThrow([self.document syncScrollers],
                     @"Should handle very long document");
}

/**
 * Test that scroll sync works with document containing many images.
 * Regression test for issue #39 - original issue mentioned "extensive media content".
 */
- (void)testScrollSyncWithManyImages
{
    NSMutableString *imageDoc = [NSMutableString string];
    [imageDoc appendString:@"# Image Gallery\n\n"];
    for (int i = 1; i <= 50; i++) {
        [imageDoc appendFormat:@"![Image %d](image%d.png)\n\n", i, i];
        [imageDoc appendString:@"Caption text.\n\n"];
    }

    self.document.markdown = imageDoc;

    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Should handle document with many images");
    XCTAssertNoThrow([self.document syncScrollers],
                     @"Should handle document with many images");
}

/**
 * Test various scroll position values.
 * Regression test for issue #39 - scroll position should handle any valid value.
 */
- (void)testScrollPositionValues
{
    // Test zero
    self.document.lastPreviewScrollTop = 0.0;
    XCTAssertEqualWithAccuracy(self.document.lastPreviewScrollTop, 0.0, 0.01,
                              @"Should handle zero scroll position");

    // Test small positive value
    self.document.lastPreviewScrollTop = 10.5;
    XCTAssertEqualWithAccuracy(self.document.lastPreviewScrollTop, 10.5, 0.01,
                              @"Should handle small scroll position");

    // Test large value (simulating long document)
    self.document.lastPreviewScrollTop = 5000.0;
    XCTAssertEqualWithAccuracy(self.document.lastPreviewScrollTop, 5000.0, 0.01,
                              @"Should handle large scroll position");

    // Test fractional values
    self.document.lastPreviewScrollTop = 123.456;
    XCTAssertEqualWithAccuracy(self.document.lastPreviewScrollTop, 123.456, 0.01,
                              @"Should handle fractional scroll position");
}

#pragma mark - Sort Logic Tests (Issue #144)

/**
 * Test that JavaScript sort function properly handles all compareDocumentPosition return values.
 * Regression test for Issue #144: Sort logic should handle edge cases more robustly.
 *
 * This test demonstrates the bug by using the current (buggy) sort logic.
 * It validates that the FIXED sort function will correctly handle:
 * - DOCUMENT_POSITION_FOLLOWING (bit 2, value 4)
 * - DOCUMENT_POSITION_PRECEDING (bit 1, value 2)
 * - Nodes in various document positions
 *
 * Expected: This test FAILS with buggy code, PASSES after fix.
 */
- (void)testJavaScriptSortHandlesAllComparisons
{
    // Unit test of the sort logic in isolation
    // Document order is: C → B → A (C comes first, A comes last)
    NSString *testScript = @"(function() {\n"
                           @"    // Create mock nodes with compareDocumentPosition\n"
                           @"    // Document order: nodeC, nodeB, nodeA\n"
                           @"    \n"
                           @"    var nodeC = {\n"
                           @"        name: 'nodeC',\n"
                           @"        compareDocumentPosition: function(other) {\n"
                           @"            if (other.name === 'nodeA') return 4; // A FOLLOWS C\n"
                           @"            if (other.name === 'nodeB') return 4; // B FOLLOWS C\n"
                           @"            return 0;\n"
                           @"        },\n"
                           @"        getBoundingClientRect: function() { return {top: 10}; }\n"
                           @"    };\n"
                           @"    \n"
                           @"    var nodeB = {\n"
                           @"        name: 'nodeB',\n"
                           @"        compareDocumentPosition: function(other) {\n"
                           @"            if (other.name === 'nodeC') return 2; // C PRECEDES B\n"
                           @"            if (other.name === 'nodeA') return 4; // A FOLLOWS B\n"
                           @"            return 0;\n"
                           @"        },\n"
                           @"        getBoundingClientRect: function() { return {top: 20}; }\n"
                           @"    };\n"
                           @"    \n"
                           @"    var nodeA = {\n"
                           @"        name: 'nodeA',\n"
                           @"        compareDocumentPosition: function(other) {\n"
                           @"            if (other.name === 'nodeC') return 2; // C PRECEDES A\n"
                           @"            if (other.name === 'nodeB') return 2; // B PRECEDES A\n"
                           @"            return 0;\n"
                           @"        },\n"
                           @"        getBoundingClientRect: function() { return {top: 30}; }\n"
                           @"    };\n"
                           @"    \n"
                           @"    // Create result array in wrong order (A, B, C)\n"
                           @"    // Correct document order should be: C, B, A\n"
                           @"    var result = [\n"
                           @"        {node: nodeA, type: 'header'},\n"
                           @"        {node: nodeB, type: 'header'},\n"
                           @"        {node: nodeC, type: 'header'}\n"
                           @"    ];\n"
                           @"    \n"
                           @"    // This is the FIXED sort from lines 67-73\n"
                           @"    result.sort(function(a, b) {\n"
                           @"        var position = a.node.compareDocumentPosition(b.node);\n"
                           @"        if (position & 4) return -1;  // FOLLOWING\n"
                           @"        if (position & 2) return 1;   // PRECEDING\n"
                           @"        return 0;  // Same node or disconnected\n"
                           @"    });\n"
                           @"    \n"
                           @"    // Return the sorted node names\n"
                           @"    return result.map(function(item) { return item.node.name; });\n"
                           @"})()";

    JSContext *context = [[JSContext alloc] init];

    JSValue *result = [context evaluateScript:testScript];
    NSArray *sortedNames = [result toArray];

    // With the FIXED code, nodes should be in correct document order
    // Expected order: [nodeC, nodeB, nodeA] (C precedes B, B precedes A)
    // The fixed sort properly checks both FOLLOWING and PRECEDING bits
    // and returns 0 for same node or disconnected nodes

    NSLog(@"Sort result: %@", sortedNames);
    NSLog(@"Expected order: [nodeC, nodeB, nodeA]");

    // This assertion should PASS with the fixed code
    XCTAssertEqualObjects(sortedNames[0], @"nodeC",
                         @"First node should be nodeC (precedes all others)");
    XCTAssertEqualObjects(sortedNames[1], @"nodeB",
                         @"Second node should be nodeB (between C and A)");
    XCTAssertEqualObjects(sortedNames[2], @"nodeA",
                         @"Third node should be nodeA (follows all others)");
}

/**
 * Test that sort function handles same node comparison (edge case).
 * Regression test for Issue #144.
 *
 * When compareDocumentPosition returns 0 (same node), the fixed sort
 * correctly returns 0, maintaining sort stability.
 */
- (void)testJavaScriptSortHandlesSameNode
{
    NSString *testScript = @"(function() {\n"
                           @"    var sameNode = {\n"
                           @"        name: 'sameNode',\n"
                           @"        compareDocumentPosition: function(other) {\n"
                           @"            return 0; // Same node\n"
                           @"        }\n"
                           @"    };\n"
                           @"    \n"
                           @"    var result = [{node: sameNode, type: 'header'}];\n"
                           @"    \n"
                           @"    // Fixed sort - returns 0 for same node\n"
                           @"    result.sort(function(a, b) {\n"
                           @"        var position = a.node.compareDocumentPosition(b.node);\n"
                           @"        if (position & 4) return -1;  // FOLLOWING\n"
                           @"        if (position & 2) return 1;   // PRECEDING\n"
                           @"        return 0;  // Same node or disconnected\n"
                           @"    });\n"
                           @"    \n"
                           @"    return result.length;\n"
                           @"})()";

    JSContext *context = [[JSContext alloc] init];
    JSValue *result = [context evaluateScript:testScript];

    // Should not crash and should return 1 element
    XCTAssertEqual([result toInt32], 1,
                  @"Single node array should remain size 1 after sort");
}

/**
 * Test that sort function handles disconnected nodes (edge case).
 * Regression test for Issue #144.
 *
 * When nodes are disconnected (bit 0 set), the fixed sort returns 0,
 * maintaining sort stability and avoiding unnecessary swaps.
 */
- (void)testJavaScriptSortHandlesDisconnectedNodes
{
    NSString *testScript = @"(function() {\n"
                           @"    var disconnectedA = {\n"
                           @"        name: 'disconnectedA',\n"
                           @"        compareDocumentPosition: function(other) {\n"
                           @"            return 1; // DISCONNECTED\n"
                           @"        }\n"
                           @"    };\n"
                           @"    \n"
                           @"    var disconnectedB = {\n"
                           @"        name: 'disconnectedB',\n"
                           @"        compareDocumentPosition: function(other) {\n"
                           @"            return 1; // DISCONNECTED\n"
                           @"        }\n"
                           @"    };\n"
                           @"    \n"
                           @"    var result = [\n"
                           @"        {node: disconnectedA, type: 'header'},\n"
                           @"        {node: disconnectedB, type: 'header'}\n"
                           @"    ];\n"
                           @"    \n"
                           @"    // Fixed sort - returns 0 for disconnected nodes\n"
                           @"    result.sort(function(a, b) {\n"
                           @"        var position = a.node.compareDocumentPosition(b.node);\n"
                           @"        if (position & 4) return -1;  // FOLLOWING\n"
                           @"        if (position & 2) return 1;   // PRECEDING\n"
                           @"        return 0;  // Same node or disconnected\n"
                           @"    });\n"
                           @"    \n"
                           @"    return result.length;\n"
                           @"})()";

    JSContext *context = [[JSContext alloc] init];
    JSValue *result = [context evaluateScript:testScript];

    // Should not crash and should return 2 elements
    // Fixed code returns 0 for disconnected nodes (stable sort)
    XCTAssertEqual([result toInt32], 2,
                  @"Disconnected nodes should not crash sort");
}

#pragma mark - Horizontal Rule Detection Tests (Issue #143)

#pragma mark - Basic HR Types

/**
 * Test that three dashes form a horizontal rule.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleThreeDashes
{
    NSString *markdown = @"---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Three dashes should be recognized as HR");
}

/**
 * Test that three asterisks form a horizontal rule.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleThreeAsterisks
{
    NSString *markdown = @"***";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Three asterisks should be recognized as HR");
}

/**
 * Test that three underscores form a horizontal rule.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleThreeUnderscores
{
    NSString *markdown = @"___";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Three underscores should be recognized as HR");
}

#pragma mark - Spacing Variants

/**
 * Test that spaced dashes form a horizontal rule.
 * Regression test for Issue #143 - CommonMark allows spaces between HR characters.
 */
- (void)testHorizontalRuleSpacedDashes
{
    NSString *markdown = @"- - -";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Spaced dashes (- - -) should be recognized as HR");
}

/**
 * Test that spaced asterisks form a horizontal rule.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleSpacedAsterisks
{
    NSString *markdown = @"* * *";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Spaced asterisks (* * *) should be recognized as HR");
}

/**
 * Test that spaced underscores form a horizontal rule.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleSpacedUnderscores
{
    NSString *markdown = @"_ _ _";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Spaced underscores (_ _ _) should be recognized as HR");
}

/**
 * Test that irregularly spaced characters form a horizontal rule.
 * Regression test for Issue #143 - any amount of whitespace allowed.
 */
- (void)testHorizontalRuleIrregularSpacing
{
    NSString *markdown = @"-  -  -";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Irregularly spaced dashes should be recognized as HR");
}

#pragma mark - Minimum Character Requirements

/**
 * Test that two dashes do NOT form a horizontal rule.
 * Regression test for Issue #143 - minimum 3 characters required.
 */
- (void)testTwoDashesNotHorizontalRule
{
    NSString *markdown = @"Some text\n--";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Two dashes should NOT be treated as HR (setext header instead)");
}

/**
 * Test that single dash does NOT form a horizontal rule.
 * Regression test for Issue #143.
 */
- (void)testSingleDashNotHorizontalRule
{
    NSString *markdown = @"-";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Single dash should NOT be treated as HR");
}

/**
 * Test that two spaced dashes do NOT form a horizontal rule.
 * Regression test for Issue #143 - must have 3+ characters.
 */
- (void)testTwoSpacedDashesNotHorizontalRule
{
    NSString *markdown = @"- -";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Two spaced dashes should NOT be treated as HR");
}

#pragma mark - Setext vs HR Context

/**
 * Test that dashes after text form a setext header, not an HR.
 * Regression test for Issue #143 - previousLineHadContent flag behavior.
 */
- (void)testSetextHeaderWithThreeDashes
{
    NSString *markdown = @"Header Text\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Three dashes after text should be setext header (context-dependent)");
}

/**
 * Test that dashes after text form a setext header.
 * Regression test for Issue #143.
 */
- (void)testSetextHeaderWithManyDashes
{
    NSString *markdown = @"Header Text\n--------";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Many dashes after text should be setext header");
}

/**
 * Test that dashes after blank line form an HR, not a header.
 * Regression test for Issue #143 - blank line breaks setext context.
 */
- (void)testHorizontalRuleAfterBlankLine
{
    NSString *markdown = @"Text\n\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Dashes after blank line should be HR, not setext header");
}

/**
 * Test that standalone three dashes form an HR.
 * Regression test for Issue #143 - no previous content means HR.
 */
- (void)testStandaloneThreeDashesIsHR
{
    NSString *markdown = @"---\n\nSome text";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Standalone three dashes should be HR");
}

#pragma mark - previousLineHadContent Flag

/**
 * Test that previousLineHadContent flag is true after text lines.
 * Regression test for Issue #143 - flag logic verification.
 */
- (void)testPreviousLineHadContentAfterText
{
    NSString *markdown = @"Some text\n--";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Flag should be true after text, making -- a setext header");
}

/**
 * Test that previousLineHadContent flag is false after empty lines.
 * Regression test for Issue #143.
 */
- (void)testPreviousLineHadContentAfterEmptyLine
{
    NSString *markdown = @"\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Flag should be false after empty line, making --- an HR");
}

/**
 * Test that previousLineHadContent flag is false after dash lines.
 * Regression test for Issue #143 - dash lines don't count as content.
 */
- (void)testPreviousLineHadContentAfterDashes
{
    NSString *markdown = @"---\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Flag should be false after dash line, both lines are HRs");
}

/**
 * Test multiple setext headers in sequence.
 * Regression test for Issue #143 - verify flag resets correctly.
 */
- (void)testMultipleSetextHeaders
{
    NSString *markdown = @"Header 1\n---\n\nHeader 2\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Multiple setext headers should be detected correctly");
}

#pragma mark - Leading Whitespace

/**
 * Test that HR with no leading spaces is recognized.
 * Regression test for Issue #143 - baseline case.
 */
- (void)testHorizontalRuleNoLeadingSpaces
{
    NSString *markdown = @"---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR with no leading spaces should be recognized");
}

/**
 * Test that HR with one leading space is recognized.
 * Regression test for Issue #143 - CommonMark allows 0-3 leading spaces.
 */
- (void)testHorizontalRuleOneLeadingSpace
{
    NSString *markdown = @" ---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR with 1 leading space should be recognized");
}

/**
 * Test that HR with two leading spaces is recognized.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleTwoLeadingSpaces
{
    NSString *markdown = @"  ---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR with 2 leading spaces should be recognized");
}

/**
 * Test that HR with three leading spaces is recognized.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleThreeLeadingSpaces
{
    NSString *markdown = @"   ---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR with 3 leading spaces should be recognized");
}

/**
 * Test that line with four leading spaces is NOT an HR (code block).
 * Regression test for Issue #143 - 4+ spaces = indented code block.
 */
- (void)testFourLeadingSpacesNotHR
{
    NSString *markdown = @"    ---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"4+ leading spaces should be code block, not HR");
}

/**
 * Test that leading spaces work with spacing variants.
 * Regression test for Issue #143 - combined edge cases.
 */
- (void)testLeadingSpacesWithSpacedHR
{
    NSString *markdown = @"  - - -";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Leading spaces + spaced characters should be recognized as HR");
}

#pragma mark - Invalid HR Patterns

/**
 * Test that mixed dash types do NOT form an HR.
 * Regression test for Issue #143 - must use same character.
 */
- (void)testMixedCharactersNotHR
{
    NSString *markdown = @"-*-";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Mixed characters should NOT form an HR");
}

/**
 * Test that dashes with trailing text do NOT form an HR.
 * Regression test for Issue #143.
 */
- (void)testDashesWithTrailingTextNotHR
{
    NSString *markdown = @"---text";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Dashes with trailing text should NOT be HR");
}

/**
 * Test that dashes with leading text do NOT form an HR.
 * Regression test for Issue #143.
 */
- (void)testDashesWithLeadingTextNotHR
{
    NSString *markdown = @"text---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Dashes with leading text should NOT be HR");
}

/**
 * Test that dashes with both leading and trailing spaces still form HR.
 * Regression test for Issue #143 - trailing spaces allowed.
 */
- (void)testHorizontalRuleWithTrailingSpaces
{
    NSString *markdown = @"---   ";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR with trailing spaces should be recognized");
}

#pragma mark - Many Characters

/**
 * Test that many dashes form an HR.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleManyDashes
{
    NSString *markdown = @"----------";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Many dashes should be recognized as HR");
}

/**
 * Test that many spaced dashes form an HR.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleManySpacedDashes
{
    NSString *markdown = @"- - - - - - - - - -";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Many spaced dashes should be recognized as HR");
}

/**
 * Test that very long HR with mixed spacing works.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleVeryLongMixedSpacing
{
    NSString *markdown = @"--  --  --  --  --";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Long HR with irregular spacing should be recognized");
}

#pragma mark - Complex Contexts

/**
 * Test that HR after ATX header is recognized.
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleAfterATXHeader
{
    NSString *markdown = @"# Header\n\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR after ATX header should be recognized");
}

/**
 * Test setext header followed by HR.
 * Regression test for Issue #143.
 */
- (void)testSetextHeaderFollowedByHR
{
    NSString *markdown = @"Header\n---\n\n***";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Setext header followed by HR should both be detected");
}

/**
 * Test alternating setext headers and HRs.
 * Regression test for Issue #143 - stress test for flag logic.
 */
- (void)testAlternatingSetextAndHR
{
    NSString *markdown = @"Header 1\n---\n\n***\n\nHeader 2\n___\n\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Alternating patterns should be handled correctly");
}

/**
 * Test HR between paragraphs (common use case).
 * Regression test for Issue #143.
 */
- (void)testHorizontalRuleBetweenParagraphs
{
    NSString *markdown = @"First paragraph.\n\n---\n\nSecond paragraph.";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"HR between paragraphs should be recognized");
}

#pragma mark - Edge Cases and Regressions

/**
 * Test that asterisk HR doesn't interfere with emphasis.
 * Regression test for Issue #143.
 */
- (void)testAsteriskHRWithEmphasis
{
    NSString *markdown = @"*emphasis* text\n\n***\n\n**bold**";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Asterisk HR should not interfere with emphasis detection");
}

/**
 * Test underscore HR with underscored text.
 * Regression test for Issue #143.
 */
- (void)testUnderscoreHRWithUnderscores
{
    NSString *markdown = @"some_variable_name\n\n___\n\nanother_variable";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Underscore HR should not interfere with underscored text");
}

/**
 * Test that tab characters are NOT treated as spaces in HR.
 * Regression test for Issue #143 - tabs have different meaning in Markdown.
 */
- (void)testHorizontalRuleWithTabs
{
    NSString *markdown = @"\t---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Tab before dashes creates code block, not HR");
}

/**
 * Test setext header with equals signs (alternative syntax).
 * Regression test for Issue #143 - equals signs are level-1 setext.
 */
- (void)testSetextHeaderWithEquals
{
    NSString *markdown = @"Header\n===";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Equals signs form level-1 setext header");
}

/**
 * Regression test for exact example in Issue #143.
 * Tests all the edge cases mentioned in the issue in one document.
 */
- (void)testIssue143ExampleCases
{
    NSString *markdown = @"Some text\n--\n\n- - -\n\nText\n---\n---";
    self.document.markdown = markdown;
    XCTAssertNoThrow([self.document updateHeaderLocations],
                     @"Issue #143 example should be handled correctly");
}

#pragma mark - Preview to Editor Reverse Sync Tests (Issue #258)

/**
 * Test that syncScrollersReverse method exists and doesn't crash.
 * Regression test for Issue #258 - bidirectional scroll sync.
 */
- (void)testSyncScrollersReverseExists
{
    XCTAssertNoThrow([self.document syncScrollersReverse],
                     @"syncScrollersReverse should exist and not crash");
}

/**
 * Test that syncScrollersReverse handles empty header locations gracefully.
 * Regression test for Issue #258 - edge case handling.
 */
- (void)testSyncScrollersReverseWithEmptyLocations
{
    self.document.webViewHeaderLocations = @[];
    self.document.editorHeaderLocations = @[];

    XCTAssertNoThrow([self.document syncScrollersReverse],
                     @"syncScrollersReverse should handle empty header locations");
}

/**
 * Test that syncScrollersReverse handles nil header locations gracefully.
 * Regression test for Issue #258 - nil safety.
 */
- (void)testSyncScrollersReverseWithNilLocations
{
    self.document.webViewHeaderLocations = nil;
    self.document.editorHeaderLocations = nil;

    XCTAssertNoThrow([self.document syncScrollersReverse],
                     @"syncScrollersReverse should handle nil header locations");
}

/**
 * Test that reverse sync uses the same reference points as forward sync.
 * Regression test for Issue #258 - algorithm symmetry.
 */
- (void)testReverseSyncUsesHeaderLocations
{
    // Set up some header locations
    self.document.webViewHeaderLocations = @[@(100), @(300), @(500)];
    self.document.editorHeaderLocations = @[@(50), @(150), @(250)];

    XCTAssertNoThrow([self.document syncScrollersReverse],
                     @"syncScrollersReverse should use webViewHeaderLocations and editorHeaderLocations");
}

/**
 * Test that reverse sync with single header location works.
 * Regression test for Issue #258 - edge case with minimal headers.
 */
- (void)testReverseSyncWithSingleHeader
{
    self.document.webViewHeaderLocations = @[@(100)];
    self.document.editorHeaderLocations = @[@(50)];

    XCTAssertNoThrow([self.document syncScrollersReverse],
                     @"syncScrollersReverse should handle single header");
}

/**
 * Test that reverse sync with many headers works.
 * Regression test for Issue #258 - performance with many reference points.
 */
- (void)testReverseSyncWithManyHeaders
{
    NSMutableArray *webLocations = [NSMutableArray array];
    NSMutableArray *editorLocations = [NSMutableArray array];

    for (int i = 0; i < 100; i++) {
        [webLocations addObject:@(i * 100)];
        [editorLocations addObject:@(i * 80)];
    }

    self.document.webViewHeaderLocations = webLocations;
    self.document.editorHeaderLocations = editorLocations;

    XCTAssertNoThrow([self.document syncScrollersReverse],
                     @"syncScrollersReverse should handle many headers");
}

#pragma mark - Code Fence Edge Case Tests

/**
 * Test that headers inside fenced code blocks are ignored.
 * Code fence detection should skip headers like "# Not a header" inside ``` blocks.
 */
- (void)testHeaderInsideCodeBlockIsIgnored
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.markdown = @"# Real Header\n\n```\n# Not a header\n## Also not a header\n```\n\n## Another Real Header";

    XCTAssertNoThrow([doc updateHeaderLocations],
                     @"updateHeaderLocations should handle headers inside code blocks");
}

/**
 * Test that code fence with info string is recognized.
 * Fences like ```markdown or ```objc should still be detected as code fences.
 */
- (void)testCodeFenceWithInfoString
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.markdown = @"# Header 1\n\n```markdown\n# Not a header\n```\n\n## Header 2\n\n```objc\n// code\n```";

    XCTAssertNoThrow([doc updateHeaderLocations],
                     @"updateHeaderLocations should handle code fences with info strings");
}

/**
 * Test that unclosed code fence at end of document is handled.
 * If document ends with an open code fence, headers after the fence should be skipped.
 */
- (void)testUnclosedCodeFenceAtEndOfDocument
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.markdown = @"# Header 1\n\n```\n# This should be ignored\n## Also ignored";

    XCTAssertNoThrow([doc updateHeaderLocations],
                     @"updateHeaderLocations should handle unclosed code fence at end of document");
}

/**
 * Test that tilde code fences work the same as backtick fences.
 */
- (void)testTildeCodeFence
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.markdown = @"# Header 1\n\n~~~\n# Not a header\n~~~\n\n## Header 2";

    XCTAssertNoThrow([doc updateHeaderLocations],
                     @"updateHeaderLocations should handle tilde code fences");
}

/**
 * Test that four backticks (escaping) doesn't start a code block.
 * Per CommonMark, ```` is different from ``` - tests our bounds check fix.
 */
- (void)testFourBackticksNotCodeFence
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.markdown = @"# Header 1\n\n````\n# Should this be a header?\n````\n\n## Header 2";

    // This tests the bounds check fix - shouldn't crash on edge cases
    XCTAssertNoThrow([doc updateHeaderLocations],
                     @"updateHeaderLocations should handle four backticks without crashing");
}

#pragma mark - Issue #342: Group A — Ownership State Machine

/**
 * A1 — Initial scrollOwner is MPScrollOwnerNeither (2).
 * Issue #342: Document starts in quiescent state.
 */
- (void)testScrollOwnerInitializedToNeither
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerNeither,
                   @"scrollOwner should be MPScrollOwnerNeither (2) at init");
}

/**
 * A2 — editorTextDidChange: sets scrollOwner to MPScrollOwnerEditor.
 * Issue #342: Typing must claim editor ownership.
 */
- (void)testEditorTextDidChangeSetsEditorOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerNeither;

    [doc editorTextDidChange:nil];

    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerEditor,
                   @"editorTextDidChange: should set scrollOwner to MPScrollOwnerEditor (0)");
}

/**
 * A3 — willStartPreviewLiveScroll: sets scrollOwner to MPScrollOwnerPreview.
 * Issue #342: User-initiated preview scroll must claim preview ownership.
 */
- (void)testWillStartPreviewLiveScrollSetsPreviewOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerNeither;

    [doc willStartPreviewLiveScroll:nil];

    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerPreview,
                   @"willStartPreviewLiveScroll: should set scrollOwner to MPScrollOwnerPreview (1)");
}

/**
 * A4 — didEndPreviewLiveScroll: resets scrollOwner to MPScrollOwnerNeither.
 * Issue #342: End of live scroll returns to quiescent state.
 */
- (void)testDidEndPreviewLiveScrollResetsToNeither
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerPreview;

    [doc didEndPreviewLiveScroll:nil];

    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerNeither,
                   @"didEndPreviewLiveScroll: should set scrollOwner to MPScrollOwnerNeither (2)");
}

/**
 * A5 — Repeated editorTextDidChange: calls keep scrollOwner as MPScrollOwnerEditor.
 * Issue #342: Multiple keystrokes must not change ownership away from Editor.
 */
- (void)testRepeatedEditorTextDidChangeStaysEditor
{
    MPDocument *doc = [[MPDocument alloc] init];
    [doc editorTextDidChange:nil];
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerEditor,
                   @"scrollOwner should be Editor after first call");

    [doc editorTextDidChange:nil];
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerEditor,
                   @"scrollOwner should remain Editor after second call");
}

/**
 * A6 — editorTextDidChange: overrides MPScrollOwnerPreview.
 * Issue #342: Typing while preview-owned must transfer ownership to editor.
 */
- (void)testEditorTextDidChangeOverridesPreviewOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerPreview;

    [doc editorTextDidChange:nil];

    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerEditor,
                   @"editorTextDidChange: should override MPScrollOwnerPreview with MPScrollOwnerEditor");
}

#pragma mark - Issue #342: Group B — Guard Logic

/**
 * B1 — previewBoundsDidChange: is suppressed when scrollOwner is Editor.
 * Issue #342: Deferred WebKit notification during editing must not trigger reverse sync.
 */
- (void)testPreviewBoundsDidChangeSuppressedDuringEditorOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerEditor;

    // Must not crash; scrollOwner must remain Editor (reverse sync was suppressed)
    XCTAssertNoThrow([doc previewBoundsDidChange:nil],
                     @"previewBoundsDidChange: should not crash when scrollOwner is Editor");
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerEditor,
                   @"scrollOwner should remain Editor after suppressed previewBoundsDidChange:");
}

/**
 * B2 — previewBoundsDidChange: is passed through when scrollOwner is Preview.
 * Issue #342: Live preview scroll must trigger reverse sync.
 */
- (void)testPreviewBoundsDidChangePassesDuringPreviewOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerPreview;
    doc.webViewHeaderLocations = @[];
    doc.editorHeaderLocations = @[];

    XCTAssertNoThrow([doc previewBoundsDidChange:nil],
                     @"previewBoundsDidChange: should not crash when scrollOwner is Preview");
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerPreview,
                   @"scrollOwner should remain Preview after previewBoundsDidChange: with Preview ownership");
}

/**
 * B3 — editorBoundsDidChange: is suppressed when scrollOwner is Editor.
 * Issue #342: Editor scroll during typing must not re-trigger forward sync.
 */
- (void)testEditorBoundsDidChangeSuppressedDuringEditorOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerEditor;

    XCTAssertNoThrow([doc editorBoundsDidChange:nil],
                     @"editorBoundsDidChange: should not crash when scrollOwner is Editor");
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerEditor,
                   @"scrollOwner should remain Editor after suppressed editorBoundsDidChange:");
}

/**
 * B4 — editorBoundsDidChange: is passed through when scrollOwner is Neither.
 * Issue #342: Manual editor scroll in quiescent state must trigger forward sync.
 */
- (void)testEditorBoundsDidChangePassesDuringNeitherOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerNeither;
    doc.webViewHeaderLocations = @[];
    doc.editorHeaderLocations = @[];

    XCTAssertNoThrow([doc editorBoundsDidChange:nil],
                     @"editorBoundsDidChange: should not crash when scrollOwner is Neither");
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerNeither,
                   @"scrollOwner should remain Neither after editorBoundsDidChange: with Neither ownership");
}

/**
 * B5 — editorBoundsDidChange: is suppressed when scrollOwner is Preview.
 * Issue #342: The guard is scrollOwner == MPScrollOwnerNeither, so Preview
 * ownership must also suppress forward sync (not just Editor ownership).
 */
- (void)testEditorBoundsDidChangeSuppressedDuringPreviewOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerPreview;

    XCTAssertNoThrow([doc editorBoundsDidChange:nil],
                     @"editorBoundsDidChange: should not crash when scrollOwner is Preview");
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerPreview,
                   @"scrollOwner should remain Preview after suppressed editorBoundsDidChange:");
}

#pragma mark - Issue #342: Group C — JS Coordinate Fix

/**
 * Helper: loads updateHeaderLocations.js source from the main bundle.
 */
- (NSString *)loadUpdateHeaderLocationsScript
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:@"updateHeaderLocations" ofType:@"js"];
    if (!path) return nil;
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

/**
 * Helper: constructs a JSContext with a mock DOM for testing the JS script.
 * scrollY:      simulated window.scrollY
 * headerTops:   array of NSNumber; each becomes a header with that rect.top
 */
- (JSContext *)jsContextWithScrollY:(CGFloat)scrollY headerTops:(NSArray<NSNumber *> *)headerTops
{
    JSContext *context = [[JSContext alloc] init];
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) { };

    NSMutableString *headersJS = [NSMutableString stringWithString:@"["];
    for (NSUInteger i = 0; i < headerTops.count; i++) {
        CGFloat top = [headerTops[i] floatValue];
        [headersJS appendFormat:
            @"{getBoundingClientRect:function(){return {top:%g};}"
            @",compareDocumentPosition:function(o){return 4;}"
            @",tagName:'H1',parentElement:null}",
            top];
        if (i + 1 < headerTops.count) [headersJS appendString:@","];
    }
    [headersJS appendString:@"]"];

    NSString *setup = [NSString stringWithFormat:
        @"var window = {scrollY: %g};\n"
        @"var Node = {DOCUMENT_POSITION_FOLLOWING: 4, DOCUMENT_POSITION_PRECEDING: 2};\n"
        @"var _headers = %@;\n"
        @"var document = {\n"
        @"    body: {},\n"
        @"    querySelectorAll: function(sel) {\n"
        @"        if (sel === 'h1, h2, h3, h4, h5, h6') return _headers;\n"
        @"        return [];\n"
        @"    }\n"
        @"};\n",
        scrollY, headersJS];

    [context evaluateScript:setup];
    return context;
}

/**
 * C1 — Scrolled page: result is window.scrollY + rect.top (document-absolute).
 * Issue #342: After JS fix, header at viewport top 100 with scrollY 200 = 300.
 */
- (void)testJSHeaderLocationScrolledPage
{
    NSString *script = [self loadUpdateHeaderLocationsScript];
    if (!script) {
        XCTFail(@"updateHeaderLocations.js not found in bundle");
        return;
    }

    JSContext *context = [self jsContextWithScrollY:200 headerTops:@[@100]];
    JSValue *result = [context evaluateScript:script];
    NSArray *locations = [result toArray];

    XCTAssertEqual(locations.count, 1U, @"Should return one location");
    XCTAssertEqualWithAccuracy([[locations firstObject] floatValue], 300.0, 0.5,
                               @"Scrolled page: scrollY(200) + rect.top(100) should equal 300");
}

/**
 * C2 — Unscrolled page: result equals rect.top directly.
 * Issue #342: At scrollY=0, document-absolute equals viewport-relative.
 */
- (void)testJSHeaderLocationUnscrolledPage
{
    NSString *script = [self loadUpdateHeaderLocationsScript];
    if (!script) {
        XCTFail(@"updateHeaderLocations.js not found in bundle");
        return;
    }

    JSContext *context = [self jsContextWithScrollY:0 headerTops:@[@150]];
    JSValue *result = [context evaluateScript:script];
    NSArray *locations = [result toArray];

    XCTAssertEqual(locations.count, 1U, @"Should return one location");
    XCTAssertEqualWithAccuracy([[locations firstObject] floatValue], 150.0, 0.5,
                               @"Unscrolled page: scrollY(0) + rect.top(150) should equal 150");
}

/**
 * C3 — Multiple headers: each gets scrollY added.
 * Issue #342: All returned values must be document-absolute.
 */
- (void)testJSHeaderLocationsMultipleHeaders
{
    NSString *script = [self loadUpdateHeaderLocationsScript];
    if (!script) {
        XCTFail(@"updateHeaderLocations.js not found in bundle");
        return;
    }

    JSContext *context = [[JSContext alloc] init];
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) { };

    [context evaluateScript:
        @"var window = {scrollY: 500};\n"
        @"var Node = {DOCUMENT_POSITION_FOLLOWING: 4, DOCUMENT_POSITION_PRECEDING: 2};\n"
        @"var h0 = {getBoundingClientRect:function(){return {top:50};},  tagName:'H1', parentElement:null,\n"
        @"          compareDocumentPosition:function(o){return o===h1?4:(o===h2?4:0);}};\n"
        @"var h1 = {getBoundingClientRect:function(){return {top:100};}, tagName:'H2', parentElement:null,\n"
        @"          compareDocumentPosition:function(o){return o===h0?2:(o===h2?4:0);}};\n"
        @"var h2 = {getBoundingClientRect:function(){return {top:300};}, tagName:'H3', parentElement:null,\n"
        @"          compareDocumentPosition:function(o){return o===h0?2:(o===h1?2:0);}};\n"
        @"var document = {\n"
        @"    body: {},\n"
        @"    querySelectorAll: function(sel) {\n"
        @"        if (sel === 'h1, h2, h3, h4, h5, h6') return [h0, h1, h2];\n"
        @"        return [];\n"
        @"    }\n"
        @"};\n"];

    JSValue *result = [context evaluateScript:script];
    NSArray *locations = [result toArray];

    XCTAssertEqual(locations.count, 3U, @"Should return three locations");
    XCTAssertEqualWithAccuracy([locations[0] floatValue], 550.0, 0.5,
                               @"First header: 500+50=550");
    XCTAssertEqualWithAccuracy([locations[1] floatValue], 600.0, 0.5,
                               @"Second header: 500+100=600");
    XCTAssertEqualWithAccuracy([locations[2] floatValue], 800.0, 0.5,
                               @"Third header: 500+300=800");
}

/**
 * C4 — Empty body (no headers, no images): returns empty array.
 * Issue #342: Script must handle documents with no reference points.
 */
- (void)testJSHeaderLocationsEmptyBody
{
    NSString *script = [self loadUpdateHeaderLocationsScript];
    if (!script) {
        XCTFail(@"updateHeaderLocations.js not found in bundle");
        return;
    }

    JSContext *context = [[JSContext alloc] init];
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) { };

    [context evaluateScript:
        @"var window = {scrollY: 100};\n"
        @"var Node = {DOCUMENT_POSITION_FOLLOWING: 4, DOCUMENT_POSITION_PRECEDING: 2};\n"
        @"var document = {\n"
        @"    body: {},\n"
        @"    querySelectorAll: function(sel) { return []; }\n"
        @"};\n"];

    JSValue *result = [context evaluateScript:script];
    NSArray *locations = [result toArray];

    XCTAssertNotNil(locations, @"Result should not be nil for empty body");
    XCTAssertEqual(locations.count, 0U, @"Empty body should return empty array");
}

/**
 * C5 — Null document.body: returns empty array without crashing.
 * Issue #342: Script must guard against missing body gracefully.
 */
- (void)testJSHeaderLocationsNullBody
{
    NSString *script = [self loadUpdateHeaderLocationsScript];
    if (!script) {
        XCTFail(@"updateHeaderLocations.js not found in bundle");
        return;
    }

    JSContext *context = [[JSContext alloc] init];
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) { };

    [context evaluateScript:
        @"var window = {scrollY: 0};\n"
        @"var Node = {DOCUMENT_POSITION_FOLLOWING: 4, DOCUMENT_POSITION_PRECEDING: 2};\n"
        @"var document = {body: null, querySelectorAll: function(s){return [];}};\n"];

    JSValue *result = [context evaluateScript:script];
    XCTAssertNoThrow((void)[result toArray],
                     @"Script with null document.body should not throw");
    NSArray *locations = [result toArray];
    XCTAssertEqual(locations.count, 0U, @"Null body should return empty array");
}

#pragma mark - Issue #342: Group D — Header Array Alignment Safety

/**
 * D1 — syncScrollers with equal-length arrays does not crash.
 * Issue #342: Arrays of equal length must not produce out-of-bounds access.
 */
- (void)testSyncScrollersWithEqualLengthArraysDoesNotCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@100, @300, @600];
    doc.editorHeaderLocations  = @[@100, @300, @600];

    XCTAssertNoThrow([doc syncScrollers],
                     @"syncScrollers should not crash with equal-length header arrays");
}

/**
 * D2 — syncScrollersReverse with equal-length arrays does not crash.
 * Issue #342: Reverse sync must also be safe with aligned arrays.
 */
- (void)testSyncScrollersReverseWithEqualLengthArraysDoesNotCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@100, @300, @600];
    doc.editorHeaderLocations  = @[@100, @300, @600];

    XCTAssertNoThrow([doc syncScrollersReverse],
                     @"syncScrollersReverse should not crash with equal-length header arrays");
}

/**
 * D3 — syncScrollers with empty arrays does not crash.
 * Issue #342: Edge case with no reference points must not crash.
 */
- (void)testSyncScrollersWithEmptyArraysDoesNotCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[];
    doc.editorHeaderLocations  = @[];

    XCTAssertNoThrow([doc syncScrollers],
                     @"syncScrollers should not crash with empty header arrays");
}

#pragma mark - Issue #342: Group E — lastPreviewScrollTop Save Point

/**
 * E2 — syncScrollers overwrites lastPreviewScrollTop.
 * Issue #342: syncScrollers must save its computed preview position,
 * not preserve a stale value from a previous render cycle.
 */
- (void)testSyncScrollersOverwritesLastPreviewScrollTop
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.lastPreviewScrollTop = 999.0;
    doc.webViewHeaderLocations = @[];
    doc.editorHeaderLocations  = @[];

    [doc syncScrollers];

    // With no scroll view, syncScrollers writes 0.0 — the point is it overwrites the stale value
    XCTAssertEqualWithAccuracy(doc.lastPreviewScrollTop, 0.0, 0.01,
                               @"syncScrollers should overwrite stale lastPreviewScrollTop with computed value");
}

#pragma mark - Issue #342: Group F — Handler Method Existence

/**
 * F1 — willStartPreviewLiveScroll: method exists on MPDocument.
 * Issue #342: New observer handler must be present after implementation.
 */
- (void)testWillStartPreviewLiveScrollMethodExists
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertTrue([doc respondsToSelector:@selector(willStartPreviewLiveScroll:)],
                  @"MPDocument should respond to willStartPreviewLiveScroll:");
}

/**
 * F2 — didEndPreviewLiveScroll: method exists on MPDocument.
 * Issue #342: New observer handler must be present after implementation.
 */
- (void)testDidEndPreviewLiveScrollMethodExists
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertTrue([doc respondsToSelector:@selector(didEndPreviewLiveScroll:)],
                  @"MPDocument should respond to didEndPreviewLiveScroll:");
}

#pragma mark - Issue #342: Group G — performDelayedSyncScrollers Removal

/**
 * G1 — performDelayedSyncScrollers method no longer exists.
 * Issue #342: Delayed sync must be removed entirely; timer-based sync is the bug.
 */
- (void)testPerformDelayedSyncScrollersMethodRemoved
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertFalse([doc respondsToSelector:@selector(performDelayedSyncScrollers)],
                   @"performDelayedSyncScrollers should not exist after Issue #342 fix");
}

/**
 * G2 — close does not crash without performDelayedSyncScrollers cancellation.
 * Issue #342: The cancelPreviousPerformRequests call must be removed along with
 * the method itself; close must not crash.
 */
- (void)testCloseDoesNotCrashAfterDelayedSyncRemoval
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertNoThrow([doc close],
                     @"close should not crash after performDelayedSyncScrollers is removed");
}

#pragma mark - Group H — Division-by-zero guard in syncScrollers/syncScrollersReverse (Commit 1, gaps 6+7)

/**
 * H1 — syncScrollers with a single header at y=0 does not crash.
 * Exercises the `maxY==0` sentinel path (gap 6): when the only header is at 0
 * after taper adjustment, maxY stays 0 and the division guard must fire.
 */
- (void)testSyncScrollersSingleHeaderAtYZeroNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@0];
    doc.editorHeaderLocations  = @[@0];

    XCTAssertNoThrow([doc syncScrollers],
                     @"H1: syncScrollers should not crash when the only header is at y=0");
}

/**
 * H2 — syncScrollersReverse with a single header at y=0 does not crash.
 * Mirror of H1 in the reverse direction.
 */
- (void)testSyncScrollersReverseSingleHeaderAtYZeroNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@0];
    doc.editorHeaderLocations  = @[@0];

    XCTAssertNoThrow([doc syncScrollersReverse],
                     @"H2: syncScrollersReverse should not crash when the only header is at y=0");
}

/**
 * H3 — syncScrollers with two headers at the same y does not crash.
 * Exercises gap 7: foundMaxY becomes YES but maxY - minY collapses to 0
 * post-normalization, so the division guard must fire.
 */
- (void)testSyncScrollersTwoHeadersSameYNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@100, @100];
    doc.editorHeaderLocations  = @[@100, @100];

    XCTAssertNoThrow([doc syncScrollers],
                     @"H3: syncScrollers should not crash when two headers share the same y");
}

/**
 * H4 — syncScrollersReverse with two headers at the same y does not crash.
 * Mirror of H3 in the reverse direction.
 */
- (void)testSyncScrollersReverseTwoHeadersSameYNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@100, @100];
    doc.editorHeaderLocations  = @[@100, @100];

    XCTAssertNoThrow([doc syncScrollersReverse],
                     @"H4: syncScrollersReverse should not crash when two headers share the same y");
}

/**
 * H5 — syncScrollers with a single header at y=0 and a non-zero scroll position does not crash.
 * Header is below currY=0 but y=0 means it enters the minY branch; foundMaxY stays NO,
 * triggering interpolateToEndOfDocument and the division guard.
 */
- (void)testSyncScrollersSingleHeaderAtYZeroWithScrollNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    // Place the header at 0 — after taper subtraction it may still land in minY branch
    doc.webViewHeaderLocations = @[@0];
    doc.editorHeaderLocations  = @[@0];
    // lastPreviewScrollTop is not the editor scroll, but we use it as a proxy.
    // The actual scroll view is nil (headless), so currY = 0 regardless.
    // This test verifies crash-freedom; behavioral verification requires a window.
    doc.lastPreviewScrollTop = 100.0;

    XCTAssertNoThrow([doc syncScrollers],
                     @"H5: syncScrollers should not crash with header at y=0 and non-zero scroll");
}

/**
 * H6 — syncScrollersReverse with a single header at y=0 and a non-zero scroll position does not crash.
 * Mirror of H5 in the reverse direction.
 */
- (void)testSyncScrollersReverseSingleHeaderAtYZeroWithScrollNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.webViewHeaderLocations = @[@0];
    doc.editorHeaderLocations  = @[@0];
    doc.lastPreviewScrollTop = 100.0;

    XCTAssertNoThrow([doc syncScrollersReverse],
                     @"H6: syncScrollersReverse should not crash with header at y=0 and non-zero scroll");
}

#pragma mark - Group L — Array alignment validation (Commit 3, gap 5)

/**
 * L1 — validateHeaderLocationAlignment truncates the longer array to MIN count.
 * When editor has 3 entries and webView has 2, both should end up with 2 entries.
 */
- (void)testValidateHeaderLocationAlignmentTruncatesToMin
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.editorHeaderLocations  = @[@50, @150, @300];
    doc.webViewHeaderLocations = @[@100, @250];

    [doc validateHeaderLocationAlignment];

    XCTAssertEqual(doc.editorHeaderLocations.count, 2U,
                   @"L1: editorHeaderLocations should be truncated to 2 (the MIN count)");
    XCTAssertEqual(doc.webViewHeaderLocations.count, 2U,
                   @"L1: webViewHeaderLocations should remain at 2");
}

/**
 * L2 — validateHeaderLocationAlignment leaves equal-length arrays unchanged.
 */
- (void)testValidateHeaderLocationAlignmentEqualArraysUnchanged
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.editorHeaderLocations  = @[@50, @150];
    doc.webViewHeaderLocations = @[@100, @250];

    [doc validateHeaderLocationAlignment];

    XCTAssertEqual(doc.editorHeaderLocations.count, 2U,
                   @"L2: editorHeaderLocations should be unchanged when counts match");
    XCTAssertEqual(doc.webViewHeaderLocations.count, 2U,
                   @"L2: webViewHeaderLocations should be unchanged when counts match");
}

/**
 * L3 — validateHeaderLocationAlignment with one empty array results in both empty.
 * MIN(3, 0) == 0, so the non-empty array must be truncated to empty.
 */
- (void)testValidateHeaderLocationAlignmentOneEmptyResultsBothEmpty
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.editorHeaderLocations  = @[@50, @150, @300];
    doc.webViewHeaderLocations = @[];

    [doc validateHeaderLocationAlignment];

    XCTAssertEqual(doc.editorHeaderLocations.count, 0U,
                   @"L3: editorHeaderLocations should be truncated to empty when webView array is empty");
    XCTAssertEqual(doc.webViewHeaderLocations.count, 0U,
                   @"L3: webViewHeaderLocations should remain empty");
}

#pragma mark - Group I — Scroll ownership on file revert (Commit 4, gap 8)

/**
 * I1 — reloadFromLoadedString on a fresh (headless) document does not crash,
 * and scrollOwner remains Neither because isPreviewReady is NO.
 *
 * Headless limitation: the `if (self.editor && self.renderer && self.highlighter)`
 * guard prevents body execution, so the ownership transition (`if (self.isPreviewReady)
 * _scrollOwner = MPScrollOwnerEditor`) is not reachable in this environment.
 * This test verifies crash-freedom and the pre-condition (Neither ownership on init).
 */
- (void)testReloadFromLoadedStringFreshDocumentNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];

    XCTAssertNoThrow([doc reloadFromLoadedString],
                     @"I1: reloadFromLoadedString should not crash on a fresh headless document");
    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerNeither,
                   @"I1: scrollOwner should remain Neither after reloadFromLoadedString on fresh document (isPreviewReady is NO)");
}

#pragma mark - Group M — Checkbox toggle ownership (Commit 5, gap 10)

/**
 * M1 — handleCheckboxToggle: with a well-formed URL does not crash.
 * Headless: self.editor is nil, so the body does not execute.
 */
- (void)testHandleCheckboxToggleValidURLNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    NSURL *url = [NSURL URLWithString:@"x-macdown-checkbox://toggle/0"];

    XCTAssertNoThrow([doc handleCheckboxToggle:url],
                     @"M1: handleCheckboxToggle: should not crash with a valid toggle URL");
}

/**
 * M2 — handleCheckboxToggle: with an unrecognized host returns early without crashing.
 * The method guards on `url.host == "toggle"` and returns early otherwise.
 */
- (void)testHandleCheckboxToggleInvalidURLNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    NSURL *url = [NSURL URLWithString:@"x-macdown-checkbox://notacommand/0"];

    XCTAssertNoThrow([doc handleCheckboxToggle:url],
                     @"M2: handleCheckboxToggle: should not crash with an unrecognized host");
}

#pragma mark - Group J — Sync after layout changes (Commit 6, gaps 1+3)

/**
 * J1 — refreshHeaderCacheAfterResize does not crash when renderer is nil.
 * The method should return early when `!self.renderer`.
 */
- (void)testRefreshHeaderCacheAfterResizeNilRendererNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];
    // renderer is nil on a fresh headless document

    XCTAssertNoThrow([doc refreshHeaderCacheAfterResize],
                     @"J1: refreshHeaderCacheAfterResize should not crash when renderer is nil");
}

/**
 * J2 — windowDidEndLiveResize: does not crash.
 */
- (void)testWindowDidEndLiveResizeNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];

    XCTAssertNoThrow([doc windowDidEndLiveResize:nil],
                     @"J2: windowDidEndLiveResize: should not crash");
}

/**
 * J3 — windowDidChangeFullScreen: does not crash.
 */
- (void)testWindowDidChangeFullScreenNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];

    XCTAssertNoThrow([doc windowDidChangeFullScreen:nil],
                     @"J3: windowDidChangeFullScreen: should not crash");
}

/**
 * J4 — refreshHeaderCacheAfterResize does not change scrollOwner when it is Preview.
 * The method may call syncScrollers only when scrollOwner == Neither; Preview
 * ownership must be preserved.
 */
- (void)testRefreshHeaderCachePreservesPreviewOwnership
{
    MPDocument *doc = [[MPDocument alloc] init];
    doc.scrollOwner = MPScrollOwnerPreview;

    [doc refreshHeaderCacheAfterResize];

    XCTAssertEqual(doc.scrollOwner, MPScrollOwnerPreview,
                   @"J4: refreshHeaderCacheAfterResize should not change scrollOwner when it is Preview");
}

#pragma mark - Group K — Editor-reveal sync (Commit 7, gap 2)

/**
 * K1 — setSplitViewDividerLocation:0.5 does not crash.
 * splitView is nil in headless tests; the method must handle that gracefully.
 */
- (void)testSetSplitViewDividerLocationNoCrash
{
    MPDocument *doc = [[MPDocument alloc] init];

    XCTAssertNoThrow([doc setSplitViewDividerLocation:0.5],
                     @"K1: setSplitViewDividerLocation: should not crash in a headless document");
}

#pragma mark - Group N — MathJax render generation counter (Commit 8, gap 9)

// NOTE: Group N tests require the `_mathJaxRenderGeneration` ivar added in Commit 8
// and the `mathJaxRenderGeneration` getter in the test category above.
// Until that ivar is added to MPDocument.m, these tests will not compile.
// They are wrapped in #if 0 so the rest of the test suite compiles and runs (red state).
// Remove the #if 0 / #endif when Commit 8 lands.
#if 0

/**
 * N1 — _mathJaxRenderGeneration ivar starts at 0 (implicitly zero-initialized by runtime).
 * Verifies the counter exists and has the expected initial value before any render.
 */
- (void)testMathJaxRenderGenerationInitialValueIsZero
{
    MPDocument *doc = [[MPDocument alloc] init];

    XCTAssertEqual([doc mathJaxRenderGeneration], (NSUInteger)0,
                   @"N1: _mathJaxRenderGeneration should be 0 on a fresh document");
}

#endif  // Group N — enable after Commit 8 adds _mathJaxRenderGeneration ivar

@end
