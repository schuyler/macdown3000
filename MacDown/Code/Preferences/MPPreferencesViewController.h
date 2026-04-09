//
//  MPPreferencesViewController.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class MPPreferences;


extern NSString * const MPDidRequestEditorSetupNotification;
extern NSString * const MPDidRequestPreviewRenderNotification;

@interface MPPreferencesViewController : NSViewController

- (id)init;

@property (nonatomic, readonly) MPPreferences *preferences;

// Partial MASPreferencesViewController conformance — inherited by all subclasses.
// MASPreferences checks these before falling back to the view's autoresizingMask.
- (BOOL)hasResizableWidth;
- (BOOL)hasResizableHeight;

@end
