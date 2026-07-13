#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPFolderWatcher : NSObject

/// Watches rootURL and its entire subtree. handler runs on the main queue,
/// coalesced, whenever anything beneath rootURL changes. Does nothing (and
/// isWatching stays NO) when the path is not a watchable local volume.
- (instancetype)initWithRootURL:(NSURL *)rootURL handler:(void (^)(void))handler;

- (void)stop;

@property (nonatomic, readonly, getter=isWatching) BOOL watching;

@end

NS_ASSUME_NONNULL_END
