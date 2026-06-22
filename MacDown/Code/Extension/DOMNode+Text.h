//
//  DOMNode+Text.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung on 18/1.
//  Copyright (c) 2015 Tzu-ping Chung . All rights reserved.
//

#import <WebKit/WebKit.h>

struct DOMNodeTextCount
{
    NSUInteger words;
    NSUInteger characters;
    NSUInteger characterWithoutSpaces;
};

typedef struct DOMNodeTextCount DOMNodeTextCount;


/**
 * Issue #452: Count words, characters, and characters-without-spaces for an
 * arbitrary string, using the same algorithm the document-wide word count
 * applies to DOM text nodes. Used to count the editor's selected text.
 */
FOUNDATION_EXPORT DOMNodeTextCount MPTextCountForString(NSString *string);


@interface DOMNode (Text)

@property (readonly, nonatomic) DOMNodeTextCount textCount;

@end
