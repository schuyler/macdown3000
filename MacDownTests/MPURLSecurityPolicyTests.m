//
//  MPURLSecurityPolicyTests.m
//  MacDown 3000
//
//  Tests for MPURLSecurityPolicy — covers CVE-2019-12138 (directory traversal)
//  and CVE-2019-12173 (RCE via app bundle links).
//

#import <XCTest/XCTest.h>
#import "MPURLSecurityPolicy.h"

@interface MPURLSecurityPolicyTests : XCTestCase
@property (strong) NSString *tempDir;
@property (strong) NSURL *appBundleURL;
@end


@implementation MPURLSecurityPolicyTests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Build a minimal .app bundle that macOS will recognize as an application.
    // Structure: Test.app/Contents/Info.plist + Contents/MacOS/Test (stub)
    // The stub executable ensures Launch Services classifies the bundle
    // correctly even on CI runners without a warm LS cache.
    NSString *bundlePath = [self.tempDir
        stringByAppendingPathComponent:@"Test.app"];
    NSString *contentsPath = [bundlePath
        stringByAppendingPathComponent:@"Contents"];
    NSString *macosPath = [contentsPath
        stringByAppendingPathComponent:@"MacOS"];
    [[NSFileManager defaultManager] createDirectoryAtPath:macosPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Minimal Info.plist required for bundle type recognition.
    NSString *plist = (
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\""
        @" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"    <key>CFBundleIdentifier</key>\n"
        @"    <string>com.test.testapp</string>\n"
        @"    <key>CFBundleName</key>\n"
        @"    <string>Test</string>\n"
        @"    <key>CFBundlePackageType</key>\n"
        @"    <string>APPL</string>\n"
        @"    <key>CFBundleExecutable</key>\n"
        @"    <string>Test</string>\n"
        @"</dict>\n"
        @"</plist>\n"
    );
    [plist writeToFile:[contentsPath stringByAppendingPathComponent:@"Info.plist"]
            atomically:YES
              encoding:NSUTF8StringEncoding
                 error:nil];

    // Stub executable — a zero-byte file with the executable bit set.
    NSString *execPath = [macosPath stringByAppendingPathComponent:@"Test"];
    [@"" writeToFile:execPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0755)}
                                     ofItemAtPath:execPath
                                            error:nil];

    self.appBundleURL = [NSURL fileURLWithPath:bundlePath];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - isExecutableOrAppBundleAtURL: Tests

- (void)testAppBundleDetectedAsExecutable
{
    // .app bundle with Contents/Info.plist should be detected as dangerous.
    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:self.appBundleURL],
                  @"App bundle should be detected as executable/dangerous");
}

- (void)testPlainTextFileNotDetectedAsExecutable
{
    NSString *txtPath = [self.tempDir stringByAppendingPathComponent:@"readme.txt"];
    [@"hello world" writeToFile:txtPath
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil];
    NSURL *txtURL = [NSURL fileURLWithPath:txtPath];

    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:txtURL],
                   @"Plain text file should not be detected as executable");
}

- (void)testPlainDirectoryNotDetectedAsExecutable
{
    NSString *dirPath = [self.tempDir stringByAppendingPathComponent:@"plain_dir"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dirPath
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:nil];
    NSURL *dirURL = [NSURL fileURLWithPath:dirPath];

    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:dirURL],
                   @"Plain directory should not be detected as executable");
}

- (void)testSymlinkToAppBundleDetectedAsExecutable
{
    // Symlink pointing to an .app bundle should be resolved and flagged.
    NSString *symlinkPath = [self.tempDir stringByAppendingPathComponent:@"link.app"];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:symlinkPath
                                         withDestinationPath:self.appBundleURL.path
                                                       error:nil];
    NSURL *symlinkURL = [NSURL fileURLWithPath:symlinkPath];

    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:symlinkURL],
                  @"Symlink to app bundle should be detected as executable after resolution");
}

- (void)testExecutableScriptDetectedAsExecutable
{
    // A file with the executable bit set should be flagged.
    NSString *scriptPath = [self.tempDir stringByAppendingPathComponent:@"script.sh"];
    [@"#!/bin/sh\necho hello\n" writeToFile:scriptPath
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:nil];
    // Set executable bit (chmod +x).
    NSDictionary *attrs = @{NSFilePosixPermissions: @(0755)};
    [[NSFileManager defaultManager] setAttributes:attrs
                                     ofItemAtPath:scriptPath
                                            error:nil];
    NSURL *scriptURL = [NSURL fileURLWithPath:scriptPath];

    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:scriptURL],
                  @"File with executable bit set should be detected as executable");
}

- (void)testNonExistentPathNotDetectedAsExecutable
{
    NSURL *missingURL = [NSURL fileURLWithPath:@"/tmp/nonexistent_file_that_does_not_exist_xyzzy"];

    // Should return NO gracefully rather than crash or throw.
    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:missingURL],
                   @"Non-existent path should return NO gracefully");
}

- (void)testNilURLNotDetectedAsExecutable
{
    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:nil],
                   @"Nil URL should return NO");
}

- (void)testBundlePluginDetectedAsDangerous
{
    // A .bundle package (CFBundlePackageType = BNDL) should be caught too,
    // not just .app bundles — plugins can contain executable code.
    NSString *bundlePath = [self.tempDir
        stringByAppendingPathComponent:@"Evil.bundle"];
    NSString *contentsPath = [bundlePath
        stringByAppendingPathComponent:@"Contents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:contentsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *plist = (
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\""
        @" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"    <key>CFBundleIdentifier</key>\n"
        @"    <string>com.test.evilbundle</string>\n"
        @"    <key>CFBundleName</key>\n"
        @"    <string>Evil</string>\n"
        @"    <key>CFBundlePackageType</key>\n"
        @"    <string>BNDL</string>\n"
        @"</dict>\n"
        @"</plist>\n"
    );
    [plist writeToFile:[contentsPath stringByAppendingPathComponent:@"Info.plist"]
            atomically:YES
              encoding:NSUTF8StringEncoding
                 error:nil];
    NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];

    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:bundleURL],
                  @".bundle plugin package should be detected as dangerous");
}

#pragma mark - url:isWithinScopeOfBaseURL: Tests

- (void)testFileInSameDirectoryIsInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/docs/image.png
    // Both are in the same directory; target should be in scope.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"image.png"]];

    XCTAssertTrue([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                  @"File in same directory should be in scope");
}

- (void)testFileInSubdirectoryIsInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/docs/sub/image.png
    // Subdirectory of the base's parent should be in scope.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *subDir = [docsDir stringByAppendingPathComponent:@"sub"];
    [[NSFileManager defaultManager] createDirectoryAtPath:subDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [subDir stringByAppendingPathComponent:@"image.png"]];

    XCTAssertTrue([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                  @"File in subdirectory should be in scope");
}

- (void)testFileOutsideDirectoryIsNotInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/other/evil.app
    // A different sibling of /tmp should not be in scope.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *otherDir = [self.tempDir stringByAppendingPathComponent:@"other"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:otherDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [otherDir stringByAppendingPathComponent:@"evil.app"]];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"File outside base directory should not be in scope");
}

- (void)testDotDotTraversalIsNotInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/docs/../other/evil
    // After resolution, /tmp/other/evil is outside /tmp/docs/ and must be rejected.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *otherDir = [self.tempDir stringByAppendingPathComponent:@"other"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:otherDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    // Construct a path that uses ".." to escape the docs directory.
    NSString *traversalPath = [docsDir stringByAppendingPathComponent:
        @"../other/evil"];
    NSURL *targetURL = [NSURL fileURLWithPath:traversalPath];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"Path traversal via .. should not be in scope after resolution");
}

- (void)testNilBaseURLReturnsFalse
{
    NSURL *targetURL = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"file.png"]];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:nil],
                   @"Nil baseURL should return NO");
}

- (void)testNonFileTargetURLReturnsFalse
{
    // HTTPS URLs are not file URLs and must always be rejected for scope checks.
    NSURL *baseURL = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL URLWithString:@"https://example.com/image.png"];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"Non-file target URL should return NO");
}

- (void)testNilTargetURLReturnsFalse
{
    NSURL *baseURL = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"file.md"]];

    XCTAssertFalse([MPURLSecurityPolicy url:nil isWithinScopeOfBaseURL:baseURL],
                   @"Nil targetURL should return NO");
}

- (void)testSymlinkEscapeIsNotInScope
{
    // A symlink inside the document directory that points outside it must be
    // caught after symlink resolution. This is a distinct vector from ../
    // traversal: the unresolved path looks in-scope but resolves outside it.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *outsideDir = [self.tempDir stringByAppendingPathComponent:@"outside"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:outsideDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Create a symlink inside docs/ pointing to the outside directory.
    NSString *symlinkPath = [docsDir stringByAppendingPathComponent:@"escape"];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:symlinkPath
                                         withDestinationPath:outsideDir
                                                       error:nil];

    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [symlinkPath stringByAppendingPathComponent:@"evil.app"]];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"Symlink escaping directory scope must be rejected after resolution");
}

@end
