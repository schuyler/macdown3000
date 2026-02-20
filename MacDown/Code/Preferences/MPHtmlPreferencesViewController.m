//
//  MPHtmlPreferencesViewController.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 8/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPHtmlPreferencesViewController.h"
#import "MPUtilities.h"
#import "MPPreferences.h"


NS_INLINE NSString *MPPrismDefaultThemeName()
{
    return NSLocalizedString(@"(Default)", @"Prism theme title");
}


@interface MPHtmlPreferencesViewController ()
@property (weak) IBOutlet NSPopUpButton *stylesheetSelect;
@property (weak) IBOutlet NSSegmentedControl *stylesheetFunctions;
@property (weak) IBOutlet NSPopUpButton *highlightingThemeSelect;
@property (weak) IBOutlet NSSegmentedControl *highlightingThemeFunctions;
@end


@implementation MPHtmlPreferencesViewController

#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier
{
    return @"HtmlPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"PreferencesRendering"];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"Rendering", @"Preference pane title.");
}


#pragma mark - Override

- (void)viewWillAppear
{
    [self loadStylesheets];
    [self loadHighlightingThemes];
}


#pragma mark - IBAction

- (IBAction)changeStylesheet:(NSPopUpButton *)sender
{
    NSString *title = sender.selectedItem.title;

    // Special case: the first (empty) item. No stylesheets will be used.
    if (!title.length)
        self.preferences.htmlStyleName = nil;
    else
        self.preferences.htmlStyleName = title;
}

- (IBAction)changeHighlightingTheme:(NSPopUpButton *)sender
{
    NSString *title = sender.selectedItem.title;
    if ([title isEqualToString:MPPrismDefaultThemeName()])
        self.preferences.htmlHighlightingThemeName = @"";
    else
        self.preferences.htmlHighlightingThemeName = title;
}

- (IBAction)invokeStylesheetFunction:(NSSegmentedControl *)sender
{
    switch (sender.selectedSegment)
    {
        case 0:     // Reveal
        {
            NSString *dirPath = MPDataDirectory(kMPStylesDirectoryName);
            NSURL *url = [NSURL fileURLWithPath:dirPath];
            NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
            [workspace activateFileViewerSelectingURLs:@[url]];
            break;
        }
        case 1:     // Reload
        {
            [self loadStylesheets];
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center postNotificationName:MPDidRequestPreviewRenderNotification
                                  object:self];
            break;
        }
        default:
            break;
    }
}

- (IBAction)invokeHighlightingThemeFunction:(NSSegmentedControl *)sender
{
    switch (sender.selectedSegment)
    {
        case 0:     // Reveal
        {
            NSString *dirPath =
                MPDataDirectory(kMPPrismThemesDirectoryName);
            NSFileManager *manager = [NSFileManager defaultManager];
            if (![manager fileExistsAtPath:dirPath])
            {
                [manager createDirectoryAtPath:dirPath
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:nil];
            }
            NSURL *url = [NSURL fileURLWithPath:dirPath];
            NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
            [workspace activateFileViewerSelectingURLs:@[url]];
            break;
        }
        case 1:     // Reload
        {
            [self loadHighlightingThemes];
            NSNotificationCenter *center =
                [NSNotificationCenter defaultCenter];
            [center postNotificationName:MPDidRequestPreviewRenderNotification
                                  object:self];
            break;
        }
        default:
            break;
    }
}


#pragma mark - Private

- (void)loadStylesheets
{
    self.stylesheetSelect.enabled = NO;
    [self.stylesheetSelect removeAllItems];

    NSArray *itemTitles = MPListEntriesForDirectory(
        kMPStylesDirectoryName,
        MPFileNameHasExtensionProcessor(kMPStyleFileExtension)
    );

    [self.stylesheetSelect addItemWithTitle:@""];
    [self.stylesheetSelect addItemsWithTitles:itemTitles];

    NSString *title = self.preferences.htmlStyleName;
    if (title.length)
        [self.stylesheetSelect selectItemWithTitle:title];

    self.stylesheetSelect.enabled = YES;
}

- (void)loadHighlightingThemes
{
    self.highlightingThemeSelect.enabled = NO;
    [self.highlightingThemeSelect removeAllItems];

    NSString *userDataRoot = MPDataDirectory(nil);
    NSString *bundleResourceRoot = [NSBundle mainBundle].resourcePath;
    NSArray *titles = MPListHighlightingThemesInPaths(userDataRoot,
                                                       bundleResourceRoot);

    [self.highlightingThemeSelect addItemWithTitle:MPPrismDefaultThemeName()];
    [self.highlightingThemeSelect addItemsWithTitles:titles];

    NSString *currentName = self.preferences.htmlHighlightingThemeName;
    if (currentName.length)
        [self.highlightingThemeSelect selectItemWithTitle:currentName];

    if (self.preferences.htmlSyntaxHighlighting)
        self.highlightingThemeSelect.enabled = YES;
}

@end
