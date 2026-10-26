//
//  MPUtilities.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 8/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPUtilities.h"
#import "NSString+Lookup.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <CommonCrypto/CommonDigest.h>

NSString * const kMPStylesDirectoryName = @"Styles";
NSString * const kMPStyleFileExtension = @"css";
NSString * const kMPThemesDirectoryName = @"Themes";
NSString * const kMPThemeFileExtension = @"style";
NSString * const kMPPrismThemesDirectoryName = @"Prism/themes";

static NSString *MPDataRootDirectory()
{
    static NSString *path = nil;
    if (!path)
    {
        NSArray *paths =
            NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                NSUserDomainMask, YES);
        NSCAssert(paths.count > 0,
                  @"Cannot find directory for NSApplicationSupportDirectory.");
        NSDictionary *infoDictionary = [NSBundle mainBundle].infoDictionary;
        path = [NSString pathWithComponents:@[paths[0],
                                              infoDictionary[@"CFBundleName"]]];
    }
    return path;
}

NSString *MPDataDirectory(NSString *relativePath)
{
    if (!relativePath)
        return MPDataRootDirectory();
    return [NSString pathWithComponents:@[MPDataRootDirectory(), relativePath]];
}

NSString *MPPathToDataFile(NSString *name, NSString *dirPath)
{
    return [NSString pathWithComponents:@[MPDataDirectory(dirPath),
                                          name]];
}

NSArray *MPListEntriesForDirectory(
    NSString *dirName, NSString *(^processor)(NSString *absolutePath))
{
    NSString *dirPath = MPDataDirectory(dirName);

    NSError *error = nil;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *fileNames = [manager contentsOfDirectoryAtPath:dirPath
                                                      error:&error];
    if (error || !fileNames.count)
        return @[];

    NSMutableArray *items = [[NSMutableArray alloc] init];
    for (NSString *fileName in fileNames)
    {
        NSString *item = [NSString pathWithComponents:@[dirPath, fileName]];
        if (processor)
            item = processor(item);
        if (item)
            [items addObject:item];
    }
    return [items copy];
}

NSString *(^MPFileNameHasExtensionProcessor(NSString *ext))(NSString *path)
{
    id block = ^(NSString *absPath) {
        NSFileManager *manager = [NSFileManager defaultManager];
        NSString *name = absPath.lastPathComponent;
        NSString *processed = nil;
        if ([name hasExtension:ext] && [manager fileExistsAtPath:absPath])
            processed = name.stringByDeletingPathExtension;
        return processed;
    };
    return block;
}

BOOL MPCharacterIsWhitespace(unichar character)
{
    static NSCharacterSet *whitespaces = nil;
    if (!whitespaces)
        whitespaces = [NSCharacterSet whitespaceCharacterSet];
    return [whitespaces characterIsMember:character];
}

BOOL MPCharacterIsNewline(unichar character)
{
    static NSCharacterSet *newlines = nil;
    if (!newlines)
        newlines = [NSCharacterSet newlineCharacterSet];
    return [newlines characterIsMember:character];
}

BOOL MPStringIsNewline(NSString *str)
{
    if (str.length != 1)
        return NO;
    return MPCharacterIsNewline([str characterAtIndex:0]);
}

NSString *MPStylePathForNameInPaths(
    NSString *name, NSString *userDataRoot, NSString *bundleResourceRoot)
{
    if (!name)
        return nil;
    if (![name hasExtension:kMPStyleFileExtension])
        name = [name stringByAppendingPathExtension:kMPStyleFileExtension];

    NSFileManager *manager = [NSFileManager defaultManager];

    NSString *userPath = nil;
    if (userDataRoot)
    {
        userPath = [NSString pathWithComponents:@[
            userDataRoot, kMPStylesDirectoryName, name]];
        if ([manager fileExistsAtPath:userPath])
            return userPath;
    }

    if (bundleResourceRoot)
    {
        NSString *bundlePath = [NSString pathWithComponents:@[
            bundleResourceRoot, kMPStylesDirectoryName, name]];
        if ([manager fileExistsAtPath:bundlePath])
            return bundlePath;
    }

    return userPath;
}

NSString *MPStylePathForName(NSString *name)
{
    return MPStylePathForNameInPaths(
        name, MPDataDirectory(nil), [NSBundle mainBundle].resourcePath);
}

NSString *MPThemePathForName(NSString *name)
{
    if (![name hasExtension:kMPThemeFileExtension])
        name = [name stringByAppendingPathExtension:kMPThemeFileExtension];
    NSString *path = MPPathToDataFile(name, kMPThemesDirectoryName);
    return path;
}

NSURL *MPHighlightingThemeURLForName(NSString *name)
{
    NSString *userDataRoot = MPDataDirectory(nil);
    NSString *bundleResourceRoot = [NSBundle mainBundle].resourcePath;
    NSURL *url = MPHighlightingThemeURLForNameInPaths(
        name, userDataRoot, bundleResourceRoot);

    // Final fallback via NSBundle lookup for bundled resources
    if (!url)
    {
        NSBundle *bundle = [NSBundle mainBundle];
        url = [bundle URLForResource:@"prism" withExtension:@"css"
                        subdirectory:kMPPrismThemesDirectoryName];
    }
    return url;
}

NSString *MPReadFileOfPath(NSString *path)
{
    NSError *error = nil;
    NSString *s = [NSString stringWithContentsOfFile:path
                                            encoding:NSUTF8StringEncoding
                                               error:&error];
    if (error)
        return @"";
    return s;
}

NSDictionary *MPGetDataMap(NSString *name)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *filePath = [bundle pathForResource:name ofType:@"map"
                                     inDirectory:@"Data"];
    return [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
}

id MPGetObjectFromJavaScript(NSString *code, NSString *variableName)
{
    if (!code.length)
        return nil;

    id object = nil;
    JSGlobalContextRef cxt = NULL;
    JSStringRef js = NULL;
    JSStringRef varn = NULL;
    JSStringRef jsonr = NULL;

    do {
        JSValueRef exc = NULL;

        cxt = JSGlobalContextCreate(NULL);
        js = JSStringCreateWithCFString((__bridge CFStringRef)code);
        JSEvaluateScript(cxt, js, NULL, NULL, 0, &exc);
        if (exc)
            break;

        varn = JSStringCreateWithUTF8CString([variableName UTF8String]);
        JSObjectRef global = JSContextGetGlobalObject(cxt);
        JSValueRef val = JSObjectGetProperty(cxt, global, varn, &exc);

        // JavaScript Object -> JSON -> Foundation Object.
        // Not the best way to do this, but enough for our purpose.
        jsonr = JSValueCreateJSONString(cxt, val, 0, &exc);
        if (exc)
            break;
        size_t sz = JSStringGetLength(jsonr) + 1;   // NULL terminated.
        char *buffer = (char *)malloc(sz * sizeof(char));
        JSStringGetUTF8CString(jsonr, buffer, sz);
        NSData *data = [NSData dataWithBytesNoCopy:buffer length:sz - 1
                                      freeWhenDone:YES];
        object = [NSJSONSerialization JSONObjectWithData:data options:0
                                                   error:NULL];
    } while (0);

    if (jsonr)
        JSStringRelease(jsonr);
    if (varn)
        JSStringRelease(varn);
    if (cxt)
        JSGlobalContextRelease(cxt);
    if (js)
        JSStringRelease(js);
    return object;
}

static NSString *MPPrismThemeFileName(NSString *name)
{
    name = [NSString stringWithFormat:@"prism-%@", [name lowercaseString]];
    if ([name hasExtension:@"css"])
        name = name.stringByDeletingPathExtension;
    return [name stringByAppendingPathExtension:@"css"];
}

static NSString *MPPrismThemeDisplayName(NSString *fileName)
{
    // prism-<name>.css -> <Name> (capitalized)
    // prism.css (default) -> nil (skipped)
    if (!fileName || ![fileName hasExtension:@"css"])
        return nil;
    NSString *base = fileName.stringByDeletingPathExtension;
    if ([base isEqualToString:@"prism"])
        return nil;  // Default theme; handled separately
    if (base.length <= 6)
        return nil;  // Too short to have "prism-" prefix
    if (![base hasPrefix:@"prism-"])
        return nil;
    NSString *name = [base substringFromIndex:6];
    return [name capitalizedString];
}

static NSURL *MPPrismThemeURLInRoot(NSString *root, NSString *fileName)
{
    if (!root || !fileName)
        return nil;

    NSString *themeDir = [NSString pathWithComponents:@[
        root, kMPPrismThemesDirectoryName]];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *files = [manager contentsOfDirectoryAtPath:themeDir error:nil];
    for (NSString *file in files)
    {
        if ([file caseInsensitiveCompare:fileName] == NSOrderedSame)
        {
            NSString *path = [themeDir stringByAppendingPathComponent:file];
            return [NSURL fileURLWithPath:path];
        }
    }

    NSString *path = [themeDir stringByAppendingPathComponent:fileName];
    if ([manager fileExistsAtPath:path])
        return [NSURL fileURLWithPath:path];
    return nil;
}

NSURL *MPHighlightingThemeURLForNameInPaths(
    NSString *name, NSString *userDataRoot, NSString *bundleResourceRoot)
{
    NSString *fileName = MPPrismThemeFileName(name);

    // Check user Application Support directory first
    NSURL *url = MPPrismThemeURLInRoot(userDataRoot, fileName);
    if (url)
        return url;

    // Fall back to bundle resources
    if (bundleResourceRoot)
    {
        url = MPPrismThemeURLInRoot(bundleResourceRoot, fileName);
        if (url)
            return url;

        // Safety net: fall back to default theme (prism.css)
        url = MPPrismThemeURLInRoot(bundleResourceRoot, @"prism.css");
        if (url)
            return url;
    }

    return nil;
}

static NSArray *MPListThemeFilesInDirectory(NSString *dirPath)
{
    if (!dirPath)
        return @[];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [manager contentsOfDirectoryAtPath:dirPath error:&error];
    if (error || !files.count)
        return @[];
    NSMutableArray *cssFiles = [NSMutableArray array];
    for (NSString *file in files)
    {
        if ([file hasExtension:@"css"])
            [cssFiles addObject:file];
    }
    return cssFiles;
}

NSArray *MPListHighlightingThemesInPaths(
    NSString *userDataRoot, NSString *bundleResourceRoot)
{
    NSString *bundleThemeDir = nil;
    if (bundleResourceRoot)
        bundleThemeDir = [NSString pathWithComponents:@[
            bundleResourceRoot, kMPPrismThemesDirectoryName]];

    NSString *userThemeDir = nil;
    if (userDataRoot)
        userThemeDir = [NSString pathWithComponents:@[
            userDataRoot, kMPPrismThemesDirectoryName]];

    // Collect theme names; user themes override bundle themes
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];

    for (NSString *file in MPListThemeFilesInDirectory(bundleThemeDir))
    {
        NSString *displayName = MPPrismThemeDisplayName(file);
        if (displayName)
            [names addObject:displayName];
    }

    for (NSString *file in MPListThemeFilesInDirectory(userThemeDir))
    {
        NSString *displayName = MPPrismThemeDisplayName(file);
        if (displayName)
            [names addObject:displayName];
    }

    return [[names array] sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray *MPListStylesheetFilesInDirectory(NSString *dirPath)
{
    if (!dirPath.length)
        return @[];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *files = [manager contentsOfDirectoryAtPath:dirPath error:NULL];
    if (!files.count)
        return @[];
    NSMutableArray *cssFiles = [NSMutableArray array];
    for (NSString *file in files)
    {
        if ([file hasExtension:kMPStyleFileExtension])
            [cssFiles addObject:file];
    }
    return cssFiles;
}

NSArray *MPListStylesheetsInPaths(
    NSString *userDataRoot, NSString *bundleResourceRoot)
{
    NSString *bundleStylesDir = nil;
    if (bundleResourceRoot)
        bundleStylesDir = [NSString pathWithComponents:@[
            bundleResourceRoot, kMPStylesDirectoryName]];

    NSString *userStylesDir = nil;
    if (userDataRoot)
        userStylesDir = [NSString pathWithComponents:@[
            userDataRoot, kMPStylesDirectoryName]];

    // Collect stylesheet names; user stylesheets shadow bundle stylesheets
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];

    for (NSString *file in MPListStylesheetFilesInDirectory(bundleStylesDir))
        [names addObject:file.stringByDeletingPathExtension];

    for (NSString *file in MPListStylesheetFilesInDirectory(userStylesDir))
        [names addObject:file.stringByDeletingPathExtension];

    return [[names array] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

NSString *MPContentHashOfFileAtPath(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data)
        return nil;

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *hex =
        [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

// FROZEN. SHA-256 of the raw bytes of every version of each bundled
// MacDown/Resources/Styles/*.css across the full history of origin/main and the
// origin/3000.1.x release branch (all v3000.0.* release tags are ancestors of
// these, so every shipped build is covered), grouped by the FILENAME (basename)
// the bytes were shipped under. 11 filenames, 48 total (filename, hash) entries.
// A hash may legitimately appear under more than one filename if two stock
// styles were ever byte-identical. Regenerate/verify with:
//   for r in origin/main origin/3000.1.x; do git rev-list "$r"; done | sort -u \
//   | while read c; do git ls-tree -r "$c" -- 'MacDown/Resources/Styles'; done \
//   | awk -F'\t' '{split($1,a," "); print a[3] "\t" $2}' \
//   | while IFS=$'\t' read oid path; do \
//       base=$(basename "$path"); \
//       hash=$(git cat-file blob "$oid" | shasum -a 256 | awk '{print $1}'); \
//       printf '%s\t%s\n' "$base" "$hash"; \
//     done | sort -u
// The path is AFTER the tab in `git ls-tree` output; many bundled filenames
// contain spaces/parens (e.g. "Solarized (Dark).css", "GitHub2 (dark).css"),
// so split on the tab (not on whitespace) before taking the basename.
// PITFALL: hash file CONTENT (git cat-file blob emits raw bytes, no header),
// never the git blob OID / git hash-object (sha1 over "blob <len>\0"+content).
// Do NOT extend when editing a bundled .css: new bundle bytes reach users via the
// bundle fallback, not this list.
NSDictionary *MPKnownStockStyleHashesByName(void)
{
    static NSDictionary *hashesByName = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hashesByName = @{
            @"Clearness Dark.css": [NSSet setWithArray:@[
                @"05765781af2e5c11351443c911b9b157933637183cececb418fe21c096bdc175",
                @"1b4a6d3f69367760215fca86a8295d1f38fbe31e8323a607af012fb9092c8df5",
                @"2a85f66c4ada7ac072f6dd8dea6c0475fe43486ffe0ee02d1b4aea2cbf1dbf4b",
                @"4ada4649d15c98be10aac2f5e4e27b4d6eb2ed505fdb3275c4959300c8408ef8",
                @"82f03b31e0f7f50c430e9c71dd0670661c561eba335719ecad1fda999795c8f3",
                @"bfd53b6ac76c5dc36ae906c23f12fe84f7b1b400dae0221ddcd81201317fdd56",
                @"f5e84a44a4eb5e45ede9eec5ba86c3d3b58f74bc9a7cb98f29b606acf41a6988",
            ]],
            @"Clearness.css": [NSSet setWithArray:@[
                @"1530b81f869cc922b30c734183a2819ed2649a36843fd20e95fd3dcc6bf3cc1a",
                @"17deb38936f704a2a02339e70139bffbb0fead49ab584efcac317ad9ca18bef8",
                @"71cc1b1a42996a02185a7d2a6785d703d13b9dfe7c99e13ac5a9fcbd3cb932c7",
                @"88fe43c01e68cd61d1c5cec30deefbd062ba03d118bc54af0f783bfdc7786220",
                @"9592b8a209974c614bef8085700788df0e97fc57480c7bfd17840d9b436a02a3",
                @"a301126bdf337711146e64e1a71ffac54459fe494c8f6bd6b79e187f5247a299",
                @"fc407d712394b6dc65bd62685e4e5abf9afb960c0e25f76025a178322e47fdd3",
            ]],
            @"GitHub Tomorrow.css": [NSSet setWithArray:@[
                @"d274836c48020747374111fec9b3428670fb75d0eaaf298523221ff74b86f5d8",
                @"da9493cf8eb7e215d603c2eb1d9b290a489901b39a7860dfe5c36add8f58b013",
            ]],
            @"GitHub-2020.css": [NSSet setWithArray:@[
                @"00dbded9d7173d8b9978cb8a53719c1e754c4c9f97521a1bbb994711f0be89a0",
                @"02a6f516007712296361b92b9f6dd97a15ac05d3ae2e32cbb98cb95d419ed277",
            ]],
            @"GitHub.css": [NSSet setWithArray:@[
                @"50b145c3b6ae27c8c1f0d2907f83eeade0feabbf082ed9827fd423fa02086328",
                @"673ad0add6f2ad0283f152bd0c4806fce92ac095a8c69331d71a6fb4835140a1",
                @"80bfb54b6d230200226f0f8aa97804c86a4a230dafd23555430e5363a052ae65",
                @"a79af2ba93f265cfe734abcd0e9b48cdc9606a06ad060719cd4b1b72e05d4628",
                @"c4589f6404eff178b69c5d9ab239fbc18d5b5aeaf6bcf5fcacc6a8b3ca7e7195",
                @"d0a3400fb7d61a3fbd0a65fa8c297856fc62cb421fd63fef3808c3bd41ed0527",
                @"dc2fa94e0d2a85214b4b54b3c79377f28a014b7f0573171247ba6e2effa4ffde",
                @"f7471e693618fadb4027d1cb2fdcaadf511984812d40ebc456f76d61ab02d835",
            ]],
            @"GitHub2.css": [NSSet setWithArray:@[
                @"62ed816fefa18599c6b8dd0b3d81143459e799e335f77b81ddc1650178ddcefd",
                @"65f78ef1582900d3598d0818ff37ab0adfbba4933bb43ec8935fb7387e9fe150",
                @"9d2d6169e20d313c57e309b5b624eb3a9bbb21c08f965ff3f581e1eddb376f1e",
                @"bd19523d2c849a032909b38770cce35bb2d3aea0c22522e2995ee3d4bb54a400",
                @"d526e3d22730267ba919c1af92c9ed826ccd8b681f516add89de9ce912a79938",
            ]],
            @"Github2 (dark).css": [NSSet setWithArray:@[
                @"d437fa41d15204f524a180dd75c0fbf03ca84df442e64154f97f6f73980af3e5",
            ]],
            @"Gmail.css": [NSSet setWithArray:@[
                @"cf2f35839c870f75716ea92a40cb27a1431049983b7095a983689fc188fa5e35",
            ]],
            @"Google Docs.css": [NSSet setWithArray:@[
                @"7305f1bbf7680a5dfa6f3db8d3fdb6f98377d9a2b0c31cc4939f40dde28ea819",
            ]],
            @"Solarized (Dark).css": [NSSet setWithArray:@[
                @"561943c37b5aebe021826d1e0f1360b015519b0ac3a5b611c143943fd5468aed",
                @"584f69c6e3781e6a6721ae05ff9ee62260f26985f7e50122fa6c488a20a0f07b",
                @"7854f39e2e55c8907de5412eaaad9f71b8abbf86d1488b4e85a45d962bf8f467",
                @"7ffd144dc8257bd98723a1d119cca2168ac7c6c92bf75aa25d72b92d2014590e",
                @"831c8a7c415905f99ef5ff53625a9a6e5a2b9de3563d71f61d0f8cf287a0570d",
                @"90078438ea2645e3082abb146157f65a0a7670625bfeb372816ad25c5faf55a8",
                @"bf4621dfa934e085ebf96d083d72dd026a77999a4a94306f8e55e9fa81ef8003",
            ]],
            @"Solarized (Light).css": [NSSet setWithArray:@[
                @"22c22b5ac7ae865e3e06fe14c0f6048ca58de165c404e539119139d41ce6dca2",
                @"242c482fe855d883a92354c79be7497a90cf024c606b0d6d95f4ada97762dd2b",
                @"3d73ae06e93db17dff7e19a730166e5b83fb4864ea585f5a9eeb34446636a9eb",
                @"525852c300063e5d27c02fac5e09ce5e9278979e7a9788e0bcccca7c214f5bcc",
                @"59b7f94e154dcd17905b4916ebddb1497d5531ac203ca68fee4f003f0f7438c8",
                @"66385e7e12660597a8ddd3b57f6ccf6c94bd34125bb9f880b328b1cf8c189c71",
                @"cba3916122805eade59ddf40595019aadf982f8131a5cd63946ef339c060d370",
            ]],
        };
    });
    return hashesByName;
}

NSUInteger MPPruneStockStylesheetsInDirectory(
    NSString *stylesDir, NSDictionary<NSString *, NSSet<NSString *> *> *stockHashesByName)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *files = [manager contentsOfDirectoryAtPath:stylesDir error:NULL];

    NSUInteger count = 0;
    for (NSString *file in files)
    {
        if (![file hasExtension:kMPStyleFileExtension])
            continue;
        NSSet<NSString *> *stockHashes = stockHashesByName[file.lastPathComponent];
        if (!stockHashes)
            continue;
        NSString *path = [stylesDir stringByAppendingPathComponent:file];
        NSString *hash = MPContentHashOfFileAtPath(path);
        if (hash && [stockHashes containsObject:hash] &&
            [manager removeItemAtPath:path error:NULL])
        {
            count++;
        }
    }
    return count;
}
