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

// h(sel) = NSHeight([sel boundsForPage:sel.pages.firstObject]), guarded: a
// selection with no pages (shouldn't happen in practice, but defensively
// possible) contributes a height of 0 rather than crashing.
static CGFloat MPPDFAnchorSelectionHeight(PDFSelection *selection)
{
    if (selection == nil) {
        return 0.0;
    }
    NSArray<PDFPage *> *pages = selection.pages;
    if (pages.count == 0) {
        return 0.0;
    }
    PDFPage *page = pages.firstObject;
    if (page == nil) {
        return 0.0;
    }
    NSRect bounds = [selection boundsForPage:page];
    return NSHeight(bounds);
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

    NSMutableDictionary<NSString *, NSArray<PDFSelection *> *> *textToMatches = [NSMutableDictionary dictionary];
    for (NSString *needle in needleTexts) {
        if (MPPDFAnchorStringIsBlank(needle)) {
            continue; // Defensive: never search for a blank string.
        }
        NSArray<PDFSelection *> *matches = nil;
        @try {
            matches = [document findString:needle withOptions:0];
        } @catch (NSException *exception) {
            matches = nil;
        }
        textToMatches[needle] = matches ?: @[];
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
            NSArray<PDFSelection *> *allMatches = textToMatches[linkText] ?: @[];
            NSUInteger tocCount = tocCountByText[linkText].unsignedIntegerValue;
            NSUInteger tocAvailable = MIN(tocCount, allMatches.count);
            NSArray<PDFSelection *> *tocSelections =
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

            PDFSelection *sourceSel = tocSelections[k];
            if (sourceSel == nil) {
                continue;
            }
            NSArray<PDFPage *> *sourcePages = sourceSel.pages;
            if (sourcePages.count == 0) {
                continue;
            }
            PDFPage *sourcePage = sourcePages.firstObject;
            if (sourcePage == nil) {
                continue;
            }
            NSRect sourceBounds = [sourceSel boundsForPage:sourcePage];
            CGFloat hSource = MPPDFAnchorSelectionHeight(sourceSel);

            // Step 5: resolve the destination.
            NSString *destText = slugToHeadingText[link.targetSlug ?: @""];
            if (MPPDFAnchorStringIsBlank(destText)) {
                continue; // Unknown/empty-text slug target; skip.
            }

            NSArray<PDFSelection *> *destMatches = textToMatches[destText] ?: @[];
            NSUInteger destTocCount = tocCountByText[destText].unsignedIntegerValue;
            NSUInteger destTocAvailable = MIN(destTocCount, destMatches.count);
            NSArray<PDFSelection *> *bodyGroup =
                [destMatches subarrayWithRange:NSMakeRange(destTocAvailable,
                                                            destMatches.count - destTocAvailable)];
            if (bodyGroup.count == 0) {
                continue; // No body occurrence to land on; skip.
            }

            // (i) Preferred: first body occurrence taller than the source
            // (a heading rendered larger than the TOC/body text).
            PDFSelection *destSel = nil;
            for (PDFSelection *candidate in bodyGroup) {
                if (candidate == nil) {
                    continue;
                }
                if (MPPDFAnchorSelectionHeight(candidate) > hSource) {
                    destSel = candidate;
                    break;
                }
            }
            // (ii) Fallback: first body occurrence in document order, so a
            // same-size heading (e.g. default-theme h5/h6) is never dropped.
            if (destSel == nil) {
                destSel = bodyGroup.firstObject;
            }
            if (destSel == nil) {
                continue;
            }

            NSArray<PDFPage *> *destPages = destSel.pages;
            if (destPages.count == 0) {
                continue;
            }
            PDFPage *destPage = destPages.firstObject;
            if (destPage == nil) {
                continue;
            }
            NSRect destBounds = [destSel boundsForPage:destPage];

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
            continue; // One bad link must never abort the whole pass.
        }
    }

    return addedCount;
}

@end
