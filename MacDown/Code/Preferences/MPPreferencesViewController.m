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
    NSRect designFrame = contentView.frame;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;

    // Keep the panel's designed width, then measure the height the content
    // actually needs at that width for the active locale. Longer localized
    // strings (e.g. French, Italian) wrap onto extra lines, so the panel must
    // grow vertically to fit them instead of clipping. The English design
    // height acts as a floor so we never shrink a panel.
    CGFloat width = NSWidth(designFrame);
    NSLayoutConstraint *widthConstraint =
        [contentView.widthAnchor constraintEqualToConstant:width];
    widthConstraint.active = YES;
    [contentView layoutSubtreeIfNeeded];
    CGFloat height = MAX(contentView.fittingSize.height, NSHeight(designFrame));

    NSView *wrapper =
        [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)];
    [wrapper addSubview:contentView];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
        [contentView.heightAnchor constraintEqualToConstant:height],
    ]];

    self.view = wrapper;
}

- (BOOL)hasResizableWidth  { return YES; }
- (BOOL)hasResizableHeight { return YES; }

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

@end
