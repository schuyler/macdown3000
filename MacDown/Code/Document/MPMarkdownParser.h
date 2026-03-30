//
//  MPMarkdownParser.h
//  MacDown 3000
//
//  CommonMark-based Markdown parser using cmark-gfm.
//  Replaces the Hoedown parser for full CommonMark 0.31.2 compliance.
//

#import <Foundation/Foundation.h>
#import "MPRenderer.h"

// Extension flags for the Markdown parser.
// These replace the old HOEDOWN_EXT_* flags.
typedef NS_OPTIONS(int, MPExtensionFlags) {
    MPExtensionAutolink       = (1 << 0),
    MPExtensionTables         = (1 << 1),
    MPExtensionStrikethrough  = (1 << 2),
    MPExtensionFootnotes      = (1 << 3),
    MPExtensionHighlight      = (1 << 4),
    MPExtensionSuperscript    = (1 << 5),
    MPExtensionMath           = (1 << 6),
    MPExtensionMathExplicit   = (1 << 7),
    // These are no-ops in CommonMark (always enabled or handled natively):
    MPExtensionFencedCode     = (1 << 8),
    MPExtensionNoIntraEmphasis = (1 << 9),
    // These are dropped in CommonMark (conflict with spec):
    MPExtensionUnderline      = (1 << 10),
    MPExtensionQuote          = (1 << 11),
};

// Renderer flags for HTML output.
// These replace the old HOEDOWN_HTML_* flags.
typedef NS_OPTIONS(int, MPRendererOptionFlags) {
    MPRendererTaskList        = (1 << 0),
    MPRendererLineNumbers     = (1 << 1),
    MPRendererHardWrap        = (1 << 2),
    MPRendererBlockcodeInfo   = (1 << 3),
};

// Language callback type - called for each code block language found.
// Returns the resolved (aliased) language name, or nil to use original.
typedef NSString * _Nullable (^MPLanguageCallback)(NSString *language);

@interface MPMarkdownParser : NSObject

// Configuration
@property (nonatomic) MPExtensionFlags extensionFlags;
@property (nonatomic) MPRendererOptionFlags rendererFlags;
@property (nonatomic) BOOL smartyPants;
@property (nonatomic) MPCodeBlockAccessoryType codeBlockAccessory;

// Language tracking
@property (nonatomic, copy) MPLanguageCallback languageCallback;

// Core API
- (NSString *)renderMarkdown:(NSString *)markdown;
- (NSString *)renderTOC:(NSString *)markdown maxLevel:(int)level;

// Reset state between renders (checkbox index counter)
- (void)resetState;

// Get current checkbox index (for testing)
@property (nonatomic, readonly) int checkboxIndex;

@end
