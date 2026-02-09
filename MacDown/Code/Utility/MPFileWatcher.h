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

/// Create a watcher for the given path. Calls handler on the main queue
/// when the file is written to. Calls cancelHandler when the file is
/// deleted, renamed, or stopWatching is called.
- (instancetype)initWithPath:(NSString *)path
                     handler:(void (^)(NSString *path))handler
               cancelHandler:(void (^)(NSString *path))cancelHandler;

/// Stop watching. Safe to call multiple times or on a stopped watcher.
- (void)stopWatching;

@end
