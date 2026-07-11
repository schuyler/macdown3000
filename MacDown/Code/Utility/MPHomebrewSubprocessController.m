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
@property (readwrite) void(^completionHandler)(NSString *);

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
    self.completionHandler = handler;

    NSString *brewPath = [self resolvedBrewPath];
    if (!brewPath)     // Homebrew not installed.
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completionHandler)
                self.completionHandler(nil);
        });
        return;
    }
    self.task.executableURL = [NSURL fileURLWithPath:brewPath];

    // -readToEndOfFileInBackgroundAndNotify + NSNotificationCenter (the
    // previous implementation) is a pre-GCD API whose background read and
    // notification delivery run at a QoS the app doesn't control. Xcode's
    // Thread Performance Checker flagged a priority-inversion "Hang Risk"
    // where the main thread (user-interactive, switching Preferences
    // panes) ended up waiting on a lock also touched by this machinery.
    // NSTask.terminationHandler runs on a GCD-managed queue we don't have
    // to fight with, and we explicitly hop back to the main queue
    // ourselves before touching the completion handler (callers update
    // KVO-observed/bound UI properties from it).
    NSFileHandle *stdoutReadHandle =
        ((NSPipe *)self.task.standardOutput).fileHandleForReading;

    // self.task.terminationHandler = ^{ ...self... } is a genuine
    // structural retain cycle (self -> _task -> terminationHandler ->
    // block -> self), which the compiler correctly flags. It's
    // deliberate: MPDetectHomebrewPrefixWithCompletionhandler() below
    // only holds this controller in a local variable, so capturing self
    // strongly is what keeps it alive long enough to report back once the
    // task exits. The cycle is broken explicitly as the first thing the
    // block does, so it never outlives a single invocation.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
    self.task.terminationHandler = ^(NSTask *task) {
        task.terminationHandler = nil;   // Break the cycle immediately.
        // Safe to read to EOF here (not a deadlock risk): this handler
        // only fires after the task has already exited, so the pipe is
        // closed and the read returns promptly.
        NSData *outData = [stdoutReadHandle readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:outData
                                                   encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completionHandler)
                self.completionHandler(output);
        });
    };
#pragma clang diagnostic pop

    NSError *launchError = nil;
    if (![self.task launchAndReturnError:&launchError])
    {
        self.task.terminationHandler = nil;   // Block will never fire; break the cycle.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completionHandler)
                self.completionHandler(nil);
        });
        return;
    }
}

@end


void MPDetectHomebrewPrefixWithCompletionhandler(void(^handler)(NSString *))
{
    NSArray *args = @[@"--prefix"];
    MPHomebrewSubprocessController *c =
        [[MPHomebrewSubprocessController alloc] initWithArguments:args];
    [c runWithCompletionHandler:handler];
}

