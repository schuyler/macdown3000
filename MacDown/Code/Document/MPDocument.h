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

/// When non-nil, this document's window is a folder workspace and shows a
/// folder sidebar rooted at this URL.
///
/// Must be set BEFORE -makeWindowControllers: the sidebar is installed while
/// the window's nib loads, so setting this afterwards is silently ignored and
/// the window comes up with no sidebar. Open the document with display:NO, set
/// this, then make the window controllers.
///
/// Stored with symlinks resolved, so that one folder is one workspace however
/// it was reached.
@property (nonatomic, copy) NSURL *workspaceRootURL;

/**
 * Toggle the checkbox at the specified index in the markdown source.
 * Unchecked checkboxes ([ ]) become checked ([x]), and vice versa.
 * Returns the modified markdown, or the original if index is out of bounds.
 * Related to GitHub issue #269.
 */
+ (NSString *)toggleCheckboxAtIndex:(NSUInteger)index inMarkdown:(NSString *)markdown;

/**
 * Set the shared document zoom to the level represented by the sender's
 * representedObject (NSNumber). Sender may be an NSMenuItem or
 * NSPopUpButton; the toolbar dropdown uses this entry point.
 */
- (IBAction)selectDocumentZoom:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)resetZoom:(id)sender;

@end
