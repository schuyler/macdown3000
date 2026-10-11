//
//  MPHTMLResourceURLs.m
//  MacDown 3000
//
//  Utility functions for extracting and cache-busting local resource
//  URLs in rendered HTML.
//  Related to GitHub issue #110.
//

#import "MPHTMLResourceURLs.h"

// Matches src="..." or src='...' on resource elements (img, video, audio, source, iframe)
// and href="..." or href='...' on <link> elements.
// Capture the delimiter separately: an apostrophe is valid in a double-quoted
// URL (and vice versa). URL values are groups 3 (src) and 6 (href).
static NSString * const kResourcePattern =
    @"<(img|video|audio|source|iframe)\\b[^>]*\\ssrc\\s*=\\s*([\"'])(.*?)\\2"
    @"|<(link)\\b[^>]*\\shref\\s*=\\s*([\"'])(.*?)\\5";

static NSString *MPDecodeHTMLURL(NSString *url)
{
    return [[[[url stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""]
        stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"]
        stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"]
        stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

static NSString *MPResolveLocalPath(NSString *url, NSURL *baseURL)
{
    url = MPDecodeHTMLURL(url);
    if (!url.length || [url hasPrefix:@"#"] || [url hasPrefix:@"//"] || !baseURL.isFileURL)
        return nil;
    NSURL *baseDir = baseURL.hasDirectoryPath ? baseURL : baseURL.URLByDeletingLastPathComponent;
    NSURL *resolved = [NSURL URLWithString:url relativeToURL:baseDir];
    if (!resolved) {
        NSMutableCharacterSet *allowed = [[NSCharacterSet URLFragmentAllowedCharacterSet] mutableCopy];
        [allowed addCharactersInString:@"%?#"];
        resolved = [NSURL URLWithString:[url stringByAddingPercentEncodingWithAllowedCharacters:allowed]
                         relativeToURL:baseDir];
    }
    return resolved.isFileURL ? resolved.path.stringByStandardizingPath : nil;
}

NSSet<NSString *> *MPLocalFilePathsInHTML(NSString *html, NSURL *baseURL)
{
    if (!html.length || !baseURL)
        return [NSSet set];

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:kResourcePattern
                             options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                               error:&error];
    if (error)
        return [NSSet set];

    NSMutableSet *paths = [NSMutableSet set];
    NSArray *matches = [regex matchesInString:html options:0
                                       range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in matches)
    {
        // Group 3 is src= URL, Group 6 is href= URL.
        NSString *url = nil;
        if ([match rangeAtIndex:3].location != NSNotFound)
            url = [html substringWithRange:[match rangeAtIndex:3]];
        else if ([match rangeAtIndex:6].location != NSNotFound)
            url = [html substringWithRange:[match rangeAtIndex:6]];

        if (!url)
            continue;

        NSString *path = MPResolveLocalPath(url, baseURL);
        if (path)
            [paths addObject:path];
    }

    return [paths copy];
}

NSString *MPApplyCacheBusting(NSString *html, NSDictionary<NSString *, NSNumber *> *timestamps, NSURL *baseURL)
{
    if (!html.length || !timestamps.count || !baseURL)
        return html;

    // Build a reverse map: relative URL (as it appears in HTML) -> timestamp
    // We need to match the URLs as they appear in the HTML, not the resolved paths
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:kResourcePattern
                             options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                               error:&error];
    if (error)
        return html;

    NSMutableString *result = [html mutableCopy];
    NSArray *matches = [regex matchesInString:html options:0
                                       range:NSMakeRange(0, html.length)];

    // Process matches in reverse to preserve offsets
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator])
    {
        NSRange urlRange;
        if ([match rangeAtIndex:3].location != NSNotFound)
            urlRange = [match rangeAtIndex:3];
        else if ([match rangeAtIndex:6].location != NSNotFound)
            urlRange = [match rangeAtIndex:6];
        else
            continue;

        NSString *url = [html substringWithRange:urlRange];

        NSString *path = MPResolveLocalPath(url, baseURL);
        if (!path)
            continue;

        NSNumber *timestamp = timestamps[path];
        if (!timestamp)
            continue;

        NSURLComponents *components = [NSURLComponents componentsWithString:MPDecodeHTMLURL(url)];
        if (!components)
            continue;
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        for (NSURLQueryItem *item in components.queryItems)
            if (![item.name isEqualToString:@"t"])
                [items addObject:item];
        [items addObject:[NSURLQueryItem queryItemWithName:@"t"
            value:[NSString stringWithFormat:@"%ld", (long)timestamp.doubleValue]]];
        components.queryItems = items;
        // NSURLComponents preserves apostrophes in URLs. Escape for the HTML
        // attribute as well as for the URL, regardless of its quote delimiter.
        NSString *busted = [components.string stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
        busted = [busted stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
        busted = [busted stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
        busted = [busted stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
        busted = [busted stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
        [result replaceCharactersInRange:urlRange withString:busted];
    }

    return [result copy];
}
