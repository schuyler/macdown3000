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

#pragma mark - init: Tests
- (void)testInit
{
    XCTAssertThrows([[FileURLInlining alloc] init]);
}

#pragma mark - mimeTypeForFilePath: Tests

- (void)testMIMETypeForPNGFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.png"];
    XCTAssertEqualObjects(type, @"image/png", @"Should return PNG MIME type for .png files");
}

- (void)testMIMETypeForJPEGFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.jpg"];
    XCTAssertEqualObjects(type, @"image/jpeg", @"Should return JPEG MIME type for .jpg files");
}

- (void)testMIMETypeForJPEGExtension
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.jpeg"];
    XCTAssertEqualObjects(type, @"image/jpeg", @"Should return JPEG MIME type for .jpeg files");
}

- (void)testMIMETypeForGIFFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.gif"];
    XCTAssertEqualObjects(type, @"image/gif", @"Should return GIF MIME type for .gif files");
}

- (void)testMIMETypeForWebPFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.webp"];
    // WebP may not be recognized on older macOS versions
    // On supported systems, it should return "public.webp"
    // We test that it either returns the expected UTI or nil (graceful degradation)
    if (type != nil) {
        XCTAssertEqualObjects(type, @"image/webp", @"Should return WebP MIME type for .webp files");
    }
}

- (void)testMIMETypeForUnsupportedTextFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/document.txt"];
    XCTAssertNil(type, @"Should return nil for .txt files");
}

- (void)testMIMETypeForUnsupportedPDFFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/document.pdf"];
    XCTAssertNil(type, @"Should return nil for .pdf files");
}

- (void)testMIMETypeForUnsupportedBMPFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.bmp"];
    XCTAssertNil(type, @"Should return nil for .bmp files (not in supported list)");
}

- (void)testMIMETypeForUnsupportedTIFFFile
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.tiff"];
    XCTAssertNil(type, @"Should return nil for .tiff files (not in supported list)");
}

- (void)testMIMETypeForFileWithNoExtension
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/imagefile"];
    XCTAssertNil(type, @"Should return nil for files with no extension");
}

- (void)testMIMETypeForUppercaseExtension
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.PNG"];
    XCTAssertEqualObjects(type, @"image/png", @"Should handle uppercase extensions");
}

- (void)testMIMETypeForMixedCaseExtension
{
    NSString *type = [FileURLInlining mimeTypeForFilePath:@"/path/to/image.Jpg"];
    XCTAssertEqualObjects(type, @"image/jpeg", @"Should handle mixed case extensions");
}

@end
