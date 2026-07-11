//
//  MPPDFAnchorInjectorTests.m
//  MacDownTests
//
//  Headless (no WebView) tests for the pure PDF anchor-annotation engine
//  described in the design for GitHub issue #504 ("Clickable Internal
//  Anchor Links in Exported PDF").
//
//  Fixture PDFs are generated in-test with real, selectable text. The
//  entire multi-page fixture is drawn into ONE tall NSView (see
//  -documentFromDrawItems:drawnRects:drawnPageIndexes: below and
//  MPPDFTestPrintView) which is handed to NSPrintOperation -- the exact same
//  AppKit printing path
//  MacDown's real "Export to PDF" feature uses. AppKit's automatic
//  vertical pagination slices that single tall view into one printed page
//  per page-height, and (unlike a raw, hand-rolled multi-page
//  CGPDFContext, which was found to embed genuinely searchable text on
//  only its FIRST page) this path reliably embeds correct, portable
//  ToUnicode/encoding text on EVERY resulting page. There is no
//  cross-document merge anywhere: the finished PDF file is loaded exactly
//  once via -[PDFDocument initWithURL:], so every page -- not just page 0
//  -- carries genuinely searchable text that -[PDFDocument
//  findString:withOptions:] can locate. No WebView is involved anywhere in
//  this file.
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


#pragma mark - Print-Based Fixture View

/**
 * A single, TALL NSView holding every draw item for a whole fixture
 * document, stacked page-by-page from top to bottom: its frame is
 * `pageWidth` wide and `pageHeight * pageCount` tall.
 *
 * -documentFromDrawItems:drawnRects:drawnPageIndexes: hands this view to an
 * NSPrintOperation configured with an NSPrintInfo whose paper size is
 * exactly `pageWidth` x `pageHeight` and whose vertical pagination is
 * automatic. That is exactly the AppKit printing path MacDown's own PDF
 * export feature uses, and AppKit reliably slices this one tall view into
 * `pageCount` separate printed pages, top-to-bottom -- unlike a raw,
 * hand-rolled multi-page CGPDFContext, which was found (across 3 CI runs)
 * to embed genuinely `-findString:withOptions:`-searchable text on only
 * its FIRST page.
 *
 * The view is FLIPPED (`-isFlipped` returns YES), so (0, 0) is its
 * top-left corner and y grows downward -- both across the whole tall view
 * and within each `pageHeight`-tall slice. Each MPPDFTestDrawItem's own
 * `topLeftPoint` is already specified in that same top-left, y-down
 * "reading order" convention (see MPPDFTestDrawItem's header comment), so
 * an item destined for `pageIndex` k is placed with a single addition:
 *
 *     viewY = k * pageHeight + topLeftPoint.y
 *     viewX = topLeftPoint.x
 *
 * Because the print paper is exactly `pageHeight` tall and pagination is
 * automatic/vertical-only, AppKit is guaranteed to cut the tall view into
 * slices `[k * pageHeight, (k + 1) * pageHeight)` -- so every item whose
 * `viewY` (as computed above) falls in slice k is printed on (0-indexed)
 * page k, i.e. exactly the page the test author requested via
 * `item.pageIndex`.
 *
 * In a FLIPPED view, `-[NSAttributedString drawAtPoint:]` places the
 * string's TOP-left corner at the given point and the glyphs flow
 * downward from there -- matching `topLeftPoint`'s own top-left, y-down
 * convention exactly, so (unlike the old CGPDFContext path, which had to
 * hand-convert top-left input into the PDF's native bottom-left/y-up space
 * using measured font metrics) no coordinate flip or font-metrics
 * prediction is needed here at all.
 */
@interface MPPDFTestPrintView : NSView
- (instancetype)initWithItems:(NSArray<MPPDFTestDrawItem *> *)items
                    pageWidth:(CGFloat)pageWidth
                   pageHeight:(CGFloat)pageHeight
                    pageCount:(NSUInteger)pageCount;
@end

@implementation MPPDFTestPrintView {
    NSArray<MPPDFTestDrawItem *> *_items;
    CGFloat _pageHeight;
}

- (instancetype)initWithItems:(NSArray<MPPDFTestDrawItem *> *)items
                    pageWidth:(CGFloat)pageWidth
                   pageHeight:(CGFloat)pageHeight
                    pageCount:(NSUInteger)pageCount
{
    NSRect frame = NSMakeRect(0, 0, pageWidth, pageHeight * (CGFloat)pageCount);
    self = [super initWithFrame:frame];
    if (self) {
        _items = [items copy];
        _pageHeight = pageHeight;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor whiteColor] setFill];
    NSRectFill(self.bounds);

    for (MPPDFTestDrawItem *item in _items) {
        // Use a standard PDF base-14 font (Helvetica) rather than the
        // private San Francisco system UI font: Helvetica is always
        // present on macOS and reliably carries a correct
        // ToUnicode/encoding mapping when printed to PDF, keeping the
        // drawn glyphs text-extractable via
        // -[PDFDocument findString:withOptions:].
        NSFont *font = [NSFont fontWithName:@"Helvetica" size:item.fontSize];
        if (!font) {
            font = [NSFont userFontOfSize:item.fontSize]; // ultra-safe fallback
        }
        NSDictionary *attrs = @{NSFontAttributeName: font};
        NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:item.text
                                                                          attributes:attrs];

        // See the class comment above: topLeftPoint is already top-left,
        // y-down within its own page, so placing it in this flipped tall
        // view is just an offset by that page's slice of pageHeight.
        CGFloat viewX = item.topLeftPoint.x;
        CGFloat viewY = (CGFloat)item.pageIndex * _pageHeight + item.topLeftPoint.y;
        [attrString drawAtPoint:NSMakePoint(viewX, viewY)];
    }
}

@end


#pragma mark - Test Case

@interface MPPDFAnchorInjectorTests : XCTestCase
@end


@implementation MPPDFAnchorInjectorTests

#pragma mark - Fixture Building

/**
 * Draws every item in `items` into a freshly generated, single 612x792
 * (US Letter) PDF document, one page per distinct pageIndex referenced by
 * `items`.
 *
 * The WHOLE multi-page document is produced by printing ONE tall
 * MPPDFTestPrintView (see its class comment above) through a real
 * NSPrintOperation -- the same AppKit printing path MacDown's own PDF
 * export feature uses -- rather than by hand-assembling a CGPDFContext or
 * merging separate per-page PDFDocuments via `-insertPage:`. The
 * NSPrintInfo's paper size is fixed at `kMPTestPageWidth` x
 * `kMPTestPageHeight` with all margins zeroed, horizontal pagination set
 * to fit the page width, and vertical pagination left automatic, so
 * AppKit auto-paginates the tall view into one printed page per
 * `kMPTestPageHeight` slice. The operation is run synchronously
 * (`-runOperation`), saving directly to a unique temp file, which is then
 * loaded exactly once via `-[PDFDocument initWithURL:]` and removed.
 *
 * Because this is the exact printing path known to embed correct,
 * portable ToUnicode/encoding text on EVERY page (unlike a raw multi-page
 * CGPDFContext, which was found across 3 CI runs to only keep page 0
 * genuinely searchable), and because Helvetica is one of the 14 standard
 * PDF fonts with reliable, portable ToUnicode/encoding support (unlike the
 * private San Francisco system font), the resulting text is
 * `-findString:withOptions:`-searchable on EVERY page, not just page 0.
 *
 * After assembly, the document's `.string` is force-accessed (and the
 * document is round-tripped once through `-dataRepresentation` /
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
 *
 * If `outDrawnPageIndexes` is non-NULL, it is set to an array of
 * NSNumber-wrapped NSUIntegers, one per entry in `items` (same order,
 * parallel to `outDrawnRects`): the ACTUAL page index each item's text was
 * found on in the finished PDF. This is measured ground truth too -- it is
 * NOT `item.pageIndex` (the page the test INTENDED the item to land on via
 * placement math). The two can diverge across environments because
 * placement uses `printInfo.imageablePageBounds`, which depends on the
 * environment's configured printer/paper (see the `effectivePageHeight`
 * comment below); the measured page index is what AppKit actually did.
 * Tests must assert against measured page indexes, never against
 * `item.pageIndex` or any hardcoded page number, to stay environment
 * independent.
 */
- (PDFDocument *)documentFromDrawItems:(NSArray<MPPDFTestDrawItem *> *)items
                             drawnRects:(NSArray<NSValue *> **)outDrawnRects
                       drawnPageIndexes:(NSArray<NSNumber *> **)outDrawnPageIndexes
{
    NSUInteger pageCount = 1;
    for (MPPDFTestDrawItem *item in items) {
        pageCount = MAX(pageCount, item.pageIndex + 1);
    }

    NSString *tempFileName = [NSString stringWithFormat:@"MPPDFAnchorInjectorTests-%@.pdf",
                               [[NSProcessInfo processInfo] globallyUniqueString]];
    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                              stringByAppendingPathComponent:tempFileName]];

    NSPrintInfo *printInfo = [[NSPrintInfo alloc] init];
    printInfo.paperSize = NSMakeSize(kMPTestPageWidth, kMPTestPageHeight);
    printInfo.topMargin = 0;
    printInfo.bottomMargin = 0;
    printInfo.leftMargin = 0;
    printInfo.rightMargin = 0;
    printInfo.horizontalPagination = NSFitPagination;
    printInfo.verticalPagination = NSAutoPagination;
    printInfo.jobDisposition = NSPrintSaveJob;
    [printInfo.dictionary setObject:tempURL forKey:NSPrintJobSavingURL];

    // AppKit auto-paginates the tall view against the printer's IMAGEABLE
    // page height, not the nominal paper height: the virtual "Save as PDF"
    // printer imposes small fixed unprintable margins that zeroing the user
    // margins does not remove, so the imageable height is a few points less
    // than kMPTestPageHeight. Sizing the view by the nominal 792pt made the
    // view an exact multiple of 792, but AppKit sliced it against the shorter
    // imageable height and so produced pageCount+1 pages (off by exactly one).
    // Size the view (and place items) by the ACTUAL imageable height so the
    // tall view is exactly pageCount imageable-slices tall -> exactly pageCount
    // pages, and each pageIndex-k item lands on printed page k.
    CGFloat effectivePageHeight = printInfo.imageablePageBounds.size.height;
    if (effectivePageHeight <= 0) {
        effectivePageHeight = kMPTestPageHeight;
    }

    MPPDFTestPrintView *printView = [[MPPDFTestPrintView alloc] initWithItems:items
                                                                     pageWidth:kMPTestPageWidth
                                                                    pageHeight:effectivePageHeight
                                                                     pageCount:pageCount];

    NSPrintOperation *printOperation = [NSPrintOperation printOperationWithView:printView
                                                                       printInfo:printInfo];
    printOperation.showsPrintPanel = NO;
    printOperation.showsProgressPanel = NO;

    BOOL ranSuccessfully = [printOperation runOperation];
    XCTAssertTrue(ranSuccessfully, @"NSPrintOperation failed to run while generating the fixture PDF");

    NSFileManager *fileManager = [NSFileManager defaultManager];
    XCTAssertTrue([fileManager fileExistsAtPath:tempURL.path],
                  @"NSPrintOperation should have synchronously saved the fixture PDF to disk");

    PDFDocument *document = [[PDFDocument alloc] initWithURL:tempURL];
    [fileManager removeItemAtPath:tempURL.path error:NULL];

    XCTAssertNotNil(document, @"Failed to load the NSPrintOperation-generated fixture PDF");
    if (document == nil) {
        return nil;
    }

    XCTAssertEqual(document.pageCount, pageCount,
                  @"Fixture should have one page per requested pageIndex");

    // Defensively force a full, synchronous text-index parse -- both on the
    // freshly-loaded document and again after a round trip through
    // -dataRepresentation/-initWithData: -- before this fixture is handed
    // to the engine or measured below.
    (void)document.string;
    NSData *roundTripData = document.dataRepresentation;
    PDFDocument *finalDocument = roundTripData ? [[PDFDocument alloc] initWithData:roundTripData] : nil;
    if (finalDocument == nil) {
        finalDocument = document;
    }
    (void)finalDocument.string;

    if (outDrawnRects || outDrawnPageIndexes) {
        NSArray<NSNumber *> *pageIndexes = nil;
        NSArray<NSValue *> *rects = [self measuredRectsForItems:items
                                                       inDocument:finalDocument
                                                      pageIndexes:&pageIndexes];
        if (outDrawnRects) {
            *outDrawnRects = rects;
        }
        if (outDrawnPageIndexes) {
            *outDrawnPageIndexes = pageIndexes;
        }
    }

    return finalDocument;
}

/**
 * Measures the GROUND-TRUTH rect (PDF/bottom-left coordinates) AND the
 * GROUND-TRUTH page index for every entry in `items`, by locating its drawn
 * text in the already-assembled `document` via `-findString:withOptions:`,
 * exactly as the engine under test does. Results are returned in the same
 * order as `items`; `outPageIndexes` (if non-NULL) is set to a parallel
 * array of NSNumber-wrapped NSUIntegers.
 *
 * Deliberately independent of `item.pageIndex`: `item.pageIndex` is the
 * page the test INTENDED an item to print on (used only to compute its
 * placement -- see `viewY` in -[MPPDFTestPrintView drawRect:]), which can
 * diverge from the page AppKit actually paginates it onto in environments
 * where `printInfo.imageablePageBounds` differs from what
 * `documentFromDrawItems:drawnRects:drawnPageIndexes:` assumed when sizing
 * the fixture view (this is the root cause of the CI-only off-by-one-page /
 * 734pt-offset failures: a "Save as PDF" printer's imageable height locally
 * is ~774.99pt, but CI's fallback geometry is ~734pt). Using `item.pageIndex`
 * here would reproduce exactly that same bug in the test's OWN ground truth.
 *
 * Instead, every item's actual page/bounds are resolved purely by ordinal
 * position among same-text items, in the same order the items were APPENDED
 * to the `items` array (which is always ascending document/print order for
 * every fixture built in this file: same-text items are always added in the
 * order they are meant to print, top of document to bottom). Since
 * `-findString:withOptions:` returns matches in that same document order,
 * the Nth item (in `items` array order) with text T is matched to the Nth
 * `-findString:` match for T, full stop -- no page filtering, so it can
 * never silently miss or misattribute an occurrence just because AppKit
 * paginated differently than intended.
 */
- (NSArray<NSValue *> *)measuredRectsForItems:(NSArray<MPPDFTestDrawItem *> *)items
                                    inDocument:(PDFDocument *)document
                                   pageIndexes:(NSArray<NSNumber *> **)outPageIndexes
{
    // PDFKit vends the SAME PDFSelection instance across successive
    // -findString: calls on one document: a later search mutates an earlier
    // search's returned selections in place (their .string, page, and bounds
    // all change). Caching arrays of live PDFSelection objects here and
    // reading their page/geometry LATER -- after this method has searched for
    // a different item's text -- reads clobbered data, making a body heading
    // on page >=1 appear to vanish. Snapshot each match's (pageIndex, bounds)
    // into a plain value IMMEDIATELY after its -findString: call, before any
    // later needle search can mutate it, and match items against those
    // snapshots. Mirrors the same snapshot fix in MPPDFAnchorInjector.m.
    // Issue #504.
    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *pageIndexesByText = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray<NSValue *> *> *boundsByText = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *consumedForText = [NSMutableDictionary dictionary];
    NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableArray<NSNumber *> *pageIndexes = [NSMutableArray arrayWithCapacity:items.count];

    for (MPPDFTestDrawItem *item in items) {
        NSArray<NSNumber *> *snapshotPageIndexes = pageIndexesByText[item.text];
        if (snapshotPageIndexes == nil) {
            NSArray<PDFSelection *> *matches = [document findString:item.text withOptions:0] ?: @[];
            NSMutableArray<NSNumber *> *pageIndexSnapshots = [NSMutableArray array];
            NSMutableArray<NSValue *> *boundsSnapshots = [NSMutableArray array];
            // Read every selection's page + bounds NOW, before the next
            // -findString: (for a different item text) can mutate them.
            for (PDFSelection *selection in matches) {
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
                [pageIndexSnapshots addObject:@(pageIndex)];
                [boundsSnapshots addObject:[NSValue valueWithRect:[selection boundsForPage:page]]];
            }
            snapshotPageIndexes = pageIndexSnapshots;
            pageIndexesByText[item.text] = pageIndexSnapshots;
            boundsByText[item.text] = boundsSnapshots;
        }
        NSArray<NSValue *> *snapshotBounds = boundsByText[item.text];

        // Ordinal position among ALL items requesting this text, regardless
        // of intended page -- see method comment above for why this must not
        // filter by item.pageIndex.
        NSUInteger occurrenceIndex = consumedForText[item.text].unsignedIntegerValue;
        consumedForText[item.text] = @(occurrenceIndex + 1);

        CGRect rect = CGRectZero;
        NSUInteger pageIndex = NSNotFound;
        if (occurrenceIndex < snapshotBounds.count) {
            rect = NSRectToCGRect([snapshotBounds[occurrenceIndex] rectValue]);
            pageIndex = snapshotPageIndexes[occurrenceIndex].unsignedIntegerValue;
        } else {
            XCTFail(@"Could not locate drawn text '%@' (occurrence %lu) via findString: -- "
                    @"the fixture's text may not be searchable", item.text, (unsigned long)occurrenceIndex);
        }

        [rects addObject:[NSValue valueWithRect:NSRectFromCGRect(rect)]];
        [pageIndexes addObject:@(pageIndex)];
    }

    if (outPageIndexes) {
        *outPageIndexes = pageIndexes;
    }
    return rects;
}

/**
 * Convenience wrapper (design §7): TOC entries drawn one per line at 12pt
 * on page 0; each body heading drawn at 24pt alone on its own subsequent
 * page (page 1, 2, ...), in the order given. Used by tests 1, 4, 7, 9.
 *
 * `outTocPageIndexes`/`outHeadingPageIndexes` (both optional), if provided,
 * are set to the MEASURED (ground-truth, via `-findString:withOptions:`)
 * page index each TOC entry / heading actually landed on in the finished
 * PDF -- NOT the page it was intended to print on. Callers must assert
 * against these, never against a hardcoded/assumed page number, so the
 * tests stay correct regardless of the environment's default
 * printer/imageable-area geometry (see `measuredRectsForItems:inDocument:
 * pageIndexes:`'s comment for why this distinction matters).
 */
- (PDFDocument *)fixtureWithTOC:(NSArray<NSString *> *)toc
                   bodyHeadings:(NSArray<NSString *> *)headings
                       tocRects:(NSArray<NSValue *> **)outTocRects
                   headingRects:(NSArray<NSValue *> **)outHeadingRects
                tocPageIndexes:(NSArray<NSNumber *> **)outTocPageIndexes
            headingPageIndexes:(NSArray<NSNumber *> **)outHeadingPageIndexes
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
    NSArray<NSNumber *> *allPageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&allRects
                                        drawnPageIndexes:&allPageIndexes];

    if (outTocRects) {
        *outTocRects = [allRects subarrayWithRange:NSMakeRange(0, toc.count)];
    }
    if (outHeadingRects) {
        *outHeadingRects = [allRects subarrayWithRange:NSMakeRange(toc.count, headings.count)];
    }
    if (outTocPageIndexes) {
        *outTocPageIndexes = [allPageIndexes subarrayWithRange:NSMakeRange(0, toc.count)];
    }
    if (outHeadingPageIndexes) {
        *outHeadingPageIndexes = [allPageIndexes subarrayWithRange:NSMakeRange(toc.count, headings.count)];
    }
    return document;
}

#pragma mark - Assertion Helpers

// Whether a PDF annotation is a link annotation, robust across PDFKit's
// slash convention. The injector builds link annotations with
// -initWithBounds:forType:PDFAnnotationSubtypeLink..., which on this platform
// yields a plain `PDFAnnotation` instance (NOT a `PDFAnnotationLink`
// subclass), whose `.type` reads back as @"Link" while the
// `PDFAnnotationSubtypeLink` constant is @"/Link" (leading slash). Comparing
// `.type` directly to the constant -- or testing `isKindOfClass:
// [PDFAnnotationLink class]` -- therefore both fail. Strip an optional leading
// "/" from BOTH sides before comparing (not just the constant), so this
// keeps matching even if a future macOS starts returning `.type` WITH its
// own leading slash (i.e. also @"/Link") instead of without one.
static NSString *MPTestStripLeadingSlash(NSString *string)
{
    if ([string hasPrefix:@"/"]) {
        return [string substringFromIndex:1];
    }
    return string;
}

static BOOL MPTestAnnotationIsLink(PDFAnnotation *annotation)
{
    if (annotation == nil) {
        return NO;
    }
    NSString *type = annotation.type;
    if (type.length == 0) {
        return NO;
    }
    return [MPTestStripLeadingSlash(type) isEqualToString:MPTestStripLeadingSlash(PDFAnnotationSubtypeLink)];
}

- (NSArray<PDFAnnotation *> *)linkAnnotationsOnPage:(PDFPage *)page
{
    NSMutableArray<PDFAnnotation *> *result = [NSMutableArray array];
    for (PDFAnnotation *annotation in page.annotations) {
        if (MPTestAnnotationIsLink(annotation)) {
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
    NSArray<NSNumber *> *tocPageIndexes = nil;
    NSArray<NSNumber *> *headingPageIndexes = nil;
    PDFDocument *document = [self fixtureWithTOC:@[@"Intro", @"Details"]
                                     bodyHeadings:@[@"Intro", @"Details"]
                                         tocRects:&tocRects
                                     headingRects:&headingRects
                                  tocPageIndexes:&tocPageIndexes
                              headingPageIndexes:&headingPageIndexes];

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

    // The TOC entries are the first text drawn in the fixture, so they land
    // on the same (measured) page -- use that measured page rather than
    // assuming page 0, though for this fixture size it is always page 0.
    PDFPage *tocPage = [document pageAtIndex:tocPageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)2,
                  @"TOC page should have exactly 2 link annotations");

    // Match each injected annotation back to its expected TOC entry by
    // source-rect proximity, since injected annotation order on a page is
    // not otherwise part of the contract.
    for (NSUInteger i = 0; i < 2; i++) {
        CGRect expectedTocRect = NSRectToCGRect([tocRects[i] rectValue]);
        CGRect expectedHeadingRect = NSRectToCGRect([headingRects[i] rectValue]);
        NSUInteger expectedPageIndex = headingPageIndexes[i].unsignedIntegerValue;

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

        XCTAssertTrue(MPTestAnnotationIsLink(match),
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
                                        topLeftPoint:CGPointMake(72, 72)]];   // FIRST body occurrence (document order)
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Dup" fontSize:24.0 pageIndex:2
                                        topLeftPoint:CGPointMake(72, 72)]];   // second body occurrence

    NSArray<NSValue *> *rects = nil;
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Dup" slug:@"dup"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"dup" text:@"Dup"],
        [MPPDFAnchorHeading headingWithSlug:@"dup" text:@"Dup"],
    ];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)1, @"Exactly one annotation should be injected for the single TOC link");

    // items[0] is the TOC entry; it is the first thing drawn, so it lands on
    // the first (measured) page.
    PDFPage *tocPage = [document pageAtIndex:pageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count != 1) {
        return;
    }

    // items[1] is the FIRST body occurrence of "Dup" in document order --
    // the occurrence the collision rule requires the engine to resolve to.
    // Its measured page is the intended destination page, independent of
    // whatever page it was originally placed to land on.
    NSUInteger expectedFirstOccurrencePageIndex = pageIndexes[1].unsignedIntegerValue;

    PDFAnnotation *annotation = tocAnnotations.firstObject;
    XCTAssertTrue([annotation.action isKindOfClass:[PDFActionGoTo class]]);
    if (![annotation.action isKindOfClass:[PDFActionGoTo class]]) {
        return;
    }
    PDFActionGoTo *goTo = (PDFActionGoTo *)annotation.action;
    NSUInteger destinationPageIndex = [document indexForPage:goTo.destination.page];
    XCTAssertEqual(destinationPageIndex, expectedFirstOccurrencePageIndex,
                  @"Colliding slugs must resolve to the FIRST body occurrence in document order, "
                  @"not the second");
}

#pragma mark - Test 3: No-Match / Inert-Safe

/**
 * Mixes one resolvable link ("Real" -> heading "real") with:
 *   - a link whose targetSlug ("unknown-slug") has no matching heading,
 *   - a link whose linkText ("NeverDrawn") does not appear anywhere in the
 *     PDF at all, and
 *   - a link ("EmptyTarget" -> "empty-heading") whose target heading has
 *     EMPTY text. Per design §4 Step1, a heading with blank text is dropped
 *     entirely and never recorded in slugToHeadingText, so destText resolves
 *     to nil (not "") for this slug; either way an empty/nil heading text
 *     must never be used as a findString: needle (it would nonsensically
 *     match everywhere, or crash), so the engine must SKIP this link rather
 *     than search for it.
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
    // Placed well clear of the top-of-page boundary (Issue #504): a couple
    // of CI runs showed this occurrence intermittently not text-searchable
    // when drawn right at the imageable-area edge, so it is drawn further
    // down the page than the bare 72pt used elsewhere, giving it a
    // comfortable margin on every side.
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Real" fontSize:24.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 200)]];   // "Real" heading, the intended destination

    NSArray<NSValue *> *rects = nil;
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

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

    // items[0] is the "Real" TOC entry -- the first thing drawn.
    PDFPage *tocPage = [document pageAtIndex:pageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    // items[3] is the sole body occurrence of "Real" (the heading) -- the
    // intended destination, identified by document order, not by an assumed
    // page index.
    NSUInteger expectedDestinationPageIndex = pageIndexes[3].unsignedIntegerValue;
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], expectedDestinationPageIndex,
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
                                     headingRects:NULL
                                  tocPageIndexes:NULL
                              headingPageIndexes:NULL];
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
                                        topLeftPoint:CGPointMake(72, 72)]];   // TOC entry
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Sub" fontSize:14.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];   // sole body occurrence (the heading)

    NSArray<NSValue *> *rects = nil;
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Sub" slug:@"sub"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[[MPPDFAnchorHeading headingWithSlug:@"sub" text:@"Sub"]];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)1,
                  @"Same-size TOC entry and heading (default-theme h5/h6 case) must still resolve "
                  @"via the document-order fallback");

    // items[0] is the TOC entry.
    PDFPage *tocPage = [document pageAtIndex:pageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    // items[1] is the sole body occurrence -- the only possible fallback
    // destination, identified by document order.
    NSUInteger expectedDestinationPageIndex = pageIndexes[1].unsignedIntegerValue;
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], expectedDestinationPageIndex,
                      @"Fallback destination should be the (only) body occurrence");
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
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

    NSArray<MPPDFAnchorLink *> *links = @[[MPPDFAnchorLink linkWithText:@"Target" slug:@"target"]];
    NSArray<MPPDFAnchorHeading *> *headings = @[[MPPDFAnchorHeading headingWithSlug:@"target" text:@"Target"]];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)1);

    // items[0] is the TOC entry.
    PDFPage *tocPage = [document pageAtIndex:pageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);

    // Identify the intended destination the SAME way the engine does (design
    // §4 Step5(i)): the first body occurrence (document order among
    // items[1...]) whose MEASURED height exceeds the TOC entry's measured
    // height. This mirrors the engine's own height-promotion criterion
    // rather than assuming a page number, so this test still verifies the
    // height-promotion LOGIC (not just an outcome) independent of pagination.
    CGFloat tocHeight = NSHeight(NSRectFromCGRect(NSRectToCGRect([rects[0] rectValue])));
    NSUInteger expectedDestinationPageIndex = NSNotFound;
    for (NSUInteger i = 1; i < items.count; i++) {
        CGFloat candidateHeight = NSHeight(NSRectFromCGRect(NSRectToCGRect([rects[i] rectValue])));
        if (candidateHeight > tocHeight) {
            expectedDestinationPageIndex = pageIndexes[i].unsignedIntegerValue;
            break;
        }
    }
    XCTAssertNotEqual(expectedDestinationPageIndex, (NSUInteger)NSNotFound,
                      @"Fixture sanity check: exactly one body occurrence should be taller than the TOC entry");

    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        NSUInteger destinationPageIndex = [document indexForPage:goTo.destination.page];
        XCTAssertEqual(destinationPageIndex, expectedDestinationPageIndex,
                      @"Destination must resolve to the larger 24pt heading, not the "
                      @"same-body-size (12pt) prose");
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
    NSArray<NSNumber *> *tocPageIndexes = nil;
    NSArray<NSNumber *> *headingPageIndexes = nil;
    PDFDocument *document = [self fixtureWithTOC:@[@"Intro", @"Intro"]
                                     bodyHeadings:@[@"Intro"]
                                         tocRects:&tocRects
                                     headingRects:&headingRects
                                  tocPageIndexes:&tocPageIndexes
                              headingPageIndexes:&headingPageIndexes];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"Intro" slug:@"intro"],
        [MPPDFAnchorLink linkWithText:@"Intro" slug:@"intro"],
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"intro" text:@"Intro"],
    ];

    NSUInteger added = [MPPDFAnchorInjector injectLinksIntoDocument:document links:links headings:headings];
    XCTAssertEqual(added, (NSUInteger)2, @"Both links to the same slug must each get their own annotation");

    PDFPage *tocPage = [document pageAtIndex:tocPageIndexes[0].unsignedIntegerValue];
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
        XCTAssertEqual(actualPageIndex, headingPageIndexes[0].unsignedIntegerValue,
                      @"Both links should navigate to the single heading's (measured) page");
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
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

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
    NSArray<NSNumber *> *tocPageIndexes = nil;
    NSArray<NSNumber *> *headingPageIndexes = nil;
    PDFDocument *document = [self fixtureWithTOC:@[@"Real"]
                                     bodyHeadings:@[@"Real"]
                                         tocRects:NULL
                                     headingRects:NULL
                                  tocPageIndexes:&tocPageIndexes
                              headingPageIndexes:&headingPageIndexes];

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

    PDFPage *tocPage = [document pageAtIndex:tocPageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1);
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], headingPageIndexes[0].unsignedIntegerValue,
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
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

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

    // items[0] is the sole "Repeat" occurrence.
    PDFPage *tocPage = [document pageAtIndex:pageIndexes[0].unsignedIntegerValue];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1,
                  @"Exactly one annotation for 'Repeat' should land on the page holding its sole occurrence");
    // items[1] is the "Target" heading -- the intended destination.
    NSUInteger expectedDestinationPageIndex = pageIndexes[1].unsignedIntegerValue;
    if (tocAnnotations.count == 1 && [tocAnnotations.firstObject.action isKindOfClass:[PDFActionGoTo class]]) {
        PDFActionGoTo *goTo = (PDFActionGoTo *)tocAnnotations.firstObject.action;
        XCTAssertEqual([document indexForPage:goTo.destination.page], expectedDestinationPageIndex,
                      @"The one resolved link must still land on the correct heading page");
    }
}

#pragma mark - Test 11: Counter Advances Past a Skipped Same-Text Link

/**
 * Guards the counter-advancement logic exercised by design §4 Step4: the
 * per-linkText occurrence counter (`linkTextCounter` in
 * MPPDFAnchorInjector.m) must advance for EVERY link sharing a given
 * linkText, whether or not that link is ultimately skipped -- otherwise a
 * later link with the same linkText would wrongly bind to an EARLIER TOC
 * occurrence than the one it actually appears at.
 *
 * Two links share linkText "Repeat", and the PDF draws TWO separate
 * "Repeat" TOC occurrences (so there is no shortage of source
 * occurrences, unlike test 10). The FIRST link targets a slug
 * ("missing-heading") with NO matching heading in the model at all, so it
 * must be skipped at Step5 (destText nil) -- but Step4's occurrence
 * counter must still advance for it (k=0 -> consumed). The SECOND link
 * targets a slug that resolves to a real, genuinely-drawn heading
 * ("Target"), and per Step4 must bind to k=1 -- the SECOND "Repeat" TOC
 * occurrence, not the first.
 *
 * Assert: exactly 1 annotation is added in total, anchored at the SECOND
 * "Repeat" occurrence (not the first), resolving to Target's measured
 * page. Ground truth for "which Repeat occurrence" and "Target's page" is
 * measured via the same document-order machinery as every other test
 * above -- never a hardcoded page number.
 */
- (void)testSecondLinkWithSharedTextSkipsPastFirstOccurrenceWhenFirstLinkIsSkipped
{
    NSMutableArray<MPPDFTestDrawItem *> *items = [NSMutableArray array];
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Repeat" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 72)]];    // first "Repeat" occurrence (unused: link 1 skipped)
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Repeat" fontSize:12.0 pageIndex:0
                                        topLeftPoint:CGPointMake(72, 96)]];    // second "Repeat" occurrence (link 2's source)
    [items addObject:[MPPDFTestDrawItem itemWithText:@"Target" fontSize:24.0 pageIndex:1
                                        topLeftPoint:CGPointMake(72, 72)]];    // link 2's destination heading

    NSArray<NSValue *> *rects = nil;
    NSArray<NSNumber *> *pageIndexes = nil;
    PDFDocument *document = [self documentFromDrawItems:items
                                              drawnRects:&rects
                                        drawnPageIndexes:&pageIndexes];

    NSArray<MPPDFAnchorLink *> *links = @[
        [MPPDFAnchorLink linkWithText:@"Repeat" slug:@"missing-heading"],   // no matching heading -> skipped
        [MPPDFAnchorLink linkWithText:@"Repeat" slug:@"target-heading"],    // resolves to "Target"
    ];
    NSArray<MPPDFAnchorHeading *> *headings = @[
        [MPPDFAnchorHeading headingWithSlug:@"target-heading" text:@"Target"],
    ];

    __block NSUInteger added = 99;
    XCTAssertNoThrow(added = [MPPDFAnchorInjector injectLinksIntoDocument:document
                                                                      links:links
                                                                   headings:headings]);
    XCTAssertEqual(added, (NSUInteger)1,
                  @"The first (unresolvable) 'Repeat' link must be skipped; the second must still "
                  @"resolve to exactly one annotation");
    XCTAssertEqual([self totalLinkAnnotationsInDocument:document], (NSUInteger)1,
                  @"Exactly one annotation total in the whole document");

    // items[1] is the SECOND "Repeat" occurrence -- the one the second link
    // must bind to, per the counter-advancement rule.
    CGRect expectedTocRect = NSRectToCGRect([rects[1] rectValue]);
    NSUInteger expectedTocPageIndex = pageIndexes[1].unsignedIntegerValue;
    // items[2] is the "Target" heading -- the intended destination.
    NSUInteger expectedDestinationPageIndex = pageIndexes[2].unsignedIntegerValue;

    PDFPage *tocPage = [document pageAtIndex:expectedTocPageIndex];
    NSArray<PDFAnnotation *> *tocAnnotations = [self linkAnnotationsOnPage:tocPage];
    XCTAssertEqual(tocAnnotations.count, (NSUInteger)1,
                  @"Exactly one annotation should land on the page holding the SECOND 'Repeat' occurrence");
    if (tocAnnotations.count != 1) {
        return;
    }

    PDFAnnotation *annotation = tocAnnotations.firstObject;
    XCTAssertEqualWithAccuracy(NSMinX(annotation.bounds), CGRectGetMinX(expectedTocRect), kMPTestTolerance,
                              @"The injected annotation must be anchored at the SECOND 'Repeat' occurrence, "
                              @"not the first (which belonged to the skipped link)");
    XCTAssertEqualWithAccuracy(NSMinY(annotation.bounds), CGRectGetMinY(expectedTocRect), kMPTestTolerance,
                              @"The injected annotation must be anchored at the SECOND 'Repeat' occurrence, "
                              @"not the first (which belonged to the skipped link)");

    XCTAssertTrue(MPTestAnnotationIsLink(annotation), @"Injected annotation should be a link annotation");
    XCTAssertTrue([annotation.action isKindOfClass:[PDFActionGoTo class]],
                  @"Injected annotation's action should be a PDFActionGoTo");
    if (![annotation.action isKindOfClass:[PDFActionGoTo class]]) {
        return;
    }
    PDFActionGoTo *goTo = (PDFActionGoTo *)annotation.action;
    NSUInteger actualDestinationPageIndex = [document indexForPage:goTo.destination.page];
    XCTAssertEqual(actualDestinationPageIndex, expectedDestinationPageIndex,
                  @"The second link must resolve to Target's (measured) page");
}

@end
