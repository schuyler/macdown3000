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

NSString *MPStylePathForName(NSString *name)
{
    if (!name)
        return nil;
    if (![name hasExtension:kMPStyleFileExtension])
        name = [name stringByAppendingPathExtension:kMPStyleFileExtension];
    NSString *path = MPPathToDataFile(name, kMPStylesDirectoryName);
    return path;
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

NSURL *MPHighlightingThemeURLForNameInPaths(
    NSString *name, NSString *userDataRoot, NSString *bundleResourceRoot)
{
    NSString *fileName = MPPrismThemeFileName(name);
    NSFileManager *manager = [NSFileManager defaultManager];

    // Check user Application Support directory first
    if (userDataRoot)
    {
        NSString *userPath = [NSString pathWithComponents:@[
            userDataRoot, kMPPrismThemesDirectoryName, fileName]];
        if ([manager fileExistsAtPath:userPath])
            return [NSURL fileURLWithPath:userPath];
    }

    // Fall back to bundle resources
    if (bundleResourceRoot)
    {
        NSString *bundlePath = [NSString pathWithComponents:@[
            bundleResourceRoot, kMPPrismThemesDirectoryName, fileName]];
        if ([manager fileExistsAtPath:bundlePath])
            return [NSURL fileURLWithPath:bundlePath];

        // Safety net: fall back to default theme (prism.css)
        NSString *defaultPath = [NSString pathWithComponents:@[
            bundleResourceRoot, kMPPrismThemesDirectoryName, @"prism.css"]];
        if ([manager fileExistsAtPath:defaultPath])
            return [NSURL fileURLWithPath:defaultPath];
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

