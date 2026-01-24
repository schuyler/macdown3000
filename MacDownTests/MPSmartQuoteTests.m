//
//  MPSmartQuoteTests.m
//  MacDown 3000
//
//  Tests for Issue #285: Smart quote substitution behavior.
//  Verifies that when smart quotes are enabled, custom code defers
//  to macOS's built-in smart quote handling for quote characters.
//

#import <XCTest/XCTest.h>
#import "NSTextView+Autocomplete.h"

#pragma mark - Mock Text View

/**
 * Mock NSTextView subclass for testing autocomplete behavior.
 * Allows controlled testing of smart quote settings without requiring
 * full window/document infrastructure.
 */
@interface MockTextViewForQuotes : NSTextView
@property (nonatomic) BOOL mockAutomaticQuoteSubstitutionEnabled;
@property (nonatomic, strong) NSString *insertedText;
@property (nonatomic) NSRange insertedRange;
@property (nonatomic) BOOL insertTextWasCalled;
@end

@implementation MockTextViewForQuotes

- (BOOL)isAutomaticQuoteSubstitutionEnabled
{
    return self.mockAutomaticQuoteSubstitutionEnabled;
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    self.insertTextWasCalled = YES;
    self.insertedText = string;
    self.insertedRange = replacementRange;
    // Don't call super - we're just tracking what would be inserted
}

@end

#pragma mark - Test Case

@interface MPSmartQuoteTests : XCTestCase
@property (strong) MockTextViewForQuotes *textView;
@end

@implementation MPSmartQuoteTests

- (void)setUp
{
    [super setUp];

    // Create mock text view with text storage
    self.textView = [[MockTextViewForQuotes alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];

    // Reset state
    self.textView.insertTextWasCalled = NO;
    self.textView.insertedText = nil;
    self.textView.mockAutomaticQuoteSubstitutionEnabled = NO;
}

- (void)tearDown
{
    self.textView = nil;
    [super tearDown];
}

#pragma mark - Smart Quotes Enabled: Custom Code Defers to macOS

/**
 * Test: Double quote typed with smart quotes ENABLED.
 * Expected: completeMatchingCharacterForText: returns NO.
 * macOS should handle the smart quote substitution.
 */
- (void)testDoubleQuoteWithSmartQuotesEnabledReturnsNO
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"\""
                                                        atLocation:6];

    XCTAssertFalse(handled,
        @"When smart quotes enabled, double quote should NOT be handled by custom code");
    XCTAssertFalse(self.textView.insertTextWasCalled,
        @"No text should be inserted by custom code");
}

/**
 * Test: Single quote typed with smart quotes ENABLED.
 * Expected: completeMatchingCharacterForText: returns NO.
 */
- (void)testSingleQuoteWithSmartQuotesEnabledReturnsNO
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"'"
                                                        atLocation:6];

    XCTAssertFalse(handled,
        @"When smart quotes enabled, single quote should NOT be handled by custom code");
    XCTAssertFalse(self.textView.insertTextWasCalled,
        @"No text should be inserted by custom code");
}

/**
 * Test: Quote at document start with smart quotes enabled.
 */
- (void)testQuoteAtDocumentStartWithSmartQuotesEnabled
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@""]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"\""
                                                        atLocation:0];

    XCTAssertFalse(handled,
        @"Quote at document start should defer to macOS when smart quotes enabled");
}

#pragma mark - Smart Quotes Disabled: Matching Pairs Work

/**
 * Test: Double quote typed with smart quotes DISABLED.
 * Expected: Matching pair behavior inserts both "" quotes.
 */
- (void)testDoubleQuoteWithSmartQuotesDisabledInsertsMatchingPair
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = NO;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"\""
                                                        atLocation:6];

    XCTAssertTrue(handled,
        @"When smart quotes disabled, double quote should be handled by custom code");
    XCTAssertTrue(self.textView.insertTextWasCalled,
        @"Text should be inserted");
    XCTAssertEqualObjects(self.textView.insertedText, @"\"\"",
        @"Should insert matching pair of straight quotes");
}

/**
 * Test: Single quote typed with smart quotes DISABLED.
 * Expected: Matching pair behavior inserts both '' quotes.
 */
- (void)testSingleQuoteWithSmartQuotesDisabledInsertsMatchingPair
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = NO;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"'"
                                                        atLocation:6];

    XCTAssertTrue(handled,
        @"When smart quotes disabled, single quote should be handled by custom code");
    XCTAssertTrue(self.textView.insertTextWasCalled,
        @"Text should be inserted");
    XCTAssertEqualObjects(self.textView.insertedText, @"''",
        @"Should insert matching pair of straight quotes");
}

#pragma mark - Non-Quote Characters: Always Use Matching Pairs

/**
 * Test: Parenthesis with smart quotes ENABLED.
 * Expected: Matching pair behavior still works for non-quote characters.
 */
- (void)testParenthesisWithSmartQuotesEnabledStillMatches
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"("
                                                        atLocation:6];

    XCTAssertTrue(handled,
        @"Parenthesis should still be handled even with smart quotes enabled");
    XCTAssertTrue(self.textView.insertTextWasCalled,
        @"Text should be inserted");
    XCTAssertEqualObjects(self.textView.insertedText, @"()",
        @"Should insert matching parentheses");
}

/**
 * Test: Square bracket with smart quotes ENABLED.
 */
- (void)testSquareBracketWithSmartQuotesEnabledStillMatches
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@""]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"["
                                                        atLocation:0];

    XCTAssertTrue(handled,
        @"Square bracket should still be handled with smart quotes enabled");
    XCTAssertEqualObjects(self.textView.insertedText, @"[]",
        @"Should insert matching brackets");
}

/**
 * Test: Curly brace with smart quotes ENABLED.
 */
- (void)testCurlyBraceWithSmartQuotesEnabledStillMatches
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@""]];

    BOOL handled = [self.textView completeMatchingCharacterForText:@"{"
                                                        atLocation:0];

    XCTAssertTrue(handled,
        @"Curly brace should still be handled with smart quotes enabled");
    XCTAssertEqualObjects(self.textView.insertedText, @"{}",
        @"Should insert matching braces");
}

#pragma mark - Integration: completeMatchingCharactersForTextInRange

/**
 * Test: Full method call with smart quotes enabled and quote character.
 */
- (void)testCompleteMatchingCharactersWithSmartQuotesEnabledAndQuote
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = YES;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    NSRange range = NSMakeRange(6, 0); // No selection, insert at position 6

    BOOL handled = [self.textView completeMatchingCharactersForTextInRange:range
                                                                withString:@"\""
                                                      strikethroughEnabled:YES];

    XCTAssertFalse(handled,
        @"When smart quotes enabled, quote should not be handled");
}

/**
 * Test: Full method call with smart quotes disabled and quote character.
 */
- (void)testCompleteMatchingCharactersWithSmartQuotesDisabledAndQuote
{
    self.textView.mockAutomaticQuoteSubstitutionEnabled = NO;
    [self.textView.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:@"Hello "]];

    NSRange range = NSMakeRange(6, 0);

    BOOL handled = [self.textView completeMatchingCharactersForTextInRange:range
                                                                withString:@"\""
                                                      strikethroughEnabled:YES];

    XCTAssertTrue(handled,
        @"When smart quotes disabled, quote should be handled");
}

@end
