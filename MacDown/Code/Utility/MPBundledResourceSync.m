//
//  MPBundledResourceSync.m
//  MacDown 3000
//
//  Keeps the bundled Styles and Themes in the user's Application Support
//  directory up to date with the installed app, without ever overwriting a
//  file the user has edited.
//  Related to GitHub issue #548.
//

#import "MPBundledResourceSync.h"

#import <CommonCrypto/CommonDigest.h>
#import <errno.h>
#import <fcntl.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <unistd.h>

#import "MPUtilities.h"

NSString * const kMPBundledResourceManifestFileName =
    @"BundledResourceManifest.json";
NSString * const kMPBundledResourceHistoryFileName =
    @"BundledResourceHistory.json";

/// Schema version understood by both manifest readers. Anything else reads
/// as corrupt and degrades to decision-table row 9, which is safe by design.
static const NSInteger kMPBundledResourceManifestVersion = 1;

/// Bytes hashed per read(2). Fixed and bounded: a user who drops a very
/// large file into Styles/ under a bundled name must not cost us a
/// launch-time allocation spike (design §6 R2).
static const size_t kMPDigestChunkSize = 64 * 1024;

static NSString *MPHexStringOfDigest(const unsigned char *digest);
static BOOL MPDigestStringIsWellFormed(id digest);
static NSError *MPPOSIXError(int code, NSString *path);
static NSError *MPCocoaFileError(NSInteger code, NSString *path,
                                 NSString *description);
static NSDictionary *MPManifestFilesObjectAtPath(NSString *path,
                                                 NSString *label);
static MPBundledResourceTargetState MPTargetStateOfPath(NSString *path);
static BOOL MPPathIsRegularFile(NSString *path);
static NSArray<NSString *> *MPDirectoryEntryNames(NSString *directoryPath,
                                                  BOOL *failed);
static NSSet<NSString *> *MPBundleFileNamesInDirectory(
    NSString *directoryPath, BOOL *failed);
static BOOL MPRefreshFileAtPath(NSString *targetPath, NSString *bundlePath,
                                NSError *__autoreleasing *error);


#pragma mark - MPBundledResourceSyncReport

@interface MPBundledResourceSyncReport ()
@property (readwrite) NSUInteger copiedCount;
@property (readwrite) NSUInteger refreshedCount;
@property (readwrite) NSUInteger unchangedCount;
@property (readwrite) NSUInteger modifiedCount;
@property (readwrite) NSUInteger skippedCount;
@property (readwrite) NSUInteger orphanedCount;
@property (readwrite) NSUInteger failedCount;
@property (readwrite) BOOL manifestWritten;
@property (readwrite) BOOL aborted;
@property (readwrite, copy) NSDictionary<NSString *, NSString *> *manifest;
@end

@implementation MPBundledResourceSyncReport

- (instancetype)init
{
    self = [super init];
    if (self)
        _manifest = @{};
    return self;
}

@end


#pragma mark - Digests

NSString *MPSHA256HexOfFileAtPath(NSString *path,
                                  NSError *__autoreleasing *error)
{
    if (error)
        *error = nil;

    if (!path)
    {
        if (error)
            *error = MPCocoaFileError(NSFileNoSuchFileError, nil,
                                      @"No file path was given.");
        return nil;
    }

    // §7.4: attributesOfItemAtPath: does not traverse a terminal symbolic
    // link, so this rejects a symlink, directory, FIFO, socket or device
    // node before anything is opened.
    NSError *attributesError = nil;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes =
        [manager attributesOfItemAtPath:path error:&attributesError];
    if (!attributes)
    {
        if (error)
            *error = attributesError;
        return nil;
    }
    if (![attributes.fileType isEqualToString:NSFileTypeRegular])
    {
        if (error)
            *error = MPCocoaFileError(NSFileReadUnknownError, path,
                                      @"Not a regular file.");
        return nil;
    }

    // O_NONBLOCK closes the window in which the entry could have become a
    // FIFO between the check above and this open(2): opening a FIFO with no
    // writer would otherwise block the launch (design §6 R2, row 10).
    int descriptor = open(path.fileSystemRepresentation,
                          O_RDONLY | O_NONBLOCK);
    if (descriptor < 0)
    {
        if (error)
            *error = MPPOSIXError(errno, path);
        return nil;
    }

    struct stat status;
    if (fstat(descriptor, &status) != 0)
    {
        int failure = errno;
        close(descriptor);
        if (error)
            *error = MPPOSIXError(failure, path);
        return nil;
    }
    if (!S_ISREG(status.st_mode))
    {
        close(descriptor);
        if (error)
            *error = MPCocoaFileError(NSFileReadUnknownError, path,
                                      @"Not a regular file.");
        return nil;
    }

    void *buffer = malloc(kMPDigestChunkSize);
    if (!buffer)
    {
        close(descriptor);
        if (error)
            *error = MPPOSIXError(ENOMEM, path);
        return nil;
    }

    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);

    int readFailure = 0;
    while (YES)
    {
        ssize_t bytesRead = read(descriptor, buffer, kMPDigestChunkSize);
        if (bytesRead > 0)
        {
            CC_SHA256_Update(&context, buffer, (CC_LONG)bytesRead);
            continue;
        }
        if (bytesRead == 0)
            break;
        if (errno == EINTR)
            continue;
        readFailure = errno;
        break;
    }

    free(buffer);
    close(descriptor);

    if (readFailure != 0)
    {
        if (error)
            *error = MPPOSIXError(readFailure, path);
        return nil;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return MPHexStringOfDigest(digest);
}

NSString *MPSHA256HexOfData(NSData *data)
{
    if (!data)
        return nil;

    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);

    // The block captures a pointer to the stack context, not a copy of it.
    CC_SHA256_CTX *contextRef = &context;
    [data enumerateByteRangesUsingBlock:
        ^(const void *bytes, NSRange range, BOOL *stop) {
            NSUInteger offset = 0;
            while (offset < range.length)
            {
                NSUInteger remaining = range.length - offset;
                if (remaining > (NSUInteger)UINT32_MAX)
                    remaining = (NSUInteger)UINT32_MAX;
                CC_SHA256_Update(contextRef, (const uint8_t *)bytes + offset,
                                 (CC_LONG)remaining);
                offset += remaining;
            }
        }];

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return MPHexStringOfDigest(digest);
}


#pragma mark - Manifests

NSDictionary<NSString *, NSString *> *
MPReadProvenanceManifestAtPath(NSString *path)
{
    NSDictionary *files = MPManifestFilesObjectAtPath(path, @"provenance");
    if (!files)
        return @{};

    NSMutableDictionary<NSString *, NSString *> *manifest =
        [NSMutableDictionary dictionaryWithCapacity:files.count];
    for (id key in files)
    {
        if (![key isKindOfClass:[NSString class]])
            continue;
        id digest = files[key];
        // Non-string and malformed values are dropped individually rather
        // than failing the whole file (§2.3).
        if (!MPDigestStringIsWellFormed(digest))
            continue;
        manifest[key] = digest;
    }
    return [manifest copy];
}

BOOL MPWriteProvenanceManifestAtPath(
    NSDictionary<NSString *, NSString *> *manifest,
    NSString *path, NSError *__autoreleasing *error)
{
    if (error)
        *error = nil;

    if (!path)
    {
        if (error)
            *error = MPCocoaFileError(NSFileNoSuchFileError, nil,
                                      @"No manifest path was given.");
        return NO;
    }

    NSData *data = MPProvenanceManifestData(manifest);
    if (!data)
    {
        if (error)
            *error = MPCocoaFileError(NSFileWriteUnknownError, path,
                                      @"Manifest could not be serialised.");
        return NO;
    }

    // §7.3: atomic, and deliberately unlocked. NSDataWritingAtomic writes a
    // temporary file in the same directory and renames it, so a concurrent
    // reader never observes a partial manifest.
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

NSData *MPProvenanceManifestData(NSDictionary<NSString *, NSString *> *manifest)
{
    NSDictionary *document = @{
        @"version": @(kMPBundledResourceManifestVersion),
        @"files": manifest ?: @{},
    };
    if (![NSJSONSerialization isValidJSONObject:document])
    {
        NSLog(@"[MPBundledResourceSync] manifest is not serialisable as "
              @"JSON; refusing to write it");
        return nil;
    }

    NSError *error = nil;
    // Sorted keys make the file diffable and make the B3 byte-comparison
    // in MPSyncBundledResourcesInPaths meaningful.
    //
    // WithoutEscapingSlashes is load-bearing, not cosmetic. With
    // PrettyPrinted alone, NSJSONSerialization emits "Styles\/GitHub.css",
    // and every key in this file carries a '/' separator per §7.2 — so the
    // on-disk manifest would match neither design §3.1's rendering of it
    // nor its sibling BundledResourceHistory.json, which the Python
    // generator writes with unescaped slashes.
    //
    // Available unconditionally here: the flag is macOS 10.15+ and the
    // deployment target is macOS 11.0.
    NSJSONWritingOptions options = NSJSONWritingSortedKeys
        | NSJSONWritingPrettyPrinted | NSJSONWritingWithoutEscapingSlashes;
    NSData *json = [NSJSONSerialization dataWithJSONObject:document
                                                   options:options
                                                     error:&error];
    if (!json)
    {
        NSLog(@"[MPBundledResourceSync] could not serialise manifest: %@",
              error);
        return nil;
    }

    NSMutableData *data = [json mutableCopy];
    [data appendBytes:"\n" length:1];
    return [data copy];
}

NSDictionary<NSString *, NSSet<NSString *> *> *
MPReadHistoryManifestAtPath(NSString *path)
{
    NSDictionary *files = MPManifestFilesObjectAtPath(path, @"history");
    if (!files)
        return @{};

    NSMutableDictionary<NSString *, NSSet<NSString *> *> *history =
        [NSMutableDictionary dictionaryWithCapacity:files.count];
    for (id key in files)
    {
        if (![key isKindOfClass:[NSString class]])
            continue;
        id digests = files[key];
        if (![digests isKindOfClass:[NSArray class]])
            continue;

        NSMutableSet<NSString *> *set = [NSMutableSet set];
        for (id digest in (NSArray *)digests)
        {
            if (MPDigestStringIsWellFormed(digest))
                [set addObject:digest];
        }
        history[key] = [set copy];
    }
    return [history copy];
}

NSString *MPProvenanceManifestPathInRoot(NSString *userDataRoot)
{
    return [userDataRoot
        stringByAppendingPathComponent:kMPBundledResourceManifestFileName];
}

NSString *MPHistoryManifestPathInRoot(NSString *bundleResourceRoot)
{
    return [bundleResourceRoot
        stringByAppendingPathComponent:kMPBundledResourceHistoryFileName];
}


#pragma mark - Classification

MPBundledResourceAction MPBundledResourceActionForFile(
    MPBundledResourceTargetState targetState,
    NSString *targetDigest,
    NSString *bundleDigest,
    NSString *provenanceDigest,
    NSSet<NSString *> *historyDigests)
{
    // Row 10 — target exists but is not a regular file (symlink, directory,
    // FIFO, socket, device node). Skip entirely: never open, follow, hash,
    // replace, or record provenance. Checked first: it is the strongest
    // prohibition and must win over every other row.
    if (targetState == MPBundledResourceTargetNonRegular)
        return MPBundledResourceActionSkip;

    // Row 7 — present in the target directory, removed from the bundle.
    // Never delete; the user may have it selected. Drop the entry (§7.5).
    if (!bundleDigest)
        return MPBundledResourceActionForget;

    // Rows 2 and 6 — absent from the target directory. Row 1 reaches here
    // too, once per file, after the directories have been created.
    if (targetState == MPBundledResourceTargetAbsent)
        return MPBundledResourceActionCopy;

    // Defensive: targetState == Regular with targetDigest == nil is
    // unreachable from MPSyncBundledResourcesInPaths (a failed hash is
    // short-circuited into the row-11 path before this function is ever
    // called), but the function is specified as total, so it must have a
    // defined answer for this combination in isolation. Treat it as
    // unclassifiable and leave the file alone, which is the safe direction.
    if (!targetDigest)
        return MPBundledResourceActionSkip;

    // §4.3 classification. Rows 8 and 9 arrive here with provenanceDigest
    // nil and are handled by exactly this expression — there is no separate
    // "no manifest" mode, which is the point of §6.1 step 3.
    //
    // -isEqualToString: is case-sensitive, and deliberately so (§7.2, §7.1).
    // Note this diverges from MPPrismThemeURLInRoot (MPUtilities.m:248),
    // which matches file names case-insensitively; normalising case here
    // would let two distinct entries collide on a case-insensitive volume.
    BOOL pristine =
        (provenanceDigest && [targetDigest isEqualToString:provenanceDigest])
        || [targetDigest isEqualToString:bundleDigest]
        || [historyDigests containsObject:targetDigest];

    // Row 5 — modified. Leave untouched. No backup, no .orig, no warning,
    // no prompt, and crucially no provenance entry (§6.1 step 6).
    if (!pristine)
        return MPBundledResourceActionSkip;

    // Row 4 — pristine and byte-equal to the bundle. No write to the file;
    // backfill the provenance entry if it was missing.
    if ([targetDigest isEqualToString:bundleDigest])
        return MPBundledResourceActionRecordOnly;

    // Rows 3 and 12 — pristine and differing. Atomically refresh from the
    // bundle and update provenance. Row 12 (downgrade) is deliberately the
    // same branch: pristine files always track the installed version (§6.2).
    return MPBundledResourceActionRefresh;
}


#pragma mark - Sync

MPBundledResourceSyncReport *MPSyncBundledResourcesInPaths(
    NSString *userDataRoot, NSString *bundleResourceRoot)
{
    MPBundledResourceSyncReport *report =
        [[MPBundledResourceSyncReport alloc] init];

    // Step 0 — guard. Nothing is read, nothing is written.
    if (!userDataRoot || !bundleResourceRoot)
    {
        report.aborted = YES;
        return report;
    }

    NSFileManager *manager = [NSFileManager defaultManager];

    // Step 1 — both manifests degrade to @{} on missing or corrupt input,
    // which is all rows 8 and 9 need (see MPBundledResourceActionForFile).
    NSDictionary<NSString *, NSSet<NSString *> *> *history =
        MPReadHistoryManifestAtPath(
            MPHistoryManifestPathInRoot(bundleResourceRoot));
    NSString *manifestPath = MPProvenanceManifestPathInRoot(userDataRoot);
    NSDictionary<NSString *, NSString *> *provenance =
        MPReadProvenanceManifestAtPath(manifestPath);

    // Step 2 — enumerate the bundle FIRST, before touching anything on
    // disk. If the bundle cannot be enumerated, every target file would
    // classify as row 7 and the resulting (empty) manifest would silently
    // erase all provenance, so this is a hard guard, not an optimisation
    // (design §6 R4).
    NSArray<NSString *> *directoryNames =
        @[kMPStylesDirectoryName, kMPThemesDirectoryName];

    // -fileExistsAtPath:isDirectory: follows symbolic links, which is what
    // we want for the resource root itself: we only ever read from it, and
    // §7.4's prohibition is about target entries we might write over. A
    // root that is missing (a wrong resourcePath, a stripped bundle) aborts
    // — unlike a missing Styles/ or Themes/ inside an otherwise valid root,
    // which is simply a bundle that ships nothing of that kind.
    BOOL bundleRootIsDirectory = NO;
    if (![manager fileExistsAtPath:bundleResourceRoot
                       isDirectory:&bundleRootIsDirectory]
        || !bundleRootIsDirectory)
    {
        NSLog(@"[MPBundledResourceSync] bundle resource root is missing or "
              @"is not a directory: %@", bundleResourceRoot);
        report.aborted = YES;
        return report;
    }

    NSMutableDictionary<NSString *, NSSet<NSString *> *> *bundleNames =
        [NSMutableDictionary dictionaryWithCapacity:directoryNames.count];
    for (NSString *directoryName in directoryNames)
    {
        NSString *bundleDirectory =
            [bundleResourceRoot stringByAppendingPathComponent:directoryName];
        BOOL failed = NO;
        NSSet<NSString *> *names =
            MPBundleFileNamesInDirectory(bundleDirectory, &failed);
        if (failed)
        {
            report.aborted = YES;
            return report;
        }
        bundleNames[directoryName] = names;
    }

    // Step 3 — row 1, the data directory itself. §7.4: any entry at that
    // path, symlink included, means the directory is PRESENT.
    if (![manager attributesOfItemAtPath:userDataRoot error:NULL])
    {
        NSError *createError = nil;
        if (![manager createDirectoryAtPath:userDataRoot
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&createError])
        {
            NSLog(@"[MPBundledResourceSync] %@: %@", userDataRoot,
                  createError);
            return report;
        }
    }

    // Step 4 — the twelve rows, per directory and per file.
    NSMutableDictionary<NSString *, NSString *> *newManifest =
        [NSMutableDictionary dictionary];

    for (NSString *directoryName in directoryNames)
    {
        NSString *bundleDirectory =
            [bundleResourceRoot stringByAppendingPathComponent:directoryName];
        NSString *targetDirectory =
            [userDataRoot stringByAppendingPathComponent:directoryName];

        // §7.4: a symlinked Styles/ or Themes/ is present, not absent. The
        // per-file rules below still run inside it.
        if (![manager attributesOfItemAtPath:targetDirectory error:NULL])
        {
            NSError *createError = nil;
            if (![manager createDirectoryAtPath:targetDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&createError])
            {
                // Row 11 at directory grain: a broken Styles/ must not stop
                // Themes/.
                NSLog(@"[MPBundledResourceSync] %@: %@", targetDirectory,
                      createError);
                continue;
            }
        }

        // The UNION of bundle and target names, so row 7 is exercised for
        // real rather than falling out silently.
        NSSet<NSString *> *shippedNames = bundleNames[directoryName];
        NSMutableSet<NSString *> *names =
            [NSMutableSet setWithSet:shippedNames];
        [names addObjectsFromArray:
            MPDirectoryEntryNames(targetDirectory, NULL)];
        NSArray<NSString *> *sortedNames =
            [names.allObjects sortedArrayUsingSelector:@selector(compare:)];

        for (NSString *name in sortedNames)
        {
            // §7.2: keys are spelled exactly as the bundle spells them, no
            // normalisation and no escaping.
            NSString *key =
                [directoryName stringByAppendingPathComponent:name];
            NSString *bundlePath =
                [bundleDirectory stringByAppendingPathComponent:name];
            NSString *targetPath =
                [targetDirectory stringByAppendingPathComponent:name];

            NSString *bundleDigest = nil;
            if ([shippedNames containsObject:name])
            {
                NSError *digestError = nil;
                bundleDigest = MPSHA256HexOfFileAtPath(bundlePath,
                                                       &digestError);
                if (!bundleDigest)
                {
                    // Row 11 — log and continue; one bad file must not stop
                    // the others.
                    NSLog(@"[MPBundledResourceSync] %@: %@", key,
                          digestError);
                    report.failedCount += 1;
                    continue;
                }
            }

            MPBundledResourceTargetState targetState =
                MPTargetStateOfPath(targetPath);

            // Only hash the target when the answer can matter: never for a
            // non-regular entry (row 10) and never for an orphan (row 7).
            NSString *targetDigest = nil;
            if (targetState == MPBundledResourceTargetRegular && bundleDigest)
            {
                NSError *digestError = nil;
                targetDigest = MPSHA256HexOfFileAtPath(targetPath,
                                                       &digestError);
                if (!targetDigest)
                {
                    NSLog(@"[MPBundledResourceSync] %@: %@", key,
                          digestError);
                    report.failedCount += 1;
                    continue;
                }
            }

            MPBundledResourceAction action = MPBundledResourceActionForFile(
                targetState, targetDigest, bundleDigest, provenance[key],
                history[key]);

            switch (action)
            {
                case MPBundledResourceActionCopy:
                {
                    NSError *copyError = nil;
                    NSURL *source = [NSURL fileURLWithPath:bundlePath];
                    NSURL *destination = [NSURL fileURLWithPath:targetPath];
                    if ([manager copyItemAtURL:source
                                         toURL:destination
                                         error:&copyError])
                    {
                        newManifest[key] = bundleDigest;
                        report.copiedCount += 1;
                    }
                    else
                    {
                        NSLog(@"[MPBundledResourceSync] %@: %@", key,
                              copyError);
                        report.failedCount += 1;
                    }
                    break;
                }
                case MPBundledResourceActionRefresh:
                {
                    NSError *refreshError = nil;
                    if (MPRefreshFileAtPath(targetPath, bundlePath,
                                            &refreshError))
                    {
                        newManifest[key] = bundleDigest;
                        report.refreshedCount += 1;
                    }
                    else
                    {
                        NSLog(@"[MPBundledResourceSync] %@: %@", key,
                              refreshError);
                        report.failedCount += 1;
                    }
                    break;
                }
                case MPBundledResourceActionRecordOnly:
                    // Row 4 — no write to the file, just backfill the entry.
                    newManifest[key] = bundleDigest;
                    report.unchangedCount += 1;
                    break;
                case MPBundledResourceActionSkip:
                    // Row 10 when the entry is not a regular file, row 5
                    // when it is one we cannot prove we placed. Neither
                    // performs I/O and neither records provenance — the
                    // missing entry is what keeps a modified file protected
                    // on subsequent launches (§6.1 step 6).
                    if (targetState == MPBundledResourceTargetNonRegular)
                        report.skippedCount += 1;
                    else
                        report.modifiedCount += 1;
                    break;
                case MPBundledResourceActionForget:
                    // Row 7 — the file stays on disk, the entry does not.
                    //
                    // Only a file we can prove the app itself placed is a
                    // genuine orphan, and a provenance entry is that proof:
                    // it means we shipped this path once and no longer do.
                    // A target file with no entry is simply the user's own
                    // — help.md:293 invites users to add custom CSS — so it
                    // is not counted, and therefore never reaches the
                    // summary log below. (It is not touched or recorded
                    // either way; that part is row 7 regardless.)
                    //
                    // This also makes the count transient rather than
                    // permanent: the first sync after we stop shipping a
                    // file counts it once and drops its entry (§7.5), so
                    // every later sync sees no entry and stays silent.
                    if (provenance[key])
                        report.orphanedCount += 1;
                    break;
            }
        }
    }

    // Step 5 — one manifest write, after the loop (§10 partial-copy), and
    // only when the bytes would actually change (B3).
    report.manifest = newManifest;
    NSData *manifestData = MPProvenanceManifestData(newManifest);
    if (manifestData)
    {
        // B3: the steady state is byte-identical, and a byte-identical
        // manifest is not rewritten — no write, no fsync, no log line.
        // A non-regular node at manifestPath (e.g. a FIFO) must not block
        // here forever; treat it exactly like a missing manifest, as the
        // row 8/9 readers already do.
        NSData *existingData = MPPathIsRegularFile(manifestPath)
            ? [NSData dataWithContentsOfFile:manifestPath] : nil;
        if (![manifestData isEqualToData:existingData])
        {
            NSError *writeError = nil;
            if (MPWriteProvenanceManifestAtPath(newManifest, manifestPath,
                                                &writeError))
            {
                report.manifestWritten = YES;
            }
            else
            {
                NSLog(@"[MPBundledResourceSync] %@: %@", manifestPath,
                      writeError);
            }
        }
    }

    // Step 6 — exactly one summary line when something changed, silent
    // otherwise. modifiedCount is deliberately excluded: a user with one
    // permanently-edited theme must not get a log line on every launch.
    // orphanedCount is deliberately included: it counts only files that
    // carried a provenance entry (see MPBundledResourceActionForget above),
    // so a mass-orphan event is notable and it is never a steady state.
    BOOL changed = (report.copiedCount + report.refreshedCount) > 0
        || report.orphanedCount > 0
        || report.manifestWritten;
    if (changed)
    {
        NSLog(@"[MPBundledResourceSync] copied %lu, refreshed %lu, left %lu "
              @"user-modified file(s) untouched, skipped %lu, orphaned %lu, "
              @"failed %lu",
              (unsigned long)report.copiedCount,
              (unsigned long)report.refreshedCount,
              (unsigned long)report.modifiedCount,
              (unsigned long)report.skippedCount,
              (unsigned long)report.orphanedCount,
              (unsigned long)report.failedCount);
    }

    return report;
}


#pragma mark - Private helpers

static NSString *MPHexStringOfDigest(const unsigned char *digest)
{
    static const char *hexDigits = "0123456789abcdef";
    char buffer[CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
    {
        buffer[i * 2] = hexDigits[(digest[i] >> 4) & 0x0F];
        buffer[i * 2 + 1] = hexDigits[digest[i] & 0x0F];
    }
    // §7.1: lowercase hexadecimal, 64 characters, no prefix, no separators.
    return [[NSString alloc] initWithBytes:buffer
                                    length:sizeof(buffer)
                                  encoding:NSASCIIStringEncoding];
}

static BOOL MPDigestStringIsWellFormed(id digest)
{
    if (![digest isKindOfClass:[NSString class]])
        return NO;
    NSString *string = digest;
    if (string.length != (NSUInteger)(CC_SHA256_DIGEST_LENGTH * 2))
        return NO;
    for (NSUInteger i = 0; i < string.length; i++)
    {
        unichar character = [string characterAtIndex:i];
        BOOL isHex = (character >= '0' && character <= '9')
            || (character >= 'a' && character <= 'f');
        if (!isHex)
            return NO;
    }
    return YES;
}

static NSError *MPPOSIXError(int code, NSString *path)
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (path)
        userInfo[NSFilePathErrorKey] = path;
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:code
                           userInfo:userInfo];
}

static NSError *MPCocoaFileError(NSInteger code, NSString *path,
                                 NSString *description)
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (path)
        userInfo[NSFilePathErrorKey] = path;
    if (description)
        userInfo[NSLocalizedDescriptionKey] = description;
    return [NSError errorWithDomain:NSCocoaErrorDomain
                               code:code
                           userInfo:userInfo];
}

/// The shared body of both manifest readers: read, parse, version-check and
/// unwrap the `files` object. Returns nil — never raises — when the file is
/// missing, unreadable, not JSON, of an unexpected shape, or of an
/// unrecognised schema version. A missing file is the ordinary first-run
/// case and is not logged; anything else is logged once.
static NSDictionary *MPManifestFilesObjectAtPath(NSString *path,
                                                 NSString *label)
{
    if (!path)
        return nil;

    // A FIFO, socket, or other non-regular node left at this path must not
    // block here indefinitely; treat it exactly like a missing manifest
    // (rows 8, 9), the same guard row 10 applies to style/theme targets.
    if (!MPPathIsRegularFile(path))
        return nil;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data)
        return nil;

    NSError *error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data
                                              options:0
                                                error:&error];
    if (![root isKindOfClass:[NSDictionary class]])
    {
        NSLog(@"[MPBundledResourceSync] ignoring unreadable %@ manifest at "
              @"%@: %@", label, path, error);
        return nil;
    }

    id version = ((NSDictionary *)root)[@"version"];
    if (![version isKindOfClass:[NSNumber class]]
        || [version integerValue] != kMPBundledResourceManifestVersion)
    {
        NSLog(@"[MPBundledResourceSync] ignoring %@ manifest at %@ with "
              @"unrecognised schema version %@", label, path, version);
        return nil;
    }

    id files = ((NSDictionary *)root)[@"files"];
    if (![files isKindOfClass:[NSDictionary class]])
    {
        NSLog(@"[MPBundledResourceSync] ignoring %@ manifest at %@ with no "
              @"usable file map", label, path);
        return nil;
    }
    return files;
}

/// §7.4: from -attributesOfItemAtPath:error:, which does not traverse a
/// terminal symbolic link. Never from -fileExistsAtPath:isDirectory:, which
/// does.
static MPBundledResourceTargetState MPTargetStateOfPath(NSString *path)
{
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:path error:NULL];
    if (!attributes)
        return MPBundledResourceTargetAbsent;
    if ([attributes.fileType isEqualToString:NSFileTypeRegular])
        return MPBundledResourceTargetRegular;
    return MPBundledResourceTargetNonRegular;
}

static BOOL MPPathIsRegularFile(NSString *path)
{
    return MPTargetStateOfPath(path) == MPBundledResourceTargetRegular;
}

/// Shallow listing of `directoryPath`, names only. Sets `*failed` when the
/// directory exists but could not be enumerated; a directory that is simply
/// absent, and one that enumerates successfully to zero entries, are both
/// reported as an empty listing with `*failed` NO.
static NSArray<NSString *> *MPDirectoryEntryNames(NSString *directoryPath,
                                                  BOOL *failed)
{
    if (failed)
        *failed = NO;

    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSURL *> *urls = [manager
              contentsOfDirectoryAtURL:[NSURL fileURLWithPath:directoryPath]
            includingPropertiesForKeys:@[]
                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                 error:&error];
    if (!urls)
    {
        // Distinguish a genuine enumeration failure from a directory that
        // is not there at all. -attributesOfItemAtPath: does not traverse a
        // terminal symlink, so a dangling link counts as present — and so
        // as a failure — rather than being quietly ignored.
        if (![manager attributesOfItemAtPath:directoryPath error:NULL])
            return @[];

        NSLog(@"[MPBundledResourceSync] cannot enumerate %@: %@",
              directoryPath, error);
        if (failed)
            *failed = YES;
        return @[];
    }

    NSMutableArray<NSString *> *names =
        [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *url in urls)
        [names addObject:url.lastPathComponent];
    return [names copy];
}

/// The regular files a bundle directory ships. Anything else in there — a
/// symlink, a nested directory — is ignored rather than counted as a
/// failure, and so is never copied.
static NSSet<NSString *> *MPBundleFileNamesInDirectory(
    NSString *directoryPath, BOOL *failed)
{
    NSArray<NSString *> *entries = MPDirectoryEntryNames(directoryPath,
                                                         failed);
    NSMutableSet<NSString *> *names =
        [NSMutableSet setWithCapacity:entries.count];
    for (NSString *name in entries)
    {
        NSString *path = [directoryPath stringByAppendingPathComponent:name];
        if (MPPathIsRegularFile(path))
            [names addObject:name];
    }
    return [names copy];
}

/// B2 — the only code path in this file that touches an existing target
/// file, and it never removes one. The bundle copy lands on a temporary in
/// the SAME directory and is then swapped in with
/// -replaceItemAtURL:withItemAtURL:…, so there is no window in which the
/// file does not exist. Delete-then-copy is forbidden (design §6 R1: the
/// app-hosted HGMarkdownHighlighterTests read the live Themes directory
/// during the test run and would fail intermittently).
///
/// The temporary name starts with "." and does not end in ".css" or
/// ".style", so that even if a failure leaves residue behind,
/// MPFileNameHasExtensionProcessor (MPUtilities.m:73-84) filters it out of
/// every style and theme listing.
static BOOL MPRefreshFileAtPath(NSString *targetPath, NSString *bundlePath,
                                NSError *__autoreleasing *error)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = targetPath.stringByDeletingLastPathComponent;
    NSString *temporaryName =
        [NSString stringWithFormat:@".%@.%@.tmp", targetPath.lastPathComponent,
                                   [[NSUUID UUID] UUIDString]];
    NSURL *temporaryURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:temporaryName]];

    if (![manager copyItemAtURL:[NSURL fileURLWithPath:bundlePath]
                          toURL:temporaryURL
                          error:error])
    {
        [manager removeItemAtURL:temporaryURL error:NULL];
        return NO;
    }

    if (![manager replaceItemAtURL:[NSURL fileURLWithPath:targetPath]
                     withItemAtURL:temporaryURL
                    backupItemName:nil
                           options:0
                  resultingItemURL:NULL
                             error:error])
    {
        [manager removeItemAtURL:temporaryURL error:NULL];
        return NO;
    }
    return YES;
}
