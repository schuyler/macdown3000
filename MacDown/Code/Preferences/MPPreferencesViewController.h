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

/// The size the pane's XIB was authored at, in English. -loadView uses it as the
/// floor for dynamic sizing (a pane never shrinks below its design size), and
/// tests reuse it when re-resolving the layout with localized titles applied.
/// NSZeroSize until the view is loaded.
@property (nonatomic, readonly) NSSize englishDesignSize;

// Partial MASPreferencesViewController conformance — inherited by all subclasses.
// MASPreferences checks these before falling back to the view's autoresizingMask.
- (BOOL)hasResizableWidth;
- (BOOL)hasResizableHeight;

/// Resolves the size @c contentView needs for the strings it is currently
/// showing, and pins it there with width and height constraints. Runs three
/// passes: width, then multi-line checkbox heights at that width, then height.
///
/// Re-entrant: any width/height pin left by a previous call is dropped first, so
/// a caller that has changed the pane's titles (e.g. a test substituting
/// localized strings) can re-run this and get a correctly re-resolved layout
/// rather than one frozen at the English width.
///
/// @param minimumSize A floor for both dimensions — normally englishDesignSize.
/// @return The resolved size, which the caller applies to @c wrapper's frame.
+ (NSSize)resolveSizingForContentView:(NSView *)contentView
                            inWrapper:(NSView *)wrapper
                          minimumSize:(NSSize)minimumSize;

/// Walks the view tree looking for word-wrapping checkbox-style NSButtons whose
/// cellSizeForBounds: height exceeds intrinsicContentSize.height (which always
/// returns single-line height). For each such checkbox, adds a >= height
/// constraint so Auto Layout allocates the correct multi-line height.
/// Called by +resolveSizingForContentView:inWrapper:minimumSize: after width is
/// pinned. Idempotent — a constraint left by an earlier call is replaced, not
/// stacked on top of.
+ (void)addHeightConstraintsForWrappingCheckboxesInView:(NSView *)view;

@end
