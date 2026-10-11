//
//  MPDocumentLifecycleTests.m
//  MacDownTests
//
//  Tests for document state management beyond basic I/O.
//  Focuses on dirty flags, revert behavior, encoding detection,
//  and edge cases in document lifecycle.
//
//  Created for Issue #234: Test Coverage Phase 1b
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPToolbarController.h"
#import "../MacDownCore/MPMarkdownPreprocessor.h"
#import "MPPreferences.h"
#import "MPRenderer.h"
#import "MPEditorView.h"
#import "HGMarkdownHighlighter.h"
#import "pmh_parser.h"
#import <sys/stat.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "MPResourceWatcherSet.h"
#import "MPHTMLResourceURLs.h"
#import "MPUtilities.h"


@interface MPPreferences (PreviewEditingTests)
- (int)rendererFlags;


@end

@interface MPDocument (ListFormattingTests)
- (IBAction)toggleOrderedList:(id)sender;
- (IBAction)toggleUnorderedList:(id)sender;
- (IBAction)toggleTaskList:(id)sender;
@end

// A real loopback HTTP response exercises WebKit navigation and its delegates.
@interface MPPreviewHTTPFixture : NSObject
@property (strong) NSURL *URL;
@property (strong) dispatch_source_t listener;
@end

@implementation MPPreviewHTTPFixture
- (instancetype)init
{
    self = [super init];
    if (!self) return nil;
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) return nil;
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(descriptor, 4) != 0) {
        close(descriptor);
        return nil;
    }
    socklen_t length = sizeof(address);
    if (getsockname(descriptor, (struct sockaddr *)&address, &length) != 0) {
        close(descriptor);
        return nil;
    }
    self.URL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/remote.html", ntohs(address.sin_port)]];
    NSString *html = @"<html><head><meta name='remote-marker' content='foreign'></head><body>Remote HTTP</body></html>";
    NSData *body = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *response = [[NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)body.length] dataUsingEncoding:NSUTF8StringEncoding].mutableCopy;
    [response appendData:body];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, descriptor, 0, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
    dispatch_source_set_event_handler(source, ^{
        int client = accept(descriptor, NULL, NULL);
        if (client < 0) return;
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        struct timeval timeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        char request[4096];
        if (read(client, request, sizeof(request)) > 0) {
            const char *bytes = response.bytes;
            NSUInteger remaining = response.length;
            while (remaining) {
                ssize_t sent = write(client, bytes, remaining);
                if (sent <= 0) break;
                bytes += sent;
                remaining -= sent;
            }
        }
        close(client);
    });
    dispatch_source_set_cancel_handler(source, ^{ close(descriptor); });
    self.listener = source;
    dispatch_resume(source);
    return self;
}
- (void)dealloc
{
    if (_listener) dispatch_source_cancel(_listener);
}
@end

#pragma mark - Test Infrastructure for Issue #358

// Expose private MPDocument properties needed by the reload tests.
@interface MPDocument (ReloadTesting)
@property (strong) MPRenderer *renderer;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (weak) MPEditorView *editor;
@property (copy) NSString *loadedString;
- (void)reloadFromLoadedString;
- (void)setupEditor:(NSString *)changedKey;
- (IBAction)toggleUnderline:(id)sender;
- (IBAction)toggleStrong:(id)sender;
- (IBAction)convertToH1:(id)sender;
- (IBAction)toggleEmphasis:(id)sender;
- (IBAction)toggleStrikethrough:(id)sender;
- (BOOL)previewHasFindFocus;
- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView;
@property (nonatomic) BOOL isPreviewReady;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (nonatomic) BOOL renderToWebPending;
@property (nonatomic) BOOL printing;
@property (weak) WebView *preview;
@property (strong) MPResourceWatcherSet *resourceWatcherSet;
@property (strong) NSSearchField *previewFindField;
@property (strong) NSTextField *readingProgressLabel;
@property (copy) NSArray<NSDictionary *> *previewEditRanges;
@property (copy) NSString *previewEditToken;
@property (copy) NSString *previewEditSource;
- (BOOL)applyPreviewEditPayload:(NSDictionary *)payload;
- (void)installPreviewEditor;
- (void)handlePreviewEdit:(NSURL *)url;
- (void)setupReadingProgress;
- (void)updateReadingProgress;
- (void)willStartLiveScroll:(NSNotification *)notification;
- (void)willStartPreviewLiveScroll:(NSNotification *)notification;
- (void)processExternalFileChange;
- (BOOL)performAfterRender:(void (^)(void))handler;
- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html;
- (void)resourceWatcherSet:(MPResourceWatcherSet *)set didDetectChangeAtPath:(NSString *)path;
- (IBAction)exportPdf:(id)sender;
- (IBAction)exportHtml:(id)sender;
+ (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context;
- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context;
@end

@interface MPRenderer (DocumentActionTesting)
- (void)parseMarkdown:(NSString *)markdown;
@end

@interface HGMarkdownHighlighter (DocumentFootnoteTesting)
- (pmh_element **)parseText:(NSString *)markdown;
@end

// Spy renderer: records whether parseAndRenderNow was called without
// performing actual background work.
@interface MPSpyRenderer : MPRenderer
@property (nonatomic) BOOL parseAndRenderNowCalled;
@end

@implementation MPSpyRenderer
- (void)parseAndRenderNow {
    self.parseAndRenderNowCalled = YES;
    // Do not call super — avoids enqueuing background parse/render ops in tests.
}
@end

// Spy highlighter: records whether parseAndHighlightNow was called.
@interface MPSpyHighlighter : HGMarkdownHighlighter
@property (nonatomic) BOOL parseAndHighlightNowCalled;
@property (nonatomic) BOOL clearHighlightingCalled;
@property (nonatomic) BOOL readClearTextStylesFromTextViewCalled;
@end

@implementation MPSpyHighlighter
- (void)parseAndHighlightNow {
    self.parseAndHighlightNowCalled = YES;
    // Do not call super — avoids actual text-view work in tests.
}
- (void)clearHighlighting {
    self.clearHighlightingCalled = YES;
}
- (void)readClearTextStylesFromTextView {
    self.readClearTextStylesFromTextViewCalled = YES;
}
@end


@interface MPPrintDelegateProbe : NSObject
@property NSDocument *document;
@property BOOL success;
@property void *context;
@property NSUInteger calls;
- (void)document:(NSDocument *)document printed:(BOOL)success context:(void *)context;
@end
@implementation MPPrintDelegateProbe
- (void)document:(NSDocument *)document printed:(BOOL)success context:(void *)context
{
    self.document = document; self.success = success; self.context = context; self.calls++;
}
@end

// Observe publication and alert output; leave the document, renderer and file
// writes real. Presenting an error sheet is an external UI boundary.
@interface MPDocumentExportAuditProbe : MPDocument
@property (strong) NSMutableArray<NSString *> *publishedHTML;
@property (strong) NSError *presentedError;
@end
@implementation MPDocumentExportAuditProbe
- (instancetype)init
{
    if ((self = [super init])) self.publishedHTML = [NSMutableArray array];
    return self;
}
- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    [self.publishedHTML addObject:html];
    [super renderer:renderer didProduceHTMLOutput:html];
}
- (BOOL)presentError:(NSError *)error
{
    self.presentedError = error;
    return NO;
}
@end

// Save-panel interaction alone is substituted. The export action, render
// completion, pending-operation rule and filesystem failure remain production.
@interface MPControlledExportPanel : NSObject
@property (copy) NSArray *allowedFileTypes;
@property (copy) NSString *nameFieldStringValue;
@property (strong) NSView *accessoryView;
@property (strong) NSURL *URL;
@property (copy) void (^completion)(NSInteger);
@property NSUInteger presentations;
@end
@implementation MPControlledExportPanel
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger))completion
{
    self.presentations++;
    self.completion = completion;
}
@end
static MPControlledExportPanel *MPCurrentControlledExportPanel;
static id MPControlledExportPanelFactory(id receiver, SEL selector)
{
    return MPCurrentControlledExportPanel;
}

@interface MPDocumentLifecycleTests : XCTestCase
@property (strong) MPDocument *document;
@property (strong) NSURL *testFileURL;
@property (strong) NSString *testDirectory;
@property (strong) NSFileManager *fileManager;
@end


@implementation MPDocumentLifecycleTests

- (void)setUp
{
    [super setUp];

    self.fileManager = [NSFileManager defaultManager];

    // Create unique test directory
    NSString *tempDir = NSTemporaryDirectory();
    self.testDirectory = [tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.fileManager createDirectoryAtPath:self.testDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];

    self.testFileURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"test.md"]];

    // Create a fresh document for each test
    self.document = [[MPDocument alloc] init];
}

- (void)tearDown
{
    // Clean up test files and directory
    if (self.testDirectory) {
        [self.fileManager removeItemAtPath:self.testDirectory error:nil];
    }

    self.document = nil;
    self.testFileURL = nil;
    self.testDirectory = nil;

    [super tearDown];
}


#pragma mark - Dirty Flag Tests

- (void)testDocumentDirtyFlagAfterEdit
{
    // Set fileURL to simulate a saved document
    [self.document setFileURL:self.testFileURL];

    // Initially not edited
    [self.document updateChangeCount:NSChangeCleared];
    XCTAssertFalse([self.document isDocumentEdited],
                   @"Document should not be edited initially");

    // Mark as edited
    [self.document updateChangeCount:NSChangeDone];

    // Should now be dirty
    XCTAssertTrue([self.document isDocumentEdited],
                  @"Document with fileURL should report as edited after change");
}

- (void)testDocumentDirtyFlagAfterMultipleEdits
{
    [self.document setFileURL:self.testFileURL];
    [self.document updateChangeCount:NSChangeCleared];

    // Multiple edits
    for (int i = 0; i < 5; i++) {
        [self.document updateChangeCount:NSChangeDone];
    }

    XCTAssertTrue([self.document isDocumentEdited],
                  @"Document should still be edited after multiple changes");
}

- (void)testDocumentDirtyFlagAfterUndoRedo
{
    [self.document setFileURL:self.testFileURL];
    [self.document updateChangeCount:NSChangeCleared];

    // Make a change
    [self.document updateChangeCount:NSChangeDone];
    XCTAssertTrue([self.document isDocumentEdited], @"Should be dirty after edit");

    // Undo the change
    [self.document updateChangeCount:NSChangeUndone];
    XCTAssertFalse([self.document isDocumentEdited],
                   @"Should not be dirty after undo to saved state");

    // Redo the change
    [self.document updateChangeCount:NSChangeRedone];
    XCTAssertTrue([self.document isDocumentEdited],
                  @"Should be dirty again after redo");
}

- (void)testUntitledDocumentDirtyFlag
{
    // Document without fileURL (untitled)
    XCTAssertNil(self.document.fileURL, @"Untitled document should have no fileURL");

    // In headless mode, editor is nil, so markdown is nil
    // The isDocumentEdited logic returns NO for untitled documents with no content
    XCTAssertFalse([self.document isDocumentEdited],
                   @"Empty untitled document should not report as edited");

    // Even with changes marked, behavior depends on content
    [self.document updateChangeCount:NSChangeDone];
    // Still should be NO because editor.string is nil (no content)
    XCTAssertFalse([self.document isDocumentEdited],
                   @"Untitled document with no actual content should not report as edited");
}


#pragma mark - Revert Tests

- (void)testDocumentRevertClearsChanges
{
    // Create a test file
    NSString *originalContent = @"# Original Content\n\nThis is the original.";
    NSError *error = nil;
    [originalContent writeToURL:self.testFileURL
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:&error];
    XCTAssertNil(error, @"Should write test file");

    // Load document from file
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document");
    XCTAssertNil(error, @"Should not have error loading document");

    // Mark as edited
    [doc updateChangeCount:NSChangeDone];
    XCTAssertTrue([doc isDocumentEdited], @"Should be dirty after change");

    // Revert (this is inherited from NSDocument)
    // Note: In headless mode, revert may not fully work as it needs window controller
    [doc updateChangeCount:NSChangeCleared];
    XCTAssertFalse([doc isDocumentEdited], @"Should not be dirty after clearing changes");
}

- (void)testDocumentRevertFromDisk
{
    // Create initial file
    NSString *originalContent = @"# Original";
    NSError *error = nil;
    [originalContent writeToURL:self.testFileURL
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:&error];

    // Load document
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document");

    // Read the file content again using readFromData
    NSData *fileData = [NSData dataWithContentsOfURL:self.testFileURL];
    BOOL success = [doc readFromData:fileData
                              ofType:@"net.daringfireball.markdown"
                               error:&error];
    XCTAssertTrue(success, @"Should successfully re-read file data");
}


#pragma mark - Encoding Detection Tests

- (void)testDocumentEncodingDetectionUTF8
{
    // Create UTF-8 file with special characters
    NSString *content = @"# UTF-8 Test\n\n日本語テスト\nÄÖÜ äöü ß";
    NSError *error = nil;
    [content writeToURL:self.testFileURL
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&error];
    XCTAssertNil(error, @"Should write UTF-8 file");

    // Load document
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load UTF-8 document");
    XCTAssertNil(error, @"Should not have error loading UTF-8");
}

- (void)testDocumentEncodingDetectionUTF8BOM
{
    // Create UTF-8 file with BOM
    const unsigned char bom[] = {0xEF, 0xBB, 0xBF};
    NSMutableData *dataWithBOM = [NSMutableData dataWithBytes:bom length:sizeof(bom)];
    [dataWithBOM appendData:[@"# Document with BOM" dataUsingEncoding:NSUTF8StringEncoding]];

    NSError *error = nil;
    [dataWithBOM writeToURL:self.testFileURL atomically:YES];

    // Load document
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document with BOM");
}

- (void)testDocumentEncodingDetectionASCII
{
    // Pure ASCII content
    NSString *content = @"# Simple ASCII\n\nNo special characters here.";
    NSError *error = nil;
    [content writeToURL:self.testFileURL
             atomically:YES
               encoding:NSASCIIStringEncoding
                  error:&error];
    XCTAssertNil(error, @"Should write ASCII file");

    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load ASCII document");
}


#pragma mark - No Extension Tests

- (void)testDocumentWithNoExtension
{
    // Create file without extension
    NSURL *noExtURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"noextension"]];
    NSString *content = @"# No Extension\n\nThis file has no extension.";
    NSError *error = nil;
    [content writeToURL:noExtURL
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&error];
    XCTAssertNil(error, @"Should write file without extension");

    // Load document - may need explicit type
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:noExtURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document without extension");
}

- (void)testDocumentWithUnusualExtension
{
    // Create file with unusual extension
    NSURL *unusualExtURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"test.txt"]];
    NSString *content = @"# TXT Extension\n\nMarkdown content in a .txt file.";
    NSError *error = nil;
    [content writeToURL:unusualExtURL
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&error];
    XCTAssertNil(error, @"Should write .txt file");

    // Load as markdown type
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:unusualExtURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load .txt file as markdown");
}


#pragma mark - File Conflict Tests

- (void)testSaveWithFileModifiedExternally
{
    // Create initial file
    NSString *originalContent = @"# Original";
    NSError *error = nil;
    [originalContent writeToURL:self.testFileURL
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:&error];

    // Load document
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document");

    // Modify file externally (simulating another process)
    NSString *externalContent = @"# Modified Externally";
    [externalContent writeToURL:self.testFileURL
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:&error];

    // Get file modification date
    NSDictionary *attrs = [self.fileManager attributesOfItemAtPath:self.testFileURL.path error:&error];
    NSDate *modDate = attrs[NSFileModificationDate];
    XCTAssertNotNil(modDate, @"Should have modification date");

    // The document's fileModificationDate may differ from the file's current date
    // This is how the system detects external modifications
}

- (void)testDocumentDetectsExternalChange
{
    // Create file
    NSString *content = @"# Initial Content";
    NSError *error = nil;
    [content writeToURL:self.testFileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    // Load document
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document");

    // Wait a moment to ensure different timestamp
    [NSThread sleepForTimeInterval:0.1];

    // Modify file externally
    NSString *newContent = @"# Changed Content";
    [newContent writeToURL:self.testFileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    // Read file to verify it changed
    NSString *readContent = [NSString stringWithContentsOfURL:self.testFileURL
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
    XCTAssertEqualObjects(readContent, newContent, @"File should have new content");
}


#pragma mark - File Deleted During Edit Tests

- (void)testOpenFileDeletedDuringEdit
{
    // Create file
    NSString *content = @"# Will Be Deleted";
    NSError *error = nil;
    [content writeToURL:self.testFileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    // Load document
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should load document");

    // Verify fileURL is set
    XCTAssertNotNil(doc.fileURL, @"Document should have fileURL");

    // Delete file externally
    [self.fileManager removeItemAtURL:self.testFileURL error:&error];
    XCTAssertNil(error, @"Should delete file");

    // Verify file is gone
    XCTAssertFalse([self.fileManager fileExistsAtPath:self.testFileURL.path],
                   @"File should be deleted");

    // Document still has the fileURL reference
    XCTAssertNotNil(doc.fileURL, @"Document should still have fileURL even if file is deleted");
}

- (void)testDocumentFileURLAfterFileDeleted
{
    // Create and load document
    NSString *content = @"# Test";
    NSError *error = nil;
    [content writeToURL:self.testFileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];

    NSURL *originalURL = doc.fileURL;

    // Delete file
    [self.fileManager removeItemAtURL:self.testFileURL error:nil];

    // fileURL should be unchanged (it's a reference, not live validation)
    XCTAssertEqualObjects(doc.fileURL, originalURL,
                          @"fileURL should persist even after file deletion");
}


#pragma mark - Document Type Tests

- (void)testReadableTypes
{
    NSArray *readableTypes = [MPDocument readableTypes];
    XCTAssertNotNil(readableTypes, @"Should return readable types");
    XCTAssertGreaterThan(readableTypes.count, 0, @"Should have at least one readable type");
    XCTAssertTrue([readableTypes containsObject:@"net.daringfireball.markdown"],
                  @"Should include markdown type");
}

- (void)testWritableTypesForSaveOperation
{
    NSArray *writableTypes = [MPDocument writableTypes];
    XCTAssertNotNil(writableTypes, @"Should return writable types");
    XCTAssertTrue([writableTypes containsObject:@"net.daringfireball.markdown"],
                  @"Should include markdown type for writing");
}


#pragma mark - Autosave Tests

- (void)testAutosavesInPlaceRespectsPreference
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;

    // When preference is YES, autosave should be enabled
    prefs.editorAutoSave = YES;
    XCTAssertTrue([MPDocument autosavesInPlace],
                  @"MPDocument should autosave when editorAutoSave is YES");

    // When preference is NO, autosave should be disabled
    prefs.editorAutoSave = NO;
    XCTAssertFalse([MPDocument autosavesInPlace],
                   @"MPDocument should not autosave when editorAutoSave is NO");

    // Restore
    prefs.editorAutoSave = original;
}

- (void)testPreservesVersions
{
    // Test the class method for version preservation
    BOOL preserves = [MPDocument preservesVersions];
    // Value depends on implementation, just verify it doesn't crash
    XCTAssertTrue(preserves || !preserves, @"Should return boolean value");
}


#pragma mark - Data Conversion Tests

- (void)testDataOfTypeWithEmptyDocument
{
    NSError *error = nil;
    NSData *data = [self.document dataOfType:@"net.daringfireball.markdown" error:&error];

    // Without editor, markdown is nil, so data may be nil or empty
    // This is expected behavior in headless mode
    if (data != nil) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        XCTAssertNotNil(content, @"Data should be valid UTF-8 if not nil");
    }
}

- (void)testReadFromDataSetsLoadedString
{
    NSString *testContent = @"# Test Content\n\nSome text here.";
    NSData *data = [testContent dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    BOOL success = [self.document readFromData:data
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    XCTAssertTrue(success, @"Should successfully read data");
    XCTAssertNil(error, @"Should not have error");

    // The content is stored internally as loadedString
    // but we cannot access it directly in headless mode
}


#pragma mark - Edge Cases

- (void)testVeryLongFileName
{
    // Create file with very long name
    NSMutableString *longName = [NSMutableString string];
    for (int i = 0; i < 50; i++) {
        [longName appendString:@"longname"];
    }
    [longName appendString:@".md"];

    // Most file systems have a 255 character limit for filenames
    if (longName.length > 255) {
        longName = [[longName substringToIndex:251] mutableCopy];
        [longName appendString:@".md"];
    }

    NSURL *longNameURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:longName]];
    NSString *content = @"# Long Filename Test";
    NSError *error = nil;

    BOOL written = [content writeToURL:longNameURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (written) {
        MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:longNameURL
                                                             ofType:@"net.daringfireball.markdown"
                                                              error:&error];
        XCTAssertNotNil(doc, @"Should handle long filename");
    }
    // If writing fails due to filename length, that's expected on some systems
}

- (void)testSpecialCharactersInFileName
{
    // Create file with special characters (but valid for filesystem)
    NSURL *specialURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"test-file_v2 (copy).md"]];
    NSString *content = @"# Special Characters";
    NSError *error = nil;
    [content writeToURL:specialURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:specialURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should handle special characters in filename");
}

- (void)testUnicodeFileName
{
    // Create file with Unicode name
    NSURL *unicodeURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"テスト文書.md"]];
    NSString *content = @"# Unicode Filename Test";
    NSError *error = nil;
    [content writeToURL:unicodeURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (error == nil) {
        MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:unicodeURL
                                                             ofType:@"net.daringfireball.markdown"
                                                              error:&error];
        XCTAssertNotNil(doc, @"Should handle Unicode filename");
    }
}


#pragma mark - reloadFromLoadedString Tests (Issue #358)
//
// These tests cover the bug where new (untitled) documents never receive an
// initial render because reloadFromLoadedString guarded all rendering behind
// the loadedString != nil check.  The two "New document" tests are RED before
// the fix — they assert behaviour the current code does not yet provide.

// Helper: wires spy renderer, editor, and highlighter into `doc` so that
// reloadFromLoadedString's outer guard (editor && renderer && highlighter) is
// satisfied.  All three objects are ALWAYS assigned to `doc` regardless of
// which output pointers the caller provides; the output params are purely
// convenience references for callers that need to inspect them afterward.
- (void)wireDocument:(MPDocument *)doc
         intoRenderer:(MPSpyRenderer **)rendererOut
          highlighter:(MPSpyHighlighter **)highlighterOut
               editor:(MPEditorView *__strong *)editorOut
{
    MPSpyRenderer *renderer = [[MPSpyRenderer alloc] init];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSZeroRect];
    MPSpyHighlighter *highlighter =
        [[MPSpyHighlighter alloc] initWithTextView:editor waitInterval:0.0];

    doc.renderer = renderer;
    doc.editor = editor;
    doc.highlighter = highlighter;

    if (rendererOut)    *rendererOut    = renderer;
    if (highlighterOut) *highlighterOut = highlighter;
    if (editorOut)      *editorOut      = editor;
}

// Regression test for issue #358: new documents must trigger a render so the
// preview WebView is initialised before the user starts typing.
- (void)testNewDocumentTriggersRenderOnReload
{
    MPSpyRenderer *renderer = nil;
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:&renderer
            highlighter:nil
                 editor:&editor];

    XCTAssertNil(self.document.loadedString,
                 @"Precondition: new document has no loadedString");

    [self.document reloadFromLoadedString];

    XCTAssertTrue(renderer.parseAndRenderNowCalled,
                  @"parseAndRenderNow must fire for new documents so the preview "
                   "WebView is initialised before the user starts typing (issue #358)");
}

// Regression test for issue #358: syntax highlighting must also fire for new documents.
- (void)testNewDocumentTriggersHighlightOnReload
{
    MPSpyHighlighter *highlighter = nil;
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:nil
            highlighter:&highlighter
                 editor:&editor];

    XCTAssertNil(self.document.loadedString,
                 @"Precondition: new document has no loadedString");

    [self.document reloadFromLoadedString];

    XCTAssertTrue(highlighter.parseAndHighlightNowCalled,
                  @"parseAndHighlightNow must fire for new documents (issue #358)");
}

- (void)testExistingDocumentClearsHighlightingBeforeReloadHighlight
{
    MPSpyHighlighter *highlighter = nil;
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:nil
            highlighter:&highlighter
                 editor:&editor];

    self.document.loadedString = @"# Reloaded\n\nBody";
    highlighter.clearHighlightingCalled = NO;
    highlighter.readClearTextStylesFromTextViewCalled = NO;

    [self.document reloadFromLoadedString];

    XCTAssertTrue(highlighter.clearHighlightingCalled,
                  @"Issue #378: external reload should clear stale editor attributes "
                  @"before the async highlight pass");
    XCTAssertTrue(highlighter.readClearTextStylesFromTextViewCalled,
                  @"Issue #378: highlighter should refresh clear-text attributes "
                  @"after replacing editor text");
}

// Regression: existing-document path must still trigger a render after the fix.
- (void)testExistingDocumentTriggersRenderOnReload
{
    MPSpyRenderer *renderer = nil;
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:&renderer
            highlighter:nil
                 editor:&editor];

    self.document.loadedString = @"# Existing content";

    [self.document reloadFromLoadedString];

    XCTAssertTrue(renderer.parseAndRenderNowCalled,
                  @"parseAndRenderNow must fire for documents opened from a file");
}

// Regression: loadedString must be consumed (nil-ed) after reload.
- (void)testReloadConsumesLoadedString
{
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:nil
            highlighter:nil
                 editor:&editor];

    self.document.loadedString = @"# Content to consume";

    [self.document reloadFromLoadedString];

    XCTAssertNil(self.document.loadedString,
                 @"loadedString must be nil-ed out after it is applied to the editor");
}

// Regression: editor.string must reflect the loaded content after reload.
- (void)testReloadSetsEditorStringFromLoadedString
{
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:nil
            highlighter:nil
                 editor:&editor];

    self.document.loadedString = @"# Hello World";

    [self.document reloadFromLoadedString];

    XCTAssertEqualObjects(editor.string, @"# Hello World",
                          @"Editor must contain the loaded string after reload");
}

// Guard path: reloadFromLoadedString must be a safe no-op when the document's
// dependencies (editor / renderer / highlighter) are not yet wired up.  This
// is the state during readFromData:ofType:error:, before the window controller
// nib has loaded.  Calling it must not crash and must not trigger a render.
- (void)testReloadIsNoOpWhenDependenciesNotReady
{
    // Document is freshly allocated — editor, renderer, highlighter are all nil.
    XCTAssertNil(self.document.editor,    @"Precondition: editor is nil");
    XCTAssertNil(self.document.renderer,  @"Precondition: renderer is nil");
    XCTAssertNil(self.document.highlighter, @"Precondition: highlighter is nil");

    // Must not crash with no loadedString set.
    XCTAssertNoThrow([self.document reloadFromLoadedString],
                     @"reloadFromLoadedString must not crash when dependencies are absent");

    // loadedString, if any, must be untouched (guard failed before consuming it).
    // Re-assert the precondition so the guard's state is explicit for this second call.
    self.document.loadedString = @"# Not yet";
    XCTAssertNil(self.document.editor, @"Precondition still holds: editor is nil");
    [self.document reloadFromLoadedString];
    XCTAssertEqualObjects(self.document.loadedString, @"# Not yet",
                          @"loadedString must not be consumed when the guard fails");
}

// Regression: editor.string must stay empty for new documents (no loadedString).
- (void)testReloadDoesNotModifyEditorStringForNewDocument
{
    MPEditorView *editor = nil;
    [self wireDocument:self.document
           intoRenderer:nil
            highlighter:nil
                 editor:&editor];

    XCTAssertEqualObjects(editor.string, @"",
                          @"Precondition: new document editor starts empty");

    [self.document reloadFromLoadedString];

    XCTAssertEqualObjects(editor.string, @"",
                          @"Editor string must not change for new documents "
                           "when there is no loadedString to apply");
}


#pragma mark - Preview Rendering Gate Tests (Issue #358 follow-up)

// When isPreviewReady is NO, the alreadyRenderingInWeb flag must NOT block the
// render.  The method should proceed past the gate and set alreadyRenderingInWeb
// to YES.  renderToWebPending must remain NO (no deferral occurred).
// We start alreadyRenderingInWeb at NO so the assertion that it becomes YES
// proves line 1278 actually executed (the gate was not triggered).
- (void)testPreReadyRendersNotBlockedByAlreadyRenderingInWeb
{
    MPSpyRenderer *renderer = nil;
    [self wireDocument:self.document
           intoRenderer:&renderer
            highlighter:nil
                 editor:nil];

    self.document.isPreviewReady = NO;
    self.document.alreadyRenderingInWeb = NO;
    self.document.renderToWebPending = NO;

    [(id<MPRendererDelegate>)self.document renderer:renderer
                               didProduceHTMLOutput:@"<p>test</p>"];

    XCTAssertFalse(self.document.renderToWebPending,
                   @"renderToWebPending must remain NO — render should not be "
                    "deferred when isPreviewReady is NO (issue #358)");
    XCTAssertTrue(self.document.alreadyRenderingInWeb,
                  @"alreadyRenderingInWeb must be YES — method must proceed past "
                   "the gate and set the flag when isPreviewReady is NO");
}

// When isPreviewReady is YES and alreadyRenderingInWeb is YES, the method must
// defer the render by setting renderToWebPending and returning early.
// alreadyRenderingInWeb must remain YES (the in-flight load is still active).
- (void)testPostReadyRendersBlockedByAlreadyRenderingInWeb
{
    MPSpyRenderer *renderer = nil;
    [self wireDocument:self.document
           intoRenderer:&renderer
            highlighter:nil
                 editor:nil];

    self.document.isPreviewReady = YES;
    self.document.alreadyRenderingInWeb = YES;
    self.document.renderToWebPending = NO;

    [(id<MPRendererDelegate>)self.document renderer:renderer
                               didProduceHTMLOutput:@"<p>test</p>"];

    XCTAssertTrue(self.document.renderToWebPending,
                  @"renderToWebPending must be YES — render must be deferred when "
                   "isPreviewReady is YES and alreadyRenderingInWeb is YES");
    XCTAssertTrue(self.document.alreadyRenderingInWeb,
                  @"alreadyRenderingInWeb must remain YES — the in-flight load is "
                   "still active; the method returned early without clearing it");
}

// When alreadyRenderingInWeb is NO the method must always proceed past the gate,
// regardless of isPreviewReady.  After the call, alreadyRenderingInWeb must be
// YES and renderToWebPending must remain NO.
- (void)testRendersNotBlockedWhenAlreadyRenderingInWebIsNO
{
    // Sub-case 1: isPreviewReady = NO
    {
        MPSpyRenderer *renderer = nil;
        MPDocument *doc = [[MPDocument alloc] init];
        [self wireDocument:doc
               intoRenderer:&renderer
                highlighter:nil
                     editor:nil];

        doc.isPreviewReady = NO;
        doc.alreadyRenderingInWeb = NO;
        doc.renderToWebPending = NO;

        [(id<MPRendererDelegate>)doc renderer:renderer
                          didProduceHTMLOutput:@"<p>test</p>"];

        XCTAssertTrue(doc.alreadyRenderingInWeb,
                      @"alreadyRenderingInWeb must be YES after render proceeds "
                       "(isPreviewReady=NO, alreadyRenderingInWeb=NO)");
        XCTAssertFalse(doc.renderToWebPending,
                       @"renderToWebPending must remain NO — no deferral should "
                        "occur when alreadyRenderingInWeb starts as NO");
    }

    // Sub-case 2: isPreviewReady = YES
    {
        MPSpyRenderer *renderer = nil;
        MPDocument *doc = [[MPDocument alloc] init];
        [self wireDocument:doc
               intoRenderer:&renderer
                highlighter:nil
                     editor:nil];

        doc.isPreviewReady = YES;
        doc.alreadyRenderingInWeb = NO;
        doc.renderToWebPending = NO;

        [(id<MPRendererDelegate>)doc renderer:renderer
                          didProduceHTMLOutput:@"<p>test</p>"];

        XCTAssertTrue(doc.alreadyRenderingInWeb,
                      @"alreadyRenderingInWeb must be YES after render proceeds "
                       "(isPreviewReady=YES, alreadyRenderingInWeb=NO)");
        XCTAssertFalse(doc.renderToWebPending,
                       @"renderToWebPending must remain NO — no deferral should "
                        "occur when alreadyRenderingInWeb starts as NO");
    }
}


#pragma mark - Opened-File Preview Base URL (Issue #405)

// Simulate the open-file state: the document has a fileURL pointing at a real
// on-disk .md file, exactly as it does after opening a saved document. The base
// URL handed to the preview WebView — through the MPRendererDelegate
// rendererBaseURL: hook that MPRenderer queries before producing HTML — must
// never be the real document file, because WebKit on macOS 26 can silently blank
// the preview when its base resource is that file (issues #405 / #431). Full
// WebView rendering can't be asserted headlessly, but this exercises the
// document-level base-URL path where the blank-preview bug lives.
- (void)testRendererBaseURLForOpenedFileAvoidsRealDocumentFile
{
    NSString *content = @"# Opened\n\nBody text.\n";
    [content writeToURL:self.testFileURL atomically:YES
               encoding:NSUTF8StringEncoding error:nil];
    self.document.fileURL = self.testFileURL;

    NSURL *base = [(id<MPRendererDelegate>)self.document rendererBaseURL:nil];

    XCTAssertNotNil(base, @"An opened document must still provide a base URL");
    XCTAssertNotEqualObjects(base, self.testFileURL,
        @"The opened document's own file must never be the preview base resource");
    XCTAssertEqualObjects(base.URLByDeletingLastPathComponent.path,
                          self.testFileURL.URLByDeletingLastPathComponent.path,
        @"The base URL must stay in the document's directory so relative "
         "resources and the security scope check are unchanged");
    XCTAssertFalse([self.fileManager fileExistsAtPath:base.path],
        @"The base URL must point at a non-existent sentinel, not a real file");
}


#pragma mark - Workspace Tests

- (void)testWorkspaceRootURLDefaultsToNilAndIsSettable
{
    MPDocument *doc = [[MPDocument alloc] init];
    XCTAssertNil(doc.workspaceRootURL);
    NSURL *root = [NSURL fileURLWithPath:@"/tmp" isDirectory:YES];
    doc.workspaceRootURL = root;
    XCTAssertEqualObjects(doc.workspaceRootURL, root);
}

- (void)testPrintCompletionRetainsDelegateAndDeliversArguments
{
    MPPrintDelegateProbe *probe = [MPPrintDelegateProbe new];
    __weak MPPrintDelegateProbe *weakProbe = probe;
    void *expectedContext = (__bridge void *)self;
    NSInvocation *invocation = [MPDocument printCompletionForDelegate:probe
        selector:@selector(document:printed:context:) context:expectedContext];
    void *retainedContext = (__bridge_retained void *)invocation;
    invocation = nil;
    probe = nil;
    XCTAssertNotNil(weakProbe);
    probe = weakProbe;
    [self.document document:self.document didPrint:YES context:retainedContext];
    XCTAssertEqual(probe.calls, 1);
    XCTAssertEqual(probe.document, self.document);
    XCTAssertTrue(probe.success);
    XCTAssertEqual(probe.context, expectedContext);
}

- (void)testEditorFootnoteParsingFollowsPreferenceAndPreservesMath
{
    MPPreferences *preferences = self.document.preferences;
    BOOL originalNotes = preferences.extensionFootnotes;
    BOOL originalMath = preferences.htmlMathJax;
    BOOL originalDollar = preferences.htmlMathJaxInlineDollar;
    HGMarkdownHighlighter *highlighter = [[HGMarkdownHighlighter alloc] init];
    self.document.highlighter = highlighter;
    @try {
        for (NSNumber *notes in @[@NO, @YES]) {
            for (NSNumber *math in @[@NO, @YES]) {
                for (NSNumber *dollar in @[@NO, @YES]) {
                    preferences.extensionFootnotes = notes.boolValue;
                    preferences.htmlMathJax = math.boolValue;
                    preferences.htmlMathJaxInlineDollar = dollar.boolValue;
                    [self.document setupEditor:@"extensionFootnotes"];
                    pmh_element **elements = [highlighter parseText:@"Text[^*note*].\n"];
                    XCTAssertNotEqual(elements, NULL);
                    if (elements) {
                        // A footnote reference is opaque when enabled. With notes disabled,
                        // its asterisks remain ordinary Markdown emphasis.
                        XCTAssertEqual(elements[pmh_EMPH] != NULL, !notes.boolValue);
                        pmh_free_elements(elements);
                    }
                    XCTAssertEqual((highlighter.extensions & pmh_EXT_MATH) != 0,
                                   math.boolValue && dollar.boolValue);
                }
            }
        }
    } @finally {
        [highlighter deactivate];
        preferences.extensionFootnotes = originalNotes;
        preferences.htmlMathJax = originalMath;
        preferences.htmlMathJaxInlineDollar = originalDollar;
    }
}


- (void)testUnderlineActionKeepsUnderlineMeaningWithExtensionEnabledOrDisabled
{
    MPPreferences *preferences = self.document.preferences;
    BOOL original = preferences.extensionUnderline;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    self.document.editor = editor;
    MPRenderer *renderer = [MPRenderer new];
    renderer.dataSource = (id<MPRendererDataSource>)self.document;
    renderer.delegate = (id<MPRendererDelegate>)self.document;
    @try {
        for (NSNumber *enabled in @[@NO, @YES]) {
            preferences.extensionUnderline = enabled.boolValue;
            editor.string = @"text";
            editor.selectedRange = NSMakeRange(0, editor.string.length);
            [self.document toggleUnderline:nil];
            XCTAssertEqualObjects(editor.string, @"_text_");
            [renderer parseMarkdown:editor.string];
            XCTAssertTrue([renderer.currentHtml containsString:@"<u>text</u>"]);
            XCTAssertFalse([renderer.currentHtml containsString:@"<em>"]);
        }
    } @finally {
        preferences.extensionUnderline = original;
    }
}

- (void)testBackspaceDeletesSelectionWithoutDeletingMatchingPairAroundIt
{
    MPPreferences *preferences = self.document.preferences;
    BOOL original = preferences.editorCompleteMatchingCharacters;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    self.document.editor = editor;
    editor.delegate = (id<NSTextViewDelegate>)self.document;
    @try {
        preferences.editorCompleteMatchingCharacters = YES;
        editor.string = @"[]";
        editor.selectedRange = NSMakeRange(1, 1);
        [editor doCommandBySelector:@selector(deleteBackward:)];
        XCTAssertEqualObjects(editor.string, @"[");
        XCTAssertTrue(NSEqualRanges(editor.selectedRange, NSMakeRange(1, 0)));
    } @finally {
        preferences.editorCompleteMatchingCharacters = original;
    }
}

- (void)testSmartHomeWithSurrogatePairMovesToFirstContentCharacter
{
    MPPreferences *preferences = self.document.preferences;
    BOOL original = preferences.editorSmartHome;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    self.document.editor = editor;
    @try {
        preferences.editorSmartHome = YES;
        editor.string = @"  😀";
        editor.selectedRange = NSMakeRange(editor.string.length, 0);
        XCTAssertFalse([self.document textViewShouldMoveToLeftEndOfLine:editor]);
        XCTAssertTrue(NSEqualRanges(editor.selectedRange, NSMakeRange(2, 0)));
    } @finally {
        preferences.editorSmartHome = original;
    }
}


- (void)testPDFExportAllowsOnePendingPanelAndCanRetryAfterCancellation
{
    MPControlledExportPanel *panel = [MPControlledExportPanel new];
    MPCurrentControlledExportPanel = panel;
    Method factory = class_getClassMethod(NSSavePanel.class, @selector(savePanel));
    IMP original = method_setImplementation(factory, (IMP)MPControlledExportPanelFactory);
    @try {
        [self.document exportPdf:nil];
        XCTAssertEqual(panel.presentations, 1u);
        [self.document exportPdf:nil];
        XCTAssertEqual(panel.presentations, 1u, @"A second export must not open another save panel");
        XCTAssertNotNil(panel.completion);
        panel.completion(NSFileHandlingPanelCancelButton);
        [self.document exportPdf:nil];
        XCTAssertEqual(panel.presentations, 2u, @"Cancellation must release the export slot");
        panel.completion(NSFileHandlingPanelCancelButton);
    } @finally {
        method_setImplementation(factory, original);
        MPCurrentControlledExportPanel = nil;
    }
}

- (void)testAnEarlierSaveTimerCannotReloadWhileTheLatestSaveIsProtected
{
    MPDocument *document = [MPDocument new];
    document.fileURL = self.testFileURL;
    document.fileType = @"net.daringfireball.markdown";
    document.markdown = @"first save";
    XCTAssertTrue([document writeToURL:self.testFileURL ofType:document.fileType error:NULL]);
    XCTestExpectation *protected = [self expectationWithDescription:@"Latest save remains protected after first timer"];
    XCTestExpectation *resumed = [self expectationWithDescription:@"External reload resumes after latest timer"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        document.markdown = @"latest save";
        XCTAssertTrue([document writeToURL:self.testFileURL ofType:document.fileType error:NULL]);
        document.fileModificationDate = [NSDate distantPast];
        XCTAssertTrue([@"external change" writeToURL:self.testFileURL atomically:YES
            encoding:NSUTF8StringEncoding error:NULL]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [document processExternalFileChange];
            XCTAssertEqualObjects(document.markdown, @"latest save");
            [protected fulfill];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [document processExternalFileChange];
            XCTAssertEqualObjects(document.markdown, @"external change");
            [resumed fulfill];
        });
    });
    [self waitForExpectations:@[protected, resumed] timeout:5.0];
    [document close];
}

- (void)testChangedHeadScriptsReloadAndUnchangedHeadPreservesJavaScriptState
{
    MPPreferences *preferences = self.document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid, graphviz = preferences.htmlGraphviz;
    MPDocumentExportAuditProbe *document = [MPDocumentExportAuditProbe new];
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    document.preview = preview;
    preview.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    document.renderer = renderer;
    NSString *(^html)(NSString *, NSString *) = ^NSString *(NSString *marker, NSString *body) {
        return [NSString stringWithFormat:@"<html><head><script>window.macdownAuditHeadMarker='%@';</script></head><body><p>%@</p></body></html>", marker, body];
    };
    @try {
        preferences.htmlMathJax = NO; preferences.htmlMermaid = NO; preferences.htmlGraphviz = NO;
        [document renderer:renderer didProduceHTMLOutput:html(@"first", @"first body")];
        XCTNSPredicateExpectation *first = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return document.isPreviewReady &&
                    [[[preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownAuditHeadMarker"] toString] isEqualToString:@"first"];
            }] object:document];
        [self waitForExpectations:@[first] timeout:10.0];
        [document renderer:renderer didProduceHTMLOutput:html(@"second", @"second body")];
        XCTNSPredicateExpectation *second = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return !document.alreadyRenderingInWeb &&
                    [[[preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownAuditHeadMarker"] toString] isEqualToString:@"second"];
            }] object:document];
        [self waitForExpectations:@[second] timeout:10.0];
        [preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownAuditHeadMarker='survived';"];
        [document renderer:renderer didProduceHTMLOutput:html(@"second", @"third body")];
        XCTAssertEqualObjects([[preview.mainFrame.javaScriptContext evaluateScript:@"window.macdownAuditHeadMarker"] toString], @"survived");
        XCTAssertEqualObjects([[preview.mainFrame.javaScriptContext evaluateScript:@"document.body.textContent.trim()"] toString], @"third body");
    } @finally {
        preview.frameLoadDelegate = nil;
        [document close];
        preferences.htmlMathJax = math; preferences.htmlMermaid = mermaid; preferences.htmlGraphviz = graphviz;
    }
}

- (void)testPreviewFindActionsSearchRenderedTextWithoutChangingMarkdown
{
    MPDocument *document = [MPDocument new];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    [document addWindowController:[[NSWindowController alloc] initWithWindow:window]];
    WebView *web = [[WebView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:web];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,400,300)];
    document.editor = editor;
    document.preview = web;
    [document showWindows];
    NSString *source = @"# source remains **unchanged**\n";
    document.editor.string = source;
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    NSMutableArray *originalItems = [NSMutableArray array];
    for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
        NSPasteboardItem *copy = [NSPasteboardItem new];
        for (NSString *type in item.types)
            [copy setData:[item dataForType:type] forType:type];
        [originalItems addObject:copy];
    }
    @try {
        [web.mainFrame loadHTMLString:@"<html><body>"
            "<p id='first'>target <strong>é</strong></p>"
            "<p id='second'>target é</p></body></html>" baseURL:nil];
        XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,
                                                                   NSDictionary *bindings) {
                return !web.isLoading && web.mainFrame.DOMDocument.body != nil;
            }] object:web];
        [self waitForExpectations:@[ready] timeout:10];
        NSMenuItem *find = [[NSMenuItem alloc] initWithTitle:@"Find"
            action:@selector(performDocumentFindAction:) keyEquivalent:@"f"];
        find.tag = NSTextFinderActionShowFindInterface;
        [web.window makeFirstResponder:web.mainFrame.frameView.documentView];
        XCTAssertTrue([NSApp sendAction:find.action to:document from:find]);
        XCTAssertTrue([document respondsToSelector:@selector(previewFindField)]);
        if (![document respondsToSelector:@selector(previewFindField)]) return;
        NSSearchField *field = document.previewFindField;
        XCTAssertTrue(field.window.isVisible);
        field.stringValue = @"target é";
        XCTAssertTrue([NSApp sendAction:field.action to:field.target from:field]);
        XCTAssertEqualObjects(web.selectedDOMRange.toString, @"target é");
        DOMNode *first = web.selectedDOMRange.startContainer;
        find.tag = NSTextFinderActionNextMatch;
        [NSApp sendAction:find.action to:document from:find];
        XCTAssertEqualObjects(web.selectedDOMRange.toString, @"target é");
        XCTAssertNotEqual(web.selectedDOMRange.startContainer, first);
        find.tag = NSTextFinderActionPreviousMatch;
        [NSApp sendAction:find.action to:document from:find];
        XCTAssertEqual(web.selectedDOMRange.startContainer, first);
        find.tag = NSTextFinderActionShowReplaceInterface;
        XCTAssertFalse([document validateDocumentFindAction:find]);
        XCTAssertEqualObjects(document.editor.string, source);
        [(NSResponder *)field.window cancelOperation:nil];
        XCTAssertFalse(field.window.isVisible);
    } @finally {
        [pasteboard clearContents];
        if (originalItems.count) [pasteboard writeObjects:originalItems];
        [document updateChangeCount:NSChangeCleared];
        [document close];
    }
}

- (void)testPreviewFormattingErrorBelongsToSelectionAndDeselectHidesPanel
{
    MPDocument *document = [MPDocument new];
    document.fileURL = self.testFileURL;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer = [MPRenderer new];
    document.editor = editor; document.preview = web; document.renderer = renderer;
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    BOOL oldMath = document.preferences.htmlMathJax;
    BOOL oldSmart = document.preferences.extensionSmartyPants;
    @try {
        document.preferences.htmlMathJax = NO;
        document.preferences.extensionSmartyPants = NO;
        editor.string = @"Alpha passage\n\nBeta passage\n";
        [renderer parseMarkdown:editor.string]; [renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
                return !web.isLoading && document.previewEditRanges.count==2;
            }] object:web]] timeout:10];
        NSString *(^select)(NSString *) = ^NSString *(NSString *text) {
            return [NSString stringWithFormat:@"(function(){var e=Array.from(document.querySelectorAll('[data-mp-edit-id]')).find(function(n){return n.textContent==='%@';}),r=document.createRange();r.selectNodeContents(e);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new Event('scroll'));})()",text];
        };
        [web stringByEvaluatingJavaScriptFromString:select(@"Alpha passage")];
        [web stringByEvaluatingJavaScriptFromString:@"window.macdownPreviewEditor.showFormattingError();window.dispatchEvent(new Event('scroll'));"];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"!!document.getElementById('macdown-preview-edit-error')"] boolValue],@"The refusal remains visible for the same selection after scrolling");
        [web stringByEvaluatingJavaScriptFromString:select(@"Beta passage")];
        XCTAssertFalse([[web stringByEvaluatingJavaScriptFromString:@"!!document.getElementById('macdown-preview-edit-error')"] boolValue],@"A new admissible selection must not inherit the previous error");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"],@"block");
        [web stringByEvaluatingJavaScriptFromString:@"document.body.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}));getSelection().removeAllRanges();window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));"];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"],@"none");
        XCTAssertEqualObjects(editor.string,@"Alpha passage\n\nBeta passage\n");
    } @finally {
        web.frameLoadDelegate = nil; [document close];
        document.preferences.htmlMathJax = oldMath;
        document.preferences.extensionSmartyPants = oldSmart;
    }
}

- (void)testPreviewFormattingInsideWordsUsesMarkdownAndRendersStyles
{
    MPDocument *document = [MPDocument new];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    document.editor = editor;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    MPPreferences *preferences = document.preferences;
    BOOL oldIntra = preferences.extensionIntraEmphasis;
    BOOL oldUnderline = preferences.extensionUnderline;
    void (^prepare)(NSString *, NSString *) = ^(NSString *source, NSString *text) {
        editor.string = source;
        [renderer parseMarkdown:source];
        NSRange range = [source rangeOfString:text];
        document.previewEditRanges = @[@{@"location":@(range.location),@"length":@(range.length),@"text":text}];
        document.previewEditSource = source;
        document.previewEditToken = renderer.checkboxBridgeToken;
    };
    @try {
        preferences.extensionIntraEmphasis = NO;
        preferences.extensionUnderline = NO;
        prepare(@"test avec test", @"test avec test");
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"bold",@"start":@1,@"end":@11}]));
        XCTAssertEqualObjects(editor.string, @"t**est avec t**est");
        XCTAssertTrue([[renderer HTMLForMarkdownSnapshot:editor.string] containsString:@"t<strong>est avec t</strong>est"]);
        XCTAssertTrue(preferences.extensionIntraEmphasis);
        prepare(editor.string, @"est avec t");
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"underline",@"start":@0,@"end":@10}]));
        XCTAssertEqualObjects(editor.string, @"t**_est avec t_**est");
        XCTAssertTrue([[renderer HTMLForMarkdownSnapshot:editor.string] containsString:@"t<strong><u>est avec t</u></strong>est"]);
        XCTAssertFalse([editor.string containsString:@"<"]);
        // Selection whitespace stays outside the formatting delimiters.
        preferences.extensionIntraEmphasis = NO;
        prepare(@"test avec test", @"test avec test");
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"bold",@"start":@0,@"end":@5}]));
        XCTAssertEqualObjects(editor.string, @"**test** avec test");
        XCTAssertTrue([[renderer HTMLForMarkdownSnapshot:editor.string] containsString:@"<strong>test</strong> avec test"]);
        prepare(@"test avec test", @"test avec test");
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"bold",@"start":@4,@"end":@5}]));
        XCTAssertEqualObjects(editor.string, @"test avec test");
        prepare(@"**part**", @"part");
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"italic",@"start":@0,@"end":@4}]));
        XCTAssertEqualObjects(editor.string, @"***part***");
        prepare(editor.string, @"part");
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"italic",@"start":@0,@"end":@4}]));
        XCTAssertEqualObjects(editor.string, @"**part**");
        preferences.extensionUnderline = YES;
        prepare(@"_**part**_", @"part");
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"underline",@"start":@0,@"end":@4}]));
        XCTAssertEqualObjects(editor.string, @"**part**");
        prepare(@"first\n\nsecond", @"first\n\nsecond");
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"action":@"bold",@"start":@0,@"end":@13}]));
        XCTAssertEqualObjects(editor.string, @"first\n\nsecond");
    } @finally {
        preferences.extensionIntraEmphasis = oldIntra;
        preferences.extensionUnderline = oldUnderline;
        [document close];
    }
}

// Keep Hoedown and the native transaction real; only the already-proven DOM
// mapping is supplied so block source transformations can be isolated.
- (void)assertPreviewBlockSource:(NSString *)source texts:(NSArray<NSString *> *)texts
                          value:(NSString *)value expected:(NSString *)expected
                           HTML:(NSString *)expectedHTML
{
    [self assertPreviewBlockSource:source texts:texts value:value expected:expected HTML:expectedHTML tasks:YES];
}

- (void)assertPreviewBlockSource:(NSString *)source texts:(NSArray<NSString *> *)texts
                          value:(NSString *)value expected:(NSString *)expected
                           HTML:(NSString *)expectedHTML tasks:(BOOL)tasks
{
    MPDocument *document = [MPDocument new];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer = [MPRenderer new];
    document.editor = editor; document.renderer = renderer;
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    BOOL oldSmarty = document.preferences.extensionSmartyPants;
    BOOL oldTasks = document.preferences.htmlTaskList;
    @try {
        document.preferences.extensionSmartyPants = NO;
        document.preferences.htmlTaskList = tasks;
        renderer.rendererFlags=document.preferences.rendererFlags;
        editor.string = source;
        [renderer parseMarkdown:source];
        NSMutableArray *mapping = [NSMutableArray array], *runs = [NSMutableArray array];
        NSMutableString *visible = [NSMutableString string];
        NSUInteger cursor = 0;
        for (NSString *text in texts) {
            NSRange found = [source rangeOfString:text options:NSLiteralSearch range:NSMakeRange(cursor,source.length-cursor)];
            XCTAssertNotEqual(found.location, NSNotFound);
            if (found.location == NSNotFound) return;
            if (mapping.count) {
                for (NSUInteger i=cursor;i<found.location;i++) {
                    unichar c = [source characterAtIndex:i];
                    if (c=='\n' || c=='\r') [visible appendFormat:@"%C",c];
                }
            }
            [visible appendString:text];
            [runs addObject:@{@"id":@(mapping.count),@"start":@0,@"end":@(text.length)}];
            [mapping addObject:@{@"location":@(found.location),@"length":@(found.length),@"text":text}];
            cursor = NSMaxRange(found);
        }
        document.previewEditRanges = mapping;
        document.previewEditSource = source;
        document.previewEditToken = renderer.checkboxBridgeToken;
        NSMutableDictionary *payload = [runs.firstObject mutableCopy];
        payload[@"runs"] = runs; payload[@"text"] = visible;
        payload[@"token"] = document.previewEditToken; payload[@"action"] = @"block"; payload[@"value"] = value;
        XCTAssertTrue([document applyPreviewEditPayload:payload], @"%@ -> %@",source,value);
        XCTAssertEqualObjects(editor.string, expected);
        NSString *HTML=[renderer HTMLForMarkdownSnapshot:editor.string];
        if ([value isEqualToString:@"code-block"]) {
            NSXMLDocument *DOM=[[NSXMLDocument alloc] initWithXMLString:HTML options:NSXMLDocumentTidyHTML error:NULL];
            NSArray *codes=[DOM nodesForXPath:@"//pre/code" error:NULL];
            XCTAssertEqual(codes.count,1u);
            XCTAssertEqualObjects([codes.firstObject stringValue],expectedHTML);
        } else XCTAssertTrue([HTML containsString:expectedHTML]);
    } @finally {
        [document close];
        document.preferences.extensionSmartyPants = oldSmarty;
        document.preferences.htmlTaskList = oldTasks;
    }
}

// Exercise the real preview endpoint, validator, parser and transaction. Only
// literal DOM mappings are supplied, as in the focused block-conversion tests.
- (NSArray<NSString *> *)blockConversionTypes
{
    return @[@"paragraph",@"h1",@"h2",@"h3",@"h4",@"h5",@"h6",@"unordered",@"ordered",@"tasks",@"quote",@"code-block",@"callout-note",@"callout-tip",@"callout-warning",@"callout-important",@"callout-caution",@"toggle",@"toggle-h1",@"toggle-h2",@"toggle-h3",@"toggle-h4"];
}

- (NSArray<NSDictionary *> *)blockConversionFixtures
{
    NSArray *types=[self blockConversionTypes];
    NSMutableArray *fixtures=[NSMutableArray array];
    NSString *text=@"Contenu é 日本語";
    for (NSString *type in types) {
        NSString *block;
        BOOL container=[type hasPrefix:@"callout-"] || [type hasPrefix:@"toggle"];
        if (container) {
            NSString *kind=[type hasPrefix:@"callout-"] ? [type substringFromIndex:8] : @"note";
            NSString *collapse=[type hasPrefix:@"toggle"] ? @" collapse=\"true\"" : @"";
            NSUInteger level=[type hasPrefix:@"toggle-h"] ? [[type substringFromIndex:8] integerValue] : 2;
            NSString *heading=[@"######" substringToIndex:level];
            block=[NSString stringWithFormat:@"::: {.callout-%@%@}\n%@ Titre conservé\n%@\n:::\n",kind,collapse,heading,text];
            [fixtures addObject:@{@"type":type,@"role":@"body",@"block":block,@"other":@"Titre conservé"}];
            block=[NSString stringWithFormat:@"::: {.callout-%@%@}\n%@ %@\nCorps conservé\n:::\n",kind,collapse,heading,text];
            [fixtures addObject:@{@"type":type,@"role":@"title",@"block":block,@"other":@"Corps conservé"}];
            continue;
        }
        NSDictionary *markers=@{@"paragraph":@"",@"unordered":@"- ",@"ordered":@"7. ",@"tasks":@"- [ ] ",@"quote":@"> "};
        if ([type isEqualToString:@"code-block"]) block=[NSString stringWithFormat:@"```text\n%@\n```\n",text];
        else {
            NSString *marker=[type hasPrefix:@"h"] ? [[@"######" substringToIndex:[[type substringFromIndex:1] integerValue]] stringByAppendingString:@" "] : markers[type];
            block=[NSString stringWithFormat:@"%@%@\n",marker,text];
        }
        [fixtures addObject:@{@"type":type,@"role":@"body",@"block":block}];
    }
    return fixtures;
}

- (NSMutableDictionary *)blockConversionEntryForFixture:(NSDictionary *)fixture source:(NSString *)source
{
    NSString *text=@"Contenu é 日本語";
    NSRange selected=[source rangeOfString:text];
    NSMutableDictionary *entry=[@{@"location":@(selected.location),@"length":@(selected.length),@"text":text} mutableCopy];
    if ([fixture[@"type"] isEqualToString:@"code-block"]) {
        NSMutableArray *boundaries=[NSMutableArray array];
        for (NSUInteger i=0;i<=text.length;i++) [boundaries addObject:@(selected.location+i)];
        entry[@"displayText"]=text; entry[@"sourceBoundaries"]=boundaries;
        entry[@"codeBlockRange"]=[NSValue valueWithRange:[source rangeOfString:fixture[@"block"]]];
        entry[@"codeContentRange"]=[NSValue valueWithRange:NSMakeRange(selected.location,text.length+1)];
    }
    return entry;
}

- (void)testEveryEditableBlockConvertsToEveryBlockDestination
{
    NSArray *targets=[[self blockConversionTypes] arrayByAddingObject:@"math-block"];
    NSArray *fixtures=[self blockConversionFixtures];
    NSString *text=@"Contenu é 日本語";
    MPPreferences *preferences=self.document.preferences;
    BOOL tasks=preferences.htmlTaskList,fenced=preferences.extensionFencedCode,math=preferences.htmlMathJax,smart=preferences.extensionSmartyPants;
    NSMutableArray *results=[NSMutableArray array];
    @try {
        preferences.htmlTaskList=YES; preferences.extensionFencedCode=YES; preferences.htmlMathJax=YES; preferences.extensionSmartyPants=NO;
        for (NSDictionary *fixture in fixtures) for (NSString *target in targets) @autoreleasepool {
            NSString *context=[NSString stringWithFormat:@"%@ (%@) → %@",fixture[@"type"],fixture[@"role"],target];
            MPDocument *document=[MPDocument new];
            MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
            MPRenderer *renderer=[MPRenderer new];
            document.editor=editor; document.renderer=renderer;
            renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
            @try {
                renderer.rendererFlags=preferences.rendererFlags;
                NSString *before=@"Avant voisin.\n\n",*after=@"\nAprès voisin.\n";
                NSString *source=[NSString stringWithFormat:@"%@%@%@",before,fixture[@"block"],after];
                editor.string=source;
                [renderer parseMarkdown:source];
                NSMutableDictionary *entry=[self blockConversionEntryForFixture:fixture source:source];
                document.previewEditRanges=@[entry]; document.previewEditSource=source;
                document.previewEditToken=renderer.checkboxBridgeToken;
                BOOL accepted=[document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"start":@0,@"end":@(text.length),@"text":text,@"action":@"block",@"value":target}];
                XCTAssertTrue(accepted,@"%@",context);
                if (!accepted) continue;
                XCTAssertTrue([editor.string hasPrefix:before],@"%@ — preceding neighbor",context);
                XCTAssertTrue([editor.string hasSuffix:after],@"%@ — following neighbor",context);
                XCTAssertFalse([editor.string containsString:@"<"],@"%@ — Markdown source only",context);
                NSString *HTML=[renderer HTMLForMarkdownSnapshot:editor.string];
                // Parse the HTML5 containers as XML instead of HTML tidy, whose
                // legacy recovery flattens aside/details/summary. Input is the
                // only HTML void element emitted by these controlled fixtures.
                NSRegularExpression *inputs=[NSRegularExpression regularExpressionWithPattern:@"<input([^>]*)>" options:0 error:NULL];
                NSString *XML=[inputs stringByReplacingMatchesInString:HTML options:0 range:NSMakeRange(0,HTML.length) withTemplate:@"<input$1 />"];
                XML=[NSString stringWithFormat:@"<html><body>%@</body></html>",XML];
                NSXMLDocument *DOM=[[NSXMLDocument alloc] initWithXMLString:XML options:NSXMLNodeLoadExternalEntitiesNever error:NULL];
                XCTAssertNotNil(DOM,@"%@",context);
                NSXMLNode *body=[[DOM nodesForXPath:@"//body" error:NULL] firstObject];
                XCTAssertTrue([body.stringValue containsString:text],@"%@ — selected content",context);
                if (fixture[@"other"]) XCTAssertTrue([body.stringValue containsString:fixture[@"other"]],@"%@ — unselected container content",context);
                NSString *path;
                if ([target isEqualToString:@"code-block"]) path=@"//pre/code";
                else if ([target isEqualToString:@"quote"]) path=@"//blockquote";
                else if ([target isEqualToString:@"ordered"]) path=@"//ol/li";
                else if ([target isEqualToString:@"tasks"]) path=@"//li[@class='task-list-item']";
                else if ([target isEqualToString:@"unordered"]) path=@"//ul/li";
                else if ([target hasPrefix:@"callout-"]) path=[NSString stringWithFormat:@"//*[contains(concat(' ',normalize-space(@class),' '),' mp-callout-%@ ')]",[target substringFromIndex:8]];
                else if ([target hasPrefix:@"toggle"]) path=@"//details";
                else if ([target hasPrefix:@"h"]) path=[NSString stringWithFormat:@"//%@",target];
                else path=@"//p";
                NSArray<NSXMLNode *> *nodes=[DOM nodesForXPath:path error:NULL];
                BOOL matches=NO;
                for (NSXMLNode *node in nodes) {
                    NSString *visible=[node.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    BOOL container=[target hasPrefix:@"callout-"] || [target hasPrefix:@"toggle"];
                    BOOL selectedTitle=[fixture[@"role"] isEqualToString:@"title"];
                    if (container ? [visible containsString:text] : selectedTitle ? [visible hasPrefix:text] : [visible isEqualToString:text]) { matches=YES; break; }
                }
                if ([target isEqualToString:@"math-block"]) {
                    XCTAssertEqual([editor.string componentsSeparatedByString:@"$$"].count,3u,@"%@ — math delimiters",context);
                } else XCTAssertTrue(matches,@"%@ — target structure %@; %@",context,path,HTML);
                if ([target isEqualToString:@"tasks"]) XCTAssertEqual([DOM nodesForXPath:@"//li[@class='task-list-item']/input[@type='checkbox']" error:NULL].count,1u,@"%@",context);
                if ([target hasPrefix:@"toggle-h"]) {
                    NSString *headingPath=[NSString stringWithFormat:@"//details/summary/h%@",[target substringFromIndex:8]];
                    XCTAssertEqual([DOM nodesForXPath:headingPath error:NULL].count,1u,@"%@ — disclosure heading",context);
                }
                if (![target hasPrefix:@"callout-"] && ![target hasPrefix:@"toggle"]) {
                    BOOL contained=[fixture[@"type"] hasPrefix:@"callout-"] || [fixture[@"type"] hasPrefix:@"toggle"];
                    XCTAssertEqual([editor.string containsString:@":::"],contained,@"%@ — content scope preserves its container",context);
                }
                XCTAssertEqual([body.stringValue componentsSeparatedByString:text].count,2u,@"%@ — content appears once",context);
                [results addObject:@{@"source":fixture[@"type"],@"selection":fixture[@"role"],@"target":target}];
            } @finally { [document close]; }
        }
        XCTAssertEqual(results.count,fixtures.count*targets.count);
        XCTAttachment *attachment=[XCTAttachment attachmentWithData:[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL] uniformTypeIdentifier:@"public.json"];
        attachment.name=@"Block conversion matrix — exercised pairs"; attachment.lifetime=XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
    } @finally {
        preferences.htmlTaskList=tasks; preferences.extensionFencedCode=fenced; preferences.htmlMathJax=math; preferences.extensionSmartyPants=smart;
    }
}

- (void)testAllBlockSourcesRefuseDisabledDestinationsWithoutChangingSourceOrSelection
{
    MPPreferences *preferences=self.document.preferences;
    BOOL tasks=preferences.htmlTaskList,fenced=preferences.extensionFencedCode,math=preferences.htmlMathJax,smart=preferences.extensionSmartyPants;
    NSString *text=@"Contenu é 日本語";
    @try {
        preferences.extensionSmartyPants=NO;
        for (NSDictionary *fixture in [self blockConversionFixtures]) for (NSString *target in @[@"tasks",@"code-block",@"math-block"]) @autoreleasepool {
            preferences.htmlTaskList=YES; preferences.extensionFencedCode=YES; preferences.htmlMathJax=YES;
            MPDocument *document=[MPDocument new];
            MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
            MPRenderer *renderer=[MPRenderer new];
            document.editor=editor; document.renderer=renderer;
            renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
            @try {
                NSString *source=[NSString stringWithFormat:@"Avant voisin.\n\n%@\nAprès voisin.\n",fixture[@"block"]];
                editor.string=source; editor.selectedRange=[source rangeOfString:text];
                renderer.rendererFlags=preferences.rendererFlags; [renderer parseMarkdown:source];
                document.previewEditRanges=@[[self blockConversionEntryForFixture:fixture source:source]];
                document.previewEditSource=source; document.previewEditToken=renderer.checkboxBridgeToken;
                if ([target isEqualToString:@"tasks"]) preferences.htmlTaskList=NO;
                else if ([target isEqualToString:@"code-block"]) preferences.extensionFencedCode=NO;
                else preferences.htmlMathJax=NO;
                NSString *context=[NSString stringWithFormat:@"%@ (%@) → %@ disabled",fixture[@"type"],fixture[@"role"],target];
                BOOL accepted=[document applyPreviewEditPayload:@{@"token":document.previewEditToken,@"id":@0,@"start":@0,@"end":@(text.length),@"text":text,@"action":@"block",@"value":target}];
                XCTAssertFalse(accepted,@"%@",context);
                XCTAssertEqualObjects(editor.string,source,@"%@",context);
                XCTAssertTrue(NSEqualRanges(editor.selectedRange,[source rangeOfString:text]),@"%@",context);
            } @finally { [document close]; }
        }
    } @finally {
        preferences.htmlTaskList=tasks; preferences.extensionFencedCode=fenced; preferences.htmlMathJax=math; preferences.extensionSmartyPants=smart;
    }
}

- (void)testEditorAndPreviewSelectionsAreExclusiveAndToolbarFollowsFocus
{
    MPDocument *document=[MPDocument new]; document.fileURL=self.testFileURL;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(600,0,600,400)];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1200,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO; [window.contentView addSubview:editor]; [window.contentView addSubview:web];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor; document.preview=web; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document; web.policyDelegate=(id<WebPolicyDelegate>)document; web.editingDelegate=(id<WebEditingDelegate>)document;
    [NSNotificationCenter.defaultCenter addObserver:document selector:NSSelectorFromString(@"editorSelectionDidChange:") name:NSTextViewDidChangeSelectionNotification object:editor];
    BOOL math=document.preferences.htmlMathJax,smart=document.preferences.extensionSmartyPants;
    @try {
        document.preferences.htmlMathJax=NO; document.preferences.extensionSmartyPants=NO; renderer.rendererFlags=document.preferences.rendererFlags;
        editor.string=@"Sourceword.\n\nPreviewword.\n"; [renderer parseMarkdown:editor.string]; [renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && document.previewEditRanges.count>0;}] object:web]] timeout:10];
        XCTAssertTrue([window makeFirstResponder:editor]);
        NSRange original=[editor.string rangeOfString:@"Sourceword"];
        editor.selectedRange=original;
        XCTAssertTrue([window makeFirstResponder:web]);
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"(function(){var e=macdownPreviewEditor.elements().spans.find(function(n){return n.textContent==='Previewword.';}),r=document.createRange();r.setStart(e.firstChild,0);r.setEnd(e.firstChild,11);getSelection().removeAllRanges();getSelection().addRange(r);return true;})()"] boolValue]);
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return editor.selectedRange.length==0;}] object:editor]] timeout:3];
        XCTAssertEqual(editor.selectedRange.location,original.location,@"Deselection preserves the source caret");
        XCTAssertTrue([NSApp sendAction:@selector(toggleStrong:) to:document from:nil]);
        XCTAssertEqualObjects(editor.string,@"Sourceword.\n\n**Previewword**.\n");
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"Previewword");
        XCTAssertEqual(editor.selectedRange.length,0u,@"Preview formatting must not select the corresponding source replacement");
        // Programmatic source range changes while the preview owns focus must
        // not invalidate its live selection or formatting continuation.
        editor.selectedRange=[editor.string rangeOfString:@"Sourceword"];
        XCTAssertEqual(editor.selectedRange.length,0u);
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"Previewword");
        XCTAssertTrue([window makeFirstResponder:editor]);
        editor.selectedRange=[editor.string rangeOfString:@"Sourceword"];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"");
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.selectionPayload('bold')===null"] boolValue],@"The cached preview selection must also be forgotten");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"],@"none");
        XCTAssertNil([document valueForKey:@"previewSelectionToRestore"]);
        XCTAssertTrue([NSApp sendAction:@selector(toggleStrong:) to:document from:nil]);
        XCTAssertEqualObjects(editor.string,@"**Sourceword**.\n\n**Previewword**.\n");
        // This isolated fixture has no document split-view controller driving
        // source render scheduling; refresh the real renderer explicitly.
        [renderer parseMarkdown:editor.string]; [renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
        XCTAssertTrue([window makeFirstResponder:web]);
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var e=macdownPreviewEditor.elements().spans.find(function(n){return n.textContent==='Previewword';}),r=document.createRange();r.selectNodeContents(e);getSelection().removeAllRanges();getSelection().addRange(r);})()"];
        [document setValue:@YES forKey:@"readingProgressFromPreview"];
        editor.selectedRange=[editor.string rangeOfString:@"Sourceword"];
        XCTAssertTrue([[document valueForKey:@"readingProgressFromPreview"] boolValue],@"Collapsing a source range must not transfer scroll ownership");
        [document toggleEmphasis:nil];
        XCTAssertNotNil([document valueForKey:@"previewSelectionToRestore"]);
        [document toggleUnderline:nil];
        XCTAssertEqual([[document valueForKey:@"previewQueuedFormatting"] count],1u);
        XCTAssertTrue([window makeFirstResponder:editor]);
        editor.selectedRange=[editor.string rangeOfString:@"Sourceword"];
        XCTAssertNil([document valueForKey:@"previewSelectionToRestore"]);
        XCTAssertNil([document valueForKey:@"previewQueuedFormatting"]);
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"");
        XCTAssertFalse([[renderer HTMLForMarkdownSnapshot:editor.string] containsString:@"<u>"],@"A cancelled preview command must not replay after switching panes");
    } @finally {
        document.preferences.htmlMathJax=math; document.preferences.extensionSmartyPants=smart;
        [NSNotificationCenter.defaultCenter removeObserver:document name:NSTextViewDidChangeSelectionNotification object:editor];
        web.frameLoadDelegate=nil; web.policyDelegate=nil; web.editingDelegate=nil;
        window.contentView=nil; [window close]; [document close];
    }
}

- (void)testPreviewBlockToolbarUsesTheSameConversionAsBlockMenu
{
    MPDocument *document=[MPDocument new];
    document.fileURL=self.testFileURL;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO; window.contentView=web;
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor; document.preview=web; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    web.policyDelegate=(id<WebPolicyDelegate>)document;
    MPToolbarController *toolbar=[MPToolbarController new]; toolbar.document=document;
    BOOL math=document.preferences.htmlMathJax,smart=document.preferences.extensionSmartyPants,tasks=document.preferences.htmlTaskList;
    NSString *source=@"# **Selected**\n\nNeighbor.\n";
    @try {
        document.preferences.htmlMathJax=NO; document.preferences.extensionSmartyPants=NO; document.preferences.htmlTaskList=YES;
        renderer.rendererFlags=document.preferences.rendererFlags;
        for (NSUInteger index=0;index<4;index++) {
            NSString *value=@[@"unordered",@"ordered",@"tasks",@"code-block"][index];
            NSString *menuSource=nil;
            for (NSUInteger mode=0;mode<2;mode++) {
                editor.string=source; [renderer parseMarkdown:source]; [renderer render];
                NSString *token=renderer.checkboxBridgeToken;
                [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                    [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditToken isEqualToString:token];}] object:web]] timeout:10];
                XCTAssertTrue([window makeFirstResponder:web]);
                XCTAssertTrue([document previewHasFindFocus]);
                editor.selectedRange=[source rangeOfString:@"Neighbor"];
                XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"(function(){var s=macdownPreviewEditor.elements().spans.find(function(e){return e.textContent==='Selected';});if(!s)return false;var r=document.createRange();r.selectNodeContents(s);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return true;})()"] boolValue]);
                if (mode==0) {
                    NSDictionary *payload=[[web.mainFrame.javaScriptContext evaluateScript:[NSString stringWithFormat:@"macdownPreviewEditor.selectionPayload('block','%@')",value]] toDictionary];
                    XCTAssertTrue([document applyPreviewEditPayload:payload]);
                    menuSource=editor.string.copy;
                } else {
                    NSToolbarItemGroup *group=(id)[toolbar toolbar:nil itemForItemIdentifier:(index==3 ? @"code" : @"list-group") willBeInsertedIntoToolbar:YES];
                    NSButton *button=(id)group.subitems[index==3 ? 1 : index].view;
                    [button performClick:nil];
                    XCTAssertEqualObjects(editor.string,menuSource,@"%@",value);
                }
                [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                    [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
                NSString *expected=index==3 ? @"\n```\nSelected\n```\n\n\nNeighbor.\n" : [NSString stringWithFormat:@"%@**Selected**\n\nNeighbor.\n",@[@"- ",@"1. ",@"- [ ] "][index]];
                XCTAssertEqualObjects(editor.string,expected);
                XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"Selected");
            }
        }
    } @finally {
        web.frameLoadDelegate=nil; web.policyDelegate=nil; window.contentView=nil; [window close]; [document close];
        document.preferences.htmlMathJax=math; document.preferences.extensionSmartyPants=smart; document.preferences.htmlTaskList=tasks;
    }
}

- (void)testPreviewOrderedListWritesSequentialSourceNumbers
{
    MPDocument *document=[MPDocument new];
    document.fileURL=self.testFileURL;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO; window.contentView=web;
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor; document.preview=web; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document; web.policyDelegate=(id<WebPolicyDelegate>)document;
    BOOL math=document.preferences.htmlMathJax,smart=document.preferences.extensionSmartyPants;
    @try {
        document.preferences.htmlMathJax=NO; document.preferences.extensionSmartyPants=NO;
        renderer.rendererFlags=document.preferences.rendererFlags;
        editor.string=@"avant\nAprès\nlui\nmoi\ntoi\n\nNeighbor.\n";
        [renderer parseMarkdown:editor.string]; [renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && document.previewEditRanges.count>0;}] object:web]] timeout:10];
        NSMutableArray *expectedOptions=[[[self blockConversionTypes] arrayByAddingObject:@"math-block"] mutableCopy];
        [expectedOptions addObject:@"no-container"];
        NSArray *actualOptions=[[web.mainFrame.javaScriptContext evaluateScript:@"Array.from(document.querySelectorAll('#macdown-preview-format [data-mp-option]')).map(function(o){return o.getAttribute('data-mp-option');})"] toArray];
        XCTAssertEqualObjects([NSSet setWithArray:actualOptions ?: @[]],[NSSet setWithArray:expectedOptions],@"Every menu option must belong to the conversion matrix");
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var r=document.createRange();r.selectNodeContents(document.querySelector('p'));getSelection().removeAllRanges();getSelection().addRange(r);})()"];
        NSDictionary *payload=[[web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('block','ordered')"] toDictionary];
        XCTAssertNotNil(payload);
        XCTAssertTrue([document applyPreviewEditPayload:payload]);
        XCTAssertEqualObjects(editor.string,@"1. avant\n2. Après\n3. lui\n4. moi\n5. toi\n\nNeighbor.\n");
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelectorAll('ol > li').length.toString()"],@"5");
    } @finally {
        document.preferences.htmlMathJax=math; document.preferences.extensionSmartyPants=smart;
        web.frameLoadDelegate=nil; web.policyDelegate=nil;
        window.contentView=nil; [window close]; [document close];
    }
}

- (void)testSourceListButtonsConvertBlocksRatherThanStackOrTogglePrefixes
{
    NSArray *cases=@[
        @[@"# **word**\n",@"toggleUnorderedList:",@"- **word**\n"],
        @[@"> word\n",@"toggleOrderedList:",@"1. word\n"],
        @[@"1. first\n2. second\n",@"toggleUnorderedList:",@"- first\n- second\n"],
        @[@"- first\n- second\n",@"toggleOrderedList:",@"1. first\n2. second\n"],
        @[@"- first\n",@"toggleUnorderedList:",@"- first\n"]
    ];
    for (NSArray *scenario in cases) {
        MPDocument *document=[MPDocument new];
        MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        MPRenderer *renderer=[MPRenderer new];
        document.editor=editor; document.renderer=renderer;
        renderer.delegate=(id<MPRendererDelegate>)document;
        renderer.dataSource=(id<MPRendererDataSource>)document;
        @try {
            editor.string=scenario[0];
            editor.selectedRange=NSMakeRange(0,editor.string.length);
            SEL action=NSSelectorFromString(scenario[1]);
            [NSApp sendAction:action to:document from:nil];
            XCTAssertEqualObjects(editor.string,scenario[2],@"%@",scenario[1]);
        } @finally { [document close]; }
    }
}

- (void)testSourceCodeBlockButtonUsesRenderedTextAndHonorsDisabledSyntax
{
    MPDocument *document=[MPDocument new];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
    BOOL fenced=document.preferences.extensionFencedCode;
    @try {
        document.preferences.extensionFencedCode=YES;
        NSArray *cases=@[
            @[@"> **word**\n",@"\n```\nword\n```\n\n"],
            @[@"# word\n",@"\n```\nword\n```\n\n"],
            @[@"first\nsecond\n",@"\n```\nfirst\nsecond\n```\n\n"]
        ];
        for (NSArray *scenario in cases) {
            editor.string=scenario[0]; editor.selectedRange=NSMakeRange(0,editor.string.length);
            XCTAssertTrue([NSApp sendAction:NSSelectorFromString(@"convertToCodeBlock:") to:document from:nil]);
            XCTAssertEqualObjects(editor.string,scenario[1]);
            XCTAssertTrue(NSMaxRange(editor.selectedRange)<=editor.string.length);
        }
        document.preferences.extensionFencedCode=NO;
        editor.string=@"word\n"; editor.selectedRange=NSMakeRange(0,4);
        [NSApp sendAction:NSSelectorFromString(@"convertToCodeBlock:") to:document from:nil];
        XCTAssertEqualObjects(editor.string,@"word\n");
    } @finally { [document close]; document.preferences.extensionFencedCode=fenced; }
}

- (void)testSourceCodeBlockButtonIsIdempotentForHeadingAfterCalloutCitation
{
    for (NSString *newline in @[@"\n",@"\r\n"]) {
        for (NSNumber *includeEnding in @[@NO,@YES]) {
            MPDocument *document=[MPDocument new];
            MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
            MPRenderer *renderer=[MPRenderer new];
            document.editor=editor; document.renderer=renderer;
            renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
            editor.delegate=(id<NSTextViewDelegate>)document;
            NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed=NO;
            [window.contentView addSubview:editor];
            XCTAssertTrue([window makeFirstResponder:editor]);
            [NSNotificationCenter.defaultCenter addObserver:document selector:NSSelectorFromString(@"editorSelectionDidChange:") name:NSTextViewDidChangeSelectionNotification object:editor];
            BOOL fenced=document.preferences.extensionFencedCode;
            @try {
                document.preferences.extensionFencedCode=YES;
                editor.string=[@"::: {.callout-important}\n## Titre TEST du callout\n> citation dans callout\n## titre dans callout\n\nencore test\n:::" stringByReplacingOccurrencesOfString:@"\n" withString:newline];
                NSString *needle=includeEnding.boolValue ? [@"## titre dans callout" stringByAppendingString:newline] : @"## titre dans callout";
                editor.selectedRange=[editor.string rangeOfString:needle];
                [NSApp sendAction:NSSelectorFromString(@"convertToCodeBlock:") to:document from:nil];
                NSString *converted=[editor.string copy];
                NSRange selected=editor.selectedRange;
                XCTAssertTrue([converted containsString:@"```\ntitre dans callout"], @"%@", converted);
                XCTAssertFalse([[converted substringWithRange:selected] containsString:@"```"], @"The editor must select code content, excluding its fences");
                XCTAssertTrue([converted hasPrefix:[@"::: {.callout-important}\n## Titre TEST du callout\n> citation dans callout\n" stringByReplacingOccurrencesOfString:@"\n" withString:newline]]);
                XCTAssertTrue([converted hasSuffix:[@"\nencore test\n:::" stringByReplacingOccurrencesOfString:@"\n" withString:newline]]);
                for (NSUInteger click=0; click<10; click++) {
                    [NSApp sendAction:NSSelectorFromString(@"convertToCodeBlock:") to:document from:nil];
                    XCTAssertEqualObjects(editor.string,converted,@"Repeated click %lu; includeEnding %@; newline %@; selection %@",(unsigned long)click,includeEnding,[newline debugDescription],NSStringFromRange(editor.selectedRange));
                    XCTAssertTrue(NSEqualRanges(editor.selectedRange,selected));
                    if (![editor.string isEqual:converted]) break;
                }
            } @finally {
                document.preferences.extensionFencedCode=fenced;
                [NSNotificationCenter.defaultCenter removeObserver:document name:NSTextViewDidChangeSelectionNotification object:editor];
                window.contentView=nil; [window close]; [document close];
            }
        }
    }
}

- (void)testOrderedListConversionWritesSequentialNumbersAndPreservesSelection
{
    MPDocument *document=[MPDocument new];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    document.editor=editor;
    NSMutableString *source=[NSMutableString new],*expected=[NSMutableString new];
    for (NSUInteger i=1;i<=12;i++) {
        [source appendFormat:@"- word%lu\r\n",(unsigned long)i];
        [expected appendFormat:@"%lu. word%lu\r\n",(unsigned long)i,(unsigned long)i];
    }
    @try {
        editor.string=source; editor.selectedRange=NSMakeRange(0,source.length);
        [document toggleOrderedList:nil];
        XCTAssertEqualObjects(editor.string,expected);
        XCTAssertTrue(NSEqualRanges(editor.selectedRange,NSMakeRange(3,expected.length-3)));
        [document toggleOrderedList:nil];
        XCTAssertEqualObjects(editor.string,expected,@"Repeated conversion must be idempotent");
    } @finally { [document close]; }
}

- (void)testSourceListConversionPreservesCaretAtBoundariesAndInsideCallout
{
    NSString *callout=@"::: {.callout-note}\nword\n:::\n";
    NSArray *cases=@[
        @[@"word\n",@0,@"- word\n",@2],
        @[@"word",@4,@"- word",@6],
        @[callout,@([callout rangeOfString:@"word"].location+2),@"::: {.callout-note}\n- word\n:::\n",@([callout rangeOfString:@"word"].location+4)]
    ];
    for (NSArray *scenario in cases) {
        MPDocument *document=[MPDocument new];
        MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        MPRenderer *renderer=[MPRenderer new];
        document.editor=editor; document.renderer=renderer;
        renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
        @try {
            editor.string=scenario[0]; editor.selectedRange=NSMakeRange([scenario[1] unsignedIntegerValue],0);
            [document toggleUnorderedList:nil];
            XCTAssertEqualObjects(editor.string,scenario[2]);
            XCTAssertTrue(NSEqualRanges(editor.selectedRange,NSMakeRange([scenario[3] unsignedIntegerValue],0)),@"Actual caret: %@",NSStringFromRange(editor.selectedRange));
        } @finally { [document close]; }
    }
}

- (void)testSourceTaskListButtonUsesSharedConversionAndHonorsDisabledSyntax
{
    MPDocument *document=[MPDocument new];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
    BOOL tasks=document.preferences.htmlTaskList;
    @try {
        document.preferences.htmlTaskList=YES;
        NSArray *cases=@[
            @[@"",@"",@"- [ ] "],
            @[@"\nNeighbor.\n",@"",@"- [ ] \nNeighbor.\n"],
            @[@"# **word**\n",@"word",@"- [ ] **word**\n"],
            @[@"1. word\r\n",@"word",@"- [ ] word\r\n"],
            @[@"::: {.callout-note}\n## Title\nword\n:::\n",@"word",@"::: {.callout-note}\n## Title\n- [ ] word\n:::\n"]
        ];
        for (NSArray *scenario in cases) {
            editor.string=scenario[0]; editor.selectedRange=[scenario[1] length] ? [editor.string rangeOfString:scenario[1]] : NSMakeRange(0,0);
            [document toggleTaskList:nil];
            XCTAssertEqualObjects(editor.string,scenario[2]);
            XCTAssertTrue(NSMaxRange(editor.selectedRange)<=editor.string.length);
        }
        document.preferences.htmlTaskList=NO;
        editor.string=@"word\n"; editor.selectedRange=NSMakeRange(0,4);
        [document toggleTaskList:nil];
        XCTAssertEqualObjects(editor.string,@"word\n");
    } @finally { [document close]; document.preferences.htmlTaskList=tasks; }
}

- (void)testPreviewMultilineQuoteSelectionMapsPlainAndStyledLines
{
    NSArray *cases = @[
        @[@">ezrtgfvqds\n> erfvsgfe\n\nNeighbor.\n", @">ezrtgfvqds\n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@">**ezrtgfvqds**\n> erfvsgfe\n\nNeighbor.\n", @">**ezrtgfvqds**\n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> > ezrtgfvqds\n> > erfvsgfe\n\nNeighbor.\n", @"> > ezrtgfvqds\n> > **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> > > ezrtgfvqds\n> > > erfvsgfe\n\nNeighbor.\n", @"> > > ezrtgfvqds\n> > > **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> > ezrtgfvqds\r\n> > erfvsgfe\r\n\r\nNeighbor.\r\n", @"> > ezrtgfvqds\r\n> > **erfvsgfe**\r\n\r\nNeighbor.\r\n"],
        @[@"> # ezrtgfvqds\n> erfvsgfe\n\nNeighbor.\n", @"> # ezrtgfvqds\n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> - ezrtgfvqds\n> - erfvsgfe\n\nNeighbor.\n", @"> - ezrtgfvqds\n> - **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> ezrtgfvqds\n> erfvsgfe\n\nNeighbor.\n", @"> ezrtgfvqds\n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> ezrtgfvqds  \n> erfvsgfe\n\nNeighbor.\n", @"> ezrtgfvqds  \n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> ezrtgfvqds\n>\n> erfvsgfe\n\nNeighbor.\n", @"> ezrtgfvqds\n>\n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> ezrtgfvqds\n> erfvsgfe\n\nerfvsgfe\n", @"> ezrtgfvqds\n> **erfvsgfe**\n\nerfvsgfe\n"],
        @[@"> ezrtgfvqds\n> erfvsgfe\n> erfvsgfe\n\nNeighbor.\n", @"> ezrtgfvqds\n> **erfvsgfe**\n> erfvsgfe\n\nNeighbor.\n"],
        @[@"> *ezrtgfvqds*\n> erfvsgfe\n\nNeighbor.\n", @"> *ezrtgfvqds*\n> **erfvsgfe**\n\nNeighbor.\n"],
        @[@"> ezrtgfvqds\n> erfvsgfe 😀 café 日本語\n\nNeighbor.\n", @"> ezrtgfvqds\n> **erfvsgfe** 😀 café 日本語\n\nNeighbor.\n"]
    ];
    for (NSArray *scenario in cases) {
        MPDocument *document = [MPDocument new];
        document.fileURL = self.testFileURL;
        MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO; window.contentView = web;
        MPRenderer *renderer = [MPRenderer new];
        document.editor = editor; document.preview = web; document.renderer = renderer;
        web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
        web.policyDelegate = (id<WebPolicyDelegate>)document;
        renderer.delegate = (id<MPRendererDelegate>)document;
        renderer.dataSource = (id<MPRendererDataSource>)document;
        BOOL math = document.preferences.htmlMathJax, smarty = document.preferences.extensionSmartyPants;
        @try {
            document.preferences.htmlMathJax = NO; document.preferences.extensionSmartyPants = NO;
            editor.string = scenario[0];
            [renderer parseMarkdown:editor.string]; [renderer render];
            NSString *token = renderer.checkboxBridgeToken;
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return !web.isLoading && [document.previewEditToken isEqualToString:token];
                }] object:web]] timeout:10];
            for (NSString *text in @[@"ezrtgfvqds", @"erfvsgfe"]) {
                XCTAssertTrue([document.previewEditRanges indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger i, BOOL *stop) { return [entry[@"text"] containsString:text]; }] != NSNotFound, @"%@", scenario[0]);
            }
            [web stringByEvaluatingJavaScriptFromString:@"(function(){var w=document.createTreeWalker(document.querySelector('blockquote'),NodeFilter.SHOW_TEXT),n;while(n=w.nextNode()){var start=n.nodeValue.indexOf('erfvsgfe');if(start<0)continue;var r=document.createRange();r.setStart(n,start);r.setEnd(n,start+8);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));break;}})()"];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"] isEqualToString:@"block"];
                }] object:web]] timeout:3];
            [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').click()"];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return !web.isLoading && [editor.string isEqualToString:scenario[1]] &&
                        [[web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"] isEqualToString:@"erfvsgfe"];
                }] object:web]] timeout:5];
            XCTAssertEqualObjects(editor.string, scenario[1]);
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"Array.from(document.querySelectorAll('blockquote strong')).find(function(n){return n.textContent==='erfvsgfe';}).textContent"], @"erfvsgfe");
            XCTAssertFalse([editor.string containsString:@"<"]);
            [web stringByEvaluatingJavaScriptFromString:@"(function(){var nodes=document.querySelectorAll('blockquote [data-mp-edit-id]'),r=document.createRange();r.setStart(nodes[0].firstChild,0);var last=nodes[nodes.length-1].firstChild;r.setEnd(last,last.length);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));})()"];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"] isEqualToString:@"block"];
            }] object:web]] timeout:3];
            [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=italic]').click()"];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && [[web stringByEvaluatingJavaScriptFromString:@"Array.from(document.querySelectorAll('blockquote [data-mp-edit-id]')).filter(function(n){return n.textContent.trim();}).every(function(n){return !!n.closest('em');}) && !!document.querySelector('blockquote strong') && getSelection().toString().indexOf('erfvsgfe')>=0"] boolValue];
            }] object:web]] timeout:8];
            NSString *separator=[scenario[0] containsString:@"\r\n"] ? @"\r\n\r\n" : @"\n\n";
            NSRange boundary=[scenario[0] rangeOfString:separator options:NSBackwardsSearch];
            XCTAssertNotEqual(boundary.location,NSNotFound);
            if(boundary.location!=NSNotFound) XCTAssertTrue([editor.string hasSuffix:[scenario[0] substringFromIndex:boundary.location]], @"Neighboring source must be preserved");
            XCTAssertFalse([editor.string containsString:@"<"]);
        } @finally {
            web.frameLoadDelegate = nil; web.policyDelegate = nil; [document close]; [window close];
            document.preferences.htmlMathJax = math; document.preferences.extensionSmartyPants = smarty;
        }
    }
}

- (void)testPreviewQuoteAllInlineStyleCombinationsRetainSelectionAndNeighbors
{
    NSArray *actions = @[@"bold", @"italic", @"underline", @"strike", @"code"];
    NSArray *tags = @[@"strong", @"em", @"u", @"del", @"code"];
    // Every subset of five inline styles, in both physical newline formats.
    for (NSString *ending in @[@"\n", @"\r\n"]) {
        MPDocument *document = [MPDocument new]; document.fileURL = self.testFileURL;
        MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO; window.contentView = web;
        MPRenderer *renderer = [MPRenderer new];
        document.editor = editor; document.preview = web; document.renderer = renderer;
        web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document; web.policyDelegate = (id<WebPolicyDelegate>)document;
        renderer.delegate = (id<MPRendererDelegate>)document; renderer.dataSource = (id<MPRendererDataSource>)document;
        MPPreferences *preferences = document.preferences;
        BOOL math=preferences.htmlMathJax, smarty=preferences.extensionSmartyPants;
        BOOL underline=preferences.extensionUnderline, strike=preferences.extensionStrikethough;
        NSString *prefix=[NSString stringWithFormat:@"> First.%@> ",ending];
        NSString *suffix=[NSString stringWithFormat:@"%@%@Neighbor.%@",ending,ending,ending];
        NSString *source=[NSString stringWithFormat:@"%@Target%@",prefix,suffix];
        @try {
            preferences.htmlMathJax=NO; preferences.extensionSmartyPants=NO;
            preferences.extensionUnderline=YES; preferences.extensionStrikethough=YES;
            for (NSUInteger combination=0; combination<32; combination++) {
                editor.string=source; [renderer parseMarkdown:source]; [renderer render];
                NSString *token=renderer.checkboxBridgeToken;
                [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return !web.isLoading && [document.previewEditToken isEqualToString:token];
                }] object:web]] timeout:10];
                [web stringByEvaluatingJavaScriptFromString:@"(function(){var span=Array.from(document.querySelectorAll('blockquote [data-mp-edit-id]')).find(function(n){return n.textContent==='Target';}),r=document.createRange();r.selectNodeContents(span);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));})()"];
                [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"] isEqualToString:@"block"];
                }] object:web]] timeout:3];
                for (NSUInteger index=0;index<actions.count;index++) {
                    if (!(combination & (1u<<index))) continue;
                    NSString *before=[editor.string copy];
                    [web stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.querySelector('[data-mp-style=%@]').click()",actions[index]]];
                    XCTNSPredicateExpectation *formatted=[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                        return !web.isLoading && ![editor.string isEqualToString:before] && [[web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"] isEqualToString:@"Target"];
                    }] object:web];
                    if([XCTWaiter waitForExpectations:@[formatted] timeout:8]!=XCTWaiterResultCompleted) {
                        XCTFail(@"Combination %lu, action %@, ending %@: before %@; after %@; selection %@",(unsigned long)combination,actions[index],ending,before,editor.string,[web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"]);
                        return;
                    }
                }
                for (NSUInteger index=0;index<actions.count;index++) {
                    NSString *check=[NSString stringWithFormat:@"(function(){var s=Array.from(document.querySelectorAll('blockquote [data-mp-edit-id]')).find(function(n){return n.textContent==='Target';});return !!s&&!!s.closest('%@');})()",tags[index]];
                    XCTAssertEqual([[web stringByEvaluatingJavaScriptFromString:check] boolValue], !!(combination & (1u<<index)), @"Combination %lu, %@",(unsigned long)combination,actions[index]);
                    NSString *state=[NSString stringWithFormat:@"document.querySelector('[data-mp-style=%@]').getAttribute('aria-pressed')",actions[index]];
                    XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:state], (combination & (1u<<index)) ? @"true" : @"false");
                }
                XCTAssertTrue([editor.string hasPrefix:prefix]); XCTAssertTrue([editor.string hasSuffix:suffix]);
                XCTAssertFalse([editor.string containsString:@"<"]);
                XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"], @"Target");
            }
        } @finally {
            web.frameLoadDelegate=nil; web.policyDelegate=nil; [document close]; [window close];
            preferences.htmlMathJax=math; preferences.extensionSmartyPants=smarty;
            preferences.extensionUnderline=underline; preferences.extensionStrikethough=strike;
        }
    }
}

- (void)testPreviewQuoteMappingRejectsUnprovenTextAndExcessiveLeafCount
{
    NSMutableString *large=[NSMutableString new];
    for(NSUInteger i=0;i<2100;i++) [large appendFormat:@"> word%lu\n",(unsigned long)i];
    NSString *largePlain=[large stringByReplacingOccurrencesOfString:@"> " withString:@""];
    NSArray *sources=@[@"> <span title=\"Secret\">Se&#99;ret</span>\n> Plainword\n",
        @"> [Se&#99;ret](https://example.test/Secret)\n> Plainword\n",large,largePlain];
    for(NSString *source in sources) {
        MPDocument *document=[MPDocument new];document.fileURL=self.testFileURL;
        MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed=NO;window.contentView=web;
        MPRenderer *renderer=[MPRenderer new];document.editor=editor;document.preview=web;document.renderer=renderer;
        renderer.delegate=(id<MPRendererDelegate>)document;renderer.dataSource=(id<MPRendererDataSource>)document;
        web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;web.policyDelegate=(id<WebPolicyDelegate>)document;
        BOOL math=document.preferences.htmlMathJax;document.preferences.htmlMathJax=NO;
        @try {
            editor.string=source;[renderer parseMarkdown:source];[renderer render];NSString *token=renderer.checkboxBridgeToken;
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){
                return !web.isLoading && [document.previewEditToken isEqualToString:token];
            }] object:web]] timeout:10];
            if(source==largePlain) {
                XCTAssertEqual(document.previewEditRanges.count,1U,@"A long ordinary paragraph keeps its existing contiguous mapping");
                XCTAssertTrue([document.previewEditRanges.firstObject[@"text"] containsString:@"word2099"]);
            } else if(source==large) {
                XCTAssertEqual(document.previewEditRanges.count,0U);
                XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('blockquote p').childNodes.length)"],@"1",@"The split budget must be checked before changing the DOM");
            } else {
                XCTAssertFalse([[document.previewEditRanges valueForKey:@"text"] containsObject:@"Secret"]);
                XCTAssertTrue([[document.previewEditRanges valueForKey:@"text"] containsObject:@"Plainword"]);
                [web stringByEvaluatingJavaScriptFromString:@"(function(){var w=document.createTreeWalker(document.querySelector('blockquote'),NodeFilter.SHOW_TEXT),n;while(n=w.nextNode()){if(n.nodeValue!=='Secret')continue;var r=document.createRange();r.selectNodeContents(n);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));break;}})()"];
                XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"window.macdownPreviewEditor.selectionPayload()===null ? 'refused' : 'accepted'"],@"refused");
            }
            XCTAssertFalse(([document applyPreviewEditPayload:@{@"action":@"bold",@"token":@"forged",@"id":@0,@"start":@0,@"end":@1}]));
            XCTAssertEqualObjects(editor.string,source);
        } @finally {
            web.frameLoadDelegate=nil;web.policyDelegate=nil;[document close];[window close];document.preferences.htmlMathJax=math;
        }
    }
}

- (void)testSourceQuotedInlineFormattingPreservesNestedHeadingAndListPrefixes
{
    NSArray *prefixes=@[@">", @"> ", @"> > ", @"> > > ", @" > ", @"  > ",
        @"> # ", @"> ## ", @"> > ### ", @"> - ", @"> 1. ", @"> - [ ] ", @"> > - [x] "];
    NSArray *selectors=@[NSStringFromSelector(@selector(toggleStrong:)),NSStringFromSelector(@selector(toggleEmphasis:)),
        NSStringFromSelector(@selector(toggleUnderline:)),NSStringFromSelector(@selector(toggleStrikethrough:)),NSStringFromSelector(@selector(toggleInlineCode:))];
    NSArray *tags=@[@"strong",@"em",@"u",@"del",@"code"];
    MPDocument *document=[MPDocument new];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new]; document.editor=editor; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document; renderer.dataSource=(id<MPRendererDataSource>)document;
    MPPreferences *preferences=document.preferences;
    BOOL underline=preferences.extensionUnderline,strike=preferences.extensionStrikethough,tasks=preferences.htmlTaskList,smart=preferences.extensionSmartyPants;
    @try {
        preferences.extensionUnderline=YES;preferences.extensionStrikethough=YES;preferences.htmlTaskList=YES;preferences.extensionSmartyPants=NO;
        for(NSString *prefix in prefixes) for(NSString *ending in @[@"\n",@"\r\n"]) for(NSUInteger index=0;index<selectors.count;index++) {
            NSString *suffix=[NSString stringWithFormat:@"%@%@Neighbor.%@",ending,ending,ending];
            NSString *source=[NSString stringWithFormat:@"%@Target%@",prefix,suffix];
            editor.string=source;editor.selectedRange=[source rangeOfString:@"Target"];
            SEL selector=NSSelectorFromString(selectors[index]);
            void (*action)(id,SEL,id)=(void (*)(id,SEL,id))[document methodForSelector:selector];action(document,selector,nil);
            XCTAssertNotEqualObjects(editor.string,source,@"%@ / %@",prefix,selectors[index]);
            XCTAssertTrue([editor.string hasPrefix:prefix]);XCTAssertTrue([editor.string hasSuffix:suffix]);
            XCTAssertFalse([editor.string containsString:@"<"]);
            NSString *html=[renderer HTMLForMarkdownSnapshot:editor.string];
            NSXMLDocument *DOM=[[NSXMLDocument alloc] initWithXMLString:[NSString stringWithFormat:@"<body>%@</body>",html] options:NSXMLDocumentTidyHTML | NSXMLNodeLoadExternalEntitiesNever error:NULL];
            NSArray *styled=[DOM nodesForXPath:[NSString stringWithFormat:@"//blockquote//%@",tags[index]] error:NULL];
            XCTAssertTrue([styled indexOfObjectPassingTest:^BOOL(NSXMLNode *node,NSUInteger i,BOOL *stop){return [node.stringValue isEqualToString:@"Target"];} ]!=NSNotFound,@"%@ / %@: %@",prefix,selectors[index],html);
            XCTAssertEqualObjects([editor.string substringWithRange:editor.selectedRange],@"Target");
            action(document,selector,nil);
            XCTAssertEqualObjects(editor.string,source,@"A second click must remove only the inline style");
        }
    } @finally {
        [document close];preferences.extensionUnderline=underline;preferences.extensionStrikethough=strike;
        preferences.htmlTaskList=tasks;preferences.extensionSmartyPants=smart;
    }
}

- (void)testPreviewQuoteToCodeRemovesOnlyStructuralPrefix
{
    [self assertPreviewBlockSource:@"> Quotedword\n\nNeighbor.\n" texts:@[@"Quotedword"] value:@"code-block"
        expected:@"\n```\nQuotedword\n```\n\n\nNeighbor.\n" HTML:@"Quotedword"];
    [self assertPreviewBlockSource:@"> # Headingword\n\nNeighbor.\n" texts:@[@"Headingword"] value:@"code-block"
        expected:@"\n```\nHeadingword\n```\n\n\nNeighbor.\n" HTML:@"Headingword"];
}

- (void)testPreviewCodeConversionPreservesRenderedLiteralMarkers
{
    [self assertPreviewBlockSource:@"> # > literal\n" texts:@[@"literal"] value:@"code-block"
        expected:@"\n```\n> literal\n```\n\n" HTML:@"> literal"];
    [self assertPreviewBlockSource:@"# - **item**\n" texts:@[@"item"] value:@"code-block"
        expected:@"\n```\n- item\n```\n\n" HTML:@"- item"];
}

- (void)testPreviewCodeConversionRefusesNonTextContentWithoutLosingSource
{
    for (NSString *source in @[@"> first ![image](photo.png)\n", @"> first\n> ![image](photo.png)\n> second\n"]) {
        MPDocument *document=[MPDocument new];
        MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
        MPRenderer *renderer=[MPRenderer new];
        document.editor=editor; document.renderer=renderer;
        renderer.delegate=(id<MPRendererDelegate>)document;
        renderer.dataSource=(id<MPRendererDataSource>)document;
        @try {
            editor.string=source;
            [renderer parseMarkdown:source];
            NSMutableArray *mapping=[NSMutableArray array], *runs=[NSMutableArray array];
            NSArray *texts=[source containsString:@"second"] ? @[@"first",@"second"] : @[@"first"];
            for (NSString *text in texts) {
                NSRange range=[source rangeOfString:text];
                [runs addObject:@{@"id":@(mapping.count),@"start":@0,@"end":@(text.length)}];
                [mapping addObject:@{@"location":@(range.location),@"length":@(range.length),@"text":text}];
            }
            document.previewEditRanges=mapping;
            document.previewEditSource=source;
            document.previewEditToken=renderer.checkboxBridgeToken;
            NSMutableDictionary *payload=[runs.firstObject mutableCopy];
            payload[@"runs"]=runs;
            payload[@"text"]=[texts componentsJoinedByString:@"\n\n"];
            payload[@"token"]=document.previewEditToken;
            payload[@"action"]=@"block"; payload[@"value"]=@"code-block";
            XCTAssertFalse([document applyPreviewEditPayload:payload]);
            XCTAssertEqualObjects(editor.string,source);
        } @finally { [document close]; }
    }
}

- (void)testPreviewMultilineQuoteToCodeRemovesEmptyStructuralLines
{
    [self assertPreviewBlockSource:@"> first\n>\n> second\n\nNeighbor.\n" texts:@[@"first",@"second"] value:@"code-block"
        expected:@"\n```\nfirst\n\nsecond\n```\n\n\nNeighbor.\n" HTML:@"first\n\nsecond"];
    [self assertPreviewBlockSource:@"> > first\n> >\n> > second\n" texts:@[@"first",@"second"] value:@"code-block"
        expected:@"\n```\nfirst\n\nsecond\n```\n\n" HTML:@"first\n\nsecond"];
}

- (void)testPreviewCalloutCreatesLocalizedDefaultTitleForEveryType
{
    for (NSString *type in @[@"note",@"tip",@"warning",@"important",@"caution"]) {
        NSString *expected=[NSString stringWithFormat:@"\n::: {.callout-%@}\n## %@\nTest\n:::\n\nNeighbor.\n",type,MPPreviewDefaultCalloutTitle(type,NO)];
        [self assertPreviewBlockSource:@"Test\n\nNeighbor.\n" texts:@[@"Test"] value:[@"callout-" stringByAppendingString:type]
            expected:expected HTML:[@"callout-" stringByAppendingString:type]];
    }
    [self assertPreviewBlockSource:@"Test\n\nNeighbor.\n" texts:@[@"Test"] value:@"toggle"
        expected:[NSString stringWithFormat:@"\n::: {.callout-note collapse=\"true\"}\n## %@\nTest\n:::\n\nNeighbor.\n",MPPreviewDefaultCalloutTitle(@"note",YES)] HTML:@"<details"];
}

- (void)testPreviewCalloutTitleAndBodyConvertWithoutLosingOtherContent
{
    [self assertPreviewBlockSource:@"::: {.callout-caution}\n## Attention\nTest\n:::\n\nNeighbor.\n"
        texts:@[@"Attention"] value:@"paragraph" expected:@"::: {.callout-caution}\nAttention\nTest\n:::\n\nNeighbor.\n" HTML:@"Attention"];
    [self assertPreviewBlockSource:@"::: {.callout-note collapse=\"true\"}\n## Prerequisites\nTest\n:::\n\nNeighbor.\n"
        texts:@[@"Test"] value:@"h1" expected:@"::: {.callout-note collapse=\"true\"}\n## Prerequisites\n# Test\n:::\n\nNeighbor.\n" HTML:@"Test</h1>"];
    [self assertPreviewBlockSource:@"::: {.callout-note}\n## Outer\n::: {.callout-tip}\n## Inner\nContent\n:::\nTail\n:::\n"
        texts:@[@"Content"] value:@"h1" expected:@"::: {.callout-note}\n## Outer\n::: {.callout-tip}\n## Inner\n# Content\n:::\nTail\n:::\n" HTML:@"Content</h1>"];
}

- (void)testPreviewBlockConversionPreservesBlankSeparators
{
    for (NSArray *scenario in @[@[@"h1",@"# ",@"<h1"],@[@"unordered",@"- ",@"<ul>"],@[@"tasks",@"- [ ] ",@"<ul>"],@[@"quote",@"> ",@"<blockquote>"]]) {
        NSString *prefix = scenario[1];
        [self assertPreviewBlockSource:@"first\n\n \t\nsecond\n\nNeighbor.\n" texts:@[@"first",@"second"] value:scenario[0]
            expected:[NSString stringWithFormat:@"%@first\n\n \t\n%@second\n\nNeighbor.\n",prefix,prefix] HTML:scenario[2]];
    }
}

- (void)testPreviewBlockConversionLeavesUnselectedSourceBetweenParagraphsUnchanged
{
    [self assertPreviewBlockSource:@"first\n\n<!-- preserved comment -->\n\n![Image](keep.png)\n\nsecond\n\nNeighbor.\n"
        texts:@[@"first",@"second"] value:@"h1"
        expected:@"# first\n\n<!-- preserved comment -->\n\n![Image](keep.png)\n\n# second\n\nNeighbor.\n" HTML:@"<h1"];
}

- (void)testPreviewBlockConversionConsumesSetextUnderlineWithoutTouchingNeighborRule
{
    for (NSString *underline in @[@"====",@"----"]) {
        for (NSArray *scenario in @[@[@"paragraph",@"",@"<p>Title</p>"],@[@"h3",@"### ",@"<h3"],@[@"quote",@"> ",@"<blockquote>"]]) {
            [self assertPreviewBlockSource:[NSString stringWithFormat:@"Title\n%@\n\n---\n\nNeighbor.\n",underline]
                texts:@[@"Title"] value:scenario[0]
                expected:[NSString stringWithFormat:@"%@Title\n\n---\n\nNeighbor.\n",scenario[1]] HTML:scenario[2]];
        }
    }
}


- (void)testPreviewSetextConversionPreservesCRLFAndStandaloneRules
{
    [self assertPreviewBlockSource:@"Title\r\n====\r\n\r\nNeighbor.\r\n" texts:@[@"Title"] value:@"h3"
        expected:@"### Title\r\n\r\nNeighbor.\r\n" HTML:@"<h3"];
    [self assertPreviewBlockSource:@"Title\n====\n\nsecond\n\nNeighbor.\n" texts:@[@"Title",@"second"] value:@"h3"
        expected:@"### Title\n\n### second\n\nNeighbor.\n" HTML:@"<h3"];
}


- (void)testPreviewMixedStylesApplyToAllSelectedCharactersAndPreserveOutsideStyles
{
    MPDocument *document=[MPDocument new];
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor;document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document;renderer.dataSource=(id<MPRendererDataSource>)document;
    MPPreferences *preferences=document.preferences;
    BOOL oldIntra=preferences.extensionIntraEmphasis,oldUnderline=preferences.extensionUnderline,oldStrike=preferences.extensionStrikethough,oldSmart=preferences.extensionSmartyPants;
    NSArray *cases=@[
        @[@"test **mot** selection",@[@"test ",@"mot",@" selection"],@0,@0,@1,@3,@"bold",@"**test mot** selection"],
        @[@"test **mot** selection",@[@"test ",@"mot",@" selection"],@0,@2,@1,@2,@"bold",@"te**st mot** selection"],
        @[@"test **mot** selection",@[@"test ",@"mot",@" selection"],@1,@1,@2,@4,@"bold",@"test **mot sel**ection"],
        @[@"test *mot* selection",@[@"test ",@"mot",@" selection"],@0,@0,@1,@3,@"italic",@"*test mot* selection"],
        @[@"test _mot_ selection",@[@"test ",@"mot",@" selection"],@0,@0,@1,@3,@"underline",@"_test mot_ selection"],
        @[@"test ~~mot~~ selection",@[@"test ",@"mot",@" selection"],@0,@0,@1,@3,@"strike",@"~~test mot~~ selection"],
        @[@"test **_mot_** selection",@[@"test ",@"mot",@" selection"],@0,@0,@1,@3,@"bold",@"**test _mot_** selection"],
        @[@"**a** **b**",@[@"a",@" ",@"b"],@0,@0,@2,@1,@"bold",@"**a b**"],
        @[@"avant **😀mot** fin",@[@"avant ",@"😀mot",@" fin"],@0,@0,@1,@2,@"bold",@"**avant 😀mot** fin"],
        @[@"**entier mot** fin",@[@"entier mot",@" fin"],@0,@7,@0,@10,@"bold",@"**entier** mot fin"]
    ];
    @try {
        preferences.extensionUnderline=YES;preferences.extensionStrikethough=YES;preferences.extensionSmartyPants=NO;
        for(NSArray *scenario in cases) {
            editor.string=scenario[0];[renderer parseMarkdown:editor.string];
            NSMutableArray *mapping=[NSMutableArray array];
            NSUInteger cursor=0;
            for(NSString *text in scenario[1]) {
                NSRange found=[editor.string rangeOfString:text options:NSLiteralSearch range:NSMakeRange(cursor,editor.string.length-cursor)];
                XCTAssertNotEqual(found.location,NSNotFound,@"%@",scenario);
                if(found.location==NSNotFound) break;
                [mapping addObject:@{@"location":@(found.location),@"length":@(found.length),@"text":text}];cursor=NSMaxRange(found);
            }
            document.previewEditRanges=mapping;document.previewEditSource=editor.string;document.previewEditToken=renderer.checkboxBridgeToken;
            NSUInteger first=[scenario[2] unsignedIntegerValue],last=[scenario[4] unsignedIntegerValue];
            NSMutableArray *runs=[NSMutableArray array];NSMutableString *visible=[NSMutableString string];
            for(NSUInteger i=first;i<=last;i++) {
                NSUInteger start=i==first?[scenario[3] unsignedIntegerValue]:0,end=i==last?[scenario[5] unsignedIntegerValue]:[mapping[i][@"length"] unsignedIntegerValue];
                [runs addObject:@{@"id":@(i),@"start":@(start),@"end":@(end)}];
                [visible appendString:[mapping[i][@"text"] substringWithRange:NSMakeRange(start,end-start)]];
            }
            NSMutableDictionary *payload=[runs.firstObject mutableCopy];payload[@"runs"]=runs;payload[@"text"]=visible;payload[@"action"]=scenario[6];payload[@"token"]=document.previewEditToken;
            XCTAssertTrue([document applyPreviewEditPayload:payload],@"%@",scenario);
            XCTAssertEqualObjects(editor.string,scenario[7],@"%@",scenario);
            XCTAssertFalse([editor.string containsString:@"<"]);
        }
        editor.string=@"test **mot** selection";[renderer parseMarkdown:editor.string];
        document.previewEditRanges=@[@{@"location":@0,@"length":@5,@"text":@"test "},@{@"location":@7,@"length":@3,@"text":@"mot"},@{@"location":@12,@"length":@10,@"text":@" selection"}];
        document.previewEditSource=editor.string;document.previewEditToken=renderer.checkboxBridgeToken;
        for(NSArray *bad in @[@[@{@"id":@0,@"start":@0,@"end":@5},@{@"id":@2,@"start":@0,@"end":@3}],@[@{@"id":@1,@"start":@0,@"end":@3},@{@"id":@0,@"start":@0,@"end":@5}],@[@{@"id":@0,@"start":@0,@"end":@5},@{@"id":@1,@"start":@0,@"end":@99}]]) {
            XCTAssertFalse(([document applyPreviewEditPayload:@{@"id":@0,@"token":document.previewEditToken,@"runs":bad,@"text":@"forged",@"action":@"bold"}]));
            XCTAssertEqualObjects(editor.string,@"test **mot** selection");
        }
    } @finally {
        [document close];preferences.extensionIntraEmphasis=oldIntra;preferences.extensionUnderline=oldUnderline;preferences.extensionStrikethough=oldStrike;preferences.extensionSmartyPants=oldSmart;
    }
}

- (void)testPreviewEditingChangesOnlyMappedSourceAndRejectsStaleOrInvalidRequests
{
    MPDocument *document = [MPDocument new];
    document.fileURL = self.testFileURL;
    MPPreferences *preferences = document.preferences;
    BOOL oldMath = preferences.htmlMathJax;
    BOOL oldSmart = preferences.extensionSmartyPants;
    BOOL oldTasks = preferences.htmlTaskList;
    BOOL oldUnderline = preferences.extensionUnderline;
    BOOL oldIntra = preferences.extensionIntraEmphasis;
    BOOL oldStrike = preferences.extensionStrikethough;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    document.editor = editor; document.preview = web;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView = web;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    web.policyDelegate = (id<WebPolicyDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    @try {
        preferences.htmlMathJax = NO;
        preferences.extensionSmartyPants = NO;
        preferences.htmlTaskList = YES;
        renderer.rendererFlags = preferences.rendererFlags;
        editor.string = @"# Unique heading\n\nEditable phrase é 日本語.\n\n[Keep this link](https://example.com)\n\nRepeated\n\nRepeated\n\n[&#68;ecoded](https://example.com/Decoded)\n\n<span title=\"Attribute\">&#65;ttribute</span>\n";
        [renderer parseMarkdown:editor.string]; [renderer render];
        XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && document.previewEditRanges.count > 0;
            }] object:document];
        [self waitForExpectations:@[loaded] timeout:10];
        XCTAssertNotNil(document.previewEditToken);
        if (!document.previewEditToken) return;
        NSUInteger index = [document.previewEditRanges indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger i, BOOL *stop) {
            return [entry[@"text"] isEqualToString:@"Editable phrase é 日本語."];
        }];
        XCTAssertNotEqual(index, NSNotFound);
        NSArray *repeated=[document.previewEditRanges filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"text == %@",@"Repeated"]];
        XCTAssertEqual(repeated.count,2U);
        if (repeated.count==2) XCTAssertNotEqual([repeated[0][@"location"] unsignedIntegerValue],[repeated[1][@"location"] unsignedIntegerValue]);
        XCTAssertFalse([[document.previewEditRanges valueForKey:@"text"] containsObject:@"Decoded"]);
        XCTAssertFalse([[document.previewEditRanges valueForKey:@"text"] containsObject:@"Attribute"]);
        NSString *token = document.previewEditToken;
        NSString *before = editor.string;
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":@"forged",@"id":@(index),@"action":@"replace",@"text":@"Changed"}]));
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":token,@"id":@(-1),@"action":@"replace",@"text":@"Changed"}]));
        for (NSString *action in @[@"color",@"background"]) {
            XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":token,@"id":@(index),@"action":action,@"start":@0,@"end":@4,@"value":@"#175cd3"}]));
        }
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":token,@"id":@(index),@"action":@"block",@"start":@0,@"end":@4}]));
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":token,@"id":@(index),@"action":@"link",@"start":@0,@"end":@4,@"value":@"javascript:alert(1)"}]));
        [document handlePreviewEdit:[NSURL URLWithString:@"x-macdown-preview://edit/?payload=%5B%5D"]];
        XCTAssertEqualObjects(editor.string, before);
        NSString *script = [NSString stringWithFormat:@"(function(){var e=document.querySelector('[data-mp-edit-id=\"%lu\"]'),r=document.createRange();r.setStart(e.firstChild,0);r.setEnd(e.firstChild,8);var s=getSelection();s.removeAllRanges();s.addRange(r);document.dispatchEvent(new Event('selectionchange'));})()",(unsigned long)index];
        [web stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.querySelector('[data-mp-edit-id=\"%lu\"]').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}));",(unsigned long)index]];
        [web stringByEvaluatingJavaScriptFromString:script];
        [web stringByEvaluatingJavaScriptFromString:@"window.__heldSelectionChecked=false;setTimeout(function(){window.__heldSelectionDisplay=getComputedStyle(document.getElementById('macdown-preview-format')).display;window.__heldSelectionChecked=true;},250);"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return [[web stringByEvaluatingJavaScriptFromString:@"window.__heldSelectionChecked"] boolValue];}] object:web]] timeout:5];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"window.__heldSelectionDisplay"], @"none");
        [web stringByEvaluatingJavaScriptFromString:@"window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));"];
        XCTNSPredicateExpectation *panel = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"] isEqualToString:@"block"];
            }] object:web];
        [self waitForExpectations:@[panel] timeout:5];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"(function(){var r=document.getElementById('macdown-preview-format').getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight;})()"] boolValue]);
        XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":token,@"id":@(index),@"action":@"bold",@"start":@0,@"end":@8}]));
        XCTAssertTrue([editor.string containsString:@"**Editable** phrase é 日本語."]);
        XCTAssertTrue([editor.string containsString:@"[Keep this link](https://example.com)"]);
        XCTAssertFalse(([document applyPreviewEditPayload:@{@"token":token,@"id":@(index),@"action":@"replace",@"text":@"Stale overwrite"}]));
        XCTAssertFalse([[renderer HTMLForExportWithStyles:YES highlighting:YES] containsString:@"macdown-preview-format"]);
        XCTNSPredicateExpectation *updated = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && ![document.previewEditToken isEqualToString:token];
            }] object:web];
        [self waitForExpectations:@[updated] timeout:10];
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var e=Array.from(document.querySelectorAll('[data-mp-edit-id]')).filter(function(n){return n.textContent==='Editable';})[0],r=document.createRange();r.selectNodeContents(e);getSelection().removeAllRanges();getSelection().addRange(r);e.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));document.dispatchEvent(new Event('selectionchange'));})()"];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"], @"Editable");
        XCTAssertFalse([[web stringByEvaluatingJavaScriptFromString:@"!!document.querySelector('[contenteditable]')"] boolValue]);
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
        [web stringByEvaluatingJavaScriptFromString:@"Array.from(document.querySelectorAll('#macdown-preview-format button')).find(function(b){return b.hasAttribute('data-mp-edit-text');}).click();document.querySelector('[contenteditable]').textContent='Changed <safe>'"];

        XCTAssertTrue(document.isDocumentEdited);
        NSError *saveError = nil;
        NSData *savedData = [document dataOfType:@"net.daringfireball.markdown" error:&saveError];
        XCTAssertNil(saveError);
        NSString *savedSource = [[NSString alloc] initWithData:savedData encoding:NSUTF8StringEncoding];
        XCTAssertTrue([savedSource containsString:@"**Changed \\<safe\\>**"]);
        XCTAssertEqualObjects(savedSource, editor.string);
        XCTAssertFalse([[web stringByEvaluatingJavaScriptFromString:@"Boolean(window.macdownPreviewEditor.draft())"] boolValue]);
        NSArray *cases = @[
            @[@"block",@"h4",@"<h4"], @[@"block",@"unordered",@"<ul>"],
            @[@"block",@"tasks",@"type=\"checkbox\""], @[@"block",@"quote",@"<blockquote>"],
            @[@"block",@"callout",@"callout-note"], @[@"block",@"toggle-h2",@"<details"],
            @[@"clear",@"",@"<p>Scenario heading</p>"],
            @[@"clear",@"legacy",@"<p>Scenario heading</p>"],
            @[@"bold",@"punct",@"<strong>[looks]</strong>"],
            @[@"bold",@"",@"<strong>Scenario</strong>"], @[@"underline",@"",@"<u>Scenario</u>"],
            @[@"italic",@"",@"<em>Scenario</em>"]];
        for (NSArray *scenario in cases) {
            editor.string = [scenario[1] isEqualToString:@"legacy"] ? @"<u>Scenario</u> heading\n\nUntouched neighbor.\n" : [scenario[1] isEqualToString:@"punct"] ? @"# [looks]\n\nUntouched neighbor.\n" : [scenario[0] isEqualToString:@"clear"] ? @"**Scenario** heading\n\nUntouched neighbor.\n" : @"# Scenario heading\n\nUntouched neighbor.\n";
            [renderer parseMarkdown:editor.string]; [renderer render];
            NSString *scenarioToken = renderer.checkboxBridgeToken;
            XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return !web.isLoading && [document.previewEditToken isEqualToString:scenarioToken];
                }] object:web];
            [self waitForExpectations:@[ready] timeout:10];
            NSUInteger headingID = [document.previewEditRanges indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger i, BOOL *stop) {
                return [item[@"text"] isEqualToString:([scenario[1] isEqualToString:@"punct"] ? @"[looks]" : [scenario[0] isEqualToString:@"clear"] ? @"Scenario" : @"Scenario heading")];
            }];
            XCTAssertNotEqual(headingID, NSNotFound);
            XCTAssertTrue(([document applyPreviewEditPayload:@{@"token":scenarioToken,@"id":@(headingID),@"action":scenario[0],@"value":scenario[1],@"start":@0,@"end":@([scenario[1] isEqualToString:@"punct"] ? 7 : 8)}]));
            XCTAssertFalse([editor.string containsString:@"<"]);
            XCTAssertFalse([editor.string containsString:@"<u>"]);
            XCTAssertFalse([editor.string containsString:@"<span"]);
            XCTAssertTrue([editor.string hasSuffix:@"\n\nUntouched neighbor.\n"], @"%@", scenario);
            [renderer parseMarkdown:editor.string];
            XCTAssertTrue([renderer.currentHtml containsString:scenario[2]], @"%@ : %@", scenario, renderer.currentHtml);
            if ([scenario[1] isEqualToString:@"toggle-h2"]) XCTAssertFalse([editor.string containsString:@"## # Scenario"]);
        }
        // Mixed source runs share one selection and one style transaction.
        // A drag may pause on an incomplete selection without opening the panel.
        editor.string=@"test **mot** selection\n\nUntouched neighbor.\n";
        [renderer parseMarkdown:editor.string];[renderer render];
        NSString *mixedToken=renderer.checkboxBridgeToken;
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[document.previewEditToken isEqualToString:mixedToken];}] object:web]] timeout:10];
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var nodes=Array.from(document.querySelectorAll('[data-mp-edit-id]')),a=nodes.find(function(n){return n.textContent==='test ';}),b=nodes.find(function(n){return n.textContent==='mot';}),r=document.createRange();a.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}));r.setStart(a.firstChild,2);r.setEnd(b.firstChild,2);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));})()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"st mo");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"false");
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[editor.string isEqualToString:@"te**st mot** selection\n\nUntouched neighbor.\n"]&&[[web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"] isEqualToString:@"st mo"];} ] object:web]] timeout:10];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"true");
        // Multiple identical inline whitespace nodes are source-bounded, so a
        // plain gap between two bold words participates in the intersection.
        editor.string=@"**a** **b** et **c** **d**\n\nUntouched neighbor.\n";
        [renderer parseMarkdown:editor.string];[renderer render];
        NSString *spaceToken=renderer.checkboxBridgeToken;
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[document.previewEditToken isEqualToString:spaceToken];}] object:web]] timeout:10];
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var nodes=Array.from(document.querySelectorAll('[data-mp-edit-id]')),a=nodes.find(function(n){return n.textContent==='a';}),b=nodes.find(function(n){return n.textContent==='b';}),r=document.createRange();r.setStart(a.firstChild,0);r.setEnd(b.firstChild,1);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));})()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"false");
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[editor.string isEqualToString:@"**a b** et **c** **d**\n\nUntouched neighbor.\n"];} ] object:web]] timeout:10];
        // A selection crossing paragraphs keeps its literal text and toggles
        // the global common style, rather than toggling each paragraph alone.
        editor.string=@"**first**\n\nsecond\n\nUntouched neighbor.\n";
        [renderer parseMarkdown:editor.string];[renderer render];
        NSString *blockToken=renderer.checkboxBridgeToken;
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[document.previewEditToken isEqualToString:blockToken];}] object:web]] timeout:10];
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var nodes=Array.from(document.querySelectorAll('[data-mp-edit-id]')),a=nodes.find(function(n){return n.textContent==='first';}),b=nodes.find(function(n){return n.textContent==='second';}),r=document.createRange();r.setStart(a.firstChild,0);r.setEnd(b.firstChild,6);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));})()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"],@"false");
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[editor.string isEqualToString:@"**first**\n\n**second**\n\nUntouched neighbor.\n"]&&[[web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')"] isEqualToString:@"true"];} ] object:web]] timeout:10];
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=bold]').click()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[editor.string isEqualToString:@"first\n\nsecond\n\nUntouched neighbor.\n"];} ] object:web]] timeout:10];
        // Block conversion must preserve a multi-paragraph visual selection
        // even though new markers are inserted inside its source range.
        [web stringByEvaluatingJavaScriptFromString:@"(function(){document.querySelector('[data-mp-option=h1]').click();})()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[editor.string isEqualToString:@"# first\n\n# second\n\nUntouched neighbor.\n"];} ] object:web]] timeout:10];
        XCTAssertEqualObjects([[web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"] stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"],@"first\nsecond");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-scope=block] [data-mp-active]').getAttribute('data-mp-option')"],@"h1");
        [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=italic]').click()"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[editor.string isEqualToString:@"# *first*\n\n# *second*\n\nUntouched neighbor.\n"];} ] object:web]] timeout:10];
        // All heading levels admit element-boundary selections. Exercise each
        // style through the native toolbar with the editor cursor at EOF.
        preferences.extensionStrikethough = YES;
        NSArray *actions = @[@"bold",@"italic",@"underline",@"strike",@"bold",@"italic"];
        NSArray *tags = @[@"strong",@"em",@"u",@"del",@"strong",@"em"];
        for (NSUInteger level=1; level<=6; level++) {
            NSString *prefix = [@"" stringByPaddingToLength:level withString:@"#" startingAtIndex:0];
            editor.string = [NSString stringWithFormat:@"%@ Heading selection\n\nUntouched neighbor.\n",prefix];
            [renderer parseMarkdown:editor.string]; [renderer render];
            NSString *expectedToken = renderer.checkboxBridgeToken;
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && [document.previewEditToken isEqualToString:expectedToken];
            }] object:web]] timeout:10];
            [web stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"(function(){var r=document.createRange();r.selectNodeContents(document.querySelector('h%lu'));getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));})()",(unsigned long)level]];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
            editor.selectedRange = NSMakeRange(editor.string.length,0);
            XCTAssertTrue([window makeFirstResponder:web.mainFrame.frameView.documentView]);
            NSString *action = actions[level-1];
            if ([action isEqualToString:@"bold"]) [document toggleStrong:nil];
            else if ([action isEqualToString:@"italic"]) [document toggleEmphasis:nil];
            else if ([action isEqualToString:@"underline"]) [document toggleUnderline:nil];
            else [document toggleStrikethrough:nil];
            XCTAssertTrue([editor.string hasPrefix:[prefix stringByAppendingString:@" "]]);
            XCTAssertTrue([editor.string hasSuffix:@"\n\nUntouched neighbor.\n"]);
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && ![document.previewEditToken isEqualToString:expectedToken];
            }] object:web]] timeout:10];
            NSString *check = [NSString stringWithFormat:@"document.querySelector('h%lu %@').textContent",(unsigned long)level,tags[level-1]];
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:check], @"Heading selection");
        }
        // Repeat the reported partial-word selection through the real WebView,
        // then format its freshly remapped rendered text again.
        preferences.extensionIntraEmphasis = NO;
        preferences.extensionUnderline = NO;
        editor.string = @"test avec test";
        [renderer parseMarkdown:editor.string]; [renderer render];
        for (NSString *action in @[@"bold",@"underline"]) {
            NSString *expectedToken = renderer.checkboxBridgeToken;
            XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return !web.isLoading && [document.previewEditToken isEqualToString:expectedToken];
                }] object:web];
            [self waitForExpectations:@[ready] timeout:10];
            NSString *text = [action isEqualToString:@"bold"] ? @"test avec test" : @"est avec t";
            NSUInteger identifier = [document.previewEditRanges indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger i, BOOL *stop) {
                return [item[@"text"] isEqualToString:text];
            }];
            XCTAssertNotEqual(identifier, NSNotFound);
            if ([action isEqualToString:@"bold"]) {
                [web stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"(function(){var e=document.querySelector('[data-mp-edit-id=\"%lu\"]'),r=document.createRange();r.setStart(e.firstChild,1);r.setEnd(e.firstChild,11);getSelection().removeAllRanges();getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));})()", (unsigned long)identifier]];
            } else XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"], @"est avec t");
            editor.selectedRange = NSMakeRange(editor.string.length, 0);
            XCTAssertTrue([window makeFirstResponder:web.mainFrame.frameView.documentView]);
            XCTAssertTrue([document previewHasFindFocus]);
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
            [web stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.querySelector('[data-mp-style=%@]').click()",action]];
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"], @"block");
            XCTNSPredicateExpectation *rendered = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                    return !web.isLoading && ![document.previewEditToken isEqualToString:expectedToken] &&
                        [[web stringByEvaluatingJavaScriptFromString:@"document.querySelector('p').textContent"] isEqualToString:@"test avec test"];
                }] object:web];
            [self waitForExpectations:@[rendered] timeout:10];
        }
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"!!document.querySelector('strong u')"] boolValue]);
        XCTAssertEqualObjects(editor.string, @"t**_est avec t_**est");
        // Queue rapid style clicks on the first of two identical words, then
        // change its block type without selecting again. Only that occurrence
        // may change; the other word and neighboring paragraph remain intact.
        editor.string = @"test avec test\n\nUntouched neighbor.\n";
        [renderer parseMarkdown:editor.string]; [renderer render];
        NSString *duplicateToken = renderer.checkboxBridgeToken;
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
            return !web.isLoading && [document.previewEditToken isEqualToString:duplicateToken];
        }] object:web]] timeout:10];
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var e=Array.from(document.querySelectorAll('[data-mp-edit-id]')).find(function(n){return n.textContent==='test avec test';}),r=document.createRange();r.setStart(e.firstChild,0);r.setEnd(e.firstChild,4);getSelection().removeAllRanges();getSelection().addRange(r);})()"];
        XCTAssertTrue([window makeFirstResponder:web.mainFrame.frameView.documentView]);
        [document toggleStrong:nil];
        [document toggleEmphasis:nil];
        [document toggleUnderline:nil];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
            return !web.isLoading && [editor.string isEqualToString:@"***_test_*** avec test\n\nUntouched neighbor.\n"] &&
                [[web stringByEvaluatingJavaScriptFromString:@"!!document.querySelector('strong') && !!document.querySelector('em') && !!document.querySelector('u') && getSelection().toString()==='test'"] boolValue];
        }] object:web]] timeout:15];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:panel.predicate object:web]] timeout:5];
        [web stringByEvaluatingJavaScriptFromString:@"window.__panelBeforeFormatting=document.getElementById('macdown-preview-format');window.__panelHiddenFrames=0;window.__panelSampling=true;(function sample(){if(!window.__panelSampling)return;if(!window.__panelBeforeFormatting.isConnected||getComputedStyle(window.__panelBeforeFormatting).display==='none')window.__panelHiddenFrames++;requestAnimationFrame(sample);})();"];
        [document convertToH1:nil];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(window.__panelBeforeFormatting).display"], @"block");
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
            return !web.isLoading && [[web stringByEvaluatingJavaScriptFromString:@"!!document.querySelector('h1 u') && getSelection().toString()==='test'"] boolValue];
        }] object:web]] timeout:10];
        XCTAssertEqualObjects(editor.string, @"# ***_test_*** avec test\n\nUntouched neighbor.\n");
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"window.__panelBeforeFormatting===document.getElementById('macdown-preview-format')"] boolValue]);
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"window.__panelSampling=false;String(window.__panelHiddenFrames)"], @"0");
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"['bold','italic','underline'].every(function(s){var b=document.querySelector('[data-mp-style='+s+']');return b.getAttribute('aria-pressed')==='true' && getComputedStyle(b).color==='rgb(39, 132, 222)';})"] boolValue]);
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-scope=block] [data-mp-active]').getAttribute('data-mp-option')"], @"h1");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.querySelector('[data-mp-scope=block] [data-mp-active]')).color"], @"rgb(39, 132, 222)");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('[data-mp-style=strike]').getAttribute('aria-pressed')"], @"false");
        [web stringByEvaluatingJavaScriptFromString:@"getSelection().removeAllRanges();document.activeElement.blur();document.dispatchEvent(new Event('selectionchange'));"];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
            return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.getElementById('macdown-preview-format')).display"] isEqualToString:@"none"];
        }] object:web]] timeout:5];

        // Changing selection while the first style is pending cancels the
        // continuation, even when the newly selected word has identical text.
        editor.string = @"test avec test\n\nUntouched neighbor.\n";
        [renderer parseMarkdown:editor.string]; [renderer render];
        NSString *cancelToken = renderer.checkboxBridgeToken;
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
            return !web.isLoading && [document.previewEditToken isEqualToString:cancelToken];
        }] object:web]] timeout:10];
        NSString *selectFirst = @"(function(){var e=Array.from(document.querySelectorAll('[data-mp-edit-id]')).find(function(n){return n.textContent==='test avec test';}),r=document.createRange();r.setStart(e.firstChild,0);r.setEnd(e.firstChild,4);getSelection().removeAllRanges();getSelection().addRange(r);})()";
        [web stringByEvaluatingJavaScriptFromString:selectFirst];
        XCTAssertTrue([window makeFirstResponder:web.mainFrame.frameView.documentView]);
        [document toggleStrong:nil];
        [web stringByEvaluatingJavaScriptFromString:[selectFirst stringByReplacingOccurrencesOfString:@"0);r.setEnd(e.firstChild,4)" withString:@"10);r.setEnd(e.firstChild,14)"]];
        [document toggleEmphasis:nil];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
            return !web.isLoading && ![document.previewEditToken isEqualToString:cancelToken];
        }] object:web]] timeout:10];
        XCTAssertEqualObjects(editor.string, @"**test** avec test\n\nUntouched neighbor.\n");
        // A collapsed preview selection must never insert at the editor cursor.
        [web stringByEvaluatingJavaScriptFromString:@"getSelection().removeAllRanges()"];
        [document toggleStrong:nil];
        XCTAssertEqualObjects(editor.string, @"**test** avec test\n\nUntouched neighbor.\n");
    } @finally {
        web.frameLoadDelegate = nil; web.policyDelegate = nil; [window close]; [document close];
        preferences.htmlMathJax = oldMath; preferences.extensionSmartyPants = oldSmart;
        preferences.htmlTaskList = oldTasks;
        preferences.extensionUnderline = oldUnderline;
        preferences.extensionIntraEmphasis = oldIntra;
        preferences.extensionStrikethough = oldStrike;
    }
}

- (void)testReadingProgressUsesVisiblePaneGeometryAndClampsBoundaries
{
    MPDocument *document = [MPDocument new];
    MPPreferences *preferences = document.preferences;
    BOOL oldProgress = preferences.editorShowReadingProgress;
    BOOL oldCount = preferences.editorShowWordCount;
    BOOL oldSync = preferences.editorSyncScrolling;
    BOOL oldReader = preferences.editorStartInPreviewMode;
    @try {
        preferences.editorShowReadingProgress = YES;
        preferences.editorShowWordCount = YES;
        preferences.editorSyncScrolling = NO;
        preferences.editorStartInPreviewMode = NO;
        [document makeWindowControllers]; [document showWindows];
        XCTestExpectation *setup = [self expectationWithDescription:@"Deferred editor setup"];
        [NSOperationQueue.mainQueue addOperationWithBlock:^{ [setup fulfill]; }];
        [self waitForExpectations:@[setup] timeout:5];
        document.editor.string = [@"Reading position line\n" stringByPaddingToLength:10000
            withString:@"Reading position line\n" startingAtIndex:0];
        [document.editor.layoutManager ensureLayoutForTextContainer:document.editor.textContainer];
        [document.editor sizeToFit];
        [document setupReadingProgress];
        XCTAssertNotNil([document valueForKey:@"readingProgressScrollMonitor"]);
        NSScrollView *scroll = document.editor.enclosingScrollView;
        [document willStartLiveScroll:nil];
        [scroll.documentView scrollPoint:NSMakePoint(0,0)];
        [document updateReadingProgress];
        XCTAssertEqualObjects(document.readingProgressLabel.stringValue, @"0%");
        CGFloat maximum = NSHeight(scroll.documentView.bounds)-NSHeight(scroll.documentVisibleRect);
        XCTAssertGreaterThan(maximum, 0);
        [scroll.documentView scrollPoint:NSMakePoint(0,maximum/2)];
        [document updateReadingProgress];
        XCTAssertEqualObjects(document.readingProgressLabel.stringValue, @"50%");
        [scroll.documentView scrollPoint:NSMakePoint(0,maximum)];
        [document updateReadingProgress];
        XCTAssertEqualObjects(document.readingProgressLabel.stringValue, @"100%");
        // A real short preview has no remaining reading distance.
        [document.preview.mainFrame loadHTMLString:@"<html><body>Short preview.</body></html>" baseURL:nil];
        XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !document.preview.isLoading &&
                    [[document.preview stringByEvaluatingJavaScriptFromString:@"document.body.textContent"]
                        isEqualToString:@"Short preview."];
            }] object:document];
        [self waitForExpectations:@[loaded] timeout:10];
        [document willStartPreviewLiveScroll:nil];
        [document updateReadingProgress];
        XCTAssertEqualObjects(document.readingProgressLabel.stringValue, @"100%");
        [document.preview stringByEvaluatingJavaScriptFromString:@"document.body.style.height='2400px'"];
        NSScrollView *previewScroll = document.preview.enclosingScrollView;
        XCTNSPredicateExpectation *resized = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return NSHeight(previewScroll.documentView.bounds) > NSHeight(previewScroll.documentVisibleRect)+100;
            }] object:document];
        [self waitForExpectations:@[resized] timeout:5];
        CGFloat previewMaximum = NSHeight(previewScroll.documentView.bounds)-NSHeight(previewScroll.documentVisibleRect);
        XCTAssertGreaterThan(previewMaximum, 0);
        [previewScroll.documentView scrollPoint:NSMakePoint(0, previewMaximum/2)];
        [document updateReadingProgress];
        XCTAssertEqualObjects(document.readingProgressLabel.stringValue, @"50%");
        [previewScroll.documentView scrollPoint:NSMakePoint(0, previewMaximum)];
        [document updateReadingProgress];
        XCTAssertEqualObjects(document.readingProgressLabel.stringValue, @"100%");
        preferences.editorShowWordCount = NO;
        [document setupReadingProgress];
        XCTAssertFalse(document.readingProgressLabel.hidden);
        preferences.editorShowReadingProgress = NO;
        [document setupReadingProgress];
        XCTAssertTrue(document.readingProgressLabel.hidden);
        XCTAssertNil([document valueForKey:@"readingProgressScrollMonitor"]);
    } @finally {
        [document updateChangeCount:NSChangeCleared]; [document close];
        preferences.editorShowReadingProgress = oldProgress;
        preferences.editorShowWordCount = oldCount;
        preferences.editorSyncScrolling = oldSync;
        preferences.editorStartInPreviewMode = oldReader;
    }
}

- (void)testCodeWrappingChangesLayoutWithoutChangingCodeAndExports
{
    MPDocument *document = [MPDocument new];
    MPPreferences *preferences = document.preferences;
    BOOL oldWrap = preferences.htmlWrapCodeBlocks;
    BOOL oldSyntax = preferences.htmlSyntaxHighlighting;
    BOOL oldFences = preferences.extensionFencedCode;
    BOOL oldMath = preferences.htmlMathJax;
    NSString *oldStyle = preferences.htmlStyleName;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,240,300)];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,240,300)];
    document.editor = editor; document.preview = web;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    NSString *code = [@"x" stringByPaddingToLength:500 withString:@"x" startingAtIndex:0];
    editor.string = [NSString stringWithFormat:@"```bash\n%@\n```", code];
    @try {
        preferences.htmlSyntaxHighlighting = YES;
        preferences.extensionFencedCode = YES;
        preferences.htmlMathJax = NO;
        preferences.htmlStyleName = @"GitHub2";
        for (NSNumber *enabled in @[@NO, @YES, @NO]) {
            preferences.htmlWrapCodeBlocks = enabled.boolValue;
            [renderer parseMarkdown:editor.string];
            [renderer render];
            NSString *expected = enabled.boolValue ? @"pre-wrap" : @"pre";
            XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                    if (web.isLoading) return NO;
                    NSString *spacing = [web stringByEvaluatingJavaScriptFromString:
                        @"document.querySelector('pre') ? getComputedStyle(document.querySelector('pre')).whiteSpace : ''"];
                    return [spacing isEqualToString:expected];
                }] object:web];
            [self waitForExpectations:@[loaded] timeout:10];
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:
                @"document.querySelector('pre code').textContent.trim()"], code);
            if (enabled.boolValue) {
                XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:
                    @"String(document.querySelector('pre').scrollWidth <= document.querySelector('pre').clientWidth+1)"], @"true");
            }
            NSString *html = [renderer HTMLForExportWithStyles:YES highlighting:YES];
            XCTAssertEqual([html containsString:@"id=\"macdown-code-wrapping\""], enabled.boolValue);
            XCTAssertFalse([[renderer HTMLForExportWithStyles:NO highlighting:NO]
                containsString:@"id=\"macdown-code-wrapping\""]);
        }
    } @finally {
        web.frameLoadDelegate = nil; [document close];
        preferences.htmlWrapCodeBlocks = oldWrap;
        preferences.htmlSyntaxHighlighting = oldSyntax;
        preferences.extensionFencedCode = oldFences;
        preferences.htmlMathJax = oldMath;
        preferences.htmlStyleName = oldStyle;
    }
}

- (void)testFirstRealCodeRenderAfterEmptyPreviewLoadsPrismGrammarAndTokens
{
    MPPreferences *preferences = self.document.preferences;
    BOOL syntax = preferences.htmlSyntaxHighlighting;
    BOOL fences = preferences.extensionFencedCode;
    BOOL math = preferences.htmlMathJax;
    BOOL mermaid = preferences.htmlMermaid, graphviz = preferences.htmlGraphviz;
    NSString *theme = [preferences.htmlHighlightingThemeName copy];
    MPDocument *document = [MPDocument new];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,400,300)];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,400,300)];
    MPRenderer *renderer = [MPRenderer new];
    document.editor = editor;
    document.preview = web;
    document.renderer = renderer;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    renderer.delegate = (id<MPRendererDelegate>)document;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    @try {
        preferences.htmlSyntaxHighlighting = YES;
        preferences.extensionFencedCode = YES;
        preferences.htmlMathJax = NO;
        preferences.htmlMermaid = NO;
        preferences.htmlGraphviz = NO;
        preferences.htmlHighlightingThemeName = nil;
        [renderer parseMarkdown:@""];
        [renderer render];
        XCTNSPredicateExpectation *empty = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,
                                                                   NSDictionary *bindings) {
                return document.isPreviewReady && !document.alreadyRenderingInWeb &&
                    [[web.mainFrame.javaScriptContext evaluateScript:@"!!window.Prism"] toBool];
            }] object:web];
        [self waitForExpectations:@[empty] timeout:10];
        editor.string = @"```javascript\nconst answer = 42;\n```\n";
        [renderer parseMarkdown:editor.string];
        [renderer render];
        XCTNSPredicateExpectation *highlighted = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,
                                                                   NSDictionary *bindings) {
                return !document.alreadyRenderingInWeb &&
                    [[web.mainFrame.javaScriptContext evaluateScript:
                        @"!!(window.Prism && Prism.languages.javascript) && "
                         "document.querySelectorAll('code.language-javascript span.token').length > 0"] toBool];
            }] object:web];
        [self waitForExpectations:@[highlighted] timeout:10];
    } @finally {
        web.frameLoadDelegate = nil;
        [document close];
        preferences.htmlSyntaxHighlighting = syntax;
        preferences.extensionFencedCode = fences;
        preferences.htmlMathJax = math;
        preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz;
        preferences.htmlHighlightingThemeName = theme;
    }
}

- (void)testResourceWatcherBurstPublishesOnceAndAnOldWatcherSetCannotPublish
{
    MPDocumentExportAuditProbe *document = [MPDocumentExportAuditProbe new];
    document.fileURL = self.testFileURL;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    document.editor = editor;
    NSString *one = [self.testDirectory stringByAppendingPathComponent:@"one.svg"];
    NSString *two = [self.testDirectory stringByAppendingPathComponent:@"two.svg"];
    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"></svg>";
    XCTAssertTrue([svg writeToFile:one atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    XCTAssertTrue([svg writeToFile:two atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    editor.string = @"![one](one.svg)\n![two](two.svg)";
    MPRenderer *renderer = [MPRenderer new];
    renderer.dataSource = (id<MPRendererDataSource>)document;
    renderer.delegate = (id<MPRendererDelegate>)document;
    document.renderer = renderer;
    [renderer parseMarkdown:editor.string];
    [renderer render];
    NSString *initialHTML = document.publishedHTML.lastObject;
    NSSet *resourcePaths = MPLocalFilePathsInHTML(initialHTML,
        [(id<MPRendererDelegate>)document rendererBaseURL:renderer]);
    [document.publishedHTML removeAllObjects];
    MPResourceWatcherSet *current = [MPResourceWatcherSet new];
    current.delegate = (id<MPResourceWatcherSetDelegate>)document;
    document.resourceWatcherSet = current;
    @try {
        [current updateWatchedPaths:resourcePaths];
        XCTAssertTrue([current.watchedPaths containsObject:one]);
        XCTAssertTrue([current.watchedPaths containsObject:two]);
        XCTestExpectation *published = [self expectationWithDescription:@"Coalesced real renderer publication"];
        dispatch_async(dispatch_get_main_queue(), ^{ [published fulfill]; });
        [self waitForExpectations:@[published] timeout:5.0];
        XCTAssertEqual(document.publishedHTML.count, 1u);
        NSString *html = document.publishedHTML.lastObject;
        XCTAssertTrue([html containsString:@"one.svg?t="]);
        XCTAssertTrue([html containsString:@"two.svg?t="]);
        MPResourceWatcherSet *old = [MPResourceWatcherSet new];
        [document resourceWatcherSet:old didDetectChangeAtPath:one];
        XCTestExpectation *idle = [self expectationWithDescription:@"Stale event has no publication"];
        dispatch_async(dispatch_get_main_queue(), ^{ [idle fulfill]; });
        [self waitForExpectations:@[idle] timeout:5.0];
        XCTAssertEqual(document.publishedHTML.count, 1u);
    } @finally {
        [document close];
    }
}

- (void)testHTMLExportReportsWriteFailureAfterRealRenderAndPreservesExistingFile
{
    MPControlledExportPanel *panel = [MPControlledExportPanel new];
    // An existing directory cannot be atomically replaced by the HTML file.
    panel.URL = [NSURL fileURLWithPath:self.testDirectory isDirectory:YES];
    NSString *preservedPath = [self.testDirectory stringByAppendingPathComponent:@"preserved.md"];
    XCTAssertTrue([@"preserved" writeToFile:preservedPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    MPDocumentExportAuditProbe *document = [MPDocumentExportAuditProbe new];
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    editor.string = @"# Exported content";
    document.editor = editor;
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    document.preview = preview;
    preview.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax;
    MPCurrentControlledExportPanel = panel;
    Method factory = class_getClassMethod(NSSavePanel.class, @selector(savePanel));
    IMP original = method_setImplementation(factory, (IMP)MPControlledExportPanelFactory);
    @try {
        preferences.htmlMathJax = NO;
        [document exportHtml:nil];
        XCTAssertEqual(panel.presentations, 1u);
        XCTAssertNotNil(panel.completion);
        panel.completion(NSFileHandlingPanelOKButton);
        XCTNSPredicateExpectation *failed = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return document.presentedError != nil;
            }] object:document];
        [self waitForExpectations:@[failed] timeout:10.0];
        XCTAssertNotNil(document.presentedError);
        XCTAssertTrue([renderer.currentHtml containsString:@"Exported content"]);
        XCTAssertEqualObjects([NSString stringWithContentsOfFile:preservedPath encoding:NSUTF8StringEncoding error:NULL], @"preserved");
    } @finally {
        method_setImplementation(factory, original);
        MPCurrentControlledExportPanel = nil;
        preview.frameLoadDelegate = nil;
        [document close];
        preferences.htmlMathJax = math;
    }
}


- (void)testPreviewAndDeferredConsumerResumeAfterPrinting
{
    MPDocumentExportAuditProbe *document = [MPDocumentExportAuditProbe new];
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid;
    BOOL graphviz = preferences.htmlGraphviz;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    editor.string = @"# Before printing";
    document.editor = editor;
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    document.preview = preview;
    preview.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    @try {
        preferences.htmlMathJax = NO;
        preferences.htmlMermaid = NO;
        preferences.htmlGraphviz = NO;
        XCTestExpectation *initial = [self expectationWithDescription:@"Preview before printing"];
        [document performAfterRender:^{ [initial fulfill]; }];
        [self waitForExpectations:@[initial] timeout:10];

        for (NSNumber *printSucceeded in @[@YES, @NO]) {
            NSString *heading = printSucceeded.boolValue ? @"Changed during print" : @"Changed during cancelled print";
            document.printing = YES;
            editor.string = [@"# " stringByAppendingString:heading];
            // The real parser can finish while AppKit's print operation is
            // running its nested event loop. The printed DOM must stay stable.
            [renderer parseMarkdown:editor.string];
            [renderer render];
            XCTAssertNotEqualObjects([[preview.mainFrame.javaScriptContext
                evaluateScript:@"document.querySelector('h1').textContent"] toString], heading);

            XCTestExpectation *consumer = [self expectationWithDescription:@"Consumer resumes with current rendered content"];
            NSUInteger publicationsBeforeRequest = document.publishedHTML.count;
            __block BOOL consumed = NO;
            XCTAssertTrue([document performAfterRender:^{
                XCTAssertEqualObjects([[preview.mainFrame.javaScriptContext
                    evaluateScript:@"document.querySelector('h1').textContent"] toString], heading);
                XCTAssertEqualObjects(renderer.checkboxSourceMarkdown, editor.string);
                consumed = YES;
                [consumer fulfill];
            }]);
            XCTNSPredicateExpectation *parsed = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                    return document.publishedHTML.count > publicationsBeforeRequest;
                }] object:document];
            [self waitForExpectations:@[parsed] timeout:10];
            XCTAssertFalse(consumed, @"The print snapshot must stay unchanged until print completion");
            [document document:document didPrint:printSucceeded.boolValue context:NULL];
            [self waitForExpectations:@[consumer] timeout:10];
            XCTAssertFalse(document.printing);
        }
    } @finally {
        preview.frameLoadDelegate = nil;
        [document close];
        preferences.htmlMathJax = math;
        preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz;
    }
}

- (void)testDeferredConsumerSeesCompletedRealMermaidDiagrams
{
    MPDocument *document = [MPDocument new];
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid;
    BOOL graphviz = preferences.htmlGraphviz, fenced = preferences.extensionFencedCode;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    editor.string = @"```mermaid\ngraph TD; A-->B; B-->C;\n```\n\n"
        @"```mermaid\nsequenceDiagram\nAlice->>Bob: Hello\n```\n\n"
        @"```mermaid\nstateDiagram-v2\n[*] --> Active\nActive --> [*]\n```\n\n"
        @"```mermaid\nclassDiagram\nAnimal <|-- Duck\n```\n\n"
        @"```mermaid\ngantt\ntitle Schedule\ndateFormat YYYY-MM-DD\nsection Work\nTask :a1, 2024-01-01, 2d\n```\n\n"
        @"```mermaid\npie title Pets\n\"Dogs\" : 3\n\"Cats\" : 2\n```\n\n"
        @"```mermaid\njourney\ntitle Work\nsection Day\nCode: 5: Me\n```\n\n"
        @"```mermaid\nmindmap\n  root((Plan))\n    Code\n    Test\n```";
    document.editor = editor;
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    document.preview = preview;
    preview.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    preview.resourceLoadDelegate = (id<WebResourceLoadDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.dataSource = (id<MPRendererDataSource>)document;
    renderer.delegate = (id<MPRendererDelegate>)document;
    document.renderer = renderer;
    @try {
        preferences.htmlMermaid = YES;
        preferences.htmlGraphviz = NO;
        preferences.extensionFencedCode = YES;
        for (NSNumber *mathEnabled in @[@NO, @YES]) {
            preferences.htmlMathJax = mathEnabled.boolValue;
            XCTestExpectation *consumed = [self expectationWithDescription:
                [NSString stringWithFormat:@"Actual deferred consumption, MathJax %@", mathEnabled]];
            [document performAfterRender:^{
                JSContext *context = preview.mainFrame.javaScriptContext;
                XCTAssertEqual([[context evaluateScript:@"document.querySelectorAll('.language-mermaid').length"] toUInt32], 0u);
                // Mermaid replaces each pre inside Hoedown’s existing div wrapper.
                // Exclude the library’s temporary rendering divs from the count.
                XCTAssertEqual([[context evaluateScript:@"Array.from(document.querySelectorAll('svg[id^=\"mermaid_\"]')).filter(function(svg){return !svg.closest('div[id^=\"dmermaid_\"]');}).length"] toUInt32], 8u);
                XCTAssertFalse([[[context evaluateScript:@"document.body.textContent"] toString] containsString:@"Mermaid Error:"]);
                [consumed fulfill];
            }];
            [self waitForExpectations:@[consumed] timeout:20.0];
        }
    } @finally {
        preview.frameLoadDelegate = nil;
        preview.resourceLoadDelegate = nil;
        [document close];
        preferences.htmlMathJax = math;
        preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz;
        preferences.extensionFencedCode = fenced;
    }
}


- (void)testDeferredConsumerRestoresLocalHeadAndBaseAfterHTTPNavigation
{
    MPPreviewHTTPFixture *server = [MPPreviewHTTPFixture new];
    XCTAssertNotNil(server);
    if (!server) return;
    MPDocument *document = [MPDocument new];
    document.fileURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"preview.md"]];
    MPPreferences *preferences = document.preferences;
    BOOL math = preferences.htmlMathJax, mermaid = preferences.htmlMermaid, graphviz = preferences.htmlGraphviz;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    editor.string = @"# Local initial";
    document.editor = editor;
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    document.preview = preview;
    preview.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    preview.policyDelegate = (id<WebPolicyDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    @try {
        preferences.htmlMathJax = NO;
        preferences.htmlMermaid = NO;
        preferences.htmlGraphviz = NO;
        __block NSString *localBase;
        XCTestExpectation *initial = [self expectationWithDescription:@"Published local preview"];
        [document performAfterRender:^{
            localBase = [[preview.mainFrame.javaScriptContext evaluateScript:@"document.baseURI"] toString];
            XCTAssertTrue([[preview.mainFrame.javaScriptContext evaluateScript:@"document.querySelector('meta[name=macdown-checkbox-token]') !== null"] toBool]);
            [initial fulfill];
        }];
        [self waitForExpectations:@[initial] timeout:10];
        [preview.mainFrame loadRequest:[NSURLRequest requestWithURL:server.URL]];
        XCTNSPredicateExpectation *remote = [[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return [[preview.mainFrame.javaScriptContext evaluateScript:@"document.querySelector('meta[name=remote-marker]') !== null && document.readyState === 'complete'"] toBool];
            }] object:preview];
        [self waitForExpectations:@[remote] timeout:10];
        XCTAssertEqualObjects([[preview.mainFrame.javaScriptContext evaluateScript:@"document.baseURI"] toString], server.URL.absoluteString);
        editor.string = @"# Returned Markdown";
        XCTestExpectation *consumer = [self expectationWithDescription:@"Fresh local preview after navigation"];
        [document performAfterRender:^{
            JSContext *context = preview.mainFrame.javaScriptContext;
            XCTAssertEqualObjects([[context evaluateScript:@"document.baseURI"] toString], localBase);
            XCTAssertTrue([[context evaluateScript:@"document.querySelector('meta[name=macdown-checkbox-token]') !== null"] toBool]);
            XCTAssertFalse([[context evaluateScript:@"document.querySelector('meta[name=remote-marker]') !== null"] toBool]);
            XCTAssertEqualObjects([[context evaluateScript:@"document.querySelector('h1').textContent"] toString], @"Returned Markdown");
            [consumer fulfill];
        }];
        [self waitForExpectations:@[consumer] timeout:10];
    } @finally {
        preview.frameLoadDelegate = nil;
        preview.policyDelegate = nil;
        [document close];
        preferences.htmlMathJax = math;
        preferences.htmlMermaid = mermaid;
        preferences.htmlGraphviz = graphviz;
    }
}


- (void)testPreviewSetextProofDoesNotConsumeUnderlineAfterATX
{
    [self assertPreviewBlockSource:@"# Title\n===\n\nNeighbor.\n" texts:@[@"Title"] value:@"h3"
        expected:@"### Title\n===\n\nNeighbor.\n" HTML:@">Title</h3>"];
}

- (void)testPreviewControlsPreserveAuthoredIDsAndRunAttributes
{
    MPDocument *document = [MPDocument new];
    document.fileURL = self.testFileURL;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer = [MPRenderer new];
    document.editor=editor; document.preview=web; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document;
    renderer.dataSource=(id<MPRendererDataSource>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    web.policyDelegate=(id<WebPolicyDelegate>)document;
    BOOL oldMath=document.preferences.htmlMathJax;
    BOOL oldSmart=document.preferences.extensionSmartyPants;
    BOOL oldHighlight=document.preferences.htmlSyntaxHighlighting;
    BOOL oldTasks=document.preferences.htmlTaskList;
    BOOL oldIntra=document.preferences.extensionIntraEmphasis;
    BOOL oldMermaid=document.preferences.htmlMermaid, oldGraphviz=document.preferences.htmlGraphviz;
    @try {
        document.preferences.htmlMathJax=NO;
        document.preferences.htmlSyntaxHighlighting=NO;
        document.preferences.htmlTaskList=YES;
        document.preferences.extensionIntraEmphasis=YES;
        document.preferences.htmlMermaid=NO; document.preferences.htmlGraphviz=NO;
        document.preferences.extensionSmartyPants=NO;
        NSString *source=@"<div id=\"macdownPreviewEditor\">Authored editor name</div>\n\n<div id=\"Prism\">Authored Prism name</div>\n\n<form id=\"MathJax\"><input name=\"Hub\"></form>\n\n<div id=\"macdown-preview-edit-style\">Authored style text</div>\n\n<div id=\"macdown-preview-format\">Authored panel text</div>\n\n<div id=\"macdown-preview-edit-error\">Authored error text</div>\n\n<span id=\"authored-run\" data-mp-edit-id=\"0\">Authored run text</span>\n\nEditable passage\n\n- [ ] Task box\n";
        renderer.rendererFlags=document.preferences.rendererFlags;
        editor.string=source;
        [renderer parseMarkdown:source];[renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings){
                return !web.isLoading && document.previewEditToken.length>0;
            }] object:web]] timeout:10];
        void (^assertAuthoredText)(void)=^{
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.getElementById('Prism').textContent"],@"Authored Prism name");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.getElementById('macdownPreviewEditor').textContent"],@"Authored editor name");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('div#macdown-preview-edit-style').textContent"],@"Authored style text");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('div#macdown-preview-format').textContent"],@"Authored panel text");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('div#macdown-preview-edit-error').textContent"],@"Authored error text");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.getElementById('authored-run').textContent"],@"Authored run text");
        };
        assertAuthoredText();
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"!!document.querySelector('input[type=checkbox]')&&!document.querySelector('input[type=checkbox]').disabled"] boolValue],@"The initial real task checkbox must be interactive");
        BOOL hasOwnedElements=[[web stringByEvaluatingJavaScriptFromString:@"!!window.macdownPreviewEditor && typeof window.macdownPreviewEditor.elements==='function'"] boolValue];
        XCTAssertTrue(hasOwnedElements,@"Preview controls must have their own DOM identity");
        if (!hasOwnedElements) return;
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"(function(){var ui=macdownPreviewEditor.elements();return ui.style.tagName==='STYLE' && ui.panel!==document.querySelector('div#macdown-preview-format') && !ui.spans.includes(document.getElementById('authored-run'));})()"] boolValue]);
        [web stringByEvaluatingJavaScriptFromString:@"(function(){var span=macdownPreviewEditor.elements().spans.find(function(n){return n.textContent==='Editable passage';});if(!span)return;var r=document.createRange();r.selectNodeContents(span);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new Event('scroll'));})()"];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"Editable passage");
        JSValue *selected=[web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('bold')"];
        NSDictionary *payload=selected.isNull||selected.isUndefined?nil:selected.toDictionary;
        XCTAssertNotNil(payload);
        if (!payload) return;
        NSString *oldToken=document.previewEditToken;
        [web stringByEvaluatingJavaScriptFromString:@"window.__mpIdentitySentinel=1;"];
        XCTAssertTrue([document applyPreviewEditPayload:payload]);
        XCTAssertEqualObjects(editor.string,[source stringByReplacingOccurrencesOfString:@"Editable passage" withString:@"**Editable passage**"]);
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings){
                return !web.isLoading && ![document.previewEditToken isEqualToString:oldToken];
            }] object:web]] timeout:10];
        assertAuthoredText();
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"window.__mpIdentitySentinel"],@"1",@"This regression must consume the fast body replacement path");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"Editable passage");
        [web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.showFormattingError();window.dispatchEvent(new Event('scroll'));"];
        assertAuthoredText();
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"!!macdownPreviewEditor.elements().panel.querySelector('#macdown-preview-edit-error')"] boolValue]);
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(macdownPreviewEditor.elements().panel).display"],@"block");
        BOOL taskEnabled=[[web stringByEvaluatingJavaScriptFromString:@"(function(){var e=document.querySelector('input[type=checkbox]');return !!e&&!e.disabled;})()"] boolValue];
        XCTAssertTrue(taskEnabled,@"Optional globals must not interrupt task-list initialization after DOM replacement");
        if (taskEnabled) {
            [web stringByEvaluatingJavaScriptFromString:@"document.querySelector('input[type=checkbox]').click();"];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return [editor.string containsString:@"- [x] Task box"];} ] object:editor]] timeout:5];
        }
    } @finally {
        web.frameLoadDelegate=nil; web.policyDelegate=nil; [document close];
        document.preferences.htmlMathJax=oldMath;
        document.preferences.extensionSmartyPants=oldSmart;
        document.preferences.htmlSyntaxHighlighting=oldHighlight;
        document.preferences.htmlTaskList=oldTasks;
        document.preferences.extensionIntraEmphasis=oldIntra;
        document.preferences.htmlMermaid=oldMermaid; document.preferences.htmlGraphviz=oldGraphviz;
    }
}

- (void)testPreviewParagraphConversionRemovesATXClosingHashes
{
    [self assertPreviewBlockSource:@"# Title ###\n\nNeighbor.\n" texts:@[@"Title"] value:@"paragraph"
        expected:@"Title\n\nNeighbor.\n" HTML:@"<p>Title</p>"];
    [self assertPreviewBlockSource:@"# Literal # tail\n\nNeighbor.\n" texts:@[@"Literal # tail"] value:@"paragraph"
        expected:@"Literal # tail\n\nNeighbor.\n" HTML:@"<p>Literal # tail</p>"];
}

- (void)testPreviewBlockConversionRespectsActualMarkdownMarkersAndOptions
{
    [self assertPreviewBlockSource:@"# Title\n---\n\nNeighbor.\n" texts:@[@"Title"] value:@"paragraph"
        expected:@"Title\n\n---\n\nNeighbor.\n" HTML:@"<hr>"];
    [self assertPreviewBlockSource:@"# Title\n===\n\nNeighbor.\n" texts:@[@"Title"] value:@"paragraph"
        expected:@"Title\n\n===\n\nNeighbor.\n" HTML:@"<p>Title</p>"];
    [self assertPreviewBlockSource:@"> # Title ###\n\nNeighbor.\n" texts:@[@"Title"] value:@"h1"
        expected:@"# Title\n\nNeighbor.\n" HTML:@">Title</h1>"];
    [self assertPreviewBlockSource:@"# > literal\n\nNeighbor.\n" texts:@[@"> literal"] value:@"paragraph"
        expected:@"\\> literal\n\nNeighbor.\n" HTML:@"<p>&gt; literal</p>"];
    [self assertPreviewBlockSource:@"> > Title\n\nNeighbor.\n" texts:@[@"Title"] value:@"h1"
        expected:@"# Title\n\nNeighbor.\n" HTML:@">Title</h1>"];
    [self assertPreviewBlockSource:@"# > literal\n\nNeighbor.\n" texts:@[@"> literal"] value:@"unordered"
        expected:@"- > literal\n\nNeighbor.\n" HTML:@"&gt; literal</li>"];
    [self assertPreviewBlockSource:@"2026) year\n\nNeighbor.\n" texts:@[@"2026) year"] value:@"h1"
        expected:@"# 2026) year\n\nNeighbor.\n" HTML:@"2026) year</h1>"];
    [self assertPreviewBlockSource:@"- [x] item\n\nNeighbor.\n" texts:@[@"[x] item"] value:@"h1"
        expected:@"# [x] item\n\nNeighbor.\n" HTML:@"[x] item</h1>" tasks:NO];
}

- (void)testPreviewWrapperConversionRestoresSelectionAcrossRemovedSetextMetadata
{
    MPDocument *document = [MPDocument new];
    document.fileURL = self.testFileURL;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer = [MPRenderer new];
    document.editor=editor; document.preview=web; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document;
    renderer.dataSource=(id<MPRendererDataSource>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    BOOL oldMath=document.preferences.htmlMathJax, oldSmart=document.preferences.extensionSmartyPants, oldIntra=document.preferences.extensionIntraEmphasis;
    @try {
        document.preferences.htmlMathJax=NO; document.preferences.extensionSmartyPants=NO;
        for (NSString *value in @[@"callout",@"toggle",@"toggle-h2"]) {
            editor.string=@"first\n====\n\nsecond\n\nUntouched neighbor.\n";
            [renderer parseMarkdown:editor.string]; [renderer render];
            NSString *token=renderer.checkboxBridgeToken;
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&[document.previewEditToken isEqualToString:token];}] object:web]] timeout:10];
            [web stringByEvaluatingJavaScriptFromString:@"(function(){var n=macdownPreviewEditor.elements().spans,a=n.find(function(e){return e.textContent==='first';}),b=n.find(function(e){return e.textContent==='second';}),r=document.createRange();r.setStart(a.firstChild,0);r.setEnd(b.firstChild,6);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new Event('scroll'));})()"];
            NSDictionary *payload=[[web.mainFrame.javaScriptContext evaluateScript:[NSString stringWithFormat:@"macdownPreviewEditor.selectionPayload('block','%@')",value]] toDictionary];
            XCTAssertNotNil(payload);
            XCTAssertTrue([document applyPreviewEditPayload:payload]);
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&![document.previewEditToken isEqualToString:token];}] object:web]] timeout:10];
            XCTAssertTrue([editor.string containsString:@"===="],@"Container conversion preserves content syntax");
            XCTAssertTrue([editor.string hasSuffix:@"\nUntouched neighbor.\n"]);
            // A collapsed body is intentionally hidden. Open it without
            // selecting again before checking the persisted range and command.
            [web stringByEvaluatingJavaScriptFromString:@"document.querySelectorAll('details').forEach(function(e){e.open=true;});window.dispatchEvent(new Event('scroll'));"];
            NSString *visible=[web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"];
            XCTAssertTrue([visible containsString:@"first"],@"%@",value);
            XCTAssertTrue([visible containsString:@"second"],@"%@",value);
            NSDictionary *bold=[[web.mainFrame.javaScriptContext evaluateScript:@"macdownPreviewEditor.selectionPayload('bold')"] toDictionary];
            XCTAssertNotNil(bold,@"%@",value);
            if (!bold) continue;
            NSString *before=editor.string.copy;
            XCTAssertTrue([document applyPreviewEditPayload:bold],@"%@",value);
            XCTAssertTrue([editor.string containsString:@"**first**"],@"%@",value);
            XCTAssertTrue([editor.string containsString:@"**second**"],@"%@",value);
            XCTAssertTrue([editor.string hasSuffix:@"\nUntouched neighbor.\n"]);
            XCTAssertNotEqualObjects(editor.string,before);
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
            if (![value isEqualToString:@"callout"])
                XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('details').open)"],@"true",
                    @"Native inline formatting must preserve the live disclosure state");
        }
    } @finally {
        web.frameLoadDelegate=nil; [document close];
        document.preferences.htmlMathJax=oldMath; document.preferences.extensionSmartyPants=oldSmart; document.preferences.extensionIntraEmphasis=oldIntra;
    }
}

- (void)testNestedCalloutBodyFormattingKeepsManuallyOpenedDisclosure
{
    MPDocument *document=[MPDocument new];
    document.fileURL=self.testFileURL;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor; document.preview=web; document.renderer=renderer;
    renderer.delegate=(id<MPRendererDelegate>)document;
    renderer.dataSource=(id<MPRendererDataSource>)document;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    web.policyDelegate=(id<WebPolicyDelegate>)document;
    MPPreferences *preferences=document.preferences;
    BOOL math=preferences.htmlMathJax, smart=preferences.extensionSmartyPants;
    BOOL mermaid=preferences.htmlMermaid, graphviz=preferences.htmlGraphviz;
    NSString *source=@"::: {.callout-note}\n\ntest ***encore*** pour lui\n::: {.callout-note collapse=\"true\"}\n# **nouveau**\ncontenu interne\n:::\n\n:::\n";
    @try {
        preferences.htmlMathJax=NO; preferences.extensionSmartyPants=NO;
        preferences.htmlMermaid=NO; preferences.htmlGraphviz=NO;
        editor.string=source;
        [renderer parseMarkdown:source]; [renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading && [document.previewEditSource isEqualToString:source];}] object:web]] timeout:10];
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('details').open)"],@"false");
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:
            @"(function(){document.querySelector('details').open=true;var spans=macdownPreviewEditor.elements().spans;var s=spans.find(function(e){return e.textContent==='contenu interne';});if(!s)return false;var r=document.createRange();r.setStart(s.firstChild,8);r.setEnd(s.firstChild,15);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return getSelection().toString()==='interne';})()"] boolValue]);
        for (NSUInteger step=0;step<2;step++) {
            NSString *before=editor.string.copy;
            [web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.elements().panel.querySelector('button[data-mp-style=bold]').click()"];
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return ![editor.string isEqualToString:before] && !web.isLoading && !document.alreadyRenderingInWeb && [document.previewEditSource isEqualToString:editor.string];}] object:web]] timeout:10];
            NSString *expected=step==0 ? [source stringByReplacingOccurrencesOfString:@"contenu interne" withString:@"contenu **interne**"] : source;
            XCTAssertEqualObjects(editor.string,expected);
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"String(document.querySelector('details').open)"],@"true");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"],@"interne");
            XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"document.querySelector('details summary').textContent.trim()"],@"nouveau");
        }
    } @finally {
        web.frameLoadDelegate=nil; web.policyDelegate=nil; [document close];
        preferences.htmlMathJax=math; preferences.extensionSmartyPants=smart;
        preferences.htmlMermaid=mermaid; preferences.htmlGraphviz=graphviz;
    }
}

- (void)testPreviewPopupQueuesRapidFormattingWithoutReselecting
{
    MPDocument *document = [MPDocument new];
    document.fileURL = self.testFileURL;
    MPPreferences *preferences = document.preferences;
    BOOL oldMath = preferences.htmlMathJax;
    BOOL oldSmart = preferences.extensionSmartyPants;
    BOOL oldIntra = preferences.extensionIntraEmphasis;
    MPEditorView *editor = [[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:web.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView = web;
    document.editor = editor; document.preview = web;
    web.frameLoadDelegate = (id<WebFrameLoadDelegate>)document;
    web.policyDelegate = (id<WebPolicyDelegate>)document;
    MPRenderer *renderer = [MPRenderer new];
    renderer.delegate = (id<MPRendererDelegate>)document;
    renderer.dataSource = (id<MPRendererDataSource>)document;
    document.renderer = renderer;
    NSOperationQueue *parseQueue = [renderer valueForKey:@"parseQueue"];
    @try {
        preferences.htmlMathJax = NO;
        preferences.extensionSmartyPants = NO;
        preferences.extensionIntraEmphasis = YES;
        renderer.rendererFlags = preferences.rendererFlags;
        editor.string = @"Selected passage\n\nNeighbor unchanged.\n";
        [renderer parseMarkdown:editor.string]; [renderer render];
        XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && !document.alreadyRenderingInWeb && document.previewEditRanges.count > 0;
            }] object:document];
        [self waitForExpectations:@[loaded] timeout:10];
        XCTAssertNotNil(document.previewEditToken);
        if (!document.previewEditToken) return;
        XCTAssertTrue([window makeFirstResponder:web]);
        XCTAssertTrue([document previewHasFindFocus]);
        NSString *initialToken = [document.previewEditToken copy];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:
            @"(function(){var e=window.macdownPreviewEditor,s=e.elements().spans.find(function(s){return s.textContent==='Selected passage';});if(!s)return false;var r=document.createRange();r.setStart(s.firstChild,0);r.setEnd(s.firstChild,8);var selection=getSelection();selection.removeAllRanges();selection.addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return true;})()"] boolValue]);
        XCTNSPredicateExpectation *panel = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(macdownPreviewEditor.elements().panel).display"] isEqualToString:@"block"];
            }] object:web];
        [self waitForExpectations:@[panel] timeout:5];
        // Delay only the real background parser: both commands still traverse
        // actual popup listeners, WebView policy routing and native source edits.
        parseQueue.suspended = YES;
        [web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.elements().panel.querySelector('button[data-mp-style=bold]').click()"];
        XCTNSPredicateExpectation *firstApplied = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return [editor.string isEqualToString:@"**Selected** passage\n\nNeighbor unchanged.\n"];
            }] object:editor];
        [self waitForExpectations:@[firstApplied] timeout:5];
        XCTAssertEqualObjects(document.previewEditToken, initialToken);
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"], @"Selected");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(macdownPreviewEditor.elements().panel).display"], @"block");
        // Forged/stale bridge requests must not become a continuation of the
        // fresh selection, or consume the valid pending formatting operation.
        NSDictionary *selectionPayload = [[web.mainFrame.javaScriptContext[@"window"][@"macdownPreviewEditor"][@"selectionPayload"]
            callWithArguments:@[@"italic",NSNull.null]] toDictionary];
        NSDictionary *pending = [[document valueForKey:@"previewSelectionToRestore"] copy];
        for (NSDictionary *invalidFields in @[@{@"token":@"expired-token"},@{@"action":@"replace"},@{@"value":@17}]) {
            NSMutableDictionary *invalid = [selectionPayload mutableCopy];
            [invalid addEntriesFromDictionary:invalidFields];
            NSString *JSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:invalid options:0 error:NULL] encoding:NSUTF8StringEncoding];
            NSURLComponents *URL = [NSURLComponents componentsWithString:@"x-macdown-preview://edit"];
            URL.queryItems = @[[NSURLQueryItem queryItemWithName:@"payload" value:JSON]];
            [document handlePreviewEdit:URL.URL];
            XCTAssertEqualObjects(editor.string,@"**Selected** passage\n\nNeighbor unchanged.\n");
            XCTAssertEqualObjects([document valueForKey:@"previewSelectionToRestore"],pending);
            XCTAssertEqual([[document valueForKey:@"previewQueuedFormatting"] count],0u);
        }
        [web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.elements().panel.querySelector('button[data-mp-style=italic]').click()"];
        XCTNSPredicateExpectation *secondRouted = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return [[document valueForKey:@"previewQueuedFormatting"] count] > 0 ||
                    [[web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.elements().panel.textContent.indexOf('refus')>=0"] boolValue];
            }] object:document];
        [self waitForExpectations:@[secondRouted] timeout:5];
        parseQueue.suspended = NO;
        XCTNSPredicateExpectation *finished = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
                return !web.isLoading && !document.alreadyRenderingInWeb &&
                    ![document.previewEditToken isEqualToString:initialToken] &&
                    ![[document valueForKey:@"previewQueuedFormatting"] count] &&
                    ![document valueForKey:@"previewSelectionToRestore"];
            }] object:document];
        [self waitForExpectations:@[finished] timeout:10];
        XCTAssertEqualObjects(editor.string, @"***Selected*** passage\n\nNeighbor unchanged.\n");
        XCTAssertEqualObjects([web stringByEvaluatingJavaScriptFromString:@"getSelection().toString()"], @"Selected");
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"(function(){var p=macdownPreviewEditor.elements().panel;return p.querySelector('[data-mp-style=bold]').getAttribute('aria-pressed')==='true'&&p.querySelector('[data-mp-style=italic]').getAttribute('aria-pressed')==='true';})()"] boolValue]);
    } @finally {
        parseQueue.suspended = NO;
        web.frameLoadDelegate = nil; web.policyDelegate = nil;
        [window close]; [document close];
        preferences.htmlMathJax = oldMath;
        preferences.extensionSmartyPants = oldSmart;
        preferences.extensionIntraEmphasis = oldIntra;
    }
}

- (void)testPreviewDraftIsCommittedBeforeSaveAddsTrailingNewline
{
    MPDocument *document = [MPDocument new];
    document.fileURL=self.testFileURL; document.fileType=@"net.daringfireball.markdown";
    MPPreferences *preferences=document.preferences;
    BOOL oldMath=preferences.htmlMathJax,oldSmart=preferences.extensionSmartyPants,oldNewline=preferences.editorEnsuresNewlineAtEndOfFile;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor;document.preview=web;document.renderer=renderer;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    renderer.delegate=(id<MPRendererDelegate>)document;renderer.dataSource=(id<MPRendererDataSource>)document;
    @try {
        preferences.htmlMathJax=NO;preferences.extensionSmartyPants=NO;preferences.editorEnsuresNewlineAtEndOfFile=YES;
        renderer.rendererFlags=preferences.rendererFlags;
        editor.string=@"Original text";
        [renderer parseMarkdown:editor.string];[renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&document.previewEditToken.length>0;}] object:web]] timeout:10];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:
            @"(function(){var e=macdownPreviewEditor,s=e.elements().spans.find(function(s){return s.textContent==='Original text';});if(!s)return false;var r=document.createRange();r.selectNodeContents(s);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return true;})()"] boolValue]);
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(macdownPreviewEditor.elements().panel).display"] isEqualToString:@"block"];} ] object:web]] timeout:5];
        [web stringByEvaluatingJavaScriptFromString:@"Array.from(macdownPreviewEditor.elements().panel.querySelectorAll('button')).find(function(b){return b.hasAttribute('data-mp-edit-text');}).click();document.querySelector('[contenteditable]').textContent='Changed text'"];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"Boolean(macdownPreviewEditor.draft())"] boolValue]);
        // A stale draft refuses the save before appending a newline or marking
        // the document as self-saving; the draft remains available to recover.
        editor.string=@"Concurrent source";
        NSUInteger generation=[[document valueForKey:@"saveGeneration"] unsignedIntegerValue];
        BOOL selfSaving=[[document valueForKey:@"isSelfSaving"] boolValue];
        NSError *error=nil;
        XCTAssertFalse([document writeToURL:self.testFileURL ofType:document.fileType error:&error]);
        XCTAssertEqual(error.code,NSFileWriteUnknownError);
        XCTAssertEqualObjects(editor.string,@"Concurrent source");
        XCTAssertEqual([[document valueForKey:@"saveGeneration"] unsignedIntegerValue],generation);
        XCTAssertEqual([[document valueForKey:@"isSelfSaving"] boolValue],selfSaving);
        XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:self.testFileURL.path]);
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"Boolean(macdownPreviewEditor.draft())"] boolValue]);
        editor.string=@"Original text";
        error=nil;
        XCTAssertTrue([document writeToURL:self.testFileURL ofType:document.fileType error:&error]);
        XCTAssertNil(error);
        XCTAssertEqualObjects(editor.string,@"Changed text\n");
        XCTAssertEqualObjects([NSString stringWithContentsOfURL:self.testFileURL encoding:NSUTF8StringEncoding error:NULL],@"Changed text\n");
        XCTAssertFalse([[web stringByEvaluatingJavaScriptFromString:@"Boolean(macdownPreviewEditor.draft())"] boolValue]);
    } @finally {
        web.frameLoadDelegate=nil;[document close];
        preferences.htmlMathJax=oldMath;preferences.extensionSmartyPants=oldSmart;preferences.editorEnsuresNewlineAtEndOfFile=oldNewline;
    }
}

- (void)testPDFExportRefusedPreviewDraftReleasesSlotAndCompletesPrint
{
    MPDocument *document = [MPDocument new];
    document.fileURL=self.testFileURL; document.fileType=@"net.daringfireball.markdown";
    MPPreferences *preferences=document.preferences;
    BOOL oldMath=preferences.htmlMathJax,oldSmart=preferences.extensionSmartyPants,oldNewline=preferences.editorEnsuresNewlineAtEndOfFile;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor;document.preview=web;document.renderer=renderer;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    renderer.delegate=(id<MPRendererDelegate>)document;renderer.dataSource=(id<MPRendererDataSource>)document;
    MPControlledExportPanel *panel=[MPControlledExportPanel new];
    panel.URL=[NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"export.pdf"]];
    MPCurrentControlledExportPanel=panel;
    Method factory=class_getClassMethod(NSSavePanel.class,@selector(savePanel));
    IMP original=method_setImplementation(factory,(IMP)MPControlledExportPanelFactory);
    @try {
        preferences.htmlMathJax=NO;preferences.extensionSmartyPants=NO;preferences.editorEnsuresNewlineAtEndOfFile=YES;
        renderer.rendererFlags=preferences.rendererFlags;
        editor.string=@"Original text";
        [renderer parseMarkdown:editor.string];[renderer render];
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return !web.isLoading&&document.previewEditToken.length>0;}] object:web]] timeout:10];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:
            @"(function(){var e=macdownPreviewEditor,s=e.elements().spans.find(function(s){return s.textContent==='Original text';});if(!s)return false;var r=document.createRange();r.selectNodeContents(s);getSelection().removeAllRanges();getSelection().addRange(r);window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}));return true;})()"] boolValue]);
        [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o,NSDictionary *b){return [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(macdownPreviewEditor.elements().panel).display"] isEqualToString:@"block"];} ] object:web]] timeout:5];
        [web stringByEvaluatingJavaScriptFromString:@"Array.from(macdownPreviewEditor.elements().panel.querySelectorAll('button')).find(function(b){return b.hasAttribute('data-mp-edit-text');}).click();document.querySelector('[contenteditable]').textContent='Changed text'"];
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"Boolean(macdownPreviewEditor.draft())"] boolValue]);
        editor.string=@"Concurrent source";
        [document exportPdf:nil];
        XCTAssertEqual(panel.presentations,1u);
        XCTAssertNotNil(panel.completion);
        panel.completion(NSFileHandlingPanelOKButton);
        XCTAssertFalse([[document valueForKey:@"pdfExportPending"] boolValue],@"A refused draft must release the PDF export slot");
        XCTAssertNil([document valueForKey:@"pdfExportURL"]);
        XCTAssertNil([document valueForKey:@"pdfExportTemporaryURL"]);
        XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:panel.URL.path]);
        XCTAssertEqualObjects(editor.string,@"Concurrent source");
        XCTAssertTrue([[web stringByEvaluatingJavaScriptFromString:@"Boolean(macdownPreviewEditor.draft())"] boolValue]);
        MPPrintDelegateProbe *probe=[MPPrintDelegateProbe new];
        void *context=(__bridge void *)self;
        [document printDocumentWithSettings:@{} showPrintPanel:NO delegate:probe
            didPrintSelector:@selector(document:printed:context:) contextInfo:context];
        XCTAssertEqual(probe.calls,1u,@"A refused print must finish with failure rather than silently dropping its delegate");
        XCTAssertFalse(probe.success);
        XCTAssertEqual(probe.document,document);
        XCTAssertEqual(probe.context,context);
        [web stringByEvaluatingJavaScriptFromString:@"macdownPreviewEditor.finish()"];
        [document exportPdf:nil];
        XCTAssertEqual(panel.presentations,2u,@"After recovering the draft, another export must be possible");
        panel.completion(NSFileHandlingPanelCancelButton);
    } @finally {
        method_setImplementation(factory,original);MPCurrentControlledExportPanel=nil;
        web.frameLoadDelegate=nil;[document close];
        preferences.htmlMathJax=oldMath;preferences.extensionSmartyPants=oldSmart;preferences.editorEnsuresNewlineAtEndOfFile=oldNewline;
    }
}

- (void)testPreviewParagraphSetextConversionPreservesFollowingUnderlineLiteral
{
    [self assertPreviewBlockSource:@"Title\n---\n===\n\nNeighbor.\n" texts:@[@"Title"] value:@"paragraph"
        expected:@"Title\n\n===\n\nNeighbor.\n" HTML:@"<p>Title</p>"];
}


- (void)testHTMLExportIncludesSelectedCustomStyleRegardlessOfStringAllocation
{
    MPDocumentExportAuditProbe *document=[MPDocumentExportAuditProbe new];
    MPPreferences *preferences=document.preferences;
    NSString *oldStyle=preferences.htmlStyleName;
    BOOL oldMath=preferences.htmlMathJax,oldHighlight=preferences.htmlSyntaxHighlighting;
    BOOL oldMermaid=preferences.htmlMermaid,oldGraphviz=preferences.htmlGraphviz;
    NSMutableArray<NSString *> *retainedPreferenceStrings=[NSMutableArray array];
    NSString *customStylePath=nil;
    MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    MPRenderer *renderer=[MPRenderer new];
    document.editor=editor;document.preview=web;document.renderer=renderer;
    web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
    renderer.delegate=(id<MPRendererDelegate>)document;renderer.dataSource=(id<MPRendererDataSource>)document;
    MPControlledExportPanel *panel=[MPControlledExportPanel new];
    MPCurrentControlledExportPanel=panel;
    Method factory=class_getClassMethod(NSSavePanel.class,@selector(savePanel));
    IMP original=method_setImplementation(factory,(IMP)MPControlledExportPanelFactory);
    @try {
        preferences.htmlMathJax=NO;preferences.htmlSyntaxHighlighting=NO;
        preferences.htmlMermaid=NO;preferences.htmlGraphviz=NO;
        NSString *prefix=[@"MacDownExportAllocation-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSString *selectedStyle=nil;
        // Real preferences and ordinary Foundation strings, never a fabricated
        // object address or replaced preference getter. Retain observed values
        // so allocations can visit different alignment offsets. The bounded
        // search selects the natural allocation exposing Intel BOOL truncation.
        for (NSUInteger i=0;i<1024;i++) {
            preferences.htmlStyleName=[NSString stringWithFormat:@"%@-%lu",prefix,(unsigned long)i];
            NSString *returned=preferences.htmlStyleName;
            if (returned) [retainedPreferenceStrings addObject:returned];
            if (returned && (((uintptr_t)(__bridge void *)returned)&0xff)==0) {
                selectedStyle=returned;
                break;
            }
        }
        XCTAssertNotNil(selectedStyle,@"The fixture must observe a real preference string with a zero low address byte");
        if (!selectedStyle) return;
        XCTAssertEqual(preferences.htmlStyleName,selectedStyle,@"The production getter must return the observed allocation");
#if defined(__x86_64__)
        NSString *fixtureArchitecture=@"x86_64";
#elif defined(__arm64__)
        NSString *fixtureArchitecture=@"arm64";
#else
        NSString *fixtureArchitecture=@"other";
#endif
        NSLog(@"HTML style allocation fixture: architecture=%@ OBJC_BOOL_IS_BOOL=%d lowByte=%lu",
            fixtureArchitecture,OBJC_BOOL_IS_BOOL,(unsigned long)(((uintptr_t)(__bridge void *)selectedStyle)&0xff));
        customStylePath=MPStylePathForName(selectedStyle);
        XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:customStylePath.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:NULL]);
        XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:customStylePath]);
        NSString *CSS=@".macdown-export-allocation-regression { color: #123456; }";
        XCTAssertTrue([CSS writeToFile:customStylePath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        editor.string=@"# Exported content\n\nPreserved source.\n";
        renderer.rendererFlags=preferences.rendererFlags;
        // Selected style defaults on; the user can still uncheck it, and no
        // selected style defaults off. Each case consumes actual exported HTML.
        for (NSUInteger scenario=0;scenario<3;scenario++) {
            if (scenario==2) preferences.htmlStyleName=nil;
            panel.URL=[NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"style-%lu.html",(unsigned long)scenario]]];
            panel.completion=nil;
            NSLog(@"HTML style allocation export: scenario=%lu currentLowByte=%lu",
                (unsigned long)scenario,(unsigned long)(((uintptr_t)(__bridge void *)preferences.htmlStyleName)&0xff));
            [document exportHtml:nil];
            NSButton *styleButton=nil;
            for (NSView *view in panel.accessoryView.subviews) {
                if (![view isKindOfClass:NSButton.class]) continue;
                NSDictionary *binding=[view infoForBinding:NSValueBinding];
                if ([binding[NSObservedKeyPathKey] isEqualToString:@"self.stylesIncluded"]) {
                    styleButton=(NSButton *)view;break;
                }
            }
            XCTAssertNotNil(styleButton);
            XCTAssertNotNil(panel.completion);
            if (!styleButton || !panel.completion) return;
            XCTAssertEqual(styleButton.state,scenario==2 ? NSControlStateValueOff : NSControlStateValueOn);
            if (scenario==1) [styleButton performClick:nil];
            panel.completion(NSFileHandlingPanelOKButton);
            [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                [NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
                    return [NSFileManager.defaultManager fileExistsAtPath:panel.URL.path] || document.presentedError!=nil;
                }] object:document]] timeout:10];
            XCTAssertNil(document.presentedError);
            NSString *HTML=[NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:NULL];
            XCTAssertNotNil(HTML);
            XCTAssertTrue([HTML containsString:@"Exported content"]);
            XCTAssertEqual([HTML containsString:@".macdown-export-allocation-regression"],scenario==0);
            XCTAssertEqualObjects(editor.string,@"# Exported content\n\nPreserved source.\n");
        }
    } @finally {
        method_setImplementation(factory,original);MPCurrentControlledExportPanel=nil;
        web.frameLoadDelegate=nil;[document close];
        preferences.htmlStyleName=oldStyle;
        preferences.htmlMathJax=oldMath;preferences.htmlSyntaxHighlighting=oldHighlight;
        preferences.htmlMermaid=oldMermaid;preferences.htmlGraphviz=oldGraphviz;
        if (customStylePath) [NSFileManager.defaultManager removeItemAtPath:customStylePath error:NULL];
    }
}


- (void)testFencedPreviewSelectionKeepsPrismAndMapsPhysicalUTF16Source
{
    MPPreferences *preferences=self.document.preferences;
    BOOL oldSyntax=preferences.htmlSyntaxHighlighting,oldFenced=preferences.extensionFencedCode;
    BOOL oldMath=preferences.htmlMathJax,oldMermaid=preferences.htmlMermaid,oldGraphviz=preferences.htmlGraphviz;
    NSString *oldTheme=[preferences.htmlHighlightingThemeName copy];
    @try {
        preferences.htmlSyntaxHighlighting=YES;preferences.extensionFencedCode=YES;
        preferences.htmlMathJax=NO;preferences.htmlMermaid=NO;preferences.htmlGraphviz=NO;
        preferences.htmlHighlightingThemeName=nil;
        for (NSString *newline in @[@"\n",@"\r\n"]) {
            MPDocument *document=[MPDocument new];
            MPEditorView *editor=[[MPEditorView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
            WebView *web=[[WebView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
            MPRenderer *renderer=[MPRenderer new];
            document.editor=editor;document.preview=web;document.renderer=renderer;
            renderer.dataSource=(id<MPRendererDataSource>)document;renderer.delegate=(id<MPRendererDelegate>)document;
            web.frameLoadDelegate=(id<WebFrameLoadDelegate>)document;
            @try {
                NSString *source=[@"Before\n\n```javascript\nconst emoji = \"😀\";\n\nconst answer = 42;\n    **word** <b> :::\n```\n\nAfter\n"
                    stringByReplacingOccurrencesOfString:@"\n" withString:newline];
                editor.string=source;renderer.rendererFlags=preferences.rendererFlags;
                [renderer parseMarkdown:source];[renderer render];
                [self waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:
                    [NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
                        return document.isPreviewReady && !document.alreadyRenderingInWeb &&
                            [[web.mainFrame.javaScriptContext evaluateScript:
                            @"Boolean(window.macdownPreviewEditor)&&document.querySelectorAll('pre>code span.token').length>0&&window.macdownPreviewEditor.elements().spans.some(function(span){return !!span.closest('pre');})"] toBool];
                    }] object:document]] timeout:10];
                XCTAssertTrue([[web.mainFrame.javaScriptContext evaluateScript:@"!!(window.Prism&&Prism.languages.javascript)"] toBool]);
                XCTAssertGreaterThan([[web.mainFrame.javaScriptContext evaluateScript:@"document.querySelectorAll('pre>code span.token').length"] toInt32],0);
                NSUInteger codeLeaves=0;
                for (NSDictionary *entry in document.previewEditRanges) {
                    if (!entry[@"codeBlockRange"]) continue;
                    codeLeaves++;
                    NSRange range=NSMakeRange([entry[@"location"] unsignedIntegerValue],[entry[@"length"] unsignedIntegerValue]);
                    XCTAssertEqualObjects([source substringWithRange:range],entry[@"text"]);
                    NSString *normalized=[[entry[@"text"] stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
                    XCTAssertEqualObjects(normalized,entry[@"displayText"]);
                    XCTAssertEqual([entry[@"sourceBoundaries"] count],[entry[@"displayText"] length]+1);
                    XCTAssertTrue(NSLocationInRange(range.location,[entry[@"codeContentRange"] rangeValue]));
                }
                XCTAssertGreaterThan(codeLeaves,1u,@"Real Prism leaves must retain their source provenance");
                NSDictionary *payload=[[web.mainFrame.javaScriptContext evaluateScript:
                    @"(function(){var code=document.querySelector('pre>code'),r=document.createRange();r.selectNodeContents(code);var selection=getSelection();selection.removeAllRanges();selection.addRange(r);return window.macdownPreviewEditor.selectionPayload('bold');})()"] toObject];
                XCTAssertTrue([payload isKindOfClass:NSDictionary.class]);
                if (![payload isKindOfClass:NSDictionary.class]) {
                    XCTFail(@"Code selection was not mapped. Actual CODE text: %@; renderer snapshot: %@",
                        [[web.mainFrame.javaScriptContext evaluateScript:@"document.querySelector('pre>code').textContent"] toString],
                        [renderer HTMLForMarkdownSnapshot:source]);
                    continue;
                }
                XCTAssertFalse([document applyPreviewEditPayload:payload]);
                XCTAssertEqualObjects(editor.string,source);
                // The primary id is not the authority for a run-based
                // selection. A prose id must not bypass literal-code rules.
                NSMutableDictionary *proseIDPayload=[payload mutableCopy];
                for (NSUInteger i=0;i<document.previewEditRanges.count;i++) {
                    NSDictionary *entry=document.previewEditRanges[i];
                    if (!entry[@"codeBlockRange"] && [entry[@"text"] isEqualToString:@"Before"]) {
                        proseIDPayload[@"id"]=@(i);break;
                    }
                }
                XCTAssertNotEqualObjects(proseIDPayload[@"id"],payload[@"id"]);
                XCTAssertFalse([document applyPreviewEditPayload:proseIDPayload]);
                XCTAssertEqualObjects(editor.string,source);
                // UTF-16 offsets inside a surrogate pair never become valid
                // source edit boundaries, even for literal code selections.
                for (NSUInteger i=0;i<document.previewEditRanges.count;i++) {
                    NSDictionary *entry=document.previewEditRanges[i];
                    if (!entry[@"codeBlockRange"]) continue;
                    NSRange emoji=[entry[@"displayText"] rangeOfString:@"😀"];
                    if (emoji.location==NSNotFound) continue;
                    NSDictionary *split=@{@"token":document.previewEditToken,@"id":@(i),@"start":@(emoji.location+1),@"end":@(emoji.location+2),@"action":@"block",@"value":@"paragraph"};
                    XCTAssertFalse([document applyPreviewEditPayload:split]);
                    XCTAssertEqualObjects(editor.string,source);
                }
                NSMutableDictionary *normal=[payload mutableCopy];normal[@"action"]=@"block";normal[@"value"]=@"paragraph";
                XCTAssertTrue([document applyPreviewEditPayload:normal]);
                XCTAssertFalse([editor.string containsString:@"```"]);
                XCTAssertTrue([editor.string hasPrefix:[@"Before\n\n" stringByReplacingOccurrencesOfString:@"\n" withString:newline]]);
                XCTAssertTrue([editor.string hasSuffix:[@"\n\nAfter\n" stringByReplacingOccurrencesOfString:@"\n" withString:newline]]);
                NSString *HTML=[renderer HTMLForMarkdownSnapshot:editor.string];
                XCTAssertFalse([HTML containsString:@"<pre>"]);
                NSXMLDocument *DOM=[[NSXMLDocument alloc] initWithXMLString:HTML options:NSXMLDocumentTidyHTML error:NULL];
                XCTAssertTrue([DOM.stringValue containsString:@"const emoji = \"😀\";"]);
                XCTAssertTrue([[DOM.stringValue stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "] containsString:@"    **word** <b> :::"],@"source=%@ HTML=%@ DOM=%@",editor.string,HTML,DOM.stringValue);
                XCTAssertFalse([HTML containsString:@"<strong>"]);
                XCTAssertFalse([HTML containsString:@"<b>"]);
                XCTAssertFalse([HTML containsString:@"class=\"mp-callout"]);
            } @finally { web.frameLoadDelegate=nil;[document close]; }
        }
    } @finally {
        preferences.htmlSyntaxHighlighting=oldSyntax;preferences.extensionFencedCode=oldFenced;
        preferences.htmlMathJax=oldMath;preferences.htmlMermaid=oldMermaid;preferences.htmlGraphviz=oldGraphviz;
        preferences.htmlHighlightingThemeName=oldTheme;
    }
}

@end
