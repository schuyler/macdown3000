#import <XCTest/XCTest.h>
#import "MPSidebarSplitView.h"

@interface MPSidebarSplitViewTests : XCTestCase
@property (strong) MPSidebarSplitView *splitView;
@end

@implementation MPSidebarSplitViewTests

- (void)setUp
{
    [super setUp];
    self.splitView = [[MPSidebarSplitView alloc]
        initWithFrame:NSMakeRect(0, 0, 600, 400)];
    self.splitView.vertical = YES;
}

- (void)testNotDraggingByDefault
{
    XCTAssertFalse(self.splitView.isDraggingDivider,
                   @"a resize with no drag must not broadcast a width");
}

- (void)testFlagIsSetOnlyForTheDurationOfTheDrag
{
    __block BOOL duringDrag = NO;
    [self.splitView performDividerDrag:^{
        duringDrag = self.splitView.isDraggingDivider;
    }];
    XCTAssertTrue(duringDrag, @"resizes inside the drag loop must broadcast");
    XCTAssertFalse(self.splitView.isDraggingDivider, @"and must stop after it");
}

// NSSplitView's tracking loop runs user code (delegate callbacks); if any of it
// raised, a stuck flag would make every later layout resize broadcast a width.
- (void)testFlagIsClearedEvenIfTheDragRaises
{
    XCTAssertThrows([self.splitView performDividerDrag:^{
        [NSException raise:@"MPTestException" format:@"boom"];
    }]);
    XCTAssertFalse(self.splitView.isDraggingDivider);
}

- (void)testNilBodyIsHarmless
{
    XCTAssertNoThrow([self.splitView performDividerDrag:nil]);
    XCTAssertFalse(self.splitView.isDraggingDivider);
}

// -mouseDown: is what actually brackets NSSplitView's tracking loop; without
// the override the flag would never be set and width sync would stop working.
- (void)testMouseDownBracketsTheDrag
{
    XCTAssertTrue([MPSidebarSplitView instancesRespondToSelector:@selector(mouseDown:)]);
    XCTAssertNotEqual(
        [MPSidebarSplitView instanceMethodForSelector:@selector(mouseDown:)],
        [NSSplitView instanceMethodForSelector:@selector(mouseDown:)],
        @"MPSidebarSplitView must override -mouseDown: to mark the drag");

    // A click that misses the divider returns without a tracking loop; the flag
    // must be back to NO either way.
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                        location:NSMakePoint(300, 200)
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                     eventNumber:0
                                      clickCount:1
                                        pressure:1.0];
    XCTAssertNoThrow([self.splitView mouseDown:click]);
    XCTAssertFalse(self.splitView.isDraggingDivider);
}

@end
