//
//  MPDocumentPrintTests.m
//  MacDownTests
//
//  Tests that -printDocumentWithSettings:showPrintPanel:delegate:
//  didPrintSelector:contextInfo: reports completion to the caller's delegate.
//  No print operation is run: the test document records the operation
//  NSDocument asks it to run and the tests complete it themselves.
//

#import <XCTest/XCTest.h>
#import <objc/message.h>
#import "MPDocument.h"
#import "MPDocumentWindowTestSupport.h"
#import "MPPreferences.h"


@interface MPDocument (PrintTesting)
@property (nonatomic, readonly) BOOL needsHtml;
@property BOOL printing;
@end


#pragma mark - Test Document

// Stands in for the print sheet. NSDocument's print method ends by calling
// -runModalPrintOperation:delegate:didRunSelector:contextInfo:, whose delegate
// is sent the selector with the document, the result and the context once the
// operation is over.
@interface MPPrintTestDocument : MPDocument
@property NSUInteger runCount;
@property (strong) id runDelegate;
@property SEL runSelector;
@property void *runContextInfo;
// When set, the operation is over before -runModalPrintOperation:... returns.
@property BOOL finishesImmediately;
@property BOOL immediateResult;
- (void)finishPrintOperationWithSuccess:(BOOL)success;
@end

@implementation MPPrintTestDocument

- (void)runModalPrintOperation:(NSPrintOperation *)printOperation
                      delegate:(id)delegate didRunSelector:(SEL)selector
                   contextInfo:(void *)contextInfo
{
    self.runCount++;
    self.runDelegate = delegate;
    self.runSelector = selector;
    self.runContextInfo = contextInfo;
    if (self.finishesImmediately)
        [self finishPrintOperationWithSuccess:self.immediateResult];
}

- (void)finishPrintOperationWithSuccess:(BOOL)success
{
    void (*send)(id, SEL, NSDocument *, BOOL, void *) = (void *)objc_msgSend;
    send(self.runDelegate, self.runSelector, self, success,
         self.runContextInfo);
}

@end


#pragma mark - Print Delegate

// What a print delegate was told. Kept apart from the delegate so the results
// outlive it.
@interface MPPrintCompletionLog : NSObject
@property NSUInteger callCount;
@property (strong) NSDocument *document;
@property BOOL success;
@property void *contextInfo;
@end

@implementation MPPrintCompletionLog
@end

@interface MPPrintDelegate : NSObject
@property (strong) MPPrintCompletionLog *log;
@end

@implementation MPPrintDelegate

- (void)document:(NSDocument *)document didPrint:(BOOL)success
     contextInfo:(void *)contextInfo
{
    self.log.callCount++;
    self.log.document = document;
    self.log.success = success;
    self.log.contextInfo = contextInfo;
}

@end


#pragma mark - Test Case

@interface MPDocumentPrintTests : XCTestCase
@property (strong) MPPrintTestDocument *document;
@property BOOL originalManualRender;
@end


@implementation MPDocumentPrintTests

- (void)setUp
{
    [super setUp];
    // The print method defers its work through -performAfterRender:, which
    // runs it at once only while needsHtml is YES.
    MPPreferences *preferences = [MPPreferences sharedInstance];
    self.originalManualRender = preferences.markdownManualRender;
    preferences.markdownManualRender = NO;
    self.document = [[MPPrintTestDocument alloc] init];
}

- (void)tearDown
{
    self.document = nil;
    [MPPreferences sharedInstance].markdownManualRender =
        self.originalManualRender;
    [super tearDown];
}

- (BOOL)loadDocumentWindow
{
    if (!MPLoadDocumentWindow(self.document))
        return NO;
    XCTAssertTrue(self.document.needsHtml,
                  @"a loaded window shows the preview, so printing starts "
                  @"without waiting for a render");
    return YES;
}

/**
 * The print sheet ends after the print method has returned. The delegate must
 * still be there, and must be told the document, the result and its own
 * context.
 */
- (void)testPrintDelegateIsCalledBackAfterPrintMethodReturns
{
    XCTSkipUnless([self loadDocumentWindow],
                  @"no document window can be loaded here");

    static char context;
    MPPrintCompletionLog *log = [[MPPrintCompletionLog alloc] init];
    __weak MPPrintDelegate *weakDelegate = nil;
    @autoreleasepool
    {
        MPPrintDelegate *delegate = [[MPPrintDelegate alloc] init];
        delegate.log = log;
        weakDelegate = delegate;
        [self.document printDocumentWithSettings:@{} showPrintPanel:NO
                                        delegate:delegate
                                didPrintSelector:
            @selector(document:didPrint:contextInfo:)
                                     contextInfo:&context];
    }
    XCTAssertEqual(self.document.runCount, 1u,
                   @"the print operation should have been started");
    XCTAssertEqual(log.callCount, 0u,
                   @"the delegate is not called before printing finishes");
    if (!weakDelegate)
    {
        XCTFail(@"the delegate must be kept until it has been called back");
        return;
    }

    @autoreleasepool
    {
        [self.document finishPrintOperationWithSuccess:YES];
    }

    XCTAssertEqual(log.callCount, 1u, @"the delegate is called back once");
    XCTAssertEqual(log.document, self.document);
    XCTAssertTrue(log.success);
    XCTAssertEqual(log.contextInfo, (void *)&context);
    XCTAssertNil(weakDelegate,
                 @"the delegate is let go once it has been called back");
}

/**
 * Printing can also be over before the print method returns. A failed print
 * and a NULL context must reach the delegate as they are.
 */
- (void)testPrintDelegateIsCalledBackBeforePrintMethodReturns
{
    XCTSkipUnless([self loadDocumentWindow],
                  @"no document window can be loaded here");

    MPPrintCompletionLog *log = [[MPPrintCompletionLog alloc] init];
    MPPrintDelegate *delegate = [[MPPrintDelegate alloc] init];
    delegate.log = log;
    log.success = YES;
    log.contextInfo = &log;
    self.document.finishesImmediately = YES;
    self.document.immediateResult = NO;

    [self.document printDocumentWithSettings:@{} showPrintPanel:NO
                                    delegate:delegate
                            didPrintSelector:
        @selector(document:didPrint:contextInfo:)
                                 contextInfo:NULL];

    XCTAssertEqual(self.document.runCount, 1u,
                   @"the print operation should have been started");
    XCTAssertEqual(log.callCount, 1u, @"the delegate is called back once");
    XCTAssertEqual(log.document, self.document);
    XCTAssertFalse(log.success);
    XCTAssertEqual(log.contextInfo, NULL);
}

/**
 * Cmd-P and Export PDF print without a delegate.
 */
- (void)testPrintWithoutDelegateFinishes
{
    XCTSkipUnless([self loadDocumentWindow],
                  @"no document window can be loaded here");

    [self.document printDocumentWithSettings:@{} showPrintPanel:NO
                                    delegate:nil didPrintSelector:NULL
                                 contextInfo:NULL];

    XCTAssertEqual(self.document.runCount, 1u,
                   @"the print operation should have been started");
    XCTAssertTrue(self.document.printing,
                  @"the document is printing until the operation is over");

    XCTAssertNoThrow([self.document finishPrintOperationWithSuccess:YES]);

    XCTAssertFalse(self.document.printing,
                   @"the document is no longer printing afterwards");
}

@end
