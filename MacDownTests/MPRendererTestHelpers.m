//
//  MPRendererTestHelpers.m
//  MacDown 3000
//
//  Shared test helpers for MPRenderer tests
//  Copyright (c) 2025 Tzu-ping Chung. All rights reserved.
//

#import "MPRendererTestHelpers.h"

@implementation MPMockRendererDataSource

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.markdown = @"";
        self.title = @"";
    }
    return self;
}

- (BOOL)rendererLoading
{
    return NO;
}

- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    return self.markdown;
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    return self.title;
}

@end


@implementation MPMockRendererDelegate

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.extensions = 0;
        self.rendererFlags = 0;
        self.smartyPants = NO;
        self.renderTOC = NO;
        self.detectFrontMatter = NO;
        self.syntaxHighlighting = NO;
        self.mermaid = NO;
        self.graphviz = NO;
        self.mathJax = NO;
        self.codeBlockAccessory = MPCodeBlockAccessoryNone;
        self.styleName = @"GitHub2";
        self.highlightingThemeName = @"tomorrow";
    }
    return self;
}

- (int)rendererExtensions:(MPRenderer *)renderer
{
    return self.extensions;
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.smartyPants;
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    return self.renderTOC;
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    return self.styleName;
}

- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.detectFrontMatter;
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    return self.syntaxHighlighting;
}

- (BOOL)rendererHasMermaid:(MPRenderer *)renderer
{
    return self.mermaid;
}

- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
{
    return self.graphviz;
}

- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return self.codeBlockAccessory;
}

- (BOOL)rendererHasMathJax:(MPRenderer *)renderer
{
    return self.mathJax;
}

- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return self.highlightingThemeName;
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    self.lastHTML = html;
}

@end
