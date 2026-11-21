//
//  MPRenderer.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 26/6.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
@protocol MPRendererDataSource;
@protocol MPRendererDelegate;


typedef NS_ENUM(NSUInteger, MPCodeBlockAccessoryType)
{
    MPCodeBlockAccessoryNone = 0,
    MPCodeBlockAccessoryLanguageName,
    MPCodeBlockAccessoryCustom,
};


@interface MPRenderer : NSObject

@property (nonatomic) int rendererFlags;
@property (weak) id<MPRendererDataSource> dataSource;
@property (weak) id<MPRendererDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *checkboxBridgeToken;

- (void)parseAndRenderNow;
- (void)parseAndRenderLater;
- (void)parseIfPreferencesChanged;
- (void)renderIfPreferencesChanged;
- (void)render;

- (NSString *)currentHtml;

/**
 * Renders the Markdown the way a parse does, with the delegate's current
 * options, but writes every task list checkbox without its state. The states
 * come back in *states, in the order of data-checkbox-index: one character
 * each, ' ' unchecked, 'x' checked, '-' indeterminate. Two texts that differ
 * only in the states of their checkboxes therefore give equal HTML.
 *
 * The renderer's own state (current HTML, languages) is left alone, and
 * checkboxes are looked for whether or not task lists are turned on.
 */
- (NSString *)checkboxProbeHTMLForMarkdown:(NSString *)markdown
                                    states:(NSString **)states;
- (NSString *)HTMLForExportWithStyles:(BOOL)withStyles
                         highlighting:(BOOL)withHighlighting;

/// Set a cache-busting timestamp for a local resource path.
/// The timestamp will be appended as ?t=<value> on the next render.
- (void)setTimestamp:(NSTimeInterval)timestamp forResourcePath:(NSString *)path;

/// Clear all cache-busting timestamps.
- (void)clearResourceTimestamps;

@end


@protocol MPRendererDataSource <NSObject>

- (BOOL)rendererLoading;
- (NSString *)rendererMarkdown:(MPRenderer *)renderer;
- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer;

@end

@protocol MPRendererDelegate <NSObject>

- (int)rendererExtensions:(MPRenderer *)renderer;
- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer;
- (BOOL)rendererRendersTOC:(MPRenderer *)renderer;
- (NSString *)rendererStyleName:(MPRenderer *)renderer;
- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer;
- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer;
- (BOOL)rendererHasMermaid:(MPRenderer *)renderer;
- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer;
- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer;
- (BOOL)rendererHasMathJax:(MPRenderer *)renderer;
- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer;
- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html;

@optional
/// Return the base URL for resolving relative resource paths.
/// Used for cache-busting local resource URLs (issue #110).
- (NSURL *)rendererBaseURL:(MPRenderer *)renderer;

@end
