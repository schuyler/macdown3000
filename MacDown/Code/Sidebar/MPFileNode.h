#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPFileNode : NSObject

@property (nonatomic, readonly, copy) NSURL *URL;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly, copy) NSString *name;

- (instancetype)initWithURL:(NSURL *)url isDirectory:(BOOL)isDirectory;

/// Lazily computed and cached. Directories return non-hidden subdirectories
/// plus Markdown files, folders first then case-insensitive by name.
/// Files and empty directories return @[].
- (NSArray<MPFileNode *> *)children;

/// Drop the cached children of this node and (recursively) of any already-built
/// child nodes, so the next -children call re-reads the disk.
- (void)invalidateChildrenRecursively;

/// YES when url's extension is md/markdown (case-insensitive).
+ (BOOL)isMarkdownFileURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
