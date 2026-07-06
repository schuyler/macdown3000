//
//  MPPDFAnchorInjectorTests.m
//  MacDownTests
//
//  Headless (no WebView) tests for the pure PDF anchor-annotation engine
//  described in the design for GitHub issue #504 ("Clickable Internal
//  Anchor Links in Exported PDF").
//
//  Fixture PDFs are generated in-test with real, selectable text. Each
//  fixture page is drawn by an offscreen AppKit view (see
//  MPPDFTestPageView below) and rasterized to PDF via -[NSView
//  dataWithPDFInsideRect:] -- the same underlying AppKit text-layout path
//  that produces the real export's searchable text via NSPrintOperation --
//  so that -[PDFDocument findString:withOptions:] can genuinely locate the
//  drawn text, the same way the real export pipeline's PDF-native text
//  search does. No WebView is involved anywhere in this file.
//
//  MPPDFAnchorInjector's +injectLinksIntoDocument:links:headings: is fully
//  implemented (see MPPDFAnchorInjector.m): it uses -findString:withOptions:
//  to locate both TOC/link source text and body/heading destination text,
//  then disambiguates same-text collisions via document order and rendered
//  height. Every behavioral assertion below is expected to PASS against
//  that implementation. Tests 4 and 8 are the exception: they assert ZERO
//  annotations for genuinely no-op/skip inputs (empty links array, empty
//  document, and a slug whose heading text has no body occurrence) -- these
//  are regression guards for the no-op/skip paths, not stub-refuting
//  coverage.
//
//  Related to GitHub issue #504.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <PDFKit/PDFKit.h>
#import <math.h> // for fabs(), used throughout the tolerance-based assertions below
#import "MPPDFAnchorInjector.h"


#pragma mark - Draw Item Helper

// Describes one piece of text to draw into a fixture PDF: its content, font
// size, destination page, and its origin point measured from the TOP-LEFT
// of the page (y grows downward) -- i.e. ordinary "reading order"
// coordinates. The fixture builder converts this into the PDF's native
// bottom-left, y-up coordinate space when it draws the glyphs.
@interface MPPDFTestDrawItem : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSUInteger pageIndex;
@property (nonatomic, assign) CGPoint topLeftPoint;
+ (instancetype)itemWithText:(NSString *)text
                     fontSize:(CGFloat)fontSize
                    pageIndex:(NSUInteger)pageIndex
                 topLeftPoint:(CGPoint)topLeftPoint;
@end

@implementation MPPDFTestDrawItem
+ (instancetype)itemWithText:(NSString *)text
                     fontSize:(CGFloat)fontSize
                    pageIndex:(NSUInteger)pageIndex
                 topLeftPoint:(CGPoint)topLeftPoint
{
    MPPDFTestDrawItem *item = [[self alloc] init];
    item.text = text;
    item.fontSize = fontSize;
    item.pageIndex = pageIndex;
    item.topLeftPoint = topLeftPoint;
    return item;
}
@end


#pragma mark - Constants

// US Letter, matching the media box used by every fixture page.
static const CGFloat kMPTestPageWidth = 612.0;
static const CGFloat kMPTestPageHeight = 792.0;

// Font metrics vary slightly by rendering environment; tolerate a couple of
// points of slop when comparing rects/points, per design §7.
static const CGFloat kMPTestTolerance = 2.0;


#pragma mark - Page View Helper

// An offscreen, never-windowed NSView that draws exactly one fixture page's
// worth of text items and is then rasterized via -dataWithPDFInsideRect:.
// This is the SAME AppKit text-drawing/layout path AppKit uses when
// producing PDF from a real print operation, so the glyphs it emits carry
// standard, searchable text (unlike drawing directly into a bare
// CGPDFContext, which does not reliably embed a ToUnicode mapping).
//
// NSView is UNFLIPPED by default (origin bottom-left, y-up) -- the same
// space as a PDF page -- so `-isFlipped` is left at its default (NO) and
// every item's precomputed bottom-left draw point is used as-is via
// -[NSAttributedString drawAtPoint:].
@interface MPPDFTestPageView : NSView
@property (nonatomic, copy) NSArray<MPPDFTestDrawItem *> *drawItems;
@end

@implementation MPPDFTestPageView

- (BOOL)isOpaque
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor whiteColor] setFill];
    NSRectFill(dirtyRect);

    for (MPPDFTestDrawItem *item in self.drawItems) {
        NSFont *font = [NSFont systemFontOfSize:item.fontSize];
        NSDictionary *attrs = @{NSFontAttributeName: font};
        NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:item.text
                                                                          attributes:attrs];
        NSSize measured = attrString.size;

        // Same top-left -> bottom-left conversion as the previous
        // CGPDFContext-based fixture: for a page of height H, an item
        // whose origin is `topLeftPoint` (y grows downward) is drawn with
        // its bottom-left corner at (x, H - topLeftPoint.y - measuredHeight).
        CGFloat pdfX = item.topLeftPoint.x;
        CGFloat pdfY = kMPTestPageHeight - item.topLeftPoint.y - measured.height;
        [attrString drawAtPoint:NSMakePoint(pdfX, pdfY)];
    }
}

@end


#pragma mark - Test Case

@interface MPPDFAnchorInjectorTests : XCTestCase
@end


@implementation MPPDFAnchorInjectorTests

#pragma mark - Fixture Building

/**
 * Draws every item in `items` into a freshly generated PDF, one 612x792
 * (US Letter) media box per page.
 *
 * Each page is rendered independently by handing an offscreen
 * MPPDFTestPageView (never added to any window) the items destined for
 * that page, then calling `-[NSView dataWithPDFInsideRect:]` to capture
 * AppKit's own PDF rendering of that view -- the same code path a real
 * NSPrintOperation-driven PDF export uses, so the resulting page carries
 * genuinely searchable text. Each page's data is loaded as its own
 * one-page PDFDocument and its PDFPage is inserted into a combined
 * PDFDocument in order.
 *
 * After assembly, the combined document's `.string` is force-accessed (and
 * the document is round-tripped once through `-dataRepresentation` /
 * `-initWithData:`) to guarantee PDFKit has fully built its text index
 * before any `-findString:withOptions:` call runs against it, eliminating
 * any lazy-parse race.
 *
 * Returns the loaded PDFDocument. If `outDrawnRects` is non-NULL, it is set
 * to an array of NSValue-wrapped CGRects (PDF/bottom-left coordinates), one
 * per entry in `items`, in the SAME ORDER as `items` (independent of which
 * page each item lands on). These rects are not predicted from font
 * metrics -- they are measured GROUND TRUTH, located in the finished
 * document via `-findString:withOptions:` and `-[PDFSelection
 * boundsForPage:]`, the exact same mechanism the engine itself uses. This
 * keeps the geometry assertions in tests 1/6/7 self-consistent with
 * whatever PDFKit actually reports for the rendered glyphs, rather than
 * depending on font-metrics prediction matching PDFKit's internal layout
 * to within a couple of points.
 */
- (PDFDocument *)documentFromDrawItems:(NSArray<MPPDFTestDrawItem *> *)items
                             drawnRects:(NSArray<NSValue *> **)outDrawnRects
{
    NSUInteger pageCount = 1;
    for (MPPDFTestDrawItem *item in items) {
        pageCount = MAX(pageCount, item.pageIndex + 1);
    }

    NSRect pageFrame = NSMakeRect(0, 0, kMPTestPageWidth, kMPTestPageHeight);
    PDFDocument *combinedDocument = [[PDFDocument alloc] init];

    for (NSUInteger pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        NSMutableArray<MPPDFTestDrawItem *> *pageItems = [NSMutableArray array];
        for (MPPDFTestDrawItem *item in items) {
            if (item.pageIndex == pageIndex) {
                [pageItems addObject:item];
            }
        }

        MPPDFTestPageView *view = [[MPPDFTestPageView alloc] initWithFrame:pageFrame];
        view.drawItems = pageItems;

        NSData *pageData = [view dataWithPDFInsideRect:pageFrame];
        XCTAssertNotNil(pageData, @"Failed to render fixture page %lu to PDF data",
                        (unsigned long)pageIndex);
        if (pageData == nil) {
            continue;
        }

        PDFDocument *singlePageDocument = [[PDFDocument alloc] initWithData:pageData];
        XCTAssertNotNil(singlePageDocument, @"Failed to load rendered fixture page %lu as a PDFDocument",
                        (unsigned long)pageIndex);
        if (singlePageDocument == nil || singlePageDocument.pageCount == 0) {
            continue;
        }

        PDFPage *page = [singlePageDocument pageAtIndex:0];
        [combinedDocument insertPage:page atIndex:combinedDocument.pageCount];
    }

    XCTAssertEqual(combinedDocument.pageCount, pageCount,
                  @"Fixture should have one page per requested pageIndex");

    // Defensively force a full, synchronous text-index parse -- both on the
    // freshly-assembled document and again after a round trip through
    // -dataRepresentation/-initWithData: -- before this fixture is handed
    // to the engine or measured below.
    (void)combinedDocument.string;
    NSData *roundTripData = combinedDocument.dataRepresentation;
    PDFDocument *finalDocument = roundTripData ? [[PDFDocument alloc] initWithData:roundTripData] : nil;
    if (finalDocument == nil) {
        finalDocument = combinedDocument;
    }
    (void)finalDocument.string;

    if (outDrawnRects) {
        *outDrawnRects = [self measuredRectsForItems:items inDocument:finalDocument];
    }

    return finalDocument;
}

/**
 * Measures the GROUND-TRUTH rect (PDF/bottom-left coordinates) for every
 * entry in `items` by locating its drawn text in the already-assembled
 * `document` via `-findString:withOptions:`, exactly as the engine under
 * test does. Results are returned in the same order as `items`.
 *
 * When the same text is drawn more than once on the same page (e.g. two
 * identical TOC entries), occurrences are matched to items in draw order:
 * the Nth item requesting a given (text, pageIndex) pair is matched to the
 * Nth matching selection found on that page, which mirrors the vertical
 * stacking order the items were drawn in (and the order PDFKit's own text
 * extraction reports them, since it works out reading order top-to-bottom).
 */
- (NSArray<NSValue *> *)measuredRectsForItems:(NSArray<MPPDFTestDrawItem *> *)items
                                    inDocument:(PDFDocument *)document
{
    NSMutableDictionary<NSString *, NSArray<PDFSelection *> *> *matchesByText = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *consumedOnPage = [NSMutableDictionary dictionary];
    NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity:items.count];

    for (MPPDFTestDrawItem *item in items) {
        NSArray<PDFSelection *> *matches = matchesByText[item.text];
        if (matches == nil) {
            matches = [document findString:item.text withOptions:0] ?: @[];
            matchesByText[item.text] = matches;
        }

        NSMutableArray<PDFSelection *> *onThisPage = [NSMutableArray array];
        for (PDFSelection *selection in matches) {
            NSArray<PDFPage *> *pages = selection.pages;
            if (pages.count == 0) {
                continue;
            }
            PDFPage *page = pages.firstObject;
            if (page != nil && [document indexForPage:page] == item.pageIndex) {
                [onThisPage addObject:selection];
            }
        }

        NSString *counterKey = [NSString stringWithFormat:@"%@|%lu", item.text,
                                 (unsigned long)item.pageIndex];
        NSUInteger occurrenceIndex = consumedOnPage[counterKey].unsignedIntegerValue;
        consumedOnPage[counterKey] = @(occurrenceIndex + 1);

        CGRect rect = CGRectZero;
        if (occurrenceIndex < onThisPage.count) {
            PDFSelection *selection = onThisPage[occurrenceIndex];
            PDFPage *page = selection.pages.firstObject;
            rect = NSRectToCGRect([selection boundsForPage:page]);
        } else {
            XCTFail(@"Could not locate drawn text '%@' on fixture page %lu via findString: -- "
                    @"the fixture's text may not be searchable", item.text, (unsigned long)item.pageIndex);
        }

        [rects addObject:[NSValue valueWithRect:NSRectFromCGRect(rect)]];
    }

    return rects;
}

/**
 * Convenience wrapper (design §7): TOC entries drawn one per line at 12pt
 * on page 0; each body heading drawn at 24pt alone on its own subsequent
 * page (page 1, 2, ...), in the order given. Used by tests 1-4.
 */
- (PDFDocument *)fixtureWithTOC:(NSArray<NSString *> *)toc
                   bodyHeadings:(NSArray<NSString *> *)headings
                       tocRects:(NSArray<NSValue *> **)outTocRects
                   headingRects:(NSArray<NSValue *> **)outHeadingRects
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];

    CGFloat tocY = 72.0;
    for (NSString *entry in toc) {
        [items addObject:[MPPDFTestDrawItem itemWithText:entry
                                                 fontSize:12.0
                                                pageIndex:0
                                             topLeftPoint:CGPointMake(72.0, tocY)]];
        tocY += 24.0;
    }

    NSUInteger pageIndex = 1;
    for (NSString *heading in headings) {
        [items addObject:[MPPDFTestDrawItem itemWithText:heading
                                                 fontSize:24.0
                                                pageIndex:pageIndex
                                             topLeftPoint:CGPointMake(72.0, 72.0)]];
        pageIndex++;
    }

    NSArray<NSValue *> *allRects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&allRects];

    if (outTocRects) {
        *outTocRects = [allRects subarrayWithRange:NSMakeRange(0, toc.count)];
    }
    if (outHeadingRects) {
        *outHeadingRects = [allRects subarrayWithRange:NSMakeRange(toc.count, headings.count)];
    }
    return document;
}

#pragma mark - Assertion Helpers

- (NSArray<PDFAnnotation *> *)linkAnnotationsOnPage:(PDFPage *)page
{
    NSMutableArray<PDFAnnotation *> *result = [NSMutableArray array];
    for (PDFAnnotation *annotation in page.annotations) {
        if ([annotation.type isEqualToString:PDFAnnotationSubtypeLink]) {
            [result addObject:annotation];
        }
    }
    return result;
}

- (NSUInteger)totalLinkAnnotationsInDocument:(PDFDocument *)document
{
    NSUInteger total = 0;
    for (NSUInteger i = 0; i < document.pageCount; i++) {
        total += [self linkAnnotationsOnPage:[document pageAtIndex:i]].count;
    }
    return total;
}

#pragma mark - Test 1: Happy Path

/**
 * TOC ["Intro", "Details"] on page 0, headings ["Intro", "Details"] on
 * pages 1 and 2 respectively. After injection, page 0 must carry exactly 2
 * link annotations, each a real PDFActionGoTo landing on the matching
 * heading page at (approximately) the top of the heading's rect.
 */
- (void)testHappyPathInjectsClickableLinksToCorrectHeadingPages
{
    NSArray<NSValue *> *tocRects = nil;
    NSArray<NSValue *> *headingRects = nil;
    PDFDocument *document = [self fixtureWithTOC:@[@"Intro", @"Details"]
                                     bodyHeadings:@[@"Intro", @"Details"]
                                         tocRects:&tocRects
                                     headingRects:&headingRects];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"Intro" slug:@"intro"],
        [MPPDFAnchorLink linkWithText:@"Details" slug:@"details"],
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"intro" text:@"Intro"],
        [MPPDFAnchorHeading headingWithSlug:@"details" text:@"Details"],
    ];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                links:links
                                                             headings:headings];
    XCTAssertEqual(added, (NSUInteger)2, @"Should inject exactly 2 annotations for 2 TOC links");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)2,
                  @"TOC page should have exactly 2 link annotations");

    NSArray<NSNumber *> *expectedHeadingPageIndexes = @[@1, @2];

    // Match each injected annotation back to its expected TOC entry by
    // source-rect proximity, since injected annotation order on a page is
    // not otherwise part of the contract.
    for (NSUInteger i = 0; i < 2; i++) {
        CGRect expectedTocRect = NSRectToCGRect([tocRects[i] rectValue]);
        CGRect expectedHeadingRect = NSRectToCGRect([headingRects[i] rectValue]);
        NSUInteger expectedPageIndex = [expectedHeadingPageIndexes[i] unsignedIntegerValue];

        PDFAnnotation *match = nil;
        for (PDFAnnotation *annotation in tocAnnotations) {
            if (fabs(NSMinX(annotation.bounds) - CGRectGetMinX(expectedTocRect)) <= kMPTestTolerance &&
                fabs(NSMinY(annotation.bounds) - CGRectGetMinY(expectedTocRect)) <= kMPTestTolerance) {
                match = annotation;
                break;
            }
        }
        XCTAssertNotNil(match, @"No injected annotation found matching TOC rect for entry %lu",
                        (unsigned long)i);
        if (!match) {
            continue;
        }

        XCTAssertEqualObjects(match.type, PDFAnnotationSubtypeLink,
                              @"Injected annotation %lu should be a link annotation", (unsigned long)i);
        XCTAssertTrue([match.action isKindOfClass:[PDFActionGoTo class]],
                      @"Injected annotation %lu's action should be a PDFActionGoTo", (unsigned long)i);
        if (![match.action isKindOfClass:[PDFActionGoTo class]]) {
            continue;
        }

        PDFActionGoTo *goTo = (PDFActionGoTo *)match.action;
        PDFDestination *destination = goTo.destination;
        NSUInteger actualPageIndex = [document indexForPage:destination.page];
        XCTAssertEqual(actualPageIndex, expectedPageIndex,
                      @"Link %lu should navigate to the correct heading page", (unsigned long)i);
        XCTAssertEqualWithAccuracy(destination.point.y, CGRectGetMaxY(expectedHeadingRect), kMPTestTolerance,
                                  @"Destination point should land at (about) the top of the heading rect");
        XCTAssertEqualWithAccuracy(destination.point.x, CGRectGetMinX(expectedHeadingRect), kMPTestTolerance,
                                  @"Destination point.x should land at (about) the left edge of the heading "
                                  @"rect (design Step6 sets point.x = NSMinX(destBounds))");
    }
}

#pragma mark - Test 2: Collision / First-Match

/**
 * Two body headings share identical text ("Dup", same slug "dup") on
 * pages 1 and 2. The single TOC link targeting "dup" must resolve to the
 * FIRST body occurrence (page 1), per the collision rule.
 */
- (void)testDuplicateHeadingTextResolvesToFirstBodyOccurrence
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Dup" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Dup" fontSize:24.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Dup" fontSize:24.0 pageIndex:2
                                        topLeftPoint:CGPointMake(72, 72)]];

    NSArray<NSValue *> *rects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&rects];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Dup" slug:@"dup"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"dup" text:@"Dup"],
        [MPPDFAnchorHeading headingWithSlug:@"dup" text:@"Dup"],
    ];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)1, @"Exactly one annotation should be injected for the single TOC link");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count != 1) {
        return;
    }

    PDFAnnotation *annotation = tocAnnotations.firstObject;
    XCTAssertTrue([annotation.action isKindOfClass:[PDFActionGoTo class]]);
    if (![annotation.action isKindOfClass:[PDFActionGoTo class]]) {
        return;
    }
    PDFActionGoTo *goTo = (PDFActionGoTo *)annotation.action;
    NSUInteger destinationPageIndex = [document indexForPage:goTo.destination.page];
    XCTAssertEqual(destinationPageIndex, (NSUInteger)1,
                  @"Colliding slugs must resolve to the FIRST body occurrence (page 1), not page 2");
}

#pragma mark - Test 3: No-Match / Inert-Safe

/**
 * Mixes one resolvable link ("Real" -> heading "real") with:
 *   - a link whose targetSlug ("unknown-slug") has no matching heading,
 *   - a link whose linkText ("NeverDrawn") does not appear anywhere in the
 *     PDF at all, and
 *   - a link ("EmptyTarget" -> "empty-heading") whose target heading has
 *     EMPTY text. Per design §4 Step5, destText resolves to "" for this
 *     slug; an empty heading text must never be used as a findString:
 *     needle (it would nonsensically match everywhere), so the engine must
 *     SKIP this link rather than search for "".
 * None of the unresolved cases may add an annotation, throw, or perturb
 * the one valid link's annotation.
 */
- (void)testUnmatchedAndUnfoundLinksProduceNoAnnotationWithoutPerturbingValidOnes
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Real" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Ghost" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 96)]];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"EmptyTarget" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 120)]];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Real" fontSize:24.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];

    NSArray<NSValue *> *rects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&rects];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"Real" slug:@"real"],
        [MPPDFAnchorLink linkWithText:@"Ghost" slug:@"unknown-slug"],
        [MPPDFAnchorLink linkWithText:@"NeverDrawn" slug:@"never-drawn-slug"],
        [MPPDFAnchorLink linkWithText:@"EmptyTarget" slug:@"empty-heading"],
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"real" text:@"Real"],
        [MPPDFAnchorHeading headingWithSlug:@"empty-heading" text:@""],
    ];

    __block NSUInteger added = 0;
    XCTAssertNoThrow(added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                      links:links
                                                                   headings:headings]);

    XCTAssertEqual(added, (NSUInteger)1,
                  @"Only the 'Real' link should resolve; unknown-slug, never-drawn, and "
                  @"empty-heading-target links must all be skipped");
    XCTAssertEqual([self totalLinkAnnotationsInDocument:document], (NSUInteger)1,
                  @"No-match/empty-heading links must not add annotations, and must not disturb "
                  @"the one valid link");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], (NSUInteger)1,
                      @"The one valid link must still resolve to the correct heading page");
    }
}

#pragma mark - Test 4: No-Op

/**
 * (a) A real, non-trivial document with an EMPTY links array must add
 *     zero annotations.
 * (b) A genuinely empty (zero-page) PDFDocument, even given non-empty
 *     links/headings, must add zero annotations and must not throw.
 *
 * This is a regression guard for the engine's early no-op guards (an empty
 * `links` array, or a zero-page document), so that a future change can
 * never make either case spuriously produce annotations.
 */
- (void)testEmptyLinksAndEmptyDocumentAreSafeNoOps
{
    // (a) Real document, but an empty links array.
    PDFDocument *document = [self fixtureWithTOC:@[@"Intro"]
                                     bodyHeadings:@[@"Intro"]
                                         tocRects:NULL
                                     headingRects:NULL];
    NSArray<MPPDFAnchorHeading *> *headings = @[[MPPDFAnchorHeading headingWithSlug:@"intro" text:@"Intro"]];

    __block NSUInteger added = 99;
    XCTAssertNoThrow(added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                      links:@[]
                                                                   headings:headings]);
    XCTAssertEqual(added, (NSUInteger)0, @"Empty links array must add zero annotations");
    XCTAssertEqual([self totalLinkAnnotationsInDocument:document], (NSUInteger)0,
                  @"Empty links array must not mutate the document");

    // (b) A genuinely empty (zero-page) PDFDocument.
    PDFDocument *emptyDocument = [[PDFDocument alloc] init];
    XCTAssertEqual(emptyDocument.pageCount, (NSUInteger)0,
                  @"Sanity check: a freshly-init PDFDocument has no pages");

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Intro" slug:@"intro"]];
    __block NSUInteger addedToEmpty = 99;
    XCTAssertNoThrow(addedToEmpty = [MPPDFAnchorInjector injectLinksIntoDocument:emptyDocument
                                                                             links:links
                                                                          headings:headings]);
    XCTAssertEqual(addedToEmpty, (NSUInteger)0, @"An empty PDFDocument must yield zero injected annotations");
}

#pragma mark - Test 5: Same-Size Fallback

/**
 * The TOC entry and its target heading are BOTH drawn at 14pt (mimicking
 * the default-theme h5/h6 case, where headings render at body size). The
 * document-order fallback (design §4 Step5(ii)) must still inject an
 * annotation, since height alone cannot distinguish heading from TOC/body
 * text here.
 */
- (void)testSameSizeHeadingStillResolvesViaDocumentOrderFallback
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Sub" fontSize:14.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Sub" fontSize:14.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];

    NSArray<NSValue *> *rects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&rects];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Sub" slug:@"sub"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[[MPPDFAnchorHeading headingWithSlug:@"sub" text:@"Sub"]];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)1,
                  @"Same-size TOC entry and heading (default-theme h5/h6 case) must still resolve "
                  @"via the document-order fallback");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], (NSUInteger)1,
                      @"Fallback destination should be the (only) body occurrence, on page 1");
    }
}

#pragma mark - Test 6: Height Promotes Heading Over Preceding Prose

/**
 * The destination text "Target" appears three times: a 12pt TOC entry on
 * page 0, a 12pt body PROSE occurrence (same size as the TOC entry) on
 * page 1, and the real 24pt HEADING on page 2.
 *
 * INVARIANT (design §4 Step4/Step5): hSource is the height of the TOC
 * entry's rendered text, which in the real app EQUALS body-prose height --
 * a TOC entry is ordinary body-size link text, and body paragraphs render
 * at that same body font size. Only text rendered LARGER than body size
 * (an actual heading) has height > hSource. This fixture reflects that
 * invariant explicitly: TOC entry == prose size (12pt) < heading size
 * (24pt). Because the prose is NOT taller than hSource, Step5(i)'s
 * `height > hSource` test correctly steps over it and promotes the
 * page-2, 24pt heading -- the first (and only) body occurrence that is
 * actually taller than the TOC entry.
 */
- (void)testHeightPromotesRealHeadingOverPrecedingSameTextProse
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Target" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];   // TOC entry (body size)
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Target" fontSize:12.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];   // body prose, SAME size as TOC entry
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Target" fontSize:24.0 pageIndex:2
                                        topLeftPoint:CGPointMake(72, 72)]];   // the real heading, LARGER than body size

    NSArray<NSValue *> *rects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&rects];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Target" slug:@"target"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[[MPPDFAnchorHeading headingWithSlug:@"target" text:@"Target"]];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)1);

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        NSUInteger destinationPageIndex = [document indexForPage:goTo.destination.page];
        XCTAssertEqual(destinationPageIndex, (NSUInteger)2,
                      @"Destination must resolve to the larger 24pt heading on page 2, "
                      @"not the same-body-size (12pt) prose on page 1");
    }
}

#pragma mark - Test 7: Multiple Links To Same Slug

/**
 * The SAME TOC entry text ("Intro") appears twice in the TOC -- two
 * separate MPPDFAnchorLinks, both with linkText "Intro" and both
 * targeting slug "intro" -- alongside exactly one body heading "Intro".
 * This models a document where a heading is cross-referenced from more
 * than one place. Per design §4 Step6, every link that targets a given
 * slug must reuse the SAME cached first-match destination ("multiple
 * links to same slug -> same first-match dest"), and per Step4 each link
 * still gets its OWN source annotation, aligned to its own TOC
 * occurrence in document order (the k-th link with text T binds to the
 * k-th TOC selection of T).
 *
 * Assert: exactly 2 link annotations are added, one anchored at each of
 * the two distinct TOC source rects, and BOTH resolve to the identical
 * destination (same page and same point) -- the sole "Intro" heading.
 */
- (void)testMultipleLinksToSameSlugShareFirstMatchDestination
{
    NSArray<NSValue *> *tocRects = nil;
    NSArray<NSValue *> *headingRects = nil;
    PDFDocument *document = [self fixtureWithTOC:@[@"Intro", @"Intro"]
                                     bodyHeadings:@[@"Intro"]
                                         tocRects:&tocRects
                                     headingRects:&headingRects];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"Intro" slug:@"intro"],
        [MPPDFAnchorLink linkWithText:@"Intro" slug:@"intro"],
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"intro" text:@"Intro"],
    ];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)2, @"Both links to the same slug must each get their own annotation");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)2,
                  @"TOC page should have exactly 2 link annotations, one per TOC occurrence");
    if (tocAnnotations.count != 2) {
        return;
    }

    CGRect expectedHeadingRect = NSRectToCGRect([headingRects[0] rectValue]);
    NSPoint firstDestinationPoint = NSZeroPoint;
    NSUInteger firstDestinationPageIndex = NSNotFound;

    // Match each injected annotation back to its expected TOC occurrence by
    // source-rect proximity (same technique as test 1), then verify every
    // one shares the exact same destination.
    for (NSUInteger i = 0; i < 2; i++) {
        CGRect expectedTocRect = NSRectToCGRect([tocRects[i] rectValue]);

        PDFAnnotation *match = nil;
        for (PDFAnnotation *annotation in tocAnnotations) {
            if (fabs(NSMinX(annotation.bounds) - CGRectGetMinX(expectedTocRect)) <= kMPTestTolerance &&
                fabs(NSMinY(annotation.bounds) - CGRectGetMinY(expectedTocRect)) <= kMPTestTolerance) {
                match = annotation;
                break;
            }
        }
        XCTAssertNotNil(match, @"No injected annotation found matching TOC rect for occurrence %lu",
                        (unsigned long)i);
        if (!match) {
            continue;
        }
        XCTAssertTrue([match.action isKindOfClass:[PDFActionGoTo class]],
                      @"Injected annotation %lu's action should be a PDFActionGoTo", (unsigned long)i);
        if (![match.action isKindOfClass:[PDFActionGoTo class]]) {
            continue;
        }

        PDFActionGoTo *goTo = (PDFActionGoTo *)match.action;
        PDFDestination *destination = goTo.destination;
        NSUInteger actualPageIndex = [document indexForPage:destination.page];
        XCTAssertEqual(actualPageIndex, (NSUInteger)1,
                      @"Both links should navigate to the single heading's page (1)");
        XCTAssertEqualWithAccuracy(destination.point.y, CGRectGetMaxY(expectedHeadingRect), kMPTestTolerance,
                                  @"Destination point.y should land at (about) the top of the heading rect");
        XCTAssertEqualWithAccuracy(destination.point.x, CGRectGetMinX(expectedHeadingRect), kMPTestTolerance,
                                  @"Destination point.x should land at (about) the left edge of the heading rect");

        if (i == 0) {
            firstDestinationPoint = destination.point;
            firstDestinationPageIndex = actualPageIndex;
        } else {
            XCTAssertEqual(actualPageIndex, firstDestinationPageIndex,
                          @"Every link to the same slug must resolve to the exact same destination page");
            XCTAssertEqualWithAccuracy(destination.point.x, firstDestinationPoint.x, kMPTestTolerance,
                                      @"Every link to the same slug must resolve to the exact same destination point.x");
            XCTAssertEqualWithAccuracy(destination.point.y, firstDestinationPoint.y, kMPTestTolerance,
                                      @"Every link to the same slug must resolve to the exact same destination point.y");
        }
    }
}

#pragma mark - Test 8: bodyGroup-Empty Skip Path

/**
 * A link whose targetSlug IS matched by a heading in the model, but whose
 * heading text NEVER appears in the PDF as a body occurrence -- only as
 * the TOC entry itself. Only the TOC entry "Ghost" is drawn (body size,
 * page 0); no body heading text is drawn anywhere in the document.
 *
 * Per design §4 Step3, matches["Ghost"] contains exactly ONE occurrence
 * (the TOC entry); tocCount("Ghost") == 1 (one link with that linkText),
 * so bodyGroup = matches["Ghost"] AFTER the first 1 occurrence == the
 * empty remainder. Step5 explicitly SKIPs when bodyGroup is empty. This
 * exercises the distinct "bodyGroup empty -> SKIP" branch, which is
 * different from test 3's "no matching heading for slug" (destText nil)
 * and "linkText never drawn at all" (matches[T] itself empty) skip paths.
 *
 * Assert: 0 annotations added, no throw.
 *
 * Like test 4, this expected outcome (0 annotations) is a regression guard
 * for the engine's bodyGroup-empty skip branch, not a count that varies
 * with the implementation.
 */
- (void)testBodyGroupEmptySkipsLinkWithoutThrowing
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Ghost" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];   // TOC entry only; no body occurrence anywhere

    NSArray<NSValue *> *rects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&rects];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Ghost" slug:@"ghost"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[[MPPDFAnchorHeading headingWithSlug:@"ghost" text:@"Ghost"]];

    __block NSUInteger added = 99;
    XCTAssertNoThrow(added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                      links:links
                                                                   headings:headings]);
    XCTAssertEqual(added, (NSUInteger)0,
                  @"A slug whose heading text never appears as a body occurrence (bodyGroup empty) "
                  @"must be skipped, not crash or partially annotate");
    XCTAssertEqual([self totalLinkAnnotationsInDocument:document], (NSUInteger)0,
                  @"No annotation should be added anywhere in the document");
}

#pragma mark - Test 9: Blank linkText Is Skipped

/**
 * A link with a BLANK linkText (empty string) alongside a resolvable
 * "Real" link targeting the same, genuinely-drawn "Real" heading. Per
 * design §4 Step2/Step4, MPPDFAnchorStringIsBlank(link.linkText) must
 * short-circuit before any findString: lookup is attempted for that link,
 * so it can never be searched for, never throws, and never adds an
 * annotation -- while the other, valid link is completely unaffected.
 */
- (void)testBlankLinkTextIsSkippedWithoutAffectingValidLink
{
    PDFDocument *document = [self fixtureWithTOC:@[@"Real"]
                                     bodyHeadings:@[@"Real"]
                                         tocRects:NULL
                                     headingRects:NULL];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"" slug:@"real"],
        [MPPDFAnchorLink linkWithText:@"Real" slug:@"real"],
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"real" text:@"Real"],
    ];

    __block NSUInteger added = 99;
    XCTAssertNoThrow(added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                      links:links
                                                                   headings:headings]);
    XCTAssertEqual(added, (NSUInteger)1,
                  @"The blank-linkText link must be silently skipped; the resolvable 'Real' link "
                  @"must still produce exactly one annotation");
    XCTAssertEqual([self totalLinkAnnotationsInDocument:document], (NSUInteger)1,
                  @"Only the valid link's annotation should exist anywhere in the document");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], (NSUInteger)1,
                      @"The valid 'Real' link must still resolve to the correct heading page");
    }
}

#pragma mark - Test 10: Partial TOC-Occurrence Mismatch

/**
 * Two MPPDFAnchorLinks share the SAME linkText ("Repeat"), but the PDF
 * contains only ONE drawn occurrence of that text (a single TOC-style
 * entry on page 0) -- there is no second "Repeat" anywhere in the document.
 * Both links target a slug that resolves to a genuinely-drawn heading
 * ("Target" on page 1), so the shared destText is resolvable; the only
 * thing limiting the second link is the shortage of source occurrences.
 *
 * Per design §4 Step4, tocAvailable = MIN(tocCount("Repeat")=2,
 * allMatches.count=1) = 1, so only ONE TOC selection exists for "Repeat".
 * The first link (k=0) binds to it and resolves normally. The second link
 * (k=1) hits `k >= tocSelections.count` and must be silently skipped: no
 * throw, no annotation, and the first link's annotation must be completely
 * unaffected.
 */
- (void)testSecondLinkWithSharedTextButNoSecondOccurrenceIsSkipped
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Repeat" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];   // sole "Repeat" occurrence
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Target" fontSize:24.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];   // the heading both links target

    NSArray<NSValue *> *rects = nil;
    PDFDocument *document = [self documentFromDrawItems:items drawnRects:&rects];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"Repeat" slug:@"target-heading"],
        [MPPDFAnchorLink linkWithText:@"Repeat" slug:@"target-heading"],
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"target-heading" text:@"Target"],
    ];

    __block NSUInteger added = 99;
    XCTAssertNoThrow(added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                      links:links
                                                                   headings:headings]);
    XCTAssertEqual(added, (NSUInteger)1,
                  @"Only the first of two links sharing linkText 'Repeat' can be matched to the "
                  @"single drawn TOC occurrence; the second must be silently skipped");
    XCTAssertEqual([self totalLinkAnnotationsInDocument:document], (NSUInteger)1,
                  @"Exactly one annotation total: the skipped second link must not add anything");

    PDFPage *tocPage = [document pageAtIndex:0];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1,
                  @"Exactly one annotation for 'Repeat' should land on the page holding its sole occurrence");
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], (NSUInteger)1,
                      @"The one resolved link must still land on the correct heading page");
    }
}

@end
