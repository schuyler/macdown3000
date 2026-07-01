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

/// Walks the view tree looking for word-wrapping checkbox-style NSButtons whose
/// cellSizeForBounds: height exceeds intrinsicContentSize.height (which always
/// returns single-line height). For each such checkbox, adds a >= height
/// constraint so Auto Layout allocates the correct multi-line height.
/// Called by loadView after width is pinned.
+ (void)addHeightConstraintsForWrappingCheckboxesInView:(NSView *)view;

@end
