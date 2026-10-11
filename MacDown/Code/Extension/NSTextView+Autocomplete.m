//
//  NSTextView+Autocomplete.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 11/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "NSTextView+Autocomplete.h"
#import "NSString+Lookup.h"
#import "MPUtilities.h"


static const unichar kMPLeftSingleQuotation  = L'\u2018';
static const unichar kMPRightSingleQuotation = L'\u2019';
static const unichar kMPLeftDoubleQuotation  = L'\u201c';
static const unichar kMPRightDoubleQuotation = L'\u201d';
static const unichar kMPLeftAngleSingleQuotation  = L'\u2039';
static const unichar kMPRightAngleSingleQuotation = L'\u203a';
static const unichar kMPLeftAngleDoubleQuotation  = L'\u00ab';
static const unichar kMPRightAngleDoubleQuotation = L'\u00bb';
static const unichar kMPLeftAngleSingleBracket  = L'\u3008';
static const unichar kMPRightAngleSingleBracket = L'\u3009';
static const unichar kMPLeftAngleDoubleBracket  = L'\u300a';
static const unichar kMPRightAngleDoubleBracket = L'\u300b';

static const unichar kMPMatchingCharactersMap[][2] = {
    {L'(', L')'},
    {L'[', L']'},
    {L'{', L'}'},
    {L'<', L'>'},
    {L'\'', L'\''},
    {L'\"', L'\"'},
    {L'\uff08', L'\uff09'},     // full-width parentheses
    {L'\u300c', L'\u300d'},     // corner brackets
    {L'\u300e', L'\u300f'},     // white corner brackets
    {kMPLeftSingleQuotation, kMPRightSingleQuotation},
    {kMPLeftDoubleQuotation, kMPRightDoubleQuotation},
    {kMPLeftAngleSingleQuotation, kMPRightAngleSingleQuotation},    // Latin Single Guillemet
    {kMPLeftAngleDoubleQuotation, kMPRightAngleDoubleQuotation},    // Latin Double Guillemet
    {kMPLeftAngleSingleBracket, kMPRightAngleSingleBracket},        // East Asian Single Guillemet
    {kMPLeftAngleDoubleBracket, kMPRightAngleDoubleBracket},        // East Asian Double Guillemet
    {L'\0', L'\0'},
};

static const unichar kMPStrikethroughCharacter = L'~';

static const unichar kMPMarkupCharacters[] = {
    L'*', L'_', L'`', L'=', L'\0',
};

static NSString * const kMPListLineHeadPattern =
    @"^(\\s*)((?:(?:\\*|\\+|-|)\\s+)?)((?:\\d+\\.\\s+)?)(\\S)?";
static NSString * const kMPBlockquoteLinePattern = @"^((?:\\> ?)+).*$";


@implementation NSTextView (Autocomplete)

- (BOOL)substringInRange:(NSRange)range isSurroundedByPrefix:(NSString *)prefix
                  suffix:(NSString *)suffix
{
    NSString *content = self.string;
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    if (content.length < location + length + suffix.length)
        return NO;
    if (location < prefix.length)
        return NO;

    if (![[content substringFromIndex:location + length] hasPrefix:suffix]
        || ![[content substringToIndex:location] hasSuffix:prefix])
        return NO;

    // Emphasis (*) requires special treatment because we need to eliminate
    // strong (**) but not strong-emphasis (***).
    if (![prefix isEqualToString:@"*"] || ![suffix isEqualToString:@"*"])
        return YES;
    if ([self substringInRange:range isSurroundedByPrefix:@"***" suffix:@"***"])
        return YES;
    if ([self substringInRange:range isSurroundedByPrefix:@"**" suffix:@"**"])
        return NO;
    return YES;
}


- (void)insertSpacesForTab
{
    NSString *spaces = @"    ";
    NSUInteger currentLocation = self.selectedRange.location;
    NSInteger p = [self.string locationOfFirstNewlineBefore:currentLocation];

    // Calculate how deep we need to go.
    NSUInteger offset = (currentLocation - p - 1) % 4;
    if (offset)
        spaces = [spaces substringFromIndex:offset];
    // NSMakeRange(NSNotFound, 0) is Apple's documented sentinel for
    // -insertText:replacementRange: meaning "use the current selection, or
    // the marked (IME composition) range if there is one" -- the same
    // behavior the deprecated 1-arg -insertText: had. Every other call in
    // this file already uses the 2-arg form; these were the stragglers.
    [self insertText:spaces replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (BOOL)completeMatchingCharactersForTextInRange:(NSRange)range
                                      withString:(NSString *)str
                            strikethroughEnabled:(BOOL)strikethrough
{
    NSUInteger stringLength = str.length;

    // Character insert without selection.
    if (range.length == 0 && stringLength == 1)
    {
        NSUInteger location = range.location;
        if ([self completeMatchingCharacterForText:str
                                        atLocation:location])
            return YES;
    }
    // Character insert with selection (i.e. select and replace).
    else if (range.length > 0 && stringLength == 1)
    {
        unichar character = [str characterAtIndex:0];
        if ([self wrapMatchingCharactersOfCharacter:character
                                  aroundTextInRange:range
                               strikethroughEnabled:strikethrough])
            return YES;
    }
    return NO;
}

- (BOOL)completeMatchingCharacterForText:(NSString *)string
                              atLocation:(NSUInteger)location
{
    static NSCharacterSet *boundaryCharacters = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *s =
            [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
        [s formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
        boundaryCharacters = [s copy];
    });
    NSString *content = self.string;
    NSUInteger contentLength = content.length;

    BOOL hasMarkedText = self.hasMarkedText;
    unichar c = [string characterAtIndex:0];
    unichar n = ' ';
    unichar p = ' ';
    if (location < contentLength)
        n = [content characterAtIndex:location];
    if (location > 0 && location <= contentLength)
        p = [content characterAtIndex:location - 1];

    // When smart quote substitution is enabled, defer quote handling to macOS.
    // This avoids conflict between our matching-pair behavior and the system's
    // smart quote conversion. See issue #285.
    if (self.isAutomaticQuoteSubstitutionEnabled && (c == L'\"' || c == L'\''))
        return NO;

    for (const unichar *cs = kMPMatchingCharactersMap[0]; *cs != 0; cs += 2)
    {
        // Ignore IM input of ASCII charaters.
        if (hasMarkedText && cs[0] < L'\u0100')
            continue;

        // First part of matching characters.
        if ([boundaryCharacters characterIsMember:n] && c == cs[0]
            && ([boundaryCharacters characterIsMember:p] || cs[0] != cs[1]))
        {
            NSRange range = NSMakeRange(location, 0);
            NSString *completion = [NSString stringWithCharacters:cs length:2];
            // Mimic OS X's quote substitution if it's on.
            if (self.isAutomaticQuoteSubstitutionEnabled)
            {
                unichar c = L'\0';
                switch (cs[0])
                {
                    case L'\"':
                        c = kMPLeftDoubleQuotation;
                        break;
                    case L'\'':
                        c = kMPLeftSingleQuotation;
                        break;
                    default:
                        break;
                }
                if (c != L'\0')
                    completion = [NSString stringWithCharacters:&c length:1];
            }
            [self insertText:completion replacementRange:range];

            range.location += string.length;
            self.selectedRange = range;
            return YES;
        }
        // Second part of matching characters (shift without really inserting).
        else if (c == cs[1] && n == cs[1])
        {
            NSRange range = NSMakeRange(location + 1, 0);
            self.selectedRange = range;
            return YES;
        }
    }
    return NO;
}

- (void)wrapTextInRange:(NSRange)range withPrefix:(unichar)prefix
                 suffix:(unichar)suffix
{
    NSString *string = [self.string substringWithRange:range];
    NSString *p = [NSString stringWithCharacters:&prefix length:1];
    NSString *s = [NSString stringWithCharacters:&suffix length:1];
    NSString *wrapped = [NSString stringWithFormat:@"%@%@%@", p, string, s];
    [self insertText:wrapped replacementRange:range];

    range.location += 1;
    self.selectedRange = range;
}

- (BOOL)wrapMatchingCharactersOfCharacter:(unichar)character
                        aroundTextInRange:(NSRange)range
                     strikethroughEnabled:(BOOL)isStrikethroughEnabled
{
    for (const unichar *cs = kMPMatchingCharactersMap[0]; *cs != 0; cs += 2)
    {
        if (character == cs[0])
        {
            [self wrapTextInRange:range withPrefix:cs[0] suffix:cs[1]];
            return YES;
        }
    }
    for (size_t i = 0; kMPMarkupCharacters[i] != 0; i++)
    {
        if (character == kMPMarkupCharacters[i])
        {
            [self wrapTextInRange:range withPrefix:character suffix:character];
            return YES;
        }
    }
    if (isStrikethroughEnabled && character == kMPStrikethroughCharacter)
    {
        [self wrapTextInRange:range withPrefix:character suffix:character];
        return YES;
    }
    return NO;
}

- (BOOL)deleteMatchingCharactersAround:(NSUInteger)location
{
    NSString *string = self.string;
    if (location == 0 || location >= string.length)
        return NO;

    unichar f = [string characterAtIndex:location - 1];
    unichar b = [string characterAtIndex:location];

    for (const unichar *cs = kMPMatchingCharactersMap[0]; *cs != 0; cs += 2)
    {
        if (f == cs[0] && b == cs[1])
        {
            NSRange range = NSMakeRange(location - 1, 2);
            [self insertText:@"" replacementRange:range];
            return YES;
        }
    }
    return NO;
}

- (BOOL)unindentForSpacesBefore:(NSUInteger)location
{
    NSString *string = self.string;

    NSUInteger whitespaceCount = 0;
    while (location - whitespaceCount > 0
           && [string characterAtIndex:location - whitespaceCount - 1] == L' ')
    {
        whitespaceCount++;
        if (whitespaceCount >= 4)
            break;
    }
    if (whitespaceCount < 2)
        return NO;

    NSUInteger lineStart = [string locationOfFirstNewlineBefore:location] + 1;
    if (location <= lineStart)
        return NO;

    NSUInteger offset = (location - lineStart) % 4;
    if (offset == 0)
        offset = 4;
    if (whitespaceCount < offset)
        offset = whitespaceCount;

    NSRange range = NSMakeRange(location - offset, offset);
    [self insertText:@"" replacementRange:range];
    return YES;
}

- (BOOL)toggleForMarkupPrefix:(NSString *)prefix suffix:(NSString *)suffix
{
    NSRange range = self.selectedRange;
    NSString *selection = [self.string substringWithRange:range];
    BOOL isOn = NO;

    // Selection is already marked-up. Clear markup and maintain selection.
    NSUInteger poff = prefix.length;
    if ([self substringInRange:range isSurroundedByPrefix:prefix
                        suffix:suffix])
    {
        NSRange sub = NSMakeRange(range.location - poff,
                                  selection.length + poff + suffix.length);
        [self insertText:selection replacementRange:sub];
        range.location = sub.location;
        isOn = NO;
    }
    // Selection is normal. Mark it up and maintain selection.
    else
    {
        NSString *text = [NSString stringWithFormat:@"%@%@%@",
                          prefix, selection, suffix];
        [self insertText:text replacementRange:range];
        range.location += poff;
        isOn = YES;
    }
    self.selectedRange = range;
    return isOn;
}

- (void)toggleBlockWithPattern:(NSString *)pattern prefix:(NSString *)prefix
{
    NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:pattern options:0 error:NULL];
    if (!regex || !prefix.length)
        return;
    NSString *content = self.string;
    NSRange selection = self.selectedRange;
    NSRange lineRange = [content lineRangeForRange:selection];
    NSString *toProcess = [content substringWithRange:lineRange];
    BOOL trailingNewline = [toProcess hasSuffix:@"\n"];
    if (trailingNewline)
        toProcess = [toProcess substringToIndex:toProcess.length - 1];
    NSArray<NSString *> *lines = [toProcess componentsSeparatedByString:@"\n"];
    NSMutableArray<NSTextCheckingResult *> *matches = [NSMutableArray array];
    BOOL marked = YES;
    for (NSString *line in lines) {
        NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        BOOL hasMarker = match && match.range.location == 0 && match.range.length > 0;
        marked = marked && hasMarker;
        [matches addObject:hasMarker ? (id)match : (id)NSNull.null];
    }
    NSMutableArray *processedLines = [NSMutableArray array];
    NSUInteger sourceOffset = lineRange.location;
    NSUInteger mappedStart = selection.location;
    NSUInteger mappedEnd = NSMaxRange(selection);
    NSUInteger originalEnd = mappedEnd;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSUInteger removed = marked ? matches[i].range.length : 0;
        NSUInteger added = marked ? 0 : prefix.length;
        [processedLines addObject:marked ? [line substringFromIndex:removed]
                                         : [prefix stringByAppendingString:line]];
        if (selection.location >= sourceOffset)
            mappedStart = mappedStart - MIN(removed, selection.location - sourceOffset) + added;
        if (originalEnd >= sourceOffset)
            mappedEnd = mappedEnd - MIN(removed, originalEnd - sourceOffset) + added;
        sourceOffset += line.length + 1;
    }
    NSString *processed = [processedLines componentsJoinedByString:@"\n"];
    if (trailingNewline)
        processed = [processed stringByAppendingString:@"\n"];
    [self insertText:processed replacementRange:lineRange];
    self.selectedRange = NSMakeRange(mappedStart, mappedEnd - mappedStart);
}

- (void)indentSelectedLinesWithPadding:(NSString *)padding
{
    NSString *content = self.string;
    NSRange selectedRange = self.selectedRange;
    NSRange lineRange = [content lineRangeForRange:selectedRange];

    NSString *toProcess = [content substringWithRange:lineRange];
    NSArray *lines = [toProcess componentsSeparatedByString:@"\n"];
    NSMutableArray *modLines = [NSMutableArray arrayWithCapacity:lines.count];
    NSUInteger paddingLength = padding.length;

    NSUInteger originalStart = selectedRange.location;
    NSUInteger originalEnd = NSMaxRange(selectedRange);
    NSUInteger mappedStart = originalStart;
    NSUInteger mappedEnd = originalEnd;
    NSUInteger offset = lineRange.location;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        // The trailing empty component after a newline is outside this block.
        // Every other line receives padding, including an empty interior line.
        NSUInteger added = (i == lines.count - 1 && !line.length) ? 0 : paddingLength;
        [modLines addObject:added ? [padding stringByAppendingString:line] : line];
        if (originalStart >= offset) mappedStart += added;
        if (originalEnd >= offset) mappedEnd += added;
        offset += line.length + 1;
    }
    NSString *processed = [modLines componentsJoinedByString:@"\n"];
    [self insertText:processed replacementRange:lineRange];

    self.selectedRange = NSMakeRange(mappedStart, mappedEnd - mappedStart);
}

- (void)unindentSelectedLines
{
    NSString *content = self.string;
    NSRange selectedRange = self.selectedRange;
    NSRange lineRange = [content lineRangeForRange:selectedRange];

    // Get the lines to unindent.
    NSString *toProcess = [content substringWithRange:lineRange];
    NSArray *lines = [toProcess componentsSeparatedByString:@"\n"];

    // This will hold the modified lines.
    NSMutableArray *modLines = [NSMutableArray arrayWithCapacity:lines.count];

    // Unindent the lines one by one, and put them in the new array.
    __block NSUInteger firstShift = 0;      // Indentation of the first line.
    __block NSUInteger totalShift = 0;      // Indents removed in total.
    [lines enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop) {
        NSString *line = obj;
        NSUInteger lineLength = line.length;
        NSUInteger shift = 0;

        for (shift = 0; shift < 4; shift++)
        {
            if (shift >= lineLength)
                break;
            unichar c = [line characterAtIndex:shift];
            if (c == '\t')
                shift++;
            if (c != ' ')
                break;
        }
        if (index == 0)
            firstShift += shift;
        totalShift += shift;
        if (shift)
            line = [line substringFromIndex:shift];
        [modLines addObject:line];
    }];

    // Join the processed lines, and replace the original with them.
    NSString *processed = [modLines componentsJoinedByString:@"\n"];
    [self insertText:processed replacementRange:lineRange];

    // Modify the selection range so that the same text (minus removed spaces)
    // are selected.
    NSUInteger originalEnd = NSMaxRange(selectedRange);
    NSUInteger removedBeforeStart = MIN(firstShift, selectedRange.location - lineRange.location);
    NSUInteger removedBeforeEnd = 0;
    NSUInteger originalOffset = lineRange.location;
    for (NSUInteger i = 0; i < lines.count; i++)
    {
        NSString *originalLine = lines[i];
        NSString *modifiedLine = modLines[i];
        NSUInteger removed = originalLine.length - modifiedLine.length;
        if (originalEnd > originalOffset)
            removedBeforeEnd += MIN(removed, originalEnd - originalOffset);
        originalOffset += originalLine.length + 1;
    }
    selectedRange.location -= removedBeforeStart;
    selectedRange.length = originalEnd - removedBeforeEnd - selectedRange.location;
    self.selectedRange = selectedRange;
}

- (BOOL)insertMappedContent
{
    NSString *content = self.string;
    NSUInteger contentLength = content.length;
    if (contentLength > 20)
        return NO;

    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = MPGetDataMap(@"data");
    });
    NSData *mapped = map[content];
    if (!mapped)
        return NO;
    NSString *path = MPWriteDataToUniqueTemporaryFile(mapped, @"image.png", NULL);
    if (!path)
        return NO;
    NSString *text = [NSString stringWithFormat:@"![%@](%@)", content, path];
    [self insertText:text replacementRange:NSMakeRange(0, contentLength)];
    self.selectedRange = NSMakeRange(2, contentLength);
    return YES;
}

- (BOOL)completeNextListItem:(BOOL)autoIncrement
{
    NSRange selectedRange = self.selectedRange;
    NSUInteger location = selectedRange.location;
    NSString *content = self.string;
    if (selectedRange.length || !content.length)
        return NO;

    NSInteger start = [content locationOfFirstNewlineBefore:location] + 1;
    NSUInteger end = location;
    NSUInteger nonwhitespace =
        [content locationOfFirstNonWhitespaceCharacterInLineBefore:location];

    // No non-whitespace character at this line.
    if (nonwhitespace == location)
        return NO;

    NSRange range = NSMakeRange(start, end - start);
    NSString *line = [self.string substringWithRange:range];

    NSRegularExpressionOptions options = NSRegularExpressionAnchorsMatchLines;
    NSRegularExpression *regex =
        [[NSRegularExpression alloc] initWithPattern:kMPListLineHeadPattern
                                             options:options
                                               error:NULL];
    NSTextCheckingResult *result =
        [regex firstMatchInString:line options:0
                            range:NSMakeRange(0, line.length)];
    if (!result || result.range.location == NSNotFound)
        return NO;

    NSString *t = nil;
    BOOL isUl = ([result rangeAtIndex:2].length != 0);
    BOOL isOl = ([result rangeAtIndex:3].length != 0);
    BOOL previousLineEmpty = ([result rangeAtIndex:4].length == 0);
    if (previousLineEmpty)
    {
        NSRange replaceRange = NSMakeRange(NSNotFound, 0);
        if (isUl)
            replaceRange = [result rangeAtIndex:2];
        else if (isOl)
            replaceRange = [result rangeAtIndex:3];
        if (replaceRange.length)
        {
            replaceRange.location += start;
            [self insertText:@"" replacementRange:range];
        }
        t = @"";
    }
    else if (isUl)
    {
        NSRange range = [result rangeAtIndex:2];
        range.length -= 1;      // Exclude trailing whitespace.
        t = [line substringWithRange:range];
    }
    else if (isOl)
    {
        NSRange range = [result rangeAtIndex:3];
        range.length -= 1;      // Exclude trailing space.
        NSString *captured = [line substringWithRange:range];
        NSInteger i = captured.integerValue;
        if (autoIncrement) {
            // integerValue saturates out-of-range markers at NSIntegerMax.
            // Refuse before changing text rather than wrapping to a negative list.
            if (i == NSIntegerMax) return NO;
            i += 1;
        }
        t = [NSString stringWithFormat:@"%ld.", i];
    }
    if (!t)
        return NO;

    [self insertNewline:self];
    location += 1;  // Shift for inserted newline.

    NSString *indent = [line substringWithRange:[result rangeAtIndex:1]];
    NSUInteger contentLength = content.length;

    // Has matching list item. Only insert indent.
    NSRange r = NSMakeRange(location, t.length);
    if (contentLength > location + t.length
            && [[content substringWithRange:r] isEqualToString:t])
    {
        [self insertText:indent replacementRange:NSMakeRange(NSNotFound, 0)];
        return YES;
    }

    NSString *it = [NSString stringWithFormat:@"%@%@", indent, t];

    // Has indent and matching list item. Accept it.
    r = NSMakeRange(location, it.length);
    if (contentLength > location + it.length
            && [[content substringWithRange:r] isEqualToString:it])
        return YES;

    // Insert completion for normal cases.
    if (t.length)
        it = [NSString stringWithFormat:@"%@ ", it];
    [self insertText:it replacementRange:NSMakeRange(NSNotFound, 0)];
    return YES;
}

- (BOOL)completeNextBlockquoteLine
{
    NSRange selectedRange = self.selectedRange;
    NSString *content = self.string;
    NSUInteger contentLength = content.length;
    if (selectedRange.length || !contentLength)
        return NO;

    NSRange lineRange = [content lineRangeForRange:selectedRange];
    NSString *line = [content substringWithRange:lineRange];

    NSRegularExpressionOptions options = NSRegularExpressionAnchorsMatchLines;
    NSRegularExpression *regex =
        [[NSRegularExpression alloc] initWithPattern:kMPBlockquoteLinePattern
                                             options:options error:NULL];
    NSTextCheckingResult *result =
        [regex firstMatchInString:line options:0
                            range:NSMakeRange(0, lineRange.length)];
    if (!result || result.range.location == NSNotFound)
        return NO;

    [self insertNewline:self];

    NSRange markersRange = [result rangeAtIndex:1];
    NSString *markers = [line substringWithRange:markersRange];
    NSUInteger nextLineStart = selectedRange.location + 1;

    // Has identical markers. Accept this.
    NSRange nextMarkersRange = NSMakeRange(nextLineStart, markersRange.length);
    if (contentLength > nextLineStart + markersRange.length)
    {
        NSString *nextMarkers = [content substringWithRange:nextMarkersRange];
        if ([nextMarkers isEqualToString:markers])
            return YES;
    }

    // Insert completion.
    [self insertText:markers replacementRange:NSMakeRange(NSNotFound, 0)];
    return YES;
}

- (BOOL)completeNextIndentedLine
{
    NSRange selectedRange = self.selectedRange;
    if (selectedRange.length)
        return NO;

    NSString *content = self.string;
    NSUInteger start = [content lineRangeForRange:selectedRange].location;
    NSUInteger end = [content locationOfFirstNonWhitespaceCharacterInLineBefore:
                      selectedRange.location];
    if (end <= start)
        return NO;

    [self insertNewline:self];
    NSRange indentRange = NSMakeRange(start, end - start);
    [self insertText:[content substringWithRange:indentRange]
     replacementRange:NSMakeRange(NSNotFound, 0)];
    return YES;
}

- (void)makeHeaderForSelectedLinesWithLevel:(NSUInteger)level
                            renderMarkdown:(NSString *(^)(NSString *))renderMarkdown
{
    NSAssert(level <= 6, @"Should be 1-6, or 0 (convert to paragraph).");
    if (level > 6 || !renderMarkdown) return;
    NSString *content = self.string;
    NSRange selection = self.selectedRange;
    if (selection.location > content.length || selection.length > content.length-selection.location) return;
    NSRange selectedLines = [content lineRangeForRange:selection];
    NSMutableArray<NSMutableDictionary *> *lines = [NSMutableArray array];
    NSUInteger offset = 0;
    do {
        NSUInteger end, contentsEnd;
        [content getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset,0)];
        [lines addObject:[@{@"range":[NSValue valueWithRange:NSMakeRange(offset,end-offset)],
            @"text":[content substringWithRange:NSMakeRange(offset,contentsEnd-offset)],
            @"ending":[content substringWithRange:NSMakeRange(contentsEnd,end-contentsEnd)],
            @"selected":@(offset==selectedLines.location || NSIntersectionRange(NSMakeRange(offset,end-offset),selectedLines).length>0),
            @"prefix":@0,@"suffix":@0,@"underline":@NO} mutableCopy]];
        if (end<=offset || end>=content.length) break;
        offset=end;
    } while (YES);
    if (content.length && selectedLines.location==content.length && [lines.lastObject[@"ending"] length])
        [lines addObject:[@{@"range":[NSValue valueWithRange:NSMakeRange(content.length,0)],@"text":@"",@"ending":@"",
            @"selected":@YES,@"prefix":@0,@"suffix":@0,@"underline":@NO} mutableCopy]];
    NSRegularExpression *atx=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}#{1,6} *" options:0 error:NULL];
    NSRegularExpression *setext=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}(?:=+|-+) *$" options:0 error:NULL];
    NSRegularExpression *heading=[NSRegularExpression regularExpressionWithPattern:@"<h([1-6])\\b[^>]*>((?:(?!</h[1-6]>).)*)</h\\1>"
        options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
    // A marker is inserted into the candidate's content, never before its
    // container syntax. The application's real parser proves it is a heading
    // in the complete document (fences/raw HTML/list contexts are preserved).
    NSMutableDictionary<NSNumber *,NSString *> *markers=[NSMutableDictionary dictionary];
    NSMutableString *probe=[content mutableCopy];
    for (NSUInteger i=lines.count;i>0;i--) {
        NSUInteger index=i-1; NSDictionary *line=lines[index]; NSString *text=line[@"text"];
        BOOL selected=[line[@"selected"] boolValue];
        BOOL nextSelected=index+1<lines.count && [lines[index+1][@"selected"] boolValue];
        if(!selected && !nextSelected) continue;
        NSTextCheckingResult *prefix=[atx firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
        BOOL underline=index+1<lines.count && [setext firstMatchInString:lines[index+1][@"text"]
            options:0 range:NSMakeRange(0,[lines[index+1][@"text"] length])]!=nil;
        if((!prefix || !selected) && !underline) continue;
        // An underline is a delimiter, not another title candidate. Marking
        // it would destroy the preceding heading in the batch parser probe.
        if(!prefix && [setext firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]) continue;
        NSString *marker=[@"macdownHeadingProbe" stringByAppendingString:NSUUID.UUID.UUIDString];
        markers[@(index)]=marker;
        NSUInteger insertion=prefix ? prefix.range.length : text.length;
        [probe insertString:marker atIndex:[line[@"range"] rangeValue].location+insertion];
    }
    NSString *probeHTML=markers.count ? renderMarkdown(probe) : @"";
    if(markers.count && !probeHTML) return;
    NSArray<NSTextCheckingResult *> *headings=[heading matchesInString:probeHTML?:@"" options:0 range:NSMakeRange(0,probeHTML.length)];
    BOOL (^isHeading)(NSUInteger,BOOL)=^BOOL(NSUInteger index,BOOL requireFirst) {
        NSString *marker=markers[@(index)];
        if(!marker) return NO;
        for (NSTextCheckingResult *match in headings) {
            NSString *body=[probeHTML substringWithRange:[match rangeAtIndex:2]];
            if (requireFirst ? [body hasPrefix:marker] :
                [[body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] hasSuffix:marker]) return YES;
        }
        return NO;
    };
    for (NSUInteger i=0;i<lines.count;i++) {
        NSMutableDictionary *line=lines[i]; NSString *text=line[@"text"];
        if(!markers[@(i)]) continue;
        NSTextCheckingResult *prefix=[atx firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
        if (prefix && isHeading(i,YES)) {
            line[@"heading"]=@YES;
            line[@"prefix"]=@(prefix.range.length);
            NSUInteger end=text.length;
            // This is Hoedown's actual ATX closing rule: hashes at the very
            // end, then preceding spaces. Do not erase literal hashes followed
            // by whitespace, or any hashes from a non-heading prose line.
            while (end>prefix.range.length && [text characterAtIndex:end-1]=='#') end--;
            while (end>prefix.range.length && [text characterAtIndex:end-1]==' ') end--;
            line[@"suffix"]=@(text.length-end);
        } else if (i+1<lines.count && !prefix && text.length &&
                   [setext firstMatchInString:lines[i+1][@"text"] options:0 range:NSMakeRange(0,[lines[i+1][@"text"] length])]) {
            NSString *pair=[NSString stringWithFormat:@"%@%@%@",text,line[@"ending"],lines[i+1][@"text"]];
            NSString *html=renderMarkdown(pair);
            NSTextCheckingResult *match=[heading firstMatchInString:html?:@"" options:0 range:NSMakeRange(0,html.length)];
            // A list/rule/HTML fragment cannot become a heading just because
            // a regex sees an underline. Require a single real heading first.
            if (match && ![[html stringByReplacingCharactersInRange:match.range withString:@""]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length && isHeading(i,NO)) {
                NSMutableDictionary *underline=lines[i+1];
                if ([line[@"selected"] boolValue] || [underline[@"selected"] boolValue]) {
                    line[@"selected"]=@YES; underline[@"selected"]=@YES; underline[@"underline"]=@YES;
                    line[@"heading"]=@YES;
                }
            }
        }
    }
    NSString *newPrefix=level ? [[@"######" substringToIndex:level] stringByAppendingString:@" "] : @"";
    NSUInteger first=NSNotFound,last=0;
    for (NSUInteger i=0;i<lines.count;i++) if ([lines[i][@"selected"] boolValue]) {if(first==NSNotFound) first=i;last=i;}
    if(first==NSNotFound) return;
    NSUInteger replacementStart=[lines[first][@"range"] rangeValue].location;
    NSUInteger replacementEnd=NSMaxRange([lines[last][@"range"] rangeValue]);
    NSMutableString *replacement=[NSMutableString string];
    NSRegularExpression *paragraph=[NSRegularExpression regularExpressionWithPattern:@"^\\s*<p>(?:(?!</p>).)*</p>\\s*$"
        options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
    NSUInteger mappedStart=NSNotFound,mappedEnd=NSNotFound;
    for (NSUInteger i=first;i<=last;i++) {
        NSDictionary *line=lines[i]; NSString *text=line[@"text"],*ending=line[@"ending"];
        NSRange range=[line[@"range"] rangeValue];
        NSUInteger outputStart=replacement.length;
        BOOL remove=[line[@"underline"] boolValue];
        NSUInteger prefix=[line[@"prefix"] unsignedIntegerValue],suffix=[line[@"suffix"] unsignedIntegerValue];
        BOOL blank=![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length];
        NSString *added=(!blank || first==last) && !remove ? newPrefix : @"";
        NSString *lineContent=[text substringWithRange:NSMakeRange(prefix,text.length-prefix-suffix)];
        NSUInteger escapePosition=NSNotFound;
        BOOL extraSeparator=NO;
        if(!level && [line[@"heading"] boolValue] && lineContent.length) {
            NSString *plainHTML=renderMarkdown(lineContent);
            if(!plainHTML) return;
            if(![paragraph firstMatchInString:plainHTML options:0 range:NSMakeRange(0,plainHTML.length)]) {
                NSRegularExpression *literal=[NSRegularExpression regularExpressionWithPattern:@"^ {0,3}(?:[0-9]+(\\.)|([#>*+\\-`~=]))"
                    options:0 error:NULL];
                NSTextCheckingResult *match=[literal firstMatchInString:lineContent options:0 range:NSMakeRange(0,lineContent.length)];
                if(!match) return; // Do not guess a conversion of an unsupported block.
                NSRange punctuation=[match rangeAtIndex:[match rangeAtIndex:1].location!=NSNotFound ? 1 : 2];
                escapePosition=punctuation.location;
                lineContent=[lineContent stringByReplacingCharactersInRange:NSMakeRange(escapePosition,0) withString:@"\\"];
                plainHTML=renderMarkdown(lineContent);
                if(!plainHTML || ![paragraph firstMatchInString:plainHTML options:0 range:NSMakeRange(0,plainHTML.length)]) return;
            }
            // A neighboring rule must stay a rule after removing an ATX
            // prefix. Without the blank separator it would become Setext.
            NSUInteger neighbor=i+1;
            while(neighbor<lines.count && [lines[neighbor][@"underline"] boolValue]) neighbor++;
            extraSeparator=ending.length && neighbor<lines.count &&
                [setext firstMatchInString:lines[neighbor][@"text"] options:0 range:NSMakeRange(0,[lines[neighbor][@"text"] length])]!=nil;
        }
        if(!remove) [replacement appendFormat:@"%@%@%@%@",added,lineContent,ending,extraSeparator?ending:@""];
        NSUInteger boundaries[]={selection.location,NSMaxRange(selection)};
        for(NSUInteger b=0;b<2;b++) if(boundaries[b]>=range.location && boundaries[b]<=NSMaxRange(range)) {
            NSUInteger relative=boundaries[b]-range.location,mapped=0;
            if(!remove) {
                NSUInteger retainedEnd=text.length-suffix;
                NSUInteger retained=MIN(relative,retainedEnd);
                mapped=added.length+(retained>prefix?retained-prefix:0);
                if(escapePosition!=NSNotFound && retained>=prefix+escapePosition) mapped++;
                if(relative>text.length) mapped+=relative-text.length;
            }
            NSUInteger absolute=replacementStart+outputStart+mapped;
            if(b==0) mappedStart=absolute;else mappedEnd=absolute;
        }
    }
    NSRange replacementRange=NSMakeRange(replacementStart,replacementEnd-replacementStart);
    if([replacement isEqualToString:[content substringWithRange:replacementRange]]) return;
    [self insertText:replacement replacementRange:replacementRange];
    if(mappedStart!=NSNotFound && mappedEnd!=NSNotFound && mappedEnd>=mappedStart)
        self.selectedRange=NSMakeRange(mappedStart,mappedEnd-mappedStart);
}

@end
