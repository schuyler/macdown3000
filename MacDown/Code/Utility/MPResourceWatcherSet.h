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
- (void)resourceWatcherSet:(MPResourceWatcherSet *)set
    didDetectChangeAtPath:(NSString *)path;
@end

@interface MPResourceWatcherSet : NSObject

@property (weak) id<MPResourceWatcherSetDelegate> delegate;

/// Currently watched paths.
@property (nonatomic, readonly) NSSet<NSString *> *watchedPaths;

/// Update the set of watched paths. Adds watchers for new paths,
/// removes watchers for paths no longer in the set.
- (void)updateWatchedPaths:(NSSet<NSString *> *)paths;

/// Stop all watchers.
- (void)stopAll;

@end
