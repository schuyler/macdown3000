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
// Group 1: the element name, Group 2: the URL value
static NSString * const kResourcePattern =
    @"<(img|video|audio|source|iframe)\\b[^>]*\\bsrc=[\"']([^\"']+)[\"']"
    @"|<(link)\\b[^>]*\\bhref=[\"']([^\"']+)[\"']";

static BOOL MPIsRemoteURL(NSString *url)
{
    return [url hasPrefix:@"http://"]
        || [url hasPrefix:@"https://"]
        || [url hasPrefix:@"data:"]
        || [url hasPrefix:@"#"];
}

static NSString *MPResolveLocalPath(NSString *url, NSURL *baseURL)
{
    // Handle file:// protocol
    if ([url hasPrefix:@"file://"])
    {
        NSURL *fileURL = [NSURL URLWithString:url];
        return fileURL.path;
    }

    // Absolute path
    if ([url hasPrefix:@"/"])
        return url;

    // Relative path — resolve against base directory.
    // If baseURL is already a directory (e.g., unsaved document default),
    // use it directly; otherwise strip the filename component.
    NSURL *baseDir = baseURL.hasDirectoryPath
        ? baseURL
        : [baseURL URLByDeletingLastPathComponent];
    NSURL *resolved = [NSURL URLWithString:
        [url stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLPathAllowedCharacterSet]]
                             relativeToURL:baseDir];
    return resolved.path.stringByStandardizingPath;
}

NSSet<NSString *> *MPLocalFilePathsInHTML(NSString *html, NSURL *baseURL)
{
    if (!html.length || !baseURL)
        return [NSSet set];

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:kResourcePattern
                             options:NSRegularExpressionCaseInsensitive
                               error:&error];
    if (error)
        return [NSSet set];

    NSMutableSet *paths = [NSMutableSet set];
    NSArray *matches = [regex matchesInString:html options:0
                                       range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in matches)
    {
        // Group 2 is src= URL, Group 4 is href= URL
        NSString *url = nil;
        if ([match rangeAtIndex:2].location != NSNotFound)
            url = [html substringWithRange:[match rangeAtIndex:2]];
        else if ([match rangeAtIndex:4].location != NSNotFound)
            url = [html substringWithRange:[match rangeAtIndex:4]];

        if (!url || MPIsRemoteURL(url))
            continue;

        // Strip any existing query string for path resolution
        NSRange queryRange = [url rangeOfString:@"?"];
        NSString *cleanUrl = (queryRange.location != NSNotFound)
            ? [url substringToIndex:queryRange.location]
            : url;

        NSString *path = MPResolveLocalPath(cleanUrl, baseURL);
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
                             options:NSRegularExpressionCaseInsensitive
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
        if ([match rangeAtIndex:2].location != NSNotFound)
            urlRange = [match rangeAtIndex:2];
        else if ([match rangeAtIndex:4].location != NSNotFound)
            urlRange = [match rangeAtIndex:4];
        else
            continue;

        NSString *url = [html substringWithRange:urlRange];
        if (MPIsRemoteURL(url))
            continue;

        // Strip existing ?t= for clean path resolution
        NSRange queryRange = [url rangeOfString:@"?"];
        NSString *cleanUrl = (queryRange.location != NSNotFound)
            ? [url substringToIndex:queryRange.location]
            : url;

        NSString *path = MPResolveLocalPath(cleanUrl, baseURL);
        if (!path)
            continue;

        NSNumber *timestamp = timestamps[path];
        if (!timestamp)
            continue;

        NSString *busted = [NSString stringWithFormat:@"%@?t=%ld",
                            cleanUrl, (long)timestamp.doubleValue];
        [result replaceCharactersInRange:urlRange withString:busted];
    }

    return [result copy];
}
