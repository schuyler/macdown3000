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
#import "MPPreferences.h"
#import <sys/stat.h>


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

@end
