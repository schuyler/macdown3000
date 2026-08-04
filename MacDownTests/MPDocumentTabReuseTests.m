#import <XCTest/XCTest.h>
#import "MPDocument.h"

@interface MPDocument (TabReuseTesting)
+ (MPDocument *)openDocumentForFileURL:(NSURL *)url;
+ (NSError *)sidebarOpenErrorForError:(NSError *)error URL:(NSURL *)url;
@end

@interface MPDocumentTabReuseTests : XCTestCase
@property (strong) NSURL *root;
@end

@implementation MPDocumentTabReuseTests

- (void)setUp
{
    [super setUp];
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                 URLByAppendingPathComponent:unique isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.root
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
    self.root = nil;
    [super tearDown];
}

- (NSURL *)writeMarkdownNamed:(NSString *)name
{
    NSURL *url = [self.root URLByAppendingPathComponent:name];
    [@"# hello" writeToURL:url atomically:YES
                  encoding:NSUTF8StringEncoding error:NULL];
    return url;
}

/// Opens a document without showing a window, or fails the test.
- (MPDocument *)openDocumentAtURL:(NSURL *)url
{
    XCTestExpectation *opened = [self expectationWithDescription:@"opened"];
    __block MPDocument *document = nil;
    [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:url display:NO
                    completionHandler:^(NSDocument *doc, BOOL wasOpen,
                                        NSError *error) {
        XCTAssertNil(error, @"could not open the fixture document");
        if ([doc isKindOfClass:[MPDocument class]])
            document = (MPDocument *)doc;
        [opened fulfill];
    }];
    [self waitForExpectations:@[opened] timeout:10.0];
    return document;
}

#pragma mark - Lookup

- (void)testReturnsNilWhenNoDocumentIsOpenForURL
{
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/definitely-not-open-xyz.md"];
    XCTAssertNil([MPDocument openDocumentForFileURL:url]);
}

// The branch that makes activating a sidebar file reuse an existing tab rather
// than open the same file twice.
- (void)testReturnsTheOpenDocumentForItsURL
{
    NSURL *url = [self writeMarkdownNamed:@"reuse.md"];
    MPDocument *document = [self openDocumentAtURL:url];
    XCTAssertNotNil(document);

    @try
    {
        MPDocument *found = [MPDocument openDocumentForFileURL:url];
        XCTAssertNotNil(found, @"an open document must be found by its URL");
        XCTAssertEqual(found, document, @"and it must be the same instance");
    }
    @finally
    {
        [document close];
    }
}

- (void)testStopsFindingTheDocumentOnceItIsClosed
{
    NSURL *url = [self writeMarkdownNamed:@"closed.md"];
    MPDocument *document = [self openDocumentAtURL:url];
    XCTAssertNotNil(document);
    XCTAssertNotNil([MPDocument openDocumentForFileURL:url]);

    [document close];
    XCTAssertNil([MPDocument openDocumentForFileURL:url],
                 @"a closed document must not be reused");
}

- (void)testDoesNotConfuseTwoFilesWithTheSameName
{
    NSURL *first = [self writeMarkdownNamed:@"same.md"];
    NSURL *otherDir = [self.root URLByAppendingPathComponent:@"sub"
                                                 isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:otherDir
        withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *second = [otherDir URLByAppendingPathComponent:@"same.md"];
    [@"# other" writeToURL:second atomically:YES
                  encoding:NSUTF8StringEncoding error:NULL];

    MPDocument *document = [self openDocumentAtURL:first];
    XCTAssertNotNil(document);
    @try
    {
        XCTAssertEqual([MPDocument openDocumentForFileURL:first], document);
        XCTAssertNil([MPDocument openDocumentForFileURL:second],
                     @"a same-named file in another folder is a different doc");
    }
    @finally
    {
        [document close];
    }
}

#pragma mark - Failed open reporting

// Activating a sidebar file opens with display:NO, which opts out of
// NSDocumentController's automatic error alert — these cover what replaces it.

- (void)testFailedOpenWithAnErrorIsReported
{
    NSError *underlying = [NSError errorWithDomain:NSCocoaErrorDomain
                                              code:NSFileReadNoSuchFileError
                                          userInfo:nil];
    NSURL *url = [self.root URLByAppendingPathComponent:@"x.md"];
    NSError *shown = [MPDocument sidebarOpenErrorForError:underlying URL:url];
    XCTAssertEqual(shown, underlying, @"the real error should be surfaced as-is");
}

- (void)testFailedOpenWithNoErrorStillReportsSomething
{
    NSURL *url = [self.root URLByAppendingPathComponent:@"gone.md"];
    NSError *shown = [MPDocument sidebarOpenErrorForError:nil URL:url];
    XCTAssertNotNil(shown, @"a failed open must never be silent");
    XCTAssertTrue([shown.localizedDescription containsString:@"gone.md"],
                  @"the message should name the file, got: %@",
                  shown.localizedDescription);
    XCTAssertEqualObjects(shown.userInfo[NSURLErrorKey], url);
}

- (void)testUserCancellationIsNotReported
{
    NSError *cancelled = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSUserCancelledError
                                         userInfo:nil];
    XCTAssertNil([MPDocument sidebarOpenErrorForError:cancelled URL:self.root],
                 @"cancelling is not a failure worth an alert");
}

@end
