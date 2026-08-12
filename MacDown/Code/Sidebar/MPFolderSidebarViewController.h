#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MPFolderSidebarViewController;

@protocol MPFolderSidebarDelegate <NSObject>
- (void)folderSidebar:(MPFolderSidebarViewController *)sidebar
   didActivateFileURL:(NSURL *)url;
@end

/// The sidebar's outline view. Handles Return itself rather than leaving it to
/// the responder chain: whether NSOutlineView forwards an unhandled Return to
/// its next responder depends on how the table is configured, so relying on
/// that would make Return silently stop working after an unrelated change.
@interface MPSidebarOutlineView : NSOutlineView

@property (nonatomic, weak) MPFolderSidebarViewController *sidebar;

@end

@interface MPFolderSidebarViewController : NSViewController <NSSplitViewDelegate>

@property (nonatomic, weak) id<MPFolderSidebarDelegate> sidebarDelegate;
@property (nonatomic, readonly, copy) NSURL *rootURL;

- (instancetype)initWithRootURL:(NSURL *)rootURL;

/// Rebuild the tree from disk, preserving expansion + selection where possible.
- (void)reload;

/// Select/scroll to the row for url, if it is currently visible in the tree.
- (void)selectFileURL:(NSURL *)url;

/// Open the selected row, if it is a Markdown file. Returns whether it did.
- (BOOL)activateSelectedRow;

/// Stop the folder watcher immediately (e.g. when the owning document closes).
- (void)stopWatching;

/// YES when url is at or below this sidebar's root (symlinks resolved on both
/// sides, so /tmp and /private/tmp compare equal).
- (BOOL)containsURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
