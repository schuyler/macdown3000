//
//  MPDocumentSplitView.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung on 13/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPDocumentSplitView.h"


@implementation NSColor (Equality)

- (BOOL)isEqualToColor:(NSColor *)color
{
    NSColor *rgb1 = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *rgb2 = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return rgb1 && rgb2 && [rgb1 isEqual:rgb2];
}

@end


@implementation MPDocumentSplitView

@synthesize dividerColor = _dividerColor;

- (NSColor *)dividerColor
{
    if (_dividerColor)
        return _dividerColor;
    return [super dividerColor];
}

- (void)setDividerColor:(NSColor *)color
{
    if ([color isEqualToColor:_dividerColor])
        return;
    _dividerColor = color;
    [self setNeedsDisplay:YES];
}

- (CGFloat)dividerLocation
{
    NSArray *parts = self.subviews;
    NSAssert1(parts.count == 2, @"%@ should only be used on two-item splits.",
              NSStringFromSelector(_cmd));

    CGFloat totalWidth = self.frame.size.width - self.dividerThickness;
    CGFloat leftWidth = [parts[0] frame].size.width;
    return leftWidth / totalWidth;
}

- (void)setDividerLocation:(CGFloat)ratio
{
    NSArray *parts = self.subviews;
    NSAssert1(parts.count == 2, @"%@ should only be used on two-item splits.",
              NSStringFromSelector(_cmd));
    if (ratio < 0.0)
        ratio = 0.0;
    else if (ratio > 1.0)
        ratio = 1.0;
    CGFloat dividerThickness = self.dividerThickness;
    CGFloat totalWidth = self.frame.size.width - dividerThickness;
    CGFloat leftWidth = totalWidth * ratio;
    CGFloat rightWidth = totalWidth - leftWidth;
    NSView *left = parts[0];
    NSView *right = parts[1];

    left.frame = NSMakeRect(0.0, 0.0, leftWidth, left.frame.size.height);
    right.frame = NSMakeRect(leftWidth + dividerThickness, 0.0,
                             rightWidth, right.frame.size.height);
    [self setPosition:leftWidth ofDividerAtIndex:0];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
    NSArray *parts = self.subviews;
    if (parts.count != 2)
    {
        [super resizeSubviewsWithOldSize:oldSize];
        return;
    }

    CGFloat oldTotalWidth = oldSize.width - self.dividerThickness;
    CGFloat oldLeftWidth = [parts[0] frame].size.width;

    if (oldTotalWidth <= 0.0)
    {
        [super resizeSubviewsWithOldSize:oldSize];
        return;
    }

    CGFloat ratio = oldLeftWidth / oldTotalWidth;

    // If either pane is collapsed, defer to default NSSplitView behavior.
    if (ratio <= 0.0 || ratio >= 1.0)
    {
        [super resizeSubviewsWithOldSize:oldSize];
        return;
    }

    CGFloat dividerThickness = self.dividerThickness;
    CGFloat newTotalWidth = self.frame.size.width - dividerThickness;
    CGFloat newHeight = self.frame.size.height;
    CGFloat newLeftWidth = round(newTotalWidth * ratio);
    CGFloat newRightWidth = newTotalWidth - newLeftWidth;

    NSView *left = parts[0];
    NSView *right = parts[1];
    left.frame = NSMakeRect(0.0, 0.0, newLeftWidth, newHeight);
    right.frame = NSMakeRect(newLeftWidth + dividerThickness, 0.0,
                             newRightWidth, newHeight);
}

// Note: If the NSSplitViewDelegate ever implements
// splitView:resizeSubviewsWithOldSize:, it will shadow this override.
// In that case, move this logic into the delegate method.

- (void)swapViews
{
    NSArray *parts = self.subviews;
    NSView *left = parts[0];
    NSView *right = parts[1];
    self.subviews = @[right, left];
}


@end
