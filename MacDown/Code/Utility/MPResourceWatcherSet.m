//
//  MPResourceWatcherSet.m
//  MacDown 3000
//
//  Manages a set of file watchers for local resources referenced in HTML.
//  Related to GitHub issue #110.
//

#import "MPResourceWatcherSet.h"
#import "MPFileWatcher.h"

@interface MPResourceWatcherSet ()
@property (strong) NSMutableDictionary<NSString *, MPFileWatcher *> *watchers;
@end

@implementation MPResourceWatcherSet

- (instancetype)init
{
    self = [super init];
    if (self)
        self.watchers = [NSMutableDictionary dictionary];
    return self;
}

- (void)dealloc
{
    [self stopAll];
}

- (NSSet<NSString *> *)watchedPaths
{
    return [NSSet setWithArray:self.watchers.allKeys];
}

- (void)updateWatchedPaths:(NSSet<NSString *> *)paths
{
    NSSet *currentPaths = [NSSet setWithArray:self.watchers.allKeys];

    // Remove watchers for paths no longer referenced
    NSMutableSet *toRemove = [currentPaths mutableCopy];
    [toRemove minusSet:paths];
    for (NSString *path in toRemove)
    {
        [self.watchers[path] stopWatching];
        [self.watchers removeObjectForKey:path];
    }

    // Add watchers for new paths
    NSMutableSet *toAdd = [paths mutableCopy];
    [toAdd minusSet:currentPaths];
    for (NSString *path in toAdd)
    {
        [self addWatcherForPath:path];
    }
}

- (void)addWatcherForPath:(NSString *)path
{
    __weak MPResourceWatcherSet *weakSelf = self;
    NSString *watchedPath = [path copy];

    MPFileWatcher *watcher = [[MPFileWatcher alloc] initWithPath:path
        handler:^(NSString *p) {
            MPResourceWatcherSet *strongSelf = weakSelf;
            if (strongSelf)
                [strongSelf.delegate resourceWatcherSet:strongSelf
                                  didDetectChangeAtPath:p];
        }
        cancelHandler:^(NSString *p) {
            MPResourceWatcherSet *strongSelf = weakSelf;
            if (strongSelf)
                [strongSelf.watchers removeObjectForKey:watchedPath];
        }];

    // Only store if watcher successfully started
    if (watcher.isWatching)
        self.watchers[path] = watcher;
}

- (void)stopAll
{
    for (MPFileWatcher *watcher in self.watchers.allValues)
        [watcher stopWatching];
    [self.watchers removeAllObjects];
}

@end
