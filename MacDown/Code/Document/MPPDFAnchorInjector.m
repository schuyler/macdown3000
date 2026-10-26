//
//  MPPDFAnchorInjector.m
//  MacDown 3000
//
//  Related to GitHub issue #504.
//

#import "MPPDFAnchorInjector.h"


#pragma mark - MPPDFAnchorLink

@interface MPPDFAnchorLink ()
@property (nonatomic, copy, readwrite) NSString *linkText;
@property (nonatomic, copy, readwrite) NSString *targetSlug;
@end

@implementation MPPDFAnchorLink

+ (instancetype)linkWithText:(NSString *)linkText slug:(NSString *)targetSlug
{
    MPPDFAnchorLink *link = [[self alloc] init];
    link.linkText = linkText;
    link.targetSlug = targetSlug;
    return link;
}

@end


#pragma mark - MPPDFAnchorHeading

@interface MPPDFAnchorHeading ()
@property (nonatomic, copy, readwrite) NSString *slug;
@property (nonatomic, copy, readwrite) NSString *headingText;
@end

@implementation MPPDFAnchorHeading

+ (instancetype)headingWithSlug:(NSString *)slug text:(NSString *)headingText
{
    MPPDFAnchorHeading *heading = [[self alloc] init];
    heading.slug = slug;
    heading.headingText = headingText;
    return heading;
}

@end


#pragma mark - MPPDFAnchorInjector Helpers

// Treats nil, and whitespace/newline-only strings, as "blank". Used
// throughout so we never hand an empty needle to -[PDFDocument
// findString:withOptions:] (design §4 Step2 defensive guard) and never
// record an empty slug/heading-text pair in Step1.
static BOOL MPPDFAnchorStringIsBlank(NSString *string)
{
    if (string == nil) {
        return YES;
    }
    NSString *trimmed = [string stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length == 0;
}

#pragma mark - MPPDFAnchorMatch

// PDFKit vends the SAME PDFSelection instance across multiple -findString:
// calls on one PDFDocument: a later search mutates an earlier selection's
// string/bounds/pages in place. Caching arrays of live PDFSelection objects
// up front (as -findString: returns them) and reading their geometry later,
// after subsequent needle searches have run, silently reads clobbered
// geometry. MPPDFAnchorMatch is a plain, immutable value snapshot of the
// only per-match facts the engine needs -- page index (resolved against the
// document's canonical page identity), on-page bounds, and rendered height
// -- captured immediately after each -findString:withOptions: call, before
// any later needle search can mutate the PDFSelection it came from.
@interface MPPDFAnchorMatch : NSObject
@property (nonatomic, assign, readonly) NSUInteger pageIndex;
@property (nonatomic, assign, readonly) NSRect bounds;
@property (nonatomic, assign, readonly) CGFloat height;
+ (instancetype)matchWithPageIndex:(NSUInteger)pageIndex bounds:(NSRect)bounds height:(CGFloat)height;
@end

@implementation MPPDFAnchorMatch

+ (instancetype)matchWithPageIndex:(NSUInteger)pageIndex bounds:(NSRect)bounds height:(CGFloat)height
{
    MPPDFAnchorMatch *match = [[self alloc] init];
    if (match) {
        match->_pageIndex = pageIndex;
        match->_bounds = bounds;
        match->_height = height;
    }
    return match;
}

@end

// Snapshots every selection in `matches` into an MPPDFAnchorMatch immediately
// (i.e. before any subsequent -findString: call can mutate the shared
// PDFSelection instances). Selections with no resolvable page are skipped
// defensively rather than crashing; this should not happen in practice.
static NSArray<MPPDFAnchorMatch *> *MPPDFAnchorSnapshotMatches(NSArray<PDFSelection *> *matches,
                                                                 PDFDocument *document)
{
    NSMutableArray<MPPDFAnchorMatch *> *snapshots = [NSMutableArray arrayWithCapacity:matches.count];
    for (PDFSelection *selection in matches) {
        if (selection == nil) {
            continue;
        }
        NSArray<PDFPage *> *pages = selection.pages;
        if (pages.count == 0) {
            continue;
        }
        PDFPage *page = pages.firstObject;
        if (page == nil) {
            continue;
        }
        NSUInteger pageIndex = [document indexForPage:page];
        if (pageIndex == NSNotFound) {
            continue;
        }
        NSRect bounds = [selection boundsForPage:page];
        [snapshots addObject:[MPPDFAnchorMatch matchWithPageIndex:pageIndex
                                                             bounds:bounds
                                                             height:NSHeight(bounds)]];
    }
    return snapshots;
}

#pragma mark - MPPDFAnchorInjector

@implementation MPPDFAnchorInjector

+ (NSUInteger)injectLinksIntoDocument:(PDFDocument *)document
                                 links:(NSArray<MPPDFAnchorLink *> *)links
                              headings:(NSArray<MPPDFAnchorHeading *> *)headings
{
    // Guard inputs (design §4): nil/zero-page document or empty links is a
    // safe no-op. `links.count` on a nil `links` messages nil and yields 0,
    // so this also covers a nil links array without a separate check.
    if (document == nil || document.pageCount == 0 || links.count == 0) {
        return 0;
    }

    // Step 1: slug -> FIRST-match heading text. Headings with a blank slug
    // or blank heading text are skipped and never recorded.
    NSMutableDictionary<NSString *, NSString *> *slugToHeadingText = [NSMutableDictionary dictionary];
    for (MPPDFAnchorHeading *heading in headings) {
        if (heading == nil) {
            continue;
        }
        NSString *slug = heading.slug;
        NSString *text = heading.headingText;
        if (MPPDFAnchorStringIsBlank(slug) || MPPDFAnchorStringIsBlank(text)) {
            continue;
        }
        if (slugToHeadingText[slug] != nil) {
            continue; // Keep only the first heading recorded per slug.
        }
        slugToHeadingText[slug] = text;
    }

    // Step 2: distinct non-blank needle texts (every link's linkText, plus
    // every destination text actually referenced by a link) get exactly one
    // cached -findString:withOptions: call each.
    NSMutableSet<NSString *> *needleTexts = [NSMutableSet set];
    for (MPPDFAnchorLink *link in links) {
        if (link == nil) {
            continue;
        }
        if (!MPPDFAnchorStringIsBlank(link.linkText)) {
            [needleTexts addObject:link.linkText];
        }
        NSString *destText = slugToHeadingText[link.targetSlug ?: @""];
        if (!MPPDFAnchorStringIsBlank(destText)) {
            [needleTexts addObject:destText];
        }
    }

    // PDFKit vends the SAME PDFSelection instance across successive
    // -findString: calls on this document, mutating earlier selections'
    // geometry in place as later needles are searched for. Snapshot each
    // needle's matches into plain MPPDFAnchorMatch value objects
    // IMMEDIATELY after its -findString: call returns -- before the next
    // needle's -findString: call runs and clobbers them. The injection loop
    // below reads exclusively from these snapshots, never from a live
    // PDFSelection. Issue #504.
    NSMutableDictionary<NSString *, NSArray<MPPDFAnchorMatch *> *> *textToMatches = [NSMutableDictionary dictionary];
    for (NSString *needle in needleTexts) {
        if (MPPDFAnchorStringIsBlank(needle)) {
            continue; // Defensive: never search for a blank string.
        }
        NSArray<PDFSelection *> *matches = nil;
        @try {
            matches = [document findString:needle withOptions:0];
        } @catch (NSException *exception) {
            NSLog(@"[Issue #504] anchor link skipped due to exception: %@", exception);
            matches = nil;
        }
        textToMatches[needle] = MPPDFAnchorSnapshotMatches(matches ?: @[], document);
    }

    // tocCount(T): number of links whose linkText == T, for any text T (used
    // both for a link's own source text and for whatever destination text it
    // resolves to).
    NSMutableDictionary<NSString *, NSNumber *> *tocCountByText = [NSMutableDictionary dictionary];
    for (MPPDFAnchorLink *link in links) {
        if (link == nil || MPPDFAnchorStringIsBlank(link.linkText)) {
            continue;
        }
        NSNumber *current = tocCountByText[link.linkText];
        tocCountByText[link.linkText] = @(current.unsignedIntegerValue + 1);
    }

    NSUInteger addedCount = 0;
    NSMutableDictionary<NSString *, NSNumber *> *linkTextCounter = [NSMutableDictionary dictionary];

    for (MPPDFAnchorLink *link in links) {
        @try {
            if (link == nil || MPPDFAnchorStringIsBlank(link.linkText)) {
                continue;
            }

            NSString *linkText = link.linkText;
            NSArray<MPPDFAnchorMatch *> *allMatches = textToMatches[linkText] ?: @[];
            NSUInteger tocCount = tocCountByText[linkText].unsignedIntegerValue;
            NSUInteger tocAvailable = MIN(tocCount, allMatches.count);
            NSArray<MPPDFAnchorMatch *> *tocSelections =
                [allMatches subarrayWithRange:NSMakeRange(0, tocAvailable)];

            // Step 4: k-th link with this text maps to the k-th TOC
            // selection of this text; the counter advances for every link
            // with this text, matched or not, so later links with the same
            // text still line up with later TOC occurrences.
            NSUInteger k = linkTextCounter[linkText].unsignedIntegerValue;
            linkTextCounter[linkText] = @(k + 1);

            if (k >= tocSelections.count) {
                continue; // Not enough TOC occurrences for this link; skip.
            }

            MPPDFAnchorMatch *sourceMatch = tocSelections[k];
            if (sourceMatch == nil) {
                continue;
            }
            NSRect sourceBounds = sourceMatch.bounds;
            CGFloat hSource = sourceMatch.height;

            // Resolve to the document's canonical PDFPage: annotations added to
            // the transient page vended by PDFSelection.pages are not persisted
            // on the page pageAtIndex: returns (and would not be written out).
            // Issue #504.
            PDFPage *sourcePage = [document pageAtIndex:sourceMatch.pageIndex];
            if (sourcePage == nil) {
                continue;
            }

            // Step 5: resolve the destination.
            NSString *destText = slugToHeadingText[link.targetSlug ?: @""];
            if (MPPDFAnchorStringIsBlank(destText)) {
                continue; // Unknown/empty-text slug target; skip.
            }

            NSArray<MPPDFAnchorMatch *> *destMatches = textToMatches[destText] ?: @[];
            NSUInteger destTocCount = tocCountByText[destText].unsignedIntegerValue;
            NSUInteger destTocAvailable = MIN(destTocCount, destMatches.count);
            NSArray<MPPDFAnchorMatch *> *bodyGroup =
                [destMatches subarrayWithRange:NSMakeRange(destTocAvailable,
                                                            destMatches.count - destTocAvailable)];
            if (bodyGroup.count == 0) {
                continue; // No body occurrence to land on; skip.
            }

            // (i) Preferred: first body occurrence taller than the source
            // (a heading rendered larger than the TOC/body text).
            MPPDFAnchorMatch *destMatch = nil;
            for (MPPDFAnchorMatch *candidate in bodyGroup) {
                if (candidate == nil) {
                    continue;
                }
                if (candidate.height > hSource) {
                    destMatch = candidate;
                    break;
                }
            }
            // (ii) Fallback: first body occurrence in document order, so a
            // same-size heading (e.g. default-theme h5/h6) is never dropped.
            if (destMatch == nil) {
                destMatch = bodyGroup.firstObject;
            }
            if (destMatch == nil) {
                continue;
            }

            NSRect destBounds = destMatch.bounds;

            // Resolve to the document's canonical PDFPage for the same reason
            // as sourcePage above: the PDFDestination must reference the page
            // pageAtIndex: vends, or navigation/persistence would target a
            // detached page wrapper. Issue #504.
            PDFPage *destPage = [document pageAtIndex:destMatch.pageIndex];
            if (destPage == nil) {
                continue;
            }

            // Step 6: construct + attach the annotation. PDF pages are
            // bottom-left origin, so the top of the heading is NSMaxY.
            PDFDestination *destination =
                [[PDFDestination alloc] initWithPage:destPage
                                              atPoint:NSMakePoint(NSMinX(destBounds), NSMaxY(destBounds))];
            PDFAnnotation *annotation =
                [[PDFAnnotation alloc] initWithBounds:sourceBounds
                                               forType:PDFAnnotationSubtypeLink
                                        withProperties:nil];
            annotation.action = [[PDFActionGoTo alloc] initWithDestination:destination];
            [sourcePage addAnnotation:annotation];
            addedCount++;
        } @catch (NSException *exception) {
            NSLog(@"[Issue #504] anchor link skipped due to exception: %@", exception);
            continue; // One bad link must never abort the whole pass.
        }
    }

    return addedCount;
}

@end
