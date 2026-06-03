//
//  MPDocument.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class MPPreferences;


@interface MPDocument : NSDocument

@property (nonatomic, readonly) MPPreferences *preferences;
@property (readonly) BOOL previewVisible;
@property (readonly) BOOL editorVisible;

@property (nonatomic, readwrite) NSString *markdown;
@property (nonatomic, readonly) NSString *html;

/**
 * Toggle the checkbox at the specified index in the markdown source.
 * Unchecked checkboxes ([ ]) become checked ([x]), and vice versa.
 * Returns the modified markdown, or the original if index is out of bounds.
 * Related to GitHub issue #269.
 */
+ (NSString *)toggleCheckboxAtIndex:(NSUInteger)index inMarkdown:(NSString *)markdown;

/**
 * Step the preview pane zoom level up to the next preset.
 * Snaps to the next preset > current; beeps if already at the maximum.
 * Bound to View > Zoom In (Command-+).
 */
- (IBAction)zoomPreviewIn:(id)sender;

/**
 * Step the preview pane zoom level down to the previous preset.
 * Snaps to the next preset < current; beeps if already at the minimum.
 * Bound to View > Zoom Out (Command--).
 */
- (IBAction)zoomPreviewOut:(id)sender;

/**
 * Reset the preview pane zoom level to 100%.
 * Bound to View > Actual Size (Command-0).
 */
- (IBAction)actualPreviewSize:(id)sender;

/**
 * Set the preview pane zoom to the level represented by the sender's
 * representedObject (NSNumber). Sender may be an NSMenuItem or
 * NSPopUpButton; the toolbar dropdown uses this entry point.
 */
- (IBAction)selectPreviewZoom:(id)sender;

@end
