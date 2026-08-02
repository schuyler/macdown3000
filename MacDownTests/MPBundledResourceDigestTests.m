//
//  MPBundledResourceDigestTests.m
//  MacDown 3000
//
//  Tests for the pure, non-filesystem-orchestrating half of
//  MPBundledResourceSync: SHA-256 digesting, provenance/history manifest
//  I/O, and the MPBundledResourceActionForFile decision table.
//
//  Written against the design and contract for GitHub issue #548, not
//  against MPBundledResourceSync.m's current (deliberately stubbed) bodies.
//  Related to GitHub issue #548.
//

#import <XCTest/XCTest.h>
#import "MPBundledResourceSync.h"

// Real SHA-256 vectors, computed with `shasum -a 256` / Python's hashlib so
// they are independently verifiable and do not depend on this codebase.
static NSString * const kSHA256EmptyDigest =
    @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
static NSString * const kSHA256AbcDigest =
    @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
// SHA-256 of 65553 bytes (64 KiB + 17) where byte[i] == i % 251, computed
// independently with Python's hashlib. Pins chunk-boundary correctness to a
// known value rather than only cross-checking the file and data code paths
// against each other.
static NSString * const kSHA256ChunkBoundaryDigest =
    @"db321256cd80da245f26f881e6b51650d0c95881f47d47e0e8c51a455b66af34";

// Arbitrary, well-formed (64 lowercase hex char) digests used as opaque
// stand-ins in manifest and truth-table tests, where only equality/
// inequality among them matters, not what they are digests of. Each is a
// real `shasum -a 256` output so nothing here is a "looks like hex" fake.
static NSString * const kHexV1 =
    @"3bfc269594ef649228e9a74bab00f042efc91d5acc6fbee31a382e80d42388fe";
static NSString * const kHexV2 =
    @"fb04dcb6970e4c3d1873de51fd5a50d7bb46b3383113602665c350ec40b5f990";
static NSString * const kHexV3 =
    @"e0d2747b9ab7abb6eb65e0373fa1b428a28bd6d8a2380106dcc080f58005ee14";
static NSString * const kHexBundle =
    @"1e6ed65d77d6364eeaed5a745ba5c4985ae2b700dd85d7cf7f027bdf294a33fc";
static NSString * const kHexProvenance =
    @"96d815328a42cb4ef89d5e0b7a1df6be43b484832c83a7b4596d8402c7c0b12b";
static NSString * const kHexTarget =
    @"34a04005bcaf206eec990bd9637d9fdb6725e0a0c0d4aebf003f17f4c956eb5c";
static NSString * const kHexModified =
    @"b80012851cf027c6d8adda328907d400c95773958fb4fec3e544a02cd5eeab0e";


@interface MPBundledResourceDigestTests : XCTestCase
@property (strong) NSString *tempDir;
@end


@implementation MPBundledResourceDigestTests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Helpers

- (NSString *)pathForName:(NSString *)name
{
    return [self.tempDir stringByAppendingPathComponent:name];
}

#pragma mark - MPSHA256HexOfFileAtPath / MPSHA256HexOfData

- (void)testSHA256HexOfEmptyFileMatchesKnownVector
{
    NSString *name = @"empty.bin";
    NSError *writeError = nil;
    BOOL wrote = [[NSData data] writeToFile:[self pathForName:name]
                                     options:0
                                       error:&writeError];
    XCTAssertTrue(wrote, @"fixture write failed: %@", writeError);

    NSError *error = nil;
    NSString *digest = MPSHA256HexOfFileAtPath([self pathForName:name],
                                                &error);
    XCTAssertNotNil(digest,
                    @"empty file must hash successfully, error: %@", error);
    XCTAssertNil(error, @"no error expected for a readable empty file");
    XCTAssertEqualObjects(digest, kSHA256EmptyDigest,
                          @"empty-file digest must match the well-known "
                          @"SHA-256(\"\") vector");
}

- (void)testSHA256HexOfKnownStringMatchesKnownVector
{
    NSData *abc = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];

    NSString *dataDigest = MPSHA256HexOfData(abc);
    XCTAssertEqualObjects(dataDigest, kSHA256AbcDigest,
                          @"MPSHA256HexOfData(\"abc\") must match the "
                          @"well-known SHA-256(\"abc\") vector");

    // Cross-check the file path against the same known vector, not just
    // against the data path, so this test cannot pass merely because both
    // functions independently return the same (possibly wrong) stub value.
    NSString *name = @"abc.bin";
    NSError *writeError = nil;
    BOOL wrote = [abc writeToFile:[self pathForName:name]
                           options:0
                             error:&writeError];
    XCTAssertTrue(wrote, @"fixture write failed: %@", writeError);

    NSError *error = nil;
    NSString *fileDigest = MPSHA256HexOfFileAtPath([self pathForName:name],
                                                    &error);
    XCTAssertEqualObjects(fileDigest, kSHA256AbcDigest,
                          @"MPSHA256HexOfFileAtPath must also match the "
                          @"well-known SHA-256(\"abc\") vector");
    XCTAssertNil(error, @"no error expected for a readable file");
}

- (void)testSHA256HexIsLowercaseAnd64Characters
{
    NSData *data = [@"regex pin" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *digest = MPSHA256HexOfData(data);
    XCTAssertNotNil(digest, @"a digest is required before regex-checking it");
    XCTAssertEqual(digest.length, (NSUInteger)64,
                   @"digest must be exactly 64 characters, got %lu",
                   (unsigned long)digest.length);

    NSError *regexError = nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{64}$"
                                                    options:0
                                                      error:&regexError];
    XCTAssertNil(regexError, @"regex itself must compile: %@", regexError);

    NSUInteger matchCount =
        [re numberOfMatchesInString:digest
                             options:0
                               range:NSMakeRange(0, digest.length)];
    XCTAssertEqual(matchCount, (NSUInteger)1,
                   @"digest %@ must be lowercase 64-char hex per §7.1",
                   digest);
}

- (void)testSHA256HexCrossesChunkBoundaryCorrectly
{
    // 64 KiB + 17 bytes: one byte past a plausible internal chunk size, so a
    // correct implementation must handle a final, non-full chunk.
    const NSUInteger length = 64 * 1024 + 17;
    NSMutableData *data = [NSMutableData dataWithCapacity:length];
    for (NSUInteger i = 0; i < length; i++)
    {
        uint8_t byte = (uint8_t)(i % 251);
        [data appendBytes:&byte length:1];
    }
    XCTAssertEqual(data.length, length, @"fixture must be exactly 64 KiB+17");

    NSString *name = @"chunk-boundary.bin";
    NSError *writeError = nil;
    BOOL wrote = [data writeToFile:[self pathForName:name]
                            options:0
                              error:&writeError];
    XCTAssertTrue(wrote, @"fixture write failed: %@", writeError);

    NSError *fileError = nil;
    NSString *fileDigest = MPSHA256HexOfFileAtPath([self pathForName:name],
                                                    &fileError);
    NSString *dataDigest = MPSHA256HexOfData(data);

    XCTAssertNotNil(fileDigest,
                    @"file-path digest must not be nil, error: %@",
                    fileError);
    XCTAssertNotNil(dataDigest, @"data-path digest must not be nil");
    XCTAssertEqualObjects(fileDigest, dataDigest,
                          @"chunked file reading must agree with the "
                          @"whole-buffer data path at a chunk boundary");
    XCTAssertEqualObjects(fileDigest, kSHA256ChunkBoundaryDigest,
                          @"digest must match the independently-computed "
                          @"pinned value for this exact 65553-byte fixture");
}

- (void)testSHA256HexReturnsNilAndSetsErrorForMissingFile
{
    NSString *missing = [self pathForName:@"does-not-exist.bin"];
    NSError *error = nil;
    NSString *digest = MPSHA256HexOfFileAtPath(missing, &error);
    XCTAssertNil(digest, @"missing file must not produce a digest");
    XCTAssertNotNil(error,
                    @"missing file must set an error describing the "
                    @"underlying failure, not just return nil silently");
}

- (void)testSHA256HexReturnsNilAndSetsErrorForDirectory
{
    NSString *dirPath = [self pathForName:@"a-directory"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSError *error = nil;
    NSString *digest = MPSHA256HexOfFileAtPath(dirPath, &error);
    XCTAssertNil(digest, @"a directory is not a regular file and must not "
                         @"produce a digest");
    XCTAssertNotNil(error,
                    @"attempting to hash a directory must set an error");
}

- (void)testSHA256HexReturnsNilAndSetsErrorForNilPath
{
    NSError *error = nil;
    NSString *digest = MPSHA256HexOfFileAtPath(nil, &error);
    XCTAssertNil(digest, @"nil path must not produce a digest");
    XCTAssertNotNil(error, @"nil path must set an error");
    XCTAssertEqual(error.code, NSFileNoSuchFileError,
                   @"§2.3's error table pins a nil path specifically to "
                   @"NSFileNoSuchFileError, got %ld", (long)error.code);
}

#pragma mark - Provenance manifest

- (void)testProvenanceManifestRoundTrip
{
    NSDictionary<NSString *, NSString *> *manifest = @{
        @"Styles/A.css": kHexV1,
        @"Themes/B.style": kHexV2,
    };
    NSString *path = [self pathForName:@"roundtrip.json"];

    NSError *writeError = nil;
    BOOL ok = MPWriteProvenanceManifestAtPath(manifest, path, &writeError);
    XCTAssertTrue(ok, @"write must succeed: %@", writeError);
    XCTAssertNil(writeError, @"no error expected on a successful write");

    NSDictionary<NSString *, NSString *> *readBack =
        MPReadProvenanceManifestAtPath(path);
    XCTAssertEqualObjects(readBack, manifest,
                          @"round-tripped manifest must equal the original");
}

- (void)testProvenanceManifestDataIsDeterministicSortedAndNewlineTerminated
{
    NSDictionary<NSString *, NSString *> *manifest = @{
        @"Styles/Zebra.css": kHexV1,
        @"Styles/Alpha.css": kHexV2,
        @"Themes/Middle.style": kHexV3,
    };

    NSData *first = MPProvenanceManifestData(manifest);
    NSData *second = MPProvenanceManifestData(manifest);
    XCTAssertNotNil(first, @"serialisation must succeed for a valid dict");
    XCTAssertEqualObjects(first, second,
                          @"the same dictionary must always serialise to "
                          @"byte-identical data (B3 depends on this)");

    NSString *text = [[NSString alloc] initWithData:first
                                            encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(text, @"serialised bytes must be valid UTF-8");
    XCTAssertTrue([text hasSuffix:@"\n"],
                  @"canonical bytes must end with a trailing newline");

    NSRange alphaRange = [text rangeOfString:@"Styles/Alpha.css"];
    NSRange zebraRange = [text rangeOfString:@"Styles/Zebra.css"];
    NSRange themesRange = [text rangeOfString:@"Themes/Middle.style"];
    XCTAssertNotEqual(alphaRange.location, (NSUInteger)NSNotFound);
    XCTAssertNotEqual(zebraRange.location, (NSUInteger)NSNotFound);
    XCTAssertNotEqual(themesRange.location, (NSUInteger)NSNotFound);
    XCTAssertLessThan(alphaRange.location, zebraRange.location,
                      @"keys must appear in sorted order: Alpha before "
                      @"Zebra");
    XCTAssertLessThan(zebraRange.location, themesRange.location,
                      @"keys must appear in sorted order: Styles/* before "
                      @"Themes/*");
}

- (void)testProvenanceManifestReadReturnsEmptyForMissingFile
{
    // Positive control in the same test: prove the reader can return a
    // populated dictionary at all, so the empty result below cannot be
    // explained by a stub that always returns @{} regardless of input.
    NSString *validPath = [self pathForName:@"valid-control.json"];
    NSString *validJSON =
        [NSString stringWithFormat:@"{\"version\":1,\"files\":"
                                    @"{\"Styles/A.css\":\"%@\"}}", kHexV1];
    NSError *writeError = nil;
    [validJSON writeToFile:validPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:&writeError];
    XCTAssertNil(writeError, @"control fixture write failed: %@",
                writeError);
    NSDictionary *control = MPReadProvenanceManifestAtPath(validPath);
    XCTAssertEqual(control.count, (NSUInteger)1,
                   @"positive control: a well-formed manifest must read "
                   @"back non-empty, proving the reader is not hardcoded "
                   @"to always return @{}");

    NSString *missingPath = [self pathForName:@"does-not-exist.json"];
    NSDictionary *result = MPReadProvenanceManifestAtPath(missingPath);
    XCTAssertNotNil(result, @"must never return nil");
    XCTAssertEqual(result.count, (NSUInteger)0,
                   @"a missing manifest file must degrade to an empty "
                   @"dictionary");
}

- (void)testProvenanceManifestReadReturnsEmptyForCorruptJSON
{
    NSString *validPath = [self pathForName:@"valid-control.json"];
    NSString *validJSON =
        [NSString stringWithFormat:@"{\"version\":1,\"files\":"
                                    @"{\"Styles/A.css\":\"%@\"}}", kHexV1];
    [validJSON writeToFile:validPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
    NSDictionary *control = MPReadProvenanceManifestAtPath(validPath);
    XCTAssertEqual(control.count, (NSUInteger)1,
                   @"positive control must read back non-empty");

    NSString *corruptPath = [self pathForName:@"corrupt.json"];
    // Deliberately truncated JSON.
    [@"{\"version\":1,\"files\":" writeToFile:corruptPath
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:nil];
    NSDictionary *result = MPReadProvenanceManifestAtPath(corruptPath);
    XCTAssertNotNil(result, @"must never return nil");
    XCTAssertEqual(result.count, (NSUInteger)0,
                   @"invalid/truncated JSON must degrade to an empty "
                   @"dictionary, not raise or return nil");
}

- (void)testProvenanceManifestReadReturnsEmptyForWrongShape
{
    NSString *validPath = [self pathForName:@"valid-control.json"];
    NSString *validJSON =
        [NSString stringWithFormat:@"{\"version\":1,\"files\":"
                                    @"{\"Styles/A.css\":\"%@\"}}", kHexV1];
    [validJSON writeToFile:validPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
    NSDictionary *control = MPReadProvenanceManifestAtPath(validPath);
    XCTAssertEqual(control.count, (NSUInteger)1,
                   @"positive control must read back non-empty");

    NSString *wrongShapePath = [self pathForName:@"wrong-shape.json"];
    // Valid JSON, but the top level is an array, not the expected object.
    [@"[1,2,3]" writeToFile:wrongShapePath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
    NSDictionary *result = MPReadProvenanceManifestAtPath(wrongShapePath);
    XCTAssertNotNil(result, @"must never return nil");
    XCTAssertEqual(result.count, (NSUInteger)0,
                   @"a JSON value of the wrong shape must degrade to an "
                   @"empty dictionary");
}

- (void)testProvenanceManifestReadReturnsEmptyForUnknownVersion
{
    NSString *validPath = [self pathForName:@"valid-control.json"];
    NSString *validJSON =
        [NSString stringWithFormat:@"{\"version\":1,\"files\":"
                                    @"{\"Styles/A.css\":\"%@\"}}", kHexV1];
    [validJSON writeToFile:validPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
    NSDictionary *control = MPReadProvenanceManifestAtPath(validPath);
    XCTAssertEqual(control.count, (NSUInteger)1,
                   @"positive control must read back non-empty");

    NSString *unknownVersionPath =
        [self pathForName:@"unknown-version.json"];
    NSString *unknownVersionJSON =
        [NSString stringWithFormat:@"{\"version\":99,\"files\":"
                                    @"{\"Styles/A.css\":\"%@\"}}", kHexV1];
    [unknownVersionJSON writeToFile:unknownVersionPath
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:nil];
    NSDictionary *result =
        MPReadProvenanceManifestAtPath(unknownVersionPath);
    XCTAssertNotNil(result, @"must never return nil");
    XCTAssertEqual(result.count, (NSUInteger)0,
                   @"an otherwise well-formed manifest with an "
                   @"unrecognised schema version must degrade to empty "
                   @"(rows 8 and 9 are the same code path)");
}

- (void)testProvenanceManifestReadDropsNonStringAndMalformedDigests
{
    NSString *path = [self pathForName:@"mixed.json"];
    NSString *json =
        [NSString stringWithFormat:
            @"{\"version\":1,\"files\":{"
            @"\"Styles/A.css\":42,"
            @"\"Styles/B.css\":\"NOTHEX\","
            @"\"Styles/C.css\":\"%@\"}}", kHexV1];
    [json writeToFile:path
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];

    NSDictionary<NSString *, NSString *> *result =
        MPReadProvenanceManifestAtPath(path);
    XCTAssertEqual(result.count, (NSUInteger)1,
                   @"only the valid entry must survive, got keys: %@",
                   result.allKeys);
    XCTAssertNil(result[@"Styles/A.css"],
                @"a non-string digest value must be dropped");
    XCTAssertNil(result[@"Styles/B.css"],
                @"a string that is not 64 lowercase hex chars must be "
                @"dropped");
    XCTAssertEqualObjects(result[@"Styles/C.css"], kHexV1,
                          @"the one well-formed entry must survive intact");
}

#pragma mark - History manifest

- (void)testHistoryManifestReadParsesArraysIntoSets
{
    NSString *path = [self pathForName:@"history.json"];
    NSString *json =
        [NSString stringWithFormat:
            @"{\"version\":1,\"tags\":[\"v1\"],\"files\":{"
            @"\"Styles/A.css\":[\"%@\",\"%@\"]}}", kHexV1, kHexV2];
    [json writeToFile:path
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];

    NSDictionary<NSString *, NSSet<NSString *> *> *result =
        MPReadHistoryManifestAtPath(path);
    NSSet<NSString *> *entry = result[@"Styles/A.css"];
    XCTAssertNotNil(entry, @"key must be present");
    XCTAssertTrue([entry isKindOfClass:[NSSet class]],
                  @"digest arrays must be converted to NSSet, got %@",
                  NSStringFromClass([entry class]));
    XCTAssertEqualObjects(entry, ([NSSet setWithObjects:kHexV1, kHexV2, nil]),
                          @"set must contain exactly the array's digests");
}

- (void)testHistoryManifestReadReturnsEmptyForMissingFile
{
    // Positive control, for the same reason as the provenance-manifest
    // equivalent: an always-@{} reader must not be indistinguishable from
    // a correct one here.
    NSString *validPath = [self pathForName:@"history-control.json"];
    NSString *validJSON =
        [NSString stringWithFormat:
            @"{\"version\":1,\"tags\":[],\"files\":{"
            @"\"Styles/A.css\":[\"%@\"]}}", kHexV1];
    [validJSON writeToFile:validPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
    NSDictionary *control = MPReadHistoryManifestAtPath(validPath);
    XCTAssertEqual(control.count, (NSUInteger)1,
                   @"positive control: a well-formed history manifest must "
                   @"read back non-empty");

    NSString *missingPath = [self pathForName:@"no-history.json"];
    NSDictionary *result = MPReadHistoryManifestAtPath(missingPath);
    XCTAssertNotNil(result, @"must never return nil");
    XCTAssertEqual(result.count, (NSUInteger)0,
                   @"a missing history manifest must degrade to an empty "
                   @"dictionary");
}

- (void)testHistoryManifestReadIgnoresNonStringMembers
{
    NSString *path = [self pathForName:@"mixed-history.json"];
    NSString *json =
        [NSString stringWithFormat:
            @"{\"version\":1,\"tags\":[],\"files\":{"
            @"\"Styles/A.css\":[\"%@\",42,\"NOTHEX\",\"%@\"]}}",
            kHexV1, kHexV2];
    [json writeToFile:path
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];

    NSDictionary<NSString *, NSSet<NSString *> *> *result =
        MPReadHistoryManifestAtPath(path);
    NSSet<NSString *> *entry = result[@"Styles/A.css"];
    XCTAssertEqualObjects(entry, ([NSSet setWithObjects:kHexV1, kHexV2, nil]),
                          @"non-string (42) and malformed (\"NOTHEX\") "
                          @"members must be dropped, valid ones kept, got "
                          @"%@", entry);
}

- (void)testHistoryManifestReadHandlesTheShippedFileShape
{
    // The §3.2 example, verbatim.
    NSString *json =
        @"{\n"
        @"  \"version\": 1,\n"
        @"  \"tags\": [\n"
        @"    \"v3000.0.0-beta.0\", \"v3000.0.0-beta.1\", "
        @"\"v3000.0.0-beta.2\",\n"
        @"    \"v3000.0.0-beta.3\", \"v3000.0.0\", \"v3000.0.1\", "
        @"\"v3000.0.2\",\n"
        @"    \"v3000.0.3-beta.1\", \"v3000.0.3\", \"v3000.0.4\", "
        @"\"v3000.0.5\",\n"
        @"    \"v3000.0.6\", \"v3000.0.7-rc.1\", \"v3000.0.7-rc.2\", "
        @"\"v3000.0.7-rc.3\",\n"
        @"    \"v3000.0.7\"\n"
        @"  ],\n"
        @"  \"files\": {\n"
        @"    \"Styles/GitHub.css\": [\n"
        @"      \"50b145c3b6ae27c8c1f0d2907f83eeade0feabbf082ed9827fd423f"
        @"a02086328\",\n"
        @"      \"673ad0add6f2ad0283f152bd0c4806fce92ac095a8c69331d71a6f"
        @"b4835140a1\"\n"
        @"    ],\n"
        @"    \"Styles/GitHub2.css\": [\n"
        @"      \"62ed816fefa18599c6b8dd0b3d81143459e799e335f77b81ddc165"
        @"0178ddcefd\",\n"
        @"      \"d526e3d22730267ba919c1af92c9ed826ccd8b681f516add89de9c"
        @"e912a79938\"\n"
        @"    ],\n"
        @"    \"Themes/Mou Night+.style\": [\n"
        @"      \"29ac097ec816c3f6c315ede0b0aba97ee0175ff9f83d65e18bb05a"
        @"2906b5650e\",\n"
        @"      \"39872c51d2972803efe27d7ea3114ce91c8718a07a3662c95b6a0b"
        @"a65bed3f95\"\n"
        @"    ]\n"
        @"  }\n"
        @"}\n";
    NSString *path = [self pathForName:@"shipped-history.json"];
    NSError *writeError = nil;
    BOOL wrote = [json writeToFile:path
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&writeError];
    XCTAssertTrue(wrote, @"fixture write failed: %@", writeError);

    NSDictionary<NSString *, NSSet<NSString *> *> *result =
        MPReadHistoryManifestAtPath(path);
    XCTAssertEqual(result.count, (NSUInteger)3,
                   @"exactly the three files in the §3.2 example, got "
                   @"keys: %@", result.allKeys);
    XCTAssertEqualObjects(result[@"Styles/GitHub.css"],
        ([NSSet setWithObjects:
            @"50b145c3b6ae27c8c1f0d2907f83eeade0feabbf082ed9827fd423f"
            @"a02086328",
            @"673ad0add6f2ad0283f152bd0c4806fce92ac095a8c69331d71a6f"
            @"b4835140a1",
            nil]));
    XCTAssertEqualObjects(result[@"Styles/GitHub2.css"],
        ([NSSet setWithObjects:
            @"62ed816fefa18599c6b8dd0b3d81143459e799e335f77b81ddc165"
            @"0178ddcefd",
            @"d526e3d22730267ba919c1af92c9ed826ccd8b681f516add89de9c"
            @"e912a79938",
            nil]));
    XCTAssertEqualObjects(result[@"Themes/Mou Night+.style"],
        ([NSSet setWithObjects:
            @"29ac097ec816c3f6c315ede0b0aba97ee0175ff9f83d65e18bb05a"
            @"2906b5650e",
            @"39872c51d2972803efe27d7ea3114ce91c8718a07a3662c95b6a0b"
            @"a65bed3f95",
            nil]));
}

#pragma mark - MPBundledResourceActionForFile truth table

- (void)testActionSkipsNonRegularTargetEvenWhenBundleDigestMissing
{
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetNonRegular, nil, nil, kHexProvenance, nil);
    XCTAssertEqual(result, MPBundledResourceActionSkip,
                   @"row 10 must win even when bundleDigest is nil (row 7 "
                   @"must not fire first)");

    // Discriminating pair: flip only targetState away from NonRegular,
    // keeping bundleDigest nil. This must now Forget (row 7), proving the
    // Skip above tracked targetState rather than being a constant answer.
    MPBundledResourceAction result2 = MPBundledResourceActionForFile(
        MPBundledResourceTargetAbsent, nil, nil, kHexProvenance, nil);
    XCTAssertEqual(result2, MPBundledResourceActionForget,
                   @"with bundleDigest nil and targetState no longer "
                   @"NonRegular, row 7 must fire");
}

- (void)testActionForgetsWhenBundleDigestIsNil
{
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexTarget, nil, kHexProvenance,
        nil);
    XCTAssertEqual(result, MPBundledResourceActionForget,
                   @"row 7: no longer shipped in the bundle, must Forget "
                   @"the entry without touching the file");
}

- (void)testActionCopiesWhenTargetAbsent
{
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetAbsent, nil, kHexBundle, nil, nil);
    XCTAssertEqual(result, MPBundledResourceActionCopy,
                   @"rows 1/2/6: file shipped, absent on disk, must Copy");
}

- (void)testActionRefreshesWhenMatchesProvenanceButNotBundle
{
    // targetDigest matches provenance (so it's pristine) but not the
    // current bundle contents (rows 3/12).
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexV1, kHexV2, kHexV1, nil);
    XCTAssertEqual(result, MPBundledResourceActionRefresh,
                   @"pristine (matches provenance) and differing from "
                   @"bundle must Refresh");
}

- (void)testActionRecordsOnlyWhenEqualsBundle
{
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexBundle, kHexBundle, nil, nil);
    XCTAssertEqual(result, MPBundledResourceActionRecordOnly,
                   @"row 4: already byte-equal to the bundle, must "
                   @"RecordOnly (no file write, backfill provenance)");
}

- (void)testActionSkipsWhenMatchesNothing
{
    NSSet<NSString *> *history = [NSSet setWithObject:kHexV1];
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexModified, kHexV2, kHexV1,
        history);
    XCTAssertEqual(result, MPBundledResourceActionSkip,
                   @"row 5: matches provenance, bundle, nor history — must "
                   @"be left alone as modified");

    // Discriminating pair: add the exact targetDigest to history so it
    // becomes pristine. Result must change to Refresh (differs from
    // bundle), proving the Skip above depended on the actual inputs rather
    // than being a constant answer.
    NSSet<NSString *> *historyWithMatch =
        [NSSet setWithObjects:kHexV1, kHexModified, nil];
    MPBundledResourceAction result2 = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexModified, kHexV2, kHexV1,
        historyWithMatch);
    XCTAssertEqual(result2, MPBundledResourceActionRefresh,
                   @"once targetDigest is in history it becomes pristine; "
                   @"differing from bundle must Refresh");
}

- (void)testActionTreatsHistoryMatchAsPristine
{
    // No provenance entry at all (rows 8/9 territory); the file's digest
    // is found in shipped history instead, and differs from the current
    // bundle, so it must be classified pristine-but-stale and refreshed.
    NSSet<NSString *> *history = [NSSet setWithObject:kHexV1];
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexV1, kHexV2, nil, history);
    XCTAssertEqual(result, MPBundledResourceActionRefresh,
                   @"row 8: history match without a provenance entry must "
                   @"still be treated as pristine and refreshed to current "
                   @"bundle bytes");
}

- (void)testActionTreatsBundleMatchAsPristineWithoutProvenance
{
    // No provenance entry, but the on-disk bytes already equal the
    // bundle's, which by itself is sufficient to classify pristine.
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexBundle, kHexBundle, nil,
        [NSSet setWithObject:kHexV3]);
    XCTAssertEqual(result, MPBundledResourceActionRecordOnly,
                   @"row 8: no provenance entry, but target already equals "
                   @"bundle bytes, must RecordOnly — provenance is "
                   @"unnecessary when the bundle match alone proves "
                   @"pristine-ness");
}

- (void)testActionTreatsNilHistoryAsEmpty
{
    MPBundledResourceAction withNilHistory = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexBundle, kHexBundle, nil, nil);
    MPBundledResourceAction withEmptyHistory = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexBundle, kHexBundle, nil,
        [NSSet set]);
    XCTAssertEqual(withNilHistory, withEmptyHistory,
                   @"nil historyDigests must behave identically to an "
                   @"empty NSSet");
    XCTAssertEqual(withNilHistory, MPBundledResourceActionRecordOnly,
                   @"sanity check on the shared result: bundle match with "
                   @"no history must still RecordOnly");
}

- (void)testActionRejectsUppercaseHexDigestMatch
{
    NSString *upperProvenance = [kHexV1 uppercaseString];
    MPBundledResourceAction caseMismatch = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexV1, kHexV2, upperProvenance,
        nil);
    XCTAssertEqual(caseMismatch, MPBundledResourceActionSkip,
                   @"§7.1: an uppercase-hex provenanceDigest must NOT "
                   @"case-insensitively match a lowercase targetDigest — "
                   @"comparison must be exact string equality");

    // Discriminating pair: the exact same digest, same case, must match.
    MPBundledResourceAction caseMatch = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexV1, kHexV2, kHexV1, nil);
    XCTAssertEqual(caseMatch, MPBundledResourceActionRefresh,
                   @"the same digest in matching (lowercase) case must be "
                   @"treated as pristine, proving the Skip above was "
                   @"caused specifically by the case mismatch");
}

- (void)testActionSkipsRegularTargetWithNilDigest
{
    // Defensive totality guard: targetState == Regular with a nil
    // targetDigest is unreachable from the real orchestration, but the
    // function is specified as total and must answer safely (Skip) here.
    MPBundledResourceAction result = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, nil, kHexBundle, nil, nil);
    XCTAssertEqual(result, MPBundledResourceActionSkip,
                   @"an unclassifiable Regular target with a nil digest "
                   @"must be defensively skipped before any other check");

    // Discriminating pair: identical inputs except targetDigest is now
    // supplied (and equals bundleDigest). Result must flip away from Skip,
    // proving the guard is keyed on targetDigest == nil specifically.
    MPBundledResourceAction withDigest = MPBundledResourceActionForFile(
        MPBundledResourceTargetRegular, kHexBundle, kHexBundle, nil, nil);
    XCTAssertEqual(withDigest, MPBundledResourceActionRecordOnly,
                   @"supplying targetDigest must flip the result away from "
                   @"Skip");
}

@end
