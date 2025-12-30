//
//  MPDocumentIOTests.m
//  MacDownTests
//
//  Tests for file I/O and document lifecycle functionality.
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"
#import "MPPreferences.h"
#import <sys/stat.h>

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

@end
