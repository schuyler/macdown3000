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

    // When the NIB loaded, NSViewController linked the content view's next
    // responder back to this controller. Re-homing the content view inside a
    // wrapper and then re-pointing -view at that wrapper leaves a responder
    // cycle, which trips "The next responder should never be yourself!" the
    // first time the responder chain is traversed (e.g. during layout in a
    // unit test). Detach the link before re-homing, then restore a clean
    // chain (content -> wrapper -> controller) afterward.
    contentView.nextResponder = nil;
    [wrapper addSubview:contentView];

    // Keep the panel's designed width and start at the designed height. The
    // height is grown below once the content has been laid out.
    NSLayoutConstraint *heightConstraint =
        [contentView.heightAnchor constraintEqualToConstant:NSHeight(frame)];
    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
        [contentView.widthAnchor  constraintEqualToConstant:NSWidth(frame)],
        heightConstraint,
    ]];

    self.view = wrapper;
    contentView.nextResponder = wrapper;

    // Now that the content is wrapped at its designed width, grow the height to
    // fit the content for the active locale: longer localized strings (e.g.
    // French, Italian) wrap onto extra lines, so the panel must expand to fit
    // them instead of clipping. The English design height acts as a floor so we
    // never shrink a panel.
    [wrapper layoutSubtreeIfNeeded];
    CGFloat height = MAX(contentView.fittingSize.height, NSHeight(frame));
    heightConstraint.constant = height;

    NSRect wrapperFrame = wrapper.frame;
    wrapperFrame.size.height = height;
    wrapper.frame = wrapperFrame;
}

- (BOOL)hasResizableWidth  { return YES; }
- (BOOL)hasResizableHeight { return YES; }

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

@end
