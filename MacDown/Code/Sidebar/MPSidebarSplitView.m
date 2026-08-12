#import "MPSidebarSplitView.h"

@interface MPSidebarSplitView ()
@property (nonatomic, readwrite, getter=isDraggingDivider) BOOL draggingDivider;
@end

@implementation MPSidebarSplitView

// NSSplitView handles a divider drag by running its own modal event-tracking
// loop inside -mouseDown:, and it posts its resize notifications from within
// that loop. Bracketing the call therefore marks exactly the drag, with no
// guessing from [NSApp currentEvent] — which cannot reliably tell a real drag
// from a layout-triggered resize.
//
// NSSplitView's -hitTest: only routes a click here when it lands on a divider;
// clicks inside either pane go to that pane's view.
- (void)mouseDown:(NSEvent *)event
{
    [self performDividerDrag:^{
        [super mouseDown:event];
    }];
}

- (void)performDividerDrag:(nullable void (^)(void))body
{
    self.draggingDivider = YES;
    @try
    {
        if (body)
            body();
    }
    @finally
    {
        self.draggingDivider = NO;
    }
}

@end
