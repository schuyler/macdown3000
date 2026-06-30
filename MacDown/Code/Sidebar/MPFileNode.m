#import "MPFileNode.h"

// Mirrors MacDown-Info.plist CFBundleDocumentTypes → CFBundleTypeExtensions.
static NSArray<NSString *> *MPMarkdownExtensions(void)
{
    static NSArray<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ exts = @[@"md", @"markdown"]; });
    return exts;
}

@interface MPFileNode ()
@property (nonatomic, copy) NSURL *URL;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, strong, nullable) NSArray<MPFileNode *> *cachedChildren;
@end

@implementation MPFileNode

- (instancetype)initWithURL:(NSURL *)url isDirectory:(BOOL)isDirectory
{
    self = [super init];
    if (self)
    {
        _URL = [url copy];
        _isDirectory = isDirectory;
    }
    return self;
}

- (NSString *)name
{
    return self.URL.lastPathComponent;
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
    NSArray<NSURL *> *contents =
        [fm contentsOfDirectoryAtURL:self.URL
          includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                             options:NSDirectoryEnumerationSkipsHiddenFiles
                               error:NULL];

    NSMutableArray<MPFileNode *> *nodes = [NSMutableArray array];
    for (NSURL *url in contents)
    {
        NSNumber *isDirNum = nil;
        [url getResourceValue:&isDirNum forKey:NSURLIsDirectoryKey error:NULL];
        BOOL isDir = isDirNum.boolValue;
        if (isDir)
            [nodes addObject:[[MPFileNode alloc] initWithURL:url isDirectory:YES]];
        else if ([MPFileNode isMarkdownFileURL:url])
            [nodes addObject:[[MPFileNode alloc] initWithURL:url isDirectory:NO]];
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
