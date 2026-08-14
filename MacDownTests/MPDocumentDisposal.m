//
//  MPDocumentDisposal.m
//  MacDownTests
//
//  Tests build real MPDocument instances and mostly never close them. An unclosed
//  document keeps its file watcher, its pending performSelector: requests, and
//  NSDocument's autosaving alive, so AppKit and MacDown go on servicing it during
//  whatever test happens to run later. When one of those services needs UI it enters
//  a modal session, and a test host with no window never leaves one — the whole
//  suite stops there.
//
//  Closing each document when its test ends is what -close exists for: it cancels
//  the pending performs, stops file watching, and lets NSDocument retire autosaving.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "MPDocument.h"


#pragma mark - Tracking

// Weak, so a document the test already released simply drops out.
static NSHashTable *MPDocumentsCreatedDuringTest(void)
{
    static NSHashTable *documents;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        documents = [NSHashTable weakObjectsHashTable];
    });
    return documents;
}


@implementation MPDocument (MPDocumentDisposal)

// MPDocument implements -init itself, so the exchange stays on MPDocument instead
// of reaching NSDocument and tracking every document class in the process.
+ (void)load
{
    Method original = class_getInstanceMethod(self, @selector(init));
    Method tracking = class_getInstanceMethod(self, @selector(mp_initTrackingCreation));
    method_exchangeImplementations(original, tracking);
}

- (instancetype)mp_initTrackingCreation
{
    // The implementations are exchanged, so this call reaches the original -init.
    MPDocument *document = [self mp_initTrackingCreation];
    if (document)
        [MPDocumentsCreatedDuringTest() addObject:document];
    return document;
}

@end


#pragma mark - Disposal

@interface MPDocumentDisposal : NSObject <XCTestObservation>
@end

@implementation MPDocumentDisposal

+ (void)load
{
    [[XCTestObservationCenter sharedTestObservationCenter]
        addTestObserver:[[self alloc] init]];
}

- (void)testCaseDidFinish:(XCTestCase *)testCase
{
    NSHashTable *documents = MPDocumentsCreatedDuringTest();
    // -close guards on needsToUnregister, so a test that closed its own document
    // is unaffected by this one.
    for (MPDocument *document in documents.allObjects)
        [document close];
    [documents removeAllObjects];
}

@end


#pragma mark - Tests

// Records the close the disposal is supposed to perform.
@interface MPDisposalSpyDocument : MPDocument
@property (nonatomic) BOOL wasClosed;
@end

@implementation MPDisposalSpyDocument
- (void)close { self.wasClosed = YES; [super close]; }
@end


// The disposal only works if every way a test builds a document is seen, so both
// construction forms used in the suite are pinned here.
@interface MPDocumentDisposalTests : XCTestCase
@end

@implementation MPDocumentDisposalTests

// The mechanism itself: a document created during a test is closed when that test
// ends. Fails if the swizzle stops recording or the observation stops closing.
- (void)testDisposalClosesADocumentTheTestCreated
{
    MPDisposalSpyDocument *document = [[MPDisposalSpyDocument alloc] init];
    XCTAssertFalse(document.wasClosed,
                   @"Precondition: nothing has closed the document yet");

    // Driven directly, because this test cannot observe its own teardown.
    [[[MPDocumentDisposal alloc] init] testCaseDidFinish:self];

    XCTAssertTrue(document.wasClosed,
                  @"Disposal must close every document created during the test");
}

- (void)testDocumentBuiltWithInitIsTracked
{
    NSUInteger before = MPDocumentsCreatedDuringTest().count;
    MPDocument *document = [[MPDocument alloc] init];
    XCTAssertEqual(MPDocumentsCreatedDuringTest().count, before + 1,
                   @"A document built with -init must be tracked for disposal");
    [document close];
}

- (void)testDocumentBuiltFromContentsOfURLIsTracked
{
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                  URLByAppendingPathComponent:@"mp-disposal-tracking.md"];
    [@"# tracked" writeToURL:url atomically:YES
                    encoding:NSUTF8StringEncoding error:NULL];

    NSUInteger before = MPDocumentsCreatedDuringTest().count;
    NSError *error = nil;
    MPDocument *document = [[MPDocument alloc]
        initWithContentsOfURL:url
                       ofType:@"net.daringfireball.markdown"
                        error:&error];
    XCTAssertNotNil(document, @"Precondition: the document must load");
    XCTAssertEqual(MPDocumentsCreatedDuringTest().count, before + 1,
                   @"-initWithContentsOfURL:ofType:error: must funnel through -init, "
                    "or documents loaded from disk escape disposal");

    [document close];
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (void)testClosingAnUnusedDocumentDoesNotThrow
{
    // Disposal closes documents that never got an editor, renderer or window
    // controller, which is how nearly every test leaves them.
    MPDocument *document = [[MPDocument alloc] init];
    XCTAssertNoThrow([document close],
                     @"A bare document must survive being closed");
}

@end
