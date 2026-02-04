//
//  MPQuickLookPreferences.h
//  MacDownCore
//
//  Quick Look preferences reader for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MPQuickLookPreferences provides read-only access to MacDown's user preferences
 * for use in the Quick Look extension. It reads from the same preference suite
 * as the main application.
 *
 * Note: Certain features are always disabled in Quick Look for performance:
 * - MathJax (mathJaxEnabled always returns NO)
 * - Mermaid (mermaidEnabled always returns NO)
 * - Graphviz (graphvizEnabled always returns NO)
 */
@interface MPQuickLookPreferences : NSObject

/**
 * Returns the shared preferences instance.
 */
+ (instancetype)sharedPreferences;

#pragma mark - Styling

/**
 * The name of the CSS style to use (e.g., "GitHub2", "Clearness").
 * Defaults to "GitHub2" if not set.
 */
- (NSString *)styleName;

/**
 * The name of the Prism syntax highlighting theme.
 * Defaults to "tomorrow" if not set.
 */
- (NSString *)highlightingThemeName;

/**
 * Whether syntax highlighting is enabled for code blocks.
 */
- (BOOL)syntaxHighlightingEnabled;

#pragma mark - Markdown Extensions

/**
 * Whether table rendering is enabled.
 */
- (BOOL)extensionTables;

/**
 * Whether fenced code blocks are enabled.
 */
- (BOOL)extensionFencedCode;

/**
 * Whether automatic URL linking is enabled.
 */
- (BOOL)extensionAutolink;

/**
 * Whether strikethrough (~~ syntax) is enabled.
 */
- (BOOL)extensionStrikethrough;

/**
 * Returns the combined extension flags as a bitmask for Hoedown.
 */
- (int)extensionFlags;

/**
 * Returns the renderer flags as a bitmask for Hoedown.
 */
- (int)rendererFlags;

#pragma mark - Feature Availability (Always Disabled for Quick Look)

/**
 * Whether MathJax is enabled. Always returns NO for Quick Look.
 */
- (BOOL)mathJaxEnabled;

/**
 * Whether Mermaid diagrams are enabled. Always returns NO for Quick Look.
 */
- (BOOL)mermaidEnabled;

/**
 * Whether Graphviz is enabled. Always returns NO for Quick Look.
 */
- (BOOL)graphvizEnabled;

@end

NS_ASSUME_NONNULL_END
