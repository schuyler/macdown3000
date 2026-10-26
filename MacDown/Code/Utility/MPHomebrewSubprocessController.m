//
//  MPHomebrewSubprocessController.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung on 18/2.
//  Copyright © 2017 Tzu-ping Chung . All rights reserved.
//

#import "MPHomebrewSubprocessController.h"


@interface MPHomebrewSubprocessController ()

@property (readonly) NSTask *task;

@end


@implementation MPHomebrewSubprocessController

- (instancetype)initWithArguments:(NSArray *)args
{
    self = [super init];
    if (!self)
        return nil;

    NSPipe *stdoutPipe = [[NSPipe alloc] init];

    _task = [[NSTask alloc] init];
    if (args)
        _task.arguments = args;
    _task.standardOutput = stdoutPipe;

    return self;
}

- (instancetype)init
{
    return [self initWithArguments:nil];
}

// Resolves the path to the `brew` executable by checking the two locations
// Homebrew installs to (Apple Silicon vs. Intel default prefixes). NSTask
// never searches PATH, so a bare "brew" launchPath always fails; we must
// give it a fully-qualified path. Declared as an overridable instance
// method (rather than a bare function) so tests can substitute a stub path.
// NOTE: if the app is ever sandboxed, NSTask subprocess execution would be
// blocked entirely and this detection would stop working regardless of the
// resolved path.
- (NSString *)resolvedBrewPath
{
    NSArray<NSString *> *candidates = @[@"/opt/homebrew/bin/brew",
                                         @"/usr/local/bin/brew"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *candidate in candidates)
    {
        if ([fm isExecutableFileAtPath:candidate])
            return candidate;
    }
    return nil;
}

- (void)runWithCompletionHandler:(void(^)(NSString *))handler
{
    NSString *brewPath = [self resolvedBrewPath];
    if (!brewPath) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handler) handler(nil);
        });
        return;
    }
    NSTask *task = self.task;
    task.executableURL = [NSURL fileURLWithPath:brewPath];
    NSFileHandle *stdoutReadHandle =
        ((NSPipe *)task.standardOutput).fileHandleForReading;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handler) handler(nil);
        });
        return;
    }

    // Drain while the child is running: waiting for termination before reading
    // deadlocks when stdout fills the pipe. This block owns the task and reader,
    // so the controller may be released without losing the result or creating
    // a task -> terminationHandler -> controller retain cycle.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *outData = [stdoutReadHandle readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:outData
                                               encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handler) handler(output);
        });
    });
}

@end


void MPDetectHomebrewPrefixWithCompletionhandler(void(^handler)(NSString *))
{
    NSArray *args = @[@"--prefix"];
    MPHomebrewSubprocessController *c =
        [[MPHomebrewSubprocessController alloc] initWithArguments:args];
    [c runWithCompletionHandler:handler];
}

