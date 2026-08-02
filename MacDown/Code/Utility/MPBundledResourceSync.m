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

NSString * const kMPBundledResourceManifestFileName =
    @"BundledResourceManifest.json";
NSString * const kMPBundledResourceHistoryFileName =
    @"BundledResourceHistory.json";


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
@end


// TODO(#548): implemented in the green phase

#pragma mark - Digests

NSString *MPSHA256HexOfFileAtPath(NSString *path,
                                  NSError *__autoreleasing *error)
{
    return nil;
}

NSString *MPSHA256HexOfData(NSData *data)
{
    return nil;
}


#pragma mark - Manifests

NSDictionary<NSString *, NSString *> *
MPReadProvenanceManifestAtPath(NSString *path)
{
    return @{};
}

BOOL MPWriteProvenanceManifestAtPath(
    NSDictionary<NSString *, NSString *> *manifest,
    NSString *path, NSError *__autoreleasing *error)
{
    return NO;
}

NSData *MPProvenanceManifestData(NSDictionary<NSString *, NSString *> *manifest)
{
    return nil;
}

NSDictionary<NSString *, NSSet<NSString *> *> *
MPReadHistoryManifestAtPath(NSString *path)
{
    return @{};
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
    return MPBundledResourceActionSkip;
}


#pragma mark - Sync

MPBundledResourceSyncReport *MPSyncBundledResourcesInPaths(
    NSString *userDataRoot, NSString *bundleResourceRoot)
{
    MPBundledResourceSyncReport *report = [[MPBundledResourceSyncReport alloc]
        init];
    report.copiedCount = 0;
    report.refreshedCount = 0;
    report.unchangedCount = 0;
    report.modifiedCount = 0;
    report.skippedCount = 0;
    report.orphanedCount = 0;
    report.failedCount = 0;
    report.manifestWritten = NO;
    report.aborted = NO;
    report.manifest = @{};
    return report;
}
