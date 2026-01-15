//
//  FileURLInliningTests.m
//  MacDown 3000
//
//  Unit tests for FileURLInlining MIME type computation for file paths.
//  Copyright (c) 2026 wltb. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "FileURLInlining.h"

// Category to expose private methods for testing
@interface FileURLInlining (Testing)
+ (NSString *)mimeTypeForFilePath:(NSString *)filePath;
@end


@interface FileURLInliningTests : XCTestCase
@end


@implementation FileURLInliningTests
#pragma mark - mimeTypeForFilePath: Tests

- (void)testMIMETypeForPNGFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.png"];
    XCTAssertEqualObjects(uti, @"image/png", @"Should return PNG MIME type for .png files");
}

- (void)testMIMETypeForJPEGFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.jpg"];
    XCTAssertEqualObjects(uti, @"image/jpeg", @"Should return JPEG MIME type for .jpg files");
}

- (void)testMIMETypeForJPEGExtension
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.jpeg"];
    XCTAssertEqualObjects(uti, @"image/jpeg", @"Should return JPEG MIME type for .jpeg files");
}

- (void)testMIMETypeForGIFFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.gif"];
    XCTAssertEqualObjects(uti, @"image/gif", @"Should return GIF MIME type for .gif files");
}

- (void)testMIMETypeForWebPFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.webp"];
    // WebP may not be recognized on older macOS versions
    // On supported systems, it should return "public.webp"
    // We test that it either returns the expected UTI or nil (graceful degradation)
    if (uti != nil) {
        XCTAssertEqualObjects(uti, @"image/webp", @"Should return WebP MIME type for .webp files");
    }
}

- (void)testMIMETypeForUnsupportedTextFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/document.txt"];
    XCTAssertNil(uti, @"Should return nil for .txt files");
}

- (void)testMIMETypeForUnsupportedPDFFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/document.pdf"];
    XCTAssertNil(uti, @"Should return nil for .pdf files");
}

- (void)testMIMETypeForUnsupportedBMPFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.bmp"];
    XCTAssertNil(uti, @"Should return nil for .bmp files (not in supported list)");
}

- (void)testMIMETypeForUnsupportedTIFFFile
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.tiff"];
    XCTAssertNil(uti, @"Should return nil for .tiff files (not in supported list)");
}

- (void)testMIMETypeForFileWithNoExtension
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/imagefile"];
    XCTAssertNil(uti, @"Should return nil for files with no extension");
}

- (void)testMIMETypeForUppercaseExtension
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.PNG"];
    XCTAssertEqualObjects(uti, @"image/png", @"Should handle uppercase extensions");
}

- (void)testMIMETypeForMixedCaseExtension
{
    NSString *uti = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.Jpg"];
    XCTAssertEqualObjects(uti, @"image/jpeg", @"Should handle mixed case extensions");
}

@end
