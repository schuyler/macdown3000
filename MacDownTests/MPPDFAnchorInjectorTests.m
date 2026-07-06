//
//  MPPDFAnchorInjectorTests.m
//  MacDownTests
//
//  Headless (no WebView) tests for the pure PDF anchor-annotation engine
//  described in the design for GitHub issue #504 ("Clickable Internal
//  Anchor Links in Exported PDF").
//
//  Fixture PDFs are generated in-test with real, selectable text (drawn via
//  -[NSAttributedString drawAtPoint:] into a CGPDFContext) so that
//  -[PDFDocument findString:withOptions:] can genuinely locate them, the
//  same way the real export pipeline's PDF-native text search does. No
//  WebView is involved anywhere in this file.
//
//  RED STATE: as of this writing, MPPDFAnchorInjector's
//  +injectLinksIntoDocument:links:headings: is an intentional no-op stub
//  that always returns 0 and adds no annotations (see the TODO(#504) in
//  MPPDFAnchorInjector.m). Every behavioral assertion below therefore fails
//  until the real text-search + disambiguation algorithm is implemented.
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
// bottom-left, y-up coordinate space both when it draws the glyphs and when
// it reports the resulting rect back to the test.
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


#pragma mark - Test Case

// US Letter, matching the media box used by every fixture page.
static const CGFloat kMPTestPageWidth = 612.0;
static const CGFloat kMPTestPageHeight = 792.0;

// Font metrics vary slightly by rendering environment; tolerate a couple of
// points of slop when comparing rects/points, per design §7.
static const CGFloat kMPTestTolerance = 2.0;

@interface MPPDFAnchorInjectorTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *temporaryFixtureURLs;
@end


@implementation MPPDFAnchorInjectorTests

- (void)setUp
{
    [super setUp];
    self.temporaryFixtureURLs = [NSMutableArray array];
}

- (void)tearDown
{
    for (NSURL *url in self.temporaryFixtureURLs) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }
    self.temporaryFixtureURLs = nil;
    [super tearDown];
}

#pragma mark - Fixture Building

/**
 * Draws every item in `items` into a freshly generated PDF, one 612x792
 * (US Letter) media box per page, using real Cocoa text drawing so the
 * glyphs are genuinely selectable text -- `-[PDFDocument
 * findString:withOptions:]` must be able to locate them, exactly as it
 * would against a real exported document.
 *
 * Coordinate mapping: each item's `topLeftPoint` is specified from the
 * page's top-left corner (y grows downward). PDF pages are natively
 * bottom-left-origin, y-up, so for a page of height H the drawn rect's
 * bottom-left corner sits at
 *     (topLeftPoint.x, H - topLeftPoint.y - measuredHeight)
 * and `-[NSAttributedString drawAtPoint:]` is invoked at that same point
 * inside an UNFLIPPED (flipped:NO) graphics context wrapping the
 * CGPDFContext -- CGPDFContext's native page space is already
 * bottom-left/y-up, so flipped:NO makes NSGraphicsContext's coordinate
 * convention match the underlying CGContext exactly, with no additional
 * transform. The measured text size comes from `-[NSAttributedString
 * size]`.
 *
 * Returns the loaded PDFDocument. If `outDrawnRects` is non-NULL, it is set
 * to an array of NSValue-wrapped CGRects (PDF/bottom-left coordinates), one
 * per entry in `items`, in the SAME ORDER as `items` (independent of which
 * page each item lands on), for assertions.
 */
- (PDFDocument *)documentFromDrawItems:(NSArray<MPPDFTestDrawItem *> *)items
                             drawnRects:(NSArray<NSValue *> **)outDrawnRects
{
    // First pass: compute each item's drawn rect/point in PDF (bottom-left)
    // coordinates, in `items` order, independent of page grouping.
    NSMutableArray<NSValue *> *drawnRects = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableArray<NSValue *> *drawPoints = [NSMutableArray arrayWithCapacity:items.count];

    NSUInteger pageCount = 1;
    for (MPPDFTestDrawItem *item in items) {
        NSFont *font = [NSFont systemFontOfSize:item.fontSize];
        NSDictionary *attrs = @{NSFontAttributeName: font};
        NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:item.text
                                                                          attributes:attrs];
        NSSize measured = attrString.size;

        CGFloat pdfX = item.topLeftPoint.x;
        CGFloat pdfY = kMPTestPageHeight - item.topLeftPoint.y - measured.height;
        NSPoint drawPoint = NSMakePoint(pdfX, pdfY);
        CGRect drawnRect = CGRectMake(pdfX, pdfY, measured.width, measured.height);

        [drawPoints addObject:[NSValue valueWithPoint:drawPoint]];
        [drawnRects addObject:[NSValue valueWithRect:NSRectFromCGRect(drawnRect)]];

        pageCount = MAX(pageCount, item.pageIndex + 1);
    }

    // Second pass: actually draw, page by page, reusing the precomputed
    // points so drawing order never affects the reported rects.
    NSURL *tempURL = [NSURL fileURLWithPath:
                       [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]
                        stringByAppendingPathExtension:@"pdf"]];
    [self.temporaryFixtureURLs addObject:tempURL];

    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL((__bridge CFURLRef)tempURL);
    CGRect mediaBox = CGRectMake(0, 0, kMPTestPageWidth, kMPTestPageHeight);
    CGContextRef ctx = CGPDFContextCreate(consumer, &mediaBox, NULL);
    CGDataConsumerRelease(consumer);
    XCTAssertTrue(ctx != NULL, @"Failed to create CGPDFContext for fixture");
    if (!ctx) {
        return nil;
    }

    for (NSUInteger pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        CGPDFContextBeginPage(ctx, NULL);

        NSGraphicsContext *nsContext = [NSGraphicsContext graphicsContextWithCGContext:ctx
                                                                                flipped:NO];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:nsContext];

        for (NSUInteger i = 0; i < items.count; i++) {
            MPPDFTestDrawItem *item = items[i];
            if (item.pageIndex != pageIndex) {
                continue;
            }

            NSFont *font = [NSFont systemFontOfSize:item.fontSize];
            NSDictionary *attrs = @{NSFontAttributeName: font};
            NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:item.text
                                                                              attributes:attrs];
            NSPoint drawPoint = [drawPoints[i] pointValue];
            [attrString drawAtPoint:drawPoint];
        }

        [NSGraphicsContext restoreGraphicsState];
        CGPDFContextEndPage(ctx);
    }

    CGPDFContextClose(ctx);
    CGContextRelease(ctx);

    PDFDocument *document = [[PDFDocument alloc] initWithURL:tempURL];
    XCTAssertNotNil(document, @"Fixture PDFDocument failed to load from %@", tempURL);
    XCTAssertEqual(document.pageCount, pageCount,
                  @"Fixture should have one page per requested pageIndex");

    if (outDrawnRects) {
        *outDrawnRects = drawnRects;
    }
    return document;
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
 *
 * FAILS AGAINST THE STUB: the stub always returns 0 and adds no
 * annotations, so `added == 2` and `tocAnnotations.count == 2` both fail
 * immediately.
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
 *
 * FAILS AGAINST THE STUB: `added == 0` (expected 1), so the annotation
 * count assertion fails immediately; the destination-page assertion is
 * never even reached against a correct implementation's wrong answer
 * because the stub produces no annotation to inspect at all.
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
 *
 * FAILS AGAINST THE STUB: `added == 0` (expected 1) and
 * `totalLinkAnnotationsInDocument: == 0` (expected 1), because the stub
 * never adds the one annotation that a correct implementation must
 * produce for the resolvable "Real" link.
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
 * NOTE ON NON-VACUITY: unlike tests 1-3/5/6, this test's expected outcome
 * (0 annotations added) is exactly what the no-op stub already always
 * returns for ANY input -- there is no way for a genuinely correct
 * no-op assertion to fail against a function that is unconditionally a
 * no-op. This test therefore currently PASSES against the stub; it is
 * still valuable as a regression guard once the real engine is
 * implemented (to catch a future bug where empty input spuriously
 * produces annotations), but it does not by itself prove the stub is
 * incomplete. See the final report for this documented, unavoidable
 * exception.
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
 *
 * FAILS AGAINST THE STUB: `added == 0` (expected 1).
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
 *
 * Before the fix, this fixture drew the TOC entry at 12pt but the
 * preceding prose at 14pt, so a CORRECT implementation would have
 * legitimately resolved to the (14pt > 12pt) prose on page 1 -- the
 * opposite of what the test asserted. That contradicted the algorithm and
 * has been corrected here.
 *
 * FAILS AGAINST THE STUB: `added == 0` (expected 1); a correct
 * implementation's destination-page assertion (page 2) is also something
 * the no-op stub can never produce, since it never adds an annotation to
 * inspect at all.
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
 *
 * FAILS AGAINST THE STUB: `added == 0` (expected 2); the stub adds no
 * annotations at all, so neither the count nor the shared-destination
 * assertions can be satisfied.
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
 * NOTE ON NON-VACUITY (like test 4): this expected outcome (0 annotations)
 * is exactly what the unconditional no-op stub already always returns, so
 * this assertion CANNOT fail against the stub. It is included as a
 * regression guard for the real engine's bodyGroup-empty branch (per the
 * task's documented, unavoidable exception for this class of test), not
 * as stub-refuting coverage.
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

@end
