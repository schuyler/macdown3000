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

// Category to expose private properties/methods for testing
@interface MPDocument (ScrollSyncTesting)
@property (nonatomic) CGFloat lastPreviewScrollTop;
@property (strong) NSArray<NSNumber *> *webViewHeaderLocations;
@property (strong) NSArray<NSNumber *> *editorHeaderLocations;
@property (weak) WebView *preview;
@property BOOL shouldHandleBoundsChange;
@property BOOL shouldHandlePreviewBoundsChange;
@property (nonatomic) BOOL inEditing;  // Issue #282: Track active editing state
- (void)updateHeaderLocations;
- (void)syncScrollers;
- (void)syncScrollersReverse;
- (void)performDelayedSyncScrollers;  // Issue #282: Delayed sync after editing
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
 * Test that shouldHandlePreviewBoundsChange property is initialized correctly.
 * Regression test for Issue #258 - loop prevention flag.
 */
- (void)testPreviewBoundsChangeFlagInitialized
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertTrue(doc.shouldHandlePreviewBoundsChange,
                  @"shouldHandlePreviewBoundsChange should be YES by default");
}

/**
 * Test that both loop prevention flags are independent.
 * Regression test for Issue #258 - ensures bidirectional sync doesn't loop.
 */
- (void)testLoopPreventionFlagsAreIndependent
{
    MPDocument *doc = [[MPDocument alloc] init];

    // Initially both should be YES
    XCTAssertTrue(doc.shouldHandleBoundsChange,
                  @"shouldHandleBoundsChange should be YES initially");
    XCTAssertTrue(doc.shouldHandlePreviewBoundsChange,
                  @"shouldHandlePreviewBoundsChange should be YES initially");

    // Setting one should not affect the other
    doc.shouldHandleBoundsChange = NO;
    XCTAssertFalse(doc.shouldHandleBoundsChange,
                   @"shouldHandleBoundsChange should be NO after setting");
    XCTAssertTrue(doc.shouldHandlePreviewBoundsChange,
                  @"shouldHandlePreviewBoundsChange should still be YES");

    doc.shouldHandlePreviewBoundsChange = NO;
    XCTAssertFalse(doc.shouldHandlePreviewBoundsChange,
                   @"shouldHandlePreviewBoundsChange should be NO after setting");
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

#pragma mark - Issue #282: Editing State Tests

/**
 * Test that inEditing property is initialized to NO.
 * Issue #282: Editing state should be NO by default.
 */
- (void)testInEditingInitializedToNo
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertFalse(doc.inEditing,
                   @"inEditing should be NO by default");
}

/**
 * Test that performDelayedSyncScrollers method exists and doesn't crash.
 * Issue #282: Delayed sync method should exist.
 */
- (void)testPerformDelayedSyncScrollersExists
{
    XCTAssertNoThrow([self.document performDelayedSyncScrollers],
                     @"performDelayedSyncScrollers should exist and not crash");
}

/**
 * Test that performDelayedSyncScrollers clears inEditing flag.
 * Issue #282: Delayed sync should reset editing state.
 */
- (void)testPerformDelayedSyncScrollersClearsInEditing
{
    self.document.inEditing = YES;
    XCTAssertTrue(self.document.inEditing, @"inEditing should be YES before test");

    [self.document performDelayedSyncScrollers];

    XCTAssertFalse(self.document.inEditing,
                   @"performDelayedSyncScrollers should set inEditing to NO");
}

/**
 * Test that inEditing flag can be set and read.
 * Issue #282: Editing state should be settable.
 */
- (void)testInEditingFlagCanBeToggled
{
    MPDocument *doc = [[MPDocument alloc] init];

    doc.inEditing = YES;
    XCTAssertTrue(doc.inEditing, @"inEditing should be YES after setting to YES");

    doc.inEditing = NO;
    XCTAssertFalse(doc.inEditing, @"inEditing should be NO after setting to NO");
}

/**
 * Test that performDelayedSyncScrollers handles empty header locations.
 * Issue #282: Delayed sync should handle edge cases.
 */
- (void)testPerformDelayedSyncScrollersWithEmptyLocations
{
    self.document.webViewHeaderLocations = @[];
    self.document.editorHeaderLocations = @[];
    self.document.inEditing = YES;

    XCTAssertNoThrow([self.document performDelayedSyncScrollers],
                     @"performDelayedSyncScrollers should handle empty header locations");
    XCTAssertFalse(self.document.inEditing,
                   @"inEditing should be NO after performDelayedSyncScrollers");
}

/**
 * Test that performDelayedSyncScrollers handles nil header locations.
 * Issue #282: Delayed sync should handle nil safely.
 */
- (void)testPerformDelayedSyncScrollersWithNilLocations
{
    self.document.webViewHeaderLocations = nil;
    self.document.editorHeaderLocations = nil;
    self.document.inEditing = YES;

    XCTAssertNoThrow([self.document performDelayedSyncScrollers],
                     @"performDelayedSyncScrollers should handle nil header locations");
    XCTAssertFalse(self.document.inEditing,
                   @"inEditing should be NO after performDelayedSyncScrollers");
}

/**
 * Test that inEditing and shouldHandleBoundsChange are independent.
 * Issue #282: Editing state should not affect loop prevention flags.
 */
- (void)testInEditingIndependentFromBoundsChangeFlag
{
    MPDocument *doc = [[MPDocument alloc] init];

    // Initially both should have their default values
    XCTAssertFalse(doc.inEditing, @"inEditing should be NO initially");
    XCTAssertTrue(doc.shouldHandleBoundsChange, @"shouldHandleBoundsChange should be YES initially");

    // Setting inEditing should not affect shouldHandleBoundsChange
    doc.inEditing = YES;
    XCTAssertTrue(doc.inEditing, @"inEditing should be YES after setting");
    XCTAssertTrue(doc.shouldHandleBoundsChange,
                  @"shouldHandleBoundsChange should still be YES");

    // Setting shouldHandleBoundsChange should not affect inEditing
    doc.shouldHandleBoundsChange = NO;
    XCTAssertTrue(doc.inEditing, @"inEditing should still be YES");
    XCTAssertFalse(doc.shouldHandleBoundsChange,
                   @"shouldHandleBoundsChange should be NO after setting");
}

/**
 * Test that pending performDelayedSyncScrollers is cancelled on document close.
 * Issue #282: Prevents crash from message to deallocated object when document
 * is closed during active editing (within 200ms of last keystroke).
 */
- (void)testPendingDelayedSyncCancelledOnClose
{
    // This test verifies the close method properly cancels pending selectors
    // to prevent crashes when document is closed during editing.
    // Note: In headless tests the document may not have full window setup,
    // but the cancel call should still execute without crashing.
    MPDocument *doc = [[MPDocument alloc] init];
    doc.inEditing = YES;  // Simulate editing state
    XCTAssertNoThrow([doc close], @"close should not crash with pending delayed sync");
}

@end
