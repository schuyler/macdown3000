//
//  MPDocumentIOTests.m
//  MacDownTests
//
//  Tests for file I/O and document lifecycle functionality.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPPreferences.h"

@interface MPDocumentIOTests : XCTestCase
@property (strong) MPDocument *document;
@property (strong) NSURL *testFileURL;
@property (strong) NSString *testDirectory;
@property (strong) NSFileManager *fileManager;
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

    // Verify document's markdown property contains the correct text
    XCTAssertEqualObjects(self.document.markdown, testMarkdown,
                         @"Document markdown should match the input data");
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

- (void)testDataOfType
{
    // Set document's markdown property to a test string
    NSString *testMarkdown = @"# Sample Markdown\n\n- Item 1\n- Item 2\n\nSome **bold** text.";
    self.document.markdown = testMarkdown;

    // Call dataOfType:error:
    NSError *error = nil;
    NSData *data = [self.document dataOfType:@"net.daringfireball.markdown" error:&error];

    // Verify no error returned
    XCTAssertNil(error, @"No error should be returned from dataOfType:error:");
    XCTAssertNotNil(data, @"Data should not be nil");

    // Convert result back to string and verify it matches original
    NSString *resultString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(resultString, testMarkdown,
                         @"Data converted back to string should match original markdown");
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

    // After setting, still returns nil because editor is not loaded
    markdown = self.document.markdown;
    XCTAssertNil(markdown,
                 @"Markdown should still be nil after setting when editor is not loaded");

    // Test setting to nil
    self.document.markdown = nil;
    XCTAssertNil(self.document.markdown,
                 @"Setting markdown to nil should not crash");
}

- (void)testAutosavesInPlace
{
    // Test class method returns YES
    BOOL autosaves = [MPDocument autosavesInPlace];
    XCTAssertTrue(autosaves,
                  @"MPDocument should autosave in place");
}

- (void)testAutosaveNameForSavedFile
{
    // Test autosaveName property can be set and retrieved
    NSString *testAutosaveName = @"TestAutosaveName";
    self.document.autosaveName = testAutosaveName;

    XCTAssertEqualObjects(self.document.autosaveName, testAutosaveName,
                          @"Autosave name should be stored correctly");

    // Test with fileURL (simulating a saved file)
    [self.document setFileURL:self.testFileURL];
    NSString *urlBasedName = self.testFileURL.absoluteString;
    self.document.autosaveName = urlBasedName;

    XCTAssertEqualObjects(self.document.autosaveName, urlBasedName,
                          @"Autosave name based on fileURL should be stored correctly");
}

#pragma mark - File Operations Tests

- (void)testWriteToURLWithNewline
{
    // Load the document's NIB by creating window controllers
    [self.document makeWindowControllers];

    // Access the editor after NIB is loaded
    // Note: In a headless test environment, the editor may not be fully initialized,
    // so we'll test what we can at the API level

    // Save the current preference
    MPPreferences *prefs = self.document.preferences;
    BOOL originalValue = prefs.editorEnsuresNewlineAtEndOfFile;

    // Set preference to ensure newline at end
    prefs.editorEnsuresNewlineAtEndOfFile = YES;

    // Set document content without trailing newline
    NSString *testContent = @"Test content";
    self.document.markdown = testContent;

    // Write to URL
    NSError *error = nil;
    BOOL success = [self.document writeToURL:self.testFileURL
                                      ofType:@"net.daringfireball.markdown"
                                       error:&error];

    XCTAssertTrue(success, @"Write should succeed");
    XCTAssertNil(error, @"No error should occur");

    // Read the file back and verify newline was added
    NSString *savedContent = [NSString stringWithContentsOfURL:self.testFileURL
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
    XCTAssertNotNil(savedContent, @"Should be able to read saved file");
    XCTAssertTrue([savedContent hasSuffix:@"\n"], @"File should end with newline");
    XCTAssertTrue([savedContent hasPrefix:testContent], @"File should contain original content");

    // Restore original preference
    prefs.editorEnsuresNewlineAtEndOfFile = originalValue;
}

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

    // Verify the content was loaded
    [doc makeWindowControllers];  // Trigger NIB load
    NSString *loadedMarkdown = doc.markdown;
    XCTAssertEqualObjects(loadedMarkdown, testContent, @"Document should load read-only file content");

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

@end
