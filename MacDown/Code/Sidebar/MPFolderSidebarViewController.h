#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MPFolderSidebarViewController;

@protocol MPFolderSidebarDelegate <NSObject>
- (void)folderSidebar:(MPFolderSidebarViewController *)sidebar
   didActivateFileURL:(NSURL *)url;
@end

@interface MPFolderSidebarViewController : NSViewController

@property (nonatomic, weak) id<MPFolderSidebarDelegate> sidebarDelegate;
@property (nonatomic, readonly, copy) NSURL *rootURL;

- (instancetype)initWithRootURL:(NSURL *)rootURL;

/// Rebuild the tree from disk, preserving expansion + selection where possible.
- (void)reload;

/// Select/scroll to the row for url, if it is currently visible in the tree.
- (void)selectFileURL:(NSURL *)url;

/// Stop the folder watcher immediately (e.g. when the owning document closes).
- (void)stopWatching;

@end

NS_ASSUME_NONNULL_END
