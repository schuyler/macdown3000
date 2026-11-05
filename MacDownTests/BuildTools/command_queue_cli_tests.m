// Keep the complete CLI pipeline real; replace only argument parser/OS launch
// boundaries and select a private queue directory for the subprocess fixture.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "MPCommandQueue.h"
#import "MPArgumentProcessor.h"

@implementation MPArgumentProcessor
- (BOOL)printsHelp { return NO; }
- (BOOL)printsVersion { return NO; }
- (NSArray *)arguments {
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    return [arguments subarrayWithRange:NSMakeRange(2, arguments.count - 2)];
}
- (void)printHelp:(BOOL)exitAfter {}
- (void)printVersion:(BOOL)exitAfter {}
@end

@interface MPTestWorkspace : NSObject
+ (instancetype)sharedWorkspace;
- (BOOL)launchAppWithBundleIdentifier:(NSString *)identifier options:(NSWorkspaceLaunchOptions)options
       additionalEventParamDescriptor:(NSAppleEventDescriptor *)descriptor launchIdentifier:(NSNumber **)number;
@end
@implementation MPTestWorkspace
+ (instancetype)sharedWorkspace { return [self new]; }
- (BOOL)launchAppWithBundleIdentifier:(NSString *)identifier options:(NSWorkspaceLaunchOptions)options
       additionalEventParamDescriptor:(NSAppleEventDescriptor *)descriptor launchIdentifier:(NSNumber **)number {
    puts("LAUNCH");
    return YES;
}
@end
static NSURL *MPTestQueueDirectoryForSuite(NSString *suite) {
    return [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[1] isDirectory:YES];
}
#define NSWorkspace MPTestWorkspace
#define MPCommandQueueDirectoryForSuite MPTestQueueDirectoryForSuite
#include "../../../macdown-cmd/main.m"
