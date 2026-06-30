//
//  MPPreferencesViewController.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPPreferencesViewController.h"
#import "MPPreferences.h"


NSString * const MPDidRequestPreviewRenderNotification =
    @"MPDidRequestPreviewRenderNotificationName";
NSString * const MPDidRequestEditorSetupNotification =
    @"MPDidRequestEditorSetupNotificationName";

@implementation MPPreferencesViewController

- (id)init
{
    return [self initWithNibName:NSStringFromClass(self.class)
                          bundle:nil];
}

- (void)loadView
{
    [super loadView];  // loads NIB named after the concrete subclass

    NSView *contentView = self.view;
    NSRect frame = contentView.frame;
    CGFloat englishDesignWidth  = NSWidth(frame);
    CGFloat englishDesignHeight = NSHeight(frame);

    NSView *wrapper = [[NSView alloc] initWithFrame:frame];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:contentView];

    // Center the content in the wrapper (unchanged from before).
    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
    ]];

    // --- Pass 1: resolve width ---
    // Apply a >= floor so the pane never shrinks below the English design width,
    // then ask Auto Layout for the width the content actually needs.
    NSLayoutConstraint *widthFloor =
        [contentView.widthAnchor constraintGreaterThanOrEqualToConstant:englishDesignWidth];
    widthFloor.active = YES;
    [wrapper layoutSubtreeIfNeeded];
    CGFloat width = MAX(contentView.fittingSize.width, englishDesignWidth);
    widthFloor.active = NO;

    // Pin the resolved width with an = constraint for the height pass.
    NSLayoutConstraint *widthPin =
        [contentView.widthAnchor constraintEqualToConstant:width];
    widthPin.active = YES;

    // --- Pass 2: resolve height at the resolved width ---
    NSLayoutConstraint *heightFloor =
        [contentView.heightAnchor constraintGreaterThanOrEqualToConstant:englishDesignHeight];
    heightFloor.active = YES;
    [wrapper layoutSubtreeIfNeeded];
    CGFloat height = MAX(contentView.fittingSize.height, englishDesignHeight);
    heightFloor.active = NO;

    // Pin the resolved height.
    NSLayoutConstraint *heightPin =
        [contentView.heightAnchor constraintEqualToConstant:height];
    heightPin.active = YES;

    // Update the wrapper frame so MASPreferences reads the correct minimum size.
    NSRect wrapperFrame = wrapper.frame;
    wrapperFrame.size = NSMakeSize(width, height);
    wrapper.frame = wrapperFrame;

    self.view = wrapper;
}

- (void)dealloc
{
    // -loadView wraps the NIB's content view in a centering wrapper, which
    // leaves the responder chain routed through this controller. When the
    // controller is later deallocated, NSViewController's own teardown tries to
    // splice itself out of that chain and can hit "The next responder should
    // never be yourself!". Detaching both ends of the link first makes the
    // superclass cleanup a no-op. (In the running app the preference panes are
    // retained for the process lifetime, so this only bites short-lived
    // instances such as those created in unit tests.)
    self.nextResponder = nil;
    if (self.isViewLoaded)
        self.view.nextResponder = nil;
}

- (BOOL)hasResizableWidth  { return YES; }
- (BOOL)hasResizableHeight { return YES; }

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

@end
