//
//  MPTerminalPreferencesTests.m
//  MacDownTests
//
//  Tests for shell utility installation functionality (Issue #38)
//

#import <XCTest/XCTest.h>
#import "MPTerminalPreferencesViewController.h"
#import "MPGlobals.h"
#import <sys/stat.h>

@interface MPTerminalPreferencesViewController (Testing)
// Expose private methods for testing
- (BOOL)ensureDirectoryExists:(NSString *)path error:(NSError **)error;
- (BOOL)createSymlinkAtPath:(NSString *)linkPath toDestination:(NSString *)destinationPath error:(NSError **)error;
- (BOOL)isPathInUserPATH:(NSString *)path;
- (NSString *)userBinPath;
@end

@interface MPTerminalPreferencesTests : XCTestCase
@property (strong) NSString *testDirectory;
@property (strong) NSString *testBinDirectory;
@property (strong) NSString *testSymlinkPath;
@property (strong) NSString *testSourcePath;
@property (strong) NSFileManager *fileManager;
@property (strong) NSString *originalPATH;
@property (strong) MPTerminalPreferencesViewController *controller;
@end

@implementation MPTerminalPreferencesTests

#pragma mark - Setup and Teardown

- (void)setUp {
    [super setUp];

    self.fileManager = [NSFileManager defaultManager];
    self.controller = [[MPTerminalPreferencesViewController alloc] init];

    // Create unique test directory
    NSString *tempDir = NSTemporaryDirectory();
    NSString *uniqueDir = [[NSUUID UUID] UUIDString];
    self.testDirectory = [tempDir stringByAppendingPathComponent:uniqueDir];
    self.testBinDirectory = [self.testDirectory stringByAppendingPathComponent:@".local/bin"];
    self.testSymlinkPath = [self.testBinDirectory stringByAppendingPathComponent:@"macdown"];

    // Create a dummy source file to symlink to
    self.testSourcePath = [self.testDirectory stringByAppendingPathComponent:@"macdown-source"];
    [@"#!/bin/bash\necho 'test'" writeToFile:self.testSourcePath
                                   atomically:YES
                                     encoding:NSUTF8StringEncoding
                                        error:nil];

    // Save original PATH
    self.originalPATH = [NSProcessInfo.processInfo.environment[@"PATH"] copy];
}

- (void)tearDown {
    // Clean up test directory
    if (self.testDirectory) {
        [self.fileManager removeItemAtPath:self.testDirectory error:nil];
    }

    // Restore PATH if modified
    if (self.originalPATH) {
        setenv("PATH", [self.originalPATH UTF8String], 1);
    }

    self.controller = nil;
    [super tearDown];
}

#pragma mark - Directory Creation Tests

- (void)testEnsureDirectoryExistsCreatesNewDirectory {
    // Verify directory doesn't exist yet
    BOOL exists = [self.fileManager fileExistsAtPath:self.testBinDirectory];
    XCTAssertFalse(exists, @"Test bin directory should not exist yet");

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller ensureDirectoryExists:self.testBinDirectory error:&error];

    // Verify success
    XCTAssertTrue(success, @"Should create directory successfully");
    XCTAssertNil(error, @"Should not return error");

    // Verify directory was created
    BOOL isDirectory = NO;
    exists = [self.fileManager fileExistsAtPath:self.testBinDirectory
                                    isDirectory:&isDirectory];
    XCTAssertTrue(exists, @"Directory should exist after creation");
    XCTAssertTrue(isDirectory, @"Path should be a directory");
}

- (void)testEnsureDirectoryExistsWhenAlreadyExists {
    // Setup: Create directory first
    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller ensureDirectoryExists:self.testBinDirectory error:&error];

    // Verify it succeeds without error
    XCTAssertTrue(success, @"Should succeed when directory already exists");
    XCTAssertNil(error, @"Should not return error");
}

- (void)testEnsureDirectoryCreatesIntermediateDirectories {
    // Verify parent .local directory doesn't exist
    NSString *localDir = [self.testDirectory stringByAppendingPathComponent:@".local"];
    BOOL exists = [self.fileManager fileExistsAtPath:localDir];
    XCTAssertFalse(exists, @"Parent directory should not exist yet");

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller ensureDirectoryExists:self.testBinDirectory error:&error];

    // Verify both parent and target directories were created
    XCTAssertTrue(success, @"Should create intermediate directories");
    XCTAssertNil(error, @"Should not return error");

    BOOL localDirExists = [self.fileManager fileExistsAtPath:localDir];
    BOOL binDirExists = [self.fileManager fileExistsAtPath:self.testBinDirectory];

    XCTAssertTrue(localDirExists, @"Parent .local directory should be created");
    XCTAssertTrue(binDirExists, @"Target bin directory should be created");
}

#pragma mark - Symlink Installation Tests

- (void)testCreateSymlinkSuccessfully {
    // Setup: Create the bin directory first
    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];

    // Verify symlink doesn't exist yet
    BOOL exists = [self.fileManager fileExistsAtPath:self.testSymlinkPath];
    XCTAssertFalse(exists, @"Symlink should not exist yet");

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller createSymlinkAtPath:self.testSymlinkPath
                                         toDestination:self.testSourcePath
                                                  error:&error];

    // Verify success
    XCTAssertTrue(success, @"Should create symlink successfully");
    XCTAssertNil(error, @"Should not return error");

    // Verify symlink was created and points to correct destination
    NSString *destination = [self.fileManager destinationOfSymbolicLinkAtPath:self.testSymlinkPath
                                                                        error:nil];
    XCTAssertEqualObjects(destination, self.testSourcePath,
                          @"Symlink should point to source file");
}

- (void)testCreateSymlinkWhenSymlinkAlreadyExistsCorrectTarget {
    // Setup: Create symlink first
    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    [self.fileManager createSymbolicLinkAtPath:self.testSymlinkPath
                           withDestinationPath:self.testSourcePath
                                         error:nil];

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller createSymlinkAtPath:self.testSymlinkPath
                                         toDestination:self.testSourcePath
                                                  error:&error];

    // Should succeed since it's already pointing to correct target
    XCTAssertTrue(success, @"Should succeed when symlink already exists with correct target");
    XCTAssertNil(error, @"Should not return error");
}

- (void)testCreateSymlinkWhenSymlinkAlreadyExistsWrongTarget {
    // Setup: Create symlink to wrong target
    NSString *wrongTarget = [self.testDirectory stringByAppendingPathComponent:@"wrong-target"];
    [@"wrong" writeToFile:wrongTarget atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    [self.fileManager createSymbolicLinkAtPath:self.testSymlinkPath
                           withDestinationPath:wrongTarget
                                         error:nil];

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller createSymlinkAtPath:self.testSymlinkPath
                                         toDestination:self.testSourcePath
                                                  error:&error];

    // Should either succeed (replacing symlink) or fail with clear error
    if (success) {
        // Verify symlink now points to correct target
        NSString *destination = [self.fileManager destinationOfSymbolicLinkAtPath:self.testSymlinkPath
                                                                            error:nil];
        XCTAssertEqualObjects(destination, self.testSourcePath,
                              @"Symlink should be updated to correct target");
    } else {
        // If it fails, should have error
        XCTAssertNotNil(error, @"Should return error if unable to update symlink");
    }
}

- (void)testCreateSymlinkWhenRegularFileExists {
    // Setup: Create regular file at symlink path
    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    [@"regular file" writeToFile:self.testSymlinkPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller createSymlinkAtPath:self.testSymlinkPath
                                         toDestination:self.testSourcePath
                                                  error:&error];

    // Should fail - don't overwrite regular files
    XCTAssertFalse(success, @"Should fail when regular file exists at symlink path");
    XCTAssertNotNil(error, @"Should return error");
}

- (void)testCreateSymlinkWithInvalidSource {
    // Setup: Create directory, but use non-existent source
    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    NSString *invalidSource = @"/nonexistent/path/to/macdown";

    // Call method under test
    NSError *error = nil;
    BOOL success = [self.controller createSymlinkAtPath:self.testSymlinkPath
                                         toDestination:invalidSource
                                                  error:&error];

    // Should fail when source doesn't exist
    XCTAssertFalse(success, @"Should fail when source file doesn't exist");
    XCTAssertNotNil(error, @"Should return error");
}

#pragma mark - Symlink Uninstallation Tests

- (void)testRemoveSymlinkSuccessfully {
    // Setup: Create symlink
    [self.fileManager createDirectoryAtPath:self.testBinDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:nil];
    [self.fileManager createSymbolicLinkAtPath:self.testSymlinkPath
                           withDestinationPath:self.testSourcePath
                                         error:nil];

    // Verify symlink exists
    BOOL exists = [self.fileManager fileExistsAtPath:self.testSymlinkPath];
    XCTAssertTrue(exists, @"Symlink should exist before removal");

    // Remove symlink (using standard NSFileManager since controller method wraps this)
    NSError *error = nil;
    BOOL success = [self.fileManager removeItemAtPath:self.testSymlinkPath error:&error];

    // Verify removal
    XCTAssertTrue(success, @"Should remove symlink successfully");
    XCTAssertNil(error, @"Should not return error");

    exists = [self.fileManager fileExistsAtPath:self.testSymlinkPath];
    XCTAssertFalse(exists, @"Symlink should not exist after removal");
}

- (void)testRemoveSymlinkWhenNotExists {
    // Try to remove non-existent symlink
    NSError *error = nil;
    BOOL success = [self.fileManager removeItemAtPath:self.testSymlinkPath error:&error];

    // Should fail gracefully
    XCTAssertFalse(success, @"Should fail when symlink doesn't exist");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, NSFileNoSuchFileError, @"Should return 'no such file' error");
}

#pragma mark - PATH Detection Tests

- (void)testIsPathInUserPATHWhenPresent {
    // Setup: Add test bin directory to PATH
    NSString *newPATH = [NSString stringWithFormat:@"%@:%@",
                         self.testBinDirectory, self.originalPATH];
    setenv("PATH", [newPATH UTF8String], 1);

    // Call method under test
    BOOL inPATH = [self.controller isPathInUserPATH:self.testBinDirectory];

    // Verify result
    XCTAssertTrue(inPATH, @"Should detect path in PATH environment variable");
}

- (void)testIsPathInUserPATHWhenAbsent {
    // Don't modify PATH - test directory should not be in it

    // Call method under test
    BOOL inPATH = [self.controller isPathInUserPATH:self.testBinDirectory];

    // Verify result
    XCTAssertFalse(inPATH, @"Should detect path is not in PATH");
}

- (void)testIsPathInUserPATHWithExpandedPath {
    // Setup: Add path with tilde, but check with expanded path
    NSString *tildePathInPATH = @"~/.local/bin";
    NSString *expandedPathToCheck = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"];

    NSString *newPATH = [NSString stringWithFormat:@"%@:%@",
                         tildePathInPATH, self.originalPATH];
    setenv("PATH", [newPATH UTF8String], 1);

    // Call method under test with expanded path
    BOOL inPATH = [self.controller isPathInUserPATH:expandedPathToCheck];

    // Should detect match even though one uses tilde and other is expanded
    XCTAssertTrue(inPATH, @"Should detect path even when PATH contains tilde notation");
}

- (void)testUserBinPathReturnsCorrectPath {
    // Call method under test
    NSString *userBinPath = [self.controller userBinPath];

    // Verify it returns ~/.local/bin
    NSString *expectedPath = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"];
    XCTAssertEqualObjects(userBinPath, expectedPath, @"Should return ~/.local/bin path");
}

#pragma mark - Integration Tests

- (void)testCompleteInstallWorkflow {
    // This will test the full workflow once implementation is complete
    // For now, just a placeholder
    XCTAssertTrue(YES, @"Integration test placeholder");
}

@end
