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

    NSView *wrapper = [[NSView alloc] initWithFrame:frame];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:contentView];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
        [contentView.widthAnchor  constraintEqualToConstant:NSWidth(frame)],
        [contentView.heightAnchor constraintEqualToConstant:NSHeight(frame)],
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
