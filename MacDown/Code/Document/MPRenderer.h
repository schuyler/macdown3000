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
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *checkboxSourceOffsets;
@property (nonatomic, copy, readonly) NSString *checkboxSourceMarkdown;
/// Generated callout tokens and their ranges in the original published Markdown.
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *calloutSourceEntries;

+ (NSArray<NSNumber *> *)checkboxOffsetsForMarkdown:(NSString *)markdown;

- (void)parseAndRenderNow;
- (void)parseAndRenderLater;
- (void)parseIfPreferencesChanged;
- (void)renderIfPreferencesChanged;
- (void)render;

- (NSString *)currentHtml;
/// Parse a snapshot with the current options without publishing or scheduling it.
/// Own callout transport identities are omitted from this semantic HTML oracle;
/// authored attributes and the published preview state are preserved.
- (NSString *)HTMLForMarkdownSnapshot:(NSString *)markdown;
/// Parser-owned callout ranges without changing the published preview.
- (NSArray<NSDictionary *> *)calloutSourceEntriesForMarkdownSnapshot:(NSString *)markdown;
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
- (BOOL)rendererWrapsCodeBlocks:(MPRenderer *)renderer;
/// Return the base URL for resolving relative resource paths.
/// Used for cache-busting local resource URLs (issue #110).
- (NSURL *)rendererBaseURL:(MPRenderer *)renderer;

@end
