//
//  MPMainController.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
@class MPPreferences;
@class SPUStandardUpdaterController;

@interface MPMainController : NSObject <NSApplicationDelegate, NSMenuItemValidation>

@property (nonatomic, readonly) MPPreferences *preferences;

/** The Sparkle updater controller. Created at init (not started); started in
    applicationDidFinishLaunching: unless the updater is disabled for this
    process (XCTest loaded, or -MPDisableUpdater YES launch argument). */
@property (nonatomic, readonly, strong) SPUStandardUpdaterController *updaterController;

/** Forwards to the updater controller; target of the
    "Check for Updates…" main-menu item. */
- (IBAction)checkForUpdates:(id)sender;

/** Prompts for a directory and opens it as a folder workspace; target of the
    "Open Folder…" main-menu item. */
- (IBAction)openFolder:(id)sender;

@end
