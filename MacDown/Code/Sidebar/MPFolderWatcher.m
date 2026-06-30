#import "MPFolderWatcher.h"
#import "MPFileWatcher.h"
#import <CoreServices/CoreServices.h>

@interface MPFolderWatcher ()
@property (nonatomic, copy) void (^handler)(void);
@property (nonatomic, assign) FSEventStreamRef stream;
@end

static void MPFolderWatcherCallback(
    ConstFSEventStreamRef streamRef, void *clientCallBackInfo,
    size_t numEvents, void *eventPaths,
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[])
{
    MPFolderWatcher *watcher = (__bridge MPFolderWatcher *)clientCallBackInfo;
    void (^handler)(void) = watcher.handler;
    if (!handler)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{ handler(); });
}

@implementation MPFolderWatcher

- (instancetype)initWithRootURL:(NSURL *)rootURL handler:(void (^)(void))handler
{
    self = [super init];
    if (self)
    {
        _handler = [handler copy];
        if ([MPFileWatcher canWatchPath:rootURL.path])
            [self startWatchingPath:rootURL.path];
    }
    return self;
}

- (void)startWatchingPath:(NSString *)path
{
    FSEventStreamContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    NSArray<NSString *> *paths = @[path];
    self.stream = FSEventStreamCreate(
        kCFAllocatorDefault, &MPFolderWatcherCallback, &context,
        (__bridge CFArrayRef)paths, kFSEventStreamEventIdSinceNow,
        0.3 /* latency: coalesce bursts */,
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
    if (!self.stream)
        return;
    FSEventStreamSetDispatchQueue(self.stream,
        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (!FSEventStreamStart(self.stream))
    {
        FSEventStreamInvalidate(self.stream);
        FSEventStreamRelease(self.stream);
        self.stream = NULL;
    }
}

- (BOOL)isWatching
{
    return self.stream != NULL;
}

- (void)stop
{
    if (!self.stream)
        return;
    FSEventStreamStop(self.stream);
    FSEventStreamInvalidate(self.stream);
    FSEventStreamRelease(self.stream);
    self.stream = NULL;
}

- (void)dealloc
{
    [self stop];
}

@end
