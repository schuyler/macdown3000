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

NS_INLINE MPAccumulatedTextCount MPAccumulatedTextCountAdd(
    MPAccumulatedTextCount lhs, MPAccumulatedTextCount rhs)
{
    return MPAccumulatedTextCountMake(lhs.words + rhs.words,
                                      lhs.characters + rhs.characters,
                                      lhs.charactersWithoutSpaces + rhs.charactersWithoutSpaces);
}

NS_INLINE MPAccumulatedTextCount MPGetStringAccumulatedTextCount(NSString *string)
{
    if (!string.length)
        return MPAccumulatedTextCountZero();

    __block NSUInteger words = 0;
    NSStringEnumerationOptions options =
        NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired;
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length)
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

NS_INLINE MPAccumulatedTextCount MPGetChildrenAccumulatedTextCount(DOMNode *node)
{
    MPAccumulatedTextCount count = MPAccumulatedTextCountZero();
    for (DOMNode *c = node.firstChild; c; c = c.nextSibling)
        count = MPAccumulatedTextCountAdd(count, MPGetNodeAccumulatedTextCount(c));
    return count;
}

NS_INLINE MPAccumulatedTextCount MPGetNodeAccumulatedTextCount(DOMNode *node)
{
    switch (node.nodeType)
    {
        case 1:
        case 9:
        case 11:
            if ([node respondsToSelector:@selector(tagName)])
            {
                NSString *tagName = [(id)node tagName].uppercaseString;
                if ([tagName isEqualToString:@"SCRIPT"]
                        || [tagName isEqualToString:@"STYLE"]
                        || [tagName isEqualToString:@"HEAD"])
                    return MPAccumulatedTextCountZero();
                if ([tagName isEqualToString:@"CODE"])
                {
                    if ([node.parentElement.tagName isEqualToString:@"PRE"])
                        return MPAccumulatedTextCountZero();
                    MPAccumulatedTextCount childCount =
                        MPGetChildrenAccumulatedTextCount(node);
                    childCount.words = childCount.words ? 1 : 0;
                    return childCount;
                }
            }
            return MPGetChildrenAccumulatedTextCount(node);
        case 3:
        case 4:
            return MPGetStringAccumulatedTextCount(node.nodeValue);
        default:
            break;
    }
    return MPAccumulatedTextCountZero();
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
