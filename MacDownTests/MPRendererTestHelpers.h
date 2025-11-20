//
//  MPRendererTestHelpers.h
//  MacDown 3000
//
//  Shared test helpers for MPRenderer tests
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MPRenderer.h"

// Category to expose private methods for testing
@interface MPRenderer (Testing)
- (void)parseMarkdown:(NSString *)markdown;
- (NSArray *)mathjaxScripts;
@end


#pragma mark - Mock Data Source

@interface MPMockRendererDataSource : NSObject <MPRendererDataSource>
@property (nonatomic, copy) NSString *markdown;
@property (nonatomic, copy) NSString *title;
@end


#pragma mark - Mock Delegate

@interface MPMockRendererDelegate : NSObject <MPRendererDelegate>
@property (nonatomic) int extensions;
@property (nonatomic) int rendererFlags;
@property (nonatomic) BOOL smartyPants;
@property (nonatomic) BOOL renderTOC;
@property (nonatomic) BOOL detectFrontMatter;
@property (nonatomic) BOOL syntaxHighlighting;
@property (nonatomic) BOOL mermaid;
@property (nonatomic) BOOL graphviz;
@property (nonatomic) BOOL mathJax;
@property (nonatomic) MPCodeBlockAccessoryType codeBlockAccessory;
@property (nonatomic, copy) NSString *styleName;
@property (nonatomic, copy) NSString *highlightingThemeName;
@property (nonatomic, copy) NSString *lastHTML;
@end
