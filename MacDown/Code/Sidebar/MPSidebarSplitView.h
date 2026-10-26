#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// The split view hosting the folder sidebar next to the editor/preview pane.
///
/// Its one job beyond NSSplitView is to say whether the user is currently
/// dragging the divider. NSSplitViewDidResizeSubviewsNotification fires for
/// programmatic -setPosition:, window resizes and tab insertion too, and only a
/// genuine drag should broadcast a new shared width — otherwise the width creeps
/// every time a tab opens.
@interface MPSidebarSplitView : NSSplitView

/// YES only for the duration of a divider-drag tracking loop.
@property (nonatomic, readonly, getter=isDraggingDivider) BOOL draggingDivider;

/// Runs `body` with -isDraggingDivider set, clearing it again even if `body`
/// raises. -mouseDown: uses this to wrap NSSplitView's tracking loop; it is
/// exposed so the bracketing can be exercised without a live drag.
- (void)performDividerDrag:(nullable void (^)(void))body;

@end

NS_ASSUME_NONNULL_END
