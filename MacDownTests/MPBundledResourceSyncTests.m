//
//  MPBundledResourceSyncTests.m
//  MacDown 3000
//
//  Filesystem-orchestrating tests for MPSyncBundledResourcesInPaths: the
//  twelve-row decision table end to end (design §9.1), plus idempotence,
//  symlinked directories, the bundle-enumeration guard, nil roots,
//  permissions, case sensitivity, and the mandatory temp-root safety guard
//  (design §9.2, contract §11, design §6 R6).
//
//  These tests were written against the specification before the
//  implementation existed, so they follow the contract's twelve-row decision
//  table (contract §6) rather than mirroring the structure of
//  MPBundledResourceSync.m.
//
//  The cited "contract §…" and "design §…" sections refer to the requirements
//  and design documents posted on GitHub issue #548.
//
//  HEADS UP, RUNNING THIS LOCALLY: MacDownTests is app-hosted, so launching
//  the suite runs the real -[MPMainController copyFiles] against your own
//  ~/Library/Application Support/MacDown 3000/. That used to be able only to
//  add a missing bundled file; it can now atomically replace a pristine one
//  so it matches the branch under test. Files you have edited yourself are
//  never touched.
//
//  Related to GitHub issue #548.
//

#import <XCTest/XCTest.h>
#import <sys/stat.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>
#import <CommonCrypto/CommonDigest.h>
#import "MPBundledResourceSync.h"
#import "MPUtilities.h"

@interface MPBundledResourceSyncTests : XCTestCase
@property (strong) NSString *tempDir;
@property (strong) NSFileManager *fm;
@end

@implementation MPBundledResourceSyncTests

- (void)setUp
{
    [super setUp];
    self.fm = [NSFileManager defaultManager];
    self.tempDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.fm createDirectoryAtPath:self.tempDir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
}

- (void)tearDown
{
    [self.fm removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Mandatory safety infrastructure (contract §11, design §6 R6)

// The predicate a refactor could silently stop guarding with. It must
// resolve symlinks on BOTH sides of the prefix check (design §6 R6):
// macOS's /var -> /private/var symlink otherwise makes the check pass or
// fail inconsistently depending on how the candidate path was spelled.
- (BOOL)mp_pathIsUnderTemporaryDirectory:(NSString *)path
{
    if (path.length == 0)
        return NO;
    NSString *resolvedPath = [[NSURL fileURLWithPath:path]
        URLByResolvingSymlinksInPath].path;
    NSString *resolvedTempRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByResolvingSymlinksInPath].path;
    if (![resolvedPath hasSuffix:@"/"])
        resolvedPath = [resolvedPath stringByAppendingString:@"/"];
    if (![resolvedTempRoot hasSuffix:@"/"])
        resolvedTempRoot = [resolvedTempRoot stringByAppendingString:@"/"];
    return [resolvedPath hasPrefix:resolvedTempRoot];
}

// Mandatory shared factory (contract §11): creates <tempDir>/user and
// <tempDir>/bundle and asserts BOTH resolve under NSTemporaryDirectory()
// before returning them. If a refactor ever lets a real path reach the
// sync logic under test, this guard fails loudly and immediately rather
// than letting a test rewrite a developer's actual themes.
- (void)makeRootsUser:(NSString **)userRootOut bundle:(NSString **)bundleRootOut
{
    NSString *userRoot = [self.tempDir stringByAppendingPathComponent:@"user"];
    NSString *bundleRoot = [self.tempDir stringByAppendingPathComponent:@"bundle"];

    XCTAssertTrue([self mp_pathIsUnderTemporaryDirectory:userRoot],
                  @"Refusing to hand out a user root outside "
                  @"NSTemporaryDirectory(): %@", userRoot);
    XCTAssertTrue([self mp_pathIsUnderTemporaryDirectory:bundleRoot],
                  @"Refusing to hand out a bundle root outside "
                  @"NSTemporaryDirectory(): %@", bundleRoot);

    [self.fm createDirectoryAtPath:bundleRoot
        withIntermediateDirectories:YES attributes:nil error:nil];
    // userRoot is deliberately NOT created here — several tests (row 1)
    // require it to be absent. Callers create it when they need it to exist.

    if (userRootOut) *userRootOut = userRoot;
    if (bundleRootOut) *bundleRootOut = bundleRoot;
}

- (void)testTempRootSafetyGuardRejectsNonTemporaryPath
{
    XCTAssertFalse([self mp_pathIsUnderTemporaryDirectory:
                    @"/Users/x/Library/Application Support/MacDown 3000"],
                   @"The guard must reject a real Application Support path");
    XCTAssertFalse([self mp_pathIsUnderTemporaryDirectory:nil]);
    XCTAssertFalse([self mp_pathIsUnderTemporaryDirectory:@""]);

    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    XCTAssertTrue([self mp_pathIsUnderTemporaryDirectory:userRoot],
                  @"The factory's own roots must pass the guard");
    XCTAssertTrue([self mp_pathIsUnderTemporaryDirectory:bundleRoot],
                  @"The factory's own roots must pass the guard");
}

#pragma mark - Helpers

- (void)writeString:(NSString *)string toPath:(NSString *)path
{
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![self.fm fileExistsAtPath:dir])
        [self.fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                             attributes:nil error:nil];
    BOOL ok = [string writeToFile:path atomically:YES
                          encoding:NSUTF8StringEncoding error:nil];
    XCTAssertTrue(ok, @"Test setup failed to write %@", path);
}

// Computes the expected digest independently of the production code under
// test (MPSHA256HexOfData is itself part of the stub and currently returns
// nil for everything, so leaning on it here would make every assertion
// below compare nil against nil and pass vacuously against the stub).
// CommonCrypto is already an SDK dependency per the contract (§9).
- (NSString *)sha256OfString:(NSString *)string
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", digest[i]];
    return [hex copy];
}

- (NSDictionary *)readManifestJSONRawAtPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data)
        return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (void)writeProvenanceFiles:(NSDictionary<NSString *, NSString *> *)files
                       atPath:(NSString *)path
{
    NSDictionary *doc = @{@"version": @1, @"files": files ?: @{}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:doc
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![self.fm fileExistsAtPath:dir])
        [self.fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                             attributes:nil error:nil];
    [data writeToFile:path atomically:YES];
}

- (unsigned long long)inodeAtPath:(NSString *)path
{
    NSDictionary *attrs = [self.fm attributesOfItemAtPath:path error:nil];
    return [attrs[NSFileSystemFileNumber] unsignedLongLongValue];
}

- (NSDate *)modDateAtPath:(NSString *)path
{
    NSDictionary *attrs = [self.fm attributesOfItemAtPath:path error:nil];
    return attrs[NSFileModificationDate];
}

- (NSString *)provenancePathForUserRoot:(NSString *)userRoot
{
    return MPProvenanceManifestPathInRoot(userRoot);
}

#pragma mark - Row 1: first run ever, data directory absent

- (void)testRow01FirstRunCreatesDirectoryCopiesAllFilesAndWritesManifest
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    // userRoot intentionally not created — this is the "absent" case.
    XCTAssertFalse([self.fm fileExistsAtPath:userRoot]);

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"t" toPath:[bundleRoot stringByAppendingPathComponent:@"Themes/T.style"]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertNotNil(report);
    XCTAssertFalse(report.aborted);
    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    NSString *tPath = [userRoot stringByAppendingPathComponent:@"Themes/T.style"];
    XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                          [@"a" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects([self.fm contentsAtPath:tPath],
                          [@"t" dataUsingEncoding:NSUTF8StringEncoding]);

    NSDictionary *manifest = report.manifest;
    XCTAssertEqual(manifest.count, 2u);
    XCTAssertEqualObjects(manifest[@"Styles/A.css"], [self sha256OfString:@"a"]);
    XCTAssertEqualObjects(manifest[@"Themes/T.style"], [self sha256OfString:@"t"]);
    XCTAssertEqual(report.copiedCount, 2u);
    XCTAssertEqual(report.refreshedCount, 0u);
}

#pragma mark - Row 2: absent file is copied and recorded

- (void)testRow02AbsentFileIsCopiedAndRecorded
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"b" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];

    NSString *bPath = [userRoot stringByAppendingPathComponent:@"Styles/B.css"];
    [self writeString:@"b" toPath:bPath]; // matches bundle bytes exactly
    [self writeProvenanceFiles:@{@"Styles/B.css": [self sha256OfString:@"b"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    NSDate *bModBefore = [self modDateAtPath:bPath];
    unsigned long long bInodeBefore = [self inodeAtPath:bPath];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                          [@"a" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects(report.manifest[@"Styles/A.css"], [self sha256OfString:@"a"]);
    XCTAssertEqualObjects(report.manifest[@"Styles/B.css"], [self sha256OfString:@"b"]);
    XCTAssertEqual(report.copiedCount, 1u, @"only A.css should have been copied");

    // B.css must be untouched: same modification date AND same inode.
    XCTAssertEqualObjects([self modDateAtPath:bPath], bModBefore,
                          @"B.css's modification date must be unchanged");
    XCTAssertEqual([self inodeAtPath:bPath], bInodeBefore,
                   @"B.css's inode must be unchanged");
}

#pragma mark - Row 3: present, pristine, differing -> refresh

- (void)testRow03PristineDifferingIsRefreshed
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"v1" toPath:userPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self.fm contentsAtPath:userPath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects(report.manifest[@"Styles/A.css"], [self sha256OfString:@"v2"]);
    XCTAssertEqual(report.refreshedCount, 1u);
}

- (void)testRow03RefreshIsAtomicAndLeavesNoResidue
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"v1" toPath:userPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    unsigned long long inodeBefore = [self inodeAtPath:userPath];

    MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    unsigned long long inodeAfter = [self inodeAtPath:userPath];
    XCTAssertNotEqual(inodeBefore, inodeAfter,
                      @"Refresh must replace the file (new inode), never "
                      @"truncate-in-place (same inode)");

    NSString *stylesDir = [userRoot stringByAppendingPathComponent:@"Styles"];
    NSArray<NSString *> *entries = [self.fm contentsOfDirectoryAtPath:stylesDir
                                                                 error:nil];
    XCTAssertEqualObjects(entries, @[@"A.css"],
                          @"No .tmp/.orig/backup residue may remain in the "
                          @"directory after a refresh, got: %@", entries);
}

#pragma mark - Row 4: present, pristine, equal to bundle -> record only

- (void)testRow04PristineEqualToBundleIsNotWrittenAndProvenanceBackfilled
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"v2" toPath:userPath];
    // provenance empty: file exists, but no record of us ever placing it.
    [self writeProvenanceFiles:@{} atPath:[self provenancePathForUserRoot:userRoot]];

    NSDate *modBefore = [self modDateAtPath:userPath];
    unsigned long long inodeBefore = [self inodeAtPath:userPath];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects(report.manifest[@"Styles/A.css"], [self sha256OfString:@"v2"]);
    XCTAssertEqualObjects([self modDateAtPath:userPath], modBefore,
                          @"Row 4 must never write to the file: mod date "
                          @"must be unchanged");
    XCTAssertEqual([self inodeAtPath:userPath], inodeBefore,
                   @"Row 4 must never write to the file: inode must be "
                   @"unchanged");
    XCTAssertEqual(report.unchangedCount, 1u);
    XCTAssertEqual(report.refreshedCount, 0u);
    XCTAssertEqual(report.copiedCount, 0u);
}

#pragma mark - Row 5: present, modified -> left untouched

- (void)testRow05ModifiedFileIsLeftUntouched
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"MY EDITS" toPath:userPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self.fm contentsAtPath:userPath],
                          [@"MY EDITS" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(report.modifiedCount, 1u);
}

- (void)testRow05ModifiedFileGetsNoProvenanceEntryAndNoBackup
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"MY EDITS" toPath:userPath];
    // A companion pristine, differing file in the same directory: it MUST
    // be refreshed by this same sync. Without this, every assertion below
    // is satisfiable by a no-op stub that touches nothing at all — this
    // file makes that impossible, since the stub cannot produce a
    // refreshed B.css.
    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    NSString *bPath = [userRoot stringByAppendingPathComponent:@"Styles/B.css"];
    [self writeString:@"v1" toPath:bPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v1"],
                                  @"Styles/B.css": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self.fm contentsAtPath:bPath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding],
                          @"Sanity check that this sync actually performed "
                          @"real work: the companion pristine file must "
                          @"have been refreshed");
    XCTAssertNil(report.manifest[@"Styles/A.css"],
                @"A modified file must get no provenance entry");
    NSString *stylesDir = [userRoot stringByAppendingPathComponent:@"Styles"];
    NSArray<NSString *> *entries =
        [[self.fm contentsOfDirectoryAtPath:stylesDir error:nil]
            sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(entries, (@[@"A.css", @"B.css"]),
                          @"No .orig/.bak file may be created, got: %@",
                          entries);
}

#pragma mark - Row 6: new bundle file, absent from target -> copy

- (void)testRow06NewBundleFileIsCopied
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"new" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/NEW.css"]];
    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"a" toPath:aPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"a"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSString *newPath = [userRoot stringByAppendingPathComponent:@"Styles/NEW.css"];
    XCTAssertEqualObjects([self.fm contentsAtPath:newPath],
                          [@"new" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects(report.manifest[@"Styles/A.css"], [self sha256OfString:@"a"]);
    XCTAssertEqualObjects(report.manifest[@"Styles/NEW.css"], [self sha256OfString:@"new"]);
    XCTAssertEqual(report.copiedCount, 1u);
}

#pragma mark - Row 7: file removed from bundle -> never delete, drop entry

- (void)testRow07FileRemovedFromBundleIsNeverDeleted
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"a" toPath:aPath];
    NSString *gonePath = [userRoot stringByAppendingPathComponent:@"Styles/GONE.css"];
    [self writeString:@"old" toPath:gonePath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"a"],
                                  @"Styles/GONE.css": [self sha256OfString:@"old"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertTrue([self.fm fileExistsAtPath:gonePath]);
    XCTAssertEqualObjects([self.fm contentsAtPath:gonePath],
                          [@"old" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(report.orphanedCount, 1u);
}

- (void)testRow07ProvenanceEntryForRemovedFileIsDropped
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"a" toPath:aPath];
    NSString *gonePath = [userRoot stringByAppendingPathComponent:@"Styles/GONE.css"];
    [self writeString:@"old" toPath:gonePath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"a"],
                                  @"Styles/GONE.css": [self sha256OfString:@"old"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([NSSet setWithArray:report.manifest.allKeys],
                          [NSSet setWithArray:@[@"Styles/A.css"]],
                          @"Styles/GONE.css's provenance entry must be "
                          @"pruned (§7.5), got keys: %@", report.manifest.allKeys);
}

// A provenance entry is the only thing that distinguishes "we shipped this
// once and no longer do" (a genuine row 7 orphan) from "the user made their
// own style" — help.md:293 explicitly invites the latter. Counting the
// user's own file as an orphan would put it in the summary log on every
// launch forever, which contract §9 forbids.
- (void)testRow07UserAuthoredFileWithNoProvenanceIsNotAnOrphan
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"a" toPath:aPath];
    // Removed from the bundle, but we placed it once: a real orphan.
    NSString *gonePath = [userRoot stringByAppendingPathComponent:@"Styles/GONE.css"];
    [self writeString:@"old" toPath:gonePath];
    // Never shipped by us at all: the user's own file.
    NSString *minePath = [userRoot stringByAppendingPathComponent:@"Styles/Mine.css"];
    [self writeString:@"mine" toPath:minePath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"a"],
                                  @"Styles/GONE.css": [self sha256OfString:@"old"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    NSDate *mineMod = [self modDateAtPath:minePath];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqual(report.orphanedCount, 1u,
                   @"Only Styles/GONE.css had a provenance entry, so only it "
                   @"is an orphan; Styles/Mine.css is the user's own file");
    XCTAssertTrue([self.fm fileExistsAtPath:minePath],
                  @"The user's own file must be left on disk (row 7)");
    XCTAssertEqualObjects([self.fm contentsAtPath:minePath],
                          [@"mine" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects([self modDateAtPath:minePath], mineMod,
                          @"The user's own file must not be written to");
    XCTAssertNil(report.manifest[@"Styles/Mine.css"],
                 @"A file we never placed gets no provenance entry (row 7)");
    XCTAssertEqualObjects([self.fm contentsAtPath:gonePath],
                          [@"old" dataUsingEncoding:NSUTF8StringEncoding],
                          @"The genuine orphan is still never deleted");
}

#pragma mark - Row 8: provenance manifest missing

- (void)testRow08ManifestMissingClassifiesFromBundleAlone
{
    // With no provenance manifest, the current bundle bytes are the ONLY
    // evidence available. A file that already equals them is adopted
    // (RecordOnly, so it receives every future bundled fix); a file that
    // differs is left strictly alone, because nothing proves we wrote it.
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    // No provenance file written at all.

    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/C.css"]];

    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    NSString *bPath = [userRoot stringByAppendingPathComponent:@"Styles/B.css"];
    NSString *cPath = [userRoot stringByAppendingPathComponent:@"Styles/C.css"];
    // A.css holds an older bundled version, but nothing on this machine
    // records that we put it there. It stays as it is.
    [self writeString:@"v1" toPath:aPath];
    [self writeString:@"v3" toPath:bPath];
    [self writeString:@"mine" toPath:cPath];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertFalse(report.aborted);
    XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                          [@"v1" dataUsingEncoding:NSUTF8StringEncoding],
                          @"A.css differs from the bundle and has no "
                          @"provenance entry -> left alone, not refreshed");
    XCTAssertEqualObjects([self.fm contentsAtPath:bPath],
                          [@"v3" dataUsingEncoding:NSUTF8StringEncoding],
                          @"B.css already equals bundle -> untouched");
    XCTAssertEqualObjects([NSSet setWithArray:report.manifest.allKeys],
                          ([NSSet setWithArray:@[@"Styles/B.css"]]),
                          @"only the file we can prove is pristine gets an "
                          @"entry, got keys: %@", report.manifest.allKeys);
    XCTAssertEqual(report.unchangedCount, 1u);
    XCTAssertEqual(report.refreshedCount, 0u);
    XCTAssertEqual(report.modifiedCount, 2u,
                   @"A.css and C.css are both unprovable -> both counted as "
                   @"modified and left untouched");
}

- (void)testRow08ManifestMissingNeverOverwritesUnknownBytes
{
    // §6.1 step 3 — the single highest-risk line in the requirements.
    // Absence of a provenance manifest must NEVER be read as license to
    // overwrite bytes that cannot be proven pristine.
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    // No provenance file written at all.

    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/C.css"]];

    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    NSString *cPath = [userRoot stringByAppendingPathComponent:@"Styles/C.css"];
    [self writeString:@"v1" toPath:aPath];
    // B.css already equals the bundle, so it is adopted. It is the positive
    // control: without it, every assertion below would be satisfiable by a
    // stub that does nothing at all.
    [self writeString:@"v3" toPath:[userRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    [self writeString:@"mine" toPath:cPath];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects(report.manifest[@"Styles/B.css"],
                          [self sha256OfString:@"v3"],
                          @"positive control: the provably pristine file "
                          @"must have been adopted by this same sync");
    XCTAssertEqualObjects([self.fm contentsAtPath:cPath],
                          [@"mine" dataUsingEncoding:NSUTF8StringEncoding],
                          @"C.css's unrecognised bytes must be left "
                          @"completely alone");
    XCTAssertNil(report.manifest[@"Styles/C.css"],
                @"C.css must get no provenance entry — a manifest entry "
                @"would misrepresent bytes we did not place");
    XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                          [@"v1" dataUsingEncoding:NSUTF8StringEncoding],
                          @"A.css's bytes are equally unprovable and must "
                          @"also be left completely alone");
    XCTAssertNil(report.manifest[@"Styles/A.css"]);
    XCTAssertEqual(report.modifiedCount, 2u);
}

#pragma mark - Row 9: provenance manifest corrupt

- (void)testRow09CorruptManifestBehavesExactlyLikeMissing
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/C.css"]];
    [self writeString:@"v1" toPath:[userRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"v3" toPath:[userRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    [self writeString:@"mine" toPath:[userRoot stringByAppendingPathComponent:@"Styles/C.css"]];

    // Truncated JSON, simulating corruption.
    [self writeString:@"{\"version\":1,\"files\":"
                toPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertFalse(report.aborted);
    XCTAssertEqualObjects([NSSet setWithArray:report.manifest.allKeys],
                          ([NSSet setWithArray:@[@"Styles/B.css"]]),
                          @"A corrupt manifest must degrade to exactly the "
                          @"row-8 (missing manifest) outcome: only B.css, "
                          @"which equals the bundle, is provable");
    XCTAssertEqualObjects([self.fm contentsAtPath:[userRoot stringByAppendingPathComponent:@"Styles/A.css"]],
                          [@"v1" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects([self.fm contentsAtPath:[userRoot stringByAppendingPathComponent:@"Styles/C.css"]],
                          [@"mine" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testRow09MalformedShapesAllDegradeToMissing
{
    NSArray *malformedBodies = @[
        @"[1,2,3]",
        @"\"hello\"",
        @"{\"version\":99,\"files\":{}}",
        @"{}",
        @"",
    ];

    for (NSString *body in malformedBodies) {
        NSString *userRoot, *bundleRoot;
        [self makeRootsUser:&userRoot bundle:&bundleRoot];

        [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
        NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
        // Equal to the bundle, so row 8 adopts it (RecordOnly). This is the
        // observable proof that the malformed manifest was read as missing
        // rather than aborting the sync: an aborted or failed run records
        // nothing at all.
        [self writeString:@"v3" toPath:aPath];
        // Differing bytes with no usable provenance entry: they must survive
        // the degradation untouched.
        NSString *bPath = [userRoot stringByAppendingPathComponent:@"Styles/B.css"];
        [self writeString:@"v3" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];
        [self writeString:@"mine" toPath:bPath];
        [self writeString:body toPath:[self provenancePathForUserRoot:userRoot]];

        MPBundledResourceSyncReport *report =
            MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

        XCTAssertFalse(report.aborted, @"body=%@", body);
        XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                              [@"v3" dataUsingEncoding:NSUTF8StringEncoding],
                              @"body=%@ must degrade to row 8", body);
        XCTAssertEqualObjects(report.manifest[@"Styles/A.css"],
                              [self sha256OfString:@"v3"], @"body=%@", body);
        XCTAssertEqualObjects([self.fm contentsAtPath:bPath],
                              [@"mine" dataUsingEncoding:NSUTF8StringEncoding],
                              @"body=%@ must not overwrite unprovable bytes",
                              body);
        XCTAssertNil(report.manifest[@"Styles/B.css"], @"body=%@", body);

        // A valid manifest must exist on disk afterwards.
        NSDictionary *onDisk = [self readManifestJSONRawAtPath:
                                [self provenancePathForUserRoot:userRoot]];
        XCTAssertNotNil(onDisk, @"body=%@ must leave a valid manifest on disk", body);

        [self.fm removeItemAtPath:self.tempDir error:nil];
        [self.fm createDirectoryAtPath:self.tempDir
            withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

#pragma mark - Row 10: target entry not a regular file

- (void)testRow10SymlinkTargetIsSkippedAndNotFollowed
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];

    NSString *outsidePath = [self.tempDir stringByAppendingPathComponent:@"outside.css"];
    [self writeString:@"SECRET" toPath:outsidePath];

    NSString *stylesDir = [userRoot stringByAppendingPathComponent:@"Styles"];
    [self.fm createDirectoryAtPath:stylesDir withIntermediateDirectories:YES
                         attributes:nil error:nil];
    NSString *linkPath = [stylesDir stringByAppendingPathComponent:@"A.css"];
    NSError *linkError = nil;
    BOOL linked = [self.fm createSymbolicLinkAtPath:linkPath
                                 withDestinationPath:outsidePath
                                               error:&linkError];
    XCTAssertTrue(linked, @"Test setup: failed to create symlink: %@", linkError);

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSDictionary *attrs = [self.fm attributesOfItemAtPath:linkPath error:nil];
    XCTAssertEqualObjects(attrs[NSFileType], NSFileTypeSymbolicLink,
                          @"The symlink itself must remain a symlink");
    XCTAssertEqualObjects([self.fm contentsAtPath:outsidePath],
                          [@"SECRET" dataUsingEncoding:NSUTF8StringEncoding],
                          @"We must never write through the symlink");
    XCTAssertNil(report.manifest[@"Styles/A.css"]);
    XCTAssertEqual(report.skippedCount, 1u);
}

- (void)testRow10DirectoryEntryIsSkipped
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];

    NSString *dirAsFilePath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self.fm createDirectoryAtPath:dirAsFilePath withIntermediateDirectories:YES
                         attributes:nil error:nil];
    NSString *innerFilePath = [dirAsFilePath stringByAppendingPathComponent:@"inner.txt"];
    [self writeString:@"inner" toPath:innerFilePath];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    BOOL isDir = NO;
    XCTAssertTrue([self.fm fileExistsAtPath:dirAsFilePath isDirectory:&isDir]);
    XCTAssertTrue(isDir, @"Must still be a directory");
    XCTAssertTrue([self.fm fileExistsAtPath:innerFilePath],
                  @"Contents of the directory must remain intact");
    XCTAssertNil(report.manifest[@"Styles/A.css"]);
    XCTAssertEqual(report.skippedCount, 1u);
}

- (void)testRow10FifoEntryIsSkipped
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    // Companion normal file, absent from target, that must be copied by
    // this same sync — proves this test is not satisfiable by a no-op
    // stub that never opens anything, FIFO or otherwise.
    [self writeString:@"n" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/NORMAL.css"]];

    NSString *stylesDir = [userRoot stringByAppendingPathComponent:@"Styles"];
    [self.fm createDirectoryAtPath:stylesDir withIntermediateDirectories:YES
                         attributes:nil error:nil];
    NSString *fifoPath = [stylesDir stringByAppendingPathComponent:@"A.css"];

    int rc = mkfifo(fifoPath.fileSystemRepresentation, 0666);
    XCTAssertEqual(rc, 0, @"Test setup: mkfifo failed: %s", strerror(errno));

    // The test COMPLETING is itself the proof the sync never opened the
    // FIFO (open(2) on a FIFO with no reader/writer on the other end
    // blocks). We do not add our own timeout guard around the call under
    // test — that would hide a real hang instead of surfacing it as a
    // test-suite timeout, which is the loud failure we want if this
    // regresses.
    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    // NSFileType for a FIFO can be reported inconsistently by
    // NSFileManager across OS versions; assert via stat(2) directly for an
    // unambiguous check that it is still a FIFO and was never opened
    // and replaced.
    struct stat st;
    XCTAssertEqual(stat(fifoPath.fileSystemRepresentation, &st), 0);
    XCTAssertTrue(S_ISFIFO(st.st_mode), @"Must still be a FIFO");
    XCTAssertNil(report.manifest[@"Styles/A.css"]);
    XCTAssertEqual(report.skippedCount, 1u);
    XCTAssertEqualObjects([self.fm contentsAtPath:
                           [stylesDir stringByAppendingPathComponent:@"NORMAL.css"]],
                          [@"n" dataUsingEncoding:NSUTF8StringEncoding],
                          @"Sanity check that this sync actually performed "
                          @"real work alongside skipping the FIFO");
}

#pragma mark - Row 11: per-file I/O failure

- (void)testRow11PerFileFailureIsSkippedAndLoopContinues
{
    XCTSkipIf(geteuid() == 0, @"root bypasses mode bits");

    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];
    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/C.css"]];

    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    NSString *bPath = [userRoot stringByAppendingPathComponent:@"Styles/B.css"];
    NSString *cPath = [userRoot stringByAppendingPathComponent:@"Styles/C.css"];
    [self writeString:@"v1" toPath:aPath];
    [self writeString:@"v1" toPath:bPath];
    [self writeString:@"v1" toPath:cPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v1"],
                                  @"Styles/B.css": [self sha256OfString:@"v1"],
                                  @"Styles/C.css": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    NSData *originalBBytes = [self.fm contentsAtPath:bPath];
    NSError *chmodError = nil;
    BOOL chmodOk = [self.fm setAttributes:@{NSFilePosixPermissions: @(0000)}
                              ofItemAtPath:bPath
                                     error:&chmodError];
    XCTAssertTrue(chmodOk, @"Test setup: chmod failed: %@", chmodError);

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    // Restore permissions so tearDown can clean up.
    [self.fm setAttributes:@{NSFilePosixPermissions: @(0644)}
               ofItemAtPath:bPath error:nil];

    XCTAssertNotNil(report);
    XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects([self.fm contentsAtPath:cPath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertNil(report.manifest[@"Styles/B.css"],
                @"A failed file must get no provenance entry");
    XCTAssertEqualObjects([self.fm contentsAtPath:bPath], originalBBytes,
                          @"B.css's original bytes must be unchanged");
    XCTAssertEqual(report.failedCount, 1u);
    XCTAssertEqual(report.refreshedCount, 2u);
}

#pragma mark - Row 12: downgrade

- (void)testRow12DowngradeRevertsPristineFileToOlderBundleBytes
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v0.3-bytes" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"v0.7-bytes" toPath:userPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v0.7-bytes"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self.fm contentsAtPath:userPath],
                          [@"v0.3-bytes" dataUsingEncoding:NSUTF8StringEncoding],
                          @"§6.2: pristine files always track the currently "
                          @"installed bundle, even backwards — this is "
                          @"intended, not a bug");
    XCTAssertEqualObjects(report.manifest[@"Styles/A.css"],
                          [self sha256OfString:@"v0.3-bytes"]);
    XCTAssertEqual(report.refreshedCount, 1u);
}

- (void)testRow12DowngradeDoesNotRevertModifiedFile
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v0.3-bytes" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"MY EDITS" toPath:userPath];
    [self writeProvenanceFiles:@{@"Styles/A.css": [self sha256OfString:@"v0.7-bytes"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self.fm contentsAtPath:userPath],
                          [@"MY EDITS" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertNil(report.manifest[@"Styles/A.css"]);
    XCTAssertEqual(report.modifiedCount, 1u);
}

#pragma mark - §9.2: idempotence (B3)

- (void)testIdempotenceSecondRunPerformsZeroWrites
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Themes/T.style"]];

    // First sync brings the user root to steady state.
    MPBundledResourceSyncReport *report1 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSString *aPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    NSString *tPath = [userRoot stringByAppendingPathComponent:@"Themes/T.style"];
    NSString *manifestPath = [self provenancePathForUserRoot:userRoot];

    // Sanity check: the first sync must actually have reached steady
    // state by doing real work. Without this, "no writes on the second
    // run" is satisfiable by a stub that never writes on ANY run.
    XCTAssertEqualObjects([self.fm contentsAtPath:aPath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding],
                          @"First sync must actually have copied A.css");
    XCTAssertEqualObjects([self.fm contentsAtPath:tPath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding],
                          @"First sync must actually have copied T.style");
    XCTAssertEqual(report1.copiedCount, 2u);
    XCTAssertTrue(report1.manifestWritten);

    NSDate *aMod1 = [self modDateAtPath:aPath];
    NSDate *tMod1 = [self modDateAtPath:tPath];
    unsigned long long aInode1 = [self inodeAtPath:aPath];
    unsigned long long tInode1 = [self inodeAtPath:tPath];
    NSDate *manifestMod1 = [self modDateAtPath:manifestPath];

    MPBundledResourceSyncReport *report2 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self modDateAtPath:aPath], aMod1);
    XCTAssertEqualObjects([self modDateAtPath:tPath], tMod1);
    XCTAssertEqual([self inodeAtPath:aPath], aInode1);
    XCTAssertEqual([self inodeAtPath:tPath], tInode1);
    XCTAssertEqualObjects([self modDateAtPath:manifestPath], manifestMod1,
                          @"Manifest must not be rewritten on the second run");
    XCTAssertFalse(report2.manifestWritten);
    XCTAssertEqual(report2.copiedCount + report2.refreshedCount, 0u);
}

- (void)testIdempotenceWithModifiedFilePresentStillPerformsZeroWrites
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Styles/A.css"];
    [self writeString:@"MY EDITS" toPath:userPath];
    // Companion file, absent from target, that the first sync must
    // actually copy. Without this, "zero writes on the second run" is
    // satisfiable by a stub that never writes on either run.
    [self writeString:@"n" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/NORMAL.css"]];
    [self writeProvenanceFiles:@{} atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report1 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSString *normalPath = [userRoot stringByAppendingPathComponent:@"Styles/NORMAL.css"];
    XCTAssertEqualObjects([self.fm contentsAtPath:normalPath],
                          [@"n" dataUsingEncoding:NSUTF8StringEncoding],
                          @"First sync must actually have copied the "
                          @"companion file");
    XCTAssertEqual(report1.copiedCount, 1u);
    XCTAssertEqual(report1.modifiedCount, 1u);

    NSString *manifestPath = [self provenancePathForUserRoot:userRoot];
    NSDate *manifestMod1 = [self modDateAtPath:manifestPath];
    NSDate *fileMod1 = [self modDateAtPath:userPath];
    NSDate *normalMod1 = [self modDateAtPath:normalPath];

    MPBundledResourceSyncReport *report2 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self modDateAtPath:userPath], fileMod1);
    XCTAssertEqualObjects([self modDateAtPath:normalPath], normalMod1);
    XCTAssertEqualObjects([self modDateAtPath:manifestPath], manifestMod1,
                          @"A permanently modified file must not cause a "
                          @"manifest rewrite on every run (log-spam trap, "
                          @"design §4.2 step 6)");
    XCTAssertFalse(report2.manifestWritten);
    XCTAssertEqual(report2.copiedCount + report2.refreshedCount, 0u);
}

#pragma mark - §9: the summary log gate is silent in the steady state

// The summary NSLog fires when copied + refreshed > 0, orphanedCount > 0, or
// the manifest was rewritten. NSLog output is awkward to capture, so this
// asserts the observable report the gate is computed from: for a user with a
// custom style, every term must be zero/false on the second and every later
// launch.
- (void)testSteadyStateWithUserAuthoredFileLeavesLogGateClosed
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    // The user's own style, present before the very first sync and never
    // shipped by us.
    NSString *minePath = [userRoot stringByAppendingPathComponent:@"Styles/Mine.css"];
    [self writeString:@"mine" toPath:minePath];

    MPBundledResourceSyncReport *report1 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    // Sanity: the first sync must actually have done work, or "quiet
    // afterwards" would be satisfiable by a sync that never does anything.
    XCTAssertEqual(report1.copiedCount, 1u,
                   @"First sync must actually have copied Styles/A.css");
    XCTAssertTrue(report1.manifestWritten);
    XCTAssertEqual(report1.orphanedCount, 0u,
                   @"The user's own file is not an orphan even on the first "
                   @"sync — it never had a provenance entry to drop");

    NSDate *mineMod1 = [self modDateAtPath:minePath];

    MPBundledResourceSyncReport *report2 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqual(report2.copiedCount + report2.refreshedCount, 0u);
    XCTAssertEqual(report2.orphanedCount, 0u,
                   @"A user-authored file must not be counted as an orphan, "
                   @"or the summary log fires on every launch forever (§9)");
    XCTAssertFalse(report2.manifestWritten);
    XCTAssertEqualObjects([self modDateAtPath:minePath], mineMod1,
                          @"The user's own file must still be untouched");
    XCTAssertNil(report2.manifest[@"Styles/Mine.css"]);
}

#pragma mark - §7.4: symlinked directories

- (void)testSymlinkedStylesDirectoryIsNotClobbered
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/PRISTINE.css"]];
    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/MOD.css"]];

    NSString *externalDir = [self.tempDir stringByAppendingPathComponent:@"external-styles"];
    [self.fm createDirectoryAtPath:externalDir withIntermediateDirectories:YES
                         attributes:nil error:nil];
    NSString *pristinePath = [externalDir stringByAppendingPathComponent:@"PRISTINE.css"];
    NSString *modPath = [externalDir stringByAppendingPathComponent:@"MOD.css"];
    [self writeString:@"v1" toPath:pristinePath];
    [self writeString:@"MY EDITS" toPath:modPath];

    [self writeProvenanceFiles:@{@"Styles/PRISTINE.css": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    NSString *stylesLinkPath = [userRoot stringByAppendingPathComponent:@"Styles"];
    NSError *linkError = nil;
    BOOL linked = [self.fm createSymbolicLinkAtPath:stylesLinkPath
                                 withDestinationPath:externalDir
                                               error:&linkError];
    XCTAssertTrue(linked, @"Test setup: %@", linkError);

    MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSDictionary *linkAttrs = [self.fm attributesOfItemAtPath:stylesLinkPath
                                                          error:nil];
    XCTAssertEqualObjects(linkAttrs[NSFileType], NSFileTypeSymbolicLink,
                          @"Styles must remain a symlink — the "
                          @"directory-absent branch must never fire");
    NSString *linkDest = [self.fm destinationOfSymbolicLinkAtPath:stylesLinkPath
                                                              error:nil];
    XCTAssertEqualObjects([linkDest stringByStandardizingPath],
                          [externalDir stringByStandardizingPath]);

    XCTAssertEqualObjects([self.fm contentsAtPath:pristinePath],
                          [@"v2" dataUsingEncoding:NSUTF8StringEncoding],
                          @"The pristine file must be refreshed INSIDE the "
                          @"linked directory");
    XCTAssertEqualObjects([self.fm contentsAtPath:modPath],
                          [@"MY EDITS" dataUsingEncoding:NSUTF8StringEncoding],
                          @"The modified file must survive");
}

- (void)testSymlinkedUserRootIsNotClobbered
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    NSString *realUserDir = [self.tempDir stringByAppendingPathComponent:@"real-user-root"];
    [self.fm createDirectoryAtPath:realUserDir withIntermediateDirectories:YES
                         attributes:nil error:nil];

    NSError *linkError = nil;
    BOOL linked = [self.fm createSymbolicLinkAtPath:userRoot
                                 withDestinationPath:realUserDir
                                               error:&linkError];
    XCTAssertTrue(linked, @"Test setup: %@", linkError);
    XCTAssertTrue([self mp_pathIsUnderTemporaryDirectory:userRoot],
                  @"The symlink path itself must still resolve under "
                  @"NSTemporaryDirectory() — required for this test to be "
                  @"a valid use of the safety factory");

    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];

    MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSDictionary *attrs = [self.fm attributesOfItemAtPath:userRoot error:nil];
    XCTAssertEqualObjects(attrs[NSFileType], NSFileTypeSymbolicLink,
                          @"userRoot symlink must survive");
    NSString *realAPath = [realUserDir stringByAppendingPathComponent:@"Styles/A.css"];
    XCTAssertEqualObjects([self.fm contentsAtPath:realAPath],
                          [@"a" dataUsingEncoding:NSUTF8StringEncoding],
                          @"Files must land through the symlink into the "
                          @"real directory");
}

- (void)testSymlinkInsideLinkedDirectoryIsStillSkipped
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"v2" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    // Companion normal file, absent from target, inside the SAME linked
    // directory. It must be copied by this same sync — without this, an
    // untouched symlink and an empty manifest are both satisfiable by a
    // no-op stub.
    [self writeString:@"n" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/NORMAL.css"]];

    NSString *externalDir = [self.tempDir stringByAppendingPathComponent:@"external-styles-2"];
    [self.fm createDirectoryAtPath:externalDir withIntermediateDirectories:YES
                         attributes:nil error:nil];
    NSString *outsidePath = [self.tempDir stringByAppendingPathComponent:@"outside2.css"];
    [self writeString:@"SECRET" toPath:outsidePath];
    NSString *innerLinkPath = [externalDir stringByAppendingPathComponent:@"A.css"];
    [self.fm createSymbolicLinkAtPath:innerLinkPath
                   withDestinationPath:outsidePath error:nil];

    NSString *stylesLinkPath = [userRoot stringByAppendingPathComponent:@"Styles"];
    [self.fm createSymbolicLinkAtPath:stylesLinkPath
                   withDestinationPath:externalDir error:nil];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSDictionary *innerAttrs = [self.fm attributesOfItemAtPath:innerLinkPath
                                                           error:nil];
    XCTAssertEqualObjects(innerAttrs[NSFileType], NSFileTypeSymbolicLink,
                          @"An entry inside a linked directory that is "
                          @"itself a symlink must still be skipped (row 10)");
    XCTAssertNil(report.manifest[@"Styles/A.css"]);
    XCTAssertEqualObjects([self.fm contentsAtPath:
                           [externalDir stringByAppendingPathComponent:@"NORMAL.css"]],
                          [@"n" dataUsingEncoding:NSUTF8StringEncoding],
                          @"Sanity check that this sync actually performed "
                          @"real work inside the linked directory");
    XCTAssertEqual(report.skippedCount, 1u);
}

#pragma mark - Bundle-side non-regular entries

- (void)testNonRegularBundleEntryIsIgnored
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    NSString *stylesBundleDir = [bundleRoot stringByAppendingPathComponent:@"Styles"];
    [self.fm createDirectoryAtPath:stylesBundleDir withIntermediateDirectories:YES
                         attributes:nil error:nil];
    NSString *outsidePath = [self.tempDir stringByAppendingPathComponent:@"bundle-outside.css"];
    [self writeString:@"x" toPath:outsidePath];
    NSString *bundleLinkPath = [stylesBundleDir stringByAppendingPathComponent:@"LINK.css"];
    [self.fm createSymbolicLinkAtPath:bundleLinkPath
                   withDestinationPath:outsidePath error:nil];
    // Companion regular bundle file, absent from target, that must
    // actually be copied by this same sync — without this, "the symlink
    // was not copied" is trivially satisfiable by a no-op stub.
    [self writeString:@"n" toPath:[stylesBundleDir stringByAppendingPathComponent:@"NORMAL.css"]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertNil(report.manifest[@"Styles/LINK.css"]);
    NSString *targetLinkPath = [userRoot stringByAppendingPathComponent:@"Styles/LINK.css"];
    XCTAssertFalse([self.fm fileExistsAtPath:targetLinkPath],
                   @"A symlink in the bundle must not be copied");
    XCTAssertEqual(report.failedCount, 0u,
                   @"A non-regular bundle entry is ignored, not a failure");
    XCTAssertEqualObjects([self.fm contentsAtPath:
                           [userRoot stringByAppendingPathComponent:@"Styles/NORMAL.css"]],
                          [@"n" dataUsingEncoding:NSUTF8StringEncoding],
                          @"Sanity check that this sync actually performed "
                          @"real work alongside ignoring the bundle symlink");
    XCTAssertEqual(report.copiedCount, 1u);
}

#pragma mark - §9.2: bundle-enumeration guard (R4)

- (void)testBundleEnumerationFailureDoesNotEraseProvenance
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    [self writeString:@"a" toPath:[userRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    NSDictionary *provenanceFiles = @{@"Styles/A.css": [self sha256OfString:@"a"]};
    NSString *manifestPath = [self provenancePathForUserRoot:userRoot];
    [self writeProvenanceFiles:provenanceFiles atPath:manifestPath];
    NSData *manifestBytesBefore = [NSData dataWithContentsOfFile:manifestPath];

    NSString *nonexistentBundleRoot = [self.tempDir
        stringByAppendingPathComponent:@"does-not-exist"];
    XCTAssertTrue([self mp_pathIsUnderTemporaryDirectory:nonexistentBundleRoot]);

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, nonexistentBundleRoot);

    XCTAssertTrue(report.aborted);
    NSData *manifestBytesAfter = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertEqualObjects(manifestBytesAfter, manifestBytesBefore,
                          @"Manifest bytes must be byte-identical after an "
                          @"enumeration failure");
    XCTAssertEqualObjects([self.fm contentsAtPath:
                           [userRoot stringByAppendingPathComponent:@"Styles/A.css"]],
                          [@"a" dataUsingEncoding:NSUTF8StringEncoding],
                          @"No user file may be touched");
}

- (void)testPartialBundleEnumerationFailureDoesNotEraseProvenance
{
    // The test that catches the bug the design review found: an
    // enumeration failure limited to ONE bundle directory (here, Themes/)
    // must still abort the ENTIRE sync without writing a manifest, rather
    // than silently erasing only that directory's provenance.
    XCTSkipIf(geteuid() == 0, @"root bypasses mode bits");

    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    NSString *stylesBundleDir = [bundleRoot stringByAppendingPathComponent:@"Styles"];
    NSString *themesBundleDir = [bundleRoot stringByAppendingPathComponent:@"Themes"];
    [self writeString:@"a" toPath:[stylesBundleDir stringByAppendingPathComponent:@"A.css"]];
    [self.fm createDirectoryAtPath:themesBundleDir withIntermediateDirectories:YES
                         attributes:nil error:nil];
    [self writeString:@"t" toPath:[themesBundleDir stringByAppendingPathComponent:@"T.style"]];

    [self writeString:@"a" toPath:[userRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"t" toPath:[userRoot stringByAppendingPathComponent:@"Themes/T.style"]];

    NSDictionary *provenanceFiles = @{
        @"Styles/A.css": [self sha256OfString:@"a"],
        @"Themes/T.style": [self sha256OfString:@"t"],
    };
    NSString *manifestPath = [self provenancePathForUserRoot:userRoot];
    [self writeProvenanceFiles:provenanceFiles atPath:manifestPath];
    NSData *manifestBytesBefore = [NSData dataWithContentsOfFile:manifestPath];

    // Styles/ stays readable; Themes/ becomes unreadable.
    NSError *chmodError = nil;
    BOOL chmodOk = [self.fm setAttributes:@{NSFilePosixPermissions: @(0000)}
                              ofItemAtPath:themesBundleDir
                                     error:&chmodError];
    XCTAssertTrue(chmodOk, @"Test setup: chmod failed: %@", chmodError);

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    // Restore permissions so tearDown can clean up.
    [self.fm setAttributes:@{NSFilePosixPermissions: @(0755)}
               ofItemAtPath:themesBundleDir error:nil];

    XCTAssertTrue(report.aborted,
                  @"A single unreadable bundle directory must abort the "
                  @"whole sync, per design §4.2 step 2 / design R4");
    NSData *manifestBytesAfter = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertEqualObjects(manifestBytesAfter, manifestBytesBefore,
                          @"Manifest bytes must be byte-identical — "
                          @"including the Styles/ entry, which enumerated "
                          @"successfully — after a partial enumeration "
                          @"failure");
    XCTAssertEqualObjects([self.fm contentsAtPath:
                           [userRoot stringByAppendingPathComponent:@"Styles/A.css"]],
                          [@"a" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects([self.fm contentsAtPath:
                           [userRoot stringByAppendingPathComponent:@"Themes/T.style"]],
                          [@"t" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testEmptyBundleDirectoryIsNotTreatedAsEnumerationFailure
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];

    NSString *stylesBundleDir = [bundleRoot stringByAppendingPathComponent:@"Styles"];
    NSString *themesBundleDir = [bundleRoot stringByAppendingPathComponent:@"Themes"];
    [self writeString:@"a" toPath:[stylesBundleDir stringByAppendingPathComponent:@"A.css"]];
    // Themes/ exists, is readable, and genuinely contains zero files.
    [self.fm createDirectoryAtPath:themesBundleDir withIntermediateDirectories:YES
                         attributes:nil error:nil];

    NSString *themeUserPath = [userRoot stringByAppendingPathComponent:@"Themes/OldTheme.style"];
    [self writeString:@"old" toPath:themeUserPath];
    [self writeProvenanceFiles:@{@"Themes/OldTheme.style": [self sha256OfString:@"old"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertFalse(report.aborted,
                   @"A directory that genuinely enumerates to zero entries "
                   @"is not an enumeration failure and must not abort");
    XCTAssertTrue([self.fm fileExistsAtPath:themeUserPath],
                  @"The now-orphaned theme file must be left on disk");
    XCTAssertNil(report.manifest[@"Themes/OldTheme.style"],
                @"It is orphaned (row 7): dropped from the manifest, not "
                @"deleted from disk");
    XCTAssertEqual(report.orphanedCount, 1u);
}

#pragma mark - §9.2: nil roots

- (void)testNilRootsAreNoOp
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];

    MPBundledResourceSyncReport *bothNil = MPSyncBundledResourcesInPaths(nil, nil);
    XCTAssertNotNil(bothNil);
    XCTAssertTrue(bothNil.aborted);
    XCTAssertEqual(bothNil.manifest.count, 0u);

    MPBundledResourceSyncReport *userNil = MPSyncBundledResourcesInPaths(nil, bundleRoot);
    XCTAssertTrue(userNil.aborted);
    XCTAssertEqual(userNil.manifest.count, 0u);

    MPBundledResourceSyncReport *bundleNil = MPSyncBundledResourcesInPaths(userRoot, nil);
    XCTAssertTrue(bundleNil.aborted);
    XCTAssertEqual(bundleNil.manifest.count, 0u);

    XCTAssertFalse([self.fm fileExistsAtPath:userRoot],
                   @"Nothing must be created when either root is nil");
}

#pragma mark - §9.2: permissions

- (void)testPermissionDeniedOnManifestWriteIsNonFatal
{
    XCTSkipIf(geteuid() == 0, @"root bypasses mode bits");

    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self.fm createDirectoryAtPath:userRoot withIntermediateDirectories:YES
                         attributes:nil error:nil];
    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];
    [self writeString:@"a" toPath:[userRoot stringByAppendingPathComponent:@"Styles/A.css"]];

    // Sync once so the manifest exists, then lock the directory down so a
    // rewrite attempt fails.
    MPBundledResourceSyncReport *report1 =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);
    NSString *manifestPath = [self provenancePathForUserRoot:userRoot];
    // Sanity check: the first, unrestricted sync must actually have
    // written a real manifest — otherwise "manifestWritten == NO" on the
    // second run proves nothing.
    XCTAssertTrue(report1.manifestWritten);
    XCTAssertTrue([self.fm fileExistsAtPath:manifestPath]);
    XCTAssertGreaterThan(report1.manifest.count, 0u);

    // A new bundle file forces a manifest change on the next run.
    [self writeString:@"b" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/B.css"]];

    NSError *chmodError = nil;
    BOOL chmodOk = [self.fm setAttributes:@{NSFilePosixPermissions: @(0500)}
                              ofItemAtPath:userRoot
                                     error:&chmodError];
    XCTAssertTrue(chmodOk, @"Test setup: chmod failed: %@", chmodError);

    MPBundledResourceSyncReport *report = nil;
    XCTAssertNoThrow(report = MPSyncBundledResourcesInPaths(userRoot, bundleRoot));

    [self.fm setAttributes:@{NSFilePosixPermissions: @(0755)}
               ofItemAtPath:userRoot error:nil];

    XCTAssertNotNil(report);
    XCTAssertFalse(report.manifestWritten,
                   @"A permission-denied manifest write must be reported "
                   @"as not-written, not crash the sync");
}

#pragma mark - §7.2: case sensitivity

- (void)testManifestKeysAreCaseSensitive
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    NSString *bundlePath = [bundleRoot stringByAppendingPathComponent:@"Themes/Mou Night.style"];
    [self writeString:@"v2" toPath:bundlePath];
    NSString *userPath = [userRoot stringByAppendingPathComponent:@"Themes/Mou Night.style"];
    [self writeString:@"v1" toPath:userPath];

    // Mis-cased key: lowercase "mou night.style" instead of the bundle's
    // "Mou Night.style".
    [self writeProvenanceFiles:@{@"Themes/mou night.style": [self sha256OfString:@"v1"]}
                         atPath:[self provenancePathForUserRoot:userRoot]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    XCTAssertEqualObjects([self.fm contentsAtPath:userPath],
                          [@"v1" dataUsingEncoding:NSUTF8StringEncoding],
                          @"The mis-cased provenance entry must not match: "
                          @"the file is therefore unclassifiable as "
                          @"pristine and must be left untouched");
    XCTAssertNil(report.manifest[@"Themes/Mou Night.style"]);
    XCTAssertNil(report.manifest[@"Themes/mou night.style"]);
    XCTAssertEqual(report.modifiedCount, 1u);
}

- (void)testManifestKeysUseBundleSpelling
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];

    NSString *name = @"Google Docs.css";
    [self writeString:@"g" toPath:[bundleRoot stringByAppendingPathComponent:
                                    [@"Styles" stringByAppendingPathComponent:name]]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    NSString *expectedKey = [@"Styles" stringByAppendingPathComponent:name];
    XCTAssertEqualObjects(report.manifest[expectedKey], [self sha256OfString:@"g"],
                          @"Manifest key must exactly match the bundle's "
                          @"spelling, including the space, no escaping, no "
                          @"normalisation. Keys present: %@",
                          report.manifest.allKeys);
}

#pragma mark - §9.2: never touches real Application Support

- (void)testSyncNeverTouchesRealApplicationSupport
{
    NSString *userRoot, *bundleRoot;
    [self makeRootsUser:&userRoot bundle:&bundleRoot];
    [self writeString:@"a" toPath:[bundleRoot stringByAppendingPathComponent:@"Styles/A.css"]];

    MPBundledResourceSyncReport *report =
        MPSyncBundledResourcesInPaths(userRoot, bundleRoot);

    // The manifest must be non-trivially populated for this test to prove
    // anything (a stub returning an empty manifest would vacuously pass
    // an empty loop below).
    XCTAssertGreaterThan(report.manifest.count, 0u,
                         @"Sync must actually have synced something for "
                         @"this test to be meaningful");

    NSString *resolvedUserRoot = [[NSURL fileURLWithPath:userRoot]
        URLByResolvingSymlinksInPath].path;
    for (NSString *key in report.manifest) {
        NSString *fullPath = [userRoot stringByAppendingPathComponent:key];
        NSString *resolvedFullPath = [[NSURL fileURLWithPath:fullPath]
            URLByResolvingSymlinksInPath].path;
        XCTAssertTrue([resolvedFullPath hasPrefix:resolvedUserRoot],
                      @"Every written path must resolve under the injected "
                      @"fake user root, never a real one: %@", fullPath);
    }
}

#pragma mark - The real call site's assumption about the app bundle

// Every other test in this file drives MPSyncBundledResourcesInPaths through
// injected fake roots. The one call site that ships does not:
//
//     MPSyncBundledResourcesInPaths(MPDataDirectory(nil),
//                                   [NSBundle mainBundle].resourcePath);
//     — MPMainController.m:274-278
//
// and it depends on Styles/ and Themes/ being readable directories directly
// inside that resource path. If a resource-layout change in project.pbxproj
// ever moved, renamed or nested either of them, MPDirectoryEntryNames would
// find nothing there — a missing directory is not an enumeration failure
// (see MPBundledResourceSync.m) — so the sync would not abort. Instead every
// file already on disk would classify as row 7 (Forget): its provenance
// entry gets dropped and it is never refreshed again, silently, while every
// fake-root test above stayed green. (An unreadable directory, or Styles/
// replaced by a plain file, is the case that does abort.) This test is the
// tripwire for the silent case.
//
// WHY THIS TEST IS EXEMPT FROM makeRootsUser:bundle:. The temp-root safety
// factory is mandatory for anything that calls the sync, because the sync
// writes. This test never calls the sync and never writes anything: it only
// reads the app bundle's own layout. The subject under test IS the real
// bundle, so handing it a temp root would defeat the entire point. Calling
// MPSyncBundledResourcesInPaths with the real roots — which would rewrite a
// developer's actual ~/Library/Application Support themes — is precisely what
// the factory exists to prevent, and this test deliberately does not do it.
// The guard is not being bypassed; there is nothing here for it to guard.
//
// MacDownTests is app-hosted (TEST_HOST = BUNDLE_LOADER = MacDown 3000.app),
// so [NSBundle mainBundle] here is the very bundle -[MPMainController
// copyFiles] sees at launch.
- (void)testAppBundleLaysOutStylesAndThemesWhereTheRealSyncCallLooks
{
    NSString *bundleResourceRoot = [NSBundle mainBundle].resourcePath;
    XCTAssertNotNil(bundleResourceRoot,
                    @"The app-hosted main bundle must have a resource path");

    for (NSString *dirName in @[kMPStylesDirectoryName, kMPThemesDirectoryName])
    {
        NSString *dirPath =
            [bundleResourceRoot stringByAppendingPathComponent:dirName];

        NSError *attributesError = nil;
        NSDictionary *attributes = [self.fm attributesOfItemAtPath:dirPath
                                                             error:&attributesError];
        XCTAssertNotNil(attributes,
                        @"%@/ must exist as a direct child of the bundle's "
                        @"resource path %@: %@",
                        dirName, bundleResourceRoot, attributesError);
        XCTAssertEqualObjects(attributes[NSFileType], NSFileTypeDirectory,
                              @"%@/ must be a real directory, not a file or "
                              @"a link", dirName);

        NSError *enumerationError = nil;
        NSArray<NSString *> *entries =
            [self.fm contentsOfDirectoryAtPath:dirPath error:&enumerationError];
        XCTAssertNotNil(entries,
                        @"%@/ must be readable — an enumeration failure here "
                        @"aborts the entire sync: %@",
                        dirName, enumerationError);

        NSUInteger regularFileCount = 0;
        for (NSString *entry in entries)
        {
            NSString *entryPath = [dirPath stringByAppendingPathComponent:entry];
            NSDictionary *entryAttributes =
                [self.fm attributesOfItemAtPath:entryPath error:NULL];
            if ([entryAttributes[NSFileType] isEqual:NSFileTypeRegular])
                regularFileCount++;
        }
        XCTAssertGreaterThan(regularFileCount, 0u,
                             @"%@/ must ship at least one regular file, or "
                             @"the sync has nothing to copy or refresh",
                             dirName);
    }
}

@end
