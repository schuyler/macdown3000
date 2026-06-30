#import "MPSidebarSyncCoordinator.h"

NSString * const MPSidebarSyncDidChangeNotification =
    @"MPSidebarSyncDidChangeNotification";
NSString * const MPSidebarSyncKindKey = @"kind";
NSString * const MPSidebarSyncRootKey = @"root";
NSString * const MPSidebarSyncKindWidth = @"width";
NSString * const MPSidebarSyncKindVisible = @"visible";
NSString * const MPSidebarSyncKindExpansion = @"expansion";

static NSString * const kMPSidebarWidthDefaultsKey = @"MPSidebarSharedWidth";
static const CGFloat kMPSidebarMinWidth = 150.0;
static const CGFloat kMPSidebarMaxWidth = 420.0;
static const CGFloat kMPSidebarDefaultWidth = 220.0;

@interface MPSidebarSyncCoordinator ()
@property (nonatomic) CGFloat sidebarWidth;
@property (nonatomic) BOOL sidebarVisible;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *expandedByRoot;
@end

@implementation MPSidebarSyncCoordinator

+ (instancetype)sharedCoordinator
{
    static MPSidebarSyncCoordinator *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[MPSidebarSyncCoordinator alloc] init]; });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _expandedByRoot = [NSMutableDictionary dictionary];
        _sidebarVisible = YES;

        NSNumber *saved = [[NSUserDefaults standardUserDefaults]
            objectForKey:kMPSidebarWidthDefaultsKey];
        _sidebarWidth = saved ? [self clampWidth:saved.doubleValue]
                              : kMPSidebarDefaultWidth;
    }
    return self;
}

- (CGFloat)clampWidth:(CGFloat)width
{
    if (width < kMPSidebarMinWidth) return kMPSidebarMinWidth;
    if (width > kMPSidebarMaxWidth) return kMPSidebarMaxWidth;
    return width;
}

- (NSArray<NSString *> *)expandedPathsForRoot:(NSURL *)root
{
    return self.expandedByRoot[root.absoluteString] ?: @[];
}

- (void)setSidebarWidth:(CGFloat)width source:(id)source
{
    CGFloat clamped = [self clampWidth:width];
    if (fabs(clamped - self.sidebarWidth) < 0.5)
        return;                                  // no-op: breaks the sync loop
    self.sidebarWidth = clamped;
    [[NSUserDefaults standardUserDefaults] setDouble:clamped
                                              forKey:kMPSidebarWidthDefaultsKey];
    [self postKind:MPSidebarSyncKindWidth root:nil source:source];
}

- (void)setSidebarVisible:(BOOL)visible source:(id)source
{
    if (visible == self.sidebarVisible)
        return;
    self.sidebarVisible = visible;
    [self postKind:MPSidebarSyncKindVisible root:nil source:source];
}

- (void)setExpandedPaths:(NSArray<NSString *> *)paths
                 forRoot:(NSURL *)root
                  source:(id)source
{
    if (!root)
        return;
    NSString *key = root.absoluteString;
    NSArray<NSString *> *current = self.expandedByRoot[key] ?: @[];
    // Order-independent comparison.
    if ([[NSSet setWithArray:paths] isEqualToSet:[NSSet setWithArray:current]])
        return;
    self.expandedByRoot[key] = [paths copy];
    [self postKind:MPSidebarSyncKindExpansion root:root source:source];
}

- (void)postKind:(NSString *)kind root:(NSURL *)root source:(id)source
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPSidebarSyncKindKey] = kind;
    if (root)
        info[MPSidebarSyncRootKey] = root;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPSidebarSyncDidChangeNotification
                      object:source
                    userInfo:info];
}

@end
