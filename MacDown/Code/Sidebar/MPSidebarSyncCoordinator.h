#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when any shared sidebar state changes. `object` is the source that
/// made the change (observers skip their own). `userInfo` carries the kind and,
/// for expansion, the workspace root.
extern NSString * const MPSidebarSyncDidChangeNotification;
extern NSString * const MPSidebarSyncKindKey;   // NSString, one of the kinds below
extern NSString * const MPSidebarSyncRootKey;   // NSURL (expansion changes only)

extern NSString * const MPSidebarSyncKindWidth;
extern NSString * const MPSidebarSyncKindVisible;
extern NSString * const MPSidebarSyncKindExpansion;

/// Shares sidebar width / visibility / per-folder expansion across the
/// (per-document) sidebars of native window tabs, so switching tabs looks
/// seamless. Changes broadcast via NSNotification; no-op (equal-value) updates
/// are ignored, which breaks sync feedback loops.
@interface MPSidebarSyncCoordinator : NSObject

+ (instancetype)sharedCoordinator;

/// Shared sidebar width (persisted as the global default; clamped 150–420).
@property (nonatomic, readonly) CGFloat sidebarWidth;

/// Shared sidebar visibility (in-memory; defaults to YES each launch).
@property (nonatomic, readonly) BOOL sidebarVisible;

/// Currently-expanded folder paths for a workspace root (empty if none known).
- (NSArray<NSString *> *)expandedPathsForRoot:(NSURL *)root;

/// Setters: update + broadcast to other sidebars. Equal values are ignored
/// (no notification), so applying a broadcast change never re-broadcasts.
- (void)setSidebarWidth:(CGFloat)width source:(nullable id)source;
- (void)setSidebarVisible:(BOOL)visible source:(nullable id)source;
- (void)setExpandedPaths:(NSArray<NSString *> *)paths
                 forRoot:(NSURL *)root
                  source:(nullable id)source;

@end

NS_ASSUME_NONNULL_END
