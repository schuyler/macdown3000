//
//  MPQuickLookRenderer.h
//  MacDownCore
//
//  Quick Look renderer facade for MacDown 3000 (Issue #284)
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MPQuickLookRenderer provides a simplified rendering interface for the
 * Quick Look extension. It renders markdown to complete, self-contained HTML
 * suitable for display in Quick Look previews.
 *
 * Features:
 * - Basic markdown rendering (headings, paragraphs, lists, etc.)
 * - Syntax highlighting via Prism (for code blocks)
 * - User's configured CSS style
 * - All assets embedded (no external references)
 *
 * Excluded features (for performance in Quick Look):
 * - MathJax (mathematical notation)
 * - Mermaid (diagrams)
 * - Graphviz (graphs)
 */
@interface MPQuickLookRenderer : NSObject

/**
 * Render markdown string to complete HTML document.
 *
 * @param markdown The markdown string to render
 * @return Complete HTML document string with embedded styles and scripts
 */
- (nullable NSString *)renderMarkdown:(nullable NSString *)markdown;

/**
 * Render markdown from a file URL.
 *
 * @param url The file URL to read markdown from
 * @param error On return, contains an error if the file couldn't be read
 * @return Complete HTML document string, or nil on error
 */
- (nullable NSString *)renderMarkdownFromURL:(NSURL *)url
                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
