#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when any shared sidebar state changes. `object` is the source that
/// made the change (observers skip their own). `userInfo` carries the kind and
/// the workspace root the change applies to.
extern NSString * const MPSidebarSyncDidChangeNotification;
extern NSString * const MPSidebarSyncKindKey;   // NSString, one of the kinds below
extern NSString * const MPSidebarSyncRootKey;   // NSURL (all but tree changes)
extern NSString * const MPSidebarSyncURLKey;    // NSURL (tree changes only)

extern NSString * const MPSidebarSyncKindWidth;
extern NSString * const MPSidebarSyncKindVisible;
extern NSString * const MPSidebarSyncKindExpansion;
extern NSString * const MPSidebarSyncKindTreeChanged;

/// Shares sidebar width / visibility / expansion across the (per-document)
/// sidebars of native window tabs, so switching tabs looks seamless. Changes
/// broadcast via NSNotification; no-op (equal-value) updates are ignored, which
/// breaks sync feedback loops.
///
/// All state is scoped to a workspace root: two windows open on different
/// folders are independent, and only the tabs sharing a folder stay in step.
@interface MPSidebarSyncCoordinator : NSObject

+ (instancetype)sharedCoordinator;

/// Sidebar width for a workspace (clamped 150–420). A root not seen before
/// starts at the last width the user dragged anywhere, which is persisted as
/// the global default so new workspaces open at a familiar size.
- (CGFloat)sidebarWidthForRoot:(nullable NSURL *)root;

/// Sidebar visibility for a workspace (in-memory; defaults to YES each launch).
- (BOOL)sidebarVisibleForRoot:(nullable NSURL *)root;

/// Currently-expanded folder paths for a workspace root (empty if none known).
- (NSArray<NSString *> *)expandedPathsForRoot:(nullable NSURL *)root;

/// Setters: update + broadcast to the other sidebars OF THE SAME WORKSPACE.
/// Equal values are ignored (no notification), so applying a broadcast change
/// never re-broadcasts.
- (void)setSidebarWidth:(CGFloat)width
                forRoot:(nullable NSURL *)root
                 source:(nullable id)source;
- (void)setSidebarVisible:(BOOL)visible
                  forRoot:(nullable NSURL *)root
                   source:(nullable id)source;
- (void)setExpandedPaths:(NSArray<NSString *> *)paths
                 forRoot:(nullable NSURL *)root
                  source:(nullable id)source;

/// Announce that MacDown itself created or moved a file on disk. The folder
/// watcher is created with kFSEventStreamCreateFlagIgnoreSelf (so our own saves
/// don't cause a reload storm), which also means it never sees files we write;
/// this is how those still show up. Every sidebar rooted at an ancestor of
/// `url` reloads. Carries no state, and is not scoped to one root.
- (void)notifyFileSavedAtURL:(NSURL *)url source:(nullable id)source;

@end

NS_ASSUME_NONNULL_END
