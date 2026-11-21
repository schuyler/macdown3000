//
//  MPCheckboxToggleTests.m
//  MacDown 3000
//
//  Tests for checkbox toggle functionality (Issue #269).
//  These tests verify the source text manipulation when toggling checkboxes.
//

#import <XCTest/XCTest.h>
#import <hoedown/document.h>
#import "hoedown_html_patch.h"
#import "MPRendererTestHelpers.h"
#import "MPDocument.h"

@interface MPCheckboxToggleTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPCheckboxToggleTests

- (void)setUp
{
    [super setUp];

    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];
    self.delegate.extensions = HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE
        | HOEDOWN_EXT_FOOTNOTES;

    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self.dataSource;
    self.renderer.delegate = self.delegate;
    self.renderer.rendererFlags = HOEDOWN_HTML_USE_TASK_LIST;
}

- (void)tearDown
{
    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    [super tearDown];
}

/** Toggles the checkbox the test's renderer gives the index. */
- (NSString *)toggleCheckboxAtIndex:(NSUInteger)index
                         inMarkdown:(NSString *)markdown
{
    return [MPDocument toggleCheckboxAtIndex:index
                                  inMarkdown:markdown
                                    renderer:self.renderer];
}

#pragma mark - Toggle Unchecked -> Checked

/**
 * Test toggling the first unchecked checkbox to checked.
 */
- (void)testToggleFirstUncheckedToChecked
{
    NSString *markdown = @"- [ ] First task\n- [ ] Second task";
    NSString *expected = @"- [x] First task\n- [ ] Second task";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:1 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:2 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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
    NSString *result = [self toggleCheckboxAtIndex:1 inMarkdown:markdown];
    NSString *expected = @"- [x] First (done)\n- [x] Second (todo)\n- [x] Third (done)";

    XCTAssertEqualObjects(result, expected,
                          @"Second checkbox should be toggled to checked");
}

#pragma mark - Nested Lists

/**
 * Test toggling a nested checkbox.
 * Depth-first order: Child(0), Another child(1), Parent(2)
 */
- (void)testToggleNestedCheckbox
{
    NSString *markdown = @"- [ ] Parent\n  - [ ] Child\n  - [ ] Another child";
    NSString *expected = @"- [ ] Parent\n  - [x] Child\n  - [ ] Another child";

    // Child is depth-first index 0 (nested items come before parent)
    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Nested checkbox should be toggled correctly");
}

/**
 * Test toggling in deeply nested lists.
 * Hoedown takes up to four spaces off each line under an item, so with a
 * two-space step Level 2 and Level 3 are siblings inside Level 1, and the
 * renderer's order is Level2(0), Level3(1), Level1(2).
 */
- (void)testToggleDeeplyNestedCheckbox
{
    NSString *markdown = @"- [ ] Level 1\n  - [ ] Level 2\n    - [ ] Level 3";
    NSString *expected = @"- [ ] Level 1\n  - [x] Level 2\n    - [ ] Level 3";

    // Level 2 is the first checkbox the renderer numbers
    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Deeply nested checkbox should be toggled correctly");
}

/**
 * Test toggling the parent checkbox in a nested list.
 * Depth-first order: Child(0), Another child(1), Parent(2)
 */
- (void)testToggleParentCheckboxInNestedList
{
    NSString *markdown = @"- [ ] Parent\n  - [ ] Child\n  - [ ] Another child";
    NSString *expected = @"- [x] Parent\n  - [ ] Child\n  - [ ] Another child";

    // Parent is depth-first index 2 (comes after all children)
    NSString *result = [self toggleCheckboxAtIndex:2 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Parent checkbox should be toggled with correct depth-first index");
}

/**
 * Test that depth-first ordering works with multiple sibling parents.
 * Structure:
 *   - [ ] Parent1
 *     - [ ] Child1
 *   - [ ] Parent2
 * Depth-first order: Child1(0), Parent1(1), Parent2(2)
 */
- (void)testToggleWithMultipleSiblingParents
{
    NSString *markdown = @"- [ ] Parent1\n  - [ ] Child1\n- [ ] Parent2";
    NSString *expected = @"- [x] Parent1\n  - [ ] Child1\n- [ ] Parent2";

    // Parent1 is depth-first index 1 (after Child1, before Parent2)
    NSString *result = [self toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Parent1 should be at depth-first index 1");
}

#pragma mark - Edge Cases

/**
 * Test toggling checkbox with inline formatting.
 */
- (void)testToggleCheckboxWithInlineFormatting
{
    NSString *markdown = @"- [ ] Task with **bold** and *italic*";
    NSString *expected = @"- [x] Task with **bold** and *italic*";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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
    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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
    NSString *result = [self toggleCheckboxAtIndex:5 inMarkdown:markdown];

    XCTAssertEqualObjects(result, markdown,
                          @"Invalid index should return unchanged markdown");
}

/**
 * Test toggling on empty document.
 */
- (void)testToggleOnEmptyDocument
{
    NSString *markdown = @"";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, markdown,
                          @"Empty document should return empty string");
}

/**
 * Test toggling on document with no checkboxes.
 */
- (void)testToggleOnDocumentWithNoCheckboxes
{
    NSString *markdown = @"Just some text\n- Regular list item\n- Another item";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Asterisk marker checkbox should toggle correctly");
}

- (void)testToggleUppercaseCheckedCheckbox
{
    NSString *markdown = @"- [X] Done";
    NSString *expected = @"- [ ] Done";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:1 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:1 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

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

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Numbered list [X] checkbox should toggle correctly");
}

#pragma mark - Indeterminate Checkbox Tests

/**
 * Test that clicking an indeterminate [-] checkbox resolves it to done, the
 * way a click on an indeterminate checkbox behaves on macOS.
 * See https://github.com/orgs/community/discussions/19199.
 */
- (void)testToggleIndeterminateToChecked
{
    NSString *markdown = @"- [-] Partly done";
    NSString *expected = @"- [x] Partly done";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"An indeterminate checkbox should toggle to checked");
}

/**
 * Test that an indeterminate [-] occupies an index, keeping the checkboxes
 * after it aligned with the indices the renderer emits. Without this, a click
 * on the second preview checkbox would rewrite the wrong source line.
 */
- (void)testIndeterminateCheckboxOccupiesIndex
{
    NSString *markdown = @"- [-] First (partly)\n- [ ] Second\n- [x] Third";
    NSString *expected = @"- [-] First (partly)\n- [x] Second\n- [x] Third";

    NSString *result = [self toggleCheckboxAtIndex:1 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"[-] should occupy index 0 so index 1 hits the second item");
}

/**
 * Test toggling an indeterminate checkbox in a numbered list.
 */
- (void)testToggleIndeterminateNumberedListCheckbox
{
    NSString *markdown = @"1. [-] First numbered\n2. [ ] Second numbered";
    NSString *expected = @"1. [x] First numbered\n2. [ ] Second numbered";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Numbered list [-] checkbox should toggle correctly");
}

/**
 * Test that a nested [-] keeps the depth-first index order the renderer uses
 * (children before their parent), so a click on the first preview checkbox
 * addresses the right line. Depth-first order here: Partly done(0), Parent(1),
 * Other parent(2).
 */
- (void)testNestedIndeterminateCheckboxIndexOrder
{
    NSString *markdown = @"- [ ] Parent\n  - [-] Partly done\n- [-] Other parent";
    NSString *expected = @"- [ ] Parent\n  - [x] Partly done\n- [-] Other parent";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Index 0 is the nested [-] in depth-first order, not the parent");
}

/**
 * Test that an indeterminate-looking marker inside a fenced code block is not
 * treated as a checkbox, so the preview's indices stay aligned. Only fenced
 * blocks are skipped, not indented ones.
 */
- (void)testIndeterminateCheckboxInFencedCodeBlockIsIgnored
{
    NSString *markdown = @"```\n- [-] Not a real checkbox\n```\n\n- [-] Real checkbox";
    NSString *expected = @"```\n- [-] Not a real checkbox\n```\n\n- [x] Real checkbox";

    NSString *result = [self toggleCheckboxAtIndex:0 inMarkdown:markdown];

    XCTAssertEqualObjects(result, expected,
                          @"Only real checkboxes outside code blocks should be counted");
}

#pragma mark - Agreement with the Renderer

/**
 * Renders the Markdown with the test's renderer, the way a document does,
 * and returns the state of each checkbox ("unchecked", "checked" or
 * "indeterminate") ordered by the index the preview sends when that
 * checkbox is clicked. *otherHTML receives the HTML with the checkboxes'
 * states taken out.
 */
- (NSArray<NSString *> *)renderedCheckboxStatesForMarkdown:(NSString *)markdown
                                                 otherHTML:(NSString **)other
{
    self.dataSource.markdown = markdown;
    [self.renderer parseMarkdown:markdown];
    NSString *html = self.renderer.currentHtml;

    NSString *pattern = @"<input type=\"checkbox\"( checked"
        @"| data-checkbox-state=\"indeterminate\")?"
        @" data-checkbox-index=\"(\\d+)\">";
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0
                                                    error:NULL];
    NSMutableDictionary<NSNumber *, NSString *> *stateByIndex =
        [NSMutableDictionary dictionary];
    NSRange all = NSMakeRange(0, html.length);
    for (NSTextCheckingResult *match in
            [regex matchesInString:html options:0 range:all])
    {
        NSString *state = @"unchecked";
        NSRange attributeRange = [match rangeAtIndex:1];
        if (attributeRange.location != NSNotFound)
        {
            NSString *attribute = [html substringWithRange:attributeRange];
            state = [attribute isEqualToString:@" checked"]
                ? @"checked" : @"indeterminate";
        }
        NSString *index = [html substringWithRange:[match rangeAtIndex:2]];
        stateByIndex[@(index.integerValue)] = state;
    }
    if (other)
    {
        *other = [regex
            stringByReplacingMatchesInString:html options:0 range:all
                                withTemplate:@"<input index=\"$2\">"];
    }

    NSMutableArray<NSString *> *states = [NSMutableArray array];
    for (NSUInteger index = 0; index < stateByIndex.count; index++)
    {
        XCTAssertNotNil(stateByIndex[@(index)],
                        @"Rendered checkbox indexes should be 0..n-1: %@",
                        html);
        [states addObject:stateByIndex[@(index)] ?: @"missing"];
    }
    return states;
}

/**
 * Asserts that the Markdown renders the given number of checkboxes, and that
 * toggling each rendered checkbox's index in the source changes the rendered
 * state of that checkbox and nothing else in the rendered HTML.
 */
- (void)assertRenderedCheckboxes:(NSUInteger)count
           toggleInPlaceInMarkdown:(NSString *)markdown
{
    NSString *otherBefore = nil;
    NSArray<NSString *> *before =
        [self renderedCheckboxStatesForMarkdown:markdown
                                      otherHTML:&otherBefore];
    XCTAssertEqual(before.count, count,
                   @"Rendered checkbox count for: %@", markdown);

    for (NSUInteger index = 0; index < before.count; index++)
    {
        NSMutableArray<NSString *> *expected = [before mutableCopy];
        expected[index] = [before[index] isEqualToString:@"checked"]
            ? @"unchecked" : @"checked";

        NSString *toggled = [self toggleCheckboxAtIndex:index
                                             inMarkdown:markdown];
        NSString *otherAfter = nil;
        NSArray<NSString *> *after =
            [self renderedCheckboxStatesForMarkdown:toggled
                                          otherHTML:&otherAfter];
        XCTAssertEqualObjects(
            after, expected,
            @"Toggling index %lu should change only that checkbox in: %@",
            index, markdown);
        XCTAssertEqualObjects(
            otherAfter, otherBefore,
            @"Toggling index %lu should change nothing else in: %@",
            index, markdown);
    }

    NSString *past = [self toggleCheckboxAtIndex:before.count
                                      inMarkdown:markdown];
    XCTAssertEqualObjects(past, markdown,
                          @"An index past the last rendered checkbox should "
                          @"change nothing in: %@", markdown);
}

/**
 * Test that task items inside a blockquote toggle, since the renderer shows
 * a checkbox for each.
 */
- (void)testBlockquoteCheckboxesToggleInPlace
{
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"> - [ ] quoted\n\n- [ ] plain\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [x] before\n\n>- [ ] quoted\n\n- [ ] after\n"];
    [self assertRenderedCheckboxes:4 toggleInPlaceInMarkdown:
        @"> - [ ] parent\n>     - [x] child\n> - [-] sibling\n\n"
        @"- [ ] plain\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"> > - [ ] nested quote\n\n1. [ ] plain\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"> - [ ] first\n\n> - [x] after blank\n\n- [ ] plain\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"> - [ ] parent\n    - [x] unquoted child\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"> - [ ] quoted\n- [x] directly after\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"> - [ ] quoted\n- [ ] after\n\n    - [x] child\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"> - [ ] quoted\n\n  - [x] separate\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"> > - [ ] inner\n>   - [x] outer line\n"];
}

/**
 * Test that a blockquote marker which does not start a blockquote changes
 * nothing: a `>` line under a list item is that item's text.
 */
- (void)testQuoteMarkersInsideListItemsToggleInPlace
{
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] item\n> note\n\n    - [x] child\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] first\n> - [ ] text of first\n\nText\n\n- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] item\n  ```\n> code\n  ```\n  - [x] child\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] parent\n\n  > quote in item\n\n    - [x] child\n\n"
        @"- [ ] next\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"> - [ ] heading text\n---\n\n- [ ] real\n"];
}

/**
 * Test that a task-like line in an indented code block is not taken for a
 * checkbox, while an equally indented nested task item still is.
 */
- (void)testIndentedCodeIsNotCounted
{
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"Text\n\n    - [ ] code\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"\t- [ ] code\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] first\n\nText\n\n    - [ ] code\n\n- [ ] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] item\n\n        - [ ] code in item\n\n- [ ] next\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @">     - [ ] quoted code\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"```\n- fenced\n```\n\n    - [ ] code\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] a\n\n        code\ntext\n\n    - [x] b\n\n- [ ] c\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"Note[^1] here.\n\n[^1]: Details:\n\n    - [ ] in footnote\n"];
}

/**
 * Test that task-like lines in an HTML comment or HTML block are not taken
 * for checkboxes.
 */
- (void)testHTMLBlocksAreNotCounted
{
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"<!--\n- [ ] comment\n-->\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"<div>\n- [ ] html\n</div>\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"<pre>\n- [ ] pre\n</pre>\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"<div>\n- [ ] html\n</div>\nNote.\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"<!--\n- [ ] comment\n-->\nNote.\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"<div>\n<div>\n</div>\nText\n- [ ] html\n</div>\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"- [ ] real\n\n<DIV class=\"x\">\n- [ ] html\n</div>\n"];
}

/**
 * Test that checkboxes next to HTML, or inside what only looks like an HTML
 * block, toggle: the renderer shows them.
 */
- (void)testCheckboxesOutsideHTMLBlocksToggleInPlace
{
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<!-- note --> text\n- [ ] first\n\n- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"Text\n<!--\n- [ ] first\n-->\n\n- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<!--\n- [ ] first\n--> text\n\n- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<span>\n- [ ] first\n</span>\n\n- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<div>\n- [ ] first\n\n- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<p align=\"center\"><img src=\"logo.png\"></p>\n- [ ] first\n"
        @"- [x] second\n\n<p>Footer</p>\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<div>\none\n</div>\n- [ ] first\n\n<div>\ntwo\n</div>\n\n"
        @"- [x] second\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"<div>\n<div>\n</div>\n- [ ] inside\n</div>\n\n- [x] outside\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"```html\n\n<div>\n</div>\n```\n\n- [ ] first\n\n<div>\nx\n</div>\n\n"
        @"- [x] second\n"];
}

/**
 * Test that task-like lines in fenced code are not taken for checkboxes: a
 * fence closes only on a fence of its own length, and a fence inside a
 * blockquote ends with the blockquote.
 */
- (void)testFencedCodeIsNotCounted
{
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"````\n```\n- [ ] code\n```\n````\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"```\n- [ ] code\n```\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"~~~\n- [ ] code\n~~~\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"> ```\n> - [ ] code\n> ```\n\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"```md\n> ```\n```\n\n- [ ] real\n\n```\ncode\n```\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"> ```\n> code\n\n- [ ] real\n\n```\ncode\n```\n"];
}

/**
 * Test that the renderer's options decide: with fenced code turned off a
 * fence is text, and the task item between two fences is a checkbox.
 */
- (void)testFencedCodeExtensionOffTogglesInPlace
{
    self.delegate.extensions = HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FOOTNOTES;
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"```\n- [ ] not code\n```\n\n- [x] real\n"];
}

/**
 * Test that nested and loose lists toggle in place.
 */
- (void)testNestedListCheckboxesToggleInPlace
{
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] parent\n    - [x] child\n- [ ] sibling\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] parent\n  - [x] child\n- [ ] sibling\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] Level 1\n  - [x] Level 2\n    - [ ] Level 3"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- plain parent\n    - [ ] child\n\n- [x] sibling\n"];
    [self assertRenderedCheckboxes:4 toggleInPlaceInMarkdown:
        @"1. [ ] one\n    - [ ] two\n        - [x] three\n2. [ ] four\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] loose\n\n    - [x] child after blank\n\n- [ ] sibling\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] item\n\n  continued\n\n- [x] next\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"Text\n- [ ] after text\n- [x] next\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] item\nlazy line\n\n    - [x] child\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] item\n```\ncode\n```\n  - [x] after code\n"];
}

/**
 * Test list markers followed by more than one space or by a tab: checkboxes
 * in a loose list, text in a tight one.
 */
- (void)testMarkerSpacingTogglesInPlace
{
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"-   [ ] wide marker\n\n-   [x] loose list\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"1.\t[ ] tab marker\n\n2.\t[x] loose list\n"];
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"-   [ ] wide marker\n\n- [x] narrow marker\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"-   [ ] wide in a tight list\n- [ ] real\n"];
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:
        @"- [ ](http://example.com) a link\n- [ ] real\n"];
}

/**
 * Test that a list which starts after another has ended is not taken for a
 * child of the earlier one, however it is indented.
 */
- (void)testSeparateListsToggleInPlace
{
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:
        @"- [ ] first list\n\nText\n\n  - [x] second list\n"];
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"- [ ] first\n\n# Heading\n\n   - [x] second\n   - [ ] third\n"];
}

/**
 * Test that front matter is left out when the renderer leaves it out, and
 * read as Markdown when it does not.
 */
- (void)testFrontMatterTogglesInPlace
{
    NSString *markdown = @"---\n- [ ] in front\nk: v\n---\n\n- [x] real\n";

    self.delegate.detectFrontMatter = YES;
    [self assertRenderedCheckboxes:1 toggleInPlaceInMarkdown:markdown];

    self.delegate.detectFrontMatter = NO;
    [self assertRenderedCheckboxes:2 toggleInPlaceInMarkdown:markdown];
}

/**
 * Test with the table of contents and SmartyPants on, which a document's
 * render runs and the lookup does not.
 */
- (void)testTOCAndSmartyPantsToggleInPlace
{
    self.delegate.renderTOC = YES;
    self.delegate.smartyPants = YES;
    [self assertRenderedCheckboxes:3 toggleInPlaceInMarkdown:
        @"[TOC]\n\n# \"First\" -- heading\n\n- [ ] \"quoted\" -- task\n"
        @"    - [x] child...\n\n## Second\n\n- [-] it's last\n"];
}

#pragma mark - Clicks That Change Nothing

/**
 * Test a checkbox whose line is not found in the source: a list on the
 * first line of a footnote definition. Its click changes nothing, whether
 * the checkbox is open or done.
 */
- (void)testCheckboxOnAnUnrecognizedLineIsLeftAlone
{
    NSString *open = @"- [ ] a\n\nText[^1]\n\n[^1]: - [ ] note\n";
    NSArray *states = [self renderedCheckboxStatesForMarkdown:open
                                                    otherHTML:NULL];
    XCTAssertEqualObjects(states, (@[@"unchecked", @"unchecked"]));
    XCTAssertEqualObjects([self toggleCheckboxAtIndex:1 inMarkdown:open],
                          open);

    // Done, it reads as checked in every lookup render, like the last of
    // the lines that were found. Only the states of the result give it away.
    NSString *done = @"- [ ] a\n\nText[^1]\n\n[^1]: - [x] note\n";
    states = [self renderedCheckboxStatesForMarkdown:done otherHTML:NULL];
    XCTAssertEqualObjects(states, (@[@"unchecked", @"checked"]));
    XCTAssertEqualObjects([self toggleCheckboxAtIndex:1 inMarkdown:done],
                          done);
}

/**
 * Test a document in which the state character decides how a line parses:
 * with a link reference named x, `[x]` is a link and `[ ]` a checkbox. A
 * click changes nothing.
 */
- (void)testStateCharacterThatIsALinkReferenceIsLeftAlone
{
    NSString *markdown =
        @"[x]: http://example.com\n\n- [x] a link\n- [ ] real\n";
    NSArray *states = [self renderedCheckboxStatesForMarkdown:markdown
                                                    otherHTML:NULL];
    XCTAssertEqualObjects(states, (@[@"unchecked"]));
    XCTAssertEqualObjects([self toggleCheckboxAtIndex:0 inMarkdown:markdown],
                          markdown);
}

/**
 * Test a document in which the state character of one line decides which
 * line is the checkbox. With x on line 3, lines 2 and 3 are a link reference
 * definition and line 4 is the checkbox; with a space, line 3 is. Changing
 * line 3 would flip the one checkbox and change the rest of the page.
 */
- (void)testStateCharacterThatMovesTheCheckboxIsLeftAlone
{
    NSString *markdown = @"- \n[id]:\n>1.\t[x]\n  [x] A\n\n- b\n";
    NSArray *states = [self renderedCheckboxStatesForMarkdown:markdown
                                                    otherHTML:NULL];
    XCTAssertEqualObjects(states, (@[@"checked"]));
    XCTAssertEqualObjects([self toggleCheckboxAtIndex:0 inMarkdown:markdown],
                          markdown);
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
