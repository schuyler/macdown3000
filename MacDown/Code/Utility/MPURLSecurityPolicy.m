//
//  MPURLSecurityPolicy.m
//  MacDown 3000
//
//  Security policy utility for URL validation.
//  Addresses CVE-2019-12138 (directory traversal) and CVE-2019-12173 (RCE via app bundles).
//

#import "MPURLSecurityPolicy.h"
#import <CoreServices/CoreServices.h>
#import <AppKit/AppKit.h>
#include <sys/stat.h>

@implementation MPURLSecurityPolicy

+ (BOOL)isExecutableOrAppBundleAtURL:(NSURL *)url
{
    if (!url || !url.isFileURL)
        return NO;

    url = url.URLByResolvingSymlinksInPath;
    NSString *path = url.path;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        return NO;

    NSString *uti = [[NSWorkspace sharedWorkspace] typeOfFile:path error:NULL];
    if (uti)
    {
        CFStringRef utiRef = (__bridge CFStringRef)uti;
        if (UTTypeConformsTo(utiRef, kUTTypeApplicationBundle)
            || UTTypeConformsTo(utiRef, kUTTypePackage)
            || UTTypeConformsTo(utiRef, kUTTypeExecutable)
            || UTTypeConformsTo(utiRef, CFSTR("public.shell-script"))
            || UTTypeConformsTo(utiRef, CFSTR("com.apple.applescript.script"))
            || UTTypeConformsTo(utiRef, CFSTR("com.apple.applescript.text")))
        {
            return YES;
        }
    }

    // Fallback: check POSIX executable bit for regular files
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) == 0)
    {
        if (S_ISREG(st.st_mode) && (st.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)))
            return YES;
    }

    return NO;
}

+ (BOOL)url:(NSURL *)targetURL isWithinScopeOfBaseURL:(NSURL *)baseURL
{
    if (!targetURL || !baseURL)
        return NO;

    if (!targetURL.isFileURL || !baseURL.isFileURL)
        return NO;

    // Resolve symlinks on the parent directory of each URL, then re-append
    // the last component. URLByResolvingSymlinksInPath uses realpath()
    // internally, which fails when the final component doesn't exist —
    // leaving intermediate symlinks unresolved. Resolving the parent
    // separately catches symlink escapes like docs/evil-link/payload
    // where evil-link points outside the document directory.
    NSURL *targetParent = targetURL.URLByDeletingLastPathComponent
                                   .URLByResolvingSymlinksInPath;
    NSString *targetPath = [targetParent.path
        stringByAppendingPathComponent:targetURL.lastPathComponent];

    NSURL *baseParent = baseURL.URLByDeletingLastPathComponent
                                .URLByResolvingSymlinksInPath;
    NSString *baseDir = baseParent.path;

    // Ensure baseDir ends with '/' to prevent prefix collision
    // e.g. /tmp/docs matching /tmp/docs-evil/file
    if (![baseDir hasSuffix:@"/"])
        baseDir = [baseDir stringByAppendingString:@"/"];

    return [targetPath hasPrefix:baseDir];
}

@end
