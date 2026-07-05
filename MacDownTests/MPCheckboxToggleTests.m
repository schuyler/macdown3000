//
//  MPCheckboxToggleTests.m
//  MacDown 3000
//
//  Tests for checkbox toggle functionality (Issue #269).
//  These tests verify the source text manipulation when toggling checkboxes.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"

@interface MPCheckboxToggleTests : XCTestCase
@end


@implementation MPCheckboxToggleTests

#pragma mark - Toggle Unchecked -> Checked

/**
 * Test toggling the first unchecked checkbox to checked.
 */
- (void)testToggleFirstUncheckedToChecked
{
    NSString *markdown = @"- [ ] First task\n- [ ] Second task";
    NSString *expected = @"- [x] First task\n- [ ] Second task";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"First checkbox should be toggled to checked");
}

/**
 * Test toggling a middle checkbox in a list.
 */
- (void)testToggleMiddleCheckbox
{
    NSString *markdown = @"- [ ] First\n- [ ] Second\n- [ ] Third";
    NSString *expected = @"- [ ] First\n- [x] Second\n- [ ] Third";

    NSString *result = [MPDocument toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Middle checkbox should be toggled to checked");
}

/**
 * Test toggling the last checkbox in a document.
 */
- (void)testToggleLastCheckbox
{
    NSString *markdown = @"- [ ] First\n- [ ] Second\n- [ ] Third";
    NSString *expected = @"- [ ] First\n- [ ] Second\n- [x] Third";

    NSString *result = [MPDocument toggleCheckboxAtIndex:2 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Last checkbox should be toggled to checked");
}

#pragma mark - Toggle Checked -> Unchecked

/**
 * Test toggling a checked checkbox to unchecked.
 */
- (void)testToggleCheckedToUnchecked
{
    NSString *markdown = @"- [x] Completed task\n- [ ] Pending task";
    NSString *expected = @"- [ ] Completed task\n- [ ] Pending task";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Checked checkbox should be toggled to unchecked");
}

/**
 * Test toggling mixed checked/unchecked checkboxes.
 */
- (void)testToggleMixedCheckboxes
{
    NSString *markdown = @"- [x] First (done)\n- [ ] Second (todo)\n- [x] Third (done)";

    // Toggle the second checkbox (index 1) from unchecked to checked
    NSString *result = [MPDocument toggleCheckboxAtIndex:1 inMarkdown:markdown];
    NSString *expected = @"- [x] First (done)\n- [x] Second (todo)\n- [x] Third (done)";

    XCTAssertEqualObjects(result, expected,
                          @"Second checkbox should be toggled to checked");
}

#pragma mark - Nested Lists

/**
 * Test toggling a nested checkbox.
 * cmark-gfm: indices are assigned in document order (issue #77):
 * Parent(0), Child(1), Another child(2)
 */
- (void)testToggleNestedCheckbox
{
    NSString *markdown = @"- [ ] Parent\n  - [ ] Child\n  - [ ] Another child";
    NSString *expected = @"- [ ] Parent\n  - [x] Child\n  - [ ] Another child";

    // Child is document-order index 1 (right after its parent)
    NSString *result = [MPDocument toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Nested checkbox should be toggled correctly");
}

/**
 * Test toggling in deeply nested lists.
 * cmark-gfm: indices are assigned in document order (issue #77):
 * Level1(0), Level2(1), Level3(2)
 */
- (void)testToggleDeeplyNestedCheckbox
{
    NSString *markdown = @"- [ ] Level 1\n  - [ ] Level 2\n    - [ ] Level 3";
    NSString *expected = @"- [ ] Level 1\n  - [ ] Level 2\n    - [x] Level 3";

    // Level 3 is document-order index 2 (last line in the source)
    NSString *result = [MPDocument toggleCheckboxAtIndex:2 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Deeply nested checkbox should be toggled correctly");
}

/**
 * Test toggling the parent checkbox in a nested list.
 * cmark-gfm: indices are assigned in document order (issue #77):
 * Parent(0), Child(1), Another child(2)
 */
- (void)testToggleParentCheckboxInNestedList
{
    NSString *markdown = @"- [ ] Parent\n  - [ ] Child\n  - [ ] Another child";
    NSString *expected = @"- [x] Parent\n  - [ ] Child\n  - [ ] Another child";

    // Parent is document-order index 0 (first line in the source)
    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Parent checkbox should be toggled with correct document-order index");
}

/**
 * Test that document ordering works with multiple sibling parents.
 * Structure:
 *   - [ ] Parent1
 *     - [ ] Child1
 *   - [ ] Parent2
 * cmark-gfm: document order (issue #77): Parent1(0), Child1(1), Parent2(2)
 */
- (void)testToggleWithMultipleSiblingParents
{
    NSString *markdown = @"- [ ] Parent1\n  - [ ] Child1\n- [ ] Parent2";
    NSString *expected = @"- [ ] Parent1\n  - [x] Child1\n- [ ] Parent2";

    // Child1 is document-order index 1 (after Parent1, before Parent2)
    NSString *result = [MPDocument toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Child1 should be at document-order index 1");
}

#pragma mark - Edge Cases

/**
 * Test toggling checkbox with inline formatting.
 */
- (void)testToggleCheckboxWithInlineFormatting
{
    NSString *markdown = @"- [ ] Task with **bold** and *italic*";
    NSString *expected = @"- [x] Task with **bold** and *italic*";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Checkbox with formatting should toggle correctly");
}

/**
 * Test that checkboxes inside code blocks are NOT counted.
 */
- (void)testCheckboxesInCodeBlocksNotCounted
{
    NSString *markdown = @"```\n- [ ] Not a real checkbox\n```\n\n- [ ] Real checkbox";
    NSString *expected = @"```\n- [ ] Not a real checkbox\n```\n\n- [x] Real checkbox";

    // Index 0 should refer to the REAL checkbox, not the one in the code block
    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Only real checkboxes outside code blocks should be counted");
}

/**
 * Test toggling checkbox at document start.
 */
- (void)testToggleCheckboxAtDocumentStart
{
    NSString *markdown = @"- [ ] First line is a checkbox";
    NSString *expected = @"- [x] First line is a checkbox";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Checkbox at document start should toggle correctly");
}

/**
 * Test toggling checkbox at document end.
 */
- (void)testToggleCheckboxAtDocumentEnd
{
    NSString *markdown = @"Some text\n\n- [ ] Last checkbox";
    NSString *expected = @"Some text\n\n- [x] Last checkbox";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Checkbox at document end should toggle correctly");
}

/**
 * Test handling of out-of-bounds index.
 */
- (void)testToggleWithInvalidIndex
{
    NSString *markdown = @"- [ ] Only one checkbox";

    // Index 5 is out of bounds - should return original markdown unchanged
    NSString *result = [MPDocument toggleCheckboxAtIndex:5 inMarkdown:markdown];

    XCTAssertEqualObjects(result, markdown,
                          @"Invalid index should return unchanged markdown");
}

/**
 * Test toggling on empty document.
 */
- (void)testToggleOnEmptyDocument
{
    NSString *markdown = @"";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, markdown,
                          @"Empty document should return empty string");
}

/**
 * Test toggling on document with no checkboxes.
 */
- (void)testToggleOnDocumentWithNoCheckboxes
{
    NSString *markdown = @"Just some text\n- Regular list item\n- Another item";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, markdown,
                          @"Document without checkboxes should return unchanged");
}

/**
 * Test checkbox with asterisk marker.
 */
- (void)testToggleCheckboxWithAsteriskMarker
{
    NSString *markdown = @"* [ ] Asterisk checkbox";
    NSString *expected = @"* [x] Asterisk checkbox";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Asterisk marker checkbox should toggle correctly");
}

- (void)testToggleUppercaseCheckedCheckbox
{
    NSString *markdown = @"- [X] Done";
    NSString *expected = @"- [ ] Done";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Uppercase checked checkbox should toggle to unchecked");
}

/**
 * Test checkbox with plus marker.
 */
- (void)testToggleCheckboxWithPlusMarker
{
    NSString *markdown = @"+ [ ] Plus checkbox";
    NSString *expected = @"+ [x] Plus checkbox";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Plus marker checkbox should toggle correctly");
}

/**
 * Test numbered list checkbox.
 */
- (void)testToggleNumberedListCheckbox
{
    NSString *markdown = @"1. [ ] First numbered\n2. [ ] Second numbered";
    NSString *expected = @"1. [x] First numbered\n2. [ ] Second numbered";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Numbered list checkbox should toggle correctly");
}

/**
 * Test checkbox with Unicode content.
 */
- (void)testToggleCheckboxWithUnicodeContent
{
    NSString *markdown = @"- [ ] 日本語タスク\n- [ ] Emoji task 🎉";
    NSString *expected = @"- [x] 日本語タスク\n- [ ] Emoji task 🎉";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Checkbox with Unicode content should toggle correctly");
}

#pragma mark - Case Insensitivity (Issue #369)

/**
 * Test that toggling an uppercase [X] checkbox unchecks it to [ ].
 */
- (void)testToggleUppercaseCheckedToUnchecked
{
    NSString *markdown = @"- [X] Capital X task\n- [ ] Pending task";
    NSString *expected = @"- [ ] Capital X task\n- [ ] Pending task";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Uppercase [X] checkbox should toggle to unchecked");
}

/**
 * Test that re-checking after an uppercase [X] normalizes to lowercase [x].
 * Index 1 is the unchecked item, which should become [x] (not [X]).
 */
- (void)testReCheckNormalizesToLowercase
{
    NSString *markdown = @"- [X] Capital X task\n- [ ] Pending task";
    NSString *expected = @"- [X] Capital X task\n- [x] Pending task";

    NSString *result = [MPDocument toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Re-checking should write lowercase [x]");
}

/**
 * Test that an uppercase [X] occupies an index, keeping subsequent checkboxes
 * aligned with the renderer. Toggling index 1 must hit the second item, not
 * skip over the uppercase one.
 */
- (void)testUppercaseCheckboxOccupiesIndex
{
    NSString *markdown = @"- [X] First (capital)\n- [ ] Second\n- [x] Third";
    NSString *expected = @"- [X] First (capital)\n- [x] Second\n- [x] Third";

    NSString *result = [MPDocument toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"[X] should occupy index 0 so index 1 hits the second item");
}

/**
 * Test toggling an uppercase [X] checkbox with an asterisk marker.
 */
- (void)testToggleUppercaseCheckboxWithAsteriskMarker
{
    NSString *markdown = @"* [X] Asterisk capital task";
    NSString *expected = @"* [ ] Asterisk capital task";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Asterisk marker [X] checkbox should toggle correctly");
}

/**
 * Test toggling an uppercase [X] checkbox with a plus marker.
 */
- (void)testToggleUppercaseCheckboxWithPlusMarker
{
    NSString *markdown = @"+ [X] Plus capital task";
    NSString *expected = @"+ [ ] Plus capital task";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Plus marker [X] checkbox should toggle correctly");
}

/**
 * Test toggling an uppercase [X] checkbox in a numbered list.
 */
- (void)testToggleUppercaseNumberedListCheckbox
{
    NSString *markdown = @"1. [X] First numbered\n2. [ ] Second numbered";
    NSString *expected = @"1. [ ] First numbered\n2. [ ] Second numbered";

    NSString *result = [MPDocument toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Numbered list [X] checkbox should toggle correctly");
}

#pragma mark - URL Scheme Tests

/**
 * Test that the checkbox URL scheme is correctly formatted.
 */
- (void)testCheckboxURLSchemeFormat
{
    NSURL *url = [NSURL URLWithString:@"x-macdown-checkbox://toggle/0"];

    XCTAssertEqualObjects(url.scheme, @"x-macdown-checkbox",
                          @"URL scheme should be x-macdown-checkbox");
    XCTAssertEqualObjects(url.host, @"toggle",
                          @"URL host should be 'toggle'");
}

/**
 * Test extracting checkbox index from URL.
 */
- (void)testExtractCheckboxIndexFromURL
{
    NSURL *url = [NSURL URLWithString:@"x-macdown-checkbox://toggle/5"];

    NSString *path = url.path;
    NSInteger index = [[path substringFromIndex:1] integerValue];

    XCTAssertEqual(index, 5, @"Should extract index 5 from URL path");
}

/**
 * Test extracting checkbox index 0 from URL.
 */
- (void)testExtractCheckboxIndex0FromURL
{
    NSURL *url = [NSURL URLWithString:@"x-macdown-checkbox://toggle/0"];

    NSString *path = url.path;
    NSInteger index = [[path substringFromIndex:1] integerValue];

    XCTAssertEqual(index, 0, @"Should extract index 0 from URL path");
}

@end
