//
//  MPPreferencesViewControllerResizabilityTests.m
//  MacDownTests
//
//  Tests for preference panel resizability (Issues #361, #362).
//  Verifies that all five preference panels declare themselves as resizable.
//

#import <XCTest/XCTest.h>
#import "MPGeneralPreferencesViewController.h"
#import "MPMarkdownPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPHtmlPreferencesViewController.h"
#import "MPTerminalPreferencesViewController.h"

@interface MPPreferencesViewControllerResizabilityTests : XCTestCase
@end

@implementation MPPreferencesViewControllerResizabilityTests

#pragma mark - hasResizableWidth

- (void)testGeneralPanelRespondsToHasResizableWidth
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"General panel should respond to hasResizableWidth");
}

- (void)testMarkdownPanelRespondsToHasResizableWidth
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Markdown panel should respond to hasResizableWidth");
}

- (void)testEditorPanelRespondsToHasResizableWidth
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Editor panel should respond to hasResizableWidth");
}

- (void)testHtmlPanelRespondsToHasResizableWidth
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Html panel should respond to hasResizableWidth");
}

- (void)testTerminalPanelRespondsToHasResizableWidth
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableWidth)],
                  @"Terminal panel should respond to hasResizableWidth");
}

#pragma mark - hasResizableHeight

- (void)testGeneralPanelRespondsToHasResizableHeight
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"General panel should respond to hasResizableHeight");
}

- (void)testMarkdownPanelRespondsToHasResizableHeight
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Markdown panel should respond to hasResizableHeight");
}

- (void)testEditorPanelRespondsToHasResizableHeight
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Editor panel should respond to hasResizableHeight");
}

- (void)testHtmlPanelRespondsToHasResizableHeight
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Html panel should respond to hasResizableHeight");
}

- (void)testTerminalPanelRespondsToHasResizableHeight
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc respondsToSelector:@selector(hasResizableHeight)],
                  @"Terminal panel should respond to hasResizableHeight");
}

#pragma mark - Return values

- (void)testGeneralPanelHasResizableWidth
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"General panel hasResizableWidth should return YES");
}

- (void)testGeneralPanelHasResizableHeight
{
    MPGeneralPreferencesViewController *vc = [[MPGeneralPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"General panel hasResizableHeight should return YES");
}

- (void)testMarkdownPanelHasResizableWidth
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Markdown panel hasResizableWidth should return YES");
}

- (void)testMarkdownPanelHasResizableHeight
{
    MPMarkdownPreferencesViewController *vc = [[MPMarkdownPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Markdown panel hasResizableHeight should return YES");
}

- (void)testEditorPanelHasResizableWidth
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Editor panel hasResizableWidth should return YES");
}

- (void)testEditorPanelHasResizableHeight
{
    MPEditorPreferencesViewController *vc = [[MPEditorPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Editor panel hasResizableHeight should return YES");
}

- (void)testHtmlPanelHasResizableWidth
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Html panel hasResizableWidth should return YES");
}

- (void)testHtmlPanelHasResizableHeight
{
    MPHtmlPreferencesViewController *vc = [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Html panel hasResizableHeight should return YES");
}

- (void)testTerminalPanelHasResizableWidth
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableWidth], @"Terminal panel hasResizableWidth should return YES");
}

- (void)testTerminalPanelHasResizableHeight
{
    MPTerminalPreferencesViewController *vc = [[MPTerminalPreferencesViewController alloc] init];
    XCTAssertTrue([vc hasResizableHeight], @"Terminal panel hasResizableHeight should return YES");
}

@end
