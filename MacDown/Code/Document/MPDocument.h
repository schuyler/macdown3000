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
{
    @package
    // Commit 8 (gap 9): Generation counter for MathJax render callbacks.
    // Exposed here (not @interface ()) so that the test category can access it via ->.
    NSUInteger _mathJaxRenderGeneration;
}

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

@end
