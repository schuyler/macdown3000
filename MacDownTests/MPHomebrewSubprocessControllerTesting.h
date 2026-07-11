//
//  MPHomebrewSubprocessControllerTesting.h
//  MacDownTests
//
//  Test seam re-exposing MPHomebrewSubprocessController's private members
//  (already declared in a class extension in the .m) so test code can see
//  them. No production behavior change.
//

#import "MPHomebrewSubprocessController.h"

@interface MPHomebrewSubprocessController (Testing)

@property (readonly) NSTask *task;
@property (readwrite) void(^completionHandler)(NSString *);

- (NSString *)resolvedBrewPath;   // overridable

@end
