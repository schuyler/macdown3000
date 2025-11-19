//
//  MPMarkdownPreprocessor.h
//  MacDown
//
//  Preprocesses markdown text to fix parsing issues before passing to hoedown.
//  See GitHub issue #34: Lists after colons render as single line
//

#import <Foundation/Foundation.h>

@interface MPMarkdownPreprocessor : NSObject

/**
 * Preprocesses markdown text to ensure lists can interrupt paragraphs.
 *
 * Hoedown 3.0.7 does not allow lists to interrupt paragraphs (not CommonMark compliant).
 * This method inserts blank lines before list markers when they follow non-blank lines,
 * ensuring proper list rendering.
 *
 * @param markdown The original markdown text
 * @return Preprocessed markdown text with blank lines inserted where needed
 */
+ (NSString *)preprocessForListInterruption:(NSString *)markdown;

@end
