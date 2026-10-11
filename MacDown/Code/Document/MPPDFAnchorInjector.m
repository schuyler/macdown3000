#import "MPPDFAnchorInjector.h"

// Accept only the exact generated URL grammar; no permissive integer parsing.
static NSUInteger MPMarkerIndex(NSString *URL, NSString *prefix, NSString *role,
                                NSUInteger count)
{
    NSString *stem = [prefix stringByAppendingFormat:@"%@/", role];
    if (![URL hasPrefix:stem]) return NSNotFound;
    NSString *digits = [URL substringFromIndex:stem.length];
    if (!digits.length) return NSNotFound;
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < digits.length; i++) {
        unichar c = [digits characterAtIndex:i];
        if (c < '0' || c > '9' || index > (NSUIntegerMax - (c - '0')) / 10)
            return NSNotFound;
        index = index * 10 + c - '0';
    }
    return index < count ? index : NSNotFound;
}

static BOOL MPMatchingRect(NSRect a, NSRect b)
{
    return fabs(a.origin.x - b.origin.x) < 0.1 && fabs(a.origin.y - b.origin.y) < 0.1
        && fabs(a.size.width - b.size.width) < 0.1 && fabs(a.size.height - b.size.height) < 0.1;
}

static NSUInteger MPGeometryFailure(NSError **error)
{
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
        userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"PDF link layout changed during export.", nil)}];
    return 0;
}

@implementation MPPDFAnchorInjector
+ (NSUInteger)resolveNativeLinksInDocument:(PDFDocument *)document
                         metadataDocument:(PDFDocument *)metadata
                             markerPrefix:(NSString *)prefix
                              linkTargets:(NSArray<NSString *> *)linkTargets
                             headingSlugs:(NSArray<NSString *> *)headingSlugs
                                    error:(NSError **)error
{
    if (error) *error = nil;
    if (!document || !metadata || !prefix.length) return 0;
    if (document.pageCount != metadata.pageCount) return MPGeometryFailure(error);
    NSMutableDictionary<NSString *, NSNumber *> *firstHeading = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < headingSlugs.count; i++) {
        NSString *slug = headingSlugs[i];
        if (slug.length && !firstHeading[slug]) firstHeading[slug] = @(i);
    }
    NSMutableDictionary<NSNumber *, PDFDestination *> *destinations = [NSMutableDictionary dictionary];
    for (NSUInteger p = 0; p < metadata.pageCount; p++) {
        PDFPage *page = [metadata pageAtIndex:p], *original = [document pageAtIndex:p];
        if (page.rotation != original.rotation ||
            !MPMatchingRect([page boundsForBox:kPDFDisplayBoxMediaBox], [original boundsForBox:kPDFDisplayBoxMediaBox]))
            return MPGeometryFailure(error);
        for (PDFAnnotation *annotation in page.annotations) {
            NSUInteger index = MPMarkerIndex(annotation.URL.absoluteString, prefix, @"heading", headingSlugs.count);
            if (index != NSNotFound && !destinations[@(index)]) {
                NSRect bounds = annotation.bounds;
                destinations[@(index)] = [[PDFDestination alloc] initWithPage:original
                    atPoint:NSMakePoint(NSMinX(bounds), NSMaxY(bounds))];
            }
        }
    }
    NSMutableArray<PDFAnnotation *> *sources = [NSMutableArray array];
    NSMutableArray<PDFDestination *> *targets = [NSMutableArray array];
    NSMutableSet<PDFAnnotation *> *consumed = [NSMutableSet set];
    for (NSUInteger p = 0; p < metadata.pageCount; p++) {
        PDFPage *page = [metadata pageAtIndex:p], *original = [document pageAtIndex:p];
        for (PDFAnnotation *annotation in page.annotations) {
            NSUInteger index = MPMarkerIndex(annotation.URL.absoluteString, prefix, @"link", linkTargets.count);
            if (index == NSNotFound) continue;
            PDFAnnotation *source = nil;
            for (PDFAnnotation *candidate in original.annotations) {
                NSString *fragment = candidate.URL.fragment;
                fragment = fragment.stringByRemovingPercentEncoding ?: fragment;
                BOOL internalSource = (!candidate.URL && !candidate.action)
                    || (fragment.length && [fragment isEqualToString:linkTargets[index]]);
                if (![consumed containsObject:candidate] && internalSource &&
                    [candidate.type isEqualToString:@"Link"] && MPMatchingRect(candidate.bounds, annotation.bounds)) {
                    if (source) return MPGeometryFailure(error);
                    source = candidate;
                }
            }
            if (!source) return MPGeometryFailure(error);
            [consumed addObject:source];
            NSNumber *heading = firstHeading[linkTargets[index]];
            PDFDestination *destination = heading ? destinations[heading] : nil;
            if (destination) { [sources addObject:source]; [targets addObject:destination]; }
        }
    }
    // Validate every source first; a rejected transfer leaves the original intact.
    for (NSUInteger i = 0; i < sources.count; i++)
        sources[i].action = [[PDFActionGoTo alloc] initWithDestination:targets[i]];
    return sources.count;
}
@end
