// Native print annotations carry identities and PDF geometry across pagination.
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface MPPDFAnchorInjector : NSObject
// Transfers GoTo actions to the untouched original print. Metadata is never
// published. Geometry disagreement fails the export instead of guessing.
+ (NSUInteger)resolveNativeLinksInDocument:(nullable PDFDocument *)document
                         metadataDocument:(nullable PDFDocument *)metadata
                             markerPrefix:(NSString *)prefix
                              linkTargets:(NSArray<NSString *> *)linkTargets
                             headingSlugs:(NSArray<NSString *> *)headingSlugs
                                    error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
