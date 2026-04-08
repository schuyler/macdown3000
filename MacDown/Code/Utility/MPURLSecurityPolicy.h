//
//  MPURLSecurityPolicy.h
//  MacDown 3000
//
//  Security policy utility for URL validation.
//  Addresses CVE-2019-12138 (directory traversal) and CVE-2019-12173 (RCE via app bundles).
//

#import <Foundation/Foundation.h>

@interface MPURLSecurityPolicy : NSObject

/// Returns YES if the URL resolves to an executable, application bundle,
/// or other potentially dangerous file type.
+ (BOOL)isExecutableOrAppBundleAtURL:(NSURL *)url;

/// Returns YES if targetURL is within the directory tree rooted at baseURL's
/// parent directory. Both URLs are resolved (symlinks, ..) before comparison.
+ (BOOL)url:(NSURL *)targetURL isWithinScopeOfBaseURL:(NSURL *)baseURL;

@end
