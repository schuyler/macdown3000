//
//  MPHTMLResourceURLs.h
//  MacDown 3000
//
//  Utility functions for extracting and cache-busting local resource
//  URLs in rendered HTML.
//  Related to GitHub issue #110.
//

#import <Foundation/Foundation.h>

/// Extract resolved absolute file paths of local resources referenced in HTML.
/// Finds src= on <img>, <video>, <audio>, <source>, <iframe> elements
/// and href= on <link> elements. Skips remote URLs (http/https/data).
/// Resolves relative paths against baseURL.
NSSet<NSString *> *MPLocalFilePathsInHTML(NSString *html, NSURL *baseURL);

/// Apply cache-busting query parameters to local resource URLs in HTML.
/// For each entry in timestamps (path -> NSTimeInterval as NSNumber),
/// appends or replaces ?t=<timestamp> on matching URLs.
NSString *MPApplyCacheBusting(NSString *html, NSDictionary<NSString *, NSNumber *> *timestamps, NSURL *baseURL);
