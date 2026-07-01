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

    // --- Pass 1.5: fix checkbox heights for word-wrapping titles ---
    // NSButton.intrinsicContentSize always returns single-line height even when
    // lineBreakMode is wordWrap, so Auto Layout underestimates the space needed
    // for multi-line labels (e.g. French/Italian translations). Resolve frames
    // at the pinned width, then add explicit height constraints where the cell
    // reports it needs more than intrinsicContentSize provides.
    [wrapper layoutSubtreeIfNeeded];
    [[self class] addHeightConstraintsForWrappingCheckboxesInView:contentView];

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

/// Recursively collects checkbox-style NSButtons (regularSquare bezel) from the
/// view tree into @c out.
static void MPCollectCheckboxes(NSView *view, NSMutableArray<NSButton *> *out)
{
    if ([view isKindOfClass:[NSButton class]])
    {
        NSButton *button = (NSButton *)view;
        if (button.bezelStyle == NSBezelStyleRegularSquare)
            [out addObject:button];
    }
    for (NSView *sub in view.subviews)
        MPCollectCheckboxes(sub, out);
}

+ (void)addHeightConstraintsForWrappingCheckboxesInView:(NSView *)view
{
    NSMutableArray<NSButton *> *checkboxes = [NSMutableArray array];
    MPCollectCheckboxes(view, checkboxes);

    for (NSButton *checkbox in checkboxes)
    {
        NSCell *cell = checkbox.cell;
        if (cell.lineBreakMode != NSLineBreakByWordWrapping)
            continue;

        CGFloat frameWidth = NSWidth(checkbox.frame);
        if (frameWidth <= 0)
            continue;

        // cellSizeForBounds: with CGFLOAT_MAX height returns NaN on some AppKit
        // versions; use a large finite value instead. No UI checkbox label can
        // plausibly exceed 10000pt of vertical space.
        NSSize cellSize = [cell cellSizeForBounds:
                           NSMakeRect(0, 0, frameWidth, 10000)];
        CGFloat intrinsicHeight = checkbox.intrinsicContentSize.height;

        // intrinsicContentSize always returns single-line height (~16pt)
        // regardless of word-wrap. If the cell needs more, add an explicit
        // height constraint so Auto Layout allocates the correct space.
        if (cellSize.height > intrinsicHeight + 0.5)
        {
            NSLayoutConstraint *heightConstraint =
                [checkbox.heightAnchor
                    constraintGreaterThanOrEqualToConstant:ceil(cellSize.height)];
            heightConstraint.active = YES;
        }
    }
}

- (void)viewDidAppear
{
    [super viewDidAppear];

    // -loadView resolves the wrapper's final size over several Auto Layout
    // passes before installing it as self.view, which delays the moment the
    // pane's view actually lands in the window relative to when
    // MASPreferencesWindowController updates the toolbar's
    // selectedItemIdentifier during a pane switch. That timing gap can leave
    // the toolbar's selection highlight stuck on the previously active tab
    // (issue #499). Force the toolbar to revalidate and the window to
    // redraw now that the pane is actually visible.
    [self.view.window.toolbar validateVisibleItems];
    [self.view.window displayIfNeeded];
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
