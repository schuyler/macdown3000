//
//  MPTerminalPreferencesViewController.m
//  MacDown
//
//  Created by Niklas Berglund on 2017-01-11.
//  Copyright © 2017 Tzu-ping Chung . All rights reserved.
//

#import "MPGlobals.h"
#import "MPHomebrewSubprocessController.h"
#import "MPPreferences.h"
#import "MPTerminalPreferencesViewController.h"
#import "MPUtilities.h"


NS_INLINE NSColor *MPGetInstallationIndicatorColor(BOOL installed)
{
    static NSColor *installedColor = nil;
    static NSColor *uninstalledColor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        installedColor = [NSColor colorWithDeviceRed:0.357 green:0.659
                                                blue:0.192 alpha:1.000];
        uninstalledColor = [NSColor colorWithDeviceRed:0.897 green:0.231
                                                  blue:0.21 alpha:1.000];
    });
    if (installed)
        return installedColor;
    else
        return uninstalledColor;
}


@interface MPTerminalPreferencesViewController ()

@property (weak) IBOutlet NSTextField *supportIndicator;
@property (weak) IBOutlet NSTextField *supportTextField;
@property (weak) IBOutlet NSTextField *infoTextField;
@property (weak) IBOutlet NSTextField *locationTextField;
@property (weak) IBOutlet NSButton *installUninstallButton;

@property (nonatomic) NSURL *shellUtilityURL;

@end

@implementation MPTerminalPreferencesViewController


#pragma mark - Accessors.

- (void)setShellUtilityURL:(NSURL *)url
{
    _shellUtilityURL = url;
    if (url)
    {
        self.supportIndicator.textColor = MPGetInstallationIndicatorColor(YES);
        self.supportTextField.stringValue = NSLocalizedString(
            @"Shell utility installed",
            @"Label stating that shell utility has been installed");
        self.locationTextField.stringValue = url.path;
        self.locationTextField.font =
            [NSFont fontWithName:@"Menlo"
                            size:self.locationTextField.font.pointSize];
        self.installUninstallButton.title = NSLocalizedString(
            @"Uninstall", @"Uninstall shell utility button");
        self.installUninstallButton.action = @selector(uninstallShellUtility);
    }
    else
    {
        self.supportIndicator.textColor = MPGetInstallationIndicatorColor(NO);
        self.supportTextField.stringValue = NSLocalizedString(
            @"Shell utility not installed",
            @"Label stating that shell utility has not been installed");
        self.locationTextField.stringValue = NSLocalizedString(
            @"<Not installed>",
            @"Displayed when shell utility is not installed");

        NSFont *font =
            [NSFont systemFontOfSize:self.locationTextField.font.pointSize];
        self.locationTextField.font =
            [[NSFontManager sharedFontManager] convertFont:font
                                               toHaveTrait:NSFontItalicTrait];
        self.installUninstallButton.title = NSLocalizedString(
            @"Install", @"Install shell utility button");
        self.installUninstallButton.action = @selector(installShellUtility);
    }
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self highlightMacdownInInfo];
    
    self.installUninstallButton.target = self;
    self.shellUtilityURL = nil;
}

- (void)viewWillAppear
{
    [self lookForShellUtility];
}

#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier
{
    return @"TerminalPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"PreferencesTerminal"];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"Terminal", @"Preference pane title.");
}

#pragma mark - Private methods

/**
 * Returns the user-local bin directory path (~/.local/bin)
 */
- (NSString *)userBinPath
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"];
}

/**
 * Ensures a directory exists, creating it if necessary
 */
- (BOOL)ensureDirectoryExists:(NSString *)path error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;

    if ([fm fileExistsAtPath:path isDirectory:&isDirectory])
    {
        if (isDirectory)
        {
            return YES;  // Directory already exists
        }
        else
        {
            // Path exists but is not a directory
            if (error)
            {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteFileExistsError
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             NSLocalizedString(@"A file exists at this location",
                                                             @"Error when path exists but is not a directory")}];
            }
            return NO;
        }
    }

    return [fm createDirectoryAtPath:path
         withIntermediateDirectories:YES
                          attributes:nil
                               error:error];
}

/**
 * Creates a symlink, with validation and error handling
 */
- (BOOL)createSymlinkAtPath:(NSString *)linkPath
              toDestination:(NSString *)destinationPath
                      error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];

    // Validate source exists
    if (![fm fileExistsAtPath:destinationPath])
    {
        if (error)
        {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         NSLocalizedString(@"Source file does not exist",
                                                         @"Error when symlink source is missing")}];
        }
        return NO;
    }

    // Check if something already exists at link path
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:linkPath isDirectory:&isDirectory])
    {
        // Check if it's a symlink
        NSDictionary *attributes = [fm attributesOfItemAtPath:linkPath error:nil];
        if ([attributes fileType] == NSFileTypeSymbolicLink)
        {
            // It's a symlink - check if it points to the right place
            NSString *existingDestination = [fm destinationOfSymbolicLinkAtPath:linkPath error:nil];
            if ([existingDestination isEqualToString:destinationPath])
            {
                // Already installed correctly
                return YES;
            }

            // Symlink exists but points to wrong place - remove and recreate
            NSError *removeError = nil;
            if (![fm removeItemAtPath:linkPath error:&removeError])
            {
                if (error)
                {
                    *error = removeError;
                }
                return NO;
            }
        }
        else
        {
            // Regular file or directory exists - don't overwrite
            if (error)
            {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteFileExistsError
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             NSLocalizedString(@"A file already exists at the installation path",
                                                             @"Error when file exists at symlink path")}];
            }
            return NO;
        }
    }

    // Create the symlink
    return [fm createSymbolicLinkAtPath:linkPath
                    withDestinationPath:destinationPath
                                  error:error];
}

/**
 * Checks if a path is in the user's PATH environment variable
 */
- (BOOL)isPathInUserPATH:(NSString *)path
{
    NSString *pathEnv = [NSProcessInfo processInfo].environment[@"PATH"];
    if (!pathEnv || pathEnv.length == 0)
    {
        return NO;
    }

    // Expand tilde in the path to check
    NSString *expandedPath = [path stringByExpandingTildeInPath];

    // Split PATH into components
    NSArray *pathComponents = [pathEnv componentsSeparatedByString:@":"];

    for (NSString *component in pathComponents)
    {
        NSString *expandedComponent = [component stringByExpandingTildeInPath];
        if ([expandedComponent isEqualToString:expandedPath])
        {
            return YES;
        }
    }

    return NO;
}

/**
 * Searches for the the macdown shell utility and invokes foundShellUtilityAtURL: if found.
 */
- (void)lookForShellUtility
{
    __weak MPTerminalPreferencesViewController *weakSelf = self;
    MPDetectHomebrewPrefixWithCompletionhandler(^(NSString *output) {
        NSString *macdownPath = MPCommandInstallationPath;
        if (output)
        {
            NSCharacterSet *padding =
                [NSCharacterSet whitespaceAndNewlineCharacterSet];
            NSString *prefix = [output stringByTrimmingCharactersInSet:padding];
            macdownPath =
                [prefix stringByAppendingPathComponent:@"bin/macdown"];
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:macdownPath])
            weakSelf.shellUtilityURL = [NSURL fileURLWithPath:macdownPath];
        else
        {
            // Also check user-local installation
            NSString *userLocalPath = [[weakSelf userBinPath] stringByAppendingPathComponent:@"macdown"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:userLocalPath])
                weakSelf.shellUtilityURL = [NSURL fileURLWithPath:userLocalPath];
            else
                weakSelf.shellUtilityURL = nil;  // Utility not found in any location
        }
    });
}

- (void)installShellUtility
{
    // URL for macdown utility in .app bundle
    NSURL *sharedSupportURL = [NSBundle mainBundle].sharedSupportURL;
    NSString *utilityBundlePath =
        [sharedSupportURL URLByAppendingPathComponent:@"bin/macdown"].path;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:utilityBundlePath])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"Installation Failed",
            @"Shell utility installation error title");
        alert.informativeText = NSLocalizedString(
            @"The shell utility could not be found in the application bundle.",
            @"Shell utility not found error");
        [alert runModal];
        return;
    }

    // Install to user-local directory (~/.local/bin)
    NSString *userBin = [self userBinPath];
    NSString *installPath = [userBin stringByAppendingPathComponent:@"macdown"];

    // Ensure directory exists
    NSError *error = nil;
    if (![self ensureDirectoryExists:userBin error:&error])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"Installation Failed",
            @"Shell utility installation error title");
        NSString *template = NSLocalizedString(
            @"Could not create directory %@: %@",
            @"Shell utility directory creation error");
        alert.informativeText = [NSString stringWithFormat:template,
                                 userBin, error.localizedDescription];
        [alert runModal];
        return;
    }

    // Create symlink
    if ([self createSymlinkAtPath:installPath toDestination:utilityBundlePath error:&error])
    {
        // Directly update UI instead of async lookup
        self.shellUtilityURL = [NSURL fileURLWithPath:installPath];

        // Check if user needs to add to PATH
        NSString *message;
        NSString *details;

        if ([self isPathInUserPATH:userBin])
        {
            message = NSLocalizedString(
                @"Installation Successful",
                @"Shell utility installation success title");
            details = NSLocalizedString(
                @"The macdown shell utility has been installed successfully.",
                @"Shell utility installation success message");
        }
        else
        {
            message = NSLocalizedString(
                @"Installation Successful - PATH Setup Required",
                @"Shell utility installation success with PATH setup needed");
            details = [NSString stringWithFormat:
                NSLocalizedString(
                    @"The macdown shell utility has been installed to %@.\n\n"
                    @"To use it from Terminal, add this line to your shell configuration file "
                    @"(~/.zshrc or ~/.bash_profile):\n\n"
                    @"    export PATH=\"$HOME/.local/bin:$PATH\"",
                    @"Shell utility installation success with PATH instructions"),
                userBin];
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = message;
        alert.informativeText = details;
        [alert runModal];
    }
    else
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"Installation Failed",
            @"Shell utility installation error title");
        NSString *template = NSLocalizedString(
            @"The shell utility could not be installed: %@",
            @"Shell utility installation error message");
        alert.informativeText = [NSString stringWithFormat:template,
                                 error.localizedDescription];
        [alert runModal];
    }
}

- (void)uninstallShellUtility
{
    NSURL *url = self.shellUtilityURL;
    if (!url)
        return;

    NSError *error = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtURL:url error:&error];

    if (ok)
    {
        self.shellUtilityURL = nil;

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"Uninstallation Successful",
            @"Shell utility uninstallation success title");
        alert.informativeText = NSLocalizedString(
            @"The macdown shell utility has been removed successfully.",
            @"Shell utility uninstallation success message");
        [alert runModal];
    }
    else
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"Uninstallation Failed",
            @"Shell utility uninstallation error title");
        NSString *template = NSLocalizedString(
            @"The shell utility could not be removed: %@",
            @"Shell utility uninstallation error message");
        alert.informativeText = [NSString stringWithFormat:template,
                                 error.localizedDescription];
        [alert runModal];
    }
}

/**
 * Highlights all occurences of "macdown" in the info-text
 */
- (void)highlightMacdownInInfo
{
    NSString *infoString = self.infoTextField.stringValue;
    NSMutableAttributedString *attributedInfoString =
        [[NSMutableAttributedString alloc] initWithString:infoString];
    
    NSRange searchRange = NSMakeRange(0, infoString.length);
    CGFloat infoFontSize = self.infoTextField.font.pointSize;
    NSFont *highlightFont = [NSFont fontWithName:@"Menlo" size:infoFontSize];
    
    while (searchRange.location < infoString.length)
    {
        searchRange.length = infoString.length - searchRange.location;
        NSRange foundRange =
            [infoString rangeOfString:@"macdown"
                              options:NSLiteralSearch range:searchRange];
        
        if (foundRange.location != NSNotFound)
        {
            [attributedInfoString addAttribute:NSFontAttributeName value:highlightFont range:foundRange];
            
            searchRange.location = foundRange.location + foundRange.length;
        }
        else // Found all occurences
        {
            break;
        }
    }

    self.infoTextField.attributedStringValue = attributedInfoString;
}

@end
