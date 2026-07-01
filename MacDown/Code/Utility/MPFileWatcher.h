//
//  MPFileWatcher.h
//  MacDown 3000
//
//  Reusable single-file watcher using GCD dispatch sources.
//  Related to GitHub issue #110.
//

#import <Foundation/Foundation.h>

@interface MPFileWatcher : NSObject

/// The path being watched, or nil if not active.
@property (nonatomic, readonly, copy) NSString *path;

/// YES if currently watching.
@property (nonatomic, readonly, getter=isWatching) BOOL watching;

/// YES if the path can receive vnode watchers: it is non-nil, non-empty, and
/// resides on a local volume. When the file itself does not exist (e.g. during
/// an external editor's atomic rename-replace save) the locality check falls
/// back to the parent directory. Returns NO for nil, empty, non-local, or
/// otherwise unresolvable paths.
+ (BOOL)canWatchPath:(NSString *)path;

/// YES if the given path resolves to a local (non-network, non-FUSE) volume.
/// Uses the same existence-fallback-to-parent-directory logic as
/// canWatchPath:. Related to #371.
+ (BOOL)pathIsOnLocalVolume:(NSString *)path;

/// Create a watcher for the given path. Calls handler on the main queue
/// when the file is written to. Calls cancelHandler when the file is
/// deleted, renamed, or stopWatching is called.
- (instancetype)initWithPath:(NSString *)path
                     handler:(void (^)(NSString *path))handler
               cancelHandler:(void (^)(NSString *path))cancelHandler;

/// Stop watching. Safe to call multiple times or on a stopped watcher.
- (void)stopWatching;

@end
