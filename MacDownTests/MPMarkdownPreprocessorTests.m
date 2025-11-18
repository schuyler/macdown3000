//
//  MPMarkdownPreprocessorTests.m
//  MacDown
//
//  Tests for markdown preprocessing to fix list rendering issues.
//  See GitHub issue #34: Lists after colons render as single line
//

#import <XCTest/XCTest.h>
#import "MPMarkdownPreprocessor.h"

@interface MPMarkdownPreprocessorTests : XCTestCase
@end

@implementation MPMarkdownPreprocessorTests

#pragma mark - Core Functionality

- (void)testBasicUnorderedListAfterColon
{
    NSString *input = @"Here is my list:\n- Item 1\n- Item 2\n- Item 3";
    NSString *expected = @"Here is my list:\n\n- Item 1\n- Item 2\n- Item 3";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line between colon and list");
}

- (void)testBasicOrderedListAfterColon
{
    NSString *input = @"My numbered list:\n1. First item\n2. Second item";
    NSString *expected = @"My numbered list:\n\n1. First item\n2. Second item";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line between colon and ordered list");
}

- (void)testListAfterColonWithExistingBlankLine
{
    NSString *input = @"Here is my list:\n\n- Item 1\n- Item 2";
    NSString *expected = @"Here is my list:\n\n- Item 1\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not add duplicate blank line when one already exists");
}

- (void)testListInsideTripleBacktickCodeBlock
{
    NSString *input = @"Example:\n```\nList:\n- Item 1\n- Item 2\n```";
    NSString *expected = @"Example:\n```\nList:\n- Item 1\n- Item 2\n```";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not modify lists inside fenced code blocks");
}

- (void)testEmptyDocument
{
    NSString *input = @"";
    NSString *expected = @"";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should handle empty document without crashing");
}

#pragma mark - Important Edge Cases

- (void)testTaskListAfterColon
{
    NSString *input = @"My tasks:\n- [ ] Task 1\n- [x] Task 2";
    NSString *expected = @"My tasks:\n\n- [ ] Task 1\n- [x] Task 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line before task lists");
}

- (void)testListAfterNormalParagraph
{
    NSString *input = @"Here is some text\n- Item 1\n- Item 2";
    NSString *expected = @"Here is some text\n\n- Item 1\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line after regular paragraph (not just colons)");
}

- (void)testMultipleListsInDocument
{
    NSString *input = @"First list:\n- A\n- B\n\nSecond list:\n- C\n- D";
    NSString *expected = @"First list:\n\n- A\n- B\n\nSecond list:\n\n- C\n- D";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should fix all list occurrences in document");
}

- (void)testListInsideTildeCodeBlock
{
    NSString *input = @"Example:\n~~~\nList:\n- Item 1\n- Item 2\n~~~";
    NSString *expected = @"Example:\n~~~\nList:\n- Item 1\n- Item 2\n~~~";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not modify lists inside tilde-fenced code blocks");
}

- (void)testListAtStartOfDocument
{
    NSString *input = @"- Item 1\n- Item 2";
    NSString *expected = @"- Item 1\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should handle list at document start without changes");
}

- (void)testVariousUnorderedListMarkers
{
    // Test dash marker
    NSString *inputDash = @"List:\n- Item 1";
    NSString *expectedDash = @"List:\n\n- Item 1";
    NSString *outputDash = [MPMarkdownPreprocessor preprocessForListInterruption:inputDash];
    XCTAssertEqualObjects(outputDash, expectedDash,
        @"Should handle dash list marker");

    // Test asterisk marker
    NSString *inputAsterisk = @"List:\n* Item 1";
    NSString *expectedAsterisk = @"List:\n\n* Item 1";
    NSString *outputAsterisk = [MPMarkdownPreprocessor preprocessForListInterruption:inputAsterisk];
    XCTAssertEqualObjects(outputAsterisk, expectedAsterisk,
        @"Should handle asterisk list marker");

    // Test plus marker
    NSString *inputPlus = @"List:\n+ Item 1";
    NSString *expectedPlus = @"List:\n\n+ Item 1";
    NSString *outputPlus = [MPMarkdownPreprocessor preprocessForListInterruption:inputPlus];
    XCTAssertEqualObjects(outputPlus, expectedPlus,
        @"Should handle plus list marker");
}

- (void)testDashInMiddleOfLine
{
    NSString *input = @"Description:\nItem - not a list";
    NSString *expected = @"Description:\nItem - not a list";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not treat dash in middle of line as list marker");
}

#pragma mark - Advanced Edge Cases

- (void)testNestedListAfterColon
{
    NSString *input = @"My list:\n- Item 1\n  - Nested 1\n  - Nested 2\n- Item 2";
    NSString *expected = @"My list:\n\n- Item 1\n  - Nested 1\n  - Nested 2\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should preserve nested list structure");
}

- (void)testListInsideBlockquote
{
    NSString *input = @"> Quote text:\n> - Item 1\n> - Item 2";
    NSString *expected = @"> Quote text:\n> - Item 1\n> - Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not modify lists inside blockquotes");
}

- (void)testFencedCodeBlockWithLanguageSpecifier
{
    NSString *input = @"Python example:\n```python\n# Comments:\n- Not a list\n```";
    NSString *expected = @"Python example:\n```python\n# Comments:\n- Not a list\n```";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not modify code blocks with language specifiers");
}

- (void)testWindowsLineEndings
{
    NSString *input = @"Here is my list:\r\n- Item 1\r\n- Item 2";
    NSString *expected = @"Here is my list:\r\n\r\n- Item 1\r\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should handle Windows line endings (CRLF)");
}

- (void)testDocumentWithOnlyNewlines
{
    NSString *input = @"\n\n\n";
    NSString *expected = @"\n\n\n";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should handle whitespace-only documents");
}

- (void)testListAfterColonWithMultipleBlankLines
{
    NSString *input = @"Here is my list:\n\n\n- Item 1";
    NSString *expected = @"Here is my list:\n\n\n- Item 1";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should preserve multiple blank lines");
}

- (void)testMultiDigitOrderedLists
{
    NSString *input = @"My list:\n1. Item\n10. Item\n100. Item";
    NSString *expected = @"My list:\n\n1. Item\n10. Item\n100. Item";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should handle multi-digit ordered lists");
}

- (void)testNumberedItemWithoutDot
{
    NSString *input = @"Numbers:\n1 First\n2 Second";
    NSString *expected = @"Numbers:\n1 First\n2 Second";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not treat numbers without dots as lists");
}

- (void)testBlockquoteFollowedByList
{
    NSString *input = @"> Quote text\n- Item 1";
    NSString *expected = @"> Quote text\n\n- Item 1";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line after blockquote before list");
}

- (void)testListAfterHeading
{
    NSString *input = @"# Heading\n- Item 1\n- Item 2";
    NSString *expected = @"# Heading\n\n- Item 1\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line after heading before list");
}

- (void)testListAfterParagraphWithPeriod
{
    NSString *input = @"Here is my list.\n- Item 1\n- Item 2";
    NSString *expected = @"Here is my list.\n\n- Item 1\n- Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line after paragraph ending with period");
}

- (void)testListInsideIndentedCodeBlock
{
    NSString *input = @"Example:\n    List:\n    - Item 1\n    - Item 2";
    NSString *expected = @"Example:\n    List:\n    - Item 1\n    - Item 2";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should not modify lists inside indented code blocks (4 spaces)");
}

- (void)testListAfterSetextHeading
{
    NSString *input = @"Heading\n=======\n- Item 1";
    NSString *expected = @"Heading\n=======\n\n- Item 1";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line after setext heading before list");
}

- (void)testListAfterHorizontalRule
{
    NSString *input = @"---\n- Item 1";
    NSString *expected = @"---\n\n- Item 1";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should insert blank line after horizontal rule before list");
}

- (void)testIndentedListAfterParagraph
{
    NSString *input = @"Text:\n    - Indented list";
    NSString *expected = @"Text:\n\n    - Indented list";
    NSString *output = [MPMarkdownPreprocessor preprocessForListInterruption:input];
    XCTAssertEqualObjects(output, expected,
        @"Should handle lists with leading indentation");
}

@end
