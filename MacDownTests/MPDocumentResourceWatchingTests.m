//
//  MPDocumentResourceWatchingTests.m
//  MacDownTests
//
//  Tests for what a document does when it begins watching the local files its
//  preview references: the cache-busting stamps reach the page being loaded,
//  and beginning to watch is not treated as a change to the files.
//

#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "MPDocument.h"
#import "MPDocumentWindowTestSupport.h"
#import "MPEditorView.h"
#import "MPPreferences.h"
#import "MPRenderer.h"
#import "MPResourceWatcherSet.h"
#import "MPUtilities.h"


@interface MPDocument (ResourceWatchingTesting)
@property BOOL isPreviewReady;
@property (weak) WebView *preview;
@property (weak) MPEditorView *editor;
@property (strong) MPResourceWatcherSet *resourceWatcherSet;
- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html;
- (void)resourceWatcherSet:(MPResourceWatcherSet *)set
     didDetectChangeAtPath:(NSString *)path;
- (IBAction)reloadPreview:(id)sender;
@end


// Counts the renders, the renders that begin while another render is still
// being handled, and the changes the resource watchers report.
@interface MPResourceWatchingSpyDocument : MPDocument
@property NSUInteger renderCount;
@property NSUInteger renderDepth;
@property NSUInteger nestedRenderCount;
@property NSUInteger reportedChangeCount;
@end

@implementation MPResourceWatchingSpyDocument

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    self.renderCount++;
    if (self.renderDepth > 0)
        self.nestedRenderCount++;
    self.renderDepth++;
    [super renderer:renderer didProduceHTMLOutput:html];
    self.renderDepth--;
}

- (void)resourceWatcherSet:(MPResourceWatcherSet *)set
     didDetectChangeAtPath:(NSString *)path
{
    self.reportedChangeCount++;
    [super resourceWatcherSet:set didDetectChangeAtPath:path];
}

@end


@interface MPDocumentResourceWatchingTests : XCTestCase
@property (copy) NSString *directory;
@end


@implementation MPDocumentResourceWatchingTests

- (void)setUp
{
    [super setUp];
    self.directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.directory
                              withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.directory
                                               error:NULL];
    [super tearDown];
}

#pragma mark - Helpers

// A PNG whose width tells one version of an image file from another.
- (void)writeImageOfWidth:(NSInteger)width named:(NSString *)name
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:1
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0
                    bitsPerPixel:0];
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG
                                     properties:@{}];
    NSString *path = [self.directory stringByAppendingPathComponent:name];
    XCTAssertTrue([data writeToFile:path atomically:NO]);
}

// Writes a document that references imageCount images in its own directory.
- (NSURL *)writeDocumentWithImages:(NSUInteger)imageCount
{
    NSMutableString *markdown = [NSMutableString stringWithString:@"# Doc\n"];
    for (NSUInteger i = 0; i < imageCount; i++)
    {
        NSString *name = [NSString stringWithFormat:@"image-%lu.png",
                          (unsigned long)i];
        [self writeImageOfWidth:1 named:name];
        [markdown appendFormat:@"\n![](%@)\n", name];
    }
    NSString *path = [self.directory stringByAppendingPathComponent:@"doc.md"];
    NSURL *url = [NSURL fileURLWithPath:path];
    XCTAssertTrue([markdown writeToURL:url atomically:NO
                              encoding:NSUTF8StringEncoding error:NULL]);
    return url;
}

- (NSString *)evaluate:(NSString *)script in:(MPDocument *)document
{
    return [document.preview stringByEvaluatingJavaScriptFromString:script];
}

// Opens the document in a loaded window and waits until its preview shows
// imageCount fully loaded images.
- (id)openDocumentOfClass:(Class)documentClass atURL:(NSURL *)url
                   images:(NSUInteger)imageCount
{
    NSError *error = nil;
    MPDocument *document = [[documentClass alloc]
        initWithContentsOfURL:url ofType:@"net.daringfireball.markdown"
                        error:&error];
    XCTAssertNotNil(document, @"%@", error);
    XCTAssertNotNil(MPLoadDocumentWindow(document));

    NSString *script = [NSString stringWithFormat:
        @"document.images.length === %lu && Array.prototype.every.call("
        @"document.images, function (i) { return i.complete; }) ? 'yes' : ''",
        (unsigned long)imageCount];
    BOOL loaded = MPRunLoopUntil(20.0, ^BOOL {
        return document.isPreviewReady && !document.preview.loading
            && [self evaluate:script in:document].length > 0;
    });
    XCTAssertTrue(loaded, @"The preview must finish loading the document");
    return document;
}

// The path under which the document watches the named file.
- (NSString *)watchedPathNamed:(NSString *)name in:(MPDocument *)document
{
    for (NSString *path in document.resourceWatcherSet.watchedPaths)
    {
        if ([path.lastPathComponent isEqualToString:name])
            return path;
    }
    return nil;
}

- (NSString *)imageSourceIn:(MPDocument *)document
{
    return [self evaluate:@"document.images[0].getAttribute('src')"
                       in:document];
}

// Types a word at the end of the document and waits for it in the preview.
- (void)appendWord:(NSString *)word to:(MPDocument *)document
{
    NSTextView *editor = document.editor;
    [editor insertText:[NSString stringWithFormat:@"\n%@\n", word]
      replacementRange:NSMakeRange(editor.string.length, 0)];
    NSString *script = [NSString stringWithFormat:
        @"document.body.textContent.indexOf('%@') >= 0 ? 'yes' : ''", word];
    BOOL rendered = MPRunLoopUntil(20.0, ^BOOL {
        return !document.preview.loading
            && [self evaluate:script in:document].length > 0;
    });
    XCTAssertTrue(rendered, @"The edit must reach the preview");
}

#pragma mark - Tests

// The page a document loads must already carry the stamps of the files it
// watches. Fails when the stamps are recorded only after the page's HTML has
// been generated.
- (void)testFirstLoadedPageCarriesStampsForWatchedResources
{
    NSURL *url = [self writeDocumentWithImages:1];
    MPDocument *document = [self openDocumentOfClass:[MPDocument class]
                                               atURL:url images:1];

    NSString *source = [self evaluate:@"document.images[0].getAttribute('src')"
                                   in:document];
    XCTAssertTrue([source hasPrefix:@"image-0.png?t="],
                  @"The image URL in the first loaded page must be stamped; "
                   "got %@", source);
    [document close];
}

// An image replaced while its document was closed must show its current
// contents when the document is opened again in the same session (#349).
- (void)testReopenedDocumentShowsImageChangedWhileClosed
{
    NSURL *url = [self writeDocumentWithImages:1];
    NSString *width = @"String(document.images[0].naturalWidth)";

    MPDocument *first = [self openDocumentOfClass:[MPDocument class]
                                            atURL:url images:1];
    XCTAssertEqualObjects([self evaluate:width in:first], @"1",
                          @"Precondition: the preview shows the 1px image");
    [first close];

    [self writeImageOfWidth:2 named:@"image-0.png"];
    // Stamps have a resolution of one second: reopen in a later second than
    // the one the first page was stamped in.
    time_t closedAt = time(NULL);
    MPRunLoopUntil(3.0, ^BOOL { return time(NULL) > closedAt; });

    MPDocument *second = [self openDocumentOfClass:[MPDocument class]
                                             atURL:url images:1];
    XCTAssertEqualObjects([self evaluate:width in:second], @"2",
                          @"The reopened document must show the image as it "
                           "is on disk, not the copy WebKit cached earlier");
    [second close];
}

// The first edit after opening must update the preview in place. Fails when
// the stamps first appear in the second page, changing the stylesheet URLs in
// <head> and forcing a full reload.
- (void)testFirstEditAfterOpenUpdatesPreviewInPlace
{
    NSURL *url = [self writeDocumentWithImages:1];
    MPDocument *document = [self openDocumentOfClass:[MPDocument class]
                                               atURL:url images:1];

    // A full reload replaces the window object; an in-place update keeps it.
    [self evaluate:@"window.mpLoadedPageMarker = 'kept'" in:document];
    [self appendWord:@"edited" to:document];

    XCTAssertEqualObjects(
        [self evaluate:@"window.mpLoadedPageMarker || 'reloaded'" in:document],
        @"kept",
        @"The first edit after opening must not reload the whole preview");
    [document updateChangeCount:NSChangeCleared];
    [document close];
}

// Beginning to watch a document's files is not a change to them: opening a
// document must not report changes, and must not start a render from inside
// another one for each file.
- (void)testOpeningDocumentWatchesFilesWithoutReportingChanges
{
    NSUInteger imageCount = 8;
    NSURL *url = [self writeDocumentWithImages:imageCount];
    MPResourceWatchingSpyDocument *document =
        [self openDocumentOfClass:[MPResourceWatchingSpyDocument class]
                            atURL:url images:imageCount];

    NSMutableSet<NSString *> *watchedNames = [NSMutableSet set];
    for (NSString *path in document.resourceWatcherSet.watchedPaths)
        [watchedNames addObject:path.lastPathComponent];
    for (NSUInteger i = 0; i < imageCount; i++)
    {
        NSString *name = [NSString stringWithFormat:@"image-%lu.png",
                          (unsigned long)i];
        XCTAssertTrue([watchedNames containsObject:name],
                      @"%@ must be watched", name);
    }

    XCTAssertEqual(document.reportedChangeCount, 0u,
                   @"Opening a document must not report its files as changed");
    XCTAssertEqual(document.nestedRenderCount, 0u,
                   @"Opening a document must not render from inside a render");
    // Opening renders the content, and usually an empty page first when a
    // preferences notification arrives while the window loads.
    XCTAssertLessThan(document.renderCount, imageCount,
                      @"Opening a document must not render once per file");
    [document close];
}

// Each reported change must give the file a URL the page has not used for it,
// or the WebView keeps showing its cached copy. Fails when two changes in the
// same second get the same stamp.
- (void)testEachReportedChangeGivesTheFileANewURL
{
    NSURL *url = [self writeDocumentWithImages:1];
    MPDocument *document = [self openDocumentOfClass:[MPDocument class]
                                               atURL:url images:1];
    NSString *path = [self watchedPathNamed:@"image-0.png" in:document];
    XCTAssertNotNil(path, @"Precondition: the image is watched");

    // A change re-renders in place and synchronously, so three reports in a
    // row span at most one second boundary.
    NSMutableArray<NSString *> *sources =
        [NSMutableArray arrayWithObject:[self imageSourceIn:document]];
    for (NSUInteger i = 0; i < 3; i++)
    {
        [document resourceWatcherSet:document.resourceWatcherSet
               didDetectChangeAtPath:path];
        [sources addObject:[self imageSourceIn:document]];
    }

    XCTAssertEqual([NSSet setWithArray:sources].count, sources.count,
                   @"Every change must produce a new image URL; got %@",
                   sources);
    [document close];
}

// A file that is watched again after its watcher was stopped may have changed
// in between, so it must get a new URL, not one the page used before. Fails
// when watching again records the current time while the file's stamp is
// ahead of the clock, or records nothing.
- (void)testFileWatchedAgainGetsANewURLAndShowsItsNewContents
{
    NSURL *url = [self writeDocumentWithImages:1];
    MPDocument *document = [self openDocumentOfClass:[MPDocument class]
                                               atURL:url images:1];
    NSString *path = [self watchedPathNamed:@"image-0.png" in:document];
    XCTAssertNotNil(path, @"Precondition: the image is watched");

    // Run the file's stamp ahead of the clock.
    NSMutableArray<NSString *> *sources =
        [NSMutableArray arrayWithObject:[self imageSourceIn:document]];
    for (NSUInteger i = 0; i < 3; i++)
    {
        [document resourceWatcherSet:document.resourceWatcherSet
               didDetectChangeAtPath:path];
        [sources addObject:[self imageSourceIn:document]];
    }

    [document.resourceWatcherSet stopAll];
    [self writeImageOfWidth:2 named:@"image-0.png"];
    [self appendWord:@"edited" to:document];
    BOOL imageLoaded = MPRunLoopUntil(20.0, ^BOOL {
        return [[self evaluate:@"document.images[0].complete ? 'yes' : ''"
                            in:document] length] > 0;
    });
    XCTAssertTrue(imageLoaded);

    XCTAssertFalse([sources containsObject:[self imageSourceIn:document]],
                   @"A file watched again must get a URL not used before; "
                    "got %@ after %@", [self imageSourceIn:document], sources);
    XCTAssertEqualObjects(
        [self evaluate:@"String(document.images[0].naturalWidth)" in:document],
        @"2", @"The preview must show the image as it is on disk");
    [document updateChangeCount:NSChangeCleared];
    [document close];
}

// An explicit preview reload must give the style CSS a URL the page has not
// used, even when earlier changes ran its stamp ahead of the clock (#318).
// Fails when the reload records the current time.
- (void)testPreviewReloadGivesStyleANewURLAfterReportedChanges
{
    NSString *styleName = [MPPreferences sharedInstance].htmlStyleName;
    NSString *stylePath = MPStylePathForName(styleName);
    if (!stylePath)
        XCTSkip(@"The active style does not resolve to a file");

    NSURL *url = [self writeDocumentWithImages:1];
    MPDocument *document = [self openDocumentOfClass:[MPDocument class]
                                               atURL:url images:1];
    NSString *script = [NSString stringWithFormat:
        @"(function () {"
        @"var links = document.querySelectorAll('link');"
        @"for (var i = 0; i < links.length; i++) {"
        @"  var href = links[i].getAttribute('href');"
        @"  if (href.indexOf('%@') >= 0) return href;"
        @"}"
        @"return ''; })()", stylePath.lastPathComponent];
    NSString *(^styleLink)(void) = ^NSString * {
        return [self evaluate:script in:document];
    };
    NSMutableArray<NSString *> *links =
        [NSMutableArray arrayWithObject:styleLink()];
    XCTAssertGreaterThan(links.lastObject.length, 0u,
                         @"Precondition: the page links the active style");

    // Each step changes <head>, so each one is a full load: wait for the
    // loaded page to carry a link other than the previous one.
    BOOL (^waitForNewLink)(void) = ^BOOL {
        NSString *previous = links.lastObject;
        BOOL changed = MPRunLoopUntil(20.0, ^BOOL {
            NSString *link = styleLink();
            return !document.preview.loading && link.length > 0
                && ![link isEqualToString:previous];
        });
        [links addObject:styleLink()];
        return changed;
    };
    for (NSUInteger i = 0; i < 4; i++)
    {
        [document resourceWatcherSet:document.resourceWatcherSet
               didDetectChangeAtPath:stylePath];
        XCTAssertTrue(waitForNewLink(), @"A change must change the link");
    }
    [document reloadPreview:nil];
    XCTAssertTrue(waitForNewLink(), @"A reload must change the link");

    XCTAssertEqual([NSSet setWithArray:links].count, links.count,
                   @"Every step must give the style a new URL; got %@", links);
    [document close];
}

@end
