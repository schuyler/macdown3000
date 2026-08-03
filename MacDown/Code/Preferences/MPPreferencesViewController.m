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

/// Marks the constraints added by
/// +addHeightConstraintsForWrappingCheckboxesInView: so a repeat call can
/// replace them instead of stacking a second one on the same checkbox.
static NSString * const MPWrappingCheckboxHeightIdentifier =
    @"MPWrappingCheckboxHeight";

@interface MPPreferencesViewController ()
@property (nonatomic, assign) NSSize englishDesignSize;
@end

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
    self.englishDesignSize = frame.size;

    NSView *wrapper = [[NSView alloc] initWithFrame:frame];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:contentView];

    // Center the content in the wrapper (unchanged from before).
    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
    ]];

    NSSize resolved = [[self class] resolveSizingForContentView:contentView
                                                      inWrapper:wrapper
                                                    minimumSize:frame.size];

    // Update the wrapper frame so MASPreferences reads the correct minimum size.
    NSRect wrapperFrame = wrapper.frame;
    wrapperFrame.size = resolved;
    wrapper.frame = wrapperFrame;

    self.view = wrapper;
}

/// Deactivates any width/height pin previously applied to @c contentView by
/// +resolveSizingForContentView:inWrapper:minimumSize:, so the sizing passes
/// start from an unpinned view. Identified structurally — an = constraint from
/// the content view to no second item — which is the same shape the tests in
/// MPPreferencesViewControllerResizabilityTests.m look for.
static void MPDeactivateSizePins(NSView *contentView)
{
    for (NSLayoutConstraint *c in [contentView.constraints copy])
    {
        if (c.firstItem != contentView || c.secondItem != nil
            || c.relation != NSLayoutRelationEqual)
            continue;
        if (c.firstAttribute == NSLayoutAttributeWidth
            || c.firstAttribute == NSLayoutAttributeHeight)
            c.active = NO;
    }
}

+ (NSSize)resolveSizingForContentView:(NSView *)contentView
                            inWrapper:(NSView *)wrapper
                          minimumSize:(NSSize)minimumSize
{
    MPDeactivateSizePins(contentView);

    // --- Pass 1: resolve width ---
    // Apply a >= floor so the pane never shrinks below the English design width,
    // then ask Auto Layout for the width the content actually needs.
    NSLayoutConstraint *widthFloor =
        [contentView.widthAnchor constraintGreaterThanOrEqualToConstant:minimumSize.width];
    widthFloor.active = YES;
    [wrapper layoutSubtreeIfNeeded];
    CGFloat width = MAX(contentView.fittingSize.width, minimumSize.width);
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
    [self addHeightConstraintsForWrappingCheckboxesInView:contentView];

    // --- Pass 2: resolve height at the resolved width ---
    NSLayoutConstraint *heightFloor =
        [contentView.heightAnchor constraintGreaterThanOrEqualToConstant:minimumSize.height];
    heightFloor.active = YES;
    [wrapper layoutSubtreeIfNeeded];
    CGFloat height = MAX(contentView.fittingSize.height, minimumSize.height);
    heightFloor.active = NO;

    // Pin the resolved height.
    NSLayoutConstraint *heightPin =
        [contentView.heightAnchor constraintEqualToConstant:height];
    heightPin.active = YES;

    return NSMakeSize(width, height);
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
        // Drop the constraint a previous call left behind. It was measured at
        // whatever width applied then; keeping it would floor the checkbox at a
        // stale height, and repeated calls would pile up constraints that never
        // get released.
        for (NSLayoutConstraint *c in [checkbox.constraints copy])
        {
            if ([c.identifier isEqualToString:MPWrappingCheckboxHeightIdentifier])
                [checkbox removeConstraint:c];
        }

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
            heightConstraint.identifier = MPWrappingCheckboxHeightIdentifier;
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
    //
    // Subclasses that override -viewDidAppear must call super, or this fix
    // is silently skipped for that pane.
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
