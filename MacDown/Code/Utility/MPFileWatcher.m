//
//  MPFileWatcher.m
//  MacDown 3000
//
//  Reusable single-file watcher using GCD dispatch sources.
//  Related to GitHub issue #110.
//

#import "MPFileWatcher.h"
#import <sys/fcntl.h>

@interface MPFileWatcher ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) dispatch_source_t source;
@end

@implementation MPFileWatcher

- (instancetype)initWithPath:(NSString *)path
                     handler:(void (^)(NSString *path))handler
               cancelHandler:(void (^)(NSString *path))cancelHandler
{
    self = [super init];
    if (!self)
        return nil;

    if (!path)
        return self;

    int fd = open(path.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0)
        return self;

    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE, fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
        dispatch_get_main_queue());

    if (!source)
    {
        close(fd);
        return self;
    }

    self.path = path;
    self.source = source;

    __weak MPFileWatcher *weakSelf = self;
    NSString *watchedPath = [path copy];

    dispatch_source_set_event_handler(source, ^{
        MPFileWatcher *strongSelf = weakSelf;
        if (!strongSelf)
            return;

        unsigned long flags = dispatch_source_get_data(source);
        if (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME))
        {
            [strongSelf stopWatching];
            if (cancelHandler)
                cancelHandler(watchedPath);
            return;
        }
        if (flags & DISPATCH_VNODE_WRITE)
        {
            if (handler)
                handler(watchedPath);
        }
    });

    int fdToClose = fd;
    dispatch_source_set_cancel_handler(source, ^{
        if (fdToClose >= 0)
            close(fdToClose);
    });

    dispatch_resume(source);
    return self;
}

- (void)dealloc
{
    [self stopWatching];
}

- (BOOL)isWatching
{
    return self.source != nil;
}

- (void)stopWatching
{
    if (self.source)
    {
        dispatch_source_cancel(self.source);
        self.source = nil;
    }
    self.path = nil;
}

@end
