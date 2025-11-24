//
//  MPPreferences.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPPreferences.h"
#import "NSUserDefaults+Suite.h"
#import "MPGlobals.h"


typedef NS_ENUM(NSUInteger, MPUnorderedListMarkerType)
{
    MPUnorderedListMarkerAsterisk = 0,
    MPUnorderedListMarkerPlusSign = 1,
    MPUnorderedListMarkerMinusSign = 2,
};



NSString * const MPDidDetectFreshInstallationNotification =
    @"MPDidDetectFreshInstallationNotificationName";

static NSString * const kMPDefaultEditorFontNameKey = @"name";
static NSString * const kMPDefaultEditorFontPointSizeKey = @"size";
static NSString * const kMPDefaultEditorFontName = @"Menlo-Regular";
static CGFloat    const kMPDefaultEditorFontPointSize = 14.0;
static CGFloat    const kMPDefaultEditorHorizontalInset = 15.0;
static CGFloat    const kMPDefaultEditorVerticalInset = 30.0;
static CGFloat    const kMPDefaultEditorLineSpacing = 3.0;
static BOOL       const kMPDefaultEditorSyncScrolling = YES;
static NSString * const kMPDefaultEditorThemeName = @"Tomorrow+";
static NSString * const kMPDefaultHtmlStyleName = @"GitHub2";


@implementation MPPreferences

- (instancetype)init
{
    NSLog(@"[MPPreferences] Initializing MPPreferences (thread: %@)", [NSThread currentThread]);
    NSDate *startTime = [NSDate date];

    self = [super init];
    if (!self)
        return nil;

    NSLog(@"[MPPreferences] Calling cleanupObsoleteAutosaveValues...");
    NSDate *cleanupStart = [NSDate date];
    [self cleanupObsoleteAutosaveValues];
    NSTimeInterval cleanupDuration = [[NSDate date] timeIntervalSinceDate:cleanupStart];
    NSLog(@"[MPPreferences] cleanupObsoleteAutosaveValues completed in %.3f seconds", cleanupDuration);

    NSLog(@"[MPPreferences] Calling migratePreferencesFromLegacyBundleIdentifierIfNeeded...");
    NSDate *migrationStart = [NSDate date];
    [self migratePreferencesFromLegacyBundleIdentifierIfNeeded];
    NSTimeInterval migrationDuration = [[NSDate date] timeIntervalSinceDate:migrationStart];
    NSLog(@"[MPPreferences] migratePreferencesFromLegacyBundleIdentifierIfNeeded completed in %.3f seconds", migrationDuration);

    NSString *version =
        [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];

    // This is a fresh install. Set default preferences.
    if (!self.firstVersionInstalled)
    {
        NSLog(@"[MPPreferences] Fresh installation detected, loading default preferences");
        self.firstVersionInstalled = version;
        [self loadDefaultPreferences];

        // Post this after the initializer finishes to give others to listen
        // to this on construction.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
            [c postNotificationName:MPDidDetectFreshInstallationNotification
                             object:self];
        }];
    }

    NSLog(@"[MPPreferences] Loading default user defaults...");
    [self loadDefaultUserDefaults];
    self.latestVersionInstalled = version;

    NSTimeInterval totalDuration = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"[MPPreferences] Initialization completed successfully in %.3f seconds", totalDuration);
    return self;
}

- (void)migratePreferencesFromLegacyBundleIdentifierIfNeeded
{
    static NSString * const kMPLegacyBundleIdentifier = @"com.uranusjr.macdown";
    static NSString * const kMPMigrationCompletedKey = @"MPDidMigrateFromLegacyBundleIdentifier";
    static const NSTimeInterval kMPMigrationTimeout = 2.0;  // 2 seconds

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Check if we've already migrated
    if ([defaults boolForKey:kMPMigrationCompletedKey])
        return;

    NSLog(@"[MPPreferences] Starting preferences migration from legacy bundle identifier: %@",
          kMPLegacyBundleIdentifier);

    // Create semaphore for timeout control
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *legacyPrefs = nil;
    __block BOOL migrationSucceeded = NO;

    // Run migration on background queue to prevent blocking main thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            // Use Apple's built-in initWithSuiteName: instead of custom category
            NSUserDefaults *legacyDefaults =
                [[NSUserDefaults alloc] initWithSuiteName:kMPLegacyBundleIdentifier];

            // This call may hang on macOS Sequoia if preferences are inaccessible
            legacyPrefs = [legacyDefaults.dictionaryRepresentation copy];
            migrationSucceeded = YES;
        }
        @catch (NSException *exception) {
            NSLog(@"[MPPreferences] Migration exception: %@ - Reason: %@",
                  exception.name, exception.reason);
        }
        @finally {
            dispatch_semaphore_signal(semaphore);
        }
    });

    // Wait with timeout
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW,
                                           (int64_t)(kMPMigrationTimeout * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(semaphore, timeout);

    // Handle timeout
    if (waitResult != 0) {
        NSLog(@"[MPPreferences] Migration timed out after %.1f seconds - skipping migration",
              kMPMigrationTimeout);
        NSLog(@"[MPPreferences] This may occur on macOS Sequoia due to sandbox restrictions");
        NSLog(@"[MPPreferences] App will use default preferences");
        [defaults setBool:YES forKey:kMPMigrationCompletedKey];
        // Note: Not calling synchronize - NSUserDefaults auto-syncs (deprecated since macOS 10.13)
        return;
    }

    // Handle exception during migration
    if (!migrationSucceeded) {
        NSLog(@"[MPPreferences] Migration failed due to exception - marking as complete to prevent retry");
        [defaults setBool:YES forKey:kMPMigrationCompletedKey];
        // Note: Not calling synchronize - NSUserDefaults auto-syncs
        return;
    }

    // If there are no legacy preferences, nothing to migrate
    if (!legacyPrefs || legacyPrefs.count == 0)
    {
        NSLog(@"[MPPreferences] No legacy preferences found - migration not needed");
        [defaults setBool:YES forKey:kMPMigrationCompletedKey];
        // Note: Not calling synchronize - NSUserDefaults auto-syncs
        return;
    }

    NSLog(@"[MPPreferences] Found %lu legacy preferences to migrate",
          (unsigned long)legacyPrefs.count);

    // Phase 2: Copy preferences to new suite (with timeout protection)
    dispatch_semaphore_t semaphore2 = dispatch_semaphore_create(0);
    __block BOOL copySucceeded = NO;
    __block NSUInteger migratedCount = 0;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSUserDefaults *currentSuite =
                [[NSUserDefaults alloc] initWithSuiteName:kMPApplicationSuiteName];

            for (NSString *key in legacyPrefs)
            {
                // Skip system-generated keys
                if ([key hasPrefix:@"NS"] || [key hasPrefix:@"Apple"])
                    continue;

                id value = legacyPrefs[key];
                // Use category method for explicit CFPreferences write
                // to ensure proper suite targeting
                [currentSuite setObject:value
                                 forKey:key
                           inSuiteNamed:kMPApplicationSuiteName];
                migratedCount++;
            }

            // Note: Not calling synchronize - NSUserDefaults auto-syncs
            // synchronize is deprecated since macOS 10.13
            copySucceeded = YES;
        }
        @catch (NSException *exception) {
            NSLog(@"[MPPreferences] Exception during preference copying: %@ - Reason: %@",
                  exception.name, exception.reason);
        }
        @finally {
            dispatch_semaphore_signal(semaphore2);
        }
    });

    // Wait with timeout for Phase 2
    long waitResult2 = dispatch_semaphore_wait(semaphore2, timeout);

    if (waitResult2 != 0) {
        NSLog(@"[MPPreferences] Preference copying timed out after %.1f seconds - migration incomplete",
              kMPMigrationTimeout);
        [defaults setBool:YES forKey:kMPMigrationCompletedKey];
        // Note: Not calling synchronize - NSUserDefaults auto-syncs
        return;
    }

    if (!copySucceeded) {
        NSLog(@"[MPPreferences] Preference copying failed - marking migration as complete to prevent retry");
        [defaults setBool:YES forKey:kMPMigrationCompletedKey];
        // Note: Not calling synchronize - NSUserDefaults auto-syncs
        return;
    }

    // Mark migration as complete
    [defaults setBool:YES forKey:kMPMigrationCompletedKey];
    // Note: Not calling synchronize - NSUserDefaults auto-syncs (deprecated since macOS 10.13)

    NSLog(@"[MPPreferences] Successfully migrated %lu preferences from legacy bundle identifier",
          (unsigned long)migratedCount);
}

#pragma mark - Accessors

@dynamic firstVersionInstalled;
@dynamic latestVersionInstalled;
@dynamic updateIncludesPreReleases;
@dynamic supressesUntitledDocumentOnLaunch;
@dynamic createFileForLinkTarget;

@dynamic extensionIntraEmphasis;
@dynamic extensionTables;
@dynamic extensionFencedCode;
@dynamic extensionAutolink;
@dynamic extensionStrikethough;
@dynamic extensionUnderline;
@dynamic extensionSuperscript;
@dynamic extensionHighlight;
@dynamic extensionFootnotes;
@dynamic extensionQuote;
@dynamic extensionSmartyPants;

@dynamic markdownManualRender;

@dynamic editorAutoIncrementNumberedLists;
@dynamic editorConvertTabs;
@dynamic editorInsertPrefixInBlock;
@dynamic editorCompleteMatchingCharacters;
@dynamic editorSyncScrolling;
@dynamic editorSmartHome;
@dynamic editorStyleName;
@dynamic editorHorizontalInset;
@dynamic editorVerticalInset;
@dynamic editorLineSpacing;
@dynamic editorWidthLimited;
@dynamic editorMaximumWidth;
@dynamic editorOnRight;
@dynamic editorShowWordCount;
@dynamic editorWordCountType;
@dynamic editorScrollsPastEnd;
@dynamic editorEnsuresNewlineAtEndOfFile;
@dynamic editorUnorderedListMarkerType;

@dynamic previewZoomRelativeToBaseFontSize;

@dynamic htmlTemplateName;
@dynamic htmlStyleName;
@dynamic htmlDetectFrontMatter;
@dynamic htmlTaskList;
@dynamic htmlHardWrap;
@dynamic htmlMathJax;
@dynamic htmlMathJaxInlineDollar;
@dynamic htmlSyntaxHighlighting;
@dynamic htmlDefaultDirectoryUrl;
@dynamic htmlHighlightingThemeName;
@dynamic htmlLineNumbers;
@dynamic htmlGraphviz;
@dynamic htmlMermaid;
@dynamic htmlCodeBlockAccessory;
@dynamic htmlRendersTOC;

// Private preference.
@dynamic editorBaseFontInfo;

- (NSString *)editorBaseFontName
{
    return [self.editorBaseFontInfo[kMPDefaultEditorFontNameKey] copy];
}

- (CGFloat)editorBaseFontSize
{
    NSDictionary *info = self.editorBaseFontInfo;
    return [info[kMPDefaultEditorFontPointSizeKey] doubleValue];
}

- (NSFont *)editorBaseFont
{
    return [NSFont fontWithName:self.editorBaseFontName
                           size:self.editorBaseFontSize];
}

- (void)setEditorBaseFont:(NSFont *)font
{
    NSDictionary *info = @{
        kMPDefaultEditorFontNameKey: font.fontName,
        kMPDefaultEditorFontPointSizeKey: @(font.pointSize)
    };
    self.editorBaseFontInfo = info;
}

- (NSString *)editorUnorderedListMarker
{
    switch (self.editorUnorderedListMarkerType)
    {
        case MPUnorderedListMarkerAsterisk:
            return @"* ";
        case MPUnorderedListMarkerPlusSign:
            return @"+ ";
        case MPUnorderedListMarkerMinusSign:
            return @"- ";
        default:
            return @"* ";
    }
}

- (NSArray *)filesToOpen
{
    return [self.userDefaults objectForKey:kMPFilesToOpenKey
                              inSuiteNamed:kMPApplicationSuiteName];
}

- (void)setFilesToOpen:(NSArray *)filesToOpen
{
    [self.userDefaults setObject:filesToOpen
                          forKey:kMPFilesToOpenKey
                    inSuiteNamed:kMPApplicationSuiteName];
}

- (NSString *)pipedContentFileToOpen {
    return [self.userDefaults objectForKey:kMPPipedContentFileToOpen
                              inSuiteNamed:kMPApplicationSuiteName];
}

- (void)setPipedContentFileToOpen:(NSString *)pipedContentFileToOpenPath {
    [self.userDefaults setObject:pipedContentFileToOpenPath
                          forKey:kMPPipedContentFileToOpen
                    inSuiteNamed:kMPApplicationSuiteName];
}


#pragma mark - Private

- (void)cleanupObsoleteAutosaveValues
{
    NSLog(@"[MPPreferences] cleanupObsoleteAutosaveValues: Starting cleanup (thread: %@)", [NSThread currentThread]);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *keysToRemove = [NSMutableArray array];

    NSLog(@"[MPPreferences] cleanupObsoleteAutosaveValues: Calling dictionaryRepresentation...");
    NSDictionary *allDefaults = defaults.dictionaryRepresentation;
    NSLog(@"[MPPreferences] cleanupObsoleteAutosaveValues: Got %lu preferences", (unsigned long)allDefaults.count);

    for (NSString *key in allDefaults)
    {
        for (NSString *p in @[@"NSSplitView Subview Frames", @"NSWindow Frame"])
        {
            if (![key hasPrefix:p] || key.length < p.length + 1)
                continue;
            NSString *path = [key substringFromIndex:p.length + 1];
            NSURL *url = [NSURL URLWithString:path];
            if (!url.isFileURL)
                continue;

            NSFileManager *manager = [NSFileManager defaultManager];
            if (![manager fileExistsAtPath:url.path])
                [keysToRemove addObject:key];
            break;
        }
    }
    for (NSString *key in keysToRemove)
        [defaults removeObjectForKey:key];

    NSLog(@"[MPPreferences] cleanupObsoleteAutosaveValues: Cleanup completed, removed %lu obsolete keys", (unsigned long)keysToRemove.count);
}

/** Load app-default preferences on first launch.
 *
 * Preferences that need to be initialized manually are put here, and will be
 * applied when the user launches MacDown the first time.
 *
 * Avoid putting preferences that doe not need initialization here. E.g. a
 * boolean preference defaults to `NO` implicitly (because `nil.booleanValue` is
 * `NO` in Objective-C), thus does not need initialization.
 *
 * Note that since this is called only when the user launches the app the first
 * time, new preferences that breaks backward compatibility should NOT be put
 * here. An example would be adding a boolean config to turn OFF an existing
 * functionality. If you add the defualt-loading code here, existing users
 * upgrading from an old version will not have this method invoked, thus
 * effecting app behavior.
 *
 * @see -loadDefaultUserDefaults
 */
- (void)loadDefaultPreferences
{
    self.extensionIntraEmphasis = YES;
    self.extensionTables = YES;
    self.extensionFencedCode = YES;
    self.extensionFootnotes = YES;
    self.editorBaseFontInfo = @{
        kMPDefaultEditorFontNameKey: kMPDefaultEditorFontName,
        kMPDefaultEditorFontPointSizeKey: @(kMPDefaultEditorFontPointSize),
    };
    self.editorStyleName = kMPDefaultEditorThemeName;
    self.editorHorizontalInset = kMPDefaultEditorHorizontalInset;
    self.editorVerticalInset = kMPDefaultEditorVerticalInset;
    self.editorLineSpacing = kMPDefaultEditorLineSpacing;
    self.editorSyncScrolling = kMPDefaultEditorSyncScrolling;
    self.htmlStyleName = kMPDefaultHtmlStyleName;
    self.htmlDefaultDirectoryUrl = [NSURL fileURLWithPath:NSHomeDirectory()
                                              isDirectory:YES];
}

/** Load default preferences when the app launches.
 *
 * Preferences that need to be initialized manually are put here, and will be
 * applied when the user launches MacDown.
 *
 * This differs from -loadDefaultPreferences in that it is invoked *every time*
 * MacDown is launched, making it suitable to perform backward-compatibility
 * checks.
 *
 * @see -loadDefaultPreferences
 */
- (void)loadDefaultUserDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:@"editorMaximumWidth"])
        self.editorMaximumWidth = 1000.0;
    if (![defaults objectForKey:@"editorAutoIncrementNumberedLists"])
        self.editorAutoIncrementNumberedLists = YES;
    if (![defaults objectForKey:@"editorInsertPrefixInBlock"])
        self.editorInsertPrefixInBlock = YES;
    if (![defaults objectForKey:@"htmlTemplateName"])
        self.htmlTemplateName = @"Default";
    if (![defaults objectForKey:@"extensionStrikethough"])
        self.extensionStrikethough = YES;
}

@end
