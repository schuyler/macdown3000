#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPFileNode : NSObject

@property (nonatomic, readonly, copy) NSURL *URL;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly, copy) NSString *name;

/// The URL to actually open, with symlinks resolved. Same as URL for anything
/// that isn't a link. Opening a link's own URL fails — NSDocumentController
/// type-detects it as public.symlink rather than Markdown.
@property (nonatomic, readonly, copy) NSURL *resolvedURL;

- (instancetype)initWithURL:(NSURL *)url isDirectory:(BOOL)isDirectory;

/// Lazily computed and cached. Directories return non-hidden subdirectories
/// plus Markdown files, folders first then case-insensitive by name.
/// Files and empty directories return @[].
///
/// Symlinks are followed, so a symlinked folder is browsable, except that a
/// link resolving to somewhere already on the path from the root is dropped
/// (otherwise the tree would never bottom out). Broken links are skipped.
- (NSArray<MPFileNode *> *)children;

/// Drop the cached children of this node and (recursively) of any already-built
/// child nodes, so the next -children call re-reads the disk.
- (void)invalidateChildrenRecursively;

/// YES when url's extension is md/markdown (case-insensitive).
+ (BOOL)isMarkdownFileURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
