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
    self = [super init];
    if (!self)
        return nil;

    [self migratePreferencesFromLegacyBundleIdentifierIfNeeded];

    NSString *version =
        [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];

    // This is a fresh install. Set default preferences.
    if (!self.firstVersionInstalled)
    {
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

    [self loadDefaultUserDefaults];
    self.latestVersionInstalled = version;

    // Run after migration and defaults are loaded so cleanup does not
    // remove keys that were just migrated or set as defaults.
    [self cleanupObsoleteAutosaveValues];

    return self;
}

// Read only the legacy application's persistent domain. A timed-out worker
// never writes preferences; startup is the sole owner of applying the result.
+ (BOOL)migrateLegacyDomain:(NSString *)domain
                 fromDefaults:(NSUserDefaults *)source
                   toDefaults:(NSUserDefaults *)destination
                      timeout:(NSTimeInterval)seconds
{
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block NSDictionary *legacy = nil;
    __block BOOL succeeded = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try
        {
            legacy = [[source persistentDomainForName:domain] copy];
            succeeded = YES;
        }
        @catch (NSException *exception)
        {
            NSLog(@"[MPPreferences] Legacy domain read failed: %@", exception.name);
        }
        @finally
        {
            dispatch_semaphore_signal(finished);
        }
    });
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW,
                       (int64_t)(seconds * NSEC_PER_SEC))) != 0 || !succeeded)
        return NO;

    for (NSString *key in legacy)
    {
        if ([key hasPrefix:@"NS"] || [key hasPrefix:@"Apple"])
            continue;
        // Settings already chosen in MacDown 3000 take precedence.
        if (![destination objectForKey:key])
            [destination setObject:legacy[key] forKey:key];
    }
    return YES;
}

- (void)migratePreferencesFromLegacyBundleIdentifierIfNeeded
{
    NSString *completedKey = @"MPDidMigrateFromLegacyBundleIdentifier";
    NSUserDefaults *defaults = self.userDefaults;
    if ([defaults boolForKey:completedKey])
        return;
    if ([[self class] migrateLegacyDomain:@"com.uranusjr.macdown"
                            fromDefaults:defaults toDefaults:defaults timeout:2.0])
        [defaults setBool:YES forKey:completedKey];
    // A failed read remains retryable on the next launch.
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
@dynamic editorStartInPreviewMode;
@dynamic editorShowWordCount;
@dynamic editorWordCountType;
@dynamic editorAutoSave;
@dynamic editorScrollsPastEnd;
@dynamic editorEnsuresNewlineAtEndOfFile;
@dynamic editorShowsInvisibleCharacters;
@dynamic editorUnorderedListMarkerType;

@dynamic previewZoomRelativeToBaseFontSize;
@dynamic documentZoomLevel;

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

- (NSArray *)foldersToOpen
{
    return [self.userDefaults objectForKey:kMPFoldersToOpenKey
                              inSuiteNamed:kMPApplicationSuiteName];
}

- (void)setFoldersToOpen:(NSArray *)foldersToOpen
{
    [self.userDefaults setObject:foldersToOpen forKey:kMPFoldersToOpenKey
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
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *keysToRemove = [NSMutableArray array];

    NSDictionary *allDefaults = defaults.dictionaryRepresentation;

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
    self.extensionIntraEmphasis = NO;
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
    self.documentZoomLevel = 1.0;
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
    if (![defaults objectForKey:@"editorAutoSave"])
        self.editorAutoSave = YES;

    // Defensive default for document zoom level. Migration v6 also handles
    // this, but this branch protects against any path that bypasses the
    // migration code (e.g. a stale user defaults blob that already has a
    // higher MPMigrationVersion but lacks this key).
    if (![defaults objectForKey:@"documentZoomLevel"])
        self.documentZoomLevel = 1.0;

    // Apply preference migrations using version-based system.
    [self applyPreferencesMigrations];
}

/** Determine the effective migration version.
 *
 * If an explicit MPMigrationVersion is set, use it. Otherwise, infer the
 * version from legacy boolean migration flags for backward compatibility.
 *
 * Migration version history:
 * - Version 0: Pre-migration state (no migrations applied)
 * - Version 1: Substitution defaults fix (Issue #263)
 * - Version 2: Task list default fix (Issue #269)
 * - Version 3: Intra-emphasis default fix (Issue #293),
 *              hide YAML front matter by default (Issue #307)
 * - Version 4: Clear stale split view autosave (Issue #309)
 * - Version 5: Auto-save preference default
 * - Version 6: Document zoom level default (100%)
 */
- (NSInteger)effectiveMigrationVersion
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Check if new version key exists
    if ([defaults objectForKey:@"MPMigrationVersion"])
    {
        return [defaults integerForKey:@"MPMigrationVersion"];
    }

    // Infer version from legacy boolean flags
    static NSString * const kMPDidApplySubstitutionDefaultsFix =
        @"MPDidApplySubstitutionDefaultsFix";
    static NSString * const kMPDidApplyTaskListDefaultFix =
        @"MPDidApplyTaskListDefaultFix";

    if ([defaults boolForKey:kMPDidApplyTaskListDefaultFix])
    {
        return 2;  // Both v1 and v2 migrations applied
    }

    if ([defaults boolForKey:kMPDidApplySubstitutionDefaultsFix])
    {
        return 1;  // Only v1 migration applied
    }

    return 0;  // No migrations applied yet
}

/** Apply all preference migrations.
 *
 * Migrations are applied incrementally based on the effective version.
 * Each migration is applied only once, and user choices made after
 * migration are preserved on subsequent launches.
 */
- (void)applyPreferencesMigrations
{
    static NSInteger const kMPCurrentMigrationVersion = 6;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSInteger currentVersion = [self effectiveMigrationVersion];

    // Migration Version 1: Substitution defaults fix (Issue #263)
    // Text substitutions (smart dashes, smart quotes, etc.) break Markdown syntax
    // and should be OFF by default.
    if (currentVersion < 1)
    {
        [defaults setBool:NO forKey:@"editorAutomaticDashSubstitutionEnabled"];
        [defaults setBool:NO forKey:@"editorAutomaticQuoteSubstitutionEnabled"];
        [defaults setBool:NO forKey:@"editorAutomaticTextReplacementEnabled"];
        [defaults setBool:NO forKey:@"editorAutomaticSpellingCorrectionEnabled"];
        [defaults setBool:NO forKey:@"editorSmartInsertDeleteEnabled"];
        [defaults setBool:NO forKey:@"editorAutomaticDataDetectionEnabled"];
        [defaults setBool:NO forKey:@"editorContinuousSpellCheckingEnabled"];
        [defaults setBool:NO forKey:@"editorGrammarCheckingEnabled"];
        // Also set legacy flag for backward compatibility detection
        [defaults setBool:YES forKey:@"MPDidApplySubstitutionDefaultsFix"];
    }

    // Migration Version 2: Task list default fix (Issue #269)
    // Enable checkbox/task list support by default.
    if (currentVersion < 2)
    {
        self.htmlTaskList = YES;
        // Also set legacy flag for backward compatibility detection
        [defaults setBool:YES forKey:@"MPDidApplyTaskListDefaultFix"];
    }

    // Migration Version 3: Intra-emphasis default fix (Issue #293)
    // Disable intra-word emphasis so underscores in filenames are not italicized.
    // Also enable front matter detection to hide YAML front matter (Issue #307).
    if (currentVersion < 3)
    {
        self.extensionIntraEmphasis = NO;
        self.htmlDetectFrontMatter = YES;
    }

    // Migration Version 4: Clear stale split view autosave (Issue #309)
    // The XIB had asymmetric initial frames (509/514 instead of 511/512).
    // NSSplitView autosave stored those absolute widths, so maximizing a
    // window would not maintain a 1:1 ratio. Clear the "Untitled" autosave
    // so new windows pick up the corrected XIB frames.
    if (currentVersion < 4)
    {
        [defaults removeObjectForKey:@"NSSplitView Subview Frames Untitled"];
    }

    // Migration Version 5: Auto-save preference default
    // Ensure existing users get editorAutoSave = YES to preserve existing behavior.
    if (currentVersion < 5)
    {
        self.editorAutoSave = YES;
    }

    // Migration Version 6: Document zoom level default
    // Establish a 100% baseline shared by the editor and preview panes.
    // Without this, existing users would inherit 0.0 (the implicit default
    // for a CGFloat NSNumber-backed preference), which would zero out the
    // preview on first launch after upgrade.
    if (currentVersion < 6)
    {
        self.documentZoomLevel = 1.0;
    }

    // Update to current version
    [defaults setInteger:MAX(currentVersion, kMPCurrentMigrationVersion)
                 forKey:@"MPMigrationVersion"];
}

@end
