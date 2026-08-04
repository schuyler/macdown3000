#import "MPFolderWatcher.h"
#import "MPFileWatcher.h"
#import <CoreServices/CoreServices.h>

// Owns the callback block on behalf of the FSEvents stream.
//
// The stream retains THIS object (via the context retain/release callbacks)
// rather than the watcher itself, for two reasons: a callback already in flight
// can never dereference a freed pointer, and there is no retain cycle keeping
// the watcher alive (which is what would happen if the context retained the
// watcher, since the watcher owns the stream).
//
// -handler is atomic so that clearing it in -stop is safe with respect to a
// callback reading it.
@interface MPFolderWatcherTarget : NSObject
@property (atomic, copy) void (^handler)(void);
@end

@implementation MPFolderWatcherTarget
@end


@interface MPFolderWatcher ()
@property (nonatomic, strong) MPFolderWatcherTarget *target;
@property (nonatomic, assign) FSEventStreamRef stream;
@end

static void MPFolderWatcherCallback(
    ConstFSEventStreamRef streamRef, void *clientCallBackInfo,
    size_t numEvents, void *eventPaths,
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[])
{
    MPFolderWatcherTarget *target =
        (__bridge MPFolderWatcherTarget *)clientCallBackInfo;
    void (^handler)(void) = target.handler;
    if (handler)
        handler();                  // already on the main queue; see -startWatchingPath:
}

@implementation MPFolderWatcher

- (instancetype)initWithRootURL:(NSURL *)rootURL handler:(void (^)(void))handler
{
    self = [super init];
    if (self)
    {
        _target = [[MPFolderWatcherTarget alloc] init];
        _target.handler = handler;
        if ([MPFileWatcher canWatchPath:rootURL.path])
            [self startWatchingPath:rootURL.path];
    }
    return self;
}

- (void)startWatchingPath:(NSString *)path
{
    FSEventStreamContext context = {
        0, (__bridge void *)self.target,
        (CFAllocatorRetainCallBack)CFRetain,
        (CFAllocatorReleaseCallBack)CFRelease,
        NULL
    };
    NSArray<NSString *> *paths = @[path];
    self.stream = FSEventStreamCreate(
        kCFAllocatorDefault, &MPFolderWatcherCallback, &context,
        (__bridge CFArrayRef)paths, kFSEventStreamEventIdSinceNow,
        0.3 /* latency: coalesce bursts */,
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        // Our own writes (autosave, Save As) must not re-trigger a full
        // synchronous sidebar reload on every keystroke-driven save. Files that
        // MacDown itself creates in the folder are picked up by an explicit
        // refresh after a save instead — see MPDocument.
        | kFSEventStreamCreateFlagIgnoreSelf);
    if (!self.stream)
        return;
    // Main queue, matching MPFileWatcher: callbacks are then serialized with
    // -stop/-dealloc and with the sidebar reload they drive, so there is no
    // window in which the stream fires against a torn-down watcher.
    FSEventStreamSetDispatchQueue(self.stream, dispatch_get_main_queue());
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
    self.target.handler = nil;      // any in-flight callback becomes a no-op
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
