//
//  MPUtilities.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 8/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kMPStylesDirectoryName;
extern NSString * const kMPStyleFileExtension;
extern NSString * const kMPThemesDirectoryName;
extern NSString * const kMPThemeFileExtension;

NSString *MPDataDirectory(NSString *relativePath);
NSString *MPPathToDataFile(NSString *name, NSString *dirPath);

NSArray *MPListEntriesForDirectory(
    NSString *dirName, NSString *(^processor)(NSString *absolutePath)
);

// Block factory for MPListEntriesForDirectory
NSString *(^MPFileNameHasExtensionProcessor(NSString *ext))(NSString *path);

BOOL MPCharacterIsWhitespace(unichar character);
BOOL MPCharacterIsNewline(unichar character);
BOOL MPStringIsNewline(NSString *str);

extern NSString * const kMPPrismThemesDirectoryName;

NSString *MPStylePathForName(NSString *name);
NSString *MPThemePathForName(NSString *name);
NSURL *MPHighlightingThemeURLForName(NSString *name);
NSString *MPReadFileOfPath(NSString *path);

// Testable variants that accept explicit paths instead of using
// NSBundle mainBundle / MPDataDirectory
NSURL *MPHighlightingThemeURLForNameInPaths(
    NSString *name, NSString *userDataRoot, NSString *bundleResourceRoot);

NSArray *MPListHighlightingThemesInPaths(
    NSString *userDataRoot, NSString *bundleResourceRoot);

NSDictionary *MPGetDataMap(NSString *name);

id MPGetObjectFromJavaScript(NSString *code, NSString *variableName);


static void (^MPDocumentOpenCompletionEmpty)(
        NSDocument *doc, BOOL wasOpen, NSError *error) = ^(
        NSDocument *doc, BOOL wasOpen, NSError *error) {

};
