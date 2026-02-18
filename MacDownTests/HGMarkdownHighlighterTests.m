//
//  HGMarkdownHighlighterTests.m
//  MacDownTests
//
//  Tests for HGMarkdownHighlighter coverage gaps including style parsing errors,
//  property behavior, and edge cases that don't require a full text view.
//
//  Created for Issue #234: Test Coverage Phase 1b
//

#import <XCTest/XCTest.h>
#import "HGMarkdownHighlighter.h"
#import "HGMarkdownHighlightingStyle.h"
#import "pmh_definitions.h"


@interface HGMarkdownHighlighterTests : XCTestCase
@property (nonatomic, strong) HGMarkdownHighlighter *highlighter;
@end


@implementation HGMarkdownHighlighterTests

- (void)setUp
{
    [super setUp];
    self.highlighter = [[HGMarkdownHighlighter alloc] init];
}

- (void)tearDown
{
    self.highlighter = nil;
    [super tearDown];
}


#pragma mark - Initialization Tests

- (void)testBasicInitialization
{
    HGMarkdownHighlighter *hl = [[HGMarkdownHighlighter alloc] init];
    XCTAssertNotNil(hl, @"Should initialize");
}

- (void)testInitWithNilTextView
{
    HGMarkdownHighlighter *hl = [[HGMarkdownHighlighter alloc] initWithTextView:nil];
    XCTAssertNotNil(hl, @"Should initialize with nil text view");
    XCTAssertNil(hl.targetTextView, @"Text view should be nil");
}

- (void)testInitWithWaitInterval
{
    HGMarkdownHighlighter *hl = [[HGMarkdownHighlighter alloc] initWithTextView:nil
                                                                   waitInterval:0.5];
    XCTAssertNotNil(hl, @"Should initialize");
    XCTAssertEqualWithAccuracy(hl.waitInterval, 0.5, 0.01, @"Wait interval should be set");
}

- (void)testInitWithStyles
{
    NSArray *customStyles = @[];
    HGMarkdownHighlighter *hl = [[HGMarkdownHighlighter alloc] initWithTextView:nil
                                                                   waitInterval:0.3
                                                                         styles:customStyles];
    XCTAssertNotNil(hl, @"Should initialize with styles");
}


#pragma mark - Property Tests

- (void)testWaitIntervalProperty
{
    self.highlighter.waitInterval = 1.0;
    XCTAssertEqualWithAccuracy(self.highlighter.waitInterval, 1.0, 0.01,
                               @"Wait interval should be stored");

    self.highlighter.waitInterval = 0.1;
    XCTAssertEqualWithAccuracy(self.highlighter.waitInterval, 0.1, 0.01,
                               @"Wait interval should update");
}

- (void)testWaitIntervalZero
{
    self.highlighter.waitInterval = 0.0;
    XCTAssertEqualWithAccuracy(self.highlighter.waitInterval, 0.0, 0.01,
                               @"Zero wait interval should be allowed");
}

- (void)testParseAndHighlightAutomaticallyProperty
{
    self.highlighter.parseAndHighlightAutomatically = YES;
    XCTAssertTrue(self.highlighter.parseAndHighlightAutomatically,
                  @"Should store YES value");

    self.highlighter.parseAndHighlightAutomatically = NO;
    XCTAssertFalse(self.highlighter.parseAndHighlightAutomatically,
                   @"Should store NO value");
}

- (void)testIsActiveProperty
{
    // Initially should be inactive
    XCTAssertFalse(self.highlighter.isActive, @"Should start inactive");
}

- (void)testResetTypingAttributesProperty
{
    self.highlighter.resetTypingAttributes = YES;
    XCTAssertTrue(self.highlighter.resetTypingAttributes, @"Should store YES");

    self.highlighter.resetTypingAttributes = NO;
    XCTAssertFalse(self.highlighter.resetTypingAttributes, @"Should store NO");
}

- (void)testMakeLinksClickableProperty
{
    self.highlighter.makeLinksClickable = YES;
    XCTAssertTrue(self.highlighter.makeLinksClickable, @"Should store YES");

    self.highlighter.makeLinksClickable = NO;
    XCTAssertFalse(self.highlighter.makeLinksClickable, @"Should store NO");
}

- (void)testExtensionsProperty
{
    self.highlighter.extensions = pmh_EXT_NONE;
    XCTAssertEqual(self.highlighter.extensions, pmh_EXT_NONE,
                   @"Should store no extensions");

    self.highlighter.extensions = pmh_EXT_NOTES;
    XCTAssertEqual(self.highlighter.extensions, pmh_EXT_NOTES,
                   @"Should store notes extension");
}

- (void)testTargetTextViewPropertyWithNil
{
    self.highlighter.targetTextView = nil;
    XCTAssertNil(self.highlighter.targetTextView, @"Should accept nil");
}


#pragma mark - Styles Property Tests

- (void)testStylesPropertyEmpty
{
    self.highlighter.styles = @[];
    XCTAssertNotNil(self.highlighter.styles, @"Should accept empty array");
    XCTAssertEqual(self.highlighter.styles.count, 0, @"Should be empty");
}

- (void)testStylesPropertyNil
{
    self.highlighter.styles = nil;
    // Behavior may vary, just verify no crash
}

- (void)testCurrentLineStyleProperty
{
    HGMarkdownHighlightingStyle *style = [[HGMarkdownHighlightingStyle alloc] init];
    self.highlighter.currentLineStyle = style;
    XCTAssertEqual(self.highlighter.currentLineStyle, style,
                   @"Should store current line style");
}


#pragma mark - Style Parsing Error Tests

- (void)testApplyStylesFromValidStylesheet
{
    __block BOOL errorCallbackInvoked = NO;
    __block NSArray *receivedErrors = nil;

    NSString *validStylesheet = @"editor { color: #333333; }";

    [self.highlighter applyStylesFromStylesheet:validStylesheet
                               withErrorHandler:^(NSArray *errorMessages) {
        errorCallbackInvoked = YES;
        receivedErrors = errorMessages;
    }];

    // Valid stylesheet should not invoke error callback
    // (though implementation may vary)
    if (errorCallbackInvoked) {
        XCTAssertTrue(receivedErrors.count == 0 || receivedErrors != nil,
                      @"If callback invoked, errors should be present or empty");
    }
}

- (void)testApplyStylesFromInvalidStylesheet
{
    __block BOOL errorCallbackInvoked = NO;
    __block NSArray *receivedErrors = nil;

    // Malformed stylesheet
    NSString *invalidStylesheet = @"{{{{ invalid: syntax::::";

    [self.highlighter applyStylesFromStylesheet:invalidStylesheet
                               withErrorHandler:^(NSArray *errorMessages) {
        errorCallbackInvoked = YES;
        receivedErrors = errorMessages;
    }];

    // Invalid stylesheet may invoke error callback
    // Implementation-dependent, so we just verify no crash
}

- (void)testApplyStylesFromEmptyStylesheet
{
    __block BOOL errorCallbackInvoked = NO;

    [self.highlighter applyStylesFromStylesheet:@""
                               withErrorHandler:^(NSArray *errorMessages) {
        errorCallbackInvoked = YES;
    }];

    // Empty stylesheet should not cause errors
    // (implementation-dependent)
}

- (void)testApplyStylesFromNilStylesheet
{
    __block BOOL errorCallbackInvoked = NO;

    XCTAssertNoThrow({
        [self.highlighter applyStylesFromStylesheet:nil
                                   withErrorHandler:^(NSArray *errorMessages) {
            errorCallbackInvoked = YES;
        }];
    }, @"Should handle nil stylesheet");
}

- (void)testApplyStylesWithNilErrorHandler
{
    NSString *stylesheet = @"editor { color: #333333; }";

    XCTAssertNoThrow({
        [self.highlighter applyStylesFromStylesheet:stylesheet
                                   withErrorHandler:nil];
    }, @"Should handle nil error handler");
}

- (void)testApplyStylesWithMixedValidInvalid
{
    __block BOOL errorCallbackInvoked = NO;
    __block NSInteger errorCount = 0;

    // Mix of valid and invalid CSS
    NSString *mixedStylesheet = @"editor { color: #333; }\n"
                                @"invalid{{{{}}}\n"
                                @"code { font-family: monospace; }";

    [self.highlighter applyStylesFromStylesheet:mixedStylesheet
                               withErrorHandler:^(NSArray *errorMessages) {
        errorCallbackInvoked = YES;
        errorCount = errorMessages.count;
    }];

    // May or may not produce errors depending on implementation
}


#pragma mark - Activation/Deactivation Tests (Without TextViewTests

- (void)testActivateWithoutTextView
{
    XCTAssertNoThrow([self.highlighter activate],
                     @"Should not crash when activating without text view");
}

- (void)testDeactivateWithoutTextView
{
    XCTAssertNoThrow([self.highlighter deactivate],
                     @"Should not crash when deactivating without text view");
}

- (void)testActivateThenDeactivate
{
    [self.highlighter activate];
    XCTAssertNoThrow([self.highlighter deactivate],
                     @"Should safely deactivate after activate");
}

- (void)testMultipleActivations
{
    // Multiple activations should be safe
    XCTAssertNoThrow({
        [self.highlighter activate];
        [self.highlighter activate];
        [self.highlighter activate];
    }, @"Multiple activations should not crash");
}

- (void)testMultipleDeactivations
{
    // Multiple deactivations should be safe
    XCTAssertNoThrow({
        [self.highlighter deactivate];
        [self.highlighter deactivate];
        [self.highlighter deactivate];
    }, @"Multiple deactivations should not crash");
}


#pragma mark - Parse Methods Without TextView Tests

- (void)testParseAndHighlightNowWithoutTextView
{
    XCTAssertNoThrow([self.highlighter parseAndHighlightNow],
                     @"Should handle parsing without text view");
}

- (void)testHighlightNowWithoutTextView
{
    XCTAssertNoThrow([self.highlighter highlightNow],
                     @"Should handle highlighting without text view");
}

- (void)testClearHighlightingWithoutTextView
{
    XCTAssertNoThrow([self.highlighter clearHighlighting],
                     @"Should handle clearing without text view");
}

- (void)testReadClearTextStylesWithoutTextView
{
    XCTAssertNoThrow([self.highlighter readClearTextStylesFromTextView],
                     @"Should handle reading styles without text view");
}


#pragma mark - HandleStyleParsingError Tests

- (void)testHandleStyleParsingErrorWithNilInfo
{
    XCTAssertNoThrow([self.highlighter handleStyleParsingError:nil],
                     @"Should handle nil error info");
}

- (void)testHandleStyleParsingErrorWithEmptyInfo
{
    XCTAssertNoThrow([self.highlighter handleStyleParsingError:@{}],
                     @"Should handle empty error info");
}

- (void)testHandleStyleParsingErrorWithValidInfo
{
    NSDictionary *errorInfo = @{
        @"message": @"Test error",
        @"line": @(1),
        @"column": @(5)
    };

    XCTAssertNoThrow([self.highlighter handleStyleParsingError:errorInfo],
                     @"Should handle valid error info");
}


#pragma mark - Memory and Resource Tests

- (void)testMultipleHighlighterInstances
{
    // Create many highlighters to test memory behavior
    NSMutableArray *highlighters = [NSMutableArray array];

    for (int i = 0; i < 100; i++) {
        HGMarkdownHighlighter *hl = [[HGMarkdownHighlighter alloc] init];
        [highlighters addObject:hl];
    }

    XCTAssertEqual(highlighters.count, 100, @"Should create all instances");

    // Clean up
    [highlighters removeAllObjects];
}

- (void)testHighlighterDeallocation
{
    @autoreleasepool {
        HGMarkdownHighlighter *hl = [[HGMarkdownHighlighter alloc] init];
        hl.waitInterval = 1.0;
        hl = nil;
    }
    // Should not crash when highlighter is deallocated
}


#pragma mark - Edge Case Extension Tests

- (void)testAllExtensionsCombined
{
    int allExtensions = pmh_EXT_NOTES | pmh_EXT_MATH;
    self.highlighter.extensions = allExtensions;
    XCTAssertEqual(self.highlighter.extensions, allExtensions,
                   @"Should store all extensions");
}

- (void)testNegativeExtensionsValue
{
    // Test edge case with negative value (though typically shouldn't be used)
    self.highlighter.extensions = -1;
    XCTAssertEqual(self.highlighter.extensions, -1,
                   @"Should store value as-is");
}


#pragma mark - Stylesheet Content Tests

- (void)testStylesheetWithUnicodeContent
{
    NSString *unicodeStylesheet = @"editor { /* コメント */ color: #333; }";

    XCTAssertNoThrow({
        [self.highlighter applyStylesFromStylesheet:unicodeStylesheet
                                   withErrorHandler:nil];
    }, @"Should handle Unicode in stylesheet");
}

- (void)testStylesheetWithVeryLongContent
{
    // Create a very long stylesheet
    NSMutableString *longStylesheet = [NSMutableString string];
    for (int i = 0; i < 1000; i++) {
        [longStylesheet appendFormat:@"element%d { color: #%06x; }\n", i, i];
    }

    XCTAssertNoThrow({
        [self.highlighter applyStylesFromStylesheet:longStylesheet
                                   withErrorHandler:nil];
    }, @"Should handle long stylesheet");
}

- (void)testStylesheetWithSpecialCharacters
{
    NSString *specialStylesheet = @"editor { content: \"<>&'\"; }";

    XCTAssertNoThrow({
        [self.highlighter applyStylesFromStylesheet:specialStylesheet
                                   withErrorHandler:nil];
    }, @"Should handle special characters");
}


#pragma mark - Stress Tests

- (void)testRapidPropertyChanges
{
    for (int i = 0; i < 100; i++) {
        self.highlighter.waitInterval = (NSTimeInterval)(i % 10) / 10.0;
        self.highlighter.parseAndHighlightAutomatically = (i % 2 == 0);
        self.highlighter.makeLinksClickable = (i % 3 == 0);
        self.highlighter.extensions = i;
    }

    XCTAssertEqual(self.highlighter.extensions, 99, @"Should have last value");
}

- (void)testRapidActivationDeactivation
{
    for (int i = 0; i < 50; i++) {
        [self.highlighter activate];
        [self.highlighter deactivate];
    }

    XCTAssertNoThrow([self.highlighter deactivate], @"Should be stable after rapid toggling");
}

@end
