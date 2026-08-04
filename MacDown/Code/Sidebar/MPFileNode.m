#import "MPFileNode.h"
#import <stdlib.h>
#import <limits.h>

// Mirrors MacDown-Info.plist CFBundleDocumentTypes → CFBundleTypeExtensions.
static NSArray<NSString *> *MPMarkdownExtensions(void)
{
    static NSArray<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ exts = @[@"md", @"markdown"]; });
    return exts;
}

// Physical on-disk path, used to detect symlink cycles. realpath(3) is used
// rather than -URLByResolvingSymlinksInPath because cycle detection needs the
// physical location: two paths are the same node only when they resolve to the
// same real path. Returns nil for a path that does not resolve, i.e. a broken
// symlink.
static NSString *MPRealPath(NSURL *url)
{
    char buf[PATH_MAX];
    const char *p = url.path.fileSystemRepresentation;
    if (p && realpath(p, buf))
        return @(buf);
    return nil;
}

@interface MPFileNode ()
@property (nonatomic, copy) NSURL *URL;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, strong, nullable) NSArray<MPFileNode *> *cachedChildren;
/// This node's fully resolved path.
@property (nonatomic, copy) NSString *realPath;
/// Resolved paths of this node and every ancestor, i.e. the whole chain from
/// the root. A directory child whose resolved path is already in here would
/// re-enter the tree, so it is dropped — without this a symlink pointing at its
/// own ancestor makes an infinitely deep, infinitely expandable sidebar.
@property (nonatomic, copy) NSSet<NSString *> *ancestorRealPaths;
@end

@implementation MPFileNode

- (instancetype)initWithURL:(NSURL *)url isDirectory:(BOOL)isDirectory
{
    return [self initWithURL:url isDirectory:isDirectory
                    realPath:nil ancestorRealPaths:nil];
}

- (instancetype)initWithURL:(NSURL *)url
                isDirectory:(BOOL)isDirectory
                   realPath:(NSString *)realPath
          ancestorRealPaths:(NSSet<NSString *> *)ancestors
{
    self = [super init];
    if (self)
    {
        _URL = [url copy];
        _isDirectory = isDirectory;
        // Only directories descend, so only they need a resolved path and an
        // ancestor chain; resolving every file would be a syscall per entry for
        // values nothing reads.
        if (isDirectory)
        {
            _realPath = [(realPath ?: MPRealPath(url)
                                   ?: url.path.stringByStandardizingPath
                                   ?: @"") copy];
            _ancestorRealPaths = ancestors ?: [NSSet setWithObject:_realPath];
        }
        else
        {
            // Only a symlinked file carries one — a regular file's own URL is
            // already the one to open, and resolving every file would be a
            // syscall per entry for a value nothing reads.
            _realPath = [realPath copy];
        }
    }
    return self;
}

- (NSString *)name
{
    return self.URL.lastPathComponent;
}

- (NSURL *)resolvedURL
{
    if (!self.realPath.length)
        return self.URL;
    return [NSURL fileURLWithPath:self.realPath isDirectory:self.isDirectory];
}

+ (BOOL)isMarkdownFileURL:(NSURL *)url
{
    NSString *ext = url.pathExtension.lowercaseString;
    return ext.length > 0 && [MPMarkdownExtensions() containsObject:ext];
}

- (NSArray<MPFileNode *> *)children
{
    if (self.cachedChildren)
        return self.cachedChildren;

    if (!self.isDirectory)
    {
        self.cachedChildren = @[];
        return self.cachedChildren;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    // Enumerate the RESOLVED path, not self.URL: -contentsOfDirectoryAtURL:
    // refuses to enumerate through a symlink ("couldn't be opened"), so a
    // symlinked folder would always look empty. Children therefore carry
    // canonical URLs, which also keeps tab reuse from treating the same file
    // reached by two paths as two documents. The node's display name still
    // comes from self.URL, so the sidebar shows the link's name.
    NSURL *dir = [NSURL fileURLWithPath:self.realPath isDirectory:YES];
    NSArray<NSURL *> *contents =
        [fm contentsOfDirectoryAtURL:dir
          includingPropertiesForKeys:@[NSURLIsDirectoryKey,
                                       NSURLIsSymbolicLinkKey]
                             options:NSDirectoryEnumerationSkipsHiddenFiles
                               error:NULL];

    NSMutableArray<MPFileNode *> *nodes = [NSMutableArray array];
    for (NSURL *url in contents)
    {
        NSNumber *isDirNum = nil, *isLinkNum = nil;
        [url getResourceValue:&isDirNum forKey:NSURLIsDirectoryKey error:NULL];
        [url getResourceValue:&isLinkNum
                       forKey:NSURLIsSymbolicLinkKey error:NULL];
        BOOL isLink = isLinkNum.boolValue;

        // NSURLIsDirectoryKey does NOT follow symlinks — it reports NO for a
        // link pointing at a folder. Resolve links ourselves so a symlinked
        // folder is browsable instead of silently missing from the tree.
        NSString *childReal;
        BOOL isDir;
        if (isLink)
        {
            childReal = MPRealPath(url);
            if (!childReal)
                continue;                  // broken link: nothing to show
            BOOL resolvedIsDir = NO;
            [fm fileExistsAtPath:childReal isDirectory:&resolvedIsDir];
            isDir = resolvedIsDir;
        }
        else
        {
            // A real subdirectory can't re-enter the tree, so skip realpath():
            // its resolved path is just ours plus its name.
            childReal = [self.realPath
                stringByAppendingPathComponent:url.lastPathComponent];
            isDir = isDirNum.boolValue;
        }

        if (isDir)
        {
            if ([self.ancestorRealPaths containsObject:childReal])
                continue;                  // symlink cycle; would never bottom out

            [nodes addObject:
                [[MPFileNode alloc]
                    initWithURL:url isDirectory:YES
                       realPath:childReal
              ancestorRealPaths:[self.ancestorRealPaths
                                    setByAddingObject:childReal]]];
        }
        else if ([MPFileNode isMarkdownFileURL:url])
        {
            // A link keeps the link's URL for display but remembers its target,
            // which is what -resolvedURL hands to NSDocumentController.
            [nodes addObject:
                [[MPFileNode alloc] initWithURL:url isDirectory:NO
                                       realPath:(isLink ? childReal : nil)
                              ancestorRealPaths:nil]];
        }
    }

    [nodes sortUsingComparator:^NSComparisonResult(MPFileNode *a, MPFileNode *b) {
        if (a.isDirectory != b.isDirectory)
            return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [a.name caseInsensitiveCompare:b.name];
    }];

    self.cachedChildren = [nodes copy];
    return self.cachedChildren;
}

- (void)invalidateChildrenRecursively
{
    for (MPFileNode *child in self.cachedChildren)
        [child invalidateChildrenRecursively];
    self.cachedChildren = nil;
}

@end
