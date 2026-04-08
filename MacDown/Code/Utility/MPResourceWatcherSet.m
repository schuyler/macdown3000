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
            MPResourceWatcherSet *cancelSelf = weakSelf;
            if (!cancelSelf)
                return;
            [cancelSelf.watchers removeObjectForKey:watchedPath];
            // File was deleted or renamed (e.g. atomic save by external editor).
            // Wait briefly for the rename to complete, then restart watching the
            // new inode at the same path. addWatcherForPath: will notify the
            // delegate, which updates the timestamp and triggers a re-render.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                MPResourceWatcherSet *strongSelf = weakSelf;
                if (!strongSelf)
                    return;
                if (![[NSFileManager defaultManager] fileExistsAtPath:watchedPath])
                    return;
                [strongSelf addWatcherForPath:watchedPath];
            });
        }];

    // Only store if watcher successfully started
    if (watcher.isWatching)
    {
        self.watchers[path] = watcher;
        if (self.delegate)
            [self.delegate resourceWatcherSet:self didDetectChangeAtPath:path];
    }
}

- (void)stopAll
{
    for (MPFileWatcher *watcher in self.watchers.allValues)
        [watcher stopWatching];
    [self.watchers removeAllObjects];
}

@end
