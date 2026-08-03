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

/// Testing seam. When set before the view is first loaded, this block runs after
/// the NIB is loaded and before the pane's size is resolved, receiving the NIB's
/// content view. It exists so a test can substitute localized titles and have
/// the real sizing pipeline run against them from the start — measuring a pane
/// after -loadView has already resolved and pinned its size yields meaningless
/// geometry. Always nil in production.
@property (nonatomic, copy) void (^contentDidLoadHook)(NSView *contentView);

// Partial MASPreferencesViewController conformance — inherited by all subclasses.
// MASPreferences checks these before falling back to the view's autoresizingMask.
- (BOOL)hasResizableWidth;
- (BOOL)hasResizableHeight;

/// Walks the view tree looking for word-wrapping checkbox-style NSButtons whose
/// cellSizeForBounds: height exceeds intrinsicContentSize.height (which always
/// returns single-line height). For each such checkbox, adds a >= height
/// constraint so Auto Layout allocates the correct multi-line height.
/// Called by +resolveSizingForContentView:inWrapper:minimumSize: after width is
/// pinned. Idempotent — a constraint left by an earlier call is replaced, not
/// stacked on top of.
+ (void)addHeightConstraintsForWrappingCheckboxesInView:(NSView *)view;

@end
