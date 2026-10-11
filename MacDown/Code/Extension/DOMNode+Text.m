//
//  DOMNode+Text.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung on 18/1.
//  Copyright (c) 2015 Tzu-ping Chung . All rights reserved.
//

#import "DOMNode+Text.h"

typedef struct
{
    NSUInteger words;
    NSUInteger characters;
    NSUInteger charactersWithoutSpaces;
} MPAccumulatedTextCount;

NS_INLINE MPAccumulatedTextCount MPGetNodeAccumulatedTextCount(DOMNode *);

NS_INLINE MPAccumulatedTextCount MPAccumulatedTextCountMake(
    NSUInteger words, NSUInteger characters, NSUInteger charactersWithoutSpaces)
{
    MPAccumulatedTextCount count;
    count.words = words;
    count.characters = characters;
    count.charactersWithoutSpaces = charactersWithoutSpaces;
    return count;
}

NS_INLINE MPAccumulatedTextCount MPAccumulatedTextCountZero(void)
{
    return MPAccumulatedTextCountMake(0, 0, 0);
}

NS_INLINE MPAccumulatedTextCount MPGetStringAccumulatedTextCount(NSString *string, BOOL includeWords)
{
    if (!string.length)
        return MPAccumulatedTextCountZero();

    __block NSUInteger words = 0;
    NSStringEnumerationOptions options =
        NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired;
    if (includeWords) [string enumerateSubstringsInRange:NSMakeRange(0, string.length)
                               options:options
                            usingBlock:^(__unused NSString *substring,
                                         __unused NSRange substringRange,
                                         __unused NSRange enclosingRange,
                                         __unused BOOL *stop) {
        words++;
    }];

    static NSCharacterSet *newlineSet = nil;
    static NSCharacterSet *whitespaceAndNewlineSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        newlineSet = [NSCharacterSet newlineCharacterSet];
        whitespaceAndNewlineSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    });

    NSUInteger characters = 0;
    NSUInteger charactersWithoutSpaces = 0;
    for (NSUInteger i = 0; i < string.length; i++)
    {
        unichar character = [string characterAtIndex:i];
        if (![newlineSet characterIsMember:character])
            characters++;
        if (![whitespaceAndNewlineSet characterIsMember:character])
            charactersWithoutSpaces++;
    }

    return MPAccumulatedTextCountMake(words, characters,
                                      charactersWithoutSpaces);
}

// Inline elements do not create word boundaries. Accumulate their visible
// text before asking Foundation to segment words; block boundaries do.
NS_INLINE void MPFlushInlineWords(NSMutableString *text, MPAccumulatedTextCount *count)
{
    if (!text.length) return;
    count->words += MPGetStringAccumulatedTextCount(text, YES).words;
    [text setString:@""];
}

NS_INLINE BOOL MPIsTextBlockBoundary(NSString *tagName)
{
    static NSSet<NSString *> *blocks;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blocks = [NSSet setWithArray:@[@"ADDRESS", @"ARTICLE", @"ASIDE", @"BLOCKQUOTE",
            @"BR", @"CAPTION", @"DD", @"DETAILS", @"DIV", @"DL", @"DT", @"FIELDSET",
            @"FIGCAPTION", @"FIGURE", @"FOOTER", @"FORM", @"H1", @"H2", @"H3",
            @"H4", @"H5", @"H6", @"HEADER", @"HGROUP", @"HR", @"LI", @"MAIN",
            @"NAV", @"OL", @"P", @"PRE", @"SECTION", @"SUMMARY", @"TABLE", @"TBODY",
            @"TD", @"TFOOT", @"TH", @"THEAD", @"TR", @"UL"]];
    });
    return tagName && [blocks containsObject:tagName];
}

NS_INLINE void MPAccumulateNodeText(DOMNode *node, NSMutableString *inlineText,
                                   MPAccumulatedTextCount *count)
{
    switch (node.nodeType)
    {
        case 1:
        case 9:
        case 11:
        {
            NSString *tagName = nil;
            if ([node respondsToSelector:@selector(tagName)])
            {
                DOMElement *element = (DOMElement *)node;
                NSString *controlToken = [element getAttribute:@"data-mp-preview-ui"];
                if (controlToken.length) {
                    DOMNodeList *metadata = [node.ownerDocument getElementsByTagName:@"meta"];
                    for (NSUInteger i = 0; i < metadata.length; i++) {
                        DOMElement *meta = (DOMElement *)[metadata item:(unsigned)i];
                        if ([meta.parentElement.tagName isEqualToString:@"HEAD"] &&
                            [[meta getAttribute:@"name"] isEqualToString:@"macdown-checkbox-token"] &&
                            [[meta getAttribute:@"content"] isEqualToString:controlToken])
                            return;
                    }
                }
                tagName = element.tagName.uppercaseString;
                if ([tagName isEqualToString:@"SCRIPT"] || [tagName isEqualToString:@"STYLE"] ||
                    [tagName isEqualToString:@"HEAD"])
                    return;
                if ([tagName isEqualToString:@"CODE"])
                {
                    if ([node.parentElement.tagName isEqualToString:@"PRE"]) return;
                    MPFlushInlineWords(inlineText, count);
                    // Preserve the established contract: an inline code span
                    // with words counts as one, regardless of its text length.
                    MPAccumulatedTextCount code = MPAccumulatedTextCountZero();
                    NSMutableString *codeText = [NSMutableString string];
                    for (DOMNode *child = node.firstChild; child; child = child.nextSibling)
                        MPAccumulateNodeText(child, codeText, &code);
                    MPFlushInlineWords(codeText, &code);
                    count->words += code.words ? 1 : 0;
                    count->characters += code.characters;
                    count->charactersWithoutSpaces += code.charactersWithoutSpaces;
                    return;
                }
            }
            BOOL boundary = MPIsTextBlockBoundary(tagName);
            if (boundary) MPFlushInlineWords(inlineText, count);
            for (DOMNode *child = node.firstChild; child; child = child.nextSibling)
                MPAccumulateNodeText(child, inlineText, count);
            if (boundary) MPFlushInlineWords(inlineText, count);
            return;
        }
        case 3:
        case 4:
        {
            MPAccumulatedTextCount text = MPGetStringAccumulatedTextCount(node.nodeValue, NO);
            count->characters += text.characters;
            count->charactersWithoutSpaces += text.charactersWithoutSpaces;
            if (node.nodeValue.length) [inlineText appendString:node.nodeValue];
            return;
        }
        default:
            return;
    }
}

NS_INLINE MPAccumulatedTextCount MPGetNodeAccumulatedTextCount(DOMNode *node)
{
    MPAccumulatedTextCount count = MPAccumulatedTextCountZero();
    NSMutableString *inlineText = [NSMutableString string];
    MPAccumulateNodeText(node, inlineText, &count);
    MPFlushInlineWords(inlineText, &count);
    return count;
}


// Issue #452: Public wrapper so the editor can count its selected text using
// the exact same per-string algorithm as the document-wide word count.
DOMNodeTextCount MPTextCountForString(NSString *string)
{
    MPAccumulatedTextCount accumulatedCount =
        MPGetStringAccumulatedTextCount(string, YES);
    DOMNodeTextCount count;
    count.words = accumulatedCount.words;
    count.characters = accumulatedCount.characters;
    count.characterWithoutSpaces = accumulatedCount.charactersWithoutSpaces;
    return count;
}


@implementation DOMNode (Text)

- (DOMNodeTextCount)textCount
{
    MPAccumulatedTextCount accumulatedCount = MPGetNodeAccumulatedTextCount(self);
    DOMNodeTextCount count;
    count.words = accumulatedCount.words;
    count.characters = accumulatedCount.characters;
    count.characterWithoutSpaces = accumulatedCount.charactersWithoutSpaces;
    return count;
}

@end
