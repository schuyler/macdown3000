//
//  MPBundledResourceSync.h
//  MacDown 3000
//
//  Keeps the bundled Styles and Themes in the user's Application Support
//  directory up to date with the installed app, without ever overwriting a
//  file the user has edited.
//
//  The cited "contract §…" and "design §…" sections refer to the requirements
//  and design documents posted on GitHub issue #548.
//
//  Related to GitHub issue #548.
//

#import <Foundation/Foundation.h>

/// File name of the per-user provenance manifest, at the data-directory root.
extern NSString * const kMPBundledResourceManifestFileName;   // BundledResourceManifest.json


#pragma mark - Digests

/// Lowercase 64-character hex SHA-256 of the bytes of the file at `path`.
/// Reads in fixed-size chunks; never maps or loads the whole file.
/// Returns nil and sets `error` if `path` is nil, is not a regular file, or
/// cannot be read. Never raises.
NSString *MPSHA256HexOfFileAtPath(NSString *path,
                                  NSError *__autoreleasing *error);

/// Lowercase 64-character hex SHA-256 of `data`. Returns nil for nil data;
/// returns the well-known empty digest for zero-length data.
NSString *MPSHA256HexOfData(NSData *data);


#pragma mark - Manifests

/// Read the provenance manifest at `path`.
/// Returns an empty (non-nil) dictionary when the file is missing, unreadable,
/// not JSON, of an unexpected shape, or of an unrecognised schema version —
/// decision-table rows 8 and 9 are the same code path. Non-string values are
/// dropped individually. Never raises, never returns nil.
NSDictionary<NSString *, NSString *> *
MPReadProvenanceManifestAtPath(NSString *path);

/// Serialize and atomically write `manifest` to `path`
/// (NSDataWritingAtomic; §7.3 — no locking).
/// Returns NO and sets `error` on serialisation or write failure.
/// A nil or empty manifest is still written, as an empty `files` object.
BOOL MPWriteProvenanceManifestAtPath(
    NSDictionary<NSString *, NSString *> *manifest,
    NSString *path, NSError *__autoreleasing *error);

/// Canonical bytes for a provenance manifest: sorted keys, two-space indent,
/// trailing newline. Deterministic — the same dictionary always produces the
/// same bytes. Used by the writer and by the B3 "did anything change?" check.
/// Returns nil only if serialisation itself fails.
NSData *MPProvenanceManifestData(NSDictionary<NSString *, NSString *> *manifest);

/// Canonical manifest location, so callers and tests never hardcode literals.
NSString *MPProvenanceManifestPathInRoot(NSString *userDataRoot);


#pragma mark - Classification

/// State of the entry at the target path, from
/// -[NSFileManager attributesOfItemAtPath:error:], which does not follow
/// symlinks (§7.4). Never from -fileExistsAtPath:isDirectory:, which does.
typedef NS_ENUM(NSInteger, MPBundledResourceTargetState) {
    MPBundledResourceTargetAbsent = 0,
    MPBundledResourceTargetRegular,      // NSFileType == NSFileTypeRegular
    MPBundledResourceTargetNonRegular,   // symlink, directory, FIFO, socket, …
};

typedef NS_ENUM(NSInteger, MPBundledResourceAction) {
    MPBundledResourceActionSkip = 0,   // rows 5, 10 — leave alone, no entry
    MPBundledResourceActionCopy,       // rows 1, 2, 6 — copy, record digest
    MPBundledResourceActionRefresh,    // rows 3, 12 — atomic replace, record
    MPBundledResourceActionRecordOnly, // row 4 — no file write, backfill entry
    MPBundledResourceActionForget,     // row 7 — never delete, drop entry
};

/// The whole decision table, as one pure function. No I/O, no globals.
/// `targetDigest`   — required iff targetState == Regular; ignored otherwise.
///                    If targetState == Regular and targetDigest is nil,
///                    returns Skip (unclassifiable → leave alone) before any
///                    other check, so the function is verifiably total even
///                    though this combination cannot occur in the current
///                    orchestration.
/// `bundleDigest`   — nil means the file is no longer shipped (row 7).
/// `provenanceDigest` — nil means no entry (rows 8, 9, or a first sighting).
///                    Provenance is forward-only: a file with no entry whose
///                    bytes differ from the bundle is left alone, because
///                    nothing proves the app wrote it.
/// Total: every input combination returns a defined action.
MPBundledResourceAction MPBundledResourceActionForFile(
    MPBundledResourceTargetState targetState,
    NSString *targetDigest,
    NSString *bundleDigest,
    NSString *provenanceDigest);


#pragma mark - Sync

/// Outcome of one sync. Counts are per file.
@interface MPBundledResourceSyncReport : NSObject
@property (readonly) NSUInteger copiedCount;     // rows 1, 2, 6
@property (readonly) NSUInteger refreshedCount;  // rows 3, 12
@property (readonly) NSUInteger unchangedCount;  // row 4
@property (readonly) NSUInteger modifiedCount;   // row 5 — left untouched
@property (readonly) NSUInteger skippedCount;    // row 10 — non-regular
@property (readonly) NSUInteger orphanedCount;   // row 7 — gone from bundle
@property (readonly) NSUInteger failedCount;     // row 11 — per-file I/O error
/// NO when the computed manifest was byte-identical to the one on disk (B3).
@property (readonly) BOOL manifestWritten;
/// YES when the bundle could not be enumerated at all; nothing was written.
@property (readonly) BOOL aborted;
/// The manifest as written (or as it would have been). Never nil.
@property (readonly, copy) NSDictionary<NSString *, NSString *> *manifest;
@end

/// Testable variant that accepts explicit paths instead of using
/// NSBundle mainBundle / MPDataDirectory. The manifest path is derived from
/// `userDataRoot` via MPProvenanceManifestPathInRoot.
///
/// Never raises, never returns nil, never aborts on a per-file failure.
/// Returns an empty report with `aborted` set if either root is nil or
/// either of the bundle's Styles and Themes directories fails to
/// enumerate — in that case the provenance manifest on disk is left
/// completely alone. "Fails to enumerate" means the NSError out-parameter
/// of -contentsOfDirectoryAtURL:… is set; a directory that exists, is
/// readable, and genuinely contains zero files is not an error and must
/// not abort.
MPBundledResourceSyncReport *MPSyncBundledResourcesInPaths(
    NSString *userDataRoot, NSString *bundleResourceRoot);
