//
//  MPEditorViewTests.m
//  MacDown 3000
//
//  Unit tests for MPEditorView drag & drop functionality.
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPEditorView.h"

// Category to expose private methods for testing
@interface MPEditorView (Testing)
- (NSString *)imageUTIForFilePath:(NSString *)filePath;
- (NSString *)mimeTypeForUTI:(NSString *)uti;
@end


@interface MPEditorViewTests : XCTestCase
@property (nonatomic, strong) MPEditorView *editorView;
@end


@implementation MPEditorViewTests

- (void)setUp
{
    [super setUp];
    self.editorView = [[MPEditorView alloc] init];
}

- (void)tearDown
{
    self.editorView = nil;
    [super tearDown];
}


#pragma mark - imageUTIForFilePath: Tests

- (void)testImageUTIForPNGFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.png"];
    XCTAssertEqualObjects(uti, @"public.png", @"Should return PNG UTI for .png files");
}

- (void)testImageUTIForJPEGFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.jpg"];
    XCTAssertEqualObjects(uti, @"public.jpeg", @"Should return JPEG UTI for .jpg files");
}

- (void)testImageUTIForJPEGExtension
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.jpeg"];
    XCTAssertEqualObjects(uti, @"public.jpeg", @"Should return JPEG UTI for .jpeg files");
}

- (void)testImageUTIForGIFFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.gif"];
    XCTAssertEqualObjects(uti, @"com.compuserve.gif", @"Should return GIF UTI for .gif files");
}

- (void)testImageUTIForWebPFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.webp"];
    // WebP may not be recognized on older macOS versions
    // On supported systems, it should return "public.webp"
    // We test that it either returns the expected UTI or nil (graceful degradation)
    if (uti != nil) {
        XCTAssertEqualObjects(uti, @"public.webp", @"Should return WebP UTI for .webp files");
    }
}

- (void)testImageUTIForUnsupportedTextFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/document.txt"];
    XCTAssertNil(uti, @"Should return nil for .txt files");
}

- (void)testImageUTIForUnsupportedPDFFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/document.pdf"];
    XCTAssertNil(uti, @"Should return nil for .pdf files");
}

- (void)testImageUTIForUnsupportedBMPFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.bmp"];
    XCTAssertNil(uti, @"Should return nil for .bmp files (not in supported list)");
}

- (void)testImageUTIForUnsupportedTIFFFile
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.tiff"];
    XCTAssertNil(uti, @"Should return nil for .tiff files (not in supported list)");
}

- (void)testImageUTIForFileWithNoExtension
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/imagefile"];
    XCTAssertNil(uti, @"Should return nil for files with no extension");
}

- (void)testImageUTIForUppercaseExtension
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.PNG"];
    XCTAssertEqualObjects(uti, @"public.png", @"Should handle uppercase extensions");
}

- (void)testImageUTIForMixedCaseExtension
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/path/to/image.Jpg"];
    XCTAssertEqualObjects(uti, @"public.jpeg", @"Should handle mixed case extensions");
}


#pragma mark - mimeTypeForUTI: Tests

- (void)testMimeTypeForJPEG
{
    NSString *mime = [self.editorView mimeTypeForUTI:@"public.jpeg"];
    XCTAssertEqualObjects(mime, @"image/jpeg", @"Should return image/jpeg for public.jpeg");
}

- (void)testMimeTypeForPNG
{
    NSString *mime = [self.editorView mimeTypeForUTI:@"public.png"];
    XCTAssertEqualObjects(mime, @"image/png", @"Should return image/png for public.png");
}

- (void)testMimeTypeForGIF
{
    NSString *mime = [self.editorView mimeTypeForUTI:@"com.compuserve.gif"];
    XCTAssertEqualObjects(mime, @"image/gif", @"Should return image/gif for com.compuserve.gif");
}

- (void)testMimeTypeForWebP
{
    NSString *mime = [self.editorView mimeTypeForUTI:@"public.webp"];
    XCTAssertEqualObjects(mime, @"image/webp", @"Should return image/webp for public.webp");
}

- (void)testMimeTypeForUnsupportedUTI
{
    NSString *mime = [self.editorView mimeTypeForUTI:@"public.tiff"];
    XCTAssertNil(mime, @"Should return nil for unsupported UTIs");
}

- (void)testMimeTypeForNilUTI
{
    NSString *mime = [self.editorView mimeTypeForUTI:nil];
    XCTAssertNil(mime, @"Should return nil for nil UTI");
}

- (void)testMimeTypeForEmptyUTI
{
    NSString *mime = [self.editorView mimeTypeForUTI:@""];
    XCTAssertNil(mime, @"Should return nil for empty UTI");
}


#pragma mark - Integration Tests (UTI to MIME round-trip)

- (void)testRoundTripPNG
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/test/image.png"];
    NSString *mime = [self.editorView mimeTypeForUTI:uti];
    XCTAssertEqualObjects(mime, @"image/png", @"PNG should round-trip correctly");
}

- (void)testRoundTripJPEG
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/test/photo.jpg"];
    NSString *mime = [self.editorView mimeTypeForUTI:uti];
    XCTAssertEqualObjects(mime, @"image/jpeg", @"JPEG should round-trip correctly");
}

- (void)testRoundTripGIF
{
    NSString *uti = [self.editorView imageUTIForFilePath:@"/test/animation.gif"];
    NSString *mime = [self.editorView mimeTypeForUTI:uti];
    XCTAssertEqualObjects(mime, @"image/gif", @"GIF should round-trip correctly");
}

@end
