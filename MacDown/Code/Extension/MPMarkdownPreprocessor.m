//
//  MPMarkdownPreprocessor.m
//  MacDown
//
//  Preprocesses markdown text to fix parsing issues before passing to hoedown.
//  See GitHub issue #34: Lists after colons render as single line
//

#import "MPMarkdownPreprocessor.h"

@implementation MPMarkdownPreprocessor

+ (NSString *)preprocessForListInterruption:(NSString *)markdown
{
    if (markdown.length == 0) {
        return markdown;
    }

    // Detect line ending style to preserve it
    NSString *lineEnding = @"\n";
    if ([markdown rangeOfString:@"\r\n"].location != NSNotFound) {
        lineEnding = @"\r\n";
    }

    // Split into lines while preserving the line ending style
    NSArray<NSString *> *lines = [self splitLines:markdown lineEnding:lineEnding];
    NSMutableArray<NSString *> *processedLines = [NSMutableArray arrayWithCapacity:lines.count];

    BOOL inFencedCodeBlock = NO;
    BOOL inBlockquote = NO;
    BOOL previousLineWasBlank = YES;  // Start as true (beginning of document)
    BOOL previousLineWasIndentedCode = NO;

    for (NSInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // Check for fenced code block markers
        if ([self isFencedCodeBlockMarker:trimmedLine]) {
            inFencedCodeBlock = !inFencedCodeBlock;
            [processedLines addObject:line];
            previousLineWasBlank = NO;
            previousLineWasIndentedCode = NO;
            continue;
        }

        // Skip processing if inside fenced code block
        if (inFencedCodeBlock) {
            [processedLines addObject:line];
            previousLineWasBlank = NO;
            previousLineWasIndentedCode = NO;
            continue;
        }

        // Check if current line is a blockquote
        inBlockquote = [self isBlockquoteLine:line];

        // Skip processing if inside blockquote (lists in blockquotes have different rules)
        if (inBlockquote) {
            [processedLines addObject:line];
            previousLineWasBlank = NO;
            previousLineWasIndentedCode = NO;
            continue;
        }

        // Check if current line is blank
        BOOL currentLineIsBlank = (trimmedLine.length == 0);

        // Check if current line is indented code (4+ spaces)
        BOOL currentLineIsIndentedCode = [self isIndentedCodeBlock:line];

        // Skip processing if this is indented code following indented code
        if (currentLineIsIndentedCode && previousLineWasIndentedCode) {
            [processedLines addObject:line];
            previousLineWasBlank = currentLineIsBlank;
            previousLineWasIndentedCode = currentLineIsIndentedCode;
            continue;
        }

        // Check if current line starts with a list marker
        BOOL currentLineIsListMarker = [self isListMarker:line];

        // If this line is a list marker and previous line was not blank, insert blank line
        BOOL insertedBlankLine = NO;
        if (currentLineIsListMarker && !previousLineWasBlank && !previousLineWasIndentedCode) {
            [processedLines addObject:@""];  // Insert blank line
            insertedBlankLine = YES;
        }

        [processedLines addObject:line];

        // Update state for next iteration
        // If we inserted a blank line, the previous line for the next iteration is blank
        previousLineWasBlank = insertedBlankLine || currentLineIsBlank;
        previousLineWasIndentedCode = currentLineIsIndentedCode;
    }

    // Rejoin lines with the original line ending style
    return [processedLines componentsJoinedByString:lineEnding];
}

#pragma mark - Helper Methods

+ (NSArray<NSString *> *)splitLines:(NSString *)text lineEnding:(NSString *)lineEnding
{
    NSArray<NSString *> *lines = [text componentsSeparatedByString:lineEnding];

    // If the text ends with a line ending, componentsSeparatedByString will add an empty string at the end
    // We need to remove it to preserve the original structure
    if (lines.count > 0 && [lines.lastObject length] == 0 && [text hasSuffix:lineEnding]) {
        lines = [lines subarrayWithRange:NSMakeRange(0, lines.count - 1)];
    }

    return lines;
}

+ (BOOL)isFencedCodeBlockMarker:(NSString *)line
{
    // Check for ``` or ~~~ (with optional trailing content like ```python)
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"];
}

+ (BOOL)isBlockquoteLine:(NSString *)line
{
    // Line starts with optional spaces followed by >
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [trimmed hasPrefix:@">"];
}

+ (BOOL)isIndentedCodeBlock:(NSString *)line
{
    // Indented code blocks start with 4 spaces or 1 tab
    if (line.length == 0) {
        return NO;
    }

    // Check if line starts with a tab
    if ([line characterAtIndex:0] == '\t') {
        return YES;
    }

    // Check if line starts with 4 spaces
    if (line.length >= 4) {
        NSString *prefix = [line substringToIndex:4];
        if ([prefix isEqualToString:@"    "]) {
            return YES;
        }
    }

    return NO;
}

+ (BOOL)isListMarker:(NSString *)line
{
    // Trim leading whitespace to handle indented lists
    NSString *trimmedLine = line;
    NSInteger leadingSpaces = 0;
    while (leadingSpaces < trimmedLine.length && [trimmedLine characterAtIndex:leadingSpaces] == ' ') {
        leadingSpaces++;
    }

    // Get the part after leading spaces
    if (leadingSpaces < trimmedLine.length) {
        NSString *contentAfterSpaces = [trimmedLine substringFromIndex:leadingSpaces];

        // Check for unordered list markers: -, *, +
        if (contentAfterSpaces.length >= 2) {
            unichar firstChar = [contentAfterSpaces characterAtIndex:0];
            unichar secondChar = [contentAfterSpaces characterAtIndex:1];

            if ((firstChar == '-' || firstChar == '*' || firstChar == '+') && secondChar == ' ') {
                return YES;
            }
        }

        // Check for ordered list markers: 1., 2., 10., etc.
        // Use static regex to avoid recreating on every call (performance optimization)
        static NSRegularExpression *orderedListRegex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orderedListRegex = [NSRegularExpression
                regularExpressionWithPattern:@"^\\d+\\. "
                options:0
                error:NULL];
        });

        NSRange matchRange = [orderedListRegex rangeOfFirstMatchInString:contentAfterSpaces
            options:0
            range:NSMakeRange(0, contentAfterSpaces.length)];

        if (matchRange.location != NSNotFound) {
            return YES;
        }
    }

    return NO;
}

@end
