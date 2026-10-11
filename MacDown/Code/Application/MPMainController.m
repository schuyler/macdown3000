//
//  MPMainController.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPMainController.h"
#import <MASPreferences/MASPreferencesWindowController.h>
#import <Sparkle/Sparkle.h>
#import "MPGlobals.h"
#import "MPUtilities.h"
#import "NSDocumentController+Document.h"
#import "NSUserDefaults+Suite.h"
#import "MPPreferences.h"
#import "MPGeneralPreferencesViewController.h"
#import "MPMarkdownPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPHtmlPreferencesViewController.h"
#import "MPTerminalPreferencesViewController.h"
#import "MPDocument.h"
#import "../../../macdown-cmd/MPCommandQueue.h"


static NSString * const kMPTreatLastSeenStampKey = @"treatLastSeenStamp";


NS_INLINE BOOL MPUpdaterDisabled(void)
{
    // Unit tests run hosted inside this app, so XCTest is loaded into our
    // process. Class lookup is robust across Xcode versions, unlike the
    // XCTestConfigurationFilePath environment variable.
    if (NSClassFromString(@"XCTestCase") != Nil)
        return YES;
    // UI tests can't be detected that way (XCTest lives in the XCUITest
    // runner process, not in the app under test), so MacDownUITests passes
    // "-MPDisableUpdater YES" as a launch argument, which NSUserDefaults'
    // argument domain surfaces here. Doubles as a persistent power-user
    // kill switch (defaults write ... MPDisableUpdater -bool YES).
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"MPDisableUpdater"];
}


// Keep help, contributing and their relative images in a private unique
// directory. Reopening help must not remove or overwrite another document.
static NSURL *MPCopyBundledFile(NSString *resource, NSString *extension, NSError **error)
{
    NSURL *source = [[NSBundle mainBundle] URLForResource:resource withExtension:extension];
    if (!source)
    {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
        return nil;
    }
    NSData *contents = [NSData dataWithContentsOfURL:source options:0 error:error];
    if (!contents)
        return nil;
    NSString *path = MPWriteDataToUniqueTemporaryFile(contents, source.lastPathComponent, error);
    if (!path)
        return nil;
    NSURL *target = [NSURL fileURLWithPath:path];
    NSURL *imagesSource = [[NSBundle mainBundle] URLForResource:@"Images" withExtension:nil];
    if (imagesSource)
    {
        NSURL *imagesTarget = [target.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Images"];
        if (![[NSFileManager defaultManager] copyItemAtURL:imagesSource toURL:imagesTarget error:error])
        {
            [[NSFileManager defaultManager] removeItemAtURL:target.URLByDeletingLastPathComponent error:nil];
            return nil;
        }
    }
    return target;
}

NS_INLINE void MPOpenBundledFile(NSString *resource, NSString *extension)
{
    NSURL *target = MPCopyBundledFile(resource, extension, NULL);
    if (!target)
        return;
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [c openDocumentWithContentsOfURL:target display:YES
                   completionHandler:MPDocumentOpenCompletionEmpty];
}

NS_INLINE void treat()
{
    NSDictionary *info = MPGetDataMap(@"treats");
    NSString *name = info[@"name"];
    if (![NSUserName().lowercaseString hasPrefix:name]
            && ![NSFullUserName().lowercaseString hasPrefix:name])
        return;

    NSDictionary *data = info[@"data"];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit unit =
        NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear;
    NSDateComponents *comps = [calendar components:unit fromDate:[NSDate date]];

    NSString *key =
        [NSString stringWithFormat:@"%02ld%02ld", comps.month, comps.day];
    if (!data[key])     // No matching treat.
        return;

    NSString *stamp = [NSString stringWithFormat:@"%ld%02ld%02ld",
                       comps.year, comps.month, comps.day];

    // User has seen this treat today.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([[defaults objectForKey:kMPTreatLastSeenStampKey] isEqual:stamp])
        return;

    NSString *path = MPWriteDataToUniqueTemporaryFile(data[key], key, NULL);
    if (!path)
        return;
    NSURL *url = [NSURL fileURLWithPath:path];
    [defaults setObject:stamp forKey:kMPTreatLastSeenStampKey];

    // Make sure this is opened last and immediately visible.
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [c openDocumentWithContentsOfURL:url display:YES
                       completionHandler:MPDocumentOpenCompletionEmpty];
    }];
}


@interface MPMainController () <SPUUpdaterDelegate>
@property (readonly) NSWindowController *preferencesWindowController;
@property (readonly) NSURL *commandQueueDirectory;
@property (readonly) NSString *commandPreferencesSuiteName;
@property BOOL didMigrateLegacyCommands;
@property (strong) id appearanceObserver;
@property (nonatomic, strong, readwrite) SPUStandardUpdaterController *updaterController;
@end


@implementation MPMainController

// Used by the Help menu and tests exercising the copied document/assets.
+ (NSURL *)copyBundledFile:(NSString *)resource extension:(NSString *)extension error:(NSError **)error
{
    return MPCopyBundledFile(resource, extension, error);
}

@synthesize preferencesWindowController = _preferencesWindowController;

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self applyApplicationAppearance];
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:self
            andSelector:@selector(openUrlSchemeAppleEvent:withReplyEvent:)
          forEventClass:kInternetEventClass andEventID:kAEGetURL];

    // Deferred start (D2/D5): never start the updater in a test process --
    // startUpdater schedules timers, may show the update-permission consent
    // prompt, and on misconfiguration surfaces a modal error alert.
    if (!MPUpdaterDisabled())
        [self.updaterController startUpdater];
}

// Open a file from a browser with url of the form :
// "x-macdown://open?url=file:///path/to/a/file&line=123&column=45"
- (void)openUrlSchemeAppleEvent:(NSAppleEventDescriptor *)event
                 withReplyEvent:(NSAppleEventDescriptor *)reply
{
    NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    if (!urlString) {
        return;
    }
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    if (!url) {
        return;
    }
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url
                                                resolvingAgainstBaseURL:NO];
    if (!urlComponents) {
        return;
    }
    NSString *host = urlComponents.host;
    if (!host || ![host isEqualToString:@"open"]) {
        return;
    }
    NSArray *queryItems = urlComponents.queryItems;
    if (!queryItems) {
        return;
    }
    NSString *fileParam = [self valueForKey:@"url" fromQueryItems:queryItems];
    if (!fileParam) {
        return;
    }
    // FIXME: Could not figure out how to place the insertion point at a given
    // line and column.
    /* Unused */ NSString *lineParam = [self valueForKey:@"line"
                                          fromQueryItems:queryItems];
    /* Unused */ NSString *columnParam = [self valueForKey:@"column"
                                            fromQueryItems:queryItems];
    NSLog(@"%@:%@:%@", fileParam, lineParam, columnParam);

    NSURL *target = [NSURL URLWithString:fileParam];
    if (!target) {
        return;
    }
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [c openDocumentWithContentsOfURL:target display:YES
                   completionHandler:MPDocumentOpenCompletionEmpty];

}

- (NSString *)valueForKey:(NSString *)key fromQueryItems:(NSArray *)queryItems
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", key];
    NSURLQueryItem *queryItem = [[queryItems filteredArrayUsingPredicate:predicate] firstObject];
    return queryItem.value;
}

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSWindowController *)preferencesWindowController
{
    if (!_preferencesWindowController)
    {
        NSArray *vcs = @[
            [[MPGeneralPreferencesViewController alloc] init],
            [[MPMarkdownPreferencesViewController alloc] init],
            [[MPEditorPreferencesViewController alloc] init],
            [[MPHtmlPreferencesViewController alloc] init],
            [[MPTerminalPreferencesViewController alloc] init],
        ];
        NSString *title = NSLocalizedString(@"Preferences",
                                            @"Preferences window title.");

        typedef MASPreferencesWindowController WC;
        _preferencesWindowController =
            [[WC alloc] initWithViewControllers:vcs title:title];
    }
    return _preferencesWindowController;
}

- (IBAction)showPreferencesWindow:(id)sender
{
    [self.preferencesWindowController showWindow:nil];
}

- (IBAction)showHelp:(id)sender
{
    MPOpenBundledFile(@"help", @"md");
}

- (IBAction)showContributing:(id)sender
{
    MPOpenBundledFile(@"contribute", @"md");
}

- (IBAction)openGitHub:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/schuyler/macdown3000"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)checkForUpdates:(id)sender
{
    [self.updaterController checkForUpdates:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(performDocumentFindAction:))
        return [[self documentForFindAction] validateDocumentFindAction:menuItem];
    if (menuItem.action == @selector(checkForUpdates:))
        return self.updaterController.updater.canCheckForUpdates;
    // Intentional blanket YES: preserves the always-enabled behavior of this
    // delegate's other menu actions (and of any added in the future).
    return YES;
}

- (MPDocument *)documentForFindAction
{
    NSWindow *window = NSApp.keyWindow;
    NSDocument *document = [[NSDocumentController sharedDocumentController]
        documentForWindow:window.parentWindow ?: window];
    return [document isKindOfClass:MPDocument.class] ? (MPDocument *)document : nil;
}

- (IBAction)performDocumentFindAction:(id)sender
{
    [[self documentForFindAction] performDocumentFindAction:sender];
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return self;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(showFirstLaunchTips)
                   name:MPDidDetectFreshInstallationNotification
                 object:self.preferences];
    _updaterController = [[SPUStandardUpdaterController alloc]
        initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
    [self copyFiles];
    __weak MPMainController *weakSelf = self;
    self.appearanceObserver = [center addObserverForName:NSUserDefaultsDidChangeNotification
        object:NSUserDefaults.standardUserDefaults queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            [weakSelf applyApplicationAppearance];
        }];
    return self;
}


- (void)dealloc
{
    if (self.appearanceObserver)
        [NSNotificationCenter.defaultCenter removeObserver:self.appearanceObserver];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)applyApplicationAppearance
{
    NSInteger mode = self.preferences.applicationAppearance;
    NSString *name = mode == 1 ? NSAppearanceNameAqua :
        mode == 2 ? NSAppearanceNameDarkAqua : nil;
    if (name == nil) {
        if (NSApp.appearance) NSApp.appearance = nil;
    } else if (![NSApp.appearance.name isEqualToString:name]) {
        NSApp.appearance = [NSAppearance appearanceNamed:name];
    }
}

#pragma mark - NSApplicationDelegate

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
    NSDocumentController *controller =
        [NSDocumentController sharedDocumentController];
    for (NSURL *url in urls)
    {
        NSNumber *directory = nil, *package = nil;
        if (url.isFileURL)
        {
            [url getResourceValue:&directory forKey:NSURLIsDirectoryKey
                            error:NULL];
            [url getResourceValue:&package forKey:NSURLIsPackageKey error:NULL];
        }
        if (directory.boolValue && !package.boolValue)
        {
            [self openWorkspaceAtURL:url];
            continue;
        }
        [controller openDocumentWithContentsOfURL:url display:YES
            completionHandler:^(NSDocument *document, BOOL alreadyOpen,
                                NSError *error) {
                if (error) [application presentError:error];
            }];
    }
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    NSArray *pending = MPCommandQueueReadPending(self.commandQueueDirectory, NULL);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id legacyFiles = [defaults objectForKey:kMPFilesToOpenKey inSuiteNamed:self.commandPreferencesSuiteName];
    id legacyFolders = [defaults objectForKey:kMPFoldersToOpenKey inSuiteNamed:self.commandPreferencesSuiteName];
    if (pending.count
        || (!self.didMigrateLegacyCommands &&
            (([legacyFiles isKindOfClass:[NSArray class]] && [legacyFiles count])
             || ([legacyFolders isKindOfClass:[NSArray class]] && [legacyFolders count])
             || [defaults objectForKey:kMPPipedContentFileToOpen inSuiteNamed:self.commandPreferencesSuiteName])))
        return NO;
    return !self.preferences.supressesUntitledDocumentOnLaunch;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self openPendingCommandRequests];
    treat();
}


- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible
{
    // Launching an already active application need not trigger didBecomeActive.
    [self openPendingCommandRequests];
    return YES;
}

#pragma mark - SPUUpdaterDelegate

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater
{
    // Pre-release builds are published on the "beta" channel of the single
    // appcast at SUFeedURL. Items with no channel (stable) are always allowed.
    if (self.preferences.updateIncludesPreReleases)
        return [NSSet setWithObject:@"beta"];
    return [NSSet set];
}


#pragma mark - Private

- (void)copyFiles
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *root = MPDataDirectory(nil);
    if (![manager fileExistsAtPath:root])
    {
        [manager createDirectoryAtPath:root
           withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    MPPruneStockStylesheetsInDirectory(MPDataDirectory(kMPStylesDirectoryName),
                                        MPKnownStockStyleHashesByName());

    NSBundle *bundle = [NSBundle mainBundle];
    for (NSString *key in @[kMPThemesDirectoryName])
    {
        NSURL *dirSource = [bundle URLForResource:key withExtension:@""];
        NSURL *dirTarget = [NSURL fileURLWithPath:MPDataDirectory(key)];

        // If the directory doesn't exist, just copy the whole thing.
        if (![manager fileExistsAtPath:dirTarget.path])
        {
            [manager copyItemAtURL:dirSource toURL:dirTarget error:NULL];
            continue;
        }

        // Check for existence of each file and copy if it's not there.
        NSArray *contents = [manager contentsOfDirectoryAtURL:dirSource
                                   includingPropertiesForKeys:nil options:0
                                                        error:NULL];
        for (NSURL *fileSource in contents)
        {
            NSString *name = fileSource.lastPathComponent;
            NSURL *fileTarget = [dirTarget URLByAppendingPathComponent:name];
            if (![manager fileExistsAtPath:fileTarget.path])
                [manager copyItemAtURL:fileSource toURL:fileTarget error:NULL];
        }
    }
}

- (NSURL *)commandQueueDirectory
{
    return MPCommandQueueDirectoryForSuite(kMPApplicationSuiteName);
}

- (NSString *)commandPreferencesSuiteName
{
    return kMPApplicationSuiteName;
}

- (BOOL)migrateLegacyCommandRequests:(NSError **)error
{
    if (self.didMigrateLegacyCommands)
        return YES;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *suite = self.commandPreferencesSuiteName;
    id files = [defaults objectForKey:kMPFilesToOpenKey inSuiteNamed:suite];
    id folders = [defaults objectForKey:kMPFoldersToOpenKey inSuiteNamed:suite];
    id pipePath = [defaults objectForKey:kMPPipedContentFileToOpen inSuiteNamed:suite];
    if (files || folders || pipePath) {
        NSMutableDictionary *request = [@{@"files": files ?: @[], @"folders": folders ?: @[]} mutableCopy];
        if (pipePath) {
            if (!MPCommandQueuePathIsValid(pipePath))
                return MPCommandQueueFail(error, @"Invalid legacy piped input path");
            NSData *data = [NSData dataWithContentsOfFile:pipePath options:0 error:error];
            if (!data) return NO;
            request[@"pipedContent"] = data;
        }
        // Preserve old requests if conversion or persistence fails. From here
        // on, both migrated and current invocations use the same consumer.
        if (!MPCommandQueueEnqueue(self.commandQueueDirectory, request, error))
            return NO;
        for (NSString *key in @[kMPFilesToOpenKey, kMPFoldersToOpenKey, kMPPipedContentFileToOpen])
            [defaults setObject:nil forKey:key inSuiteNamed:suite];
        CFPreferencesSynchronize((__bridge CFStringRef)suite, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    self.didMigrateLegacyCommands = YES;
    return YES;
}

- (void)openPendingCommandRequests
{
    NSError *error = nil;
    if (![self migrateLegacyCommandRequests:&error]) {
        [NSApp presentError:error];
        return;
    }
    NSArray *requests = MPCommandQueueDrain(self.commandQueueDirectory, &error);
    if (!requests) {
        [NSApp presentError:error];
        return;
    }
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    for (NSDictionary *request in requests) {
        NSData *pipedContent = request[@"pipedContent"];
        if (pipedContent) {
            NSString *markdown = [[NSString alloc] initWithData:pipedContent encoding:NSUTF8StringEncoding];
            if (!markdown) {
                [NSApp presentError:[NSError errorWithDomain:NSCocoaErrorDomain
                    code:NSFileReadInapplicableStringEncodingError
                    userInfo:@{NSLocalizedDescriptionKey: @"Command input is not valid UTF-8 text"}]];
            } else {
                NSError *documentError = nil;
                MPDocument *document = (MPDocument *)[controller openUntitledDocumentAndDisplay:YES error:&documentError];
                if (document) document.markdown = markdown;
                else if (documentError) [NSApp presentError:documentError];
            }
        }
        for (NSString *path in request[@"files"]) {
            NSURL *url = [NSURL fileURLWithPath:path];
            if ([url checkResourceIsReachableAndReturnError:NULL]) {
                [controller openDocumentWithContentsOfURL:url display:YES
                                       completionHandler:MPDocumentOpenCompletionEmpty];
            } else {
                [controller createNewEmptyDocumentForURL:url display:YES error:NULL];
            }
        }
        for (NSString *path in request[@"folders"]) {
            NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
            if ([url checkResourceIsReachableAndReturnError:NULL])
                [self openWorkspaceAtURL:url];
        }
    }
}

- (IBAction)openFolder:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] == NSModalResponseOK && panel.URL)
        [self openWorkspaceAtURL:panel.URL];
}

- (void)openWorkspaceAtURL:(NSURL *)url
{
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    NSError *error = nil;
    MPDocument *doc =
        (MPDocument *)[c openUntitledDocumentAndDisplay:NO error:&error];
    if (!doc)
        return;
    doc.workspaceRootURL = url;          // set BEFORE the nib loads the sidebar
    [doc makeWindowControllers];
    [doc showWindows];
}



#pragma mark - Notification handler

- (void)showFirstLaunchTips
{
    // Issue #428: Open only the help document on first launch. Together
    // with the standard untitled document this makes two windows; also
    // opening contribute.md made it three, which users reported as
    // confusing. Contributing remains available in the Help menu.
    [self showHelp:nil];
}


@end
