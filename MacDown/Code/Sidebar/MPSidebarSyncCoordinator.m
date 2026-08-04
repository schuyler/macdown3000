#import "MPSidebarSyncCoordinator.h"

NSString * const MPSidebarSyncDidChangeNotification =
    @"MPSidebarSyncDidChangeNotification";
NSString * const MPSidebarSyncKindKey = @"kind";
NSString * const MPSidebarSyncRootKey = @"root";
NSString * const MPSidebarSyncURLKey = @"url";
NSString * const MPSidebarSyncKindWidth = @"width";
NSString * const MPSidebarSyncKindVisible = @"visible";
NSString * const MPSidebarSyncKindExpansion = @"expansion";
NSString * const MPSidebarSyncKindTreeChanged = @"tree";

static NSString * const kMPSidebarWidthDefaultsKey = @"MPSidebarSharedWidth";
static NSString * const kMPSidebarNoRootKey = @"";
static const CGFloat kMPSidebarMinWidth = 150.0;
static const CGFloat kMPSidebarMaxWidth = 420.0;
static const CGFloat kMPSidebarDefaultWidth = 220.0;

@interface MPSidebarSyncCoordinator ()
/// Last width the user dragged anywhere; persisted, and used to seed a
/// workspace that has no width of its own yet.
@property (nonatomic) CGFloat defaultWidth;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *widthByRoot;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *visibleByRoot;
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
        _widthByRoot = [NSMutableDictionary dictionary];
        _visibleByRoot = [NSMutableDictionary dictionary];
        _expandedByRoot = [NSMutableDictionary dictionary];

        NSNumber *saved = [[NSUserDefaults standardUserDefaults]
            objectForKey:kMPSidebarWidthDefaultsKey];
        _defaultWidth = saved ? [self clampWidth:saved.doubleValue]
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

// Documents with no workspace share one (unused) bucket rather than needing a
// nil check at every call site.
- (NSString *)keyForRoot:(NSURL *)root
{
    return root.absoluteString ?: kMPSidebarNoRootKey;
}

#pragma mark - Reading

- (CGFloat)sidebarWidthForRoot:(NSURL *)root
{
    NSString *key = [self keyForRoot:root];
    NSNumber *w = self.widthByRoot[key];
    if (w)
        return [self clampWidth:w.doubleValue];
    // Pin the seed on first ask. Without this a workspace the user never drags
    // has no entry of its own, so it would follow defaultWidth and jump when
    // some other workspace is resized.
    self.widthByRoot[key] = @(self.defaultWidth);
    return self.defaultWidth;
}

- (BOOL)sidebarVisibleForRoot:(NSURL *)root
{
    NSNumber *v = self.visibleByRoot[[self keyForRoot:root]];
    return v ? v.boolValue : YES;
}

- (NSArray<NSString *> *)expandedPathsForRoot:(NSURL *)root
{
    return self.expandedByRoot[[self keyForRoot:root]] ?: @[];
}

#pragma mark - Writing

- (void)setSidebarWidth:(CGFloat)width forRoot:(NSURL *)root source:(id)source
{
    CGFloat clamped = [self clampWidth:width];
    if (fabs(clamped - [self sidebarWidthForRoot:root]) < 0.5)
        return;                                  // no-op: breaks the sync loop
    self.widthByRoot[[self keyForRoot:root]] = @(clamped);
    // Persisted globally, not per root: it only seeds workspaces opened later.
    self.defaultWidth = clamped;
    [[NSUserDefaults standardUserDefaults] setDouble:clamped
                                              forKey:kMPSidebarWidthDefaultsKey];
    [self postKind:MPSidebarSyncKindWidth root:root source:source];
}

- (void)setSidebarVisible:(BOOL)visible forRoot:(NSURL *)root source:(id)source
{
    if (visible == [self sidebarVisibleForRoot:root])
        return;
    self.visibleByRoot[[self keyForRoot:root]] = @(visible);
    [self postKind:MPSidebarSyncKindVisible root:root source:source];
}

- (void)setExpandedPaths:(NSArray<NSString *> *)paths
                 forRoot:(NSURL *)root
                  source:(id)source
{
    if (!root)
        return;
    NSString *key = [self keyForRoot:root];
    NSArray<NSString *> *current = self.expandedByRoot[key] ?: @[];
    // Order-independent comparison.
    if ([[NSSet setWithArray:paths] isEqualToSet:[NSSet setWithArray:current]])
        return;
    self.expandedByRoot[key] = [paths copy];
    [self postKind:MPSidebarSyncKindExpansion root:root source:source];
}

- (void)notifyFileSavedAtURL:(NSURL *)url source:(id)source
{
    if (!url.isFileURL)
        return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPSidebarSyncKindKey] = MPSidebarSyncKindTreeChanged;
    info[MPSidebarSyncURLKey] = url;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPSidebarSyncDidChangeNotification
                      object:source
                    userInfo:info];
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
