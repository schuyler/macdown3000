#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <PDFKit/PDFKit.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>
#import "MPDocument.h"
#import "../MacDownCore/MPQuickLookRenderer.h"
#import "MPPDFAnchorInjector.h"

@interface MPDocument (NativePDFTests)
- (BOOL)preparePDFAnchorSession;
- (void)restorePDFAnchorSession;
- (void)document:(NSDocument *)document didPrint:(BOOL)success context:(void *)context;
@end

@interface MPNativePDFDocument : MPDocument
@property (strong) NSError *presentedPDFError;
@end
@implementation MPNativePDFDocument
- (BOOL)presentError:(NSError *)error
{
    self.presentedPDFError = error;
    return YES;
}
@end

// Serve the exact fixture on loopback, with no external dependency or refetch.
@interface MPPDFLocalCSSServer : NSObject
@property (strong) dispatch_source_t source;
@property (strong) NSURL *URL;
@end
@implementation MPPDFLocalCSSServer
- (instancetype)init
{
    self = [super init];
    if (!self) return nil;
    int socketFD = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (socketFD < 0 || bind(socketFD, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(socketFD, 1) != 0) {
        if (socketFD >= 0) close(socketFD);
        return nil;
    }
    socklen_t length = sizeof(address);
    if (getsockname(socketFD, (struct sockaddr *)&address, &length) != 0) {
        close(socketFD);
        return nil;
    }
    self.URL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/style.css", ntohs(address.sin_port)]];
    NSData *CSS = [@"body{font:26px Helvetica;color:red}h2{margin-top:40px}" dataUsingEncoding:NSUTF8StringEncoding];
    self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socketFD, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_event_handler(self.source, ^{
        int client = accept(socketFD, NULL, NULL);
        if (client < 0) return;
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        struct timeval timeout = {1, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        char request[4096];
        if (recv(client, request, sizeof(request), 0) <= 0) { close(client); return; }
        NSString *header = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/css\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)CSS.length];
        NSMutableData *response = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        [response appendData:CSS];
        const uint8_t *bytes = response.bytes;
        NSUInteger sent = 0;
        while (sent < response.length) {
            ssize_t count = send(client, bytes + sent, response.length - sent, 0);
            if (count <= 0) break;
            sent += (NSUInteger)count;
        }
        close(client);
    });
    dispatch_source_set_cancel_handler(self.source, ^{ close(socketFD); });
    dispatch_resume(self.source);
    return self;
}
- (void)dealloc { if (_source) dispatch_source_cancel(_source); }
@end

@interface MPPDFAnchorInjectorTests : XCTestCase
@property (strong) NSMutableArray<NSURL *> *temporaryURLs;
@property (strong) NSMutableArray<WebView *> *previews;
@end
@implementation MPPDFAnchorInjectorTests
- (void)setUp
{
    [super setUp];
    self.temporaryURLs = [NSMutableArray array];
    self.previews = [NSMutableArray array];
}
- (void)tearDown
{
    for (WebView *view in self.previews) [view close];
    for (NSURL *URL in self.temporaryURLs)
        [[NSFileManager defaultManager] removeItemAtURL:URL error:NULL];
    [super tearDown];
}
- (NSURL *)temporaryPDFURL
{
    NSURL *URL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"MPNativePDF-%@.pdf", NSUUID.UUID.UUIDString]]];
    [self.temporaryURLs addObject:URL];
    return URL;
}
- (MPNativePDFDocument *)documentWithBody:(NSString *)body CSS:(NSString *)CSS
{
    MPNativePDFDocument *document = [MPNativePDFDocument new];
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 600, 800)];
    [self.previews addObject:preview];
    [document setValue:preview forKey:@"preview"];
    NSString *HTML = [NSString stringWithFormat:
        @"<html><head><meta name='fixture-ready'><style>body{font:14px Helvetica;width:500px}h2{font:14px Helvetica}%@</style></head><body>%@</body></html>", CSS, body];
    [preview.mainFrame loadHTMLString:HTML baseURL:nil];
    NSString *ready = @"document.readyState==='complete'&&!!document.querySelector('meta[name=fixture-ready]')";
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[preview stringByEvaluatingJavaScriptFromString:ready] isEqualToString:@"true"]
           && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    XCTAssertEqualObjects([preview stringByEvaluatingJavaScriptFromString:ready], @"true");
    NSPrintInfo *info = document.printInfo;
    info.paperSize = NSMakeSize(612, 792);
    info.topMargin = info.bottomMargin = info.leftMargin = info.rightMargin = 36;
    [document setValue:[self temporaryPDFURL] forKey:@"pdfExportURL"];
    [document setValue:[self temporaryPDFURL] forKey:@"pdfExportTemporaryURL"];
    [document setValue:@YES forKey:@"pdfExportPending"];
    return document;
}
- (NSString *)bodyHTML:(MPDocument *)document
{
    WebView *view = [document valueForKey:@"preview"];
    return [view stringByEvaluatingJavaScriptFromString:@"document.body.innerHTML"];
}
- (PDFDocument *)printTemporaryPDF:(MPDocument *)document
{
    NSURL *URL = [document valueForKey:@"pdfExportTemporaryURL"];
    NSError *error = nil;
    NSPrintOperation *operation = [document printOperationWithSettings:
        @{NSPrintJobDisposition:NSPrintSaveJob, NSPrintJobSavingURL:URL} error:&error];
    XCTAssertNotNil(operation, @"%@", error);
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    XCTAssertTrue([operation runOperation]);
    PDFDocument *PDF = [[PDFDocument alloc] initWithURL:URL];
    XCTAssertNotNil(PDF);
    return PDF;
}
- (PDFDocument *)completeExport:(MPNativePDFDocument *)document
{
    NSURL *URL = [document valueForKey:@"pdfExportURL"];
    [document document:document didPrint:YES context:NULL];
    XCTAssertNil(document.presentedPDFError);
    PDFDocument *PDF = [[PDFDocument alloc] initWithURL:URL];
    XCTAssertNotNil(PDF);
    return PDF;
}
- (NSArray<PDFAnnotation *> *)GoToAnnotations:(PDFDocument *)PDF
{
    NSMutableArray *annotations = [NSMutableArray array];
    for (NSUInteger i = 0; i < PDF.pageCount; i++)
        for (PDFAnnotation *annotation in [PDF pageAtIndex:i].annotations)
            if ([annotation.action isKindOfClass:PDFActionGoTo.class]) [annotations addObject:annotation];
    return annotations;
}
- (void)assertNoMarkers:(PDFDocument *)PDF
{
    for (NSUInteger p = 0; p < PDF.pageCount; p++) {
        for (PDFAnnotation *annotation in [PDF pageAtIndex:p].annotations)
            XCTAssertNotEqualObjects(annotation.URL.host, @"macdown-pdf.invalid");
    }
}
- (void)testCollapsedCalloutBodyIsIncludedInPrintedPDF
{
    NSString *body = [[MPQuickLookRenderer new] renderMarkdown:
        @"::: {.callout-note collapse=true}\n## Printable title\n\nHidden callout content 8675309.\n:::"];
    MPNativePDFDocument *document = [self documentWithBody:body CSS:@""];
    WebView *web = [document valueForKey:@"preview"];
    XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:
        @"String(document.querySelector('details').open)"], @"false");
    [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('summary').click()"];
    XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:
        @"String(document.querySelector('details').open)"], @"true");
    [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('summary').click()"];
    PDFDocument *pdf = [self printTemporaryPDF:document];
    XCTAssertTrue([pdf.string containsString:@"Hidden callout content 8675309"]);
    XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:
        @"String(document.querySelector('details').open)"], @"false",
        @"Printing must preserve the preview collapse state");
    [document close];
}

- (void)testCSSReorderingKeepsLinkSourceAndHeadingDestinationAfterReopening
{
    MPNativePDFDocument *document = [self documentWithBody:
        @"<div class='reverse'><h2 id='target'>Target</h2><p><a href='#target'>Target</a></p></div>"
        CSS:@".reverse{display:flex;flex-direction:column-reverse}"];
    NSString *original = [self bodyHTML:document];
    PDFDocument *temporary = [self printTemporaryPDF:document];
    XCTAssertEqual([temporary findString:@"Target" withOptions:0].count, 2u);
    PDFDocument *PDF = [self completeExport:document];
    NSArray<PDFAnnotation *> *annotations = [self GoToAnnotations:PDF];
    XCTAssertEqual(annotations.count, 1u);
    if (annotations.count == 1) {
        PDFAnnotation *source = annotations.firstObject;
        PDFDestination *destination = ((PDFActionGoTo *)source.action).destination;
        // The reverse layout puts the link ABOVE its heading. The old index
        // heuristic annotated the heading and targeted the link instead.
        XCTAssertLessThan(destination.point.y, NSMinY(source.bounds));
        XCTAssertEqual([PDF indexForPage:destination.page], 0u);
    }
    XCTAssertEqualObjects([self bodyHTML:document], original);
    [self assertNoMarkers:PDF];
}
- (void)testLongLinkHasPersistedGoToRectangleOnEveryOccupiedPage
{
    NSString *words = [@"" stringByPaddingToLength:12000 withString:@"Long anchor words " startingAtIndex:0];
    NSString *body = [NSString stringWithFormat:@"<a href='#target'>%@</a><h2 id='target'>Destination</h2>", words];
    MPNativePDFDocument *document = [self documentWithBody:body CSS:@""];
    PDFDocument *original = [self printTemporaryPDF:document];
    NSMutableArray<NSNumber *> *sourceCounts = [NSMutableArray array];
    NSUInteger totalSources = 0;
    for (NSUInteger p = 0; p < original.pageCount; p++) {
        NSUInteger count = 0;
        for (PDFAnnotation *annotation in [original pageAtIndex:p].annotations)
            if ([annotation.type isEqualToString:@"Link"]) count++;
        [sourceCounts addObject:@(count)];
        totalSources += count;
    }
    XCTAssertGreaterThan(totalSources, 1u);
    PDFDocument *PDF = [self completeExport:document];
    XCTAssertGreaterThan(PDF.pageCount, 1u);
    NSArray *annotations = [self GoToAnnotations:PDF];
    XCTAssertEqual(annotations.count, totalSources);
    for (NSUInteger p = 0; p < PDF.pageCount; p++) {
        NSUInteger count = 0;
        for (PDFAnnotation *annotation in [PDF pageAtIndex:p].annotations) {
            if (![annotation.action isKindOfClass:PDFActionGoTo.class]) continue;
            count++;
            PDFDestination *destination = ((PDFActionGoTo *)annotation.action).destination;
            XCTAssertEqual([PDF indexForPage:destination.page], PDF.pageCount - 1);
        }
        XCTAssertEqual(count, sourceCounts[p].unsignedIntegerValue);
    }
    [self assertNoMarkers:PDF];
}
- (void)testRepeatedTextEncodedSlugUnknownTargetAndExternalURL
{
    MPNativePDFDocument *document = [self documentWithBody:
        @"<p>Repeat</p><a href='#tar%20get'>Repeat</a><h2 id='tar get'>Repeat</h2>"
        "<p>Repeat</p><a href='#missing'>Repeat</a><a href='https://example.test/help'>Help</a>"
        CSS:@""];
    [self printTemporaryPDF:document];
    PDFDocument *PDF = [self completeExport:document];
    XCTAssertEqual([self GoToAnnotations:PDF].count, 1u);
    NSUInteger external = 0;
    for (NSUInteger p = 0; p < PDF.pageCount; p++)
        for (PDFAnnotation *annotation in [PDF pageAtIndex:p].annotations)
            if ([annotation.URL.absoluteString isEqualToString:@"https://example.test/help"]) external++;
    XCTAssertEqual(external, 1u);
    [self assertNoMarkers:PDF];
}
- (void)testDuplicateRawHeadingIdsKeepFirstDOMDestinationDespiteReverseLayout
{
    MPNativePDFDocument *document = [self documentWithBody:
        @"<a href='#same'>Go</a><div class='reverse'><h2 id='same'>First</h2><h2 id='same'>Second</h2></div>"
        CSS:@".reverse{display:flex;flex-direction:column-reverse}"];
    [self printTemporaryPDF:document];
    PDFDocument *PDF = [self completeExport:document];
    NSArray *annotations = [self GoToAnnotations:PDF];
    XCTAssertEqual(annotations.count, 1u);
    NSArray<PDFSelection *> *first = [PDF findString:@"First" withOptions:0];
    XCTAssertEqual(first.count, 1u);
    if (annotations.count == 1 && first.count == 1) {
        PDFDestination *destination = ((PDFActionGoTo *)((PDFAnnotation *)annotations.firstObject).action).destination;
        NSRect heading = [first.firstObject boundsForPage:first.firstObject.pages.firstObject];
        XCTAssertEqualWithAccuracy(destination.point.y, NSMaxY(heading), 3.0);
    }
}
- (void)testCancelledPrintRestoresExactDOMAndPreservesExistingDestination
{
    MPNativePDFDocument *document = [self documentWithBody:
        @"<a href='#target' style='color:red'>Go</a><h2 id='target'><strong>Heading</strong></h2>" CSS:@""];
    NSString *original = [self bodyHTML:document];
    NSURL *destination = [document valueForKey:@"pdfExportURL"];
    NSData *existing = [@"existing file" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([existing writeToURL:destination atomically:YES]);
    XCTAssertTrue([document preparePDFAnchorSession]);
    XCTAssertNotEqualObjects([self bodyHTML:document], original);
    [document document:document didPrint:NO context:NULL];
    XCTAssertEqualObjects([self bodyHTML:document], original);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:destination], existing);
    XCTAssertNil([document valueForKey:@"pdfExportAnchorSession"]);
    XCTAssertNil([document valueForKey:@"pdfExportTemporaryURL"]);
    XCTAssertFalse([[document valueForKey:@"pdfExportPending"] boolValue]);
}
- (void)testPublishFailureCleansTemporaryPDFAndRestoresDOM
{
    MPNativePDFDocument *document = [self documentWithBody:@"<a href='#target'>Go</a><h2 id='target'>Heading</h2>" CSS:@""];
    NSString *original = [self bodyHTML:document];
    NSURL *temporary = [document valueForKey:@"pdfExportTemporaryURL"];
    [self printTemporaryPDF:document];
    [document setValue:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] forKey:@"pdfExportURL"];
    [document document:document didPrint:YES context:NULL];
    XCTAssertNotNil(document.presentedPDFError);
    XCTAssertEqualObjects([self bodyHTML:document], original);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:temporary.path]);
}
- (PDFDocument *)metadataPDF:(MPDocument *)document
{
    XCTAssertTrue([document preparePDFAnchorSession]);
    NSURL *URL = [self temporaryPDFURL];
    NSPrintInfo *info = [document.printInfo copy];
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = URL;
    WebView *view = [document valueForKey:@"preview"];
    NSPrintOperation *operation = [view.mainFrame.frameView printOperationWithPrintInfo:info];
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    XCTAssertTrue([operation runOperation]);
    return [[PDFDocument alloc] initWithURL:URL];
}
- (void)testNativeResolverIgnoresMalformedMetadataWithoutPublishingMarkers
{
    MPNativePDFDocument *document = [self documentWithBody:@"<a href='#target'>Go</a><h2 id='target'>Heading</h2>" CSS:@""];
    PDFDocument *original = [self printTemporaryPDF:document];
    PDFDocument *metadata = [self metadataPDF:document];
    NSDictionary *session = [document valueForKey:@"pdfExportAnchorSession"];
    PDFPage *page = [metadata pageAtIndex:0];
    for (NSString *suffix in @[@"link/999", @"link/0evil", @"heading/184467440737095516160", @"other/0"]) {
        PDFAnnotation *annotation = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(10, 10, 5, 5)
            forType:PDFAnnotationSubtypeLink withProperties:nil];
        annotation.URL = [NSURL URLWithString:[session[@"prefix"] stringByAppendingString:suffix]];
        [page addAnnotation:annotation];
    }
    NSError *error = nil;
    XCTAssertEqual([MPPDFAnchorInjector resolveNativeLinksInDocument:original metadataDocument:metadata
        markerPrefix:session[@"prefix"] linkTargets:session[@"links"] headingSlugs:session[@"headings"] error:&error], 1u);
    XCTAssertNil(error);
    [self assertNoMarkers:original];
    [document document:document didPrint:NO context:NULL];
}
- (void)testGeometryMismatchRejectsTransferBeforeChangingOriginalAnnotations
{
    MPNativePDFDocument *document = [self documentWithBody:@"<a href='#target'>Go</a><h2 id='target'>Heading</h2>" CSS:@""];
    PDFDocument *original = [self printTemporaryPDF:document];
    PDFDocument *metadata = [self metadataPDF:document];
    NSDictionary *session = [document valueForKey:@"pdfExportAnchorSession"];
    for (PDFAnnotation *annotation in [metadata pageAtIndex:0].annotations)
        if ([annotation.URL.absoluteString containsString:@"/link/"])
            annotation.bounds = NSOffsetRect(annotation.bounds, 10, 0);
    NSError *error = nil;
    XCTAssertEqual([MPPDFAnchorInjector resolveNativeLinksInDocument:original metadataDocument:metadata
        markerPrefix:session[@"prefix"] linkTargets:session[@"links"] headingSlugs:session[@"headings"] error:&error], 0u);
    XCTAssertNotNil(error);
    XCTAssertEqual([self GoToAnnotations:original].count, 0u);
    [document document:document didPrint:NO context:NULL];
}
- (void)testOverlappingSourceRectanglesAreRejectedRatherThanMatchedByOrder
{
    MPNativePDFDocument *document = [self documentWithBody:@"<a href='#target'>Go</a><h2 id='target'>Heading</h2>" CSS:@""];
    PDFDocument *original = [self printTemporaryPDF:document];
    PDFDocument *metadata = [self metadataPDF:document];
    NSDictionary *session = [document valueForKey:@"pdfExportAnchorSession"];
    PDFPage *page = [original pageAtIndex:0];
    PDFAnnotation *source = page.annotations.firstObject;
    PDFAnnotation *duplicate = [[PDFAnnotation alloc] initWithBounds:source.bounds forType:PDFAnnotationSubtypeLink withProperties:nil];
    [page addAnnotation:duplicate];
    NSError *error = nil;
    XCTAssertEqual([MPPDFAnchorInjector resolveNativeLinksInDocument:original metadataDocument:metadata
        markerPrefix:session[@"prefix"] linkTargets:session[@"links"] headingSlugs:session[@"headings"] error:&error], 0u);
    XCTAssertNotNil(error);
    XCTAssertEqual([self GoToAnnotations:original].count, 0u);
    [document document:document didPrint:NO context:NULL];
}
- (void)testAbsentDocumentAndEmptyPrefixAreSafeNoOps
{
    XCTAssertEqual([MPPDFAnchorInjector resolveNativeLinksInDocument:nil metadataDocument:nil markerPrefix:@"prefix"
        linkTargets:@[] headingSlugs:@[] error:NULL], 0u);
    XCTAssertEqual([MPPDFAnchorInjector resolveNativeLinksInDocument:[PDFDocument new] metadataDocument:[PDFDocument new] markerPrefix:@""
        linkTargets:@[] headingSlugs:@[] error:NULL], 0u);
}
- (void)assertChangedPreviewRejectsExport:(NSString *)change
{
    MPNativePDFDocument *document = [self documentWithBody:@"<a href='#target'>Go</a><h2 id='target'>Heading</h2>" CSS:@""];
    NSURL *destination = [document valueForKey:@"pdfExportURL"];
    NSData *existing = [@"existing file" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([existing writeToURL:destination atomically:YES]);
    [self printTemporaryPDF:document];
    if ([change isEqualToString:@"generation"])
        [document setValue:@([[document valueForKey:@"previewRenderGeneration"] unsignedIntegerValue] + 1) forKey:@"previewRenderGeneration"];
    else if ([change isEqualToString:@"closed"])
        [document setValue:@YES forKey:@"documentClosed"];
    else if ([change isEqualToString:@"CSSOM"])
        [[document valueForKey:@"preview"] stringByEvaluatingJavaScriptFromString:@"document.styleSheets[0].insertRule('h2{margin-top:100px}',0)"];
    else
        [[document valueForKey:@"preview"] stringByEvaluatingJavaScriptFromString:@"document.body.appendChild(document.createElement('hr'))"];
    [document document:document didPrint:YES context:NULL];
    XCTAssertNotNil(document.presentedPDFError);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:destination], existing);
    XCTAssertNil([document valueForKey:@"pdfExportTemporaryURL"]);
    XCTAssertNil([document valueForKey:@"pdfExportMetadataURL"]);
    XCTAssertNil([document valueForKey:@"pdfExportAnchorSession"]);
}
- (void)testRenderGenerationChangeRejectsExport { [self assertChangedPreviewRejectsExport:@"generation"]; }
- (void)testDirectDOMChangeRejectsExport { [self assertChangedPreviewRejectsExport:@"DOM"]; }
- (void)testCSSOMChangeRejectsExport { [self assertChangedPreviewRejectsExport:@"CSSOM"]; }
- (void)testClosedDocumentRejectsExport { [self assertChangedPreviewRejectsExport:@"closed"]; }
- (NSData *)pixelsForPage:(PDFPage *)page
{
    NSImage *image = [page thumbnailOfSize:NSMakeSize(500, 650) forBox:kPDFDisplayBoxMediaBox];
    NSBitmapImageRep *pixels = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    return [pixels representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
- (void)assertOriginalPixelsWithCSS:(NSString *)CSS
{
    MPNativePDFDocument *document = [self documentWithBody:
        @"<a href='#target'>Go</a><h2 id='target'><strong>Heading</strong></h2><p>Following paragraph</p>"
        CSS:CSS];
    WebView *view = [document valueForKey:@"preview"];
    NSURL *destination = [document valueForKey:@"pdfExportURL"];
    [document setValue:nil forKey:@"pdfExportURL"];
    NSURL *baselineURL = [self temporaryPDFURL];
    NSError *error = nil;
    NSPrintOperation *baselineOperation = [document printOperationWithSettings:
        @{NSPrintJobDisposition:NSPrintSaveJob, NSPrintJobSavingURL:baselineURL} error:&error];
    baselineOperation.showsPrintPanel = NO;
    baselineOperation.showsProgressPanel = NO;
    XCTAssertTrue([baselineOperation runOperation]);
    PDFDocument *baseline = [[PDFDocument alloc] initWithURL:baselineURL];
    [document setValue:destination forKey:@"pdfExportURL"];
    [self printTemporaryPDF:document];
    PDFDocument *result = [self completeExport:document];
    XCTAssertEqual(result.pageCount, baseline.pageCount);
    XCTAssertEqual([self GoToAnnotations:result].count, 1u);
    XCTAssertNotNil(view);
    if (result.pageCount == baseline.pageCount)
        for (NSUInteger p = 0; p < result.pageCount; p++)
            XCTAssertEqualObjects([self pixelsForPage:[result pageAtIndex:p]], [self pixelsForPage:[baseline pageAtIndex:p]]);
}
- (void)testPrintSelectorsAndFirstChildStylesKeepIdenticalRenderedPixels
{
    [self assertOriginalPixelsWithCSS:@"a[href^='#']{color:green}h2 strong{color:blue}h2 strong:first-child{color:red}@media print{h2 strong:first-child{font-size:24px}}"];
}
- (void)testStructuralSiblingSelectorKeepsOriginalPixels
{
    [self assertOriginalPixelsWithCSS:@"h2:has(a)+p{font-size:40px;color:red}"];
}
- (void)testHrefGeneratedContentKeepsOriginalPixels
{
    [self assertOriginalPixelsWithCSS:@"a::after{content:attr(href)}"];
}
- (void)testFluidLinkWidthAndPrintMediaKeepOriginalPixels
{
    [self assertOriginalPixelsWithCSS:@"body{width:auto}a[href^='#']{display:block;width:75%;font-size:26px;border:2px solid green}@media print{h2{margin-top:30px}}"];
}
- (void)testNoAnchorsExportsOriginalWithActuallyInaccessibleCrossOriginCSS
{
    __attribute__((objc_precise_lifetime)) MPPDFLocalCSSServer *server = [MPPDFLocalCSSServer new];
    XCTAssertNotNil(server);
    MPNativePDFDocument *document = [self documentWithBody:@"<h2 id='target'>Heading</h2>" CSS:@""];
    WebView *view = [document valueForKey:@"preview"];
    NSString *HTML = [NSString stringWithFormat:@"<html><head><meta name='cross-origin-css-fixture'><link rel='stylesheet' href='%@'></head><body><h2 id='target'>Heading</h2><a href='#'>Empty fragment</a></body></html>", server.URL.absoluteString];
    [view.mainFrame loadHTMLString:HTML baseURL:[NSURL URLWithString:@"http://127.0.0.1:1/document.md"]];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[view stringByEvaluatingJavaScriptFromString:@"document.readyState==='complete'&&!!document.querySelector('meta[name=cross-origin-css-fixture]')&&document.styleSheets.length===1"] isEqualToString:@"true"] && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    XCTAssertEqualObjects([view stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.body).fontSize"], @"26px");
    XCTAssertEqualObjects([view stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.body).color"], @"rgb(255, 0, 0)");
    XCTAssertEqualObjects([view stringByEvaluatingJavaScriptFromString:@"(function(){try{document.styleSheets[0].cssRules;return 'accessible'}catch(e){return e.name}})()"], @"SecurityError");
    PDFDocument *original = [self printTemporaryPDF:document];
    PDFDocument *published = [self completeExport:document];
    XCTAssertEqual(published.pageCount, original.pageCount);
    XCTAssertEqualObjects([self pixelsForPage:[published pageAtIndex:0]], [self pixelsForPage:[original pageAtIndex:0]]);
    XCTAssertEqual([published findString:@"Heading" withOptions:0].count, 1u);
    XCTAssertEqual([self GoToAnnotations:published].count, 0u);
    [self assertNoMarkers:published];
    XCTAssertNil([document valueForKey:@"pdfExportAnchorSession"]);
}
@end
