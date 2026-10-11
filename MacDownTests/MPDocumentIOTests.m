//
//  MPDocumentIOTests.m
//  MacDownTests
//
//  Tests for file I/O and document lifecycle functionality.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPPreferences.h"
#import "MPRenderer.h"
#import "MPEditorView.h"
#import <sys/stat.h>

@interface MPRenderer (ScriptingContractTesting)
- (void)parseMarkdown:(NSString *)markdown;
@end

@interface MPDocument (ScriptingContractTesting)
@property (strong) MPRenderer *renderer;
@property (weak) MPEditorView *editor;
@end

@interface MPDocument (LinkTargetTesting)
@property (strong) NSURL *currentBaseUrl;
- (BOOL)canAutomaticallyCreateLinkedFileAtURL:(NSURL *)url;
- (NSURL *)previewSafeBaseURL:(NSURL *)baseURL;
- (IBAction)toggleAutoSave:(id)sender;
- (BOOL)shouldBypassSafeSaveForURL:(NSURL *)url;
@property (nonatomic, copy) BOOL (^volumeLocalityChecker)(NSString *path);
@end

@interface MPDocumentIOTests : XCTestCase
@property (strong) MPDocument *document;
@property (strong) NSURL *testFileURL;
@property (strong) NSString *testDirectory;
@property (strong) NSFileManager *fileManager;
@property (strong) NSUndoManager *scriptUndoManager;
@property (strong) NSNumber *scriptOriginalGroupsByEvent;
@property (strong) NSNumber *scriptOriginalAutoSave;
@end

@implementation MPDocumentIOTests

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
    if (self.scriptOriginalGroupsByEvent) {
        self.scriptUndoManager.groupsByEvent = self.scriptOriginalGroupsByEvent.boolValue;
        self.scriptOriginalGroupsByEvent = nil;
        self.scriptUndoManager = nil;
    }
    if (self.scriptOriginalAutoSave) {
        [MPPreferences sharedInstance].editorAutoSave = self.scriptOriginalAutoSave.boolValue;
        self.scriptOriginalAutoSave = nil;
    }
    // Clean up test files and directory
    if (self.testDirectory) {
        [self.fileManager removeItemAtPath:self.testDirectory error:nil];
    }

    self.document = nil;
    self.testFileURL = nil;
    self.testDirectory = nil;

    [super tearDown];
}

#pragma mark - API & Data Tests

- (void)testNativeUntitledAutosavePreservesContentAndHasRecoveryLocation
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL original = preferences.editorAutoSave;
    preferences.editorAutoSave = YES;
    [self addTeardownBlock:^{ preferences.editorAutoSave = original; }];
    NSDocumentController *controller = NSDocumentController.sharedDocumentController;
    NSError *error = nil;
    MPDocument *document = (MPDocument *)[controller
        openUntitledDocumentAndDisplay:YES error:&error];
    XCTAssertNotNil(document, @"%@", error);
    if (!document) return;
    [self addTeardownBlock:^{
        NSURL *draft = document.isDraft ? document.fileURL : nil;
        NSURL *recovery = document.autosavedContentsFileURL;
        [document updateChangeCount:NSChangeCleared];
        [document close];
        if (draft) [[NSFileManager defaultManager] removeItemAtURL:draft error:NULL];
        if (recovery) [[NSFileManager defaultManager] removeItemAtURL:recovery error:NULL];
    }];
    NSUndoManager *undo = document.undoManager;
    BOOL groups = undo.groupsByEvent;
    undo.groupsByEvent = NO;
    [self addTeardownBlock:^{ undo.groupsByEvent = groups; }];
    [document.undoManager beginUndoGrouping];
    [document.editor insertText:@"Draft recovery é 日本語\n"
              replacementRange:NSMakeRange(0, 0)];
    [document.editor breakUndoCoalescing];
    [document.undoManager endUndoGrouping];
    XCTAssertEqualObjects(document.markdown, @"Draft recovery é 日本語\n");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!document.isDocumentEdited && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    XCTAssertTrue(document.isDocumentEdited);
    XCTestExpectation *saved = [self expectationWithDescription:@"Native draft autosave"];
    [document autosaveWithImplicitCancellability:NO completionHandler:^(NSError *saveError) {
        XCTAssertNil(saveError);
        NSURL *location = document.fileURL ?: document.autosavedContentsFileURL;
        XCTAssertNotNil(location);
        NSString *bytes = [NSString stringWithContentsOfURL:location
                          encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertEqualObjects(bytes, @"Draft recovery é 日本語\n");
        [saved fulfill];
    }];
    [self waitForExpectations:@[saved] timeout:10];
}

- (void)testReadFromDataValidUTF8
{
    // Create valid UTF-8 markdown data
    NSString *testMarkdown = @"# Test Document\n\nThis is a **test** with _markdown_.";
    NSData *data = [testMarkdown dataUsingEncoding:NSUTF8StringEncoding];

    // Call readFromData:ofType:error:
    NSError *error = nil;
    BOOL success = [self.document readFromData:data
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    // Verify no error and success
    XCTAssertTrue(success, @"readFromData:ofType:error: should succeed with valid UTF-8 data");
    XCTAssertNil(error, @"No error should be returned for valid UTF-8 data");

    // Note: We cannot verify the content was loaded into the markdown property
    // in headless CI because that requires the editor outlet to be initialized,
    // which doesn't happen without a display server. The API-level test above
    // verifies that the method succeeds.
}

- (void)testReadFromDataInvalidEncoding
{
    // Create data with invalid UTF-8 encoding (Latin-1 with special characters)
    // The character 0xE9 is valid in Latin-1 (é) but invalid as standalone UTF-8
    const unsigned char bytes[] = {0x54, 0x65, 0x73, 0x74, 0x20, 0xE9, 0x20, 0x74, 0x65, 0x78, 0x74};
    NSData *invalidData = [NSData dataWithBytes:bytes length:sizeof(bytes)];

    // Call readFromData:ofType:error:
    NSError *error = nil;
    BOOL success = [self.document readFromData:invalidData
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    // According to the implementation (line 550-551), it returns NO when conversion fails
    XCTAssertFalse(success, @"readFromData:ofType:error: should return NO for invalid UTF-8 data");

    // Note: The current implementation does not set an error when returning NO,
    // it simply returns NO when [[NSString alloc] initWithData:encoding:] returns nil
}

- (void)testReadFromDataWithCRLFLineEndings
{
    // Windows-created files use CRLF (\r\n). This is valid UTF-8, so the load
    // must succeed. On load, \r\n should be normalized to \n so downstream
    // rendering and preprocessing see only LF line endings (Issue #382).
    NSString *crlfMarkdown = @"# Heading\r\n\r\nParagraph text.\r\n";
    NSData *crlfData = [crlfMarkdown dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    BOOL success = [self.document readFromData:crlfData
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    XCTAssertTrue(success, @"readFromData:ofType:error: should succeed with CRLF data");
    XCTAssertNil(error, @"No error should occur loading CRLF-terminated content");
}

- (void)testPreviewSafeBaseURLRewritesRegularFile
{
    // Issues #405 / #431: WebKit on macOS 26 can silently blank the preview
    // based on file metadata it inspects but the editor does not (execute bit,
    // stale TCC/provenance state). There is no reliable runtime signal for this,
    // so the real document file is NEVER used as the preview base resource — even
    // an ordinary, non-executable file is swapped for a non-existent sentinel in
    // the SAME directory. The directory is all the scope/resolution code needs.
    NSString *content = @"# Test\n";
    [content writeToURL:self.testFileURL atomically:YES
               encoding:NSUTF8StringEncoding error:nil];

    NSURL *safe = [self.document previewSafeBaseURL:self.testFileURL];

    XCTAssertNotEqualObjects(safe, self.testFileURL,
        @"A real document file must never be used as the preview base URL");
    XCTAssertEqualObjects(safe.URLByDeletingLastPathComponent.path,
                          self.testFileURL.URLByDeletingLastPathComponent.path,
        @"Sentinel base URL must live in the same directory as the document");
    XCTAssertFalse([self.fileManager fileExistsAtPath:safe.path],
        @"Sentinel base URL must not point at a real file");
}

- (void)testPreviewSafeBaseURLRewritesExecutableFile
{
    // Issue #431: WebKit blanks the preview for executable base resources (e.g.
    // OneDrive's 0700 files). The base URL should be swapped for a non-existent
    // sentinel in the SAME directory, so WebKit no longer sees an executable
    // base while the directory — all the scope/resolution code depends on —
    // stays identical.
    NSString *content = @"# Test\n";
    [content writeToURL:self.testFileURL atomically:YES
               encoding:NSUTF8StringEncoding error:nil];
    chmod(self.testFileURL.path.fileSystemRepresentation, 0700);

    NSURL *safe = [self.document previewSafeBaseURL:self.testFileURL];

    XCTAssertNotEqualObjects(safe, self.testFileURL,
        @"Executable files should not be used as the preview base URL");
    XCTAssertEqualObjects(safe.URLByDeletingLastPathComponent.path,
                          self.testFileURL.URLByDeletingLastPathComponent.path,
        @"Sentinel base URL must live in the same directory as the document");
    XCTAssertFalse([self.fileManager fileExistsAtPath:safe.path],
        @"Sentinel base URL must not point at a real (executable) file");
}

- (void)testPreviewSafeBaseURLLeavesDirectoryUnchanged
{
    // An unsaved document has no fileURL, so the base URL is the default HTML
    // directory rather than a document file. A directory is already a safe base
    // resource (relative resolution uses the directory itself) and must pass
    // through untouched.
    NSURL *dirURL = [NSURL fileURLWithPath:self.testDirectory isDirectory:YES];

    NSURL *safe = [self.document previewSafeBaseURL:dirURL];
    XCTAssertEqualObjects(safe, dirURL,
        @"Directory base URLs must be returned unchanged");
}

- (void)testPreviewSafeBaseURLLeavesNonexistentPathUnchanged
{
    // A file URL that does not resolve to anything on disk has no real base
    // resource for WebKit to inspect, so there is nothing to make safe.
    NSURL *missingURL = [NSURL fileURLWithPath:
        [self.testDirectory stringByAppendingPathComponent:@"missing.md"]];

    NSURL *safe = [self.document previewSafeBaseURL:missingURL];
    XCTAssertEqualObjects(safe, missingURL,
        @"Non-existent file paths must be returned unchanged");
}

- (void)testPreviewSafeBaseURLLeavesNonFileURLUnchanged
{
    // Only file:// base URLs can trigger the WebKit blanking behavior.
    NSURL *httpURL = [NSURL URLWithString:@"https://example.com/page.html"];

    NSURL *safe = [self.document previewSafeBaseURL:httpURL];
    XCTAssertEqualObjects(safe, httpURL,
        @"Non-file URLs must be returned unchanged");
}

- (void)testPreviewSafeBaseURLLeavesNilUnchanged
{
    XCTAssertNil([self.document previewSafeBaseURL:nil],
        @"A nil base URL must be returned as nil");
}

- (void)testWritableTypes
{
    // Call [MPDocument writableTypes] (class method)
    NSArray *writableTypes = [MPDocument writableTypes];

    // Verify it returns an array
    XCTAssertNotNil(writableTypes, @"writableTypes should return a non-nil array");
    XCTAssertTrue([writableTypes isKindOfClass:[NSArray class]],
                 @"writableTypes should return an NSArray");

    // Verify it contains the expected markdown type
    XCTAssertTrue([writableTypes containsObject:@"net.daringfireball.markdown"],
                 @"writableTypes should contain 'net.daringfireball.markdown'");
}

#pragma mark - Document State Tests

- (void)testIsDocumentEditedWhenModified
{
    // Set fileURL to simulate a saved document
    [self.document setFileURL:self.testFileURL];

    // Mark the document as modified
    [self.document updateChangeCount:NSChangeDone];

    // With a fileURL present, should call super and return YES
    XCTAssertTrue([self.document isDocumentEdited],
                  @"Document with fileURL should report as edited when modified");
}

- (void)testIsDocumentEditedEmptyUntitled
{
    // Fresh document has no fileURL and no content
    // The editor outlet is nil before window controller loads
    XCTAssertFalse([self.document isDocumentEdited],
                   @"Empty untitled document should not report as edited");

    // Even if we mark it as changed, it should still return NO
    [self.document updateChangeCount:NSChangeDone];
    XCTAssertFalse([self.document isDocumentEdited],
                   @"Empty untitled document should not report as edited even when marked as changed");
}

- (void)testMarkdownProperty
{
    // Without window controller loaded, editor outlet is nil
    // Test that markdown getter returns nil when editor is not loaded
    NSString *markdown = self.document.markdown;
    XCTAssertNil(markdown,
                 @"Markdown should be nil when editor is not loaded");

    // Test that setter doesn't crash (messaging nil is safe in Objective-C)
    XCTAssertNoThrow(self.document.markdown = @"# Test",
                     @"Setting markdown should not throw");

    // Scripted/background edits must survive lazy window loading.
    markdown = self.document.markdown;
    XCTAssertEqualObjects(markdown, @"# Test");
    XCTAssertEqualObjects([self.document dataOfType:@"net.daringfireball.markdown" error:NULL],
        [@"# Test" dataUsingEncoding:NSUTF8StringEncoding]);

    // Test setting to nil
    self.document.markdown = nil;
    XCTAssertNil(self.document.markdown,
                 @"Setting markdown to nil should not crash");
}


#pragma mark - Native Cocoa Scripting Contract

- (NSScriptClassDescription *)scriptedDocumentDescription
{
    NSScriptSuiteRegistry *registry = NSScriptSuiteRegistry.sharedScriptSuiteRegistry;
    [registry loadSuitesFromBundle:NSBundle.mainBundle];
    NSScriptClassDescription *description = [registry classDescriptionWithAppleEventCode:'docu'];
    XCTAssertNotNil(description);
    XCTAssertEqualObjects(description.implementationClassName, @"MPDocument");
    XCTAssertEqualObjects([description keyWithAppleEventCode:'text'], @"markdown");
    XCTAssertEqualObjects([description keyWithAppleEventCode:'rndd'], @"html");
    XCTAssertTrue([description hasWritablePropertyForKey:@"markdown"]);
    XCTAssertTrue([description hasReadablePropertyForKey:@"html"]);
    XCTAssertFalse([description hasWritablePropertyForKey:@"html"]);
    return description;
}

// Send to this test host only. Self Apple Events dispatch synchronously on the
// sending thread, so keep the real Cocoa/UI consumer on the main thread.
- (NSAppleEventDescriptor *)sendScriptEvent:(AEEventID)eventID
                                  property:(NSString *)key
                                     value:(NSString *)value
                               description:(NSScriptClassDescription *)description
{
    NSScriptObjectSpecifier *documentSpecifier = self.document.objectSpecifier;
    XCTAssertNotNil(documentSpecifier);
    if (!description || !documentSpecifier) return nil;
    NSPropertySpecifier *property = [[NSPropertySpecifier alloc]
        initWithContainerClassDescription:description
        containerSpecifier:documentSpecifier key:key];
    NSAppleEventDescriptor *directObject = property.descriptor;
    XCTAssertNotNil(directObject);
    if (!directObject) return nil;
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
        appleEventWithEventClass:'core' eventID:eventID
        targetDescriptor:NSAppleEventDescriptor.currentProcessDescriptor
        returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:directObject forKeyword:keyDirectObject];
    if (value) [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:value]
                            forKeyword:keyAEData];
    XCTAssertTrue(NSThread.isMainThread);
    NSError *error = nil;
    NSAppleEventDescriptor *reply = [event
        sendEventWithOptions:NSAppleEventSendWaitForReply | NSAppleEventSendNeverInteract
        timeout:5 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(reply);
    NSAppleEventDescriptor *scriptError = [reply paramDescriptorForKeyword:keyErrorNumber];
    XCTAssertEqual(scriptError.int32Value, 0, @"%@", [reply paramDescriptorForKeyword:keyErrorString].stringValue);
    return [reply paramDescriptorForKeyword:keyDirectObject];
}

- (void)loadScriptedDocumentWithSource:(NSString *)source
{
    self.scriptOriginalAutoSave = @([MPPreferences sharedInstance].editorAutoSave);
    [MPPreferences sharedInstance].editorAutoSave = NO;
    self.scriptUndoManager = self.document.undoManager;
    self.scriptOriginalGroupsByEvent = @(self.scriptUndoManager.groupsByEvent);
    // Self Apple Events dispatch inline inside XCTest, without an NSApplication
    // event boundary to close the automatic undo group. The production setter
    // owns explicit command groups; use those here and preserve every dirty /
    // undo assertion rather than forcing a change count or closing a group.
    self.scriptUndoManager.groupsByEvent = NO;
    XCTAssertTrue([source writeToURL:self.testFileURL atomically:YES
                           encoding:NSUTF8StringEncoding error:NULL]);
    XCTAssertTrue([self.document readFromURL:self.testFileURL
                                     ofType:@"net.daringfireball.markdown" error:NULL]);
    self.document.fileURL = self.testFileURL;
    self.document.fileType = @"net.daringfireball.markdown";
    [NSDocumentController.sharedDocumentController addDocument:self.document];
    [self.document makeWindowControllers];
    for (NSWindowController *controller in self.document.windowControllers) {
        XCTAssertNotNil(controller.window); // Load the production nib without showing it.
    }
    XCTAssertNotNil(self.document.editor);
    XCTAssertNotNil(self.document.renderer);
    XCTestExpectation *loaded = [self expectationForPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return [self.document.markdown isEqualToString:source];
        }] evaluatedWithObject:self.document handler:nil];
    [self waitForExpectations:@[loaded] timeout:5];
    XCTAssertEqualObjects(self.document.markdown, source);
    [self.document updateChangeCount:NSChangeCleared];
}

- (void)closeScriptedDocument
{
    // These fixtures test persistence explicitly. Clear unsaved test-only state
    // before closing so subsequent tests cannot inherit deferred autosave work.
    [self.document updateChangeCount:NSChangeCleared];
    [self.document close];
}

- (void)testNativeScriptPropertiesResolveTextAndRenderedHTML
{
    @try {
        NSScriptClassDescription *description = [self scriptedDocumentDescription];
        NSString *source = @"# Native heading\n\nUnicode é 日本語 😀\n";
        [self loadScriptedDocumentWithSource:source];
        // Establish real rendered output before asking its read-only scripting property.
        [self.document.renderer parseMarkdown:source];
        XCTAssertEqualObjects([self sendScriptEvent:'getd' property:@"markdown" value:nil
                                       description:description].stringValue, source);
        NSString *html = [self sendScriptEvent:'getd' property:@"html" value:nil
                                  description:description].stringValue;
        XCTAssertEqualObjects(html, self.document.html);
        XCTAssertTrue([html containsString:@"Native heading</h1>"]);
        XCTAssertTrue([html containsString:@"Unicode é 日本語 😀"]);
    } @finally {
        [self closeScriptedDocument];
        [NSDocumentController.sharedDocumentController removeDocument:self.document];
    }
}

- (void)testNativeScriptTextEditNotifiesRendersAndSavesLiteralContent
{
    MPPreferences *preferences = self.document.preferences;
    BOOL manual = preferences.markdownManualRender;
    BOOL wordCount = preferences.editorShowWordCount;
    __block NSUInteger notifications = 0;
    id observer = nil;
    @try {
        preferences.markdownManualRender = NO;
        preferences.editorShowWordCount = YES;
        NSScriptClassDescription *description = [self scriptedDocumentDescription];
        [self loadScriptedDocumentWithSource:@"# Before\n"];
        [self.document.renderer parseMarkdown:self.document.markdown];
        XCTAssertTrue([self.document.html containsString:@"Before</h1>"]);
        observer = [NSNotificationCenter.defaultCenter
            addObserverForName:NSTextDidChangeNotification object:self.document.editor
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { notifications++; }];
        NSString *source = @"# After\n\nLiteral ( [ ` and Unicode é 日本語 😀\n";
        [self sendScriptEvent:'setd' property:@"markdown" value:source description:description];
        XCTAssertEqualObjects([self sendScriptEvent:'getd' property:@"markdown" value:nil
                                       description:description].stringValue, source);
        // No forced parse after the mutation: native editing must publish its own change.
        XCTestExpectation *rendered = [self expectationForPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return [self.document.html containsString:@"After</h1>"];
            }] evaluatedWithObject:self.document handler:nil];
        [self waitForExpectations:@[rendered] timeout:5];
        XCTAssertEqual(notifications, 1U);
        XCTAssertTrue(self.document.isDocumentEdited);
        NSString *html = [self sendScriptEvent:'getd' property:@"html" value:nil
                                  description:description].stringValue;
        XCTAssertTrue([html containsString:@"After</h1>"]);
        XCTAssertFalse([html containsString:@"Before</h1>"]);
        XCTestExpectation *saved = [self expectationWithDescription:@"Script-edited document saved"];
        [self.document saveToURL:self.testFileURL ofType:@"net.daringfireball.markdown"
               forSaveOperation:NSSaveOperation completionHandler:^(NSError *error) {
            XCTAssertNil(error);
            [saved fulfill];
        }];
        [self waitForExpectations:@[saved] timeout:5];
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:self.testFileURL],
                              [source dataUsingEncoding:NSUTF8StringEncoding]);
        XCTAssertFalse(self.document.isDocumentEdited);
        BOOL canUndo = self.document.undoManager.canUndo;
        BOOL canRedo = self.document.undoManager.canRedo;
        [self sendScriptEvent:'setd' property:@"markdown" value:source description:description];
        XCTAssertFalse(self.document.isDocumentEdited);
        XCTAssertEqual(notifications, 1U);
        XCTAssertEqual(self.document.undoManager.canUndo, canUndo);
        XCTAssertEqual(self.document.undoManager.canRedo, canRedo);
    } @finally {
        if (observer) [NSNotificationCenter.defaultCenter removeObserver:observer];
        [self closeScriptedDocument];
        [NSDocumentController.sharedDocumentController removeDocument:self.document];
        preferences.markdownManualRender = manual;
        preferences.editorShowWordCount = wordCount;
    }
}


- (void)testNativeScriptTextNoOpAndUndoRedoPreserveLiteralContentAndCleanBaseline
{
    NSUndoManager *undo = nil;
    MPPreferences *preferences = self.document.preferences;
    BOOL matching = preferences.editorCompleteMatchingCharacters;
    __block NSUInteger notifications = 0;
    id observer = nil;
    @try {
        preferences.editorCompleteMatchingCharacters = YES;
        NSScriptClassDescription *description = [self scriptedDocumentDescription];
        NSString *before = @"# Before\n";
        [self loadScriptedDocumentWithSource:before];
        undo = self.document.undoManager;
        [undo removeAllActions];
        observer = [NSNotificationCenter.defaultCenter
            addObserverForName:NSTextDidChangeNotification object:self.document.editor
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { notifications++; }];
        [self sendScriptEvent:'setd' property:@"markdown" value:before description:description];
        XCTAssertEqual(notifications, 0U);
        XCTAssertFalse(self.document.isDocumentEdited);
        XCTAssertFalse(undo.canUndo);

        // A whole-source property must not turn a lone opening delimiter into
        // a matching pair through the editor's interactive delegate.
        NSString *literal = @"(";
        [self sendScriptEvent:'setd' property:@"markdown" value:literal description:description];
        XCTAssertEqualObjects(self.document.markdown, literal);
        XCTAssertEqual(notifications, 1U);
        XCTAssertTrue(self.document.isDocumentEdited);
        XCTAssertTrue(undo.canUndo);
        [undo undo];
        XCTAssertEqualObjects(self.document.markdown, before);
        XCTAssertEqual(notifications, 2U);
        XCTAssertFalse(self.document.isDocumentEdited);
        XCTAssertFalse(undo.canUndo);
        XCTAssertTrue(undo.canRedo);
        [undo redo];
        XCTAssertEqualObjects(self.document.markdown, literal);
        XCTAssertEqual(notifications, 3U);
        XCTAssertTrue(self.document.isDocumentEdited);
        XCTAssertTrue(undo.canUndo);
        [undo undo];
        XCTAssertEqualObjects(self.document.markdown, before);
        XCTAssertFalse(self.document.isDocumentEdited);
    } @finally {
        if (observer) [NSNotificationCenter.defaultCenter removeObserver:observer];
        [self closeScriptedDocument];
        preferences.editorCompleteMatchingCharacters = matching;
        [NSDocumentController.sharedDocumentController removeDocument:self.document];
    }
}

- (void)testLiveMarkdownEditWithoutUndoStillTracksTheDocumentChange
{
    @try {
        [self loadScriptedDocumentWithSource:@"# Before\n"];
        self.document.hasUndoManager = NO;
        self.document.markdown = @"# After without undo\n";
        XCTAssertEqualObjects(self.document.markdown, @"# After without undo\n");
        XCTAssertTrue(self.document.isDocumentEdited);
    } @finally {
        [self closeScriptedDocument];
        [NSDocumentController.sharedDocumentController removeDocument:self.document];
    }
}


- (void)testNativeScriptTextEditRespectsManualRender
{
    MPPreferences *preferences = self.document.preferences;
    BOOL manual = preferences.markdownManualRender;
    @try {
        preferences.markdownManualRender = YES;
        NSScriptClassDescription *description = [self scriptedDocumentDescription];
        [self loadScriptedDocumentWithSource:@"# Before\n"];
        [self.document.renderer parseMarkdown:self.document.markdown];
        [self sendScriptEvent:'setd' property:@"markdown" value:@"# After\n" description:description];
        XCTAssertEqualObjects(self.document.markdown, @"# After\n");
        XCTAssertTrue(self.document.isDocumentEdited);
        // Give the ordinary delayed renderer a turn; manual mode must keep the
        // published baseline until the user requests a render.
        XCTestExpectation *settled = [self expectationWithDescription:@"Manual render remains unchanged"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            XCTAssertTrue([self.document.html containsString:@"Before</h1>"]);
            XCTAssertFalse([self.document.html containsString:@"After</h1>"]);
            [settled fulfill];
        });
        [self waitForExpectations:@[settled] timeout:3];
    } @finally {
        [self closeScriptedDocument];
        [NSDocumentController.sharedDocumentController removeDocument:self.document];
        preferences.markdownManualRender = manual;
    }
}

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

- (void)testToggleAutoSaveActionUpdatesPreference
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;

    prefs.editorAutoSave = YES;
    [self.document toggleAutoSave:nil];
    XCTAssertFalse(prefs.editorAutoSave,
                   @"File menu auto-save toggle should disable autosave");

    [self.document toggleAutoSave:nil];
    XCTAssertTrue(prefs.editorAutoSave,
                  @"File menu auto-save toggle should re-enable autosave");

    prefs.editorAutoSave = original;
}

- (void)testToggleAutoSaveMenuValidationReflectsPreference
{
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL original = prefs.editorAutoSave;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Auto Save"
                                                  action:@selector(toggleAutoSave:)
                                           keyEquivalent:@""];

    prefs.editorAutoSave = YES;
    [self.document validateUserInterfaceItem:item];
    XCTAssertEqual(item.state, NSControlStateValueOn,
                   @"Auto-save menu item should be checked when autosave is enabled");

    prefs.editorAutoSave = NO;
    [self.document validateUserInterfaceItem:item];
    XCTAssertEqual(item.state, NSControlStateValueOff,
                   @"Auto-save menu item should be unchecked when autosave is disabled");

    prefs.editorAutoSave = original;
}

#pragma mark - File Operations Tests

- (void)testReadOnlyFileDetection
{
    // Create a test file with some content
    NSString *testContent = @"# Read-only test\n\nThis file is read-only.";
    NSError *error = nil;
    BOOL written = [testContent writeToURL:self.testFileURL
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&error];
    XCTAssertTrue(written, @"Should write test file");

    // Make the file read-only using chmod
    const char *path = [self.testFileURL.path fileSystemRepresentation];
    int result = chmod(path, S_IRUSR | S_IRGRP | S_IROTH);  // 444 - read-only
    XCTAssertEqual(result, 0, @"chmod should succeed");

    // Verify file is read-only
    NSDictionary *attrs = [self.fileManager attributesOfItemAtPath:self.testFileURL.path
                                                             error:&error];
    NSNumber *permissions = attrs[NSFilePosixPermissions];
    XCTAssertNotNil(permissions, @"Should get file permissions");

    // Try to read the file (should work)
    NSString *readContent = [NSString stringWithContentsOfURL:self.testFileURL
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
    XCTAssertNotNil(readContent, @"Should be able to read read-only file");
    XCTAssertEqualObjects(readContent, testContent, @"Content should match");

    // Load document from URL
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:self.testFileURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];
    XCTAssertNotNil(doc, @"Should create document from read-only file");

    // Note: We cannot verify the content was loaded into the markdown property
    // in headless CI because that requires the editor outlet to be initialized.
    // The test above verifies that MPDocument can successfully load a read-only file.

    // Restore write permissions before cleanup
    result = chmod(path, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);  // 644
    XCTAssertEqual(result, 0, @"Should restore write permissions for cleanup");
}

- (void)testPrepareSavePanelExtensions
{
    // Test the writableTypes class method
    NSArray *writableTypes = [MPDocument writableTypes];
    XCTAssertNotNil(writableTypes, @"Writable types should not be nil");
    XCTAssertGreaterThan(writableTypes.count, 0, @"Should have at least one writable type");
    XCTAssertTrue([writableTypes containsObject:@"net.daringfireball.markdown"],
                  @"Should support Markdown type");

    // Create a save panel to test prepareSavePanel:
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    XCTAssertNotNil(savePanel, @"Should create save panel");

    // Load the document's NIB
    [self.document makeWindowControllers];

    // Call prepareSavePanel: to configure it
    BOOL result = [self.document prepareSavePanel:savePanel];
    XCTAssertTrue(result, @"prepareSavePanel: should return YES");

    // Verify the save panel was configured
    XCTAssertFalse(savePanel.extensionHidden, @"Extension should not be hidden");
    XCTAssertNotNil(savePanel.allowedFileTypes, @"Should set allowed file types");
    XCTAssertGreaterThan(savePanel.allowedFileTypes.count, 0, @"Should have allowed file types");
    XCTAssertTrue(savePanel.allowsOtherFileTypes, @"Should allow other file types");

    // Verify that common Markdown extensions are in the allowed types
    NSArray *allowedTypes = savePanel.allowedFileTypes;
    BOOL hasMarkdownExtension = NO;
    for (NSString *ext in @[@"md", @"markdown", @"mdown"]) {
        if ([allowedTypes containsObject:ext]) {
            hasMarkdownExtension = YES;
            break;
        }
    }
    XCTAssertTrue(hasMarkdownExtension, @"Should include at least one Markdown extension");
}


#pragma mark - Error Handling Tests

- (void)testReadFromDataMalformedUTF8Sequences
{
    // Test various malformed UTF-8 sequences

    // Invalid continuation byte
    const unsigned char bytes1[] = {0xC3, 0x28};  // 0xC3 expects continuation, 0x28 is ASCII
    NSData *data1 = [NSData dataWithBytes:bytes1 length:sizeof(bytes1)];
    NSError *error = nil;
    BOOL success = [self.document readFromData:data1
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];
    XCTAssertFalse(success, @"Should reject invalid continuation byte");

    // Overlong encoding (2-byte encoding of ASCII)
    const unsigned char bytes2[] = {0xC0, 0xAF};  // Overlong '/'
    NSData *data2 = [NSData dataWithBytes:bytes2 length:sizeof(bytes2)];
    success = [self.document readFromData:data2
                                   ofType:@"net.daringfireball.markdown"
                                    error:&error];
    XCTAssertFalse(success, @"Should reject overlong encoding");

    // Incomplete multi-byte sequence at end
    const unsigned char bytes3[] = {0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE2, 0x82};  // "Hello" + incomplete €
    NSData *data3 = [NSData dataWithBytes:bytes3 length:sizeof(bytes3)];
    success = [self.document readFromData:data3
                                   ofType:@"net.daringfireball.markdown"
                                    error:&error];
    XCTAssertFalse(success, @"Should reject incomplete multi-byte at end");
}

- (void)testReadFromDataEmptyData
{
    // Empty data should succeed (empty document is valid)
    NSData *emptyData = [NSData data];
    NSError *error = nil;
    BOOL success = [self.document readFromData:emptyData
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    // Empty string from empty data is valid UTF-8
    XCTAssertTrue(success, @"Empty data should be valid");
    XCTAssertNil(error, @"Should not have error for empty data");
}

- (void)testReadFromDataNilData
{
    // Nil data creates an empty string, which is valid
    NSError *error = nil;
    BOOL success = [self.document readFromData:nil
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    // NSString initWithData:nil returns @"" (empty string), which is valid
    XCTAssertTrue(success, @"Nil data should succeed (becomes empty string)");
    XCTAssertNil(error, @"Should not have error");
}

- (void)testReadFromDataLargeFile
{
    // Create a large markdown document (1MB)
    NSMutableString *largeMarkdown = [NSMutableString stringWithCapacity:1024 * 1024];
    for (int i = 0; i < 10000; i++) {
        [largeMarkdown appendFormat:@"## Heading %d\n\nParagraph with some content for line %d.\n\n", i, i];
    }

    NSData *largeData = [largeMarkdown dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertGreaterThan(largeData.length, 500000, @"Should be at least 500KB");

    NSError *error = nil;
    BOOL success = [self.document readFromData:largeData
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    XCTAssertTrue(success, @"Should handle large files");
    XCTAssertNil(error, @"Should not error on large file");
}

- (void)testReadFromDataWithBOM
{
    // UTF-8 with BOM (Byte Order Mark)
    const unsigned char bom[] = {0xEF, 0xBB, 0xBF};  // UTF-8 BOM
    NSMutableData *dataWithBOM = [NSMutableData dataWithBytes:bom length:sizeof(bom)];
    [dataWithBOM appendData:[@"# Document with BOM\n\nContent here." dataUsingEncoding:NSUTF8StringEncoding]];

    NSError *error = nil;
    BOOL success = [self.document readFromData:dataWithBOM
                                        ofType:@"net.daringfireball.markdown"
                                         error:&error];

    XCTAssertTrue(success, @"Should handle UTF-8 BOM");
    XCTAssertNil(error, @"Should not error with BOM");
}

- (void)testWriteToReadOnlyDirectory
{
    // Create a read-only directory
    NSString *readOnlyDir = [self.testDirectory stringByAppendingPathComponent:@"readonly"];
    NSError *error = nil;
    [self.fileManager createDirectoryAtPath:readOnlyDir
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error];

    // Make it read-only
    const char *path = [readOnlyDir fileSystemRepresentation];
    chmod(path, S_IRUSR | S_IXUSR);  // r-x only

    // Create some test content and try to write
    NSString *content = @"# Test\n\nThis should fail to write.";
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];

    NSURL *targetURL = [NSURL fileURLWithPath:[readOnlyDir stringByAppendingPathComponent:@"test.md"]];
    BOOL success = [data writeToURL:targetURL
                            options:NSDataWritingAtomic
                              error:&error];

    XCTAssertFalse(success, @"Write to read-only directory should fail");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.domain, NSCocoaErrorDomain, @"Should be Cocoa error");

    // Restore permissions for cleanup
    chmod(path, S_IRWXU);
}

- (void)testDataOfTypeReturnsUTF8
{
    // Test that dataOfType returns valid UTF-8 data
    // Note: In headless mode, the document has no content, so this tests the empty case
    NSError *error = nil;
    NSData *data = [self.document dataOfType:@"net.daringfireball.markdown" error:&error];

    // Without editor, markdown is nil, so data should be nil or empty
    // The implementation converts markdown to data, so nil markdown = nil data
    if (data != nil) {
        // If we got data, verify it's valid UTF-8
        NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        XCTAssertNotNil(decoded, @"Data should be valid UTF-8");
    }
}

- (void)testOpenNonexistentFile
{
    NSURL *nonexistentURL = [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"does_not_exist.md"]];

    NSError *error = nil;
    MPDocument *doc = [[MPDocument alloc] initWithContentsOfURL:nonexistentURL
                                                         ofType:@"net.daringfireball.markdown"
                                                          error:&error];

    XCTAssertNil(doc, @"Should not create document from nonexistent file");
    XCTAssertNotNil(error, @"Should return error for nonexistent file");
}

#pragma mark - Link Target Auto-Creation Security Tests

- (void)testCanAutomaticallyCreateLinkedFileInSameDirectory
{
    NSURL *targetURL = [NSURL fileURLWithPath:
        [self.testDirectory stringByAppendingPathComponent:@"notes.md"]];

    self.document.fileURL = self.testFileURL;

    XCTAssertTrue([self.document canAutomaticallyCreateLinkedFileAtURL:targetURL],
                  @"Missing file links in the same directory should be auto-creatable");
}

- (void)testCanAutomaticallyCreateLinkedFileInSubdirectory
{
    NSString *subdirectory = [self.testDirectory stringByAppendingPathComponent:@"assets"];
    [self.fileManager createDirectoryAtPath:subdirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [subdirectory stringByAppendingPathComponent:@"diagram.md"]];

    self.document.fileURL = self.testFileURL;

    XCTAssertTrue([self.document canAutomaticallyCreateLinkedFileAtURL:targetURL],
                  @"Missing file links in a subdirectory should remain auto-creatable");
}

- (void)testCanAutomaticallyCreateLinkedFileRejectsUnsavedDocument
{
    NSURL *targetURL = [NSURL fileURLWithPath:
        [self.testDirectory stringByAppendingPathComponent:@"notes.md"]];

    XCTAssertFalse([self.document canAutomaticallyCreateLinkedFileAtURL:targetURL],
                   @"Untitled documents should not auto-create link targets");
}

- (void)testCanAutomaticallyCreateLinkedFileRejectsOutOfScopeTarget
{
    NSString *outsideDirectory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.fileManager createDirectoryAtPath:outsideDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    [self addTeardownBlock:^{
        [self.fileManager removeItemAtPath:outsideDirectory error:nil];
    }];

    NSURL *targetURL = [NSURL fileURLWithPath:
        [outsideDirectory stringByAppendingPathComponent:@"outside.md"]];
    self.document.fileURL = self.testFileURL;

    XCTAssertFalse([self.document canAutomaticallyCreateLinkedFileAtURL:targetURL],
                   @"Auto-created link targets must stay within the current document scope");
}

- (void)testCanAutomaticallyCreateLinkedFileRejectsSymlinkEscape
{
    NSString *docsDirectory = [self.testDirectory stringByAppendingPathComponent:@"docs"];
    NSString *outsideDirectory = [self.testDirectory stringByAppendingPathComponent:@"outside"];
    [self.fileManager createDirectoryAtPath:docsDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    [self.fileManager createDirectoryAtPath:outsideDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];

    NSString *symlinkPath = [docsDirectory stringByAppendingPathComponent:@"escape"];
    [self.fileManager createSymbolicLinkAtPath:symlinkPath
                           withDestinationPath:outsideDirectory
                                         error:nil];

    self.document.fileURL = [NSURL fileURLWithPath:
        [docsDirectory stringByAppendingPathComponent:@"source.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [symlinkPath stringByAppendingPathComponent:@"payload.md"]];

    XCTAssertFalse([self.document canAutomaticallyCreateLinkedFileAtURL:targetURL],
                   @"Symlink escapes must not be auto-created");
}

#pragma mark - Remote Volume Save Tests (Issue #371)

- (void)testShouldBypassSafeSaveForURLIsNoForLocalFile
{
    // On a local volume, NSDocument's normal atomic "safe save" (with its
    // conflict check and versioning support) must keep working exactly as
    // before.
    XCTAssertFalse([self.document shouldBypassSafeSaveForURL:self.testFileURL],
        @"Local destinations must use NSDocument's default safe-save path");
}

- (void)testShouldBypassSafeSaveForURLIsNoForNonFileURL
{
    NSURL *httpURL = [NSURL URLWithString:@"https://example.com/page.html"];
    XCTAssertFalse([self.document shouldBypassSafeSaveForURL:httpURL],
        @"Non-file URLs are not eligible for the direct-write bypass");
}

- (void)testShouldBypassSafeSaveForURLIsYesForSimulatedNonLocalVolume
{
    // A real FUSE/network mount isn't available in CI, so simulate one via
    // the volumeLocalityChecker injection seam rather than skipping coverage
    // of the actual bug-fix branch entirely.
    self.document.volumeLocalityChecker = ^BOOL(NSString *path) {
        return NO;
    };

    XCTAssertTrue([self.document shouldBypassSafeSaveForURL:self.testFileURL],
        @"Non-local destinations must bypass NSDocument's atomic safe-save");
}

- (void)testShouldBypassSafeSaveForURLDefaultCheckerMatchesFileWatcher
{
    // The default (non-test-injected) checker should be wired to
    // MPFileWatcher's locality check, not some other logic.
    XCTAssertTrue(self.document.volumeLocalityChecker(self.testFileURL.path),
        @"Default volumeLocalityChecker should report the local test directory as local");
}

// NOTE: The bypass decision itself (shouldBypassSafeSaveForURL:) is now
// exercised for both branches above via dependency injection. What remains
// untestable in CI is the real-world trigger for the "YES" branch — an
// actual non-local volume, per [MPFileWatcher pathIsOnLocalVolume:] (covered
// directly in MPFileWatcherTests.m) — and the resulting absence of the
// "changed by another application" dialog and the "couldn't be saved in
// folder tmp" failure, which require manual verification against a real
// SSHFS/SMB/NFS mount. Related to #371.

- (void)testInvalidUTF8ProvidesReadError
{
    const unsigned char bytes[] = {0xff, 0xfe, 0xff};
    NSError *error = nil;
    XCTAssertFalse([self.document readFromData:[NSData dataWithBytes:bytes length:sizeof(bytes)]
        ofType:@"net.daringfireball.markdown" error:&error]);
    XCTAssertEqualObjects(error.domain, NSCocoaErrorDomain);
    XCTAssertEqual(error.code, NSFileReadInapplicableStringEncodingError);
}

- (void)testReadBeforeWindowLoadingCanBeSerializedWithoutDataLoss
{
    NSString *source = @"# Loaded before its window\n\nÉ漢😀\n";
    NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([self.document readFromData:data ofType:@"net.daringfireball.markdown" error:NULL]);
    XCTAssertEqualObjects(self.document.markdown, source);
    XCTAssertEqualObjects([self.document dataOfType:@"net.daringfireball.markdown" error:NULL], data);
}

@end
