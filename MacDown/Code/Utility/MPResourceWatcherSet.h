//
//  MPResourceWatcherSet.h
//  MacDown 3000
//
//  Manages a set of file watchers for local resources referenced in HTML.
//  Related to GitHub issue #110.
//

#import <Foundation/Foundation.h>

@class MPResourceWatcherSet;

@protocol MPResourceWatcherSetDelegate <NSObject>
/// Called when a watched file is written to, or has been replaced (e.g. by an
/// atomic save) and is being watched again. Not called when watching begins.
- (void)resourceWatcherSet:(MPResourceWatcherSet *)set
    didDetectChangeAtPath:(NSString *)path;
@end

@interface MPResourceWatcherSet : NSObject

@property (weak) id<MPResourceWatcherSetDelegate> delegate;

/// Currently watched paths.
@property (nonatomic, readonly) NSSet<NSString *> *watchedPaths;

/// Update the set of watched paths. Adds watchers for new paths,
/// removes watchers for paths no longer in the set. Returns the paths that
/// began to be watched in this call.
- (NSSet<NSString *> *)updateWatchedPaths:(NSSet<NSString *> *)paths;

/// Stop all watchers.
- (void)stopAll;

@end
