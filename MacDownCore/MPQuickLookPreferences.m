//
//  MPQuickLookPreferences.m
//  MacDownCore
//
//  Quick Look preferences reader for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import "MPQuickLookPreferences.h"
#import <cmark-gfm/mdmark.h>

// MacDown's preference suite name
static NSString * const kMPPreferenceSuiteName = @"app.macdown.macdown3000";

// Preference keys (matching MPPreferences.h)
static NSString * const kMPHtmlStyleNameKey = @"htmlStyleName";
static NSString * const kMPHtmlHighlightingThemeNameKey = @"htmlHighlightingThemeName";
static NSString * const kMPHtmlSyntaxHighlightingKey = @"htmlSyntaxHighlighting";
static NSString * const kMPExtensionTablesKey = @"extensionTables";
static NSString * const kMPExtensionFencedCodeKey = @"extensionFencedCode";
static NSString * const kMPExtensionAutolinkKey = @"extensionAutolink";
static NSString * const kMPExtensionStrikethroughKey = @"extensionStrikethough"; // Note: typo matches original
static NSString * const kMPHtmlTaskListKey = @"htmlTaskList";

// Default values
static NSString * const kMPDefaultStyleName = @"GitHub2";
static NSString * const kMPDefaultHighlightingThemeName = @"tomorrow";


@implementation MPQuickLookPreferences

#pragma mark - Singleton

+ (instancetype)sharedPreferences
{
    static MPQuickLookPreferences *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MPQuickLookPreferences alloc] init];
    });
    return instance;
}

#pragma mark - Helper Methods

- (id)preferenceForKey:(NSString *)key
{
    // Use CFPreferences to read from MacDown's preference domain
    // This works in sandboxed extensions for reading (not writing)
    CFPropertyListRef value = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kMPPreferenceSuiteName,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );

    if (value) {
        id result = (__bridge_transfer id)value;
        return result;
    }
    return nil;
}

- (NSString *)stringPreferenceForKey:(NSString *)key defaultValue:(NSString *)defaultValue
{
    id value = [self preferenceForKey:key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return defaultValue;
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue
{
    id value = [self preferenceForKey:key];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return defaultValue;
}

#pragma mark - Styling

- (NSString *)styleName
{
    return [self stringPreferenceForKey:kMPHtmlStyleNameKey
                           defaultValue:kMPDefaultStyleName];
}

- (NSString *)highlightingThemeName
{
    return [self stringPreferenceForKey:kMPHtmlHighlightingThemeNameKey
                           defaultValue:kMPDefaultHighlightingThemeName];
}

- (BOOL)syntaxHighlightingEnabled
{
    return [self boolPreferenceForKey:kMPHtmlSyntaxHighlightingKey
                         defaultValue:YES];
}

#pragma mark - Markdown Extensions

- (BOOL)extensionTables
{
    return [self boolPreferenceForKey:kMPExtensionTablesKey
                         defaultValue:YES];
}

- (BOOL)extensionFencedCode
{
    return [self boolPreferenceForKey:kMPExtensionFencedCodeKey
                         defaultValue:YES];
}

- (BOOL)extensionAutolink
{
    return [self boolPreferenceForKey:kMPExtensionAutolinkKey
                         defaultValue:YES];
}

- (BOOL)extensionStrikethrough
{
    return [self boolPreferenceForKey:kMPExtensionStrikethroughKey
                         defaultValue:YES];
}

- (int)extensionFlags
{
    int flags = 0;

    if ([self extensionTables]) {
        flags |= MDMARK_EXT_TABLES;
    }
    // Fenced code is core CommonMark and always on; the extensionFencedCode
    // preference no longer maps to a parser flag (issue #77).
    if ([self extensionAutolink]) {
        flags |= MDMARK_EXT_AUTOLINK;
    }
    if ([self extensionStrikethrough]) {
        flags |= MDMARK_EXT_STRIKETHROUGH;
    }

    return flags;
}

- (int)rendererFlags
{
    int flags = 0;

    // Enable task lists if configured
    BOOL taskList = [self boolPreferenceForKey:kMPHtmlTaskListKey defaultValue:YES];
    if (taskList) {
        flags |= MDMARK_HTML_USE_TASK_LIST;
    }

    // Enable block code information for language tags
    flags |= MDMARK_HTML_BLOCKCODE_INFORMATION;

    return flags;
}

#pragma mark - Feature Availability (Always Disabled for Quick Look)

- (BOOL)mathJaxEnabled
{
    // Always return NO for Quick Look - MathJax is too heavy
    return NO;
}

- (BOOL)mermaidEnabled
{
    // Always return NO for Quick Look - Mermaid is too heavy
    return NO;
}

- (BOOL)graphvizEnabled
{
    // Always return NO for Quick Look - Graphviz is too heavy
    return NO;
}

@end
